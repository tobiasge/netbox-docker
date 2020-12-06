#!/bin/bash
# Runs on every start of the Netbox Docker container

# Stop when an error occures
set -e

# Allows Netbox to be run as non-root users
umask 002

load_configuration() {
  UNIT_SOCKET="/opt/unit/unit.sock"
  UNIT_CONFIG="/etc/unit/nginx-unit.json"
  wait_count=0
  while [ ! -S $UNIT_SOCKET ]; do
    if [ $wait_count -gt 10 ]; then
      echo "$0: No control socket found; configuration will not be loaded."
      return 1
    fi
    echo "$0: Waiting for control socket to be created..."
    wait_count=$[$wait_count + 1]
    sleep 1
  done
  # even when the control socket exists, it does not mean unit has finished initialisation
  # this curl call will get a reply once unit is fully launched
  curl --silent --output /dev/null --request GET --unix-socket $UNIT_SOCKET http://localhost/
  echo "$0: Applying configuration from $UNIT_CONFIG";
  RESP_CODE=$(curl \
                  --silent \
                  --output /dev/null \
                  --write-out '%{http_code}' \
                  --request PUT \
                  --data-binary @$UNIT_CONFIG \
                  --unix-socket $UNIT_SOCKET http://localhost/config \
            )
  if [ "$RESP_CODE" != "200" ]; then
    echo "$0: Could no load Unit configuration"
    kill $(cat /opt/unit/unit.pid)
  else
    echo "$0: Unit configuration loaded successfully"
  fi
}

# Load correct Python3 env
source /opt/netbox/venv/bin/activate

# Try to connect to the DB
DB_WAIT_TIMEOUT=${DB_WAIT_TIMEOUT-3}
MAX_DB_WAIT_TIME=${MAX_DB_WAIT_TIME-30}
CUR_DB_WAIT_TIME=0
while ! ./manage.py migrate 2>&1 && [ "${CUR_DB_WAIT_TIME}" -lt "${MAX_DB_WAIT_TIME}" ]; do
  echo "⏳ Waiting on DB... (${CUR_DB_WAIT_TIME}s / ${MAX_DB_WAIT_TIME}s)"
  sleep "${DB_WAIT_TIMEOUT}"
  CUR_DB_WAIT_TIME=$(( CUR_DB_WAIT_TIME + DB_WAIT_TIMEOUT ))
done
if [ "${CUR_DB_WAIT_TIME}" -ge "${MAX_DB_WAIT_TIME}" ]; then
  echo "❌ Waited ${MAX_DB_WAIT_TIME}s or more for the DB to become ready."
  exit 1
fi

# Create Superuser if required
if [ "$SKIP_SUPERUSER" == "true" ]; then
  echo "↩️ Skip creating the superuser"
else
  if [ -z ${SUPERUSER_NAME+x} ]; then
    SUPERUSER_NAME='admin'
  fi
  if [ -z ${SUPERUSER_EMAIL+x} ]; then
    SUPERUSER_EMAIL='admin@example.com'
  fi
  if [ -f "/run/secrets/superuser_password" ]; then
    SUPERUSER_PASSWORD="$(< /run/secrets/superuser_password)"
  elif [ -z ${SUPERUSER_PASSWORD+x} ]; then
    SUPERUSER_PASSWORD='admin'
  fi
  if [ -f "/run/secrets/superuser_api_token" ]; then
    SUPERUSER_API_TOKEN="$(< /run/secrets/superuser_api_token)"
  elif [ -z ${SUPERUSER_API_TOKEN+x} ]; then
    SUPERUSER_API_TOKEN='0123456789abcdef0123456789abcdef01234567'
  fi

  ./manage.py shell --interface python << END
from django.contrib.auth.models import User
from users.models import Token
if not User.objects.filter(username='${SUPERUSER_NAME}'):
    u=User.objects.create_superuser('${SUPERUSER_NAME}', '${SUPERUSER_EMAIL}', '${SUPERUSER_PASSWORD}')
    Token.objects.create(user=u, key='${SUPERUSER_API_TOKEN}')
END

  echo "💡 Superuser Username: ${SUPERUSER_NAME}, E-Mail: ${SUPERUSER_EMAIL}"
fi

# Run the startup scripts (and initializers)
if [ "$SKIP_STARTUP_SCRIPTS" == "true" ]; then
  echo "↩️ Skipping startup scripts"
else
  echo "import runpy; runpy.run_path('../startup_scripts')" | ./manage.py shell --interface python
fi

echo "✅ Initialisation is done."

load_configuration&

# Launch whatever is passed by docker
# (i.e. the RUN instruction in the Dockerfile)
#
# shellcheck disable=SC2068
exec $@

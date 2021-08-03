ARG FROM
FROM ${FROM} as builder

RUN export DEBIAN_FRONTEND=noninteractive \
    && apt-get update -qq \
    && apt-get install --yes -qq \
      build-essential \
      ca-certificates \
      libldap-dev \
      libsasl2-dev \
      python3-dev \
      python3-pip \
      python3-venv \
    && python3 -m venv /opt/netbox/venv \
    && /opt/netbox/venv/bin/python3 -m pip install --upgrade \
      pip \
      setuptools \
      wheel

ARG NETBOX_PATH
COPY ${NETBOX_PATH}/requirements.txt requirements-container.txt /
RUN /opt/netbox/venv/bin/pip install \
      -r /requirements.txt \
      -r /requirements-container.txt

###
# Main stage
###

ARG FROM
FROM ${FROM} as main

RUN export DEBIAN_FRONTEND=noninteractive \
    CODENAME=$(cat /etc/os-release | grep VERSION_CODENAME | cut -d '=' -f 2) \
    && apt-get update -qq \
    && apt-get upgrade \
      --yes -qq --no-install-recommends \
    && apt-get install \
      --yes -qq --no-install-recommends \
      ca-certificates \
      curl \
      openssl \
      python3 \
      python3-distutils \
    && curl -sL https://nginx.org/keys/nginx_signing.key \
      > /etc/apt/trusted.gpg.d/nginx.asc && \
    echo "deb https://packages.nginx.org/unit/debian/ $CODENAME unit" \
      > /etc/apt/sources.list.d/unit.list \
    && apt-get update -qq \
    && apt-get install \
      --yes -qq --no-install-recommends \
      unit \
      unit-python3.9 \
      tini \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/netbox/venv /opt/netbox/venv

ARG NETBOX_PATH
COPY ${NETBOX_PATH} /opt/netbox

COPY docker/configuration.docker.py /opt/netbox/netbox/netbox/configuration.py
COPY docker/ldap_config.docker.py /opt/netbox/netbox/netbox/ldap_config.py
COPY docker/docker-entrypoint.sh /opt/netbox/docker-entrypoint.sh
COPY docker/launch-netbox.sh /opt/netbox/launch-netbox.sh
COPY docker/housekeeping.sh /opt/netbox/housekeeping.sh
COPY startup_scripts/ /opt/netbox/startup_scripts/
COPY initializers/ /opt/netbox/initializers/
COPY configuration/ /etc/netbox/config/
COPY docker/nginx-unit.json /etc/unit/

WORKDIR /opt/netbox/

# Must set permissions for '/opt/netbox/netbox/media' directory
# to g+w so that pictures can be uploaded to netbox.
RUN mkdir -p /opt/netbox/netbox/static /opt/unit/state/ /opt/unit/tmp/ \
      && chmod -R a+w /opt/netbox/netbox/media /opt/unit/ \
      && /opt/netbox/venv/bin/python -m mkdocs build \
          --config-file /opt/netbox/mkdocs.yml --site-dir /opt/netbox/netbox/project-static/docs/ \
      && SECRET_KEY="dummy" /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py collectstatic --no-input

ENTRYPOINT [ "/usr/bin/tini", "--" ]

CMD [ "/opt/netbox/docker-entrypoint.sh", "/opt/netbox/launch-netbox.sh" ]

LABEL netbox.original-tag="" \
      netbox.git-branch="" \
      netbox.git-ref="" \
      netbox.git-url="" \
# See http://label-schema.org/rc1/#build-time-labels
# Also https://microbadger.com/labels
      org.label-schema.schema-version="1.0" \
      org.label-schema.build-date="" \
      org.label-schema.name="NetBox Docker" \
      org.label-schema.description="A container based distribution of NetBox, the free and open IPAM and DCIM solution." \
      org.label-schema.vendor="The netbox-docker contributors." \
      org.label-schema.url="https://github.com/netbox-community/netbox-docker" \
      org.label-schema.usage="https://github.com/netbox-community/netbox-docker/wiki" \
      org.label-schema.vcs-url="https://github.com/netbox-community/netbox-docker.git" \
      org.label-schema.vcs-ref="" \
      org.label-schema.version="snapshot" \
# See https://github.com/opencontainers/image-spec/blob/master/annotations.md#pre-defined-annotation-keys
      org.opencontainers.image.created="" \
      org.opencontainers.image.title="NetBox Docker" \
      org.opencontainers.image.description="A container based distribution of NetBox, the free and open IPAM and DCIM solution." \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.authors="The netbox-docker contributors." \
      org.opencontainers.image.vendor="The netbox-docker contributors." \
      org.opencontainers.image.url="https://github.com/netbox-community/netbox-docker" \
      org.opencontainers.image.documentation="https://github.com/netbox-community/netbox-docker/wiki" \
      org.opencontainers.image.source="https://github.com/netbox-community/netbox-docker.git" \
      org.opencontainers.image.revision="" \
      org.opencontainers.image.version="snapshot"

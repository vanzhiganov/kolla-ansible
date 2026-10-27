# syntax=docker/dockerfile:1
#
# Kolla-Ansible deployment controller image
#   Base:    Rocky Linux 9
#   Python:  3.11 (Rocky AppStream)
#   Kolla:   2025.1 (Epoxy) == kolla-ansible 20.6.0 + kolla 20.6.0 on PyPI
#   Docker:  docker-ce-cli only; image builds run on the host daemon through
#            a bind-mounted /var/run/docker.sock (docker-out-of-docker)
#
# The openstack.kolla collection is installed from the stable/2025.1 branch
# referenced by the kolla-ansible wheel's requirements.yml.
# See README.md for details and usage.
#
# Build args:
#   ROCKY_VERSION              base image tag               (default: 9)
#   PYTHON_VERSION             python 3.x from AppStream   (default: 3.11)
#   KOLLA_ANSIBLE_VERSION      kolla-ansible PyPI version  (default: 20.6.0)
#   KOLLA_VERSION              kolla (image builder) PyPI version (default: 20.6.0)
#   OPENSTACK_RELEASE          release name, labels only   (default: 2025.1)

ARG ROCKY_VERSION=9

# ---------------------------------------------------------------------------
# Builder: create the virtualenv and install kolla-ansible from PyPI
# ---------------------------------------------------------------------------
FROM rockylinux:${ROCKY_VERSION} AS builder

ARG PYTHON_VERSION=3.11
ARG KOLLA_ANSIBLE_VERSION=20.6.0
ARG KOLLA_VERSION=20.6.0

# python3.11 comes from AppStream. gcc/make and the -devel headers are only
# needed if a dependency has no manylinux wheel for CPython 3.11.
# dbus-devel/glib2-devel/pkgconf: build deps for dbus-python (no wheels).
RUN dnf -y install \
        python${PYTHON_VERSION} \
        python${PYTHON_VERSION}-pip \
        python${PYTHON_VERSION}-devel \
        gcc \
        make \
        dbus-devel \
        glib2-devel \
        pkgconf-pkg-config \
    && dnf -y clean all \
    && rm -rf /var/cache/dnf /var/cache/yum

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PATH=/opt/venv/bin:$PATH

# The Python docker SDK is not declared by the kolla wheel, but kolla-build
# imports it when engine=docker, so it is installed explicitly.
# dbus-python: kolla_container's module_utils (kolla_systemd_worker) imports
# dbus unconditionally on every target; for all-in-one runs interpreter
# discovery picks this venv's python inside the controller, so the binding
# must live here, not only in the system python.
RUN python${PYTHON_VERSION} -m venv /opt/venv \
    && /opt/venv/bin/python -m pip install --upgrade pip setuptools wheel \
    && /opt/venv/bin/python -m pip install \
        "kolla-ansible==${KOLLA_ANSIBLE_VERSION}" \
        "kolla==${KOLLA_VERSION}" \
        "docker>=6.0.0" \
        "dbus-python>=1.3.2"

# ---------------------------------------------------------------------------
# Runtime
# ---------------------------------------------------------------------------
FROM rockylinux:${ROCKY_VERSION}

ARG PYTHON_VERSION=3.11
ARG KOLLA_ANSIBLE_VERSION=20.6.0
ARG KOLLA_VERSION=20.6.0
ARG OPENSTACK_RELEASE=2025.1

LABEL org.opencontainers.image.title="kolla-ansible" \
      org.opencontainers.image.description="OpenStack Kolla-Ansible ${KOLLA_ANSIBLE_VERSION} (${OPENSTACK_RELEASE}) deployment controller - Rocky Linux, Python ${PYTHON_VERSION}" \
      org.opencontainers.image.source="https://opendev.org/openstack/kolla-ansible" \
      org.opencontainers.image.licenses="Apache-2.0"

# openssh-clients: ansible connectivity to target hosts
# rsync: used by parts of the deployment
# findutils/which: trivial command lookups during playbook runs
# git: ansible-galaxy clones the git-sourced openstack.kolla collection
# python3-dbus: kolla module_utils imports dbus; needed when modules run
#               under the system python3 instead of the venv
# dbus-daemon: private system bus for localhost module runs; kolla's
#              module_utils connect to it even when engine=docker (started
#              by the entrypoint, see kolla-systemd1-stub)
RUN dnf -y install \
        python${PYTHON_VERSION} \
        git \
        openssh-clients \
        rsync \
        findutils \
        which \
        python3-dbus \
        dbus-daemon \
    && dnf -y clean all \
    && rm -rf /var/cache/dnf /var/cache/yum

# docker-ce-cli: lets kolla-build (and the operator) drive the host Docker
# daemon through a bind-mounted /var/run/docker.sock - no engine runs inside
# this image. Installed from the Docker CE repo, which is removed afterwards
# to keep the image self-contained.
RUN dnf -y install dnf-plugins-core \
    && dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo \
    && dnf -y install docker-ce-cli \
    && dnf -y clean all \
    && rm -rf /var/cache/dnf /var/cache/yum /etc/yum.repos.d/docker-ce.repo

COPY --from=builder /opt/venv /opt/venv
COPY ansible.cfg /etc/ansible/ansible.cfg

ENV PATH=/opt/venv/bin:$PATH \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    ANSIBLE_COLLECTIONS_PATH=/usr/share/ansible/collections \
    ANSIBLE_ROLES_PATH=/usr/share/ansible/roles

# Install the Galaxy dependencies listed in the packaged requirements.yml
# (openstack.kolla from stable/2025.1).
RUN mkdir -p /usr/share/ansible/collections /usr/share/ansible/roles /etc/kolla \
    && ansible-galaxy collection install -r /opt/venv/share/kolla-ansible/requirements.yml \
        -p /usr/share/ansible/collections \
    && ansible-galaxy collection list

# Private system bus bits: kolla's module_utils talk to D-Bus even when the
# engine is docker (SystemdWorker is constructed unconditionally). The
# entrypoint starts dbus-daemon when no bus is present, and this activation
# stub owns org.freedesktop.systemd1 so the module's lazy proxies can be
# created. Only localhost/all-in-one runs execute modules inside here.
COPY kolla-systemd1-stub /usr/local/libexec/kolla-systemd1-stub
COPY org.freedesktop.systemd1.service /usr/share/dbus-1/system-services/org.freedesktop.systemd1.service
RUN chmod 0755 /usr/local/libexec/kolla-systemd1-stub

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh

VOLUME ["/etc/kolla"]
WORKDIR /etc/kolla

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["bash"]

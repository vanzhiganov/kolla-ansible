# syntax=docker/dockerfile:1
#
# Kolla-Ansible deployment controller image
#   Base:    Rocky Linux 9
#   Python:  3.11 (Rocky AppStream)
#   Kolla:   2025.1 (Epoxy) == kolla-ansible 20.6.0 + kolla 20.6.0 on PyPI
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
RUN dnf -y install \
        python${PYTHON_VERSION} \
        python${PYTHON_VERSION}-pip \
        python${PYTHON_VERSION}-devel \
        gcc \
        make \
    && dnf -y clean all \
    && rm -rf /var/cache/dnf /var/cache/yum

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PATH=/opt/venv/bin:$PATH

RUN python${PYTHON_VERSION} -m venv /opt/venv \
    && /opt/venv/bin/python -m pip install --upgrade pip setuptools wheel \
    && /opt/venv/bin/python -m pip install \
        "kolla-ansible==${KOLLA_ANSIBLE_VERSION}" \
        "kolla==${KOLLA_VERSION}"

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
RUN dnf -y install \
        python${PYTHON_VERSION} \
        git \
        openssh-clients \
        rsync \
        findutils \
        which \
    && dnf -y clean all \
    && rm -rf /var/cache/dnf /var/cache/yum

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

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh

VOLUME ["/etc/kolla"]
WORKDIR /etc/kolla

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["bash"]

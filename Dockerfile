# syntax=docker/dockerfile:1
#
# Kolla-Ansible deployment controller image
#   Base:    Rocky Linux 9
#   Python:  3.11 (Rocky AppStream)
#   Kolla:   2024.2 (Dalmatian) == kolla-ansible 19.8.0 on PyPI
#
# The upstream stable/2024.2 branch was removed when Dalmatian reached EOL,
# so the Ansible collection is pinned to its 2024.2-eol tag.
# See README.md for details and usage.
#
# Build args:
#   ROCKY_VERSION              base image tag               (default: 9)
#   PYTHON_VERSION             python 3.x from AppStream   (default: 3.11)
#   KOLLA_ANSIBLE_VERSION      kolla-ansible PyPI version  (default: 19.8.0)
#   OPENSTACK_RELEASE          release name, labels only   (default: 2024.2)
#   KOLLA_COLLECTION_BRANCH    branch ref in requirements.yml (default: stable/2024.2)
#   KOLLA_COLLECTION_REF       replacement git ref          (default: 2024.2-eol)

ARG ROCKY_VERSION=9

# ---------------------------------------------------------------------------
# Builder: create the virtualenv and install kolla-ansible from PyPI
# ---------------------------------------------------------------------------
FROM rockylinux:${ROCKY_VERSION} AS builder

ARG PYTHON_VERSION=3.11
ARG KOLLA_ANSIBLE_VERSION=19.8.0

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
    && /opt/venv/bin/python -m pip install "kolla-ansible==${KOLLA_ANSIBLE_VERSION}"

# ---------------------------------------------------------------------------
# Runtime
# ---------------------------------------------------------------------------
FROM rockylinux:${ROCKY_VERSION}

ARG PYTHON_VERSION=3.11
ARG KOLLA_ANSIBLE_VERSION=19.8.0
ARG OPENSTACK_RELEASE=2024.2
ARG KOLLA_COLLECTION_BRANCH=stable/2024.2
ARG KOLLA_COLLECTION_REF=2024.2-eol

LABEL org.opencontainers.image.title="kolla-ansible" \
      org.opencontainers.image.description="OpenStack Kolla-Ansible ${KOLLA_ANSIBLE_VERSION} (${OPENSTACK_RELEASE}) deployment controller - Rocky Linux, Python ${PYTHON_VERSION}" \
      org.opencontainers.image.source="https://opendev.org/openstack/kolla-ansible" \
      org.opencontainers.image.licenses="Apache-2.0"

# openssh-clients: ansible connectivity to target hosts
# rsync: used by parts of the deployment
# findutils/which: trivial command lookups during playbook runs
RUN dnf -y install \
        python${PYTHON_VERSION} \
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

# The packaged requirements.yml references the now-deleted stable/2024.2
# branch; repoint it to the EOL tag, then install all Galaxy dependencies.
RUN sed -i "s#${KOLLA_COLLECTION_BRANCH}#${KOLLA_COLLECTION_REF}#" \
        /opt/venv/share/kolla-ansible/requirements.yml \
    && mkdir -p /usr/share/ansible/collections /usr/share/ansible/roles /etc/kolla \
    && ansible-galaxy collection list

# command `kolla-ansible install-deps` will fails be cause the stable/2024.2
# branch was removed, so we skip it and just list the installed collections.
# RUN sed -i "s#${KOLLA_COLLECTION_BRANCH}#${KOLLA_COLLECTION_REF}#" \
#         /opt/venv/share/kolla-ansible/requirements.yml \
#     && mkdir -p /usr/share/ansible/collections /usr/share/ansible/roles /etc/kolla \
#     && kolla-ansible install-deps \
#     && ansible-galaxy collection list


COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh

VOLUME ["/etc/kolla"]
WORKDIR /etc/kolla

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["bash"]

# Kolla-Ansible deployment controller image
#
#   Run `make help` (or just `make`) for the target list and the effective
#   configuration (all values honour VAR=value overrides).
#
# Override any of the variables below, e.g.
#   make build KOLLA_ANSIBLE_VERSION=22.1.0
#   make shell KOLLA_CONFIG_DIR=/srv/kolla

IMAGE                 ?= kolla-ansible
ROCKY_VERSION         ?= 10
PYTHON_VERSION        ?= 3.12
KOLLA_ANSIBLE_VERSION ?= 22.2.0
KOLLA_VERSION         ?= 22.2.0
OPENSTACK_RELEASE     ?= 2026.1
KOLLA_CONFIG_DIR      ?= $(CURDIR)/kolla
DOCKER_SOCK           ?= /var/run/docker.sock

TAG ?= $(OPENSTACK_RELEASE)-rocky-$(ROCKY_VERSION)
REF ?= $(IMAGE):$(TAG)

BUILD_ARGS = \
	--build-arg ROCKY_VERSION=$(ROCKY_VERSION) \
	--build-arg PYTHON_VERSION=$(PYTHON_VERSION) \
	--build-arg KOLLA_ANSIBLE_VERSION=$(KOLLA_ANSIBLE_VERSION) \
	--build-arg KOLLA_VERSION=$(KOLLA_VERSION) \
	--build-arg OPENSTACK_RELEASE=$(OPENSTACK_RELEASE)

# Operator resources mounted by `make shell`, mirroring kolla-ansible.sh:
# the kolla config dir, read-only SSH keys, the SSH agent socket and the
# host Docker socket for kolla-build (each of the latter three only when
# it exists on the host).
SHELL_MOUNTS = -v $(KOLLA_CONFIG_DIR):/etc/kolla
SHELL_MOUNTS += $(if $(wildcard $(HOME)/.ssh),-v $(HOME)/.ssh:/root/.ssh:ro)
SHELL_MOUNTS += $(if $(and $(SSH_AUTH_SOCK),$(wildcard $(SSH_AUTH_SOCK))),\
	-v $(SSH_AUTH_SOCK):/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent)
SHELL_MOUNTS += $(if $(wildcard $(DOCKER_SOCK)),-v $(DOCKER_SOCK):/var/run/docker.sock)

.DEFAULT_GOAL := help
.PHONY: help build rebuild test shell push clean

help:
	@echo "kolla-ansible deployment controller image"
	@echo ""
	@echo "Release:       $(OPENSTACK_RELEASE) | kolla-ansible $(KOLLA_ANSIBLE_VERSION) | kolla $(KOLLA_VERSION) | Rocky $(ROCKY_VERSION) / Python $(PYTHON_VERSION)"
	@echo "Image:         $(REF)"
	@echo "Tag:           $(TAG)"
	@echo "Config:        $(KOLLA_CONFIG_DIR) -> /etc/kolla (make shell)"
	@echo ""
	@echo "Targets:"
	@echo "  help         show this help"
	@echo "  build        build the image"
	@echo "  rebuild      build without cache (--no-cache --pull)"
	@echo "  test         run smoke tests inside the image"
	@echo "  shell        interactive shell with operator resources mounted"
	@echo "  push         push the image to a registry"
	@echo "  clean        remove the local image"
	@echo ""
	@echo "Configuration (override: make <target> VAR=value):"
	@echo "  IMAGE                  = $(IMAGE)"
	@echo "  ROCKY_VERSION          = $(ROCKY_VERSION)"
	@echo "  PYTHON_VERSION         = $(PYTHON_VERSION)"
	@echo "  KOLLA_ANSIBLE_VERSION  = $(KOLLA_ANSIBLE_VERSION)"
	@echo "  KOLLA_VERSION          = $(KOLLA_VERSION)"
	@echo "  OPENSTACK_RELEASE      = $(OPENSTACK_RELEASE)"
	@echo "  KOLLA_CONFIG_DIR       = $(KOLLA_CONFIG_DIR)"
	@echo "  DOCKER_SOCK            = $(DOCKER_SOCK)"
	@echo "  TAG                    = $(TAG)"
	@echo "  REF                    = $(REF)"
	@echo ""
	@echo "Mounts (make shell):"
	@echo "  config dir     $(KOLLA_CONFIG_DIR) -> /etc/kolla (always)"
	@echo "  ~/.ssh         $(if $(wildcard $(HOME)/.ssh),mounted read-only,not found)"
	@echo "  SSH agent      $(if $(and $(SSH_AUTH_SOCK),$(wildcard $(SSH_AUTH_SOCK))),forwarded,not available)"
	@echo "  docker socket  $(if $(wildcard $(DOCKER_SOCK)),mounted,not found)"
	@echo ""
	@echo "Examples:"
	@echo "  make build KOLLA_ANSIBLE_VERSION=22.1.0"
	@echo "  make shell KOLLA_CONFIG_DIR=/srv/kolla"
	@echo "  make build TAG=myregistry.example.com/kolla-ansible:2026.1"
	@echo ""
	@echo "Run 'make help VAR=value' to show effective values for an override."

build:
	docker build $(BUILD_ARGS) -t $(REF) .

rebuild:
	docker build --no-cache --pull $(BUILD_ARGS) -t $(REF) .

test:
	@echo "== kolla-ansible version"
	@docker run --rm --entrypoint kolla-ansible $(REF) --version
	@echo "== kolla-build version"
	@docker run --rm --entrypoint kolla-build $(REF) --version
	@echo "== module deps in venv (docker SDK + dbus for kolla_container)"
	@docker run --rm --entrypoint python $(REF) -c 'import docker, dbus; print("docker SDK", docker.__version__, "| dbus-python", dbus.__version__)'
	@echo "== kolla_container module on localhost (private bus + docker SDK)"
	@docker run --rm \
		$(if $(wildcard $(DOCKER_SOCK)),-v $(DOCKER_SOCK):/var/run/docker.sock) \
		-e ANSIBLE_LIBRARY=/opt/venv/share/kolla-ansible/ansible/library \
		-e ANSIBLE_MODULE_UTILS=/opt/venv/share/kolla-ansible/ansible/module_utils \
		$(REF) ansible localhost -m kolla_container \
		-a "action=compare_container name=kolla-smoke-test"
	@echo "== ansible.utils ipaddr filter (netaddr + ansible.utils collection)"
	@docker run --rm $(REF) ansible localhost -m debug \
		-a "msg={{ '10.0.0.1/24' | ansible.utils.ipaddr('address') }}"
	@echo "== ansible version"
	@docker run --rm --entrypoint ansible $(REF) --version
	@echo "== python version"
	@docker run --rm --entrypoint python $(REF) --version
	@echo "== installed collections"
	@docker run --rm --entrypoint ansible-galaxy $(REF) collection list
	@echo "== requirements.yml (collection ref)"
	@docker run --rm --entrypoint cat $(REF) /opt/venv/share/kolla-ansible/requirements.yml
	@echo "== entrypoint bootstrap (passwords + inventory)"
	@docker run --rm $(REF) bash -c '\
		test -s /etc/kolla/passwords.yml && echo "passwords.yml OK"; \
		test -s /etc/kolla/inventory && echo "inventory OK"; \
		test -s /etc/kolla/globals.yml && echo "globals.yml OK"'

shell:
	@mkdir -p $(KOLLA_CONFIG_DIR)
	docker run --rm -it $(SHELL_MOUNTS) $(REF)

push:
	docker push $(REF)

clean:
	-docker rmi $(REF)

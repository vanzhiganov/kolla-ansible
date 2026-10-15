# Kolla-Ansible deployment controller image
#
#   make build          build the image
#   make rebuild        build without cache
#   make test           run smoke tests inside the image
#   make shell          drop into a shell in the image
#   make push           push the image to a registry
#
# Override any of the variables below, e.g.
#   make build KOLLA_ANSIBLE_VERSION=19.8.0

IMAGE                 ?= kolla-ansible
ROCKY_VERSION         ?= 9
PYTHON_VERSION        ?= 3.11
KOLLA_ANSIBLE_VERSION ?= 19.8.0
OPENSTACK_RELEASE     ?= 2024.2
KOLLA_COLLECTION_BRANCH ?= stable/2024.2
KOLLA_COLLECTION_REF  ?= 2024.2-eol

TAG ?= $(OPENSTACK_RELEASE)-rocky$(ROCKY_VERSION)-py$(subst .,,$(PYTHON_VERSION))
REF ?= $(IMAGE):$(TAG)

BUILD_ARGS = \
	--build-arg ROCKY_VERSION=$(ROCKY_VERSION) \
	--build-arg PYTHON_VERSION=$(PYTHON_VERSION) \
	--build-arg KOLLA_ANSIBLE_VERSION=$(KOLLA_ANSIBLE_VERSION) \
	--build-arg OPENSTACK_RELEASE=$(OPENSTACK_RELEASE) \
	--build-arg KOLLA_COLLECTION_BRANCH=$(KOLLA_COLLECTION_BRANCH) \
	--build-arg KOLLA_COLLECTION_REF=$(KOLLA_COLLECTION_REF)

.PHONY: help build rebuild test shell push clean

help:
	@echo "Targets: build rebuild test shell push clean"
	@echo "Image:   $(REF)"

build:
	docker build $(BUILD_ARGS) -t $(REF) .

rebuild:
	docker build --no-cache --pull $(BUILD_ARGS) -t $(REF) .

test:
	@echo "== kolla-ansible version"
	@docker run --rm --entrypoint kolla-ansible $(REF) --version
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
	docker run --rm -it --entrypoint bash $(REF)

push:
	docker push $(REF)

clean:
	-docker rmi $(REF)

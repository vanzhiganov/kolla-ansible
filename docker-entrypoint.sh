#!/bin/bash
#
# Runtime bootstrap for the kolla-ansible deployment controller image.
#
# On first start it seeds a working /etc/kolla with the packaged examples
# (globals.yml, an all-in-one inventory and freshly generated passwords),
# then hands control to the requested command. Nothing is seeded if the
# corresponding file already exists, so a bind-mounted /etc/kolla is the
# single source of truth across container runs.

set -euo pipefail

KOLLA_CONFIG_DIR="${KOLLA_CONFIG_DIR:-/etc/kolla}"
DATA_DIR="/opt/venv/share/kolla-ansible"
EXAMPLES_DIR="${DATA_DIR}/etc_examples/kolla"
INVENTORY_DIR="${DATA_DIR}/ansible/inventory"

mkdir -p "${KOLLA_CONFIG_DIR}"

seed_from_examples() {
    local name="$1"
    if [ ! -e "${KOLLA_CONFIG_DIR}/${name}" ] && [ -f "${EXAMPLES_DIR}/${name}" ]; then
        echo "kolla-ansible: seeding ${KOLLA_CONFIG_DIR}/${name}"
        cp "${EXAMPLES_DIR}/${name}" "${KOLLA_CONFIG_DIR}/${name}"
    fi
}

seed_from_examples globals.yml

# Passwords: copy the template, then fill it in with kolla-genpwd.
if [ ! -e "${KOLLA_CONFIG_DIR}/passwords.yml" ]; then
    if [ -f "${EXAMPLES_DIR}/passwords.yml" ]; then
        echo "kolla-ansible: generating ${KOLLA_CONFIG_DIR}/passwords.yml"
        cp "${EXAMPLES_DIR}/passwords.yml" "${KOLLA_CONFIG_DIR}/passwords.yml"
        kolla-genpwd -p "${KOLLA_CONFIG_DIR}/passwords.yml"
    fi
fi

# Inventory: default to all-in-one for a quick evaluation; operators using a
# multinode deployment should replace it with their own inventory file.
if [ ! -e "${KOLLA_CONFIG_DIR}/inventory" ] && [ -f "${INVENTORY_DIR}/all-in-one" ]; then
    echo "kolla-ansible: seeding ${KOLLA_CONFIG_DIR}/inventory (all-in-one)"
    cp "${INVENTORY_DIR}/all-in-one" "${KOLLA_CONFIG_DIR}/inventory"
fi

exec "$@"

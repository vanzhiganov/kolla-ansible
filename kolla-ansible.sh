#!/usr/bin/env bash

set -euo pipefail

IMAGE="${IMAGE:-kolla-ansible:2025.1-rocky9-py311}"
KOLLA_CONFIG_DIR="${KOLLA_CONFIG_DIR:-$PWD/kolla}"

mkdir -p "$KOLLA_CONFIG_DIR"

docker_args=(run -it --rm -v "$KOLLA_CONFIG_DIR:/etc/kolla")

if [[ -d "$HOME/.ssh" ]]; then
    docker_args+=(-v "$HOME/.ssh:/root/.ssh:ro")
fi

if [[ -n "${SSH_AUTH_SOCK:-}" && -S "$SSH_AUTH_SOCK" ]]; then
    docker_args+=(-v "$SSH_AUTH_SOCK:/ssh-agent" -e SSH_AUTH_SOCK=/ssh-agent)
fi

# Host Docker daemon so kolla-build can build images (docker-out-of-docker).
DOCKER_SOCK="${DOCKER_SOCK:-/var/run/docker.sock}"
if [[ -S "$DOCKER_SOCK" ]]; then
    docker_args+=(-v "$DOCKER_SOCK:/var/run/docker.sock")
fi

if (($# == 0)); then
    set -- bash
fi

exec docker "${docker_args[@]}" "$IMAGE" "$@"
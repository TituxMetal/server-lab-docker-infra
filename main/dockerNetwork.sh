#!/usr/bin/env bash
# Creates the two bridge networks the stacks expect. Both are `external` in the
# compose files, so nothing creates them implicitly, and default-nw must keep
# this exact iprange: TRUSTED_PROXIES in the Arcane manager relies on it.
set -euo pipefail

if ! docker network inspect default-nw >/dev/null 2>&1; then
  docker network create --driver bridge \
    --subnet 192.168.10.0/24 --gateway 192.168.10.1 --ip-range 192.168.10.0/26 \
    default-nw
fi

if ! docker network inspect reverse-proxy-nw >/dev/null 2>&1; then
  docker network create reverse-proxy-nw
fi

#!/bin/sh
# Caddy entrypoint: substitutes {{WSL_HOST_IP}} placeholders in Caddyfile
# with the value of the WSL_HOST_IP env var, then starts Caddy.
#
# This lets the Caddyfile (which is a static bind-mount, not interpolated
# by compose) use the same WSL_HOST_IP value that compose does.

set -eu

if [ -z "${WSL_HOST_IP:-}" ]; then
    echo "ERROR: WSL_HOST_IP is not set. Configure it in .env" >&2
    exit 1
fi

SRC="/etc/caddy/Caddyfile"
DST="/tmp/Caddyfile.rendered"

sed "s|{{WSL_HOST_IP}}|${WSL_HOST_IP}|g" "$SRC" > "$DST"

echo "Caddyfile rendered with WSL_HOST_IP=${WSL_HOST_IP}"

exec caddy run --config "$DST" --adapter caddyfile

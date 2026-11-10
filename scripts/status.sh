#!/usr/bin/env bash
# Shows slots, containers, disk and registered runners of a host. Usage: scripts/status.sh <server-name>
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
name="${1:?usage: scripts/status.sh <server-name>}"
host="$(sed -n 's/^HOST=//p' "$root/servers/${name}.env" | tail -1)"
ssh "${SSH_USER:-root}@${host}" /opt/ci-runner/host/status.sh

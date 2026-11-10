#!/usr/bin/env bash
# Stores the runner-registration token on a host as /etc/ci-runner/token (root, 0600). Reads it without echo and
# passes it over SSH stdin, so it never appears in shell history, the process list or a file on this machine.
# Usage: scripts/set-token.sh <server-name>
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
name="${1:?usage: scripts/set-token.sh <server-name>}"
host="$(sed -n 's/^HOST=//p' "$root/servers/${name}.env" | tail -1)"
[[ -n "$host" ]] || { echo "HOST is not set in servers/${name}.env" >&2; exit 1; }

read -rsp "Fine-grained token (organization permission Self-hosted runners: read and write): " token
echo
[[ -n "$token" ]] || { echo "Empty token." >&2; exit 1; }
printf '%s' "$token" \
  | ssh "${SSH_USER:-root}@${host}" 'install -d -m 0700 /etc/ci-runner && install -m 0600 /dev/stdin /etc/ci-runner/token'
echo "Token stored on ${host}."

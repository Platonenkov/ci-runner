#!/usr/bin/env bash
# Deploys this repository to a runner host: merges config/defaults.env with servers/<name>.env into
# /etc/ci-runner/runner.env and runs host/install.sh there. Usage: scripts/deploy.sh <server-name>
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
name="${1:?usage: scripts/deploy.sh <server-name>  (a file in servers/)}"
server_env="$root/servers/${name}.env"
[[ -f "$server_env" ]] || { echo "No $server_env" >&2; exit 1; }

host="$(sed -n 's/^HOST=//p' "$server_env" | tail -1)"
[[ -n "$host" ]] || { echo "HOST is not set in $server_env" >&2; exit 1; }
target="${SSH_USER:-root}@${host}"

cat "$root/config/defaults.env" "$server_env" \
  | ssh "$target" 'install -d -m 0700 /etc/ci-runner && { umask 077 && cat > /etc/ci-runner/runner.env.tmp && mv -f /etc/ci-runner/runner.env.tmp /etc/ci-runner/runner.env; }'
tar -C "$root" -cf - image host \
  | ssh "$target" 'rm -rf /opt/ci-runner-src && mkdir -p /opt/ci-runner-src && tar -xf - -C /opt/ci-runner-src'
ssh "$target" 'bash /opt/ci-runner-src/host/install.sh'

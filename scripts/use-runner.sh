#!/usr/bin/env bash
# Switches repositories between the self-hosted runners and GitHub-hosted ubuntu-latest by setting or deleting the
# repository variable LINUX_RUNNER, which workflows read as runs-on: ${{ vars.LINUX_RUNNER || 'ubuntu-latest' }}.
# Usage: scripts/use-runner.sh on|off <repo>...   (repository names in the organization from config/defaults.env)
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode="${1:?usage: scripts/use-runner.sh on|off <repo>...}"
shift
(( $# > 0 )) || { echo "Name at least one repository." >&2; exit 1; }

org="$(sed -n 's/^ORG=//p' "$root/config/defaults.env")"
label="$(sed -n 's/^RUNNER_LABELS=//p' "$root/config/defaults.env" | cut -d, -f1)"

for repo in "$@"; do
  case "$mode" in
    on)  gh variable set LINUX_RUNNER --body "$label" -R "$org/$repo" && echo "$repo -> $label" ;;
    off) gh variable delete LINUX_RUNNER -R "$org/$repo" 2>/dev/null; echo "$repo -> ubuntu-latest" ;;
    *)   echo "Mode is on or off." >&2; exit 1 ;;
  esac
done

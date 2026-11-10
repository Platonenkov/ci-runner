#!/usr/bin/env bash
# Host and GitHub view of the runners: slot units, containers, disk, and the organization's registered runners.
set -Eeuo pipefail

# shellcheck source=/dev/null
source /etc/ci-runner/runner.env

echo "== slots"
systemctl list-units 'ci-runner@*' --all --no-pager --plain --no-legend
echo
echo "== containers"
docker ps --filter name=ci- --format '{{.Names}}\t{{.Status}}\t{{.Image}}'
echo
echo "== disk"
df -h / | tail -1
docker system df
echo
echo "== registered runners (${ORG})"
if [[ -s /etc/ci-runner/token ]]; then
  printf 'header = "Authorization: Bearer %s"\n' "$(</etc/ci-runner/token)" | curl -fsS -K - \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/orgs/${ORG}/actions/runners?per_page=100" \
    | jq -r '.runners[] | "\(.name)\t\(.status)\tbusy=\(.busy)\t\([.labels[].name] | join(","))"'
else
  echo "no token"
fi

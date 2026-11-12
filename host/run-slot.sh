#!/usr/bin/env bash
# One systemd start of ci-runner@<slot> = one job: get a single-use JIT runner config, run the container until the
# job ends, exit; systemd starts the next one. The token stays on the host and never enters the container.
set -Eeuo pipefail

slot="${1:?usage: run-slot.sh <slot>}"
# shellcheck source=/dev/null
source /etc/ci-runner/runner.env

token_file=/etc/ci-runner/token
if [[ ! -s "$token_file" ]]; then
  echo "No token in $token_file; run scripts/set-token from the workstation." >&2
  exit 1
fi

name="$(hostname -s)-${slot}-$(date +%s)"
body="$(jq -n --arg name "$name" --arg labels "$RUNNER_LABELS" --argjson group "$RUNNER_GROUP_ID" \
  '{name: $name, runner_group_id: $group, labels: ($labels | split(",")), work_folder: "_work"}')"

# The header goes through curl's config on stdin so the token is not visible in the process list.
response="$(printf 'header = "Authorization: Bearer %s"\n' "$(<"$token_file")" | curl -fsS -K - \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -d "$body" \
  "https://api.github.com/orgs/${ORG}/actions/runners/generate-jitconfig")"
jit="$(jq -r '.encoded_jit_config' <<<"$response")"
if [[ -z "$jit" || "$jit" == "null" ]]; then
  echo "GitHub returned no JIT config: $response" >&2
  exit 1
fi

# The NuGet package folder is shared by every slot and kept between jobs, so a restore downloads only what is new.
# Workflows skip actions/cache on this runner: that cache lives in Azure Blob Storage, which some hosting networks
# reach at a fraction of their bandwidth. NuGet guards each package extraction with a lock file, so two slots
# restoring at once is safe. Sysbox maps the host owner straight through, so uid 1001 here is runner inside.
nuget_volume=ci-nuget
docker volume create "$nuget_volume" >/dev/null
chown 1001:1001 "$(docker volume inspect -f '{{.Mountpoint}}' "$nuget_volume")"

docker rm -f "ci-${slot}" >/dev/null 2>&1 || true
exec docker run --rm \
  --name "ci-${slot}" \
  --hostname "$name" \
  --runtime=sysbox-runc \
  --memory "$SLOT_MEMORY" \
  --memory-swap "$SLOT_MEMORY" \
  -v "ci-${slot}-docker:/var/lib/docker" \
  -v "${nuget_volume}:/home/runner/.nuget/packages" \
  -e RUNNER_JITCONFIG="$jit" \
  -e DOCKER_CACHE_LIMIT_MB="$DOCKER_CACHE_LIMIT_MB" \
  -e JOB_TIMEOUT_MINUTES="${JOB_TIMEOUT_MINUTES:-120}" \
  "$IMAGE"

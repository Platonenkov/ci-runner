#!/usr/bin/env bash
# Starts the container's own Docker daemon, clears what the previous job of this slot left in it, runs exactly one
# job (the JIT config is single-use) and stops the daemon cleanly: /var/lib/docker is a persistent per-slot volume,
# so killing dockerd with the container could corrupt the image cache the next job relies on.
set -Eeuo pipefail

: "${RUNNER_JITCONFIG:?RUNNER_JITCONFIG is not set}"
cache_limit_mb="${DOCKER_CACHE_LIMIT_MB:-25000}"

dockerd >/var/log/dockerd.log 2>&1 &
dockerd_pid=$!

stop_dockerd() {
  kill -TERM "$dockerd_pid" 2>/dev/null || true
  wait "$dockerd_pid" 2>/dev/null || true
}
trap stop_dockerd EXIT

for _ in $(seq 1 60); do
  docker info >/dev/null 2>&1 && break
  sleep 1
done
if ! docker info >/dev/null 2>&1; then
  echo "dockerd did not start" >&2
  cat /var/log/dockerd.log >&2
  exit 1
fi

# Images and build cache are kept between jobs of a slot; containers, networks and volumes are not.
docker ps -aq | xargs -r docker rm -f >/dev/null
docker network prune -f >/dev/null
docker volume prune -af >/dev/null
used_mb="$(du -sxm /var/lib/docker | cut -f1)"
if (( used_mb > cache_limit_mb )); then
  echo "Docker cache is ${used_mb} MB (limit ${cache_limit_mb} MB), pruning it."
  docker system prune -af --volumes >/dev/null
  docker builder prune -af >/dev/null
fi

cd /home/runner/actions-runner
# sudo applies pam_umask, which with USERGROUPS_ENAB gives umask 0002; the hosted runner uses 0022, and tests
# that check the mode of created files and directories fail on 0775 instead of 0755.
sudo -u runner --preserve-env=LANG,RUNNER_TOOL_CACHE,AGENT_TOOLSDIRECTORY,DOTNET_ROOT,DOTNET_NOLOGO,DOTNET_CLI_TELEMETRY_OPTOUT,ImageOS \
  bash -c 'umask 0022 && exec ./run.sh --jitconfig "$1"' run "$RUNNER_JITCONFIG"

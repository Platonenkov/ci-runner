#!/usr/bin/env bash
# Builds the runner image. Ephemeral runners do not self-update between jobs, and GitHub stops accepting a runner
# version about 30 days after a newer release, so the weekly timer rebuilds with the latest one. Running slots pick
# up the new image with their next job.
set -Eeuo pipefail

# shellcheck source=/dev/null
source /etc/ci-runner/runner.env

version="${RUNNER_VERSION:-}"
if [[ -z "$version" ]]; then
  version="$(curl -fsS https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name | ltrimstr("v")')"
fi
echo "Building $IMAGE with runner $version"

docker build --pull --build-arg RUNNER_VERSION="$version" -t "$IMAGE" /opt/ci-runner/image
docker image prune -f >/dev/null

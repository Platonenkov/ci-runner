#!/usr/bin/env bash
# Idempotent host setup, run as root from the unpacked repository (scripts/deploy does that). Installs Docker and
# Sysbox, places the files under /opt/ci-runner, builds the image and runs SLOTS slot units. Slots that are already
# running are left alone, so a redeploy never kills a job in progress; they take the new image with their next job.
set -Eeuo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file=/etc/ci-runner/runner.env

if [[ $EUID -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi
if [[ ! -s "$env_file" ]]; then
  echo "$env_file is missing; scripts/deploy writes it from config/defaults.env and servers/<name>.env." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$env_file"

export DEBIAN_FRONTEND=noninteractive
apt-get update -q
# fuse3: sysbox-fs mounts through fusermount3, and the Sysbox package does not depend on it; without it every
# container fails with "failed to pre-register with sysbox-fs".
apt-get install -y -q ca-certificates curl jq gnupg rsync fuse3

if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  # shellcheck source=/dev/null
  codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${codename} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -q
  apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin
fi

installed_sysbox="$(dpkg-query -W -f='${Version}' sysbox-ce 2>/dev/null || true)"
if [[ "$installed_sysbox" != "${SYSBOX_VERSION}"* ]]; then
  # The Sysbox package restarts Docker and refuses to install while containers run; on a host with busy slots
  # stop them first (systemctl stop 'ci-runner@*').
  deb="/tmp/sysbox-ce_${SYSBOX_VERSION}.linux_amd64.deb"
  curl -fsSL -o "$deb" \
    "https://github.com/nestybox/sysbox/releases/download/v${SYSBOX_VERSION}/sysbox-ce_${SYSBOX_VERSION}.linux_amd64.deb"
  echo "${SYSBOX_SHA256}  ${deb}" | sha256sum -c -
  apt-get install -y -q "$deb"
  rm -f "$deb"
fi

install -d -m 0755 /opt/ci-runner
rsync -a --delete "$src/image" "$src/host" /opt/ci-runner/
chmod +x /opt/ci-runner/host/*.sh /opt/ci-runner/image/entrypoint.sh
install -m 0644 "$src"/host/systemd/* /etc/systemd/system/
systemctl daemon-reload

/opt/ci-runner/host/build-image.sh
systemctl enable --now ci-runner-rebuild.timer

for unit in $(systemctl list-units 'ci-runner@*' --all --plain --no-legend | awk '{print $1}'); do
  slot="${unit#ci-runner@}"
  slot="${slot%.service}"
  if (( slot > SLOTS )); then
    systemctl disable --now "$unit"
  fi
done

if [[ ! -s /etc/ci-runner/token ]]; then
  echo "Installed. No token yet: run scripts/set-token, then scripts/deploy again to start the slots."
  exit 0
fi
for slot in $(seq 1 "$SLOTS"); do
  systemctl enable --now "ci-runner@${slot}"
done
echo "Installed, ${SLOTS} slots enabled."

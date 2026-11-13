#!/usr/bin/env bash
# Runs before sysbox-fs starts (install.sh adds it as ExecStartPre). FUSE mounts left under /var/lib/sysboxfs by a
# sysbox-fs that died with containers running make the next one time out on start; with sysbox-fs down nothing can
# be using them, so they are detached.
set -Eeuo pipefail

awk '$2 ~ "^/var/lib/sysboxfs/" { print $2 }' /proc/mounts | while read -r mountpoint; do
  echo "Detaching stale sysbox-fs mount ${mountpoint}"
  umount -l "$mountpoint" || true
done

#!/usr/bin/env bash
# Server side of scripts/bootstrap, piped over the administrator's own SSH session as root.
#   authorize <public key>   adds the deploy key to root's authorized_keys
#   facts                    prints CPU, memory, disk and the host keys for known_hosts
#   harden                   turns off password login; run only after the deploy key is proven to work
set -Eeuo pipefail

case "${1:-}" in
  authorize)
    key="${2:?public key required}"
    install -d -m 0700 /root/.ssh
    touch /root/.ssh/authorized_keys
    chmod 0600 /root/.ssh/authorized_keys
    grep -qxF "$key" /root/.ssh/authorized_keys || printf '%s\n' "$key" >> /root/.ssh/authorized_keys
    echo "authorized"
    ;;
  facts)
    echo "nproc=$(nproc)"
    # MemTotal is below the nominal size (16 GB shows as about 15.6 GiB), so round to the nearest GiB.
    echo "mem_gb=$(awk '/^MemTotal:/ { printf "%d", $2 / 1048576 + 0.5 }' /proc/meminfo)"
    echo "disk_gb=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')"
    # shellcheck source=/dev/null
    echo "os=$(. /etc/os-release && echo "${ID}-${VERSION_ID}")"
    for f in /etc/ssh/ssh_host_*_key.pub; do
      echo "hostkey=$(cut -d' ' -f1,2 "$f")"
    done
    ;;
  harden)
    # Files in sshd_config.d are read in name order and the first value wins, so 10- overrides the cloud image's
    # 50-cloud-init.conf, which turns password login on.
    cat > /etc/ssh/sshd_config.d/10-ci-runner.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
    sshd -t
    systemctl reload ssh
    sshd -T | grep -E '^(passwordauthentication|permitrootlogin|kbdinteractiveauthentication) '
    ;;
  *)
    echo "usage: bootstrap-remote.sh authorize <key> | facts | harden" >&2
    exit 2
    ;;
esac

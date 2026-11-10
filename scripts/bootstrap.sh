#!/usr/bin/env bash
# First-time setup of a runner host from the administrator's machine; see scripts/bootstrap.ps1 for the steps.
# Usage: scripts/bootstrap.sh [--apply] [--skip-harden] [--repo owner/name] <name> <address>
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
apply=false
harden=true
repo=""
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --apply) apply=true ;;
    --skip-harden) harden=false ;;
    --repo) repo="$2"; shift ;;
    *) echo "Unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
name="${1:?usage: scripts/bootstrap.sh [--apply] [--skip-harden] [--repo owner/name] <name> <address>}"
address="${2:?address required}"
[[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Name may contain letters, digits, . _ -" >&2; exit 2; }

target="${SSH_USER:-root}@${address}"
dir="$root/.local/$name"
key="$dir/deploy_key"
known_hosts="$dir/known_hosts"
mkdir -p "$dir"
chmod 700 "$dir"

# The arguments are meant to expand here: they are the subcommand and the already quoted public key.
# shellcheck disable=SC2029
remote() { ssh "$target" "bash -s -- $*" < "$root/host/bootstrap-remote.sh"; }

[[ -f "$key" ]] || ssh-keygen -q -t ed25519 -N "" -C "ci-runner-deploy@$name" -f "$key"

echo "== Authorizing the deploy key on $address (your own SSH access is used once)"
remote authorize "'$(<"$key.pub")'"

echo "== Reading the host"
facts="$(remote facts)"
fact() { sed -n "s/^$1=//p" <<<"$facts"; }
sed -n "s/^hostkey=/$address /p" <<<"$facts" > "$known_hosts"
[[ -s "$known_hosts" ]] || { echo "The host returned no host keys." >&2; exit 1; }

echo "== Checking the deploy key"
ssh -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts" \
  "$target" true || { echo "The deploy key does not log in; password login stays on." >&2; exit 1; }

if $harden; then
  echo "== Turning off password login"
  remote harden
fi

nproc="$(fact nproc)"
mem_gb="$(fact mem_gb)"
disk_gb="$(fact disk_gb)"
os="$(fact os)"
# Same sizing rules as bootstrap.ps1: 7 GB per slot plus 2 GB for the host, two vCPUs per slot, and half of the
# disk beyond 25 GB split between the slot caches, within 5-25 GB each.
by_mem=$(( (mem_gb - 2) / 7 ))
by_cpu=$(( nproc / 2 > 0 ? nproc / 2 : 1 ))
slots=$(( by_mem < by_cpu ? by_mem : by_cpu ))
(( slots >= 1 )) || slots=1
cache_mb=$(( (disk_gb - 25) * 1000 / slots / 2 ))
(( cache_mb <= 25000 )) || cache_mb=25000
(( cache_mb >= 5000 )) || cache_mb=5000

cat > "$root/servers/$name.env" <<EOF
# Written by scripts/bootstrap.sh: $nproc vCPU, $mem_gb GB RAM, $disk_gb GB free, $os.
HOST=$address
SLOTS=$slots
SLOT_MEMORY=7g
DOCKER_CACHE_LIMIT_MB=$cache_mb
EOF

if [[ -z "$repo" ]]; then
  repo="$(git -C "$root" remote get-url origin 2>/dev/null | sed -nE 's#.*github\.com[:/](.+)$#\1#; s#\.git$##p')"
fi

cat <<EOF

Host: $nproc vCPU, $mem_gb GB RAM, $disk_gb GB free, $os -> SLOTS=$slots, DOCKER_CACHE_LIMIT_MB=$cache_mb

GitHub environment '$name' (repository $repo, Settings > Environments):
  secret   SSH_HOST               $address
  secret   SSH_PRIVATE_KEY        contents of $key
  secret   SSH_KNOWN_HOSTS        contents of $known_hosts
  variable SLOTS                  $slots
  variable SLOT_MEMORY            7g
  variable DOCKER_CACHE_LIMIT_MB  $cache_mb
Repository secret (once for all hosts):
  secret   RUNNER_TOKEN           fine-grained token, owner StaticBit-io, Self-hosted runners: Read and write
EOF

if ! $apply; then
  echo
  echo "Run again with --apply to set them with gh, then: gh secret set RUNNER_TOKEN -R $repo"
  exit 0
fi
[[ -n "$repo" ]] || { echo "No repository: pass --repo owner/name." >&2; exit 1; }

echo
echo "== Setting environment '$name' in $repo"
gh api -X PUT "repos/$repo/environments/$name" --silent
# Values go through stdin, so the private key is never on a command line.
printf '%s' "$address" | gh secret set SSH_HOST --env "$name" -R "$repo"
gh secret set SSH_PRIVATE_KEY --env "$name" -R "$repo" < "$key"
gh secret set SSH_KNOWN_HOSTS --env "$name" -R "$repo" < "$known_hosts"
gh variable set SLOTS --env "$name" -R "$repo" --body "$slots"
gh variable set SLOT_MEMORY --env "$name" -R "$repo" --body 7g
gh variable set DOCKER_CACHE_LIMIT_MB --env "$name" -R "$repo" --body "$cache_mb"

if ! gh secret list -R "$repo" --json name --jq '.[].name' | grep -qx RUNNER_TOKEN; then
  echo "RUNNER_TOKEN is not set yet: gh secret set RUNNER_TOKEN -R $repo  (gh asks for the value without echo)"
fi
echo "Done. Deploy: gh workflow run deploy.yml -R $repo -f server=$name"

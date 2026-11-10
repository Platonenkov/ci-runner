<#
.SYNOPSIS
First-time setup of a runner host from the administrator's machine.

.DESCRIPTION
Uses the administrator's own SSH access (key or password) once, and:
  1. creates a dedicated deploy key in .local/<Name>/ and authorizes it for root on the host;
  2. reads CPU, memory, disk and the host keys, and pins the host keys in .local/<Name>/known_hosts;
  3. checks that the deploy key logs in, then turns off password login (skip with -SkipHarden);
  4. sizes the slots and writes servers/<Name>.env for the local deploy scripts;
  5. prints the GitHub environment secrets and variables, or sets them with -Apply.

The deploy workflow (.github/workflows/deploy.yml) then reaches the host only through those secrets.

.EXAMPLE
./scripts/bootstrap.ps1 -Name ryzen -Address 203.0.113.10
./scripts/bootstrap.ps1 -Name ryzen -Address 203.0.113.10 -Apply
#>
param(
    [Parameter(Mandatory)] [ValidatePattern('^[A-Za-z0-9._-]+$')] [string] $Name,
    [Parameter(Mandatory)] [string] $Address,
    [string] $SshUser = 'root',
    [string] $Repo,
    [switch] $Apply,
    [switch] $SkipHarden
)
# Native commands are checked through $LASTEXITCODE: with 'Stop', Windows PowerShell 5.1 turns any stderr line of
# a native command into a terminating error once output is redirected.
$ErrorActionPreference = 'Continue'
# Text piped to ssh and gh is encoded with $OutputEncoding; a profile may set UTF-8 with a BOM.
$OutputEncoding = New-Object System.Text.UTF8Encoding $false

$root = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $root ".local/$Name"
$key = Join-Path $dir 'deploy_key'
$knownHosts = Join-Path $dir 'known_hosts'
$remoteScript = Join-Path $root 'host/bootstrap-remote.sh'
$target = "$SshUser@$Address"
New-Item -ItemType Directory -Force $dir | Out-Null

function Invoke-Remote([string] $Arguments) {
    # The script travels on stdin. Windows PowerShell 5.1 may prefix piped text with a UTF-8 BOM whatever
    # $OutputEncoding says and appends CRLF, so both are removed on the host.
    Get-Content -Raw -ErrorAction Stop $remoteScript | ssh $target "sed '1s/^\xEF\xBB\xBF//' | tr -d '\r' | bash -s -- $Arguments"
    if ($LASTEXITCODE -ne 0) { throw "bootstrap-remote.sh $Arguments failed ($LASTEXITCODE)" }
}

if (-not (Test-Path $key)) {
    # '""' is how Windows PowerShell 5.1 passes an empty argument; a bare "" is dropped.
    ssh-keygen -q -t ed25519 -N '""' -C "ci-runner-deploy@$Name" -f $key
    if ($LASTEXITCODE -ne 0) { throw "ssh-keygen failed ($LASTEXITCODE)" }
}
$publicKey = (Get-Content -Raw -ErrorAction Stop "$key.pub").Trim()

Write-Host "== Authorizing the deploy key on $Address (your own SSH access is used once)"
Invoke-Remote "authorize '$publicKey'"

Write-Host '== Reading the host'
$facts = @{}
$hostKeys = @()
foreach ($line in (Invoke-Remote 'facts')) {
    $k, $v = $line -split '=', 2
    if ($k -eq 'hostkey') { $hostKeys += "$Address $v" } else { $facts[$k] = $v }
}
if (-not $hostKeys) { throw 'The host returned no host keys.' }
[IO.File]::WriteAllText($knownHosts, (($hostKeys -join "`n") + "`n"))

Write-Host '== Checking the deploy key'
ssh -i $key -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$knownHosts" $target true
if ($LASTEXITCODE -ne 0) { throw 'The deploy key does not log in; password login stays on.' }

if (-not $SkipHarden) {
    Write-Host '== Turning off password login'
    Invoke-Remote 'harden'
}

$nproc = [int] $facts['nproc']
$memGb = [int] $facts['mem_gb']
$diskGb = [int] $facts['disk_gb']
# 7 GB per slot as on the hosted runner, about 2 GB for the host itself, and at least two vCPUs per slot.
$slots = [Math]::Max(1, [Math]::Min([Math]::Floor(($memGb - 2) / 7), [Math]::Max(1, [Math]::Floor($nproc / 2))))
# About 25 GB stay for the runner image and the system; half of the rest is split between the slot caches.
$cacheMb = [Math]::Max(5000, [Math]::Min(25000, [Math]::Floor(($diskGb - 25) * 1000 / $slots / 2)))

$serverEnv = @(
    "# Written by scripts/bootstrap.ps1: $nproc vCPU, $memGb GB RAM, $diskGb GB free, $($facts['os']).",
    "HOST=$Address",
    "SLOTS=$slots",
    'SLOT_MEMORY=7g',
    "DOCKER_CACHE_LIMIT_MB=$cacheMb"
) -join "`n"
[IO.File]::WriteAllText((Join-Path $root "servers/$Name.env"), "$serverEnv`n")

if (-not $Repo) {
    $origin = git -C $root remote get-url origin 2>$null
    if ($origin -match 'github\.com[:/](.+?)(\.git)?$') { $Repo = $Matches[1] }
}

Write-Host ''
Write-Host "Host: $nproc vCPU, $memGb GB RAM, $diskGb GB free, $($facts['os']) -> SLOTS=$slots, DOCKER_CACHE_LIMIT_MB=$cacheMb"
Write-Host ''
Write-Host "GitHub environment '$Name' (repository $Repo, Settings > Environments):"
Write-Host "  secret   SSH_HOST               $Address"
Write-Host "  secret   SSH_PRIVATE_KEY        contents of $key"
Write-Host "  secret   SSH_KNOWN_HOSTS        contents of $knownHosts"
Write-Host "  variable SLOTS                  $slots"
Write-Host '  variable SLOT_MEMORY            7g'
Write-Host "  variable DOCKER_CACHE_LIMIT_MB  $cacheMb"
Write-Host 'Repository secret (once for all hosts):'
Write-Host '  secret   RUNNER_TOKEN           fine-grained token, owner StaticBit-io, Self-hosted runners: Read and write'

if (-not $Apply) {
    Write-Host ''
    Write-Host "Run again with -Apply to set them with gh, then: gh secret set RUNNER_TOKEN -R $Repo"
    return
}
if (-not $Repo) { throw 'No repository: pass -Repo owner/name.' }

Write-Host ''
Write-Host "== Setting environment '$Name' in $Repo"
gh api -X PUT "repos/$Repo/environments/$Name" --silent
if ($LASTEXITCODE -ne 0) { throw "Creating the environment failed ($LASTEXITCODE)" }
# Files go to gh through cmd redirection: the bytes arrive unchanged (a PowerShell pipe may add a BOM), and the
# private key is never on a command line.
gh secret set SSH_HOST --env $Name -R $Repo --body $Address
cmd /c "gh secret set SSH_PRIVATE_KEY --env $Name -R $Repo < `"$key`""
cmd /c "gh secret set SSH_KNOWN_HOSTS --env $Name -R $Repo < `"$knownHosts`""
gh variable set SLOTS --env $Name -R $Repo --body "$slots"
gh variable set SLOT_MEMORY --env $Name -R $Repo --body '7g'
gh variable set DOCKER_CACHE_LIMIT_MB --env $Name -R $Repo --body "$cacheMb"
if ($LASTEXITCODE -ne 0) { throw "gh failed ($LASTEXITCODE)" }

$hasToken = gh secret list -R $Repo --json name --jq '.[].name' 2>$null | Where-Object { $_ -eq 'RUNNER_TOKEN' }
if (-not $hasToken) {
    Write-Host "RUNNER_TOKEN is not set yet: gh secret set RUNNER_TOKEN -R $Repo  (gh asks for the value without echo)"
}
Write-Host "Done. Deploy: gh workflow run deploy.yml -R $Repo -f server=$Name"

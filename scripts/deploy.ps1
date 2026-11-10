<#
.SYNOPSIS
Deploys this repository to a runner host.

.DESCRIPTION
Merges config/defaults.env with servers/<Server>.env into /etc/ci-runner/runner.env on the host and runs
host/install.sh there. Uses the Windows OpenSSH client and the built-in tar.

.EXAMPLE
./scripts/deploy.ps1 -Server ryzen
#>
param(
    [Parameter(Mandatory)] [string] $Server,
    [string] $SshUser = 'root'
)
# Native commands are checked through $LASTEXITCODE: with 'Stop', Windows PowerShell 5.1 turns any stderr line of
# ssh (apt and docker progress, for example) into a terminating error once output is redirected.
$ErrorActionPreference = 'Continue'
# Text piped to ssh is encoded with $OutputEncoding; a profile may set UTF-8 with a BOM, which bash then reads
# as part of the first line.
$OutputEncoding = New-Object System.Text.UTF8Encoding $false

$root = Split-Path -Parent $PSScriptRoot
$serverEnv = Join-Path $root "servers/$Server.env"
if (-not (Test-Path $serverEnv)) { throw "No $serverEnv" }

$hostLine = Get-Content $serverEnv | Where-Object { $_ -match '^HOST=' } | Select-Object -Last 1
if (-not $hostLine) { throw "HOST is not set in $serverEnv" }
$target = "$SshUser@$($hostLine.Substring(5))"

# The file is sourced by bash, and a CR would end up inside every value; PowerShell adds CRLF when piping to ssh.
$config = ((Get-Content -ErrorAction Stop (Join-Path $root 'config/defaults.env')) + (Get-Content $serverEnv)) -join "`n"
$config | ssh $target 'install -d -m 0700 /etc/ci-runner && tr -d ''\r'' | sed ''1s/^\xEF\xBB\xBF//'' | install -m 0600 /dev/stdin /etc/ci-runner/runner.env'
if ($LASTEXITCODE -ne 0) { throw "Writing runner.env failed ($LASTEXITCODE)" }

# The archive goes through a file: PowerShell 5.1 pipes text, not bytes, between native commands.
$archive = Join-Path ([IO.Path]::GetTempPath()) "ci-runner-$([guid]::NewGuid()).tar"
try {
    tar -C $root -cf $archive image host
    if ($LASTEXITCODE -ne 0) { throw "tar failed ($LASTEXITCODE)" }
    scp -q $archive "${target}:/tmp/ci-runner-src.tar"
    if ($LASTEXITCODE -ne 0) { throw "scp failed ($LASTEXITCODE)" }
} finally {
    Remove-Item $archive -ErrorAction SilentlyContinue
}

ssh $target 'rm -rf /opt/ci-runner-src && mkdir -p /opt/ci-runner-src && tar -xf /tmp/ci-runner-src.tar -C /opt/ci-runner-src && rm /tmp/ci-runner-src.tar && bash /opt/ci-runner-src/host/install.sh'
if ($LASTEXITCODE -ne 0) { throw "install.sh failed ($LASTEXITCODE)" }

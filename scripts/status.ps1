<#
.SYNOPSIS
Shows slots, containers, disk and registered runners of a host.

.EXAMPLE
./scripts/status.ps1 -Server ryzen
#>
param(
    [Parameter(Mandatory)] [string] $Server,
    [string] $SshUser = 'root'
)
# Native commands are checked through $LASTEXITCODE: with 'Stop', Windows PowerShell 5.1 turns any stderr line of
# ssh (apt and docker progress, for example) into a terminating error once output is redirected.
$ErrorActionPreference = 'Continue'

$root = Split-Path -Parent $PSScriptRoot
$hostLine = Get-Content -ErrorAction Stop (Join-Path $root "servers/$Server.env") | Where-Object { $_ -match '^HOST=' } | Select-Object -Last 1
if (-not $hostLine) { throw "HOST is not set in servers/$Server.env" }
ssh "$SshUser@$($hostLine.Substring(5))" /opt/ci-runner/host/status.sh

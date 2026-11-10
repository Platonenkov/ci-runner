<#
.SYNOPSIS
Switches repositories between the self-hosted runners and GitHub-hosted ubuntu-latest.

.DESCRIPTION
Sets or deletes the repository variable LINUX_RUNNER, which workflows read as
runs-on: ${{ vars.LINUX_RUNNER || 'ubuntu-latest' }}. Deleting it is the fallback when the host is down.

.EXAMPLE
./scripts/use-runner.ps1 -Mode On -Repo glintwild, xrpl-explorer-net
./scripts/use-runner.ps1 -Mode Off -Repo glintwild
#>
param(
    [Parameter(Mandatory)] [ValidateSet('On', 'Off')] [string] $Mode,
    [Parameter(Mandatory)] [string[]] $Repo
)
# gh is checked through $LASTEXITCODE: with 'Stop', Windows PowerShell 5.1 turns any stderr line of a native command
# into a terminating error once output is redirected.
$ErrorActionPreference = 'Continue'

$defaults = Get-Content -ErrorAction Stop (Join-Path (Split-Path -Parent $PSScriptRoot) 'config/defaults.env')
$org = ($defaults | Where-Object { $_ -match '^ORG=' }).Substring(4)
$label = ($defaults | Where-Object { $_ -match '^RUNNER_LABELS=' }).Substring(14).Split(',')[0]

foreach ($r in $Repo) {
    if ($Mode -eq 'On') {
        gh variable set LINUX_RUNNER --body $label -R "$org/$r"
        if ($LASTEXITCODE -ne 0) { throw "gh failed for $r ($LASTEXITCODE)" }
        Write-Host "$r -> $label"
    } else {
        gh variable delete LINUX_RUNNER -R "$org/$r" 2>$null
        Write-Host "$r -> ubuntu-latest"
    }
}

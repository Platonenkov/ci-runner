<#
.SYNOPSIS
Stores the runner-registration token on a host as /etc/ci-runner/token (root, 0600).

.DESCRIPTION
Reads the token as a SecureString and passes it over SSH stdin, so it never appears in history, the process list
or a file on this machine. The token is a fine-grained personal access token for the organization with the
permission "Self-hosted runners: Read and write" and nothing else.

.EXAMPLE
./scripts/set-token.ps1 -Server ryzen
#>
param(
    [Parameter(Mandatory)] [string] $Server,
    [string] $SshUser = 'root'
)
# Native commands are checked through $LASTEXITCODE: with 'Stop', Windows PowerShell 5.1 turns any stderr line of
# ssh (apt and docker progress, for example) into a terminating error once output is redirected.
$ErrorActionPreference = 'Continue'
# Text piped to ssh is encoded with $OutputEncoding; a profile may set UTF-8 with a BOM, which would become part
# of the stored token.
$OutputEncoding = New-Object System.Text.UTF8Encoding $false

$root = Split-Path -Parent $PSScriptRoot
$hostLine = Get-Content -ErrorAction Stop (Join-Path $root "servers/$Server.env") | Where-Object { $_ -match '^HOST=' } | Select-Object -Last 1
if (-not $hostLine) { throw "HOST is not set in servers/$Server.env" }
$target = "$SshUser@$($hostLine.Substring(5))"

$secure = Read-Host -AsSecureString 'Fine-grained token (organization permission Self-hosted runners: read and write)'
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    if (-not $token) { throw 'Empty token.' }
    # Single quotes on the remote side: Windows PowerShell 5.1 drops embedded double quotes when it builds a native
    # command line, and tr would then strip the letters r and n from the token.
    $token | ssh $target 'install -d -m 0700 /etc/ci-runner && tr -d ''\r\n'' | sed ''1s/^\xEF\xBB\xBF//'' | { umask 077 && cat > /etc/ci-runner/token.tmp && mv -f /etc/ci-runner/token.tmp /etc/ci-runner/token; }'
    if ($LASTEXITCODE -ne 0) { throw "ssh failed ($LASTEXITCODE)" }
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    Remove-Variable token -ErrorAction SilentlyContinue
}
Write-Host "Token stored on $($target.Split('@')[1])."

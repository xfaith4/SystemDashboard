<#
.SYNOPSIS
    Install the System Monitor WebApp as a Windows service.
.DESCRIPTION
    Prefers NSSM if present (recommended for robust logging/restarts).
    Falls back to sc.exe with a simple service command.
.NOTES
    Run from repo root with admin PowerShell 7.
#>
param(
    [string]$ServiceName = 'SystemMonitorWebApp',
    [string]$DisplayName = 'System Monitor WebApp',
    [string]$Description = 'PowerShell 7 + Pode based local monitoring service'
)

$repo = Split-Path -Parent $PSScriptRoot
$pwsh = (Get-Command pwsh).Source
$entry = Join-Path $repo 'Start-SystemDashboard.ps1'
if (-not (Test-Path $entry)) { throw "Start-SystemDashboard.ps1 not found at repo root." }

$logs = Join-Path $repo 'logs'
if (-not (Test-Path $logs)) { New-Item -ItemType Directory -Path $logs | Out-Null }

if (Get-Command nssm -ErrorAction SilentlyContinue) {
    nssm install $ServiceName $pwsh "-NoProfile -File `"$entry`""
    nssm set $ServiceName Description "$Description"
    nssm set $ServiceName AppStdout (Join-Path $logs 'service.out.log')
    nssm set $ServiceName AppStderr (Join-Path $logs 'service.err.log')
    nssm set $ServiceName Start SERVICE_AUTO_START
    nssm start $ServiceName
    Write-Host "Installed via NSSM."
} else {
    sc.exe create $ServiceName binPath= "`"$pwsh`" -NoProfile -File `"$entry`"" start= auto
    sc.exe description $ServiceName "$Description" | Out-Null
    sc.exe start $ServiceName | Out-Null
    Write-Host "Installed via sc.exe. Logs appear in .\logs\app.log"
}

Write-Host "Service '$ServiceName' installed."

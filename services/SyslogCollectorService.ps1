#requires -Version 7
<#
.SYNOPSIS
    SystemDashboard Syslog Collector Service
.DESCRIPTION
    Listens for syslog over UDP (default 5514) and ingests into PostgreSQL.
    Uses SystemDashboard.Telemetry pipeline with ASUS collection disabled.
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..' 'config.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$telemetryModulePath = Join-Path $repoRoot "tools" "SystemDashboard.Telemetry.psm1"

if (-not (Test-Path -LiteralPath $telemetryModulePath)) {
    throw "Telemetry module not found at $telemetryModulePath"
}

Import-Module $telemetryModulePath -Force -Global

# Load and override config so this service only handles syslog
try {
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
} catch {
    throw "Failed to read config file at $ConfigPath: $($_.Exception.Message)"
}

# Ensure log directory
$logDir = Join-Path $repoRoot "var" "log"
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Override settings for syslog-only run
$config.Service.Asus.Enabled = $false
if ($config.Service.Asus.SSH) { $config.Service.Asus.SSH.Enabled = $false }
$config.Service.LogPath = Join-Path $logDir "syslog-collector.log"

# Write temp config for this service instance
$tempConfig = Join-Path $env:TEMP "sysdash-syslog-config.json"
$config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tempConfig -Encoding UTF8

Write-Host "Starting Syslog Collector with config: $tempConfig"
Start-TelemetryService -ConfigPath $tempConfig

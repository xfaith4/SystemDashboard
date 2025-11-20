#requires -Version 7
<#
.SYNOPSIS
  Canonical entrypoint that runs the unified Pode-based SystemDashboard build (2025-09-11 version).
.DESCRIPTION
  Imports the modern module under 2025-09-11/modules, loads the matching config, and starts the server.
  Keep using this file while we finish merging older variants (legacy listener, Flask UI, WindSurf telemetry).
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

param(
    # Path to the config that matches the Pode build (defaults to the 2025-09-11 config.json).
    [string]$ConfigPath = (Join-Path $PSScriptRoot '2025-09-11\config.json')
)

$modulePath = Join-Path $PSScriptRoot '2025-09-11\modules\SystemDashboard.psd1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "Unified module not found at $modulePath. Did the 2025-09-11 tree move?"
}

Import-Module $modulePath -Force

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config file not found at $ConfigPath. Pass -ConfigPath to override."
}

$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
Start-SystemDashboard -Config $cfg

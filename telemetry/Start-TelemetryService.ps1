#requires -Version 7
[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..' '2025-09-11' 'config.json')
)

$modulePath = Join-Path $PSScriptRoot 'SystemDashboard.Telemetry.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "Telemetry module not found at $modulePath"
}

$rawConfig = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -Depth 10

if ($rawConfig.PSObject.Properties.Name -contains 'telemetry') {
    if ($rawConfig.telemetry.enabled -ne $true) {
        Write-Host "Telemetry service is disabled in config.telemetry.enabled. Nothing to do." -ForegroundColor Yellow
        return
    }
}

Import-Module $modulePath -Force

# Dot-source the schema helper for convenience during bring-up
. (Join-Path $PSScriptRoot 'Apply-TelemetrySchema.ps1') *>$null

Start-TelemetryService -ConfigPath $ConfigPath

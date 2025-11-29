#requires -Version 7
[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..' 'config.json')
)

$modulePath = Join-Path $PSScriptRoot '..' 'tools' 'SystemDashboard.Telemetry-Minimal.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "Telemetry module not found at $modulePath"
}

Import-Module $modulePath -Force
Start-TelemetryService -ConfigPath $ConfigPath

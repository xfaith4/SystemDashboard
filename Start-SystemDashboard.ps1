#requires -Version 7
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json')
)
try {
$env:SYSTEMDASHBOARD_CONFIG = $ConfigPath
Import-Module (Join-Path $PSScriptRoot 'Start-SystemDashboard.psm1') -Force
} catch {    
    Write-Error "Failed to start dashboard: $_"
    }

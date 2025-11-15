#requires -Version 7
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json')
)
try {
    $env:SYSTEMDASHBOARD_CONFIG = $ConfigPath
    
    # Guard against module nesting limit - only import if not already loaded
    $modulePath = Join-Path $PSScriptRoot 'Start-SystemDashboard.psm1'
    $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($modulePath)
    
    if (-not (Get-Module -Name $moduleName -ErrorAction SilentlyContinue)) {
        Import-Module $modulePath -Force
    } else {
        Write-Verbose "Module '$moduleName' already loaded; skipping Import-Module to avoid nested imports."
    }
} catch {    
    Write-Error "Failed to start dashboard: $_"
}

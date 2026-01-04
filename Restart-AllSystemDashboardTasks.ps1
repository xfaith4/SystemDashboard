#requires -Version 7
<#
.SYNOPSIS
Restarts the telemetry, listener, and UI scheduled tasks for the System Dashboard stack.

.DESCRIPTION
Imports the SystemDashboard module and invokes the helper that restarts every Service-based scheduled task defined by the project (SystemDashboard-Telemetry and SystemDashboard-LegacyUI).

.USAGE
Pin this script to your taskbar via a shortcut that runs `pwsh.exe -NoProfile -File "Restart-AllSystemDashboardTasks.ps1"`.
#>

param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulePath = Join-Path $repoRoot 'Start-SystemDashboard.psm1'

if (-not (Test-Path -LiteralPath $modulePath)) {
    Write-Error "Cannot find Start-SystemDashboard.psm1 at $modulePath"
    exit 1
}

Import-Module $modulePath -Force
Restart-SystemDashboardTasks

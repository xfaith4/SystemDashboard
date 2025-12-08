#!/usr/bin/env pwsh
<#
.SYNOPSIS
Create a scheduled task to run System Dashboard as a service

.DESCRIPTION
This script creates a scheduled task that runs the System Dashboard telemetry service
automatically at system startup. This is more reliable than Windows Services for PowerShell scripts.

.EXAMPLE
.\scripts\setup-scheduled-task.ps1
#>

[CmdletBinding()]
param()

$taskName = "SystemDashboard-Telemetry"
$scriptPath = Join-Path $PSScriptRoot "services\SystemDashboardService.ps1"
$configPath = Join-Path $PSScriptRoot "config.json"
$logPath = Join-Path $PSScriptRoot "var\log\scheduled-task.log"

# Ensure log directory exists
$logDir = Split-Path $logPath -Parent
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

Write-Host "Setting up System Dashboard as a scheduled task..." -ForegroundColor Cyan

# Remove existing task if it exists
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "Removing existing scheduled task: $taskName" -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# Create the action (what to run)
$actionArgs = "-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -ConfigPath `"$configPath`""
$action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument $actionArgs -WorkingDirectory $PSScriptRoot

# Create the trigger (when to run) - at startup
$trigger = New-ScheduledTaskTrigger -AtStartup

# Create settings
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

# Create the principal (run as SYSTEM)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount

# Register the task
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "System Dashboard Telemetry Collection Service" | Out-Null

Write-Host "✅ Scheduled task '$taskName' created successfully!" -ForegroundColor Green

# Start the task immediately for testing
Write-Host "Starting the task for immediate testing..." -ForegroundColor Cyan
Start-ScheduledTask -TaskName $taskName

# Wait a moment and check status
Start-Sleep -Seconds 3
$taskInfo = Get-ScheduledTask -TaskName $taskName
Write-Host "Task Status: $($taskInfo.State)" -ForegroundColor $(if ($taskInfo.State -eq 'Running') { 'Green' } else { 'Yellow' })

Write-Host "`n📋 Task Management Commands:" -ForegroundColor Blue
Write-Host "Start:  Start-ScheduledTask -TaskName '$taskName'" -ForegroundColor White
Write-Host "Stop:   Stop-ScheduledTask -TaskName '$taskName'" -ForegroundColor White
Write-Host "Status: Get-ScheduledTask -TaskName '$taskName' | Select-Object TaskName, State" -ForegroundColor White
Write-Host "Remove: Unregister-ScheduledTask -TaskName '$taskName' -Confirm:`$false" -ForegroundColor White

Write-Host "`n📁 Check logs at: $($logPath -replace [regex]::Escape($PSScriptRoot), '.')" -ForegroundColor Blue

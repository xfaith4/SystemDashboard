# Setup script to create scheduled tasks for permanent System Dashboard operation
# Run this script as Administrator to set up all services

param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Status
)

# Configuration
$Tasks = @(
    @{
        Name = "SystemDashboard-WebUI"
        Description = "System Dashboard Flask Web Interface"
        Script = "SystemDashboard-WebUI.ps1"
        Action = "start"
    }
)

$RootPath = $env:SYSTEMDASHBOARD_ROOT
if (-not $RootPath) {
    $RootPath = Split-Path -Parent $PSScriptRoot
}

$ServicesPath = Join-Path $RootPath "services"

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-DashboardTasks {
    if (-not (Test-Administrator)) {
        Write-Error "This script must be run as Administrator to create scheduled tasks"
        return
    }

    Write-Host "Installing System Dashboard scheduled tasks..." -ForegroundColor Green

    foreach ($task in $Tasks) {
        $taskName = $task.Name
        $scriptPath = Join-Path $ServicesPath $task.Script

        if (-not (Test-Path $scriptPath)) {
            Write-Warning "Script not found: $scriptPath"
            continue
        }

        # Remove existing task if it exists
        $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Host "Removing existing task: $taskName"
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        }

        # Create new task action
        $action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Action $($task.Action)"

        # Create trigger (start at boot, repeat every 5 minutes if stops)
        $trigger = New-ScheduledTaskTrigger -AtStartup

        # Create settings
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnDemand -DontStopIfGoingOnBatteries -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Hours 0) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)

        # Create principal (run as SYSTEM)
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

        # Register the task
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description $task.Description

        Write-Host "Created scheduled task: $taskName" -ForegroundColor Green

        # Start the task
        Start-ScheduledTask -TaskName $taskName
        Write-Host "Started task: $taskName" -ForegroundColor Green
    }

    Write-Host "`nAll System Dashboard services have been installed and started!" -ForegroundColor Green
    Write-Host "Services will automatically start when Windows boots." -ForegroundColor Green
}

function Uninstall-DashboardTasks {
    if (-not (Test-Administrator)) {
        Write-Error "This script must be run as Administrator to remove scheduled tasks"
        return
    }

    Write-Host "Uninstalling System Dashboard scheduled tasks..." -ForegroundColor Yellow

    foreach ($task in $Tasks) {
        $taskName = $task.Name

        $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Host "Removing task: $taskName"
            Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            Write-Host "Removed task: $taskName" -ForegroundColor Yellow
        } else {
            Write-Host "Task not found: $taskName"
        }
    }

    # Also remove the telemetry task
    $telemetryTask = Get-ScheduledTask -TaskName "SystemDashboard-Telemetry" -ErrorAction SilentlyContinue
    if ($telemetryTask) {
        Write-Host "Removing telemetry task: SystemDashboard-Telemetry"
        Stop-ScheduledTask -TaskName "SystemDashboard-Telemetry" -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName "SystemDashboard-Telemetry" -Confirm:$false
        Write-Host "Removed task: SystemDashboard-Telemetry" -ForegroundColor Yellow
    }

    Write-Host "`nAll System Dashboard services have been uninstalled." -ForegroundColor Yellow
}

function Show-DashboardStatus {
    Write-Host "System Dashboard Service Status:" -ForegroundColor Cyan
    Write-Host "=================================" -ForegroundColor Cyan

    # Check PostgreSQL container
    Write-Host "`n📊 Database (PostgreSQL):" -ForegroundColor White
    try {
        $container = docker ps --filter name=postgres-container --format "{{.Status}}"
        if ($container) {
            Write-Host "  ✅ Running: $container" -ForegroundColor Green
        } else {
            Write-Host "  ❌ Not running" -ForegroundColor Red
        }
    } catch {
        Write-Host "  ❌ Docker not available" -ForegroundColor Red
    }

    # Check scheduled tasks
    Write-Host "`n🔄 Scheduled Tasks:" -ForegroundColor White

    $allTasks = @("SystemDashboard-Telemetry") + ($Tasks | ForEach-Object { $_.Name })

    foreach ($taskName in $allTasks) {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($task) {
            $status = $task.State
            $icon = if ($status -eq "Running") { "✅" } else { "⚠️" }
            Write-Host "  $icon $taskName`: $status" -ForegroundColor $(if ($status -eq "Running") { "Green" } else { "Yellow" })
        } else {
            Write-Host "  ❌ $taskName`: Not installed" -ForegroundColor Red
        }
    }

    # Check web interface
    Write-Host "`n🌐 Web Interface:" -ForegroundColor White
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:5000/health" -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200) {
            Write-Host "  ✅ Available at http://localhost:5000" -ForegroundColor Green
        } else {
            Write-Host "  ⚠️ Responding but unhealthy (Status: $($response.StatusCode))" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  ❌ Not responding at http://localhost:5000" -ForegroundColor Red
    }

    Write-Host ""
}

# Main execution
if ($Install) {
    Install-DashboardTasks
} elseif ($Uninstall) {
    Uninstall-DashboardTasks
} elseif ($Status) {
    Show-DashboardStatus
} else {
    Write-Host "System Dashboard Service Manager" -ForegroundColor Cyan
    Write-Host "Usage:"
    Write-Host "  setup-permanent-services.ps1 -Install   # Install all services"
    Write-Host "  setup-permanent-services.ps1 -Uninstall # Remove all services"
    Write-Host "  setup-permanent-services.ps1 -Status    # Show service status"
    Write-Host ""
    Write-Host "Current status:"
    Show-DashboardStatus
}

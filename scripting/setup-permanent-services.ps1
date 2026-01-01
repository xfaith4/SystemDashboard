# Setup script to create scheduled tasks for permanent System Dashboard operation
# Run this script as Administrator to set up all services

param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Status
)

$RootPath = $env:SYSTEMDASHBOARD_ROOT
$scriptRoot = Split-Path -Parent $PSScriptRoot
if (-not $RootPath -or -not (Test-Path (Join-Path $RootPath "config.json"))) {
    $RootPath = $scriptRoot
} elseif ($RootPath -ne $scriptRoot -and (Test-Path (Join-Path $scriptRoot "config.json"))) {
    $RootPath = $scriptRoot
}

$ServicesPath = Join-Path $PSScriptRoot "services"

# Configuration
$Tasks = @(
    @{
        Name = "SystemDashboard-LegacyUI"
        Description = "System Dashboard Legacy UI Listener"
        Script = "SystemDashboard-LegacyUI.ps1"
        Action = "start"
        Args = "-ConfigPath `"$RootPath\\config.json`""
    },
    @{
        Name = "SystemDashboard-LANCollector"
        Description = "System Dashboard LAN Collector"
        Script = "LanCollectorService.ps1"
        Action = $null
        Args = "-ConfigPath `"$RootPath\\config.json`""
    },
    @{
        Name = "SystemDashboard-SyslogCollector"
        Description = "System Dashboard Syslog Collector"
        Script = "SyslogCollectorService.ps1"
        Action = $null
        Args = "-ConfigPath `"$RootPath\\config.json`""
    }
)

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

    $depsScript = Join-Path $PSScriptRoot 'setup-lan-collector-deps.ps1'
    if (Test-Path -LiteralPath $depsScript) {
        try {
            Write-Host "Ensuring LAN collector dependencies..." -ForegroundColor Cyan
            & $depsScript
        }
        catch {
            Write-Warning "LAN collector dependency setup failed: $($_.Exception.Message)"
        }
    }

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
        $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        if ($task.Action) {
            $argList += " -Action $($task.Action)"
        }
        if ($task.Args) {
            $argList += " $($task.Args)"
        }
        $action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument $argList

        # Create trigger (start at boot, repeat every 5 minutes if stops)
        $trigger = New-ScheduledTaskTrigger -AtStartup

        # Create settings (use flags available on older Windows builds)
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Hours 0) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)

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

    $configPath = Join-Path $RootPath "config.json"
    $config = $null
    if (Test-Path $configPath) {
        try {
            $config = Get-Content $configPath -Raw | ConvertFrom-Json
        } catch {
            $config = $null
        }
    }

    $dbHost = if ($config?.Database?.Host) { $config.Database.Host } else { "localhost" }
    $dbPort = if ($config?.Database?.Port) { $config.Database.Port } else { 5432 }

    # Check PostgreSQL connectivity
    Write-Host "`n📊 Database (PostgreSQL):" -ForegroundColor White
    try {
        $test = Test-NetConnection -ComputerName $dbHost -Port $dbPort -WarningAction SilentlyContinue
        if ($test.TcpTestSucceeded) {
            Write-Host "  ✅ Reachable: $dbHost`:$dbPort" -ForegroundColor Green
        } else {
            Write-Host "  ❌ Unreachable: $dbHost`:$dbPort" -ForegroundColor Red
        }
    } catch {
        Write-Host "  ❌ Connection check failed: $($_.Exception.Message)" -ForegroundColor Red
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
        $prefix = if ($config?.Prefix) { $config.Prefix } else { "http://localhost:15000/" }
        $response = Invoke-WebRequest -Uri $prefix -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
        if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400) {
            Write-Host "  ✅ Available at $prefix" -ForegroundColor Green
        } else {
            Write-Host "  ⚠️ Responding but unhealthy (Status: $($response.StatusCode))" -ForegroundColor Yellow
        }
    } catch {
        $prefix = if ($config?.Prefix) { $config.Prefix } else { "http://localhost:15000/" }
        Write-Host "  ❌ Not responding at $prefix" -ForegroundColor Red
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

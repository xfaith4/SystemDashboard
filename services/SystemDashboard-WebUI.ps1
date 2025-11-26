# SystemDashboard Web UI Service
# This script runs the Flask dashboard as a persistent service

param(
    [string]$Action = "start"
)

# Configuration
$TelemetryModulePath = Join-Path $PSScriptRoot "..\tools\SystemDashboard.Telemetry.psm1"
Import-Module $TelemetryModulePath -Force -Global


# Paths
$RootPath = $env:SYSTEMDASHBOARD_ROOT
if (-not $RootPath) {
    $RootPath = Split-Path -Parent $PSScriptRoot
}

$AppPath = Join-Path $RootPath "app"
# Use repository-level virtual environment created by Install.ps1
$VenvPath = Join-Path $RootPath ".venv"
$PythonExe = Join-Path $VenvPath "Scripts\python.exe"
$AppScript = Join-Path $AppPath "run_dashboard.py"
$LogPath = Join-Path $RootPath "var\log"

# Ensure log directory exists
if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

$LogFile = Join-Path $LogPath "webui-service.log"

function Write-ServiceLog {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $LogFile -Append -Encoding utf8
    Write-Host "$timestamp - $Message"
}

function Start-WebUIService {
    Write-ServiceLog "Starting System Dashboard Web UI..."

    # Load database configuration from config file
    $configPath = Join-Path $RootPath "config.json"
    if (Test-Path $configPath) {
        try {
            $config = Get-Content $configPath | ConvertFrom-Json
            Write-ServiceLog "Loaded configuration from: $configPath"
        } catch {
            Write-ServiceLog "WARNING: Failed to load config file: $($_.Exception.Message)"
            $config = $null
        }
    }

    # Set environment variables for Flask app
    $env:DASHBOARD_DB_HOST = if ($config.Database.Host) { $config.Database.Host } else { "localhost" }
    $env:DASHBOARD_DB_PORT = if ($config.Database.Port) { $config.Database.Port.ToString() } else { "5432" }
    $env:DASHBOARD_DB_NAME = if ($config.Database.Database) { $config.Database.Database } else { "system_dashboard" }
    $env:DASHBOARD_DB_USER = "sysdash_reader"  # Use read-only user for dashboard

    # Get the reader password - try multiple sources
    $readerPassword = $null
    if ($env:SYSTEMDASHBOARD_DB_READER_PASSWORD) {
        $readerPassword = $env:SYSTEMDASHBOARD_DB_READER_PASSWORD
        Write-ServiceLog "Using SYSTEMDASHBOARD_DB_READER_PASSWORD from environment"
    } elseif ($env:SYSTEMDASHBOARD_DB_PASSWORD) {
        # Fallback: If we can't find reader password, derive it from main password
        $readerPassword = $env:SYSTEMDASHBOARD_DB_PASSWORD -replace "123!", "456!"
        Write-ServiceLog "Derived reader password from main password"
    } else {
        # Last resort: use the known working password
        $readerPassword = "ReaderPassword456!"
        Write-ServiceLog "Using known working reader password"
    }

    $env:DASHBOARD_DB_PASSWORD = $readerPassword
    # Allow caller to override; default to 5001
    if (-not $env:DASHBOARD_PORT) { $env:DASHBOARD_PORT = "5001" }
    $env:FLASK_ENV = "production"

    Write-ServiceLog "Database config: Host=$($env:DASHBOARD_DB_HOST), Port=$($env:DASHBOARD_DB_PORT), DB=$($env:DASHBOARD_DB_NAME), User=$($env:DASHBOARD_DB_USER)"    # Verify prerequisites
    if (-not (Test-Path $PythonExe)) {
        Write-ServiceLog "ERROR: Python virtual environment not found at $VenvPath"
        exit 1
    }

    if (-not (Test-Path $AppScript)) {
        Write-ServiceLog "ERROR: Flask app not found at $AppScript"
        exit 1
    }

    # Change to app directory
    Set-Location $AppPath

    Write-ServiceLog "Starting Flask application..."
    Write-ServiceLog "Python: $PythonExe"
    Write-ServiceLog "App: $AppScript"
    Write-ServiceLog "Working Directory: $AppPath"

    try {
        # Start Flask app
        & $PythonExe $AppScript 2>&1 | ForEach-Object {
            Write-ServiceLog "Flask: $_"
        }
    }
    catch {
        Write-ServiceLog "ERROR: Failed to start Flask app: $($_.Exception.Message)"
        exit 1
    }
}

function Stop-WebUIService {
    Write-ServiceLog "Stopping System Dashboard Web UI..."

    # Find and stop any running Flask processes
    Get-Process | Where-Object {
        $_.ProcessName -eq "python" -and
        $_.CommandLine -like "*app.py*"
    } | ForEach-Object {
        Write-ServiceLog "Stopping Flask process (PID: $($_.Id))"
        Stop-Process -Id $_.Id -Force
    }

    Write-ServiceLog "Web UI service stopped"
}

function Get-WebUIStatus {
    $processes = Get-Process | Where-Object {
        $_.ProcessName -eq "python" -and
        $_.CommandLine -like "*app.py*"
    }

    if ($processes) {
        Write-ServiceLog "Web UI is running (PID: $($processes[0].Id))"
        return $true
    } else {
        Write-ServiceLog "Web UI is not running"
        return $false
    }
}

# Main execution
switch ($Action.ToLower()) {
    "start" {
        Start-WebUIService
    }
    "stop" {
        Stop-WebUIService
    }
    "restart" {
        Stop-WebUIService
        Start-Sleep -Seconds 2
        Start-WebUIService
    }
    "status" {
        Get-WebUIStatus
    }
    default {
        Write-Host "Usage: $($MyInvocation.MyCommand.Name) -Action [start|stop|restart|status]"
        exit 1
    }
}

# SystemDashboard Legacy UI Service
# Runs the legacy PowerShell dashboard listener as a persistent process

param(
    [string]$Action = "start",
    [string]$ConfigPath = (Join-Path $PSScriptRoot "..\..\config.json")
)

$RootPath = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
$LogDir = Join-Path $RootPath "var\log"
$RunDir = Join-Path $RootPath "var\run"
$LogFile = Join-Path $LogDir "dashboard-ui.log"
$PidFile = Join-Path $RunDir "dashboard-legacy.pid"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
if (-not (Test-Path $RunDir)) {
    New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
}

function Write-ServiceLog {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $LogFile -Append -Encoding utf8
    Write-Host "$timestamp - $Message"
}

function Get-DashboardProcess {
    if (-not (Test-Path $PidFile)) {
        return $null
    }
    $pid = Get-Content -LiteralPath $PidFile -ErrorAction SilentlyContinue
    if (-not $pid) { return $null }
    return Get-Process -Id $pid -ErrorAction SilentlyContinue
}

function Start-DashboardService {
    $existing = Get-DashboardProcess
    if ($existing) {
        Write-ServiceLog "Dashboard already running (PID: $($existing.Id))"
        return
    }

    $defaultConfig = Join-Path $RootPath "config.json"
    $resolvedConfig = $ConfigPath

    if (-not (Test-Path -LiteralPath $resolvedConfig)) {
        $resolvedConfig = $defaultConfig
    }

    if (-not (Test-Path -LiteralPath $resolvedConfig)) {
        Write-ServiceLog "ERROR: Config not found at $resolvedConfig"
        exit 1
    }

    try {
        $cfg = Get-Content -LiteralPath $resolvedConfig -Raw | ConvertFrom-Json
        $hasDatabase = $cfg.PSObject.Properties.Name -contains 'Database'
        if (-not $hasDatabase) {
            $resolvedConfig = $defaultConfig
        }
    }
    catch {
        $resolvedConfig = $defaultConfig
    }

    if (-not (Test-Path -LiteralPath $resolvedConfig)) {
        Write-ServiceLog "ERROR: Config not found at $resolvedConfig"
        exit 1
    }

    $env:SYSTEMDASHBOARD_ROOT = $RootPath
    $env:SYSTEMDASHBOARD_CONFIG = $resolvedConfig

    Write-ServiceLog "Starting legacy dashboard listener..."
    Write-ServiceLog "Config: $resolvedConfig"
    try {
        Set-Content -LiteralPath $PidFile -Value $PID -Encoding ascii
        & (Join-Path $RootPath 'Start-SystemDashboard.ps1') -Mode Legacy -ConfigPath $resolvedConfig -SkipPreflight -SkipDatabaseCheck -SkipInstall
    }
    catch {
        Write-ServiceLog "ERROR: Legacy dashboard failed: $($_.Exception.Message)"
        exit 1
    }
    finally {
        Remove-Item -LiteralPath $PidFile -ErrorAction SilentlyContinue
    }
}

function Stop-DashboardService {
    $proc = Get-DashboardProcess
    if ($proc) {
        Write-ServiceLog "Stopping legacy dashboard (PID: $($proc.Id))"
        Stop-Process -Id $proc.Id -Force
    }
    if (Test-Path $PidFile) {
        Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-DashboardStatus {
    $proc = Get-DashboardProcess
    if ($proc) {
        Write-ServiceLog "Legacy dashboard running (PID: $($proc.Id))"
        return $true
    }
    Write-ServiceLog "Legacy dashboard not running"
    return $false
}

switch ($Action.ToLower()) {
    "start" { Start-DashboardService }
    "stop" { Stop-DashboardService }
    "restart" {
        Stop-DashboardService
        Start-Sleep -Seconds 2
        Start-DashboardService
    }
    "status" { Get-DashboardStatus }
    default {
        Write-Host "Usage: $($MyInvocation.MyCommand.Name) -Action [start|stop|restart|status]"
        exit 1
    }
}

# SystemDashboard Legacy UI Service
# Runs the legacy PowerShell dashboard listener as a persistent process

param(
    [string]$Action = "start",
    [string]$ConfigPath = (Join-Path $PSScriptRoot "..\..\config.json")
)

$RootPath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
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
    $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
    if (-not $proc) {
        return $null
    }

    $scriptPath = (Resolve-Path -LiteralPath $PSCommandPath).Path
    try {
        $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $pid" -ErrorAction SilentlyContinue
        $cmdLine = $processInfo.CommandLine
        if ($cmdLine -and ($cmdLine -match [regex]::Escape($scriptPath) -or $cmdLine -match 'SystemDashboard-LegacyUI\.ps1')) {
            return $proc
        }
    }
    catch {
        # Fall back to trusting the PID if we can't inspect the command line.
        return $proc
    }

    Write-ServiceLog "Stale PID file detected (PID: $pid); removing."
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    return $null
}

function Test-DashboardHealth {
    param([string]$ConfigPath)

    $prefix = 'http://localhost:15000/'
    if ($ConfigPath -and (Test-Path -LiteralPath $ConfigPath)) {
        try {
            $cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
            if ($cfg.Prefix) {
                $prefix = [string]$cfg.Prefix
            }
        }
        catch {
            # Keep default
        }
    }

    $url = ($prefix.TrimEnd('/') + '/metrics')
    try {
        $response = Invoke-WebRequest -Uri $url -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
        return ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400)
    }
    catch {
        return $false
    }
}

function Start-DashboardService {
    $existing = Get-DashboardProcess
    if ($existing) {
        if (Test-DashboardHealth -ConfigPath $ConfigPath) {
            Write-ServiceLog "Dashboard already running (PID: $($existing.Id))"
            return
        }
        Write-ServiceLog "Stale dashboard process detected (PID: $($existing.Id)); restarting."
        Stop-Process -Id $existing.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }

    $defaultConfig = Join-Path $RootPath "config.json"
    $resolvedConfig = $ConfigPath

    if ($resolvedConfig -and (Test-Path -LiteralPath $resolvedConfig)) {
        $resolvedConfig = (Resolve-Path -LiteralPath $resolvedConfig).Path
    } else {
        $resolvedConfig = $defaultConfig
    }

    if ($resolvedConfig -and (-not ($resolvedConfig.StartsWith($RootPath, [System.StringComparison]::OrdinalIgnoreCase)))) {
        Write-ServiceLog "WARNING: Ignoring config outside repo root: $resolvedConfig"
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

    $autoHealScript = Join-Path $RootPath 'scripting\auto-heal.ps1'
    if (Test-Path -LiteralPath $autoHealScript) {
        try {
            $enabled = $env:SYSTEMDASHBOARD_AUTOHEAL_ENABLED
            if (-not $enabled -or $enabled.ToLower() -notin @('0','false','no')) {
                Write-ServiceLog "Launching auto-heal check..."
                Start-Process -FilePath 'pwsh.exe' -ArgumentList @(
                    '-NoProfile',
                    '-File',
                    $autoHealScript,
                    '-ConfigPath',
                    $resolvedConfig
                ) -WindowStyle Hidden | Out-Null
            }
        } catch {
            Write-ServiceLog "WARNING: Auto-heal launch failed: $($_.Exception.Message)"
        }
    }

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

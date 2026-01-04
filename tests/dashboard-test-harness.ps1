#requires -Version 7
<#
.SYNOPSIS
Runs a lightweight smoke test for the SystemDashboard stack.

.DESCRIPTION
This harness verifies the scheduled tasks, starts a temporary legacy listener,
pulls the dashboard HTML, and samples the logs for known keywords so you can
catch choreography issues before manual testing.

.NOTES
Run from the repo root (or adjust `$RepoRoot` below) with an elevated session.
#>

param(
    [string]$ConfigPath = (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\config.local.json'),
    [string]$ListenerMode = 'Legacy',
    [string]$ListenerUrl = 'http://localhost:15000/',
    [string]$DashboardUrl = 'http://localhost:15000/',
    [string[]]$ScheduledTasks = @(
        'SystemDashboard-Telemetry',
        'SystemDashboard-LegacyUI',
        'SystemDashboard-SyslogCollector',
        'SystemDashboard-LANCollector',
        'SystemDashboard-WebUI'
    )
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $ScriptDir '..')).Path
$ListenerScript = Join-Path $RepoRoot 'Start-SystemDashboard.ps1'
$LogDir = Join-Path $RepoRoot 'var\log'
$StatusEndpoint = ("{0}/api/status" -f $ListenerUrl.TrimEnd('/'))

if (-not (Test-Path -LiteralPath $ListenerScript)) {
    throw "Listener entrypoint not found: $ListenerScript"
}

function Test-ScheduledTaskAlive {
    param([string]$Name)
    try {
        Get-ScheduledTask -TaskName $Name -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Restart-ScheduledTaskIfNeeded {
    param([string]$Name)
    Write-Host "Checking scheduled task $Name"
    if (-not (Test-ScheduledTaskAlive -Name $Name)) {
        Write-Warning "$Name not registered; skipping."
        return
    }
    try {
        Stop-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    } catch {}
    Start-ScheduledTask -TaskName $Name
    Start-Sleep -Seconds 2
    $state = (Get-ScheduledTaskInfo -TaskName $Name).State
    Write-Host "  -> state: $state"
}

function Sample-Log {
    param(
        [string]$Path,
        [int]$Lines = 12
    )
    if (-not (Test-Path $Path)) {
        return @()
    }
    return Get-Content -Last $Lines -Path $Path
}

function Start-ListenerProcess {
    $args = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $ListenerScript,
        '-Mode',
        $ListenerMode,
        '-ConfigPath',
        $ConfigPath
    )
    $process = Start-Process -FilePath 'pwsh' -ArgumentList $args -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 6
    return $process
}

function Stop-ListenerProcess {
    param([System.Diagnostics.Process]$Process)
    if ($Process -and -not $Process.HasExited) {
        try {
            $Process | Stop-Process -Force
        } catch {}
    }
}

Write-Host "=== Dashboard Test Harness ==="
foreach ($task in $ScheduledTasks) {
    Restart-ScheduledTaskIfNeeded -Name $task
}

$listenerProc = $null
try {
    Write-Host "Starting temporary listener process..."
    $listenerProc = Start-ListenerProcess
    try {
        $dashboardHtml = Invoke-WebRequest -Uri $DashboardUrl -UseBasicParsing -TimeoutSec 10
        if ($dashboardHtml.StatusCode -eq 200) {
            Write-Host "Dashboard HTML fetched successfully."
            if ($dashboardHtml.Content -match '<title>System Dashboard') {
                Write-Host "Title verified."
            } else {
                Write-Warning "Unexpected dashboard title."
            }
        } else {
            Write-Warning "Dashboard responded with status $($dashboardHtml.StatusCode)"
        }
    } catch {
        Write-Warning "Failed to fetch dashboard HTML: $_"
    }
    $timeout = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $timeout) {
        try {
            $status = Invoke-WebRequest -Uri $StatusEndpoint -UseBasicParsing -TimeoutSec 5
        } catch {
            Start-Sleep -Seconds 2
            continue
        }
        if ($status.StatusCode -eq 200) {
            $payload = $status.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($payload -and $payload.ok) {
                Write-Host "Listener status OK."
                break
            }
        }
        Start-Sleep -Seconds 2
    }
} catch {
    Write-Warning "Listener validation failed: $_"
} finally {
    Stop-ListenerProcess -Process $listenerProc
}

Write-Host "Sampling logs"
$logFiles = @(
    Join-Path $LogDir 'dashboard-listener.log',
    Join-Path $LogDir 'dashboard-ui.log',
    Join-Path $LogDir 'lan-collector.log'
)
foreach ($log in $logFiles) {
    Write-Host "=== $log ==="
    Sample-Log -Path $log -Lines 15 | ForEach-Object { Write-Host "  $_" }
}

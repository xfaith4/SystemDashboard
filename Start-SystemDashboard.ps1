#requires -Version 7
[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'),
    [ValidateSet('Unified','Legacy','Flask')]
    [string]$Mode = 'Unified',
    [ValidateSet('postgres','docker','skip')]
    [string]$DatabaseMode = 'postgres',
    [switch]$SkipInstall,
    [switch]$SkipDatabaseCheck,
    [switch]$SkipPreflight,
    [switch]$SkipLaunch,
    [switch]$RestartTasks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$scriptingRoot = Join-Path $repoRoot 'scripting'
$scriptingModule = Join-Path $scriptingRoot 'SystemDashboard.Scripting.psm1'
if (-not (Test-Path -LiteralPath $scriptingModule)) {
    throw "Scripting module not found at $scriptingModule"
}
Import-Module $scriptingModule -Force

if (-not $env:SYSTEMDASHBOARD_ROOT) {
    $env:SYSTEMDASHBOARD_ROOT = $repoRoot
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-PythonExe {
    param([string]$RepoRoot)

    $venvPath = Join-Path $RepoRoot '.venv'
    $venvPython = if ($IsWindows) {
        Join-Path $venvPath 'Scripts\python.exe'
    } else {
        Join-Path $venvPath 'bin/python'
    }

    if (Test-Path -LiteralPath $venvPython) {
        return $venvPython
    }

    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $cmd = Get-Command python3 -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    return $null
}

function Load-DbSecrets {
    param([string]$RepoRoot)

    $connectionFile = Join-Path $RepoRoot 'var\database-connection.json'
    if (-not (Test-Path -LiteralPath $connectionFile)) {
        return
    }

    try {
        $connectionInfo = Get-Content -LiteralPath $connectionFile -Raw | ConvertFrom-Json
    } catch {
        Write-Warning "Failed to read database connection info from $connectionFile"
        return
    }

    if ($connectionInfo.IngestPassword) {
        $env:SYSTEMDASHBOARD_DB_PASSWORD = $connectionInfo.IngestPassword
    }

    if ($connectionInfo.ReaderPassword) {
        $env:SYSTEMDASHBOARD_DB_READER_PASSWORD = $connectionInfo.ReaderPassword
    }
}

function Set-DashboardDbEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ConfigPath
    )

    try {
        $cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    } catch {
        Write-Warning "Failed to parse config file at $ConfigPath. $_"
        return
    }

    $db = $cfg.Database
    if (-not $db) {
        return
    }

    $env:DASHBOARD_DB_HOST = if ($db.Host) { [string]$db.Host } else { 'localhost' }
    $env:DASHBOARD_DB_PORT = [string]($db.Port ?? 5432)
    $env:DASHBOARD_DB_NAME = if ($db.Database) { [string]$db.Database } else { 'system_dashboard' }
    $env:DASHBOARD_DB_USER = 'sysdash_reader'

    $readerPassword = $env:SYSTEMDASHBOARD_DB_READER_PASSWORD
    if (-not $readerPassword) {
        if ($env:SYSTEMDASHBOARD_DB_PASSWORD) {
            Write-Warning "SYSTEMDASHBOARD_DB_READER_PASSWORD is not set; falling back to SYSTEMDASHBOARD_DB_PASSWORD (may not work for reader user)."
            Write-Host "SYSTEMDASHBOARD_DB_READER_PASSWORD is not set; falling back to SYSTEMDASHBOARD_DB_PASSWORD (may not work for reader user)."
            $readerPassword = $env:SYSTEMDASHBOARD_DB_PASSWORD
        }
    }

    if ($readerPassword) {
        $env:DASHBOARD_DB_PASSWORD = $readerPassword
    }
}

function Restart-SystemDashboardTasks {
    $tasks = @('SystemDashboard-Telemetry', 'SystemDashboard-LegacyUI')
    foreach ($task in $tasks) {
        try {
            $taskInfo = Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
            if (-not $taskInfo) {
                continue
            }
            if ($taskInfo.State -eq 'Running') {
                Write-Host "Stopping scheduled task $task..." -ForegroundColor Yellow
                Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
            Write-Host "Starting scheduled task $task..." -ForegroundColor Yellow
            Start-ScheduledTask -TaskName $task
        } catch {
            Write-Warning "Failed to restart scheduled task $($task): $($_.Exception.Message)"
            Write-Host "Failed to restart scheduled task $($task): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config file not found at $ConfigPath"
}

$ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
$env:SYSTEMDASHBOARD_CONFIG = $ConfigPath

if (-not $SkipPreflight) {
    if ($IsWindows -and -not (Test-Administrator)) {
        throw "Start-SystemDashboard.ps1 must run in an elevated PowerShell session."
    }

    Load-DbSecrets -RepoRoot $repoRoot
    Set-DashboardDbEnvironment -ConfigPath $ConfigPath

    if (-not $SkipInstall) {
        $pythonExe = Resolve-PythonExe -RepoRoot $repoRoot
        if (-not $pythonExe) {
            throw "Python is required to install dependencies and run health checks."
        }

        $venvPython = if ($IsWindows) {
            Join-Path $repoRoot '.venv\Scripts\python.exe'
        } else {
            Join-Path $repoRoot '.venv/bin/python'
        }

        if (-not (Test-Path -LiteralPath $venvPython)) {
            Write-Host "🔧 Installing dependencies..." -ForegroundColor Cyan
            Install-SystemDashboard -ConfigPath $ConfigPath
        }
    }

    if (-not $SkipDatabaseCheck) {
        $pythonExe = Resolve-PythonExe -RepoRoot $repoRoot
        if (-not $pythonExe) {
            throw "Python is required to verify database connectivity."
        }

        $dbTest = Join-Path $repoRoot 'app\test_db_connection.py'
        if (-not (Test-Path -LiteralPath $dbTest)) {
            throw "Database test script not found at $dbTest"
        }

        Write-Host "🔍 Verifying database connectivity..." -ForegroundColor Cyan
        & $pythonExe $dbTest
        if ($LASTEXITCODE -ne 0 -and $DatabaseMode -ne 'skip') {
            Write-Host "⚙️  Database check failed; attempting setup via $DatabaseMode..." -ForegroundColor Yellow
            if ($DatabaseMode -eq 'docker') {
                Initialize-SystemDashboardDockerDatabase
            }
            else {
                Initialize-SystemDashboardDatabase
            }

            Write-Host "🔁 Re-checking database connectivity..." -ForegroundColor Cyan
            & $pythonExe $dbTest
            if ($LASTEXITCODE -ne 0) {
                throw "Database connectivity check still failing. Review the output above."
            }
        }
        elseif ($LASTEXITCODE -ne 0) {
            throw "Database connectivity check failed. Use -DatabaseMode postgres|docker to attempt setup."
        }
    }
}

if ($SkipLaunch) {
    Write-Host "✅ Preflight complete. Launch skipped by request." -ForegroundColor Green
    return
}

if ($RestartTasks) {
    if ($IsWindows -and -not (Test-Administrator)) {
        Write-Warning "Restarting scheduled tasks may require an elevated session."
    }
    Restart-SystemDashboardTasks
}

switch ($Mode) {
    'Unified' {
        $entry = Join-Path $scriptingRoot 'Start-SystemDashboard.Unified.ps1'
        if (-not (Test-Path -LiteralPath $entry)) {
            throw "Unified entrypoint not found at $entry"
        }
        try {
            if ($PSBoundParameters.ContainsKey('ConfigPath')) {
                Write-Warning "Unified mode expects the 2025-09-11 config schema; you passed -ConfigPath, so ensure it's compatible."
                Write-Host "Unified mode expects the 2025-09-11 config schema; you passed -ConfigPath, so ensure it's compatible."
                & $entry -ConfigPath $ConfigPath
            }
            else {
                & $entry
            }
        }
        catch {
            Write-Warning "Unified mode failed to start. This is commonly caused by missing dependencies (ex: the 'Pode' PowerShell module)."
            Write-Warning "To run the Postgres-backed dashboard in this repo, use: pwsh -NoProfile -File .\\Start-SystemDashboard.ps1 -Mode Legacy"
            Write-Warning "To run the Flask dashboard directly, use: pwsh -NoProfile -File .\\Start-SystemDashboard.ps1 -Mode Flask"
            Write-Host "Unified mode failed to start. This is commonly caused by missing dependencies (ex: the 'Pode' PowerShell module)."

            if (-not $PSBoundParameters.ContainsKey('Mode')) {
                Write-Warning "Falling back to Legacy mode (because -Mode was not explicitly provided)."
                $modulePath = Join-Path $repoRoot 'Start-SystemDashboard.psm1'
                if (-not (Get-Module -Name 'Start-SystemDashboard' -ErrorAction SilentlyContinue)) {
                    Import-Module $modulePath -Force
                }
                Start-SystemDashboard -ConfigPath $ConfigPath
                break
            }

            throw
        }
    }
    'Legacy' {
        $modulePath = Join-Path $repoRoot 'Start-SystemDashboard.psm1'
        if (-not (Get-Module -Name 'Start-SystemDashboard' -ErrorAction SilentlyContinue)) {
            Import-Module $modulePath -Force
        }
        Start-SystemDashboard -ConfigPath $ConfigPath
    }
    'Flask' {
        $pythonExe = Resolve-PythonExe -RepoRoot $repoRoot
        if (-not $pythonExe) {
            throw "Python is required to run the Flask dashboard."
        }
        & $pythonExe (Join-Path $repoRoot 'app\app.py')
    }
    default {
        throw "Unknown mode: $Mode"
    }
}

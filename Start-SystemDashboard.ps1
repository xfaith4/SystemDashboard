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
    [switch]$SkipLaunch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$scriptingRoot = Join-Path $repoRoot 'scripting'

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
            $installScript = Join-Path $scriptingRoot 'Install.ps1'
            if (-not (Test-Path -LiteralPath $installScript)) {
                throw "Install script not found at $installScript"
            }

            Write-Host "🔧 Installing dependencies..." -ForegroundColor Cyan
            & $installScript -ConfigPath $ConfigPath
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
            $dbScript = if ($DatabaseMode -eq 'docker') {
                Join-Path $scriptingRoot 'setup-database-docker.ps1'
            } else {
                Join-Path $scriptingRoot 'setup-database.ps1'
            }

            if (-not (Test-Path -LiteralPath $dbScript)) {
                throw "Database setup script not found at $dbScript"
            }

            Write-Host "⚙️  Database check failed; attempting setup via $DatabaseMode..." -ForegroundColor Yellow
            & $dbScript

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

switch ($Mode) {
    'Unified' {
        $entry = Join-Path $scriptingRoot 'Start-SystemDashboard.Unified.ps1'
        if (-not (Test-Path -LiteralPath $entry)) {
            throw "Unified entrypoint not found at $entry"
        }
        & $entry -ConfigPath $ConfigPath
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

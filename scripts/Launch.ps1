#!/usr/bin/env pwsh
<#
.SYNOPSIS
Orchestrate repository root scripts from a single entry point.
.DESCRIPTION
This helper runs the existing root-level PowerShell helpers in a dependable order so you can bootstrap the database,
install the telemetry service, and register supporting scheduled tasks from one command. It also exposes knobs for
container-based databases, LAN schema forcefully re-applied, and stage picking for custom workflows.
#>

param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('Environment','Database','Install','PermanentServices','ScheduledTask','LanSchema')]
    [string[]]
    $Stages = @('Environment','Database','Install','PermanentServices','ScheduledTask','LanSchema'),

    [ValidateSet('postgres','docker')]
    [string]
    $DatabaseMode = 'postgres',

    [string[]]
    $DatabaseArgs = @(),

    [string[]]
    $InstallArgs = @(),

    [ValidateSet('Install','Uninstall','Status')]
    [string]
    $PermanentServicesAction = 'Install',

    [string[]]
    $ScheduledTaskArgs = @(),

    [switch]
    $ForceLanSchema,

    [string]
    $LanConfigPath,

    [string[]]
    $LanArgs = @(),

    [switch]
    $EnvironmentPermanent
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$LaunchRoot = $PSScriptRoot

function Get-ScriptPath {
    param([string]$RelativePath)

    $absolute = Join-Path -Path $LaunchRoot -ChildPath $RelativePath
    if (-not (Test-Path $absolute)) {
        throw "Script not found: $RelativePath"
    }

    return $absolute
}

function Invoke-Stage {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    Write-Host "`n=== Stage: $Name ===" -ForegroundColor Cyan
    try {
        & $Action
        Write-Host "✅ Completed stage: $Name" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Stage $Name failed: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

function Run-Environment {
    $scriptPath = Get-ScriptPath 'setup-environment.ps1'
    $scriptArgs = @()
    if ($EnvironmentPermanent) {
        $scriptArgs += '-Permanent'
    }

    Write-Host 'Running setup-environment.ps1' -ForegroundColor Yellow
    . $scriptPath @scriptArgs
}

function Run-Database {
    $scriptName = if ($DatabaseMode -eq 'docker') { 'setup-database-docker.ps1' } else { 'setup-database.ps1' }
    $scriptPath = Get-ScriptPath $scriptName
    $scriptArgs = @()
    if ($DatabaseArgs) {
        $scriptArgs += $DatabaseArgs
    }

    Write-Host ("Running {0}" -f $scriptName) -ForegroundColor Yellow
    & $scriptPath @scriptArgs
}

function Run-Install {
    $scriptPath = Get-ScriptPath 'Install.ps1'
    $args = @()
    if ($InstallArgs) {
        $args += $InstallArgs
    }

    Write-Host 'Running Install.ps1' -ForegroundColor Yellow
    & $scriptPath @args
}

function Run-PermanentServices {
    $scriptPath = Get-ScriptPath 'setup-permanent-services.ps1'
    $args = @("-$PermanentServicesAction")

    Write-Host ("Running setup-permanent-services.ps1 -{0}" -f $PermanentServicesAction) -ForegroundColor Yellow
    & $scriptPath @args
}

function Run-ScheduledTask {
    $scriptPath = Get-ScriptPath 'setup-scheduled-task.ps1'
    $args = @()
    if ($ScheduledTaskArgs) {
        $args += $ScheduledTaskArgs
    }

    Write-Host 'Running setup-scheduled-task.ps1' -ForegroundColor Yellow
    & $scriptPath @args
}

function Run-LanSchema {
    $scriptPath = Get-ScriptPath 'apply-lan-schema.ps1'
    $args = @()
    if ($LanConfigPath) {
        $args += '-ConfigPath'
        $args += $LanConfigPath
    }

    if ($ForceLanSchema) {
        $args += '-Force'
    }

    if ($LanArgs) {
        $args += $LanArgs
    }

    Write-Host 'Running apply-lan-schema.ps1' -ForegroundColor Yellow
    & $scriptPath @args
}

$stageActions = [ordered]@{
    Environment        = { Run-Environment }
    Database           = { Run-Database }
    Install            = { Run-Install }
    PermanentServices  = { Run-PermanentServices }
    ScheduledTask      = { Run-ScheduledTask }
    LanSchema          = { Run-LanSchema }
}

Write-Host "Launching stages: $($Stages -join ', ')" -ForegroundColor Cyan
foreach ($stage in $Stages) {
    if (-not $stageActions.Contains($stage)) {
        Write-Host "⚠️  Unknown stage '$stage' skipped" -ForegroundColor Yellow
        continue
    }

    Invoke-Stage -Name $stage -Action $stageActions[$stage]
}

Write-Host "`n🎉 All requested stages completed."

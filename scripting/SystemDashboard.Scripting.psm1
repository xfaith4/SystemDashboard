Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-SystemDashboardScriptInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScriptName,
        [Parameter()][hashtable]$BoundParameters
    )

    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Script not found at $scriptPath"
    }

    if (-not $BoundParameters) {
        & $scriptPath
        return
    }

    & $scriptPath @BoundParameters
}

function Install-SystemDashboard {
    [CmdletBinding()]
    param(
        [string]$ModulePath = (Join-Path $env:ProgramFiles 'PowerShell/Modules/SystemDashboard'),
        [string]$ConfigPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config.json'),
        [string]$ServiceName = 'SystemDashboardTelemetry',
        [switch]$UseWindowsService
    )

    $args = @{}
    foreach ($kvp in $PSBoundParameters.GetEnumerator()) {
        $args[$kvp.Key] = $kvp.Value
    }
    Invoke-SystemDashboardScriptInternal -ScriptName 'Install.ps1' -BoundParameters $args
}

function Initialize-SystemDashboardDatabase {
    [CmdletBinding()]
    param(
        [string]$PostgreSQLPath,
        [string]$DatabaseName = "system_dashboard",
        [string]$AdminUser = "postgres",
        [string]$IngestUser = "sysdash_ingest",
        [string]$ReaderUser = "sysdash_reader",
        [string]$DatabaseHost = "localhost",
        [int]$Port = 5432
    )

    $args = @{}
    foreach ($kvp in $PSBoundParameters.GetEnumerator()) {
        $args[$kvp.Key] = $kvp.Value
    }
    Invoke-SystemDashboardScriptInternal -ScriptName 'setup-database.ps1' -BoundParameters $args
}

function Initialize-SystemDashboardDockerDatabase {
    [CmdletBinding()]
    param(
        [string]$ContainerName = "postgres-container",
        [string]$DatabaseName = "system_dashboard",
        [string]$AdminUser = "postgres",
        [string]$AdminPassword = "ChangeMe123!",
        [string]$IngestUser = "sysdash_ingest",
        [string]$ReaderUser = "sysdash_reader",
        [string]$DatabaseHost = "localhost",
        [int]$Port = 5432
    )

    $args = @{}
    foreach ($kvp in $PSBoundParameters.GetEnumerator()) {
        $args[$kvp.Key] = $kvp.Value
    }
    Invoke-SystemDashboardScriptInternal -ScriptName 'setup-database-docker.ps1' -BoundParameters $args
}

function Apply-SystemDashboardLanSchema {
    [CmdletBinding()]
    param(
        [string]$ConfigPath,
        [switch]$Force
    )

    $args = @{}
    foreach ($kvp in $PSBoundParameters.GetEnumerator()) {
        $args[$kvp.Key] = $kvp.Value
    }
    Invoke-SystemDashboardScriptInternal -ScriptName 'apply-lan-schema.ps1' -BoundParameters $args
}

function Ensure-SystemDashboardLanDependencies {
    [CmdletBinding()]
    param(
        [string]$Destination = (Join-Path $PSScriptRoot '..\lib'),
        [string]$NpgsqlVersion = '8.0.3',
        [string]$LoggingVersion = '8.0.0',
        [string]$DiagnosticSourceVersion = '8.0.0'
    )

    $args = @{}
    foreach ($kvp in $PSBoundParameters.GetEnumerator()) {
        $args[$kvp.Key] = $kvp.Value
    }
    Invoke-SystemDashboardScriptInternal -ScriptName 'setup-lan-collector-deps.ps1' -BoundParameters $args
}

function Install-SystemDashboardScheduledTask {
    [CmdletBinding()]
    param()

    Invoke-SystemDashboardScriptInternal -ScriptName 'setup-scheduled-task.ps1'
}

function Manage-SystemDashboardServices {
    [CmdletBinding()]
    param(
        [switch]$Install,
        [switch]$Uninstall,
        [switch]$Status
    )

    $args = @{}
    foreach ($kvp in $PSBoundParameters.GetEnumerator()) {
        $args[$kvp.Key] = $kvp.Value
    }
    Invoke-SystemDashboardScriptInternal -ScriptName 'setup-permanent-services.ps1' -BoundParameters $args
}

function Invoke-SystemDashboardControl {
    [CmdletBinding()]
    param(
        [string]$Action = "menu",
        [switch]$RouterMonitoring,
        [switch]$ContinuousEvents,
        [switch]$HealthMonitoring,
        [switch]$Maintenance
    )

    $args = @{}
    foreach ($kvp in $PSBoundParameters.GetEnumerator()) {
        $args[$kvp.Key] = $kvp.Value
    }
    Invoke-SystemDashboardScriptInternal -ScriptName 'dashboard-control.ps1' -BoundParameters $args
}

function Invoke-SystemDashboardAutoHeal {
    [CmdletBinding()]
    param(
        [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config.json'),
        [int]$StartupDelaySeconds = 10,
        [string]$HealthPath = '/api/health'
    )

    $args = @{}
    foreach ($kvp in $PSBoundParameters.GetEnumerator()) {
        $args[$kvp.Key] = $kvp.Value
    }
    Invoke-SystemDashboardScriptInternal -ScriptName 'auto-heal.ps1' -BoundParameters $args
}

function Test-SystemDashboardTelemetryDatabase {
    [CmdletBinding()]
    param(
        [string]$ConfigPath = (Join-Path $PSScriptRoot '..' 'config.json'),
        [int]$Tail = 20
    )

    $args = @{}
    foreach ($kvp in $PSBoundParameters.GetEnumerator()) {
        $args[$kvp.Key] = $kvp.Value
    }
    Invoke-SystemDashboardScriptInternal -ScriptName 'Check-TelemetryDatabase.ps1' -BoundParameters $args
}

Export-ModuleMember -Function `
    Install-SystemDashboard, `
    Initialize-SystemDashboardDatabase, `
    Initialize-SystemDashboardDockerDatabase, `
    Apply-SystemDashboardLanSchema, `
    Ensure-SystemDashboardLanDependencies, `
    Install-SystemDashboardScheduledTask, `
    Manage-SystemDashboardServices, `
    Invoke-SystemDashboardControl, `
    Invoke-SystemDashboardAutoHeal, `
    Test-SystemDashboardTelemetryDatabase

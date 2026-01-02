#requires -Version 7
[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..' '..' 'config.json')
)

$repoRoot = Join-Path $PSScriptRoot '..' '..'

function Import-TelemetryModule {
    $candidates = @(
        (Join-Path $repoRoot 'tools' 'SystemDashboard.Telemetry.psm1'),
        (Join-Path $repoRoot 'telemetry' 'SystemDashboard.Telemetry.psm1'),
        (Join-Path $repoRoot 'tools' 'SystemDashboard.Telemetry-Minimal.psm1')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            Import-Module $candidate -Force
            return $candidate
        }
    }

    throw "Telemetry module not found. Tried: $($candidates -join ', ')"
}

function Load-DbSecrets {
    $connectionFile = Join-Path $repoRoot 'var' 'database-connection.json'
    if (-not (Test-Path -LiteralPath $connectionFile)) {
        return
    }

    try {
        $connectionInfo = Get-Content -LiteralPath $connectionFile -Raw | ConvertFrom-Json
    }
    catch {
        return
    }

    if ($connectionInfo.IngestPassword) {
        $env:SYSTEMDASHBOARD_DB_PASSWORD = $connectionInfo.IngestPassword
    }

    if ($connectionInfo.ReaderPassword) {
        $env:SYSTEMDASHBOARD_DB_READER_PASSWORD = $connectionInfo.ReaderPassword
    }
}

Load-DbSecrets
$loaded = Import-TelemetryModule

try {
    $cfg = $null
    if (Test-Path -LiteralPath $ConfigPath) {
        $cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -Depth 20
    }
    $logPath = $cfg.Service.LogPath
    if ($logPath) {
        if (-not [System.IO.Path]::IsPathRooted($logPath)) {
            $logPath = Join-Path (Split-Path -Parent $ConfigPath) $logPath
        }
        $ts = (Get-Date).ToString('o')
        Add-Content -LiteralPath $logPath -Value "[$ts][INFO] Service wrapper starting. Telemetry module loaded: $loaded"
    }
}
catch {
    # Best-effort only; telemetry logging should still start.
}

Start-TelemetryService -ConfigPath $ConfigPath

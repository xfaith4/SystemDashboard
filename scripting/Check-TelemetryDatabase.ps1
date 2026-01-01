#requires -Version 7
[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..' 'config.json'),
    [int]$Tail = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-Secret {
    param([object]$Secret)
    if ($null -eq $Secret) { return $null }
    if ($Secret -is [string]) {
        if ($Secret.StartsWith('env:', [System.StringComparison]::OrdinalIgnoreCase)) {
            return [Environment]::GetEnvironmentVariable($Secret.Substring(4))
        }
        if ($Secret.StartsWith('file:', [System.StringComparison]::OrdinalIgnoreCase)) {
            $path = $Secret.Substring(5)
            if (Test-Path -LiteralPath $path) { return (Get-Content -LiteralPath $path -Raw).Trim() }
            return $null
        }
        return $Secret
    }
    return $null
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config file not found at $ConfigPath"
}

$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -Depth 20
$db = $cfg.Database
if (-not $db) { throw "No 'Database' section found in $ConfigPath" }

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

$psql = $db.PsqlPath
if (-not $psql) { $psql = 'psql' }
if ($psql -ne 'psql' -and -not (Test-Path -LiteralPath $psql)) {
    throw "psql not found at '$psql' (set Database.PsqlPath in config.json)"
}

$password = $env:SYSTEMDASHBOARD_DB_READER_PASSWORD
if (-not $password) {
    $connectionPath = Join-Path $repoRoot 'var' 'database-connection.json'
    if (Test-Path -LiteralPath $connectionPath) {
        try {
            $connectionInfo = Get-Content -LiteralPath $connectionPath -Raw | ConvertFrom-Json
            if ($connectionInfo.ReaderPassword) {
                $password = [string]$connectionInfo.ReaderPassword
            }
        }
        catch {
            $password = $null
        }
    }
}
if (-not $password) {
    $password = Resolve-Secret $db.PasswordSecret
    if ($password) {
        Write-Warning "Using Database.PasswordSecret as a fallback; prefer SYSTEMDASHBOARD_DB_READER_PASSWORD for read queries."
    }
}
if (-not $password) {
    throw "Database password missing. Set Database.PasswordSecret (or SYSTEMDASHBOARD_DB_READER_PASSWORD)."
}

$dbHost = $db.Host ?? 'localhost'
$dbPort = [int]($db.Port ?? 5432)
$databaseName = $db.Database ?? 'system_dashboard'
$dbUser = 'sysdash_reader'
$schema = $db.Schema ?? 'telemetry'

$env:PGPASSWORD = $password
try {
    Write-Host "=== Telemetry DB Check ===" -ForegroundColor Cyan
    Write-Host ("psql: {0}" -f $psql)
    Write-Host ("db:   {0}@{1}:{2}/{3} schema={4}" -f $dbUser, $dbHost, $dbPort, $databaseName, $schema)

    & $psql -h $dbHost -p $dbPort -U $dbUser -d $databaseName -c @"
SELECT
  now() as now,
  (SELECT COUNT(*) FROM $schema.syslog_recent) AS syslog_recent,
  (SELECT COUNT(*) FROM $schema.syslog_generic_template) AS syslog_total,
  (SELECT COUNT(*) FROM $schema.events) AS events,
  (SELECT COUNT(*) FROM $schema.metrics) AS metrics;
"@

    & $psql -h $dbHost -p $dbPort -U $dbUser -d $databaseName -c @"
SELECT received_utc, source_host, app_name, facility, severity, left(message, 120) AS message
FROM $schema.syslog_recent
ORDER BY received_utc DESC
LIMIT $Tail;
"@
}
finally {
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}

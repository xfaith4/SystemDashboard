#requires -Version 7
<#
.SYNOPSIS
  Apply the telemetry schema (syslog partitions + recent view) to Postgres using config telemetry settings.
.DESCRIPTION
  Reads telemetry database settings from the unified config (2025-09-11/config.json by default),
  resolves env/file secrets, and runs schema.sql via psql.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..' '2025-09-11' 'config.json'),
    [string]$SchemaPath = (Join-Path $PSScriptRoot 'schema.sql')
)

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config not found at $ConfigPath" }
if (-not (Test-Path -LiteralPath $SchemaPath)) { throw "Schema file not found at $SchemaPath" }

$cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -Depth 10
if (-not $cfg.telemetry) { throw "telemetry section missing in config." }
if (-not $cfg.telemetry.database) { throw "telemetry.database missing in config." }
$db = $cfg.telemetry.database

$psql = $db.psqlPath
if (-not $psql) { $psql = 'psql' }
$cmd = Get-Command -Name $psql -ErrorAction SilentlyContinue
if (-not $cmd) { throw "psql '$psql' not found in PATH. Set telemetry.database.psqlPath." }

function Resolve-Secret {
    param([object]$Secret,[string]$Fallback)
    if ($null -eq $Secret) { return $Fallback }
    if ($Secret -is [string]) {
        if ($Secret.StartsWith('env:', [System.StringComparison]::OrdinalIgnoreCase)) {
            $name = $Secret.Substring(4)
            return [Environment]::GetEnvironmentVariable($name)
        }
        elseif ($Secret.StartsWith('file:', [System.StringComparison]::OrdinalIgnoreCase)) {
            $path = $Secret.Substring(5)
            if (-not (Test-Path -LiteralPath $path)) { throw "Secret file '$path' not found." }
            return (Get-Content -LiteralPath $path -Raw).Trim()
        }
        else {
            return $Secret
        }
    }
    return $Fallback
}

$host = $db.host ?? 'localhost'
$port = [int]($db.port ?? 5432)
$name = $db.database ?? $db.name
$user = $db.username ?? $db.user
if (-not $name -or -not $user) { throw "telemetry.database.host/user/database required." }
$pwd = Resolve-Secret -Secret ($db.passwordSecret ?? $db.password) -Fallback $null
if ([string]::IsNullOrWhiteSpace($pwd)) { throw "telemetry database password missing (password or passwordSecret)." }

$env:PGPASSWORD = $pwd
try {
    $args = @('-h', $host, '-p', [string]$port, '-U', $user, '-d', $name, '-f', $SchemaPath)
    Write-Host "Applying telemetry schema to $host:$port/$name using $($cmd.Source)..." -ForegroundColor Cyan
    $p = Start-Process -FilePath $cmd.Source -ArgumentList $args -NoNewWindow -Wait -PassThru -ErrorAction Stop
    if ($p.ExitCode -ne 0) { throw "psql exited with $($p.ExitCode)" }
    Write-Host "Schema applied successfully." -ForegroundColor Green
}
finally {
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}

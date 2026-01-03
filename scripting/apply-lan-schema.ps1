#requires -Version 7
<#
.SYNOPSIS
    Applies the unified telemetry schema (including LAN observability) to the database
.DESCRIPTION
    Runs the consolidated telemetry/schema.sql script to create the tables,
    functions, and views needed for LAN device monitoring and related features.
#>

param(
    [Parameter()][string]$ConfigPath,
    [Parameter()][switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import telemetry module for config reading
$repoRoot = Split-Path -Parent $PSScriptRoot
$telemetryModulePath = Join-Path $repoRoot "tools\SystemDashboard.Telemetry.psm1"
if (-not (Test-Path $telemetryModulePath)) {
    Write-Error "Telemetry module not found at: $telemetryModulePath"
    exit 1
}

Import-Module $telemetryModulePath -Force -Global

# Load configuration
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $repoRoot "config.json"
}

Write-Host "Loading configuration from: $ConfigPath" -ForegroundColor Cyan
$configInfo = Read-SystemDashboardConfig -ConfigPath $ConfigPath
$config = $configInfo.Config ?? $configInfo

# Get database settings
$dbHost = $config.Database.Host
$dbPort = $config.Database.Port
$dbName = $config.Database.Database
$dbUser = $config.Database.Username
$dbPassword = Resolve-SystemDashboardSecret -Secret $config.Database.PasswordSecret

if (-not $dbPassword) {
    Write-Error "Database password not configured"
    exit 1
}

# Get psql path
$psqlPath = $config.Database.PsqlPath
if (-not $psqlPath -or -not (Test-Path $psqlPath)) {
    # Try to find psql in common locations
    $commonPaths = @(
        "C:\Program Files\PostgreSQL\18\bin\psql.exe",
        "C:\Program Files\PostgreSQL\15\bin\psql.exe",
        "C:\Program Files\PostgreSQL\14\bin\psql.exe"
    )

    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            $psqlPath = $path
            break
        }
    }

    if (-not $psqlPath) {
        Write-Error "psql.exe not found. Please install PostgreSQL client tools or specify path in config.json"
        exit 1
    }
}

Write-Host "Using psql at: $psqlPath" -ForegroundColor Cyan

# Schema file path
$schemaFile = Join-Path $repoRoot "telemetry\\schema.sql"
if (-not (Test-Path $schemaFile)) {
    Write-Error "Schema file not found at: $schemaFile"
    exit 1
}

Write-Host "Schema file: $schemaFile" -ForegroundColor Cyan

# Check if LAN tables already exist
Write-Host "`nChecking for existing LAN tables..." -ForegroundColor Yellow

$env:PGPASSWORD = $dbPassword
$checkCmd = "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'telemetry' AND table_name = 'devices';"
$checkResult = & "$psqlPath" -h $dbHost -p $dbPort -U $dbUser -d $dbName -t -c $checkCmd 2>&1

if ($LASTEXITCODE -eq 0) {
    $checkText = ($checkResult | Out-String)
    $countMatch = [regex]::Match($checkText, '^\s*(\d+)', [System.Text.RegularExpressions.RegexOptions]::Multiline)

    if ($countMatch.Success) {
        $tableCount = [int]$countMatch.Groups[1].Value

        if ($tableCount -gt 0) {
            Write-Host "LAN tables already exist in the database." -ForegroundColor Yellow

            if (-not $Force) {
                Write-Host "`nThe schema appears to be already applied." -ForegroundColor Yellow
                Write-Host "If you want to reapply the schema (this is safe for existing data), use the -Force parameter." -ForegroundColor Yellow
                Write-Host "Example: .\scripting\apply-lan-schema.ps1 -Force" -ForegroundColor Cyan
                exit 0
            }

            Write-Host "Force parameter specified. Proceeding with schema application..." -ForegroundColor Yellow
        }
    }
    else {
        Write-Warning "Could not parse table count from psql output: $checkText"
    }
}

# Apply schema
Write-Host "`nApplying unified telemetry schema (includes LAN)..." -ForegroundColor Green

try {
    $output = & "$psqlPath" -h $dbHost -p $dbPort -U $dbUser -d $dbName -f $schemaFile 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to apply schema. Exit code: $LASTEXITCODE"
        Write-Host "Output:" -ForegroundColor Red
        Write-Host $output
        exit 1
    }

    Write-Host "`n✅ Schema applied successfully!" -ForegroundColor Green

    # Show summary
    Write-Host "`nSchema Summary:" -ForegroundColor Cyan
    Write-Host "- Created devices table (stable inventory)" -ForegroundColor White
    Write-Host "- Created device_snapshots_template table (time-series with partitioning)" -ForegroundColor White
    Write-Host "- Created syslog_device_links table (correlation)" -ForegroundColor White
    Write-Host "- Created lan_settings table (configuration)" -ForegroundColor White
    Write-Host "- Created helper functions and views" -ForegroundColor White
    Write-Host "- Set up initial partitions for current month" -ForegroundColor White
    Write-Host "- Granted permissions to sysdash_ingest and sysdash_reader" -ForegroundColor White

    # Verify tables
    Write-Host "`nVerifying tables..." -ForegroundColor Yellow
    $verifyCmd = @"
SELECT table_name,
pg_size_pretty(pg_total_relation_size('telemetry.' || table_name)) AS size
FROM information_schema.tables
WHERE table_schema = 'telemetry'
AND table_name IN ('devices', 'device_snapshots_template', 'syslog_device_links', 'lan_settings')
ORDER BY table_name;
"@

    $verifyResult = & "$psqlPath" -h $dbHost -p $dbPort -U $dbUser -d $dbName -c $verifyCmd 2>&1
    Write-Host $verifyResult

    Write-Host "`n✅ All LAN Observability tables verified!" -ForegroundColor Green

    # Show next steps
    Write-Host "`nNext Steps:" -ForegroundColor Cyan
    Write-Host "1. Start the LAN collector service:" -ForegroundColor White
    Write-Host "   .\services\LanCollectorService.ps1" -ForegroundColor Gray
    Write-Host "2. Access the LAN dashboard:" -ForegroundColor White
    Write-Host "   http://localhost:5000/lan" -ForegroundColor Gray
    Write-Host "3. Configure router settings in config.json if needed" -ForegroundColor White
}
catch {
    Write-Error "Failed to apply schema: $_"
    exit 1
}
finally {
    # Clear password from environment
    Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
}

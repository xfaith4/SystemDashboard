#!/usr/bin/env pwsh
<#
.SYNOPSIS
Database setup script for System Dashboard

.DESCRIPTION
This script sets up the PostgreSQL database for the System Dashboard project.
It creates the database, users, and schema required for telemetry data storage.

.PARAMETER PostgreSQLPath
Path to PostgreSQL installation directory (defaults to common locations)

.PARAMETER DatabaseName
Name of the database to create (default: system_dashboard)

.PARAMETER AdminUser
PostgreSQL admin user (default: postgres)

.PARAMETER IngestUser
Database user for data ingestion (default: sysdash_ingest)

.PARAMETER ReaderUser
Database user for read-only access (default: sysdash_reader)

.PARAMETER Host
Database host (default: localhost)

.PARAMETER Port
Database port (default: 5432)

.EXAMPLE
.\setup-database.ps1
Create database with default settings

.EXAMPLE
.\setup-database.ps1 -PostgreSQLPath "C:\PostgreSQL\16"
Specify custom PostgreSQL installation path
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage="Path to PostgreSQL installation directory")]
    [string]$PostgreSQLPath,

    [Parameter(HelpMessage="Name of the database to create")]
    [string]$DatabaseName = "system_dashboard",

    [Parameter(HelpMessage="PostgreSQL admin user")]
    [string]$AdminUser = "postgres",

    [Parameter(HelpMessage="Database user for data ingestion")]
    [string]$IngestUser = "sysdash_ingest",

    [Parameter(HelpMessage="Database user for read-only access")]
    [string]$ReaderUser = "sysdash_reader",

    [Parameter(HelpMessage="Database host")]
    [string]$DatabaseHost = "localhost",

    [Parameter(HelpMessage="Database port")]
    [int]$Port = 5432
)

# Function to find PostgreSQL installation
function Find-PostgreSQLPath {
    $commonPaths = @(
        "C:\Program Files\PostgreSQL\16\bin",
        "C:\Program Files\PostgreSQL\15\bin",
        "C:\Program Files\PostgreSQL\14\bin",
        "C:\Program Files (x86)\PostgreSQL\16\bin",
        "C:\Program Files (x86)\PostgreSQL\15\bin"
    )

    foreach ($path in $commonPaths) {
        if (Test-Path (Join-Path $path "psql.exe")) {
            return $path
        }
    }

    # Try to find in PATH
    try {
        $psqlCmd = Get-Command psql -ErrorAction Stop
        return Split-Path $psqlCmd.Source -Parent
    }
    catch {
        return $null
    }
}

# Function to generate secure password
function New-SecurePassword {
    param([int]$Length = 16)

    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*"
    $password = ""
    for ($i = 0; $i -lt $Length; $i++) {
        $password += $chars[(Get-Random -Maximum $chars.Length)]
    }
    return $password
}

# Function to execute SQL safely
function Invoke-PSQL {
    param(
        [string]$Command,
        [string]$Database = "postgres",
        [string]$User = $AdminUser,
        [string]$Description
    )

    Write-Host "📋 $Description..." -ForegroundColor Cyan

    $arguments = @(
        "-h", $DatabaseHost
        "-p", $Port
        "-U", $User
        "-d", $Database
        "-c", $Command
        "-q"
    )

    try {
        $result = & $psqlPath $arguments
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Success" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "❌ Failed with exit code $LASTEXITCODE" -ForegroundColor Red
            Write-Host "Output: $result" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "❌ Error: $_" -ForegroundColor Red
        return $false
    }
}

# Main script execution
Write-Host "🔧 System Dashboard Database Setup" -ForegroundColor Yellow
Write-Host "=" * 50

# Find PostgreSQL installation
if (-not $PostgreSQLPath) {
    $PostgreSQLPath = Find-PostgreSQLPath
}

if (-not $PostgreSQLPath) {
    Write-Host "❌ PostgreSQL installation not found!" -ForegroundColor Red
    Write-Host "Please install PostgreSQL 15+ or specify the path with -PostgreSQLPath" -ForegroundColor Red
    Write-Host "Download from: https://www.postgresql.org/download/windows/" -ForegroundColor Blue
    exit 1
}

$psqlPath = Join-Path $PostgreSQLPath "psql.exe"
if (-not (Test-Path $psqlPath)) {
    Write-Host "❌ psql.exe not found at: $psqlPath" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Found PostgreSQL at: $PostgreSQLPath" -ForegroundColor Green

# Test connection
Write-Host "`n🔌 Testing PostgreSQL connection..." -ForegroundColor Cyan
Write-Host "You will be prompted for the PostgreSQL admin password..." -ForegroundColor Yellow

$testArgs = @("-h", $DatabaseHost, "-p", $Port, "-U", $AdminUser, "-d", "postgres", "-c", "SELECT version();", "-t")
try {
    $version = & $psqlPath $testArgs
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Connection successful" -ForegroundColor Green
        Write-Host "PostgreSQL Version: $($version.Trim())" -ForegroundColor Gray
    }
    else {
        Write-Host "❌ Connection failed" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "❌ Connection error: $_" -ForegroundColor Red
    exit 1
}

# Generate passwords
$ingestPassword = New-SecurePassword
$readerPassword = New-SecurePassword

Write-Host "`n🔐 Generated secure passwords for database users" -ForegroundColor Green

# Create database
Write-Host "`n📊 Creating database and users..." -ForegroundColor Yellow

$success = $true

# Create database
$success = $success -and (Invoke-PSQL -Command "CREATE DATABASE $DatabaseName;" -Description "Creating database '$DatabaseName'")

# Create users
$success = $success -and (Invoke-PSQL -Command "CREATE USER $IngestUser WITH PASSWORD '$ingestPassword';" -Description "Creating ingest user '$IngestUser'")
$success = $success -and (Invoke-PSQL -Command "CREATE USER $ReaderUser WITH PASSWORD '$readerPassword';" -Description "Creating reader user '$ReaderUser'")

if (-not $success) {
    Write-Host "❌ Database setup failed" -ForegroundColor Red
    exit 1
}

# Set up schema and permissions
Write-Host "`n🏗️  Setting up schema and permissions..." -ForegroundColor Yellow

$schemaPath = Join-Path $PSScriptRoot "tools\schema.sql"
if (Test-Path $schemaPath) {
    Write-Host "📋 Applying schema from: $schemaPath" -ForegroundColor Cyan
    $schemaArgs = @("-h", $DatabaseHost, "-p", $Port, "-U", $AdminUser, "-d", $DatabaseName, "-f", $schemaPath, "-q")
    try {
        & $psqlPath $schemaArgs
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Schema applied successfully" -ForegroundColor Green
        }
        else {
            Write-Host "❌ Schema application failed" -ForegroundColor Red
            $success = $false
        }
    }
    catch {
        Write-Host "❌ Schema error: $_" -ForegroundColor Red
        $success = $false
    }
}
else {
    Write-Host "⚠️  Schema file not found at: $schemaPath" -ForegroundColor Yellow
}

# Grant permissions
$permissionCommands = @(
    "GRANT CONNECT ON DATABASE $DatabaseName TO $IngestUser;",
    "GRANT CONNECT ON DATABASE $DatabaseName TO $ReaderUser;",
    "GRANT USAGE ON SCHEMA telemetry TO $IngestUser;",
    "GRANT USAGE ON SCHEMA telemetry TO $ReaderUser;",
    "GRANT INSERT, SELECT ON ALL TABLES IN SCHEMA telemetry TO $IngestUser;",
    "GRANT SELECT ON ALL TABLES IN SCHEMA telemetry TO $ReaderUser;",
    "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA telemetry TO $IngestUser;",
    "GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA telemetry TO $IngestUser;",
    "ALTER DEFAULT PRIVILEGES IN SCHEMA telemetry GRANT INSERT, SELECT ON TABLES TO $IngestUser;",
    "ALTER DEFAULT PRIVILEGES IN SCHEMA telemetry GRANT SELECT ON TABLES TO $ReaderUser;",
    "ALTER DEFAULT PRIVILEGES IN SCHEMA telemetry GRANT USAGE, SELECT ON SEQUENCES TO $IngestUser;"
)

foreach ($cmd in $permissionCommands) {
    $success = $success -and (Invoke-PSQL -Command $cmd -Database $DatabaseName -Description "Setting permissions")
}

# Create initial partition
$success = $success -and (Invoke-PSQL -Command "SELECT telemetry.ensure_syslog_partition(CURRENT_DATE);" -Database $DatabaseName -Description "Creating initial partition")

if ($success) {
    Write-Host "`n🎉 Database setup completed successfully!" -ForegroundColor Green

    # Update environment variables
    Write-Host "`n🔧 Setting up environment variables..." -ForegroundColor Yellow

    [Environment]::SetEnvironmentVariable("SYSTEMDASHBOARD_DB_PASSWORD", $ingestPassword, [EnvironmentVariableTarget]::User)
    [Environment]::SetEnvironmentVariable("SYSTEMDASHBOARD_DB_READER_PASSWORD", $readerPassword, [EnvironmentVariableTarget]::User)

    # Also set for current session
    $env:SYSTEMDASHBOARD_DB_PASSWORD = $ingestPassword
    $env:SYSTEMDASHBOARD_DB_READER_PASSWORD = $readerPassword

    Write-Host "✅ Environment variables set" -ForegroundColor Green

    # Save connection details
    $connectionInfo = @{
        Host = $DatabaseHost
        Port = $Port
        Database = $DatabaseName
        IngestUser = $IngestUser
        IngestPassword = $ingestPassword
        ReaderUser = $ReaderUser
        ReaderPassword = $readerPassword
        CreatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }

    $connectionFile = Join-Path $PSScriptRoot "var\database-connection.json"
    $connectionInfo | ConvertTo-Json -Depth 3 | Out-File -FilePath $connectionFile -Encoding UTF8
    Write-Host "✅ Connection details saved to: $connectionFile" -ForegroundColor Green

    Write-Host "`n📋 Database Configuration Summary:" -ForegroundColor Cyan
    Write-Host "Database: $DatabaseName" -ForegroundColor White
    Write-Host "Host: ${DatabaseHost}:${Port}" -ForegroundColor White
    Write-Host "Ingest User: $IngestUser" -ForegroundColor White
    Write-Host "Reader User: $ReaderUser" -ForegroundColor White
    Write-Host "`n🔐 Passwords have been set in environment variables:" -ForegroundColor Yellow
    Write-Host "- SYSTEMDASHBOARD_DB_PASSWORD (for ingestion)" -ForegroundColor White
    Write-Host "- SYSTEMDASHBOARD_DB_READER_PASSWORD (for Flask app)" -ForegroundColor White

    Write-Host "`n✅ Your System Dashboard database is ready!" -ForegroundColor Green
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Run: .\Install.ps1" -ForegroundColor White
    Write-Host "2. Start-Service SystemDashboardTelemetry" -ForegroundColor White
    Write-Host "3. python .\app\app.py" -ForegroundColor White

}
else {
    Write-Host "`n❌ Database setup failed" -ForegroundColor Red
    Write-Host "Please check the errors above and try again" -ForegroundColor Red
    exit 1
}

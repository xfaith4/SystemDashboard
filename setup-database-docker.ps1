#!/usr/bin/env pwsh
<#
.SYNOPSIS
Database setup script for System Dashboard using Docker PostgreSQL

.DESCRIPTION
This script sets up the PostgreSQL database for the System Dashboard project using a Docker container.
It creates the database, users, and schema required for telemetry data storage.

.PARAMETER ContainerName
Name of the PostgreSQL Docker container (default: postgres-container)

.PARAMETER DatabaseName
Name of the database to create (default: system_dashboard)

.PARAMETER AdminUser
PostgreSQL admin user (default: postgres)

.PARAMETER AdminPassword
PostgreSQL admin password (default: mysecretpassword)

.PARAMETER IngestUser
Database user for data ingestion (default: sysdash_ingest)

.PARAMETER ReaderUser
Database user for read-only access (default: sysdash_reader)

.PARAMETER Host
Database host (default: localhost)

.PARAMETER Port
Database port (default: 5432)

.EXAMPLE
.\setup-database-docker.ps1
Create database with default settings for Docker container

.EXAMPLE
.\setup-database-docker.ps1 -AdminPassword "mypassword"
Specify custom admin password
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage="Name of the PostgreSQL Docker container")]
    [string]$ContainerName = "postgres-container",

    [Parameter(HelpMessage="Name of the database to create")]
    [string]$DatabaseName = "system_dashboard",

    [Parameter(HelpMessage="PostgreSQL admin user")]
    [string]$AdminUser = "postgres",

    [Parameter(HelpMessage="PostgreSQL admin password")]
    [string]$AdminPassword = "mysecretpassword",

    [Parameter(HelpMessage="Database user for data ingestion")]
    [string]$IngestUser = "sysdash_ingest",

    [Parameter(HelpMessage="Database user for read-only access")]
    [string]$ReaderUser = "sysdash_reader",

    [Parameter(HelpMessage="Database host")]
    [string]$DatabaseHost = "localhost",

    [Parameter(HelpMessage="Database port")]
    [int]$Port = 5432
)

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

# Function to execute SQL in Docker container
function Invoke-DockerPSQL {
    param(
        [string]$Command,
        [string]$Database = "postgres",
        [string]$Description,
        [switch]$IgnoreErrors
    )

    Write-Host "📋 $Description..." -ForegroundColor Cyan

    try {
        $result = docker exec -it $ContainerName psql -U $AdminUser -d $Database -c $Command
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Success" -ForegroundColor Green
            return $true
        }
        elseif ($IgnoreErrors) {
            Write-Host "⚠️  Already exists or completed (ignored)" -ForegroundColor Yellow
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
}# Function to copy and execute SQL file
function Invoke-DockerSQLFile {
    param(
        [string]$FilePath,
        [string]$Database,
        [string]$Description
    )

    Write-Host "📋 $Description..." -ForegroundColor Cyan

    try {
        # Copy file to container
        docker cp $FilePath "${ContainerName}:/tmp/script.sql"
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Failed to copy SQL file to container" -ForegroundColor Red
            return $false
        }

        # Execute the file
        $result = docker exec -it $ContainerName psql -U $AdminUser -d $Database -f /tmp/script.sql
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Success" -ForegroundColor Green

            # Clean up
            docker exec $ContainerName rm /tmp/script.sql
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
Write-Host "🔧 System Dashboard Database Setup (Docker)" -ForegroundColor Yellow
Write-Host "=" * 50

# Check if Docker is available
try {
    $dockerVersion = docker --version
    Write-Host "✅ Docker available: $dockerVersion" -ForegroundColor Green
}
catch {
    Write-Host "❌ Docker is not available or not running" -ForegroundColor Red
    Write-Host "Please install Docker Desktop and ensure it's running" -ForegroundColor Red
    exit 1
}

# Check if container exists and is running
try {
    $containerStatus = docker ps --filter "name=$ContainerName" --format "{{.Status}}"
    if (-not $containerStatus) {
        Write-Host "❌ Container '$ContainerName' not found or not running" -ForegroundColor Red
        Write-Host "Please start the PostgreSQL container first:" -ForegroundColor Red
        Write-Host "docker run -d --name $ContainerName -p 5432:5432 -e POSTGRES_PASSWORD=$AdminPassword postgres:latest" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "✅ Container '$ContainerName' is running: $containerStatus" -ForegroundColor Green
}
catch {
    Write-Host "❌ Error checking container status: $_" -ForegroundColor Red
    exit 1
}

# Test connection
Write-Host "`n🔌 Testing PostgreSQL connection..." -ForegroundColor Cyan

try {
    $version = docker exec $ContainerName psql -U $AdminUser -d postgres -t -c "SELECT version();"
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

# Create database and users
Write-Host "`n📊 Creating database and users..." -ForegroundColor Yellow

$success = $true

# Create database (ignore if already exists)
$success = $success -and (Invoke-DockerPSQL -Command "CREATE DATABASE $DatabaseName;" -Description "Creating database '$DatabaseName'" -IgnoreErrors)

# Create users (ignore if already exist)
$success = $success -and (Invoke-DockerPSQL -Command "CREATE USER $IngestUser WITH PASSWORD '$ingestPassword';" -Description "Creating ingest user '$IngestUser'" -IgnoreErrors)
$success = $success -and (Invoke-DockerPSQL -Command "CREATE USER $ReaderUser WITH PASSWORD '$readerPassword';" -Description "Creating reader user '$ReaderUser'" -IgnoreErrors)

if (-not $success) {
    Write-Host "❌ Database setup failed" -ForegroundColor Red
    exit 1
}

# Apply schema
Write-Host "`n🏗️  Setting up schema..." -ForegroundColor Yellow

$schemaPath = Join-Path $PSScriptRoot "tools\schema.sql"
if (Test-Path $schemaPath) {
    $success = $success -and (Invoke-DockerSQLFile -FilePath $schemaPath -Database $DatabaseName -Description "Applying schema from schema.sql")
}
else {
    Write-Host "⚠️  Schema file not found at: $schemaPath" -ForegroundColor Yellow
    Write-Host "Creating basic telemetry schema..." -ForegroundColor Cyan

    $basicSchema = @"
CREATE SCHEMA IF NOT EXISTS telemetry;

CREATE TABLE IF NOT EXISTS telemetry.syslog_generic_template (
    id              BIGSERIAL PRIMARY KEY,
    received_utc    TIMESTAMPTZ NOT NULL,
    event_utc       TIMESTAMPTZ,
    source_host     TEXT,
    app_name        TEXT,
    facility        SMALLINT,
    severity        SMALLINT,
    message         TEXT,
    raw_message     TEXT,
    remote_endpoint TEXT,
    source          TEXT NOT NULL DEFAULT 'syslog',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
) PARTITION BY RANGE (received_utc);

CREATE OR REPLACE FUNCTION telemetry.ensure_syslog_partition(target_month DATE)
RETURNS VOID
LANGUAGE plpgsql
AS \$\$
DECLARE
    partition_name TEXT;
    start_ts       DATE;
    end_ts         DATE;
    stmt           TEXT;
BEGIN
    start_ts := date_trunc('month', target_month);
    end_ts := (start_ts + INTERVAL '1 month');
    partition_name := format('syslog_generic_%s', to_char(start_ts, 'YYMM'));

    IF NOT EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = partition_name
          AND n.nspname = 'telemetry'
    ) THEN
        stmt := format(
            'CREATE TABLE telemetry.%I PARTITION OF telemetry.syslog_generic_template
             FOR VALUES FROM (%L) TO (%L);',
            partition_name,
            start_ts,
            end_ts
        );
        EXECUTE stmt;
    END IF;
END;
\$\$;
"@

    $success = $success -and (Invoke-DockerPSQL -Command $basicSchema -Database $DatabaseName -Description "Creating basic telemetry schema")
}

# Apply extended schema for Windows Event Log and IIS tables
$extendedSchemaPath = Join-Path $PSScriptRoot "extended-schema.sql"
if (Test-Path $extendedSchemaPath) {
    Write-Host "`n📋 Applying extended schema (Windows Event Log and IIS tables)..." -ForegroundColor Cyan
    $success = $success -and (Invoke-DockerSQLFile -FilePath $extendedSchemaPath -Database $DatabaseName -Description "Applying extended schema from extended-schema.sql")
}
else {
    Write-Host "⚠️  Extended schema file not found at: $extendedSchemaPath" -ForegroundColor Yellow
}

# Grant permissions
Write-Host "`n🔐 Setting up permissions..." -ForegroundColor Yellow

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
    $success = $success -and (Invoke-DockerPSQL -Command $cmd -Database $DatabaseName -Description "Setting permissions")
}

# Create initial partition
$success = $success -and (Invoke-DockerPSQL -Command "SELECT telemetry.ensure_syslog_partition(CURRENT_DATE);" -Database $DatabaseName -Description "Creating initial partition")

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

    # Ensure var directory exists
    $varDir = Join-Path $PSScriptRoot "var"
    if (-not (Test-Path $varDir)) {
        New-Item -ItemType Directory -Path $varDir -Force | Out-Null
    }

    # Save connection details
    $connectionInfo = @{
        Host = $DatabaseHost
        Port = $Port
        Database = $DatabaseName
        IngestUser = $IngestUser
        IngestPassword = $ingestPassword
        ReaderUser = $ReaderUser
        ReaderPassword = $readerPassword
        ContainerName = $ContainerName
        AdminPassword = $AdminPassword
        CreatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }

    $connectionFile = Join-Path $varDir "database-connection.json"
    $connectionInfo | ConvertTo-Json -Depth 3 | Out-File -FilePath $connectionFile -Encoding UTF8
    Write-Host "✅ Connection details saved to: $connectionFile" -ForegroundColor Green

    Write-Host "`n📋 Database Configuration Summary:" -ForegroundColor Cyan
    Write-Host "Container: $ContainerName" -ForegroundColor White
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

    Write-Host "`n💡 Docker container management:" -ForegroundColor Blue
    Write-Host "- Stop: docker stop $ContainerName" -ForegroundColor White
    Write-Host "- Start: docker start $ContainerName" -ForegroundColor White
    Write-Host "- Connect: docker exec -it $ContainerName psql -U postgres -d $DatabaseName" -ForegroundColor White

}
else {
    Write-Host "`n❌ Database setup failed" -ForegroundColor Red
    Write-Host "Please check the errors above and try again" -ForegroundColor Red
    exit 1
}

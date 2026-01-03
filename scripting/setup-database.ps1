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
.\scripting\setup-database.ps1
Create database with default settings

.EXAMPLE
.\scripting\setup-database.ps1 -PostgreSQLPath "C:\PostgreSQL\16"
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
        "C:\\Program Files\\PostgreSQL\\18\\bin",
        "C:\\Program Files\\PostgreSQL\\17\\bin",
        "C:\Program Files\PostgreSQL\16\bin",
        "C:\Program Files\PostgreSQL\15\bin",
        "C:\Program Files\PostgreSQL\14\bin",
        "C:\\Program Files\\PostgreSQL\\13\\bin",
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

function Test-PostgresPort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][int]$Port
    )

    if (-not $IsWindows) {
        return $true
    }

    $targets = if ($HostName -eq 'localhost') { @('127.0.0.1', '::1') } else { @($HostName) }

    foreach ($target in $targets) {
        try {
            $addressFamily = if ($target -eq '::1') {
                [System.Net.Sockets.AddressFamily]::InterNetworkV6
            }
            else {
                [System.Net.Sockets.AddressFamily]::InterNetwork
            }

            $client = New-Object System.Net.Sockets.TcpClient($addressFamily)
            try {
                $task = $client.ConnectAsync($target, $Port)
                if ($task.Wait(800) -and $client.Connected) {
                    return $true
                }
            }
            finally {
                $client.Dispose()
            }
        }
        catch {
            # ignore and try next target
        }
    }

    return $false
}

function Get-PostgresServices {
    [CmdletBinding()]
    param(
        [Parameter()][string]$PostgreSQLBinPath
    )

    if (-not $IsWindows) {
        return @()
    }

    $services = @(Get-Service -Name 'postgresql*' -ErrorAction SilentlyContinue)
    if (-not $services) {
        return @()
    }

    if (-not $PostgreSQLBinPath) {
        return $services
    }

    $versionMatch = [regex]::Match($PostgreSQLBinPath, 'PostgreSQL\\(?<ver>\\d+)\\bin', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $versionMatch.Success) {
        return $services
    }

    $version = $versionMatch.Groups['ver'].Value
    $preferred = @($services | Where-Object { $_.Name -match [regex]::Escape($version) })
    if ($preferred) {
        $other = @($services | Where-Object { $_.Name -notmatch [regex]::Escape($version) })
        return @($preferred + $other)
    }

    return $services
}

function Get-ListeningPortsForService {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ServiceName
    )

    if (-not $IsWindows) {
        return @()
    }

    $svc = $null
    try {
        $svc = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $ServiceName) -ErrorAction Stop
    }
    catch {
        return @()
    }

    $servicePid = $svc.ProcessId
    if (-not $servicePid -or $servicePid -le 0) {
        return @()
    }

    try {
        return @(Get-NetTCPConnection -State Listen -OwningProcess $servicePid -ErrorAction Stop |
            Select-Object LocalAddress, LocalPort, OwningProcess)
    }
    catch {
        # Fallback: parse netstat output (older systems / restricted environments)
        try {
            $lines = @(netstat -ano -p tcp 2>$null)
            $results = @()
            foreach ($line in $lines) {
                if ($line -match '^\\s*TCP\\s+(\\S+):(\\d+)\\s+(\\S+):(\\S+)\\s+LISTENING\\s+(\\d+)\\s*$') {
                    $ownerPid = [int]$Matches[5]
                    if ($ownerPid -eq $servicePid) {
                        $results += [pscustomobject]@{
                            LocalAddress  = $Matches[1]
                            LocalPort     = [int]$Matches[2]
                            OwningProcess = $ownerPid
                        }
                    }
                }
            }
            return $results
        }
        catch {
            return @()
        }
    }
}

function Get-DescendantProcessIds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$RootProcessId
    )

    if (-not $IsWindows) {
        return @()
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[int]'
    $queue = New-Object 'System.Collections.Generic.Queue[int]'
    [void]$queue.Enqueue($RootProcessId)

    while ($queue.Count -gt 0) {
        $currentPid = $queue.Dequeue()
        if (-not $seen.Add($currentPid)) {
            continue
        }

        try {
            $children = @(Get-CimInstance Win32_Process -Filter ("ParentProcessId={0}" -f $currentPid) -ErrorAction Stop)
        }
        catch {
            $children = @()
        }

        foreach ($child in $children) {
            if ($child.ProcessId -and $child.ProcessId -gt 0) {
                [void]$queue.Enqueue([int]$child.ProcessId)
            }
        }
    }

    return @($seen | Where-Object { $_ -ne $RootProcessId })
}

function Get-ListeningPortsForProcessIds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int[]]$ProcessIds
    )

    if (-not $IsWindows -or -not $ProcessIds -or $ProcessIds.Count -eq 0) {
        return @()
    }

    $listeners = @()
    foreach ($processId in ($ProcessIds | Select-Object -Unique)) {
        try {
            $listeners += @(Get-NetTCPConnection -State Listen -OwningProcess $processId -ErrorAction Stop |
                Select-Object LocalAddress, LocalPort, OwningProcess)
        }
        catch {
            # ignore; callers will fall back to netstat if needed elsewhere
        }
    }

    return @($listeners | Sort-Object LocalPort, LocalAddress -Unique)
}

function Show-PostgresDiagnostics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.ServiceProcess.ServiceController[]]$Services
    )

    if (-not $IsWindows) {
        return
    }

    foreach ($svc in $Services) {
        Write-Host ("   - {0} ({1})" -f $svc.Name, $svc.Status) -ForegroundColor Yellow

        $svcInfo = $null
        try {
            $svcInfo = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $svc.Name) -ErrorAction Stop
        }
        catch {
            $svcInfo = $null
        }

        if ($svcInfo) {
            $pidInfo = $svcInfo.ProcessId
            $pathInfo = $svcInfo.PathName
            if ($pidInfo -and $pidInfo -gt 0) {
                Write-Host ("     pid: {0}" -f $pidInfo) -ForegroundColor Yellow
            }
            else {
                Write-Host "     pid: (unknown/0)" -ForegroundColor Yellow
            }
            if ($pathInfo) {
                Write-Host ("     bin: {0}" -f $pathInfo) -ForegroundColor Yellow
            }
        }

        $listeners = @()
        $descendants = @()
        if ($svcInfo -and $svcInfo.ProcessId -and $svcInfo.ProcessId -gt 0) {
            $descendants = Get-DescendantProcessIds -RootProcessId ([int]$svcInfo.ProcessId)
            if ($descendants -and $descendants.Count -gt 0) {
                $listeners = Get-ListeningPortsForProcessIds -ProcessIds $descendants
            }
        }

        if (-not $listeners -or $listeners.Count -eq 0) {
            $listeners = Get-ListeningPortsForService -ServiceName $svc.Name
        }

        if ($listeners -and $listeners.Count -gt 0) {
            foreach ($l in $listeners | Sort-Object LocalPort, LocalAddress) {
                Write-Host ("     listens: {0}:{1} (pid {2})" -f $l.LocalAddress, $l.LocalPort, $l.OwningProcess) -ForegroundColor Yellow
            }
        }
        else {
            if ($descendants -and $descendants.Count -gt 0) {
                Write-Host ("     postgres child pids: {0}" -f (($descendants | Sort-Object) -join ', ')) -ForegroundColor Yellow
            }
            Write-Host "     listens: (no TCP listeners detected for service or child processes)" -ForegroundColor Yellow
            Write-Host "     next: check Postgres logs; also verify listen_addresses/port in postgresql.conf." -ForegroundColor Yellow
        }
    }
}

function Ensure-PostgresReachable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][int]$Port,
        [Parameter()][string]$PostgreSQLBinPath
    )

    if (-not $IsWindows) {
        return $true
    }

    if ($HostName -notin @('localhost', '127.0.0.1', '::1')) {
        return $true
    }

    if (Test-PostgresPort -HostName $HostName -Port $Port) {
        return $true
    }

    $services = Get-PostgresServices -PostgreSQLBinPath $PostgreSQLBinPath
    if (-not $services) {
        Write-Host "⚠️  PostgreSQL is not reachable at ${HostName}:${Port} and no Windows service named 'postgresql*' was found." -ForegroundColor Yellow
        Write-Host "   If PostgreSQL is installed, start it manually (Services app), or switch to Docker mode: .\\Start-SystemDashboard.ps1 -DatabaseMode docker" -ForegroundColor Yellow
        return $false
    }

    $running = @($services | Where-Object Status -eq 'Running')
    if (-not $running) {
        $toStart = $services | Select-Object -First 1
        Write-Host "🔧 PostgreSQL is not reachable at ${HostName}:${Port}. Starting service '$($toStart.Name)'..." -ForegroundColor Yellow
        try {
            Start-Service -Name $toStart.Name -ErrorAction Stop
        }
        catch {
            Write-Host "❌ Failed to start service '$($toStart.Name)': $_" -ForegroundColor Red
            return $false
        }
    }

    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        if (Test-PostgresPort -HostName $HostName -Port $Port) {
            return $true
        }
        Start-Sleep -Seconds 1
    }

    Write-Host "❌ PostgreSQL is still not reachable at ${HostName}:${Port}." -ForegroundColor Red
    Write-Host "   Detected services:" -ForegroundColor Yellow
    Show-PostgresDiagnostics -Services $services
    Write-Host "   If PostgreSQL is listening on a different port, update Database.Port in config.json (and rerun)." -ForegroundColor Yellow
    return $false
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

# Ensure the server is reachable before prompting for credentials (Windows-local installs only)
if (-not (Ensure-PostgresReachable -HostName $DatabaseHost -Port $Port -PostgreSQLBinPath $PostgreSQLPath)) {
    exit 1
}

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

# Create or update users to ensure passwords stay in sync
$ingestUserSql = @'
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '{0}') THEN
        CREATE USER {0} WITH PASSWORD '{1}';
    ELSE
        ALTER USER {0} WITH PASSWORD '{1}';
    END IF;
END;
$$;
'@ -f $IngestUser, $ingestPassword

$readerUserSql = @'
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '{0}') THEN
        CREATE USER {0} WITH PASSWORD '{1}';
    ELSE
        ALTER USER {0} WITH PASSWORD '{1}';
    END IF;
END;
$$;
'@ -f $ReaderUser, $readerPassword

$success = $success -and (Invoke-PSQL -Command $ingestUserSql -Description "Creating/updating ingest user '$IngestUser'")
$success = $success -and (Invoke-PSQL -Command $readerUserSql -Description "Creating/updating reader user '$ReaderUser'")

if (-not $success) {
    Write-Host "❌ Database setup failed" -ForegroundColor Red
    exit 1
}

# Set up schema and permissions
Write-Host "`n🏗️  Setting up schema and permissions..." -ForegroundColor Yellow

$schemaPath = Join-Path $PSScriptRoot "..\telemetry\schema.sql"
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

    $connectionFile = Join-Path $PSScriptRoot "..\var\database-connection.json"
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
    Write-Host "1. Run: .\scripting\Install.ps1" -ForegroundColor White
    Write-Host "2. Start-ScheduledTask -TaskName 'SystemDashboard-Telemetry'" -ForegroundColor White
    Write-Host "3. Run: .\Start-SystemDashboard.ps1" -ForegroundColor White

}
else {
    Write-Host "`n❌ Database setup failed" -ForegroundColor Red
    Write-Host "Please check the errors above and try again" -ForegroundColor Red
    exit 1
}

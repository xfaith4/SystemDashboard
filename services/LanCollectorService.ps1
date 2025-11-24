#requires -Version 7
<#
.SYNOPSIS
    LAN Observability Collector Service
.DESCRIPTION
    Periodically collects LAN device information from the router and updates the database.
    This service runs continuously and performs:
    - Router client polling
    - Device snapshot recording
    - Syslog correlation
    - Retention cleanup
#>

param(
    [Parameter()][string]$ConfigPath,
    [Parameter()][int]$PollIntervalSeconds = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Import required modules
$telemetryModulePath = Join-Path $PSScriptRoot "..\tools\SystemDashboard.Telemetry.psm1"
$lanModulePath = Join-Path $PSScriptRoot "..\tools\LanObservability.psm1"

if (-not (Test-Path $telemetryModulePath)) {
    Write-Error "Telemetry module not found at: $telemetryModulePath"
    exit 1
}

if (-not (Test-Path $lanModulePath)) {
    Write-Error "LAN Observability module not found at: $lanModulePath"
    exit 1
}

Import-Module $telemetryModulePath -Force -Global
Import-Module $lanModulePath -Force -Global

# Setup logging
$logPath = Join-Path $PSScriptRoot "..\var\log"
if (-not (Test-Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath -Force | Out-Null
}
$logFile = Join-Path $logPath "lan-collector.log"

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$Level] $Message"
    $logMessage | Out-File -FilePath $logFile -Append -Encoding utf8
    Write-Host $logMessage
}

function Get-DatabaseConnection {
    param([hashtable]$Config)
    
    try {
        $dbHost = $Config.Database.Host
        $dbPort = $Config.Database.Port
        $dbName = $Config.Database.Database
        $dbUser = $Config.Database.Username
        $dbPassword = Resolve-SystemDashboardSecret -Secret $Config.Database.PasswordSecret
        
        if (-not $dbPassword) {
            Write-Log "Database password not configured" -Level 'ERROR'
            return $null
        }
        
        $connString = "Host=$dbHost;Port=$dbPort;Database=$dbName;Username=$dbUser;Password=$dbPassword;Timeout=30;"
        
        # Load Npgsql if not already loaded
        # Try common locations for Npgsql assembly
        $npgsqlLocations = @(
            (Join-Path ([System.IO.Path]::GetDirectoryName([System.Reflection.Assembly]::GetExecutingAssembly().Location)) "Npgsql.dll"),
            (Join-Path $PSScriptRoot "..\lib\Npgsql.dll"),
            "Npgsql.dll"  # Will use GAC or already loaded assembly
        )
        
        $loaded = $false
        foreach ($npgsqlPath in $npgsqlLocations) {
            if (Test-Path $npgsqlPath) {
                try {
                    Add-Type -Path $npgsqlPath -ErrorAction Stop
                    $loaded = $true
                    break
                } catch {
                    # Try next location
                }
            }
        }
        
        if (-not $loaded) {
            Write-Log "Npgsql assembly not found. Please install it or place Npgsql.dll in the lib/ directory." -Level 'ERROR'
            throw "Npgsql assembly not available"
        }
        
        $conn = New-Object Npgsql.NpgsqlConnection($connString)
        $conn.Open()
        
        Write-Log "Database connection established"
        return $conn
    }
    catch {
        Write-Log "Failed to connect to database: $_" -Level 'ERROR'
        return $null
    }
}

function Invoke-CollectionCycle {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][object]$DbConnection
    )
    
    Write-Log "Starting LAN collection cycle"
    
    try {
        # Get LAN settings from database
        $lanSettings = Get-LanSettings -DbConnection $DbConnection
        
        # Poll router and collect device data
        Invoke-LanDeviceCollection -Config $Config -DbConnection $DbConnection
        
        # Update device activity status
        $inactiveThreshold = [int]$lanSettings.inactive_threshold_minutes
        Update-DeviceActivityStatus -DbConnection $DbConnection -InactiveThresholdMinutes $inactiveThreshold
        
        # Correlate syslog events with devices (if enabled)
        if ($lanSettings.syslog_correlation_enabled -eq 'true') {
            Invoke-SyslogDeviceCorrelation -DbConnection $DbConnection -LookbackHours 1
        }
        
        Write-Log "Collection cycle completed successfully"
    }
    catch {
        Write-Log "Collection cycle failed: $_" -Level 'ERROR'
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level 'ERROR'
    }
}

function Invoke-RetentionCleanup {
    param(
        [Parameter(Mandatory)][object]$DbConnection,
        [Parameter()][int]$RetentionDays = 7
    )
    
    Write-Log "Starting retention cleanup"
    
    try {
        Invoke-DeviceSnapshotRetention -DbConnection $DbConnection -RetentionDays $RetentionDays
        Write-Log "Retention cleanup completed"
    }
    catch {
        Write-Log "Retention cleanup failed: $_" -Level 'ERROR'
    }
}

# Main service loop
try {
    Write-Log "LAN Collector Service starting"
    
    # Load configuration
    if (-not $ConfigPath) {
        $ConfigPath = Join-Path $PSScriptRoot "..\config.json"
    }
    
    Write-Log "Loading configuration from: $ConfigPath"
    $config = Read-SystemDashboardConfig -ConfigPath $ConfigPath
    
    # Get poll interval from config or use parameter
    if ($config.Service.Asus.PollIntervalSeconds) {
        $PollIntervalSeconds = $config.Service.Asus.PollIntervalSeconds
    }
    
    Write-Log "Poll interval: $PollIntervalSeconds seconds"
    
    # Connect to database
    $dbConn = Get-DatabaseConnection -Config $config
    if (-not $dbConn) {
        Write-Log "Failed to establish database connection. Service cannot start." -Level 'ERROR'
        exit 1
    }
    
    # Track last cleanup time
    $lastCleanup = [DateTime]::MinValue
    $cleanupIntervalHours = 24
    
    Write-Log "Service loop starting"
    
    while ($true) {
        try {
            # Perform collection cycle
            Invoke-CollectionCycle -Config $config -DbConnection $dbConn
            
            # Perform retention cleanup once per day
            $now = Get-Date
            if (($now - $lastCleanup).TotalHours -ge $cleanupIntervalHours) {
                $lanSettings = Get-LanSettings -DbConnection $dbConn
                $retentionDays = [int]$lanSettings.snapshot_retention_days
                Invoke-RetentionCleanup -DbConnection $dbConn -RetentionDays $retentionDays
                $lastCleanup = $now
            }
            
            # Wait for next cycle
            Write-Log "Waiting $PollIntervalSeconds seconds until next collection"
            Start-Sleep -Seconds $PollIntervalSeconds
        }
        catch {
            Write-Log "Error in service loop: $_" -Level 'ERROR'
            
            # Check if database connection is still valid
            try {
                if ($dbConn.State -ne 'Open') {
                    Write-Log "Database connection lost. Attempting to reconnect..." -Level 'WARN'
                    $dbConn.Close()
                    $dbConn = Get-DatabaseConnection -Config $config
                }
            }
            catch {
                Write-Log "Failed to check/reconnect database: $_" -Level 'ERROR'
            }
            
            # Short sleep before retry
            Start-Sleep -Seconds 60
        }
    }
}
catch {
    Write-Log "Fatal error in service: $_" -Level 'ERROR'
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level 'ERROR'
    exit 1
}
finally {
    if ($dbConn -and $dbConn.State -eq 'Open') {
        $dbConn.Close()
        Write-Log "Database connection closed"
    }
    Write-Log "LAN Collector Service stopped"
}

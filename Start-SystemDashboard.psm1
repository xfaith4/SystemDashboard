### BEGIN FILE: SystemDashboard Listener
#requires -Version 7
<#
.SYNOPSIS
    HTTP-based system metrics endpoint with extended telemetry.
.DESCRIPTION
    Exposes CPU, memory, disk, events, network, uptime, processes, and latency.
    Provides a Start-SystemDashboardListener function used by tests.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Determine config path with fallback for empty $PSScriptRoot
# In some contexts (e.g., pwsh -Command), $PSScriptRoot may be empty
# Use $PSCommandPath as fallback, then Get-Location as last resort
$script:ModuleRoot = if ($PSScriptRoot) {
    $PSScriptRoot
} elseif ($PSCommandPath) {
    Split-Path -Parent $PSCommandPath
} else {
    Get-Location
}

$localConfigPath = Join-Path $script:ModuleRoot 'config.local.json'
$ConfigPath = if ($env:SYSTEMDASHBOARD_CONFIG) {
    $env:SYSTEMDASHBOARD_CONFIG
} elseif (Test-Path -LiteralPath $localConfigPath) {
    $localConfigPath
} else {
    Join-Path $script:ModuleRoot 'config.json'
}

# Configuration is already set by the importing script via $env:SYSTEMDASHBOARD_CONFIG
# No need to re-import the module here - this would cause circular reference

$script:Config = @{}
$script:ConfigPath = $null
$script:ConfigBase = $script:ModuleRoot
if ($ConfigPath -and (Test-Path -LiteralPath $ConfigPath -ErrorAction SilentlyContinue)) {
    $resolvedConfig = (Resolve-Path -LiteralPath $ConfigPath).Path
    $script:ConfigPath = $resolvedConfig
    $script:ConfigBase = Split-Path -Parent $resolvedConfig
    $script:Config = Get-Content -LiteralPath $resolvedConfig -Raw | ConvertFrom-Json
}

$script:ListenerStartedAt = $null
$script:ListenerPrefix = $null
$script:StartupIssues = @()
$script:StaticReady = $true
$script:LastError = $null
$script:LastErrorAt = $null
$script:DbFailureCount = 0
$script:DbLastFailureAt = $null
$script:DbCircuitUntil = $null

function Get-ListenerLogSettings {
    $logging = if ($script:Config) { $script:Config.Logging } else { $null }
    $format = if ($env:SYSTEMDASHBOARD_LOG_FORMAT) {
        $env:SYSTEMDASHBOARD_LOG_FORMAT
    } elseif ($logging -and $logging.PSObject.Properties['Format'] -and $logging.Format) {
        $logging.Format
    } else {
        'text'
    }

    $maxSizeMb = if ($env:SYSTEMDASHBOARD_LOG_MAX_MB) {
        [int]$env:SYSTEMDASHBOARD_LOG_MAX_MB
    } elseif ($logging -and $logging.PSObject.Properties['MaxSizeMB'] -and $logging.MaxSizeMB) {
        [int]$logging.MaxSizeMB
    } else {
        10
    }

    $maxFiles = if ($env:SYSTEMDASHBOARD_LOG_MAX_FILES) {
        [int]$env:SYSTEMDASHBOARD_LOG_MAX_FILES
    } elseif ($logging -and $logging.PSObject.Properties['MaxFiles'] -and $logging.MaxFiles) {
        [int]$logging.MaxFiles
    } else {
        5
    }

    return @{
        Format = $format.ToLowerInvariant()
        MaxSizeMB = $maxSizeMb
        MaxFiles = $maxFiles
    }
}

function Rotate-LogFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$MaxSizeMB = 10,
        [int]$MaxFiles = 5
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $info = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $info) {
        return
    }

    if ($info.Length -lt ($MaxSizeMB * 1MB)) {
        return
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $archivePath = "{0}.{1}.log" -f $Path, $timestamp
    try {
        Move-Item -LiteralPath $Path -Destination $archivePath -Force
    } catch {
        return
    }

    if ($MaxFiles -le 0) {
        return
    }

    $dir = Split-Path -Parent $Path
    $base = [System.IO.Path]::GetFileName($Path)
    $archives = Get-ChildItem -LiteralPath $dir -Filter "$base.*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

    if ($archives.Count -gt $MaxFiles) {
        $archives | Select-Object -Skip $MaxFiles | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    $ts = Get-Date -Format o
    $line = "[$ts] [$Level] $Message"
    Write-Information $line -InformationAction Continue
    if ($Level -eq 'ERROR') {
        $script:LastError = $Message
        $script:LastErrorAt = Get-Date
    }

    $logPath = $env:SYSTEMDASHBOARD_LISTENER_LOG
    if (-not $logPath -and $script:Config) {
        $loggingProp = $script:Config.PSObject.Properties['Logging']
        if ($loggingProp -and $loggingProp.Value) {
            $logging = $loggingProp.Value
            $logPathProp = $logging.PSObject.Properties['LogPath']
            if ($logPathProp -and $logPathProp.Value) {
                try {
                    $logPath = Resolve-ConfigPathValue $logPathProp.Value
                } catch {
                    $logPath = $null
                }
            }
        }
    }
    if ($logPath) {
        try {
            $settings = Get-ListenerLogSettings
            Rotate-LogFile -Path $logPath -MaxSizeMB $settings.MaxSizeMB -MaxFiles $settings.MaxFiles

            $payload = if ($settings.Format -eq 'json') {
                @{ timestamp = $ts; level = $Level; message = $Message } | ConvertTo-Json -Compress
            } else {
                $line
            }
            $payload | Out-File -FilePath $logPath -Append -Encoding utf8
        } catch {
            # Avoid logging loops if the log path is invalid.
        }
    }
}

function Get-DbTimeoutSettings {
    $dbConfig = if ($script:Config) { $script:Config.Database } else { $null }
    $connectSeconds = if ($env:SYSTEMDASHBOARD_DB_CONNECT_TIMEOUT) {
        [int]$env:SYSTEMDASHBOARD_DB_CONNECT_TIMEOUT
    } elseif ($dbConfig -and $dbConfig.PSObject.Properties['ConnectTimeoutSeconds'] -and $dbConfig.ConnectTimeoutSeconds) {
        [int]$dbConfig.ConnectTimeoutSeconds
    } else {
        5
    }

    $statementSeconds = if ($env:SYSTEMDASHBOARD_DB_STATEMENT_TIMEOUT) {
        [int]$env:SYSTEMDASHBOARD_DB_STATEMENT_TIMEOUT
    } elseif ($dbConfig -and $dbConfig.PSObject.Properties['StatementTimeoutSeconds'] -and $dbConfig.StatementTimeoutSeconds) {
        [int]$dbConfig.StatementTimeoutSeconds
    } else {
        8
    }

    return @{
        ConnectSeconds = $connectSeconds
        StatementMs = ($statementSeconds * 1000)
    }
}

function Get-DbCircuitSettings {
    $dbConfig = if ($script:Config) { $script:Config.Database } else { $null }
    $circuit = if ($dbConfig) { $dbConfig.CircuitBreaker } else { $null }

    $threshold = if ($env:SYSTEMDASHBOARD_DB_CIRCUIT_THRESHOLD) {
        [int]$env:SYSTEMDASHBOARD_DB_CIRCUIT_THRESHOLD
    } elseif ($circuit -and $circuit.PSObject.Properties['Threshold'] -and $circuit.Threshold) {
        [int]$circuit.Threshold
    } else {
        3
    }

    $windowSeconds = if ($env:SYSTEMDASHBOARD_DB_CIRCUIT_WINDOW_SECONDS) {
        [int]$env:SYSTEMDASHBOARD_DB_CIRCUIT_WINDOW_SECONDS
    } elseif ($circuit -and $circuit.PSObject.Properties['WindowSeconds'] -and $circuit.WindowSeconds) {
        [int]$circuit.WindowSeconds
    } else {
        60
    }

    $openSeconds = if ($env:SYSTEMDASHBOARD_DB_CIRCUIT_OPEN_SECONDS) {
        [int]$env:SYSTEMDASHBOARD_DB_CIRCUIT_OPEN_SECONDS
    } elseif ($circuit -and $circuit.PSObject.Properties['OpenSeconds'] -and $circuit.OpenSeconds) {
        [int]$circuit.OpenSeconds
    } else {
        30
    }

    return @{
        Threshold = $threshold
        WindowSeconds = $windowSeconds
        OpenSeconds = $openSeconds
    }
}

function Test-DbCircuitOpen {
    $now = Get-Date
    if ($script:DbCircuitUntil -and $script:DbCircuitUntil -gt $now) {
        return @{ Open = $true; Until = $script:DbCircuitUntil }
    }
    return @{ Open = $false; Until = $null }
}

function Register-DbFailure {
    param([string]$ErrorMessage)

    $settings = Get-DbCircuitSettings
    $now = Get-Date

    if (-not $script:DbLastFailureAt -or ($now - $script:DbLastFailureAt).TotalSeconds -gt $settings.WindowSeconds) {
        $script:DbFailureCount = 1
    } else {
        $script:DbFailureCount += 1
    }

    $script:DbLastFailureAt = $now

    if ($script:DbFailureCount -ge $settings.Threshold) {
        $script:DbCircuitUntil = $now.AddSeconds($settings.OpenSeconds)
        Write-Log -Level 'WARN' -Message ("DB circuit opened for {0}s after {1} failures." -f $settings.OpenSeconds, $script:DbFailureCount)
    }

    if ($ErrorMessage) {
        $script:LastError = "DB failure: $ErrorMessage"
        $script:LastErrorAt = $now
        Write-Log -Level 'WARN' -Message ("DB failure: {0}" -f $ErrorMessage)
    }
}

function Reset-DbCircuit {
    $script:DbFailureCount = 0
    $script:DbLastFailureAt = $null
    $script:DbCircuitUntil = $null
}

function Get-ListenerStatusPayload {
    $now = Get-Date
    $uptime = if ($script:ListenerStartedAt) { New-TimeSpan -Start $script:ListenerStartedAt -End $now } else { $null }
    $circuit = Test-DbCircuitOpen

    return @{
        ok = ($script:StartupIssues.Count -eq 0) -and (-not $circuit.Open)
        time = $now.ToString('o')
        listener = @{
            prefix = $script:ListenerPrefix
            started_at = if ($script:ListenerStartedAt) { $script:ListenerStartedAt.ToString('o') } else { $null }
            uptime_seconds = if ($uptime) { [int]$uptime.TotalSeconds } else { $null }
            pid = $PID
        }
        static_ready = $script:StaticReady
        startup_issues = $script:StartupIssues
        last_error = if ($script:LastError) {
            @{
                message = $script:LastError
                time = if ($script:LastErrorAt) { $script:LastErrorAt.ToString('o') } else { $null }
            }
        } else { $null }
        db = @{
            circuit_open = $circuit.Open
            circuit_until = if ($circuit.Open -and $circuit.Until) { $circuit.Until.ToString('o') } else { $null }
            failure_count = $script:DbFailureCount
            last_failure_at = if ($script:DbLastFailureAt) { $script:DbLastFailureAt.ToString('o') } else { $null }
        }
    }
}

function Get-MockSystemMetrics {
    [CmdletBinding()]
    param()

    Write-Log -Level 'INFO' -Message "Generating mock system metrics for demonstration purposes"

    $nowUtc = (Get-Date).ToUniversalTime()
    $computerName = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { "MockHost" }

    # Mock CPU, Memory, Disk data
    $cpuPct = Get-Random -Minimum 5 -Maximum 85
    $totalMemGB = 16.0
    $usedMemGB = Get-Random -Minimum 4.0 -Maximum 12.0
    $freeMemGB = $totalMemGB - $usedMemGB
    $memPct = [math]::Round(($usedMemGB / $totalMemGB), 4)

    $disks = @(
        [pscustomobject]@{
            Drive = "C"
            TotalGB = 500.0
            UsedGB = Get-Random -Minimum 100.0 -Maximum 400.0
            UsedPct = 0.6
        },
        [pscustomobject]@{
            Drive = "D"
            TotalGB = 1000.0
            UsedGB = Get-Random -Minimum 200.0 -Maximum 800.0
            UsedPct = 0.4
        }
    )

    # Mock uptime
    $uptime = @{
        Days = Get-Random -Minimum 0 -Maximum 30
        Hours = Get-Random -Minimum 0 -Maximum 23
        Minutes = Get-Random -Minimum 0 -Maximum 59
    }

    # Mock events
    $warnSources = @('Application Error', 'System', 'DNS Client', 'Service Control Manager')
    $errSources = @('Application Error', 'System', 'DCOM')
    $warnSummary = $warnSources | ForEach-Object {
        [pscustomobject]@{ Source=$_; Count=(Get-Random -Minimum 1 -Maximum 10) }
    }
    $errSummary = $errSources | ForEach-Object {
        [pscustomobject]@{ Source=$_; Count=(Get-Random -Minimum 1 -Maximum 5) }
    }

    # Mock network
    $netUsage = @(
        [pscustomobject]@{
            Adapter="Ethernet";
            BytesSentPerSec=(Get-Random -Minimum 1000 -Maximum 50000);
            BytesRecvPerSec=(Get-Random -Minimum 5000 -Maximum 100000)
        }
    )
    $latencyMs = Get-Random -Minimum 1 -Maximum 100

    # Mock processes
    $processNames = @('explorer', 'chrome', 'code', 'powershell', 'svchost')
    $topProcs = $processNames | ForEach-Object {
        $workingSetMb = Get-Random -Minimum 50 -Maximum 600
        $privateMb = Get-Random -Minimum 25 -Maximum 400
        $ioReadMb = Get-Random -Minimum 1 -Maximum 50
        $ioWriteMb = Get-Random -Minimum 1 -Maximum 30
        [pscustomobject]@{
            Name=$_;
            CPU=([math]::Round((Get-Random -Minimum 0.1 -Maximum 25.5), 2));
            Id=(Get-Random -Minimum 1000 -Maximum 9999);
            WorkingSet64=($workingSetMb * 1MB);
            PrivateMemorySize64=($privateMb * 1MB);
            IOReadBytes=($ioReadMb * 1MB);
            IOWriteBytes=($ioWriteMb * 1MB)
        }
    }

    return [pscustomobject]@{
        Time          = $nowUtc
        ComputerName  = $computerName
        CPU           = @{ Pct = $cpuPct }
        Memory        = @{ TotalGB=$totalMemGB; FreeGB=$freeMemGB; UsedGB=$usedMemGB; Pct=$memPct }
        Disk          = $disks
        Uptime        = $uptime
        Events        = @{ Warnings=$warnSummary; Errors=$errSummary }
        Network       = @{ Usage=$netUsage; LatencyMs=$latencyMs }
        Processes     = $topProcs
    }
}

function Resolve-ConfigPathValue {
    [CmdletBinding()]
    param(
        [Parameter()][string]$PathValue
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $null
    }

    try {
        $expanded = [Environment]::ExpandEnvironmentVariables($PathValue)
        if ($expanded.StartsWith('~')) {
            $userProfilePath = [Environment]::GetFolderPath('UserProfile')
            if ($userProfilePath) {
                $expanded = Join-Path $userProfilePath ($expanded.Substring(1).TrimStart('\\','/'))
            }
        }

        if ([System.IO.Path]::IsPathRooted($expanded)) {
            return [System.IO.Path]::GetFullPath($expanded)
        }

        $basePath = if ($script:ConfigBase) { $script:ConfigBase } else { $PSScriptRoot }
        return [System.IO.Path]::GetFullPath((Join-Path $basePath $expanded))
    }
    catch {
        throw "Failed to resolve path '$PathValue'. $_"
    }
}

function Get-ContentType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    switch ($extension) {
        '.css'  { 'text/css' }
        '.js'   { 'application/javascript' }
        '.json' { 'application/json' }
        '.svg'  { 'image/svg+xml' }
        '.png'  { 'image/png' }
        '.jpg'  { 'image/jpeg' }
        '.jpeg' { 'image/jpeg' }
        '.ico'  { 'image/x-icon' }
        Default { 'text/html' }
    }
}

function Get-FallbackHtml {
    param([string[]]$Issues)

    $issueItems = if ($Issues -and $Issues.Count -gt 0) {
        ($Issues | ForEach-Object { "<li>$_</li>" }) -join ''
    } else {
        '<li>Unknown startup issue.</li>'
    }

    return @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>System Dashboard (Degraded)</title>
  <style>
    body { font-family: Segoe UI, Arial, sans-serif; margin: 0; padding: 2rem; background: #0f172a; color: #e2e8f0; }
    .card { max-width: 780px; background: #111827; padding: 1.5rem; border-radius: 12px; border: 1px solid #1f2937; }
    h1 { margin-top: 0; color: #f59e0b; }
    a { color: #38bdf8; }
    ul { margin: 0.75rem 0 0 1.25rem; }
    code { background: #0b1120; padding: 0.1rem 0.3rem; border-radius: 4px; }
  </style>
</head>
<body>
  <div class="card">
    <h1>System Dashboard running in degraded mode</h1>
    <p>The listener is online, but the web assets or configuration are missing or invalid.</p>
    <p>Detected issues:</p>
    <ul>$issueItems</ul>
    <p>Check <code>/api/status</code> for details and review the listener log for traces.</p>
  </div>
</body>
</html>
"@
}

function Resolve-SecretValue {
    [CmdletBinding()]
    param([string]$Secret)

    if (-not $Secret) {
        return $null
    }
    if ($Secret -match '^env:(.+)$') {
        return (Get-Item "Env:$($Matches[1])" -ErrorAction SilentlyContinue).Value
    }
    return $Secret
}

function Get-PostgresConfig {
    if (-not $script:Config.Database) {
        return $null
    }

    $db = $script:Config.Database
    # NOTE: $Host is a built-in, read-only automatic variable in PowerShell.
    # Use a different name to avoid assignment errors.
    $dbHost = if ($env:DASHBOARD_DB_HOST) { [string]$env:DASHBOARD_DB_HOST } elseif ($db.Host) { [string]$db.Host } else { 'localhost' }
    $port = if ($env:DASHBOARD_DB_PORT) { [int]$env:DASHBOARD_DB_PORT } elseif ($db.Port) { [int]$db.Port } else { 5432 }
    $database = if ($env:DASHBOARD_DB_NAME) { [string]$env:DASHBOARD_DB_NAME } elseif ($db.Database) { [string]$db.Database } else { 'system_dashboard' }
    $username = if ($env:DASHBOARD_DB_USER) { [string]$env:DASHBOARD_DB_USER } elseif ($db.Username) { [string]$db.Username } else { 'sysdash_reader' }
    $password = if ($env:DASHBOARD_DB_PASSWORD) { [string]$env:DASHBOARD_DB_PASSWORD } else { Resolve-SecretValue $db.PasswordSecret }
    if (-not $password -and $db.Password) {
        $password = [string]$db.Password
    }
    if (-not $password) {
        $password = (Get-Item 'Env:SYSTEMDASHBOARD_DB_READER_PASSWORD' -ErrorAction SilentlyContinue).Value
        if ($password -and (-not $db.Username)) {
            $username = 'sysdash_reader'
        }
    }
    $psqlPath = if ($db.PsqlPath -and (Test-Path -LiteralPath $db.PsqlPath)) {
        $db.PsqlPath
    } else {
        $cmd = Get-Command psql -ErrorAction SilentlyContinue
        if ($cmd) { $cmd.Source } else { $null }
    }

    if (-not $password -or -not $psqlPath) {
        return $null
    }

    return @{
        Host = $dbHost
        Port = $port
        Database = $database
        Username = $username
        Password = $password
        PsqlPath = $psqlPath
    }
}

function Invoke-PostgresJsonQuery {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Sql)

    $cfg = Get-PostgresConfig
    if (-not $cfg) {
        Write-Log -Level 'WARN' -Message 'Postgres config missing; cannot query LAN data.'
        Register-DbFailure -ErrorMessage 'Postgres config missing'
        return $null
    }

    $circuit = Test-DbCircuitOpen
    if ($circuit.Open) {
        Write-Log -Level 'WARN' -Message ("DB circuit open until {0}; skipping query." -f $circuit.Until)
        return $null
    }

    $timeouts = Get-DbTimeoutSettings
    $previousPassword = $env:PGPASSWORD
    $previousConnectTimeout = $env:PGCONNECT_TIMEOUT
    $previousOptions = $env:PGOPTIONS
    $env:PGPASSWORD = $cfg.Password
    $env:PGCONNECT_TIMEOUT = [string]$timeouts.ConnectSeconds
    $statementOption = "-c statement_timeout=$($timeouts.StatementMs)"
    $env:PGOPTIONS = if ($previousOptions) { "$statementOption $previousOptions" } else { $statementOption }
    try {
        $output = & $cfg.PsqlPath -h $cfg.Host -p $cfg.Port -U $cfg.Username -d $cfg.Database -t -A -q -v ON_ERROR_STOP=1 -c $Sql 2>&1
        if ($LASTEXITCODE -ne 0) {
            Register-DbFailure -ErrorMessage ($output -join ' ')
            return $null
        }
        Reset-DbCircuit
    } finally {
        if ($previousPassword) {
            $env:PGPASSWORD = $previousPassword
        } else {
            Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
        }
        if ($previousConnectTimeout) {
            $env:PGCONNECT_TIMEOUT = $previousConnectTimeout
        } else {
            Remove-Item Env:PGCONNECT_TIMEOUT -ErrorAction SilentlyContinue
        }
        if ($previousOptions) {
            $env:PGOPTIONS = $previousOptions
        } else {
            Remove-Item Env:PGOPTIONS -ErrorAction SilentlyContinue
        }
    }

    $lines = @($output | Where-Object { $_ -and $_.Trim() -ne '' } | ForEach-Object { $_.TrimEnd() })
    if (-not $lines) {
        return '[]'
    }
    $json = $lines -join "`n"
    return $json.Trim()
}

function Test-PostgresQuery {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Sql)

    $cfg = Get-PostgresConfig
    if (-not $cfg) {
        Register-DbFailure -ErrorMessage 'Postgres config missing'
        return @{ ok = $false; error = 'Postgres config missing or incomplete.' }
    }

    $circuit = Test-DbCircuitOpen
    if ($circuit.Open) {
        return @{ ok = $false; error = ("DB circuit open until {0}" -f $circuit.Until); circuit_open = $true }
    }

    $timeouts = Get-DbTimeoutSettings
    $previousPassword = $env:PGPASSWORD
    $previousConnectTimeout = $env:PGCONNECT_TIMEOUT
    $previousOptions = $env:PGOPTIONS
    $env:PGPASSWORD = $cfg.Password
    $env:PGCONNECT_TIMEOUT = [string]$timeouts.ConnectSeconds
    $statementOption = "-c statement_timeout=$($timeouts.StatementMs)"
    $env:PGOPTIONS = if ($previousOptions) { "$statementOption $previousOptions" } else { $statementOption }
    try {
        $output = & $cfg.PsqlPath -h $cfg.Host -p $cfg.Port -U $cfg.Username -d $cfg.Database -t -A -q -v ON_ERROR_STOP=1 -c $Sql 2>&1
        if ($LASTEXITCODE -ne 0) {
            Register-DbFailure -ErrorMessage ($output -join ' ')
            return @{ ok = $false; error = ($output -join ' ') }
        }
        Reset-DbCircuit
    } finally {
        if ($previousPassword) {
            $env:PGPASSWORD = $previousPassword
        } else {
            Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
        }
        if ($previousConnectTimeout) {
            $env:PGCONNECT_TIMEOUT = $previousConnectTimeout
        } else {
            Remove-Item Env:PGCONNECT_TIMEOUT -ErrorAction SilentlyContinue
        }
        if ($previousOptions) {
            $env:PGOPTIONS = $previousOptions
        } else {
            Remove-Item Env:PGOPTIONS -ErrorAction SilentlyContinue
        }
    }

    return @{ ok = $true }
}

function Escape-SqlLiteral {
    param([string]$Value)
    return ($Value -replace "'", "''")
}

function Convert-IsoDurationToMinutes {
    param([string]$Duration)

    if (-not $Duration) {
        return 1440
    }
    if ($Duration -match '^PT(?:(\d+)H)?(?:(\d+)M)?$') {
        $hours = if ($Matches[1]) { [int]$Matches[1] } else { 0 }
        $minutes = if ($Matches[2]) { [int]$Matches[2] } else { 0 }
        $total = ($hours * 60) + $minutes
        if ($total -gt 0) {
            return $total
        }
    }
    return 1440
}

function Try-ParseQueryDateTime {
    param([string]$Value)

    if (-not $Value) {
        return $null
    }
    $parsed = $null
    try {
        $styles = [System.Globalization.DateTimeStyles]::AssumeLocal
        $culture = [System.Globalization.CultureInfo]::InvariantCulture
        if ([DateTime]::TryParse($Value, $culture, $styles, [ref]$parsed)) {
            return $parsed
        }
    } catch {
        # Fallback for runtimes that don't expose the 4-arg TryParse overload.
    }
    try {
        if ([DateTime]::TryParse($Value, [ref]$parsed)) {
            return $parsed
        }
    } catch {}
    return $null
}

function Resolve-QueryTimeRange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.Specialized.NameValueCollection]$Query,
        [int]$DefaultHours = 24
    )

    $end = Try-ParseQueryDateTime $Query['end']
    $start = Try-ParseQueryDateTime $Query['start']

    if (-not $end) {
        $end = Get-Date
    }
    if (-not $start) {
        $start = $end.AddHours(-$DefaultHours)
    }
    if ($start -gt $end) {
        $tmp = $start
        $start = $end
        $end = $tmp
    }

    return @{
        StartUtc = $start.ToUniversalTime()
        EndUtc = $end.ToUniversalTime()
    }
}

function Read-RequestBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Net.HttpListenerRequest]$Request
    )

    $encoding = if ($Request.ContentEncoding) { $Request.ContentEncoding } else { [Text.Encoding]::UTF8 }
    $reader = New-Object System.IO.StreamReader($Request.InputStream, $encoding)
    try {
        return $reader.ReadToEnd()
    } finally {
        $reader.Close()
    }
}

function Get-ConfigPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter()][object]$Parent,
        [Parameter(Mandatory)][string]$PropertyName
    )

    if (-not $Parent -or [string]::IsNullOrWhiteSpace($PropertyName)) {
        return $null
    }

    $psProp = $Parent.PSObject.Properties[$PropertyName]
    if ($psProp) {
        return $psProp.Value
    }

    if ($Parent -is [System.Collections.IDictionary] -and $Parent.Contains($PropertyName)) {
        return $Parent[$PropertyName]
    }

    return $null
}

function Get-LayoutStorePath {
    [CmdletBinding()]
    param()

    $path = $null
    $service = Get-ConfigPropertyValue -Parent $script:Config -PropertyName 'Service'
    $serviceUi = Get-ConfigPropertyValue -Parent $service -PropertyName 'Ui'
    $serviceLayoutPath = Get-ConfigPropertyValue -Parent $serviceUi -PropertyName 'LayoutPath'
    $configUi = Get-ConfigPropertyValue -Parent $script:Config -PropertyName 'Ui'
    $configLayoutPath = Get-ConfigPropertyValue -Parent $configUi -PropertyName 'LayoutPath'

    if ($serviceLayoutPath) {
        $path = $serviceLayoutPath
    } elseif ($configLayoutPath) {
        $path = $configLayoutPath
    }
    if (-not $path) {
        $path = './var/ui/layouts.json'
    }

    try {
        return Resolve-ConfigPathValue $path
    } catch {
        Write-Log -Level 'WARN' -Message "Layout store path invalid: $path ($($_.Exception.Message))"
        return $null
    }
}

function Load-LayoutStore {
    [CmdletBinding()]
    param()

    $path = Get-LayoutStorePath
    if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }
    try {
        $raw = Get-Content -LiteralPath $path -Raw
        if (-not $raw) {
            return $null
        }
        return $raw | ConvertFrom-Json
    } catch {
        Write-Log -Level 'WARN' -Message "Failed to read layout store: $($_.Exception.Message)"
        return $null
    }
}

function Save-LayoutStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Store
    )

    $path = Get-LayoutStorePath
    if (-not $path) {
        return $false
    }
    try {
        $dir = Split-Path -Parent $path
        if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
        $json = $Store | ConvertTo-Json -Depth 8
        Set-Content -LiteralPath $path -Value $json -Encoding UTF8
        return $true
    } catch {
        Write-Log -Level 'WARN' -Message "Failed to save layout store: $($_.Exception.Message)"
        return $false
    }
}

function Write-JsonResponse {
    param(
        [Parameter(Mandatory)][System.Net.HttpListenerResponse]$Response,
        [Parameter(Mandatory)][string]$Json,
        [int]$StatusCode = 200
    )
    $buf = [Text.Encoding]::UTF8.GetBytes($Json)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = 'application/json'
    $Response.Headers['Cache-Control'] = 'no-store'
    $Response.ContentLength64 = $buf.Length
    $Response.OutputStream.Write($buf, 0, $buf.Length)
    $Response.Close()
}

function Safe-JsonResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Net.HttpListenerResponse]$Response,
        [Parameter(Mandatory)][string]$Json,
        [int]$StatusCode = 200,
        [string]$Context = 'response'
    )

    try {
        Write-JsonResponse -Response $Response -Json $Json -StatusCode $StatusCode
        return $true
    } catch {
        Write-Log -Level 'WARN' -Message ("Failed to write {0}: {1}" -f $Context, $_.Exception.Message)
        return $false
    }
}

function Test-ClientDisconnectException {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Exception]$Exception
    )

    $current = $Exception
    while ($current) {
        if ($current -is [System.Net.HttpListenerException]) {
            if ($current.ErrorCode -eq 64 -or $current.ErrorCode -eq 995) {
                return $true
            }
        }
        if ($current -is [System.IO.IOException]) {
            if ($current.HResult -eq -2147024832) {
                return $true
            }
        }
        if ($current.Message -match 'network name is no longer available') {
            return $true
        }
        $current = $current.InnerException
    }

    return $false
}

function Ensure-UrlAcl {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Prefix)
    if (-not $IsWindows) { return }
    try {
        Remove-UrlAcl -Prefix $Prefix
        $exists = netsh http show urlacl | Select-String -SimpleMatch $Prefix -Quiet
        if (-not $exists) {
            $user = "$env:USERDOMAIN\$env:USERNAME"
            Start-Process -FilePath netsh -ArgumentList @('http','add','urlacl',"url=$Prefix",("user={0}" -f $user)) -Wait -WindowStyle Hidden | Out-Null
        }
    } catch {
        Write-Log -Level 'WARN' -Message "Ensure-UrlAcl failed: $_"
    }
}

function Remove-UrlAcl {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Prefix)
    if (-not $IsWindows) { return }
    try {
        Start-Process -FilePath netsh -ArgumentList @('http','delete','urlacl',"url=$Prefix") -Wait -WindowStyle Hidden | Out-Null
    } catch {
        Write-Log -Level 'WARN' -Message "Remove-UrlAcl failed: $_"
    }
}

function Start-SystemDashboardListener {
    [CmdletBinding()]
    param(
        [Parameter()][string] $Prefix,
        [Parameter()][string] $Root,
        [Parameter()][string] $IndexHtml,
        [Parameter()][string] $CssFile,
        [Parameter()][string] $PingTarget
    )
    if (-not $Prefix) {
        if ($env:SYSTEMDASHBOARD_PREFIX) { $Prefix = $env:SYSTEMDASHBOARD_PREFIX }
        elseif ($script:Config.Prefix) { $Prefix = $script:Config.Prefix }
    }
    if (-not $Root) {
        if ($script:Config.Root) { $Root = $script:Config.Root }
        elseif ($env:SYSTEMDASHBOARD_ROOT) { $Root = $env:SYSTEMDASHBOARD_ROOT }
    }
    if (-not $IndexHtml -and $script:Config.IndexHtml) { $IndexHtml = $script:Config.IndexHtml }
    if (-not $CssFile -and $script:Config.CssFile) { $CssFile = $script:Config.CssFile }
    if (-not $PingTarget) { $PingTarget = $script:Config.PingTarget }
    if (-not $PingTarget) { $PingTarget = '1.1.1.1' }

    $startupIssues = @()
    $staticReady = $true

    if (-not $Prefix) {
        $Prefix = 'http://localhost:15000/'
        $startupIssues += "Prefix not set; defaulting to $Prefix"
    }

    try {
        $Root = Resolve-ConfigPathValue $Root
    } catch {
        $startupIssues += "Root path invalid: $Root"
        $Root = $null
        $staticReady = $false
    }

    if (-not $Root) {
        $Root = Join-Path $script:ModuleRoot 'wwwroot'
        $startupIssues += "Root not set; defaulting to $Root"
    }

    if (-not $IndexHtml) {
        $IndexHtml = [System.IO.Path]::GetFullPath((Join-Path $Root 'index.html'))
    } else {
        try {
            $IndexHtml = Resolve-ConfigPathValue $IndexHtml
        } catch {
            $startupIssues += "IndexHtml path invalid: $IndexHtml"
            $staticReady = $false
        }
    }

    if (-not $CssFile) {
        $CssFile = [System.IO.Path]::GetFullPath((Join-Path $Root 'styles.css'))
    } else {
        try {
            $CssFile = Resolve-ConfigPathValue $CssFile
        } catch {
            $startupIssues += "CssFile path invalid: $CssFile"
            $staticReady = $false
        }
    }

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        $startupIssues += "Root path not found: $Root"
        $staticReady = $false
    }

    if (-not (Test-Path -LiteralPath $IndexHtml -PathType Leaf)) {
        $startupIssues += "IndexHtml not found: $IndexHtml"
        $staticReady = $false
    }

    if (-not (Test-Path -LiteralPath $CssFile -PathType Leaf)) {
        $startupIssues += "CssFile not found: $CssFile"
        $staticReady = $false
    }

    $AppJsFile = if ($IndexHtml) { Join-Path (Split-Path -Parent $IndexHtml) 'app.js' } else { $null }
    if ($AppJsFile -and -not (Test-Path -LiteralPath $AppJsFile -PathType Leaf)) {
        $startupIssues += "AppJsFile not found: $AppJsFile"
        $staticReady = $false
    }

    $script:StartupIssues = $startupIssues
    $script:StaticReady = $staticReady
    $fallbackHtml = Get-FallbackHtml -Issues $startupIssues

    $listener = $null
    $started = $false
    $attempts = 0
    $maxAttempts = 10
    $basePrefix = $Prefix
    try {
        $baseUri = [System.Uri]$basePrefix
    } catch {
        $startupIssues += "Prefix invalid: $basePrefix"
        $basePrefix = 'http://localhost:15000/'
        $baseUri = [System.Uri]$basePrefix
        $script:StartupIssues = $startupIssues
        $fallbackHtml = Get-FallbackHtml -Issues $startupIssues
    }
    $port = $baseUri.Port
    $prefixTemplate = '{0}://{1}:{2}/' -f $baseUri.Scheme, $baseUri.Host, '{0}'
    while (-not $started -and $attempts -lt $maxAttempts) {
        $candidatePrefix = if ($attempts -eq 0) { $basePrefix } else { ($prefixTemplate -f ($port + $attempts)) }
        try {
            Ensure-UrlAcl -Prefix $candidatePrefix
            $listener = [System.Net.HttpListener]::new()
            $listener.Prefixes.Add($candidatePrefix)
            $listener.Start()
            $started = $true
            $Prefix = $candidatePrefix
            if ($attempts -gt 0) {
                Write-Log -Level 'WARN' -Message ("Prefix {0} unavailable; switched to {1}" -f $basePrefix, $candidatePrefix)
            }
        } catch {
            if ($listener) {
                $listener.Close()
            }
            $listener = $null
            Write-Log -Level 'WARN' -Message ("Failed to listen on prefix {0}: {1}" -f $candidatePrefix, $_.Exception.Message)
        }
        $attempts += 1
    }
    if (-not $started -or -not $listener) {
        throw ("Failed to listen on prefix '{0}' after {1} attempts." -f $basePrefix, $maxAttempts)
    }
    $l = $listener
    Write-Log -Message "Listening on $Prefix"
    $script:ListenerStartedAt = Get-Date
    $script:ListenerPrefix = $Prefix
    if ($startupIssues.Count -gt 0) {
        Write-Log -Level 'WARN' -Message ("Listener started with {0} startup issue(s)." -f $startupIssues.Count)
    }
    # Cache for network deltas
    $prevNet = @{}

    try {
        while ($true) {
            $context = $l.GetContext()
            $req = $context.Request
            $res = $context.Response
            $rawPath = $req.RawUrl.Split('?',2)[0]
            $requestPath = [System.Uri]::UnescapeDataString($rawPath)
            try {
            if ($requestPath -eq '/metrics') {
                # Try to collect real metrics on Windows, fallback to mock data otherwise
                try {
                    if (-not $IsWindows) {
                        throw "Non-Windows platform detected"
                    }

                    $nowUtc = (Get-Date).ToUniversalTime().ToString('o')
                    $computerName = $env:COMPUTERNAME
                    # CPU
                    $cpuPct = $null
                    try {
                        $cpuPct = [double](Get-Counter '\\Processor(_Total)\\% Processor Time').CounterSamples.CookedValue
                    } catch {
                        $cpuPct = $null
                    }
                    if ($cpuPct -eq $null -or $cpuPct -lt 0 -or $cpuPct -gt 1000) {
                        try {
                            $cpuPct = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
                        } catch {
                            $cpuPct = $null
                        }
                    }
                    if ($cpuPct -ne $null) {
                        $cpuPct = [math]::Round([math]::Min([math]::Max($cpuPct, 0), 100), 2)
                    }
                    # Memory
                    $os = Get-CimInstance Win32_OperatingSystem
                    $totalMemGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
                    $freeMemGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
                    $usedMemGB  = $totalMemGB - $freeMemGB
                    $memPct     = if ($totalMemGB -gt 0) { [math]::Round(($usedMemGB / $totalMemGB), 4) } else { 0 }
                    # Disks
                    $fixedDrives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
                    $disks = $fixedDrives | ForEach-Object {
                        $sizeGB = [math]::Round($_.Size / 1GB, 2)
                        $freeGB = [math]::Round($_.FreeSpace / 1GB, 2)
                        [pscustomobject]@{
                            Drive = $_.DeviceID.TrimEnd(':')
                            TotalGB = $sizeGB
                            UsedGB  = $sizeGB - $freeGB
                            UsedPct = if ($sizeGB -gt 0) { [math]::Round((($sizeGB - $freeGB) / $sizeGB), 4) } else { 0 }
                        }
                    }
                    # Uptime
                    $bootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
                    $uptime   = (Get-Date) - $bootTime
                    # Events last hour
                    $startTime = (Get-Date).AddHours(-1)
                    $warns = Get-WinEvent -FilterHashtable @{LogName='System','Application'; Level=3; StartTime=$startTime} -ErrorAction SilentlyContinue
                    $errs  = Get-WinEvent -FilterHashtable @{LogName='System','Application'; Level=2; StartTime=$startTime} -ErrorAction SilentlyContinue
                    $warnSummary = $warns | Group-Object ProviderName | ForEach-Object { [pscustomobject]@{ Source=$_.Name; Count=$_.Count } }
                    $errSummary  = $errs  | Group-Object ProviderName | ForEach-Object { [pscustomobject]@{ Source=$_.Name; Count=$_.Count } }
                    # Network usage delta
                    $netUsage = @()
                    try {
                        Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object {
                            $name  = $_.Name
                            $stats = Get-NetAdapterStatistics -Name $name
                            $prev  = $prevNet[$name]
                            if ($prev) {
                                $sentBps = [math]::Round((($stats.OutboundBytes - $prev.OutboundBytes)), 2)
                                $recvBps = [math]::Round((($stats.InboundBytes  - $prev.InboundBytes)), 2)
                                $netUsage += [pscustomobject]@{ Adapter=$name; BytesSentPerSec=$sentBps; BytesRecvPerSec=$recvBps }
                            }
                            $prevNet[$name] = $stats
                        }
                    } catch {}
                    # Ping latency
                    $latencyMs = -1
                    $latencyTarget = $PingTarget
                    try {
                        $targets = @()
                        if ($PingTarget) { $targets += $PingTarget }
                        if ($script:Config -and $script:Config.RouterIP) { $targets += [string]$script:Config.RouterIP }
                        try {
                            $gateway = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                                Sort-Object RouteMetric | Select-Object -First 1).NextHop
                            if ($gateway) { $targets += $gateway }
                        } catch {}
                        $targets += '1.1.1.1'
                        $targets = $targets | Where-Object { $_ } | Select-Object -Unique

                        foreach ($target in $targets) {
                            try {
                                $ping = Test-Connection -ComputerName $target -Count 1 -ErrorAction Stop
                                if ($ping) {
                                    $latencyMs = [int]($ping | Select-Object -First 1).ResponseTime
                                    $latencyTarget = $target
                                    break
                                }
                            } catch {}
                        }
                    } catch {}
                    # Top processes
                    $topProcs = Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 | ForEach-Object {
                        [pscustomobject]@{
                            Name               = $_.ProcessName
                            CPU                = $([math]::Round($_.CPU, 2))
                            Id                 = $_.Id
                            WorkingSet64       = $_.WorkingSet64
                            PrivateMemorySize64 = $_.PrivateMemorySize64
                            IOReadBytes        = $_.IOReadBytes
                            IOWriteBytes       = $_.IOWriteBytes
                        }
                    }
                    $metrics = [pscustomobject]@{
                        Time          = $nowUtc
                        ComputerName  = $computerName
                        CPU           = @{ Pct = $cpuPct }
                        Memory        = @{ TotalGB=$totalMemGB; FreeGB=$freeMemGB; UsedGB=$usedMemGB; Pct=$memPct }
                        Disk          = $disks
                        Uptime        = @{ Days=$uptime.Days; Hours=$uptime.Hours; Minutes=$uptime.Minutes }
                        Events        = @{ Warnings=$warnSummary; Errors=$errSummary }
                        Network       = @{ Usage=$netUsage; LatencyMs=$latencyMs; LatencyTarget=$latencyTarget }
                        Processes     = $topProcs
                    }
                } catch {
                    Write-Log -Level 'WARN' -Message "Failed to collect real metrics ($($_.Exception.Message)). Using mock data."
                    $metrics = Get-MockSystemMetrics
                }
                $json = $metrics | ConvertTo-Json -Depth 5
                $buf  = [Text.Encoding]::UTF8.GetBytes($json)
                $res.ContentType = 'application/json'
                $res.Headers['Cache-Control'] = 'no-store'
                $res.ContentLength64 = $buf.Length
                $res.OutputStream.Write($buf,0,$buf.Length)
                $res.Close()
                continue
            } elseif ($requestPath -eq '/scan-clients') {
                # Scan for connected clients
                $clients = Scan-ConnectedClients
                $json = $clients | ConvertTo-Json -Depth 5
                $buf  = [Text.Encoding]::UTF8.GetBytes($json)
                $res.ContentType = 'application/json'
                $res.OutputStream.Write($buf,0,$buf.Length)
                $res.Close()
                continue
            } elseif ($requestPath -eq '/router-login') {
                # Handle router login
                $credentials = Get-RouterCredentials
                $json = $credentials | ConvertTo-Json -Depth 5
                $buf  = [Text.Encoding]::UTF8.GetBytes($json)
                $res.ContentType = 'application/json'
                $res.OutputStream.Write($buf,0,$buf.Length)
                $res.Close()
                continue
            } elseif ($requestPath -eq '/system-logs') {
                # Retrieve system logs
                $logs = Get-SystemLogs
                $json = $logs | ConvertTo-Json -Depth 5
                $buf  = [Text.Encoding]::UTF8.GetBytes($json)
                $res.ContentType = 'application/json'
                $res.OutputStream.Write($buf,0,$buf.Length)
                $res.Close()
                continue
            } elseif ($requestPath -eq '/api/syslog/summary') {
                $range = Resolve-QueryTimeRange -Query $req.QueryString -DefaultHours 24
                $rangeStartIso = Escape-SqlLiteral $range.StartUtc.ToString('o')
                $rangeEndIso = Escape-SqlLiteral $range.EndUtc.ToString('o')
                $rangeStart1h = $range.EndUtc.AddHours(-1)
                if ($rangeStart1h -lt $range.StartUtc) { $rangeStart1h = $range.StartUtc }
                $rangeStart24h = $range.EndUtc.AddHours(-24)
                if ($rangeStart24h -lt $range.StartUtc) { $rangeStart24h = $range.StartUtc }
                $rangeStart1hIso = Escape-SqlLiteral $rangeStart1h.ToString('o')
                $rangeStart24hIso = Escape-SqlLiteral $rangeStart24h.ToString('o')

                $filters = @(
                    "received_utc >= '$rangeStartIso'::timestamptz",
                    "received_utc <= '$rangeEndIso'::timestamptz"
                )
                $hostQuery = $req.QueryString['host']
                if ($hostQuery) {
                    $hostSafe = Escape-SqlLiteral $hostQuery.ToLowerInvariant()
                    $filters += ("LOWER(source_host) LIKE '%{0}%'" -f $hostSafe)
                }

                $category = $req.QueryString['category']
                $categorySafe = if ($category) { Escape-SqlLiteral $category.ToLowerInvariant() } else { $null }

                $severityFilter = $null
                if ($req.QueryString['severity']) {
                    $sevParsed = 0
                    if ([int]::TryParse($req.QueryString['severity'], [ref]$sevParsed)) {
                        $severityFilter = $sevParsed
                    }
                }

                $categoryExpr = @"
CASE
    WHEN (app_name ILIKE '%wlceventd%' OR message ILIKE '%wifi%' OR message ILIKE '%wlan%') THEN 'wifi'
    WHEN (app_name ILIKE '%dnsmasq%' OR message ILIKE '%dhcp%' OR message ILIKE '%udhcpd%') THEN 'dhcp'
    WHEN (message ILIKE '%firewall%' OR message ILIKE '%iptables%' OR message ILIKE '%drop%') THEN 'firewall'
    WHEN (message ILIKE '%auth%' OR message ILIKE '%login%' OR message ILIKE '%ssh%' OR message ILIKE '%vpn%') THEN 'auth'
    WHEN (message ILIKE '%dns%' OR message ILIKE '%resolver%' OR message ILIKE '%named%') THEN 'dns'
    WHEN (message ILIKE '%network%' OR message ILIKE '%link%') THEN 'network'
    ELSE 'system'
END
"@

                if ($severityFilter -ne $null) {
                    $filters += "severity = $severityFilter"
                }
                if ($categorySafe) {
                    $filters += ("($categoryExpr) = '{0}'" -f $categorySafe)
                }

                $where = $filters -join ' AND '
                $sql = @"
WITH rows AS (
    SELECT received_utc,
           source_host,
           app_name,
           severity,
           $categoryExpr AS category
    FROM telemetry.syslog_generic_template
    WHERE $where
)
SELECT json_build_object(
    'total1h', (SELECT COUNT(*) FROM rows WHERE received_utc >= '$rangeStart1hIso'::timestamptz),
    'total24h', (SELECT COUNT(*) FROM rows WHERE received_utc >= '$rangeStart24hIso'::timestamptz),
    'noisyHosts', (SELECT COUNT(DISTINCT source_host) FROM rows WHERE source_host IS NOT NULL AND source_host <> '' AND severity <= 4),
    'topApps', COALESCE((
        SELECT json_agg(t)
        FROM (
            SELECT app_name AS app, COUNT(*) AS total
            FROM rows
            GROUP BY app_name
            ORDER BY total DESC NULLS LAST
            LIMIT 5
        ) t
    ), '[]'::json),
    'topHosts', COALESCE((
        SELECT json_agg(t)
        FROM (
            SELECT source_host AS host, COUNT(*) AS total
            FROM rows
            WHERE source_host IS NOT NULL AND source_host <> ''
            GROUP BY source_host
            ORDER BY total DESC NULLS LAST
            LIMIT 5
        ) t
    ), '[]'::json),
    'bySeverity', COALESCE((
        SELECT json_agg(t)
        FROM (
            SELECT severity, COUNT(*) AS total
            FROM rows
            GROUP BY severity
            ORDER BY total DESC
        ) t
    ), '[]'::json)
);
"@
                $json = Invoke-PostgresJsonQuery -Sql $sql
                if ($null -eq $json) {
                    Write-Log -Level 'WARN' -Message 'Syslog summary query failed.'
                    Write-JsonResponse -Response $res -Json '{}' -StatusCode 503
                } else {
                    Write-JsonResponse -Response $res -Json $json
                }
                continue
            } elseif ($requestPath -eq '/api/syslog/recent') {
                $limit = 50
                if ($req.QueryString['limit']) {
                    $parsed = 0
                    if ([int]::TryParse($req.QueryString['limit'], [ref]$parsed)) {
                        $limit = [Math]::Max(1, [Math]::Min(200, $parsed))
                    }
                }
                $offset = 0
                if ($req.QueryString['offset']) {
                    $parsed = 0
                    if ([int]::TryParse($req.QueryString['offset'], [ref]$parsed)) {
                        $offset = [Math]::Max(0, [Math]::Min(10000, $parsed))
                    }
                }

                $range = Resolve-QueryTimeRange -Query $req.QueryString -DefaultHours 24
                $rangeStartIso = Escape-SqlLiteral $range.StartUtc.ToString('o')
                $rangeEndIso = Escape-SqlLiteral $range.EndUtc.ToString('o')
                $filters = @(
                    "received_utc >= '$rangeStartIso'::timestamptz",
                    "received_utc <= '$rangeEndIso'::timestamptz"
                )
                $hostQuery = $req.QueryString['host']
                if ($hostQuery) {
                    $hostSafe = Escape-SqlLiteral $hostQuery.ToLowerInvariant()
                    $filters += ("LOWER(source_host) LIKE '%{0}%'" -f $hostSafe)
                }

                $category = $req.QueryString['category']
                $categorySafe = if ($category) { Escape-SqlLiteral $category.ToLowerInvariant() } else { $null }

                $severityFilter = $null
                if ($req.QueryString['severity']) {
                    $sevParsed = 0
                    if ([int]::TryParse($req.QueryString['severity'], [ref]$sevParsed)) {
                        $severityFilter = $sevParsed
                    }
                }

                $categoryExpr = @"
CASE
    WHEN (app_name ILIKE '%wlceventd%' OR message ILIKE '%wifi%' OR message ILIKE '%wlan%') THEN 'wifi'
    WHEN (app_name ILIKE '%dnsmasq%' OR message ILIKE '%dhcp%' OR message ILIKE '%udhcpd%') THEN 'dhcp'
    WHEN (message ILIKE '%firewall%' OR message ILIKE '%iptables%' OR message ILIKE '%drop%') THEN 'firewall'
    WHEN (message ILIKE '%auth%' OR message ILIKE '%login%' OR message ILIKE '%ssh%' OR message ILIKE '%vpn%') THEN 'auth'
    WHEN (message ILIKE '%dns%' OR message ILIKE '%resolver%' OR message ILIKE '%named%') THEN 'dns'
    WHEN (message ILIKE '%network%' OR message ILIKE '%link%') THEN 'network'
    ELSE 'system'
END
"@

                $where = $filters -join ' AND '
                $sql = @"
WITH rows AS (
    SELECT received_utc,
           source_host,
           app_name,
           severity,
           message,
           $categoryExpr AS category,
           CASE severity
                WHEN 0 THEN 'emerg'
                WHEN 1 THEN 'alert'
                WHEN 2 THEN 'critical'
                WHEN 3 THEN 'error'
                WHEN 4 THEN 'warning'
                WHEN 5 THEN 'notice'
                WHEN 6 THEN 'info'
                WHEN 7 THEN 'debug'
                ELSE 'unknown'
           END AS severity_label
    FROM telemetry.syslog_generic_template
    WHERE $where
)
SELECT COALESCE(json_agg(t), '[]'::json) FROM (
    SELECT *
    FROM rows
    WHERE 1=1
    $(if ($severityFilter -ne $null) { "AND severity = $severityFilter" } else { "" })
    $(if ($categorySafe) { "AND category = '$categorySafe'" } else { "" })
    ORDER BY received_utc DESC
    LIMIT $limit
    OFFSET $offset
) t;
"@

                $json = Invoke-PostgresJsonQuery -Sql $sql
                if ($null -eq $json) {
                    Write-Log -Level 'WARN' -Message 'Syslog recent query failed.'
                    Write-JsonResponse -Response $res -Json '[]' -StatusCode 503
                } else {
                    Write-JsonResponse -Response $res -Json $json
                }
                continue
            } elseif ($requestPath -eq '/api/syslog/timeline') {
                $bucketMinutes = 15
                if ($req.QueryString['bucketMinutes']) {
                    $parsed = 0
                    if ([int]::TryParse($req.QueryString['bucketMinutes'], [ref]$parsed)) {
                        if ($parsed -ge 1 -and $parsed -le 60) {
                            $bucketMinutes = $parsed
                        }
                    }
                }

                $range = Resolve-QueryTimeRange -Query $req.QueryString -DefaultHours 24
                $rangeStartIso = Escape-SqlLiteral $range.StartUtc.ToString('o')
                $rangeEndIso = Escape-SqlLiteral $range.EndUtc.ToString('o')
                $filters = @(
                    "received_utc >= '$rangeStartIso'::timestamptz",
                    "received_utc <= '$rangeEndIso'::timestamptz"
                )
                $hostQuery = $req.QueryString['host']
                if ($hostQuery) {
                    $hostSafe = Escape-SqlLiteral $hostQuery.ToLowerInvariant()
                    $filters += ("LOWER(source_host) LIKE '%{0}%'" -f $hostSafe)
                }

                $category = $req.QueryString['category']
                $categorySafe = if ($category) { Escape-SqlLiteral $category.ToLowerInvariant() } else { $null }

                $severityFilter = $null
                if ($req.QueryString['severity']) {
                    $sevParsed = 0
                    if ([int]::TryParse($req.QueryString['severity'], [ref]$sevParsed)) {
                        $severityFilter = $sevParsed
                    }
                }

                $categoryExpr = @"
CASE
    WHEN (app_name ILIKE '%wlceventd%' OR message ILIKE '%wifi%' OR message ILIKE '%wlan%') THEN 'wifi'
    WHEN (app_name ILIKE '%dnsmasq%' OR message ILIKE '%dhcp%' OR message ILIKE '%udhcpd%') THEN 'dhcp'
    WHEN (message ILIKE '%firewall%' OR message ILIKE '%iptables%' OR message ILIKE '%drop%') THEN 'firewall'
    WHEN (message ILIKE '%auth%' OR message ILIKE '%login%' OR message ILIKE '%ssh%' OR message ILIKE '%vpn%') THEN 'auth'
    WHEN (message ILIKE '%dns%' OR message ILIKE '%resolver%' OR message ILIKE '%named%') THEN 'dns'
    WHEN (message ILIKE '%network%' OR message ILIKE '%link%') THEN 'network'
    ELSE 'system'
END
"@
                if ($severityFilter -ne $null) {
                    $filters += "severity = $severityFilter"
                }
                if ($categorySafe) {
                    $filters += ("($categoryExpr) = '{0}'" -f $categorySafe)
                }

                $where = $filters -join ' AND '
                $severityGroupExpr = @"
CASE
    WHEN severity <= 3 THEN 'error'
    WHEN severity = 4 THEN 'warning'
    WHEN severity IN (5, 6) THEN 'info'
    WHEN severity = 7 THEN 'debug'
    ELSE 'info'
END
"@
                $sql = @"
WITH rows AS (
    SELECT received_utc,
           $severityGroupExpr AS severity_group
    FROM telemetry.syslog_generic_template
    WHERE $where
)
SELECT COALESCE(json_agg(t), '[]'::json) FROM (
    SELECT
        date_trunc('minute', received_utc)
            - make_interval(mins => (EXTRACT(MINUTE FROM received_utc)::int % $bucketMinutes)) AS bucket_start,
        severity_group AS category,
        COUNT(*) AS total
    FROM rows
    GROUP BY bucket_start, severity_group
    ORDER BY bucket_start ASC
) t;
"@
                $json = Invoke-PostgresJsonQuery -Sql $sql
                if ($null -eq $json) {
                    Write-Log -Level 'WARN' -Message 'Syslog timeline query failed.'
                    Write-JsonResponse -Response $res -Json '[]' -StatusCode 503
                } else {
                    Write-JsonResponse -Response $res -Json $json
                }
                continue
            } elseif ($requestPath -eq '/api/events/summary') {
                $range = Resolve-QueryTimeRange -Query $req.QueryString -DefaultHours 24
                $rangeStartIso = Escape-SqlLiteral $range.StartUtc.ToString('o')
                $rangeEndIso = Escape-SqlLiteral $range.EndUtc.ToString('o')
                $rangeStart1h = $range.EndUtc.AddHours(-1)
                if ($rangeStart1h -lt $range.StartUtc) { $rangeStart1h = $range.StartUtc }
                $rangeStart24h = $range.EndUtc.AddHours(-24)
                if ($rangeStart24h -lt $range.StartUtc) { $rangeStart24h = $range.StartUtc }
                $rangeStart1hIso = Escape-SqlLiteral $rangeStart1h.ToString('o')
                $rangeStart24hIso = Escape-SqlLiteral $rangeStart24h.ToString('o')

                $filters = @(
                    "occurred_at >= '$rangeStartIso'::timestamptz",
                    "occurred_at <= '$rangeEndIso'::timestamptz"
                )

                $sourceQuery = $req.QueryString['source']
                if ($sourceQuery) {
                    $sourceSafe = Escape-SqlLiteral $sourceQuery.ToLowerInvariant()
                    $filters += ("LOWER(source) LIKE '%{0}%'" -f $sourceSafe)
                }

                $category = $req.QueryString['category']
                if ($category) {
                    $categorySafe = Escape-SqlLiteral $category.ToLowerInvariant()
                    $filters += ("LOWER(event_type) = '{0}'" -f $categorySafe)
                }

                $severity = $req.QueryString['severity']
                if ($severity) {
                    $severitySafe = Escape-SqlLiteral $severity.ToLowerInvariant()
                    $filters += ("LOWER(severity) = '{0}'" -f $severitySafe)
                }

                $where = $filters -join ' AND '
                $sql = @"
WITH rows AS (
    SELECT occurred_at,
           source,
           severity,
           event_type
    FROM telemetry.events
    WHERE $where
)
SELECT json_build_object(
    'total1h', (SELECT COUNT(*) FROM rows WHERE occurred_at >= '$rangeStart1hIso'::timestamptz),
    'total24h', (SELECT COUNT(*) FROM rows WHERE occurred_at >= '$rangeStart24hIso'::timestamptz),
    'topSources', COALESCE((
        SELECT json_agg(t)
        FROM (
            SELECT source, COUNT(*) AS total
            FROM rows
            GROUP BY source
            ORDER BY total DESC NULLS LAST
            LIMIT 5
        ) t
    ), '[]'::json),
    'bySeverity', COALESCE((
        SELECT json_agg(t)
        FROM (
            SELECT severity, COUNT(*) AS total
            FROM rows
            GROUP BY severity
            ORDER BY total DESC
        ) t
    ), '[]'::json)
);
"@
                $json = Invoke-PostgresJsonQuery -Sql $sql
                if ($null -eq $json) {
                    Write-Log -Level 'WARN' -Message 'Event summary query failed.'
                    Write-JsonResponse -Response $res -Json '{}' -StatusCode 503
                } else {
                    Write-JsonResponse -Response $res -Json $json
                }
                continue
            } elseif ($requestPath -eq '/api/events/recent') {
                $limit = 50
                if ($req.QueryString['limit']) {
                    $parsed = 0
                    if ([int]::TryParse($req.QueryString['limit'], [ref]$parsed)) {
                        $limit = [Math]::Max(1, [Math]::Min(200, $parsed))
                    }
                }
                $offset = 0
                if ($req.QueryString['offset']) {
                    $parsed = 0
                    if ([int]::TryParse($req.QueryString['offset'], [ref]$parsed)) {
                        $offset = [Math]::Max(0, [Math]::Min(10000, $parsed))
                    }
                }

                $range = Resolve-QueryTimeRange -Query $req.QueryString -DefaultHours 24
                $rangeStartIso = Escape-SqlLiteral $range.StartUtc.ToString('o')
                $rangeEndIso = Escape-SqlLiteral $range.EndUtc.ToString('o')
                $filters = @(
                    "occurred_at >= '$rangeStartIso'::timestamptz",
                    "occurred_at <= '$rangeEndIso'::timestamptz"
                )

                $sourceQuery = $req.QueryString['source']
                if ($sourceQuery) {
                    $sourceSafe = Escape-SqlLiteral $sourceQuery.ToLowerInvariant()
                    $filters += ("LOWER(source) LIKE '%{0}%'" -f $sourceSafe)
                }

                $category = $req.QueryString['category']
                if ($category) {
                    $categorySafe = Escape-SqlLiteral $category.ToLowerInvariant()
                    $filters += ("LOWER(event_type) = '{0}'" -f $categorySafe)
                }

                $severity = $req.QueryString['severity']
                if ($severity) {
                    $severitySafe = Escape-SqlLiteral $severity.ToLowerInvariant()
                    $filters += ("LOWER(severity) = '{0}'" -f $severitySafe)
                }

                $where = $filters -join ' AND '
                $sql = @"
SELECT COALESCE(json_agg(t), '[]'::json) FROM (
    SELECT occurred_at,
           source,
           severity,
           event_type AS category,
           subject,
           COALESCE(payload->>'message', '') AS message
    FROM telemetry.events
    WHERE $where
    ORDER BY occurred_at DESC NULLS LAST
    LIMIT $limit
    OFFSET $offset
) t;
"@
                $json = Invoke-PostgresJsonQuery -Sql $sql
                if ($null -eq $json) {
                    Write-Log -Level 'WARN' -Message 'Event recent query failed.'
                    Write-JsonResponse -Response $res -Json '[]' -StatusCode 503
                } else {
                    Write-JsonResponse -Response $res -Json $json
                }
                continue
            } elseif ($requestPath -eq '/api/events/timeline') {
                $bucketMinutes = 15
                if ($req.QueryString['bucketMinutes']) {
                    $parsed = 0
                    if ([int]::TryParse($req.QueryString['bucketMinutes'], [ref]$parsed)) {
                        if ($parsed -ge 1 -and $parsed -le 60) {
                            $bucketMinutes = $parsed
                        }
                    }
                }

                $range = Resolve-QueryTimeRange -Query $req.QueryString -DefaultHours 24
                $rangeStartIso = Escape-SqlLiteral $range.StartUtc.ToString('o')
                $rangeEndIso = Escape-SqlLiteral $range.EndUtc.ToString('o')
                $filters = @(
                    "occurred_at >= '$rangeStartIso'::timestamptz",
                    "occurred_at <= '$rangeEndIso'::timestamptz"
                )

                $sourceQuery = $req.QueryString['source']
                if ($sourceQuery) {
                    $sourceSafe = Escape-SqlLiteral $sourceQuery.ToLowerInvariant()
                    $filters += ("LOWER(source) LIKE '%{0}%'" -f $sourceSafe)
                }

                $category = $req.QueryString['category']
                if ($category) {
                    $categorySafe = Escape-SqlLiteral $category.ToLowerInvariant()
                    $filters += ("LOWER(event_type) = '{0}'" -f $categorySafe)
                }

                $severity = $req.QueryString['severity']
                if ($severity) {
                    $severitySafe = Escape-SqlLiteral $severity.ToLowerInvariant()
                    $filters += ("LOWER(severity) = '{0}'" -f $severitySafe)
                }

                $where = $filters -join ' AND '
                $severityGroupExpr = @"
CASE
    WHEN LOWER(severity) IN ('critical', 'error') THEN 'error'
    WHEN LOWER(severity) IN ('warning', 'warn') THEN 'warning'
    ELSE 'info'
END
"@
                $sql = @"
WITH rows AS (
    SELECT occurred_at,
           $severityGroupExpr AS severity_group
    FROM telemetry.events
    WHERE $where
)
SELECT COALESCE(json_agg(t), '[]'::json) FROM (
    SELECT
        date_trunc('minute', occurred_at)
            - make_interval(mins => (EXTRACT(MINUTE FROM occurred_at)::int % $bucketMinutes)) AS bucket_start,
        severity_group AS category,
        COUNT(*) AS total
    FROM rows
    GROUP BY bucket_start, severity_group
    ORDER BY bucket_start ASC
) t;
"@
                $json = Invoke-PostgresJsonQuery -Sql $sql
                if ($null -eq $json) {
                    Write-Log -Level 'WARN' -Message 'Event timeline query failed.'
                    Write-JsonResponse -Response $res -Json '[]' -StatusCode 503
                } else {
                    Write-JsonResponse -Response $res -Json $json
                }
                continue
            } elseif ($requestPath -eq '/api/router/kpis') {
                $kpiPath = $null
                if ($script:Config -and $script:Config.Service -and $script:Config.Service.Syslog) {
                    $kpiPath = $script:Config.Service.Syslog.KpiSummaryPath
                }
                if (-not $kpiPath) {
                    $kpiPath = Resolve-ConfigPathValue './var/syslog/router-kpis.json'
                } else {
                    $kpiPath = Resolve-ConfigPathValue $kpiPath
                }

                $json = $null
                if ($kpiPath -and (Test-Path -LiteralPath $kpiPath)) {
                    try {
                        $raw = Get-Content -LiteralPath $kpiPath -Raw
                        if ($raw) {
                            $parsed = $raw | ConvertFrom-Json
                            if ($parsed -and $parsed.kpis) {
                                $json = $raw
                            }
                        }
                    } catch {
                        $json = $null
                    }
                }

                if (-not $json) {
                    $fallbackSql = @"
SELECT json_build_object(
    'updated_utc', to_char((NOW() AT TIME ZONE 'utc'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'window_hours', 24,
    'kpis', json_build_object(
        'total_drop', (SELECT COUNT(*) FROM telemetry.syslog_generic_template WHERE received_utc >= NOW() - INTERVAL '24 hours' AND message ~* 'kernel:\s+DROP'),
        'igmp_drops', (SELECT COUNT(*) FROM telemetry.syslog_generic_template WHERE received_utc >= NOW() - INTERVAL '24 hours' AND message ~* 'kernel:\s+DROP' AND message ~* 'DST=224\.0\.0\.1' AND message ~* 'PROTO=2'),
        'rstats_errors', (SELECT COUNT(*) FROM telemetry.syslog_generic_template WHERE received_utc >= NOW() - INTERVAL '24 hours' AND message ~* 'rstats\[\d+\]:\s+Problem loading'),
        'roam_kicks', (SELECT COUNT(*) FROM telemetry.syslog_generic_template WHERE received_utc >= NOW() - INTERVAL '24 hours' AND message ~* 'roamast:.*(disconnect weak signal strength station|remove client)\s+\[[0-9a-f:]{17}\]'),
        'dnsmasq_sigterm', (SELECT COUNT(*) FROM telemetry.syslog_generic_template WHERE received_utc >= NOW() - INTERVAL '24 hours' AND message ~* 'dnsmasq\[\d+\]: exiting on receipt of SIGTERM'),
        'avahi_sigterm', (SELECT COUNT(*) FROM telemetry.syslog_generic_template WHERE received_utc >= NOW() - INTERVAL '24 hours' AND message ~* 'avahi-daemon\[\d+\]: Got SIGTERM'),
        'upnp_shutdowns', (SELECT COUNT(*) FROM telemetry.syslog_generic_template WHERE received_utc >= NOW() - INTERVAL '24 hours' AND message ~* 'miniupnpd\[\d+\]: shutting down MiniUPnPd')
    ),
    'top_drop_sources', '[]'::json,
    'top_drop_destinations', '[]'::json,
    'roam_kicks', '[]'::json
);
"@
                    $json = Invoke-PostgresJsonQuery -Sql $fallbackSql
                }

                if (-not $json) {
                    $json = '{}'
                }
                Write-JsonResponse -Response $res -Json $json
                continue
            } elseif ($requestPath -eq '/api/devices/summary') {
                $limit = 10
                if ($req.QueryString['limit']) {
                    $parsed = 0
                    if ([int]::TryParse($req.QueryString['limit'], [ref]$parsed)) {
                        $limit = [Math]::Max(1, [Math]::Min(100, $parsed))
                    }
                }
                $sql = @"
SELECT COALESCE(json_agg(t), '[]'::json) FROM (
    SELECT p.mac_address,
           p.last_seen AS last_seen,
           p.last_rssi AS last_rssi,
           p.last_event_type AS last_event_type,
           COALESCE(c.events_1h, 0) AS events_1h
    FROM telemetry.device_profiles p
    LEFT JOIN (
        SELECT mac_address, COUNT(*) AS events_1h
        FROM telemetry.device_observations
        WHERE occurred_at >= NOW() - INTERVAL '1 hour'
        GROUP BY mac_address
    ) c ON c.mac_address = p.mac_address
    ORDER BY c.events_1h DESC NULLS LAST, p.last_seen DESC
    LIMIT $limit
) t;
"@
                $json = Invoke-PostgresJsonQuery -Sql $sql
                if ($null -eq $json) {
                    Write-Log -Level 'WARN' -Message 'Device summary query failed.'
                    Write-JsonResponse -Response $res -Json '[]' -StatusCode 503
                } else {
                    Write-JsonResponse -Response $res -Json $json
                }
                continue
            } elseif ($requestPath -eq '/api/lan/clients') {
                $limit = 50
                if ($req.QueryString['limit']) {
                    $parsed = 0
                    if ([int]::TryParse($req.QueryString['limit'], [ref]$parsed)) {
                        $limit = [Math]::Max(1, [Math]::Min(200, $parsed))
                    }
                }
                $windowMinutes = 10
                if ($req.QueryString['windowMinutes']) {
                    $parsed = 0
                    if ([int]::TryParse($req.QueryString['windowMinutes'], [ref]$parsed)) {
                        if ($parsed -ge 1 -and $parsed -le 120) {
                            $windowMinutes = $parsed
                        }
                    }
                }
                $sql = @"
WITH rows AS (
    SELECT d.device_id,
           d.mac_address,
           d.hostname,
           d.nickname,
           d.primary_ip_address,
           d.last_seen_utc,
           ds.sample_time_utc AS last_snapshot_time,
           COALESCE(ds.ip_address, d.primary_ip_address) AS current_ip,
           ds.interface AS current_interface,
           ds.rssi AS current_rssi,
           ds.tx_rate_mbps,
           ds.rx_rate_mbps
    FROM telemetry.devices d
    JOIN LATERAL (
        SELECT sample_time_utc,
               ip_address,
               interface,
               rssi,
               tx_rate_mbps,
               rx_rate_mbps
        FROM telemetry.device_snapshots_template
        WHERE device_id = d.device_id
          AND sample_time_utc >= NOW() - INTERVAL '$windowMinutes minutes'
          AND is_online = true
        ORDER BY sample_time_utc DESC
        LIMIT 1
    ) ds ON true
    WHERE d.is_active = true
      AND ds.interface ILIKE ANY (ARRAY['%wl0%','%wl1%','%wl2%','%2.4%','%2g%','%5g%','%6g%','%wireless%','%wifi%'])
)
SELECT COALESCE(json_agg(t), '[]'::json) FROM (
    SELECT rows.*,
           rows.current_interface AS interface,
           rows.current_ip AS ip_address
    FROM rows
    ORDER BY current_rssi DESC NULLS LAST, last_snapshot_time DESC
    LIMIT $limit
) t;
"@
                $json = Invoke-PostgresJsonQuery -Sql $sql
                if ($null -eq $json) {
                    Write-Log -Level 'WARN' -Message 'Wi-Fi client query failed.'
                    Write-JsonResponse -Response $res -Json '[]' -StatusCode 503
                } else {
                    Write-JsonResponse -Response $res -Json $json
                }
                continue
            } elseif ($requestPath -eq '/api/timeline') {
                $bucketMinutes = 5
                if ($req.QueryString['bucketMinutes']) {
                    $parsed = 0
                    if ([int]::TryParse($req.QueryString['bucketMinutes'], [ref]$parsed)) {
                        if ($parsed -ge 1 -and $parsed -le 60) {
                            $bucketMinutes = $parsed
                        }
                    }
                }

                $sinceMinutes = Convert-IsoDurationToMinutes $req.QueryString['since']
                $filters = @("occurred_at >= NOW() - INTERVAL '$sinceMinutes minutes'")

                $mac = $req.QueryString['mac']
                if ($mac -and ($mac -match '^[0-9a-fA-F:\-]{11,17}$')) {
                    $filters += ("mac_address = '{0}'" -f (Escape-SqlLiteral $mac.ToUpper()))
                }

                $category = $req.QueryString['category']
                if ($category -and ($category -match '^[a-zA-Z0-9_-]+$')) {
                    $filters += ("LOWER(category) = '{0}'" -f (Escape-SqlLiteral $category.ToLower()))
                }

                $eventType = $req.QueryString['eventType']
                if ($eventType -and ($eventType -match '^[a-zA-Z0-9_-]+$')) {
                    $filters += ("event_type = '{0}'" -f (Escape-SqlLiteral $eventType))
                }

                $where = $filters -join ' AND '
                $sql = @"
SELECT COALESCE(json_agg(t), '[]'::json) FROM (
    SELECT
        date_trunc('minute', occurred_at)
            - make_interval(mins => (EXTRACT(MINUTE FROM occurred_at)::int % $bucketMinutes)) AS bucket_start,
        COALESCE(NULLIF(lower(category), ''), 'unknown') AS category,
        COUNT(*) AS total
    FROM telemetry.device_observations
    WHERE $where
    GROUP BY bucket_start, category
    ORDER BY bucket_start ASC
) t;
"@
                {
                    $statusCode = 200
                    $payload = '[]'
                    try {
                        $json = Invoke-PostgresJsonQuery -Sql $sql
                        if (-not [string]::IsNullOrWhiteSpace($json)) {
                            $payload = $json
                        }
                    } catch {
                        Write-Log -Level 'WARN' -Message "Timeline query failed: $($_.Exception.Message)"
                        $statusCode = 503
                    }
                    Safe-JsonResponse -Response $res -Json $payload -StatusCode $statusCode -Context 'timeline payload'
                }
                continue
            } elseif ($requestPath -eq '/api/layouts') {
                if ($req.HttpMethod -eq 'GET') {
                    $store = Load-LayoutStore
                    if (-not $store) {
                        $store = @{
                            active = 'Default'
                            layouts = @{}
                        }
                    } elseif (-not $store.layouts) {
                        $store.layouts = @{}
                    }
                    if (-not $store.active) {
                        $store.active = 'Default'
                    }
                    $json = $store | ConvertTo-Json -Depth 8
                    Write-JsonResponse -Response $res -Json $json
                } elseif ($req.HttpMethod -eq 'POST') {
                    $raw = Read-RequestBody -Request $req
                    if (-not $raw) {
                        Write-JsonResponse -Response $res -Json '{"error":"empty body"}' -StatusCode 400
                        continue
                    }
                    try {
                        $payload = $raw | ConvertFrom-Json -ErrorAction Stop
                    } catch {
                        Write-JsonResponse -Response $res -Json '{"error":"invalid json"}' -StatusCode 400
                        continue
                    }
                    $store = @{
                        active = if ($payload.active) { [string]$payload.active } else { 'Default' }
                        layouts = if ($payload.layouts) { $payload.layouts } else { @{} }
                    }
                    if (-not (Save-LayoutStore -Store $store)) {
                        Write-JsonResponse -Response $res -Json '{"error":"failed to save layout"}' -StatusCode 500
                        continue
                    }
                    $json = $store | ConvertTo-Json -Depth 8
                    Write-JsonResponse -Response $res -Json $json
                } else {
                    Write-JsonResponse -Response $res -Json '{"error":"method not allowed"}' -StatusCode 405
                }
                continue
            } elseif ($requestPath -eq '/api/status') {
                $payload = Get-ListenerStatusPayload
                $json = $payload | ConvertTo-Json -Depth 6
                Write-JsonResponse -Response $res -Json $json
                continue
            } elseif ($requestPath -eq '/api/health') {
                $checks = [ordered]@{}
                $checks.postgres = Test-PostgresQuery -Sql 'SELECT 1;'
                $checks.device_summary = Test-PostgresQuery -Sql 'SELECT COUNT(*) FROM telemetry.device_profiles;'
                $checks.timeline = Test-PostgresQuery -Sql "SELECT COUNT(*) FROM telemetry.device_observations WHERE occurred_at >= NOW() - INTERVAL '24 hours';"

                $allOk = $true
                foreach ($entry in $checks.GetEnumerator()) {
                    if (-not $entry.Value.ok) {
                        $allOk = $false
                        Write-Log -Level 'WARN' -Message ("Health check failed: {0} ({1})" -f $entry.Key, $entry.Value.error)
                    }
                }

                $payload = @{
                    ok = $allOk
                    time = (Get-Date).ToString('o')
                    checks = $checks
                }
                $json = $payload | ConvertTo-Json -Depth 5
                Write-JsonResponse -Response $res -Json $json -StatusCode ($allOk ? 200 : 503)
                continue
            }
            if (-not $staticReady) {
                if ($requestPath -eq '/' -or $requestPath -eq '/index.html') {
                    $buf = [Text.Encoding]::UTF8.GetBytes($fallbackHtml)
                    $res.ContentType = 'text/html'
                    $res.ContentLength64 = $buf.Length
                    $res.OutputStream.Write($buf,0,$buf.Length)
                    $res.Close()
                    continue
                }
                Write-JsonResponse -Response $res -Json '{"error":"static assets unavailable"}' -StatusCode 503
                continue
            }
            # Static files
            $file = switch ($requestPath) {
                '/'           { $IndexHtml }
                '/index.html' { $IndexHtml }
                '/styles.css' { $CssFile }
                '/app.js' {
                    if (Test-Path -LiteralPath $AppJsFile -PathType Leaf) {
                        $AppJsFile
                    } else {
                        $null
                    }
                }
                Default {
                    $relative = $requestPath.TrimStart('/')
                    if ([string]::IsNullOrWhiteSpace($relative)) {
                        $IndexHtml
                    } else {
                        $normalized = $relative -replace '/', [System.IO.Path]::DirectorySeparatorChar
                        $candidate = [System.IO.Path]::GetFullPath((Join-Path $Root $normalized))
                        if ($candidate.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
                            $candidate
                        } else {
                            $null
                        }
                    }
                }
            }
            if ($file -and (Test-Path -LiteralPath $file -PathType Leaf)) {
                $bytes = [IO.File]::ReadAllBytes($file)
                $res.ContentType = Get-ContentType -Path $file
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes,0,$bytes.Length)
            } else {
                $res.StatusCode = 404
                $res.StatusDescription = 'Not Found'
            }
            $res.Close()
            } catch {
                $pathLabel = if ($requestPath) { $requestPath } else { $req.RawUrl }
                if (Test-ClientDisconnectException -Exception $_.Exception) {
                    try { if ($res) { $res.Close() } } catch {}
                } else {
                    Write-Log -Level 'ERROR' -Message ("Request failed for {0}: {1}" -f $pathLabel, $_.Exception.Message)
                    try {
                        if ($res) {
                            Write-JsonResponse -Response $res -Json '{"error":"request failed"}' -StatusCode 500
                        }
                    } catch {
                        try { $res.Close() } catch {}
                    }
                }
            }
        }
    } catch {
        Write-Log -Level 'ERROR' -Message $_
    } finally {
        try { $l.Stop(); $l.Close() } catch {}
    }
}

function Start-SystemDashboard {
    [CmdletBinding()]
    param(
        [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json')
    )
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Config file not found: $ConfigPath"
    }
    $resolved = (Resolve-Path -LiteralPath $ConfigPath).Path
    $script:ConfigPath = $resolved
    $script:ConfigBase = Split-Path -Parent $resolved
    $script:Config = Get-Content -LiteralPath $resolved -Raw | ConvertFrom-Json
    Start-SystemDashboardListener
}

function Scan-ConnectedClients {
    [CmdletBinding()]
    param(
        [Parameter()][ValidatePattern('^(?:\d{1,3}\.){3}\d{1,3}$')]
        [string]$NetworkPrefix = '192.168.1'  # e.g. '192.168.1' for /24
    )

    # Return mock data if not on Windows or if Get-NetNeighbor is not available
    if (-not $IsWindows -or -not (Get-Command Get-NetNeighbor -ErrorAction SilentlyContinue)) {
        Write-Log -Level 'INFO' -Message "Generating mock network client data (Windows-specific features not available)"
        return @(
            [PSCustomObject]@{
                IPAddress  = "$NetworkPrefix.10"
                Hostname   = "router.local"
                MACAddress = "00:11:22:33:44:55"
                State      = "Reachable"
            },
            [PSCustomObject]@{
                IPAddress  = "$NetworkPrefix.25"
                Hostname   = "laptop-01"
                MACAddress = "AA:BB:CC:DD:EE:FF"
                State      = "Reachable"
            },
            [PSCustomObject]@{
                IPAddress  = "$NetworkPrefix.50"
                Hostname   = $null
                MACAddress = "11:22:33:44:55:66"
                State      = "Reachable"
            }
        )
    }

    try {
        # 1) Generate all IPs in the /24 (1..254)
        $addresses = 1..254 | ForEach-Object { "$NetworkPrefix.$_" }

        # 2) Fire off parallel ping sweep to populate ARP table
        Write-Log -Level 'INFO' -Message "Pinging $($addresses.Count) addresses to prime ARP cache..."
        $pingParams = @{
            Count        = 1
            Quiet        = $true
            Timeout      = 200      # ms; bump if you have a slow network
        }
        $addresses | ForEach-Object -Parallel {
            Test-Connection -ComputerName $_ @using:pingParams
        } -ThrottleLimit 50       # adjust parallelism to your CPU/network

        # 3) Wait a tick for ARP entries to settle
        Start-Sleep -Milliseconds 500

        # 4) Pull the ARP table entries for our subnet
        $neighbors = Get-NetNeighbor `
            | Where-Object {
                $_.State -eq 'Reachable' -and
                $_.IPAddress -like "$NetworkPrefix.*"
            }

        # 5) Build PSCustomObjects with DNS lookups
        $clients = foreach ($n in $neighbors) {
            # Try to get the DNS name; swallow errors if reverse-DNS is off
            try {
                $name = (Resolve-DnsName -Name $n.IPAddress -ErrorAction Stop).NameHost
            } catch {
                $name = $null
            }

            [PSCustomObject]@{
                IPAddress  = $n.IPAddress
                Hostname   = $name
                MACAddress = $n.LinkLayerAddress
                State      = $n.State
            }
        }

        # 6) Return the list (empty if nothing found)
        return $clients
    } catch {
        Write-Log -Level 'WARN' -Message "Network scan failed: $($_.Exception.Message). Returning empty list."
        return @()
    }
}

function Get-RouterCredentials {
    [CmdletBinding()]
    param(
        # The IP or hostname of your router
        [ValidateNotNullOrEmpty()]
        [string]$RouterIP
    )

    if (-not $RouterIP) {
        if ($env:ROUTER_IP) { $RouterIP = $env:ROUTER_IP }
        elseif ($script:Config.RouterIP) { $RouterIP = $script:Config.RouterIP }
        else { $RouterIP = '192.168.50.1' }
    }

    Import-Module CredentialManager -ErrorAction SilentlyContinue | Out-Null
    $target = "SystemDashboard:$RouterIP"
    $credential = $null
    if (Get-Command Get-StoredCredential -ErrorAction SilentlyContinue) {
        $stored = Get-StoredCredential -Target $target
        if ($stored) {
            $secure = $stored.Password | ConvertTo-SecureString -AsPlainText -Force
            $credential = [PSCredential]::new($stored.UserName, $secure)
        } else {
            $credential = Get-Credential -Message "Enter administrator credentials for router $RouterIP"
            New-StoredCredential -Target $target -UserName $credential.UserName -Password ($credential.GetNetworkCredential().Password) -Persist LocalMachine | Out-Null
        }
    } else {
        $credential = Get-Credential -Message "Enter administrator credentials for router $RouterIP"
    }

    # 2) Quick reachability check
    Write-Log -Level 'INFO' -Message "Pinging router at $RouterIP to verify it’s up..."
    if (-not (Test-Connection -ComputerName $RouterIP -Count 1 -Quiet)) {
        throw "ERROR: Cannot reach router at $RouterIP. Check network connectivity."
    }

    # 3) Verify login via SSH/HTTP here (if SSH module is available).
    if (Get-Command New-SSHSession -ErrorAction SilentlyContinue) {
        try {
            New-SSHSession -ComputerName $RouterIP -Credential $credential -ErrorAction Stop | Remove-SSHSession
            Write-Log -Level 'INFO' -Message "SSH authentication to $RouterIP succeeded."
        } catch {
            throw "ERROR: SSH authentication to $RouterIP failed. $_"
        }
    } else {
        Write-Log -Level 'WARN' -Message "SSH module not available. Skipping router authentication verification."
    }

    # 4) Package up and return
    [PSCustomObject]@{
        RouterIP   = $RouterIP
        Credential = $credential
    }
}

function Get-SystemLogs {
    [CmdletBinding()]
    param(
        # Which Windows Event Log to read (Application, System, Security, etc.)
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$LogName,

        # Maximum number of events to retrieve per log
        [Parameter()]
        [ValidateRange(1, 10000)]
        [int]$MaxEvents = 100,

        # Minimum level to include: Info, Warning, Error, Critical
        [Parameter()]
        [ValidateSet('Information','Warning','Error','Critical')]
        [string]$MinimumLevel = 'Warning'
    )

    if (-not $PSBoundParameters.ContainsKey('LogName')) {
        $LogName = @('Application','System')
    }

    # Return mock data if not on Windows or if Get-WinEvent is not available
    if (-not $IsWindows -or -not (Get-Command Get-WinEvent -ErrorAction SilentlyContinue)) {
        Write-Log -Level 'INFO' -Message "Generating mock system logs (Windows Event Log not available)"
        $mockEvents = @(
            [PSCustomObject]@{
                LogName     = "Application"
                TimeCreated = (Get-Date).AddMinutes(-30)
                Level       = "Warning"
                EventID     = 1001
                Source      = "Application Error"
                Message     = "Mock application warning - database connection timeout occurred"
            },
            [PSCustomObject]@{
                LogName     = "System"
                TimeCreated = (Get-Date).AddHours(-1)
                Level       = "Error"
                EventID     = 2001
                Source      = "Service Control Manager"
                Message     = "Mock system error - service failed to start"
            },
            [PSCustomObject]@{
                LogName     = "Application"
                TimeCreated = (Get-Date).AddHours(-2)
                Level       = "Information"
                EventID     = 1002
                Source      = "DNS Client"
                Message     = "Mock information event - DNS resolution completed successfully"
            }
        )

        # Filter by minimum level if needed
        $levelMap = @{
            'Critical'    = 1
            'Error'       = 2
            'Warning'     = 3
            'Information' = 4
        }
        $minLevelNum = $levelMap[$MinimumLevel]

        return $mockEvents | Where-Object { $levelMap[$_.Level] -le $minLevelNum } | Select-Object -First $MaxEvents
    }

    # Map friendly level names to numeric values in Windows events
    $levelMap = @{
        'Critical'    = 1
        'Error'       = 2
        'Warning'     = 3
        'Information' = 4
    }

    # Ensure we got a valid numeric threshold
    $minLevelNum = $levelMap[$MinimumLevel]

    try {
        # Loop through each requested log
        $allLogs = foreach ($log in $LogName) {
            Write-Log -Level 'INFO' -Message "Retrieving up to $MaxEvents entries from '$log' where Level ≥ $MinimumLevel..."

            # Query the log with filters applied
            Get-WinEvent `
                -LogName $log `
                -MaxEvents $MaxEvents `
                -ErrorAction Stop |
            Where-Object { $_.LevelDisplayName -and $levelMap[$_.LevelDisplayName] -le $minLevelNum } |
            ForEach-Object {
                # Project only the fields you care about
                [PSCustomObject]@{
                    LogName        = $log
                    TimeCreated    = $_.TimeCreated
                    Level          = $_.LevelDisplayName
                    EventID        = $_.Id
                    Source         = $_.ProviderName
                    Message        = ($_.Message -replace '\r?\n',' ')  # flatten newlines
                }
            }
        }

        return $allLogs
    }
    catch {
        throw "ERROR: Failed to retrieve system logs. $($_.Exception.Message)"
    }
}


Export-ModuleMember -Function Start-SystemDashboardListener, Start-SystemDashboard, Ensure-UrlAcl, Remove-UrlAcl, Scan-ConnectedClients, Get-RouterCredentials, Get-SystemLogs, Get-MockSystemMetrics
### END FILE: SystemDashboard Listener

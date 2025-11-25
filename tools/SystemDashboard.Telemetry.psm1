#requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-SystemDashboardPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)][string]$Path
    )

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if ($expanded.StartsWith('~')) {
        $userProfile = [Environment]::GetFolderPath('UserProfile')
        if ($userProfile) {
            $expanded = Join-Path $userProfile ($expanded.Substring(1).TrimStart('\\','/'))
        }
    }

    if ([System.IO.Path]::IsPathRooted($expanded)) {
        return [System.IO.Path]::GetFullPath($expanded)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $expanded))
}

function Resolve-SystemDashboardSecret {
    [CmdletBinding()]
    param(
        [Parameter()][object]$Secret,
        [Parameter()][string]$Fallback
    )

    if ($null -eq $Secret) {
        return $Fallback
    }

    if ($Secret -is [string]) {
        if ($Secret.StartsWith('env:', [System.StringComparison]::OrdinalIgnoreCase)) {
            $name = $Secret.Substring(4)
            return [Environment]::GetEnvironmentVariable($name)
        }
        elseif ($Secret.StartsWith('file:', [System.StringComparison]::OrdinalIgnoreCase)) {
            $path = $Secret.Substring(5)
            if ([string]::IsNullOrWhiteSpace($path)) {
                return $Fallback
            }
            if (-not (Test-Path -LiteralPath $path)) {
                throw "Secret file '$path' not found."
            }
            return (Get-Content -LiteralPath $path -Raw).Trim()
        }
        else {
            return $Secret
        }
    }

    if ($Secret -is [hashtable]) {
        $type = ($Secret.Type ?? $Secret.kind ?? '').ToString()
        switch ($type.ToLowerInvariant()) {
            'environment' { return [Environment]::GetEnvironmentVariable(($Secret.Name ?? $Secret.Variable)) }
            'file'        { return Resolve-SystemDashboardSecret -Secret ("file:" + ($Secret.Path ?? $Secret.File)) -Fallback $Fallback }
            'plaintext'   { return ($Secret.Value ?? $Secret.Secret) }
            default       { return $Fallback }
        }
    }

    return $Fallback
}

function Read-SystemDashboardConfig {
    [CmdletBinding()]
    param(
        [Parameter()][string]$ConfigPath
    )

    if (-not $ConfigPath) {
        if ($env:SYSTEMDASHBOARD_CONFIG) {
            $ConfigPath = $env:SYSTEMDASHBOARD_CONFIG
        }
        else {
            $ConfigPath = Join-Path $PSScriptRoot '..' 'config.json'
        }
    }

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Configuration file '$ConfigPath' not found."
    }

    $resolved = (Resolve-Path -LiteralPath $ConfigPath).Path
    $base = Split-Path -Parent $resolved
    $raw = Get-Content -LiteralPath $resolved -Raw | ConvertFrom-Json -Depth 10

    if (-not $raw.Service) {
        $raw | Add-Member -NotePropertyName Service -NotePropertyValue (@{})
    }
    if (-not $raw.Database) {
        $raw | Add-Member -NotePropertyName Database -NotePropertyValue (@{})
    }

    # Resolve path-based settings
    if ($raw.Service.LogPath) {
        $raw.Service.LogPath = Resolve-SystemDashboardPath -BasePath $base -Path $raw.Service.LogPath
    }
    else {
        $raw.Service.LogPath = Resolve-SystemDashboardPath -BasePath $base -Path './var/log/telemetry-service.log'
    }

    if (-not $raw.Service.Ingestion) {
        $raw.Service.Ingestion = @{}
    }
    $raw.Service.Ingestion.StagingDirectory = Resolve-SystemDashboardPath -BasePath $base -Path ($raw.Service.Ingestion.StagingDirectory ?? './var/staging')
    if (-not $raw.Service.Ingestion.BatchIntervalSeconds) {
        $raw.Service.Ingestion.BatchIntervalSeconds = 30
    }
    if (-not $raw.Service.Ingestion.MinBatchSize) {
        $raw.Service.Ingestion.MinBatchSize = 25
    }

    if (-not $raw.Service.Syslog) {
        $raw.Service.Syslog = @{}
    }
    if (-not $raw.Service.Syslog.BindAddress) { $raw.Service.Syslog.BindAddress = '0.0.0.0' }
    if (-not $raw.Service.Syslog.Port) { $raw.Service.Syslog.Port = 514 }
    if (-not $raw.Service.Syslog.MaxMessageBytes) { $raw.Service.Syslog.MaxMessageBytes = 8192 }

    if (-not $raw.Service.Asus) {
        $raw.Service.Asus = @{}
    }
    if ($raw.Service.Asus.StatePath) {
        $raw.Service.Asus.StatePath = Resolve-SystemDashboardPath -BasePath $base -Path $raw.Service.Asus.StatePath
    }
    else {
        $raw.Service.Asus.StatePath = Resolve-SystemDashboardPath -BasePath $base -Path './var/asus/state.json'
    }
    if (-not $raw.Service.Asus.PollIntervalSeconds) { $raw.Service.Asus.PollIntervalSeconds = 60 }
    if (-not $raw.Service.Asus.Enabled) { $raw.Service.Asus.Enabled = $false }

    if ($raw.Service.Asus.DownloadPath) {
        $raw.Service.Asus.DownloadPath = Resolve-SystemDashboardPath -BasePath $base -Path $raw.Service.Asus.DownloadPath
    }
    else {
        $raw.Service.Asus.DownloadPath = Resolve-SystemDashboardPath -BasePath $base -Path './var/asus'
    }

    $raw.Service.Syslog.BufferDirectory = Resolve-SystemDashboardPath -BasePath $base -Path ($raw.Service.Syslog.BufferDirectory ?? './var/syslog')

    $raw.Database.Schema = $raw.Database.Schema ?? 'telemetry'

    return [pscustomobject]@{
        Path     = $resolved
        BasePath = $base
        Config   = $raw
    }
}

function Write-TelemetryLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )

    $dir = Split-Path -Parent $LogPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $ts = (Get-Date).ToString('o')
    Add-Content -Path $LogPath -Value "[$ts][$Level] $Message"
}

function ConvertFrom-SyslogLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Line
    )

    $result = [ordered]@{
        EventUtc    = $null
        SourceHost  = $null
        AppName     = $null
        Facility    = $null
        Severity    = $null
        Message     = $Line.Trim()
        RawMessage  = $Line
    }

    if ($Line -match '^<(?<pri>\d+)>(?<rest>.+)$') {
        $pri = [int]$Matches['pri']
        $facility = [math]::Floor($pri / 8)
        $severity = $pri % 8
        $result.Facility = $facility
        $result.Severity = $severity
        $rest = $Matches['rest']
    }
    else {
        $rest = $Line
    }

    if ($rest -match '^(?<timestamp>[A-Za-z]{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+(?<host>[^\s]+)\s*(?<app>[^:]+)?:?\s*(?<msg>.*)$') {
        $timestamp = $Matches['timestamp']
        $sourceHost = $Matches['host']
        $app = ($Matches['app'] ?? '').Trim()
        $msg = ($Matches['msg'] ?? '').Trim()
        $result.SourceHost = if ($sourceHost) { $sourceHost } else { $null }
        if ($app) { $result.AppName = $app }
        if ($msg) { $result.Message = $msg }
        try {
            $now = Get-Date
            $year = $now.Year
            $parsed = [DateTime]::ParseExact("$timestamp $year", 'MMM d HH:mm:ss yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
            if ($parsed -gt $now.AddDays(2)) {
                $parsed = $parsed.AddYears(-1)
            }
            $result.EventUtc = [DateTime]::SpecifyKind($parsed, [System.DateTimeKind]::Local).ToUniversalTime()
        }
        catch {
            $result.EventUtc = $null
        }
    }

    return [pscustomobject]$result
}

function ConvertFrom-AsusLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Line,
        [Parameter()][string]$DefaultHost = 'asus-router'
    )

    $result = [ordered]@{
        EventUtc    = $null
        SourceHost  = $DefaultHost
        AppName     = 'asus-router'
        Facility    = 4
        Severity    = 6
        Message     = $Line.Trim()
        RawMessage  = $Line
    }

    if ($Line -match '^(?<ts>\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s+(?<level>\w+)\s+(?<body>.+)$') {
        $timestamp = $Matches['ts']
        $level = $Matches['level']
        $body = $Matches['body']
        try {
            $parsed = [DateTime]::Parse($timestamp, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeLocal)
            $result.EventUtc = $parsed.ToUniversalTime()
        }
        catch {
            $result.EventUtc = $null
        }
        $result.Message = $body.Trim()
        switch ($level.ToUpperInvariant()) {
            'DEBUG' { $result.Severity = 7 }
            'INFO'  { $result.Severity = 6 }
            'NOTICE'{ $result.Severity = 5 }
            'WARN'  { $result.Severity = 4 }
            'ERROR' { $result.Severity = 3 }
            'CRIT'  { $result.Severity = 2 }
            'ALERT' { $result.Severity = 1 }
            'EMERG' { $result.Severity = 0 }
        }
    }

    return [pscustomobject]$result
}

function Get-PartitionTableName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseName,
        [Parameter()][DateTime]$Timestamp = (Get-Date)
    )

    $suffix = $Timestamp.ToUniversalTime().ToString('yyMM')
    return "$BaseName`_$suffix"
}

function Write-BatchToCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IEnumerable]$Events,
        [Parameter(Mandatory)][string]$TargetDirectory,
        [Parameter(Mandatory)][string]$Prefix
    )

    if (-not (Test-Path -LiteralPath $TargetDirectory)) {
        New-Item -ItemType Directory -Path $TargetDirectory -Force | Out-Null
    }
    $name = "{0}_{1:yyyyMMddTHHmmssfffZ}.csv" -f $Prefix, (Get-Date).ToUniversalTime()
    $path = Join-Path $TargetDirectory $name
    $Events | Select-Object ReceivedUtc, EventUtc, SourceHost, AppName, Facility, Severity, Message, RawMessage, RemoteEndpoint, Source |
        Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
    return $path
}

function Invoke-PostgresCopy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Database,
        [Parameter(Mandatory)][string]$TableName,
        [Parameter(Mandatory)][string]$CsvPath
    )

    $psqlPath = if ($Database.PsqlPath) { $Database.PsqlPath } else { 'psql' }
    $command = Get-Command -Name $psqlPath -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "psql executable '$psqlPath' not found in PATH. Set Database.PsqlPath in config.json."
    }

    $dbHost = $Database.Host ?? 'localhost'
    $port = $Database.Port ?? 5432
    $databaseName = $Database.Database ?? $Database.Name
    $username = $Database.Username ?? $Database.User
    if (-not $databaseName) {
        throw 'Database name must be specified in the configuration.'
    }
    if (-not $username) {
        throw 'Database username must be specified in the configuration.'
    }

    $password = Resolve-SystemDashboardSecret -Secret $Database.PasswordSecret -Fallback $Database.Password
    if ([string]::IsNullOrEmpty($password)) {
        throw 'Database password is not configured. Provide Database.Password or Database.PasswordSecret.'
    }

    $env:PGPASSWORD = $password
    try {
        $schema = $Database.Schema ?? 'telemetry'
        if (-not $TableName.Contains('.')) {
            $table = "$schema.$TableName"
        }
        else {
            $table = $TableName
        }
        $copyCommand = "\\copy $table (received_utc, event_utc, source_host, app_name, facility, severity, message, raw_message, remote_endpoint, source) FROM '$CsvPath' WITH (FORMAT csv, HEADER true, DELIMITER ',')"
        $psqlArgs = @('-h', $dbHost, '-p', [string]$port, '-U', $username, '-d', $databaseName, '-c', $copyCommand)
        $process = Start-Process -FilePath $command.Source -ArgumentList $psqlArgs -NoNewWindow -Wait -PassThru -ErrorAction Stop
        if ($process.ExitCode -ne 0) {
            throw "psql exited with code $($process.ExitCode)."
        }
    }
    finally {
        Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    }
}

function Invoke-PostgresStatement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Database,
        [Parameter(Mandatory)][string]$Sql
    )

    $psqlPath = if ($Database.PsqlPath) { $Database.PsqlPath } else { 'psql' }
    $command = Get-Command -Name $psqlPath -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "psql executable '$psqlPath' not found in PATH. Set Database.PsqlPath in config.json."
    }

    $dbHost = $Database.Host ?? 'localhost'
    $port = $Database.Port ?? 5432
    $databaseName = $Database.Database ?? $Database.Name
    $username = $Database.Username ?? $Database.User
    if (-not $databaseName -or -not $username) {
        throw 'Database connection settings are incomplete (host/user/database required).'
    }

    $password = Resolve-SystemDashboardSecret -Secret $Database.PasswordSecret -Fallback $Database.Password
    if ([string]::IsNullOrEmpty($password)) {
        throw 'Database password is not configured. Provide Database.Password or Database.PasswordSecret.'
    }

    $env:PGPASSWORD = $password
    try {
        $psqlArgs = @('-h', $dbHost, '-p', [string]$port, '-U', $username, '-d', $databaseName, '-c', $Sql)
        $process = Start-Process -FilePath $command.Source -ArgumentList $psqlArgs -NoNewWindow -Wait -PassThru -ErrorAction Stop
        if ($process.ExitCode -ne 0) {
            throw "psql exited with code $($process.ExitCode) when executing statement."
        }
    }
    finally {
        Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    }
}

function Invoke-SyslogIngestion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IEnumerable]$Events,
        [Parameter(Mandatory)][hashtable]$Ingestion,
        [Parameter(Mandatory)][hashtable]$Database,
        [Parameter()][string]$SourceLabel = 'syslog'
    )

    $batch = @($Events)
    if ($batch.Count -eq 0) { return }

    try {
        $monthStart = (Get-Date).ToUniversalTime().ToString('yyyy-MM-01')
        Invoke-PostgresStatement -Database $Database -Sql "SELECT telemetry.ensure_syslog_partition('$monthStart'::date);"
    }
    catch {
        Write-Verbose "Failed to ensure syslog partition: $_"
    }

    $csvPath = Write-BatchToCsv -Events $batch -TargetDirectory $Ingestion.StagingDirectory -Prefix $SourceLabel
    try {
        $table = Get-PartitionTableName -BaseName 'syslog_generic' -Timestamp (Get-Date)
        Invoke-PostgresCopy -Database $Database -TableName $table -CsvPath $csvPath
    }
    finally {
        Remove-Item -LiteralPath $csvPath -ErrorAction SilentlyContinue
    }
}

function Load-AsusState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @{}
    }
    try {
        return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
    }
    catch {
        return @{}
    }
}

function Save-AsusState {
    [CmdletBinding()]
    param(
        [Parameter()][object]$State,
        [Parameter(Mandatory)][string]$Path
    )

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $State | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-AsusLogFetch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter()][hashtable]$State
    )

    $uri = $Config.Uri ?? $Config.Url
    if (-not $uri) {
        throw 'Asus log endpoint URI must be configured (Service.Asus.Uri).'
    }

    $params = @{ Uri = $uri; Method = 'Get' }
    if ($Config.TimeoutSeconds) { $params.TimeoutSec = [int]$Config.TimeoutSeconds }
    if ($Config.Headers) { $params.Headers = $Config.Headers }

    $username = $Config.Username ?? $Config.User
    if ($username) {
        $password = Resolve-SystemDashboardSecret -Secret $Config.PasswordSecret -Fallback $Config.Password
        if (-not $password) {
            throw 'Asus router credentials missing password. Configure Service.Asus.Password or PasswordSecret.'
        }
        $secure = ConvertTo-SecureString $password -AsPlainText -Force
        $params.Credential = [pscredential]::new($username, $secure)
    }

    $response = Invoke-WebRequest @params
    $content = $response.Content -replace "\r", ''
    $lines = $content -split "\n"

    $lastUtc = $null
    if ($State -and $State.LastEventUtc) {
        try { $lastUtc = [DateTime]::Parse($State.LastEventUtc, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal) }
        catch { $lastUtc = $null }
    }

    $events = @()
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parsed = ConvertFrom-AsusLine -Line $line -DefaultHost ($Config.HostName ?? 'asus-router')
        $parsed | Add-Member -NotePropertyName Source -NotePropertyValue 'asus'
        $parsed | Add-Member -NotePropertyName RemoteEndpoint -NotePropertyValue ($Config.Uri ?? '')
        $parsed | Add-Member -NotePropertyName ReceivedUtc -NotePropertyValue ([DateTime]::UtcNow)
        if ($lastUtc -and $parsed.EventUtc -and $parsed.EventUtc -le $lastUtc) {
            continue
        }
        $events += $parsed
    }

    if ($events.Count -gt 0) {
        $mostRecent = ($events | Where-Object EventUtc | Sort-Object EventUtc -Descending | Select-Object -First 1)
        if ($mostRecent) {
            $State.LastEventUtc = $mostRecent.EventUtc.ToString('o')
        }
    }

    if ($LogPath) {
        if (-not (Test-Path -LiteralPath $LogPath)) {
            New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
        }
        $appendPath = Join-Path $LogPath ("asus-log-{0:yyyyMMdd}.log" -f (Get-Date))
        foreach ($evt in $events) {
            Add-Content -LiteralPath $appendPath -Value $evt.RawMessage
        }
    }

    return ,$events
}

function Invoke-AsusWifiClientScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter()][hashtable]$State
    )

    # Check if SSH monitoring is enabled and configured
    if (-not $Config.SSH -or -not $Config.SSH.Enabled) {
        return @()
    }

    $routerIP = $Config.SSH.HostName ?? $Config.HostName ?? '192.168.50.1'
    $username = $Config.SSH.Username ?? $Config.Username ?? 'admin'
    $password = Resolve-SystemDashboardSecret -Secret ($Config.SSH.PasswordSecret ?? $Config.PasswordSecret) -Fallback ($Config.SSH.Password ?? $Config.Password)

    if (-not $password) {
        Write-Verbose "WiFi client scan skipped: SSH password not configured"
        return @()
    }

    try {
        # Commands to gather WiFi client information
        $commands = @(
            "nvram get wl0_assoclist",  # 2.4GHz clients
            "nvram get wl1_assoclist",  # 5GHz clients
            "nvram get wl2_assoclist",  # 6GHz clients (WiFi 6E)
            "wl -i eth1 assoclist",     # Alternative method for 2.4GHz
            "wl -i eth2 assoclist",     # Alternative method for 5GHz
            "arp -a",                   # ARP table for IP assignments
            "cat /proc/net/arp"         # Alternative ARP method
        )

        $events = @()
        $timestamp = [DateTime]::UtcNow

        # Note: This is a conceptual implementation
        # In practice, you would need to use a PowerShell SSH module like Posh-SSH
        # or implement SSH connectivity through .NET SSH libraries

        foreach ($command in $commands) {
            try {
                # Placeholder for SSH command execution
                # In real implementation, this would execute SSH commands
                $output = Invoke-SSHCommand -ComputerName $routerIP -Username $username -Password $password -Command $command

                if ($output -and $output.Length -gt 0) {
                    $wifiEvent = [pscustomobject]@{
                        ReceivedUtc    = $timestamp
                        EventUtc       = $timestamp
                        SourceHost     = $routerIP
                        AppName        = 'asus-wifi-scan'
                        Facility       = 16  # local0
                        Severity       = 6   # info
                        Message        = "WiFi scan: $command"
                        RawMessage     = $output
                        RemoteEndpoint = "ssh://${routerIP}"
                        Source         = 'asus-wifi'
                        Command        = $command
                    }
                    $events += $wifiEvent
                }
            }
            catch {
                Write-Verbose "WiFi scan command failed: $command - $($_.Exception.Message)"
            }
        }

        return ,$events
    }
    catch {
        Write-Verbose "WiFi client scan failed: $($_.Exception.Message)"
        return @()
    }
}

function Invoke-SSHCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string]$Username,
        [Parameter(Mandatory)][string]$Password,
        [Parameter(Mandatory)][string]$Command
    )

    # This is a placeholder function that would need to be implemented
    # using a proper SSH library like Posh-SSH or SSH.NET
    # For now, return empty to prevent errors

    Write-Verbose "SSH Command placeholder: $Username@$ComputerName : $Command"

    # Example of what this would look like with Posh-SSH:
    # $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    # $credential = New-Object System.Management.Automation.PSCredential($Username, $securePassword)
    # $session = New-SSHSession -ComputerName $ComputerName -Credential $credential -AcceptKey
    # $result = Invoke-SSHCommand -SessionId $session.SessionId -Command $Command
    # Remove-SSHSession -SessionId $session.SessionId
    # return $result.Output

    return ""
}

function Start-TelemetryService {
    [CmdletBinding()]
    param(
        [Parameter()][string]$ConfigPath
    )

    $configInfo = Read-SystemDashboardConfig -ConfigPath $ConfigPath
    $config = $configInfo.Config
    $logPath = $config.Service.LogPath
    Write-TelemetryLog -LogPath $logPath -Message "SystemDashboard telemetry service starting." -Level 'INFO'

    $cts = [System.Threading.CancellationTokenSource]::new()
    Register-EngineEvent -SourceIdentifier 'PowerShell.Exiting' -Action { $event.MessageData.Cancel() } -MessageData $cts | Out-Null
    Register-EngineEvent -SourceIdentifier Console_CancelKeyPress -Action { $event.MessageData.Cancel(); $eventArgs.Cancel = $true } -MessageData $cts | Out-Null

    $syslogBuffer = New-Object System.Collections.Generic.List[object]
    $asusBuffer = New-Object System.Collections.Generic.List[object]
    $wifiBuffer = New-Object System.Collections.Generic.List[object]
    $ingestion = $config.Service.Ingestion
    $database = @{}
    $config.Database.PSObject.Properties | ForEach-Object { $database[$_.Name] = $_.Value }

    foreach ($dir in @($config.Service.Syslog.BufferDirectory, $config.Service.Asus.DownloadPath, ($config.Service.Asus.StatePath | Split-Path -Parent), $ingestion.StagingDirectory)) {
        if (-not [string]::IsNullOrWhiteSpace($dir)) {
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
        }
    }

    # Initialize UDP syslog listener with error handling
    $syslogEndpoint = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse($config.Service.Syslog.BindAddress), [int]$config.Service.Syslog.Port)
    $udpClient = $null

    try {
        $udpClient = [System.Net.Sockets.UdpClient]::new()
        $udpClient.Client.Bind($syslogEndpoint)
        $udpClient.Client.ReceiveTimeout = 1000
        Write-TelemetryLog -LogPath $logPath -Message "Syslog UDP listener bound to $($config.Service.Syslog.BindAddress):$($config.Service.Syslog.Port)" -Level 'INFO'
    }
    catch {
        Write-TelemetryLog -LogPath $logPath -Message "Failed to bind syslog UDP listener to $($config.Service.Syslog.BindAddress):$($config.Service.Syslog.Port) - $($_.Exception.Message)" -Level 'ERROR'
        if ($udpClient) { $udpClient.Close() }
        $udpClient = $null
    }

    # Initialize TCP syslog listener with error handling
    $tcpListener = $null
    $tcpClients = New-Object System.Collections.Generic.List[object]

    try {
        $tcpListener = [System.Net.Sockets.TcpListener]::new($syslogEndpoint)
        $tcpListener.Start()
        Write-TelemetryLog -LogPath $logPath -Message "Syslog TCP listener bound to $($config.Service.Syslog.BindAddress):$($config.Service.Syslog.Port)" -Level 'INFO'
    }
    catch {
        Write-TelemetryLog -LogPath $logPath -Message "Failed to bind syslog TCP listener to $($config.Service.Syslog.BindAddress):$($config.Service.Syslog.Port) - $($_.Exception.Message)" -Level 'ERROR'
        if ($tcpListener) { 
            try { $tcpListener.Stop() } catch { }
        }
        $tcpListener = $null
    }

    $nextFlush = (Get-Date).AddSeconds($ingestion.BatchIntervalSeconds)
    $nextAsus = (Get-Date)
    $nextWifiScan = (Get-Date)
    $asusState = Load-AsusState -Path $config.Service.Asus.StatePath

    try {
        while (-not $cts.IsCancellationRequested) {
            # Syslog UDP listener (only if successfully bound)
            if ($udpClient) {
                $remote = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
                try {
                    $bytes = $udpClient.Receive([ref]$remote)
                    if ($bytes.Length -gt 0) {
                        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
                        $parsed = ConvertFrom-SyslogLine -Line $text
                        $syslogEvent = [pscustomobject]@{
                            ReceivedUtc    = [DateTime]::UtcNow
                            EventUtc       = $parsed.EventUtc
                            SourceHost     = $parsed.SourceHost
                            AppName        = $parsed.AppName
                            Facility       = $parsed.Facility
                            Severity       = $parsed.Severity
                            Message        = $parsed.Message
                            RawMessage     = $parsed.RawMessage
                            RemoteEndpoint = $remote.ToString()
                            Source         = 'syslog'
                        }
                        $syslogBuffer.Add($syslogEvent) | Out-Null
                    }
                }
                catch [System.Net.Sockets.SocketException] {
                    if ($_.Exception.NativeErrorCode -ne 10060) {
                        Write-TelemetryLog -LogPath $logPath -Message "Syslog UDP listener error: $($_.Exception.Message)" -Level 'WARN'
                    }
                }
                catch {
                    Write-TelemetryLog -LogPath $logPath -Message "Unexpected error in syslog UDP listener: $_" -Level 'WARN'
                }
            }

            # Syslog TCP listener - accept new connections and read from existing ones
            if ($tcpListener) {
                # Accept new connections (non-blocking check)
                try {
                    if ($tcpListener.Pending()) {
                        $newClient = $tcpListener.AcceptTcpClient()
                        $newClient.ReceiveTimeout = 100
                        $clientInfo = @{
                            Client = $newClient
                            Stream = $newClient.GetStream()
                            Reader = [System.IO.StreamReader]::new($newClient.GetStream(), [System.Text.Encoding]::UTF8)
                            Endpoint = $newClient.Client.RemoteEndPoint.ToString()
                            Buffer = ''
                        }
                        $tcpClients.Add($clientInfo) | Out-Null
                        Write-TelemetryLog -LogPath $logPath -Message "TCP syslog client connected from $($clientInfo.Endpoint)" -Level 'INFO'
                    }
                }
                catch {
                    Write-TelemetryLog -LogPath $logPath -Message "TCP accept error: $($_.Exception.Message)" -Level 'WARN'
                }

                # Read from existing TCP clients
                $clientsToRemove = @()
                foreach ($clientInfo in $tcpClients) {
                    try {
                        if ($clientInfo.Client.Connected -and $clientInfo.Stream.DataAvailable) {
                            $buffer = New-Object byte[] 8192
                            $bytesRead = $clientInfo.Stream.Read($buffer, 0, $buffer.Length)
                            if ($bytesRead -gt 0) {
                                $data = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $bytesRead)
                                $clientInfo.Buffer += $data
                                
                                # Process complete lines (syslog messages end with newline)
                                while ($clientInfo.Buffer.Contains("`n")) {
                                    $nlIndex = $clientInfo.Buffer.IndexOf("`n")
                                    $line = $clientInfo.Buffer.Substring(0, $nlIndex).TrimEnd("`r")
                                    $clientInfo.Buffer = $clientInfo.Buffer.Substring($nlIndex + 1)
                                    
                                    if (-not [string]::IsNullOrWhiteSpace($line)) {
                                        $parsed = ConvertFrom-SyslogLine -Line $line
                                        $syslogEvent = [pscustomobject]@{
                                            ReceivedUtc    = [DateTime]::UtcNow
                                            EventUtc       = $parsed.EventUtc
                                            SourceHost     = $parsed.SourceHost
                                            AppName        = $parsed.AppName
                                            Facility       = $parsed.Facility
                                            Severity       = $parsed.Severity
                                            Message        = $parsed.Message
                                            RawMessage     = $parsed.RawMessage
                                            RemoteEndpoint = $clientInfo.Endpoint
                                            Source         = 'syslog'
                                        }
                                        $syslogBuffer.Add($syslogEvent) | Out-Null
                                    }
                                }
                            }
                            elseif ($bytesRead -eq 0) {
                                # Connection closed by remote
                                $clientsToRemove += $clientInfo
                            }
                        }
                        elseif (-not $clientInfo.Client.Connected) {
                            $clientsToRemove += $clientInfo
                        }
                    }
                    catch {
                        Write-TelemetryLog -LogPath $logPath -Message "TCP read error from $($clientInfo.Endpoint): $($_.Exception.Message)" -Level 'WARN'
                        $clientsToRemove += $clientInfo
                    }
                }

                # Clean up disconnected clients
                foreach ($clientInfo in $clientsToRemove) {
                    try {
                        $clientInfo.Reader.Dispose()
                        $clientInfo.Stream.Dispose()
                        $clientInfo.Client.Dispose()
                    }
                    catch { }
                    $tcpClients.Remove($clientInfo) | Out-Null
                    Write-TelemetryLog -LogPath $logPath -Message "TCP syslog client disconnected: $($clientInfo.Endpoint)" -Level 'INFO'
                }
            }

            $now = Get-Date
            if ($config.Service.Asus.Enabled -and $now -ge $nextAsus) {
                try {
                    $events = Invoke-AsusLogFetch -Config $config.Service.Asus -LogPath $config.Service.Asus.DownloadPath -State $asusState
                    if ($events.Count -gt 0) {
                        foreach ($evt in $events) { $asusBuffer.Add($evt) | Out-Null }
                        Save-AsusState -State $asusState -Path $config.Service.Asus.StatePath
                        Write-TelemetryLog -LogPath $logPath -Message "Fetched $($events.Count) ASUS router log entries." -Level 'INFO'
                    }
                }
                catch {
                    Write-TelemetryLog -LogPath $logPath -Message "Failed to fetch ASUS logs: $_" -Level 'WARN'
                }
                $nextAsus = $now.AddSeconds($config.Service.Asus.PollIntervalSeconds)
            }

            # WiFi client scanning (every 5 minutes)
            if ($config.Service.Asus.SSH -and $config.Service.Asus.SSH.Enabled -and $now -ge $nextWifiScan) {
                try {
                    $wifiEvents = Invoke-AsusWifiClientScan -Config $config.Service.Asus -State $asusState
                    if ($wifiEvents.Count -gt 0) {
                        foreach ($evt in $wifiEvents) { $wifiBuffer.Add($evt) | Out-Null }
                        Write-TelemetryLog -LogPath $logPath -Message "Collected $($wifiEvents.Count) WiFi client scan results." -Level 'INFO'
                    }
                }
                catch {
                    Write-TelemetryLog -LogPath $logPath -Message "WiFi client scan failed: $_" -Level 'WARN'
                }
                $nextWifiScan = $now.AddMinutes(5)  # Scan every 5 minutes
            }

            if ($now -ge $nextFlush) {
                if ($syslogBuffer.Count -ge $ingestion.MinBatchSize -or ($syslogBuffer.Count -gt 0 -and $now -ge $nextFlush)) {
                    $batch = $syslogBuffer.ToArray()
                    $syslogBuffer.Clear()
                    try {
                        Invoke-SyslogIngestion -Events $batch -Ingestion $ingestion -Database $database -SourceLabel 'syslog'
                        Write-TelemetryLog -LogPath $logPath -Message "Ingested $($batch.Count) syslog entries." -Level 'INFO'
                    }
                    catch {
                        Write-TelemetryLog -LogPath $logPath -Message "Syslog ingestion failed: $_" -Level 'ERROR'
                    }
                }
                if ($asusBuffer.Count -gt 0) {
                    $batch = $asusBuffer.ToArray()
                    $asusBuffer.Clear()
                    try {
                        Invoke-SyslogIngestion -Events $batch -Ingestion $ingestion -Database $database -SourceLabel 'asus'
                        Write-TelemetryLog -LogPath $logPath -Message "Ingested $($batch.Count) ASUS log entries." -Level 'INFO'
                    }
                    catch {
                        Write-TelemetryLog -LogPath $logPath -Message "ASUS log ingestion failed: $_" -Level 'ERROR'
                    }
                }
                if ($wifiBuffer.Count -gt 0) {
                    $batch = $wifiBuffer.ToArray()
                    $wifiBuffer.Clear()
                    try {
                        Invoke-SyslogIngestion -Events $batch -Ingestion $ingestion -Database $database -SourceLabel 'asus-wifi'
                        Write-TelemetryLog -LogPath $logPath -Message "Ingested $($batch.Count) WiFi scan entries." -Level 'INFO'
                    }
                    catch {
                        Write-TelemetryLog -LogPath $logPath -Message "WiFi scan ingestion failed: $_" -Level 'ERROR'
                    }
                }
                $nextFlush = (Get-Date).AddSeconds($ingestion.BatchIntervalSeconds)
            }
        }
    }
    finally {
        if ($syslogBuffer.Count -gt 0) {
            try {
                Invoke-SyslogIngestion -Events ($syslogBuffer.ToArray()) -Ingestion $ingestion -Database $database -SourceLabel 'syslog'
            }
            catch {
                Write-TelemetryLog -LogPath $logPath -Message "Final syslog ingestion failed during shutdown: $_" -Level 'ERROR'
            }
        }
        if ($asusBuffer.Count -gt 0) {
            try {
                Invoke-SyslogIngestion -Events ($asusBuffer.ToArray()) -Ingestion $ingestion -Database $database -SourceLabel 'asus'
            }
            catch {
                Write-TelemetryLog -LogPath $logPath -Message "Final ASUS ingestion failed during shutdown: $_" -Level 'ERROR'
            }
        }
        if ($wifiBuffer.Count -gt 0) {
            try {
                Invoke-SyslogIngestion -Events ($wifiBuffer.ToArray()) -Ingestion $ingestion -Database $database -SourceLabel 'asus-wifi'
            }
            catch {
                Write-TelemetryLog -LogPath $logPath -Message "Final WiFi scan ingestion failed during shutdown: $_" -Level 'ERROR'
            }
        }
        if ($udpClient) {
            $udpClient.Dispose()
        }
        # Clean up TCP resources
        foreach ($clientInfo in $tcpClients) {
            try {
                $clientInfo.Reader.Dispose()
                $clientInfo.Stream.Dispose()
                $clientInfo.Client.Dispose()
            }
            catch { }
        }
        if ($tcpListener) {
            try { $tcpListener.Stop() } catch { }
        }
        Save-AsusState -State $asusState -Path $config.Service.Asus.StatePath
        Write-TelemetryLog -LogPath $logPath -Message 'Telemetry service stopping.' -Level 'INFO'
    }
}

Export-ModuleMember -Function *-SystemDashboard*, Write-TelemetryLog, ConvertFrom-SyslogLine, ConvertFrom-AsusLine, Invoke-SyslogIngestion, Invoke-AsusLogFetch, Invoke-AsusWifiClientScan, Start-TelemetryService, Invoke-PostgresStatement

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

    if (-not $raw.Service.PSObject.Properties['Syslog']) {
        $raw.Service | Add-Member -NotePropertyName Syslog -NotePropertyValue (@{})
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

    if (-not $raw.Service.PSObject.Properties['Events']) {
        $raw.Service | Add-Member -NotePropertyName Events -NotePropertyValue (@{})
    }
    if (-not $raw.Service.Events.LogNames) {
        $raw.Service.Events.LogNames = @('System','Application','Security')
    }
    if (-not $raw.Service.Events.Levels) {
        $raw.Service.Events.Levels = @(1,2,3,4)
    }
    if (-not $raw.Service.Events.PollIntervalSeconds) {
        $raw.Service.Events.PollIntervalSeconds = 120
    }
    if (-not $raw.Service.Events.MaxEvents) {
        $raw.Service.Events.MaxEvents = 200
    }
    if (-not $raw.Service.Events.StatePath) {
        $raw.Service.Events.StatePath = Resolve-SystemDashboardPath -BasePath $base -Path './var/events/state.json'
    }
    else {
        $raw.Service.Events.StatePath = Resolve-SystemDashboardPath -BasePath $base -Path $raw.Service.Events.StatePath
    }

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

    function Convert-ToIsoTimestamp {
        param([object]$Value)
        if ($null -eq $Value) { return $null }
        if ($Value -is [DateTime]) {
            return $Value.ToUniversalTime().ToString('o')
        }
        $parsed = [DateTime]::MinValue
        if ([DateTime]::TryParse($Value.ToString(), [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
            return $parsed.ToUniversalTime().ToString('o')
        }
        if ([DateTime]::TryParse($Value.ToString(), [ref]$parsed)) {
            return $parsed.ToUniversalTime().ToString('o')
        }
        return $null
    }

    if (-not (Test-Path -LiteralPath $TargetDirectory)) {
        New-Item -ItemType Directory -Path $TargetDirectory -Force | Out-Null
    }
    $name = "{0}_{1:yyyyMMddTHHmmssfffZ}.csv" -f $Prefix, (Get-Date).ToUniversalTime()
    $path = Join-Path $TargetDirectory $name

    $rows = foreach ($evt in $Events) {
        [pscustomobject]@{
            ReceivedUtc    = Convert-ToIsoTimestamp $evt.ReceivedUtc
            EventUtc       = Convert-ToIsoTimestamp $evt.EventUtc
            SourceHost     = $evt.SourceHost
            AppName        = $evt.AppName
            Facility       = $evt.Facility
            Severity       = $evt.Severity
            Message        = $evt.Message
            RawMessage     = $evt.RawMessage
            RemoteEndpoint = $evt.RemoteEndpoint
            Source         = $evt.Source
        }
    }

    $rows | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
    return $path
}

function Normalize-MacAddress {
    [CmdletBinding()]
    param([string]$Mac)

    if ([string]::IsNullOrWhiteSpace($Mac)) { return $null }
    $normalized = $Mac.Trim() -replace '-', ':'
    $normalized = $normalized.ToUpperInvariant()
    if ($normalized -match '^([0-9A-F]{2}:){5}[0-9A-F]{2}$') {
        return $normalized
    }
    return $null
}

function Get-MacAddressesFromText {
    [CmdletBinding()]
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $matches = [regex]::Matches($Text, '(?i)([0-9a-f]{2}[:-]){5}[0-9a-f]{2}')
    $macs = foreach ($match in $matches) {
        Normalize-MacAddress -Mac $match.Value
    }
    return $macs | Where-Object { $_ } | Select-Object -Unique
}

function Get-RssiFromText {
    [CmdletBinding()]
    param([string]$Text)

    if ($Text -match '(?i)rssi[:=]\\s*(-?\\d+)') {
        return [int]$Matches[1]
    }
    return $null
}

function Get-IpFromText {
    [CmdletBinding()]
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $match = [regex]::Match($Text, '\\b(\\d{1,3}(?:\\.\\d{1,3}){3})\\b')
    if ($match.Success) {
        return $match.Value
    }
    return $null
}

function Get-SyslogEventClassification {
    [CmdletBinding()]
    param(
        [Parameter()][string]$AppName,
        [Parameter()][string]$Message
    )

    $text = ("{0} {1}" -f ($AppName ?? ''), ($Message ?? '')).ToLowerInvariant()
    $category = 'system'
    $eventType = 'syslog'

    if ($text -match 'dhcp|dnsmasq-dhcp|udhcpd') {
        $category = 'dhcp'
        if ($text -match 'ack|lease|leased|bound') { $eventType = 'dhcp_lease' }
        elseif ($text -match 'release|released') { $eventType = 'dhcp_release' }
        elseif ($text -match 'discover') { $eventType = 'dhcp_discover' }
        elseif ($text -match 'request') { $eventType = 'dhcp_request' }
        elseif ($text -match 'offer') { $eventType = 'dhcp_offer' }
        elseif ($text -match 'decline') { $eventType = 'dhcp_decline' }
        elseif ($text -match 'expire|expired') { $eventType = 'dhcp_expire' }
        else { $eventType = 'dhcp_event' }
    }
    elseif ($text -match 'hostapd|wlceventd|roam|assoc|disassoc|deauth|rssi') {
        $category = 'wifi'
        if ($text -match 'deauth') { $eventType = 'wifi_deauth' }
        elseif ($text -match 'disassoc') { $eventType = 'wifi_disassoc' }
        elseif ($text -match 'assoc') { $eventType = 'wifi_assoc' }
        elseif ($text -match 'auth') { $eventType = 'wifi_auth' }
        elseif ($text -match 'roam') { $eventType = 'wifi_roam' }
        elseif ($text -match 'rssi') { $eventType = 'wifi_signal' }
        else { $eventType = 'wifi_event' }
    }
    elseif ($text -match 'firewall|iptables|blocked|drop') {
        $category = 'firewall'
        $eventType = 'firewall'
    }
    elseif ($text -match 'auth|login|password|ssh|vpn|radius') {
        $category = 'auth'
        $eventType = 'auth_event'
    }
    elseif ($text -match 'dns|resolver|named|unbound') {
        $category = 'dns'
        $eventType = 'dns_event'
    }

    return [pscustomobject]@{
        Category  = $category
        EventType = $eventType
    }
}

function Get-DeviceObservationsFromSyslogBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IEnumerable]$Events
    )

    $observations = New-Object System.Collections.Generic.List[object]
    foreach ($evt in $Events) {
        $message = $evt.Message
        $macs = Get-MacAddressesFromText -Text $message
        if ($macs.Count -eq 0) { continue }
        $classification = Get-SyslogEventClassification -AppName $evt.AppName -Message $message
        $rssi = Get-RssiFromText -Text $message
        $ip = Get-IpFromText -Text $message
        $occurred = if ($evt.EventUtc) { $evt.EventUtc } else { $evt.ReceivedUtc }
        foreach ($mac in $macs) {
            $observations.Add([pscustomobject]@{
                OccurredAt = $occurred
                ReceivedAt = $evt.ReceivedUtc
                MacAddress = $mac
                EventType  = $classification.EventType
                Category   = $classification.Category
                SourceHost = $evt.SourceHost
                AppName    = $evt.AppName
                Rssi       = $rssi
                IpAddress  = $ip
                Message    = $evt.Message
                RawMessage = $evt.RawMessage
            }) | Out-Null
        }
    }
    return ,$observations.ToArray()
}

function Write-DeviceObservationsCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IEnumerable]$Observations,
        [Parameter(Mandatory)][string]$TargetDirectory,
        [Parameter(Mandatory)][string]$Prefix
    )

    if (-not (Test-Path -LiteralPath $TargetDirectory)) {
        New-Item -ItemType Directory -Path $TargetDirectory -Force | Out-Null
    }
    $name = "{0}_{1:yyyyMMddTHHmmssfffZ}.csv" -f $Prefix, (Get-Date).ToUniversalTime()
    $path = Join-Path $TargetDirectory $name

    $rows = foreach ($obs in $Observations) {
        [pscustomobject]@{
            OccurredAt = $obs.OccurredAt.ToUniversalTime().ToString('o')
            ReceivedAt = $obs.ReceivedAt.ToUniversalTime().ToString('o')
            MacAddress = $obs.MacAddress
            EventType  = $obs.EventType
            Category   = $obs.Category
            SourceHost = $obs.SourceHost
            AppName    = $obs.AppName
            Rssi       = $obs.Rssi
            IpAddress  = $obs.IpAddress
            Message    = $obs.Message
            RawMessage = $obs.RawMessage
        }
    }

    $rows | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
    return $path
}

function Invoke-PostgresDeviceObservationCopy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Database,
        [Parameter(Mandatory)][string]$CsvPath,
        [int]$Retries = 2
    )

    function Get-DbSetting {
        param([object]$Db, [string]$Name)
        if ($Db -is [hashtable]) {
            return ($Db.ContainsKey($Name) ? $Db[$Name] : $null)
        }
        $prop = $Db.PSObject.Properties[$Name]
        return $(if ($prop) { $prop.Value } else { $null })
    }

    $psqlPath = Get-DbSetting $Database 'PsqlPath'
    if (-not $psqlPath) { $psqlPath = 'psql' }
    $command = Get-Command -Name $psqlPath -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "psql executable '$psqlPath' not found in PATH. Set Database.PsqlPath in config.json."
    }

    $host = (Get-DbSetting $Database 'Host') ?? 'localhost'
    $port = (Get-DbSetting $Database 'Port') ?? 5432
    $databaseName = (Get-DbSetting $Database 'Database') ?? (Get-DbSetting $Database 'Name')
    $username = (Get-DbSetting $Database 'Username') ?? (Get-DbSetting $Database 'User')
    if (-not $databaseName) {
        throw 'Database name must be specified in the configuration.'
    }
    if (-not $username) {
        throw 'Database username must be specified in the configuration.'
    }

    $password = Resolve-SystemDashboardSecret -Secret (Get-DbSetting $Database 'PasswordSecret') -Fallback (Get-DbSetting $Database 'Password')
    if ([string]::IsNullOrEmpty($password)) {
        throw 'Database password is not configured. Provide Database.Password or Database.PasswordSecret.'
    }

    $schema = (Get-DbSetting $Database 'Schema') ?? 'telemetry'
    $copyCommand = "\copy $schema.device_observations (occurred_at, received_at, mac_address, event_type, category, source_host, app_name, rssi, ip_address, message, raw_message) FROM '$CsvPath' WITH (FORMAT csv, HEADER true, DELIMITER ',')"
    $argsBase = @('-h', $host, '-p', [string]$port, '-U', $username, '-d', $databaseName, '-c', $copyCommand)

    $attempt = 0
    do {
        $attempt++
        $env:PGPASSWORD = $password
        try {
            $output = & $command.Source @argsBase 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                throw "psql exited with code $LASTEXITCODE. Output: $output"
            }
            return
        }
        catch {
            if ($attempt -gt $Retries) { throw }
            Start-Sleep -Seconds ([math]::Min(5, $attempt * 2))
        }
        finally {
            Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
        }
    } while ($attempt -le $Retries)
}

function Convert-ToSqlLiteral {
    param([string]$Value)
    if ($null -eq $Value) { return 'NULL' }
    return "'{0}'" -f ($Value.Replace("'", "''"))
}

function Update-DeviceProfiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IEnumerable]$Observations,
        [Parameter(Mandatory)][object]$Database
    )

    $groups = $Observations | Group-Object MacAddress
    foreach ($group in $groups) {
        $mac = $group.Name
        if (-not $mac) { continue }
        $sorted = $group.Group | Sort-Object OccurredAt
        $first = $sorted | Select-Object -First 1
        $last = $sorted | Select-Object -Last 1
        $rssi = ($sorted | Where-Object { $null -ne $_.Rssi } | Select-Object -Last 1).Rssi
        $ip = ($sorted | Where-Object { $_.IpAddress } | Select-Object -Last 1).IpAddress
        $vendor = $mac.Substring(0,8)
        $count = $group.Count
        $rssiValue = if ($null -ne $rssi) { $rssi } else { 'NULL' }
        $ipValue = if ($ip) { ("'{0}'::inet" -f $ip) } else { 'NULL' }
        $sql = @"
INSERT INTO telemetry.device_profiles
  (mac_address, first_seen, last_seen, last_event_type, last_category, last_source_host, last_app_name, last_rssi, vendor_oui, last_ip, total_events)
VALUES
  ($(Convert-ToSqlLiteral $mac), $(Convert-ToSqlLiteral $first.OccurredAt.ToUniversalTime().ToString('o')), $(Convert-ToSqlLiteral $last.OccurredAt.ToUniversalTime().ToString('o')),
   $(Convert-ToSqlLiteral $last.EventType), $(Convert-ToSqlLiteral $last.Category), $(Convert-ToSqlLiteral $last.SourceHost), $(Convert-ToSqlLiteral $last.AppName),
   $rssiValue, $(Convert-ToSqlLiteral $vendor), $ipValue, $count)
ON CONFLICT (mac_address) DO UPDATE
SET
  last_seen = EXCLUDED.last_seen,
  last_event_type = EXCLUDED.last_event_type,
  last_category = EXCLUDED.last_category,
  last_source_host = EXCLUDED.last_source_host,
  last_app_name = EXCLUDED.last_app_name,
  last_rssi = COALESCE(EXCLUDED.last_rssi, telemetry.device_profiles.last_rssi),
  vendor_oui = COALESCE(telemetry.device_profiles.vendor_oui, EXCLUDED.vendor_oui),
  last_ip = COALESCE(EXCLUDED.last_ip, telemetry.device_profiles.last_ip),
  total_events = telemetry.device_profiles.total_events + EXCLUDED.total_events,
  first_seen = LEAST(telemetry.device_profiles.first_seen, EXCLUDED.first_seen);
"@
        Invoke-PostgresStatement -Database $Database -Sql $sql
    }
}

function Invoke-PostgresCopy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Database,
        [Parameter(Mandatory)][string]$TableName,
        [Parameter(Mandatory)][string]$CsvPath
    )

    function Get-DbSetting {
        param([object]$Db, [string]$Name)
        if ($Db -is [hashtable]) {
            return ($Db.ContainsKey($Name) ? $Db[$Name] : $null)
        }
        $prop = $Db.PSObject.Properties[$Name]
        return $(if ($prop) { $prop.Value } else { $null })
    }

    $psqlPath = Get-DbSetting $Database 'PsqlPath'
    if (-not $psqlPath) { $psqlPath = 'psql' }
    $command = Get-Command -Name $psqlPath -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "psql executable '$psqlPath' not found in PATH. Set Database.PsqlPath in config.json."
    }

    $dbHost = (Get-DbSetting $Database 'Host') ?? 'localhost'
    $port = (Get-DbSetting $Database 'Port') ?? 5432
    $databaseName = (Get-DbSetting $Database 'Database') ?? (Get-DbSetting $Database 'Name')
    $username = (Get-DbSetting $Database 'Username') ?? (Get-DbSetting $Database 'User')
    if (-not $databaseName) {
        throw 'Database name must be specified in the configuration.'
    }
    if (-not $username) {
        throw 'Database username must be specified in the configuration.'
    }

    $password = Resolve-SystemDashboardSecret -Secret (Get-DbSetting $Database 'PasswordSecret') -Fallback (Get-DbSetting $Database 'Password')
    if ([string]::IsNullOrEmpty($password)) {
        throw 'Database password is not configured. Provide Database.Password or Database.PasswordSecret.'
    }

    $env:PGPASSWORD = $password
    try {
        $schema = (Get-DbSetting $Database 'Schema') ?? 'telemetry'
        if (-not $TableName.Contains('.')) {
            $table = "$schema.$TableName"
        }
        else {
            $table = $TableName
        }
        $copyCommand = "\copy $table (received_utc, event_utc, source_host, app_name, facility, severity, message, raw_message, remote_endpoint, source) FROM '$CsvPath' WITH (FORMAT csv, HEADER true, DELIMITER ',')"
        $psqlArgs = @('-h', $dbHost, '-p', [string]$port, '-U', $username, '-d', $databaseName, '-c', $copyCommand)
        $output = & $command.Source @psqlArgs 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "psql exited with code $LASTEXITCODE. Output: $output"
        }
    }
    finally {
        Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    }
}

function Invoke-PostgresStatement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Database,
        [Parameter(Mandatory)][string]$Sql
    )

    function Get-DbSetting {
        param([object]$Db, [string]$Name)
        if ($Db -is [hashtable]) {
            return ($Db.ContainsKey($Name) ? $Db[$Name] : $null)
        }
        $prop = $Db.PSObject.Properties[$Name]
        return $(if ($prop) { $prop.Value } else { $null })
    }

    $psqlPath = Get-DbSetting $Database 'PsqlPath'
    if (-not $psqlPath) { $psqlPath = 'psql' }
    $command = Get-Command -Name $psqlPath -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "psql executable '$psqlPath' not found in PATH. Set Database.PsqlPath in config.json."
    }

    $dbHost = (Get-DbSetting $Database 'Host') ?? 'localhost'
    $port = (Get-DbSetting $Database 'Port') ?? 5432
    $databaseName = (Get-DbSetting $Database 'Database') ?? (Get-DbSetting $Database 'Name')
    $username = (Get-DbSetting $Database 'Username') ?? (Get-DbSetting $Database 'User')
    if (-not $databaseName -or -not $username) {
        throw 'Database connection settings are incomplete (host/user/database required).'
    }

    $password = Resolve-SystemDashboardSecret -Secret (Get-DbSetting $Database 'PasswordSecret') -Fallback (Get-DbSetting $Database 'Password')
    if ([string]::IsNullOrEmpty($password)) {
        throw 'Database password is not configured. Provide Database.Password or Database.PasswordSecret.'
    }

    $env:PGPASSWORD = $password
    try {
        $psqlArgs = @('-h', $dbHost, '-p', [string]$port, '-U', $username, '-d', $databaseName, '-c', $Sql)
        $output = & $command.Source @psqlArgs 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "psql exited with code $LASTEXITCODE when executing statement. Output: $output"
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
        [Parameter(Mandatory)][object]$Ingestion,
        [Parameter(Mandatory)][object]$Database,
        [Parameter()][string]$SourceLabel = 'syslog'
    )

    $batch = @($Events)
    if ($batch.Count -eq 0) { return }

    function Get-IngestionSetting {
        param([object]$Settings, [string]$Name)
        if ($Settings -is [hashtable]) {
            return ($Settings.ContainsKey($Name) ? $Settings[$Name] : $null)
        }
        $prop = $Settings.PSObject.Properties[$Name]
        return $(if ($prop) { $prop.Value } else { $null })
    }

    try {
        $monthStart = (Get-Date).ToUniversalTime().ToString('yyyy-MM-01')
        Invoke-PostgresStatement -Database $Database -Sql "SELECT telemetry.ensure_syslog_partition('$monthStart'::date);"
    }
    catch {
        Write-Verbose "Failed to ensure syslog partition: $_"
    }

    $stagingDir = Get-IngestionSetting $Ingestion 'StagingDirectory'
    if (-not $stagingDir) { $stagingDir = './var/staging' }
    $csvPath = Write-BatchToCsv -Events $batch -TargetDirectory $stagingDir -Prefix $SourceLabel
    try {
        $table = Get-PartitionTableName -BaseName 'syslog_generic' -Timestamp (Get-Date)
        Invoke-PostgresCopy -Database $Database -TableName $table -CsvPath $csvPath
    }
    finally {
        Remove-Item -LiteralPath $csvPath -ErrorAction SilentlyContinue
    }

    $deviceObservations = Get-DeviceObservationsFromSyslogBatch -Events $batch
    if ($deviceObservations.Count -gt 0) {
        $deviceCsv = Write-DeviceObservationsCsv -Observations $deviceObservations -TargetDirectory $stagingDir -Prefix "$SourceLabel-devices"
        try {
            Invoke-PostgresDeviceObservationCopy -Database $Database -CsvPath $deviceCsv
            Update-DeviceProfiles -Observations $deviceObservations -Database $Database
        }
        finally {
            Remove-Item -LiteralPath $deviceCsv -ErrorAction SilentlyContinue
        }
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

function Load-EventIngestionState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @{ Logs = @{} }
    }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        return @{ Logs = @{} }
    }

    $logs = @{}
    if ($raw.Logs) {
        foreach ($prop in $raw.Logs.PSObject.Properties) {
            $logs[$prop.Name] = $prop.Value
        }
    }
    return @{ Logs = $logs }
}

function Save-EventIngestionState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$Path
    )

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $payload = [pscustomobject]@{
        Logs = $State.Logs
    }
    $payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function ConvertTo-EventSeverity {
    [CmdletBinding()]
    param(
        [Parameter()][string]$LevelDisplayName,
        [Parameter()][int]$Level
    )

    if ($LevelDisplayName) {
        switch ($LevelDisplayName.ToLowerInvariant()) {
            'critical' { return 'critical' }
            'error' { return 'error' }
            'warning' { return 'warning' }
            'information' { return 'information' }
            'verbose' { return 'verbose' }
        }
    }

    switch ($Level) {
        1 { 'critical' }
        2 { 'error' }
        3 { 'warning' }
        4 { 'information' }
        5 { 'verbose' }
        Default { 'unknown' }
    }
}

function Write-EventBatchToCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IEnumerable]$Events,
        [Parameter(Mandatory)][string]$TargetDirectory,
        [Parameter(Mandatory)][string]$Prefix
    )

    function Convert-ToIsoTimestamp {
        param([object]$Value)
        if ($null -eq $Value) { return $null }
        if ($Value -is [DateTime]) {
            return $Value.ToUniversalTime().ToString('o')
        }
        $parsed = [DateTime]::MinValue
        if ([DateTime]::TryParse($Value.ToString(), [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
            return $parsed.ToUniversalTime().ToString('o')
        }
        if ([DateTime]::TryParse($Value.ToString(), [ref]$parsed)) {
            return $parsed.ToUniversalTime().ToString('o')
        }
        return $null
    }

    if (-not (Test-Path -LiteralPath $TargetDirectory)) {
        New-Item -ItemType Directory -Path $TargetDirectory -Force | Out-Null
    }
    $name = "{0}_{1:yyyyMMddTHHmmssfffZ}.csv" -f $Prefix, (Get-Date).ToUniversalTime()
    $path = Join-Path $TargetDirectory $name

    $rows = foreach ($evt in $Events) {
        [pscustomobject]@{
            EventType     = $evt.EventType
            Source        = $evt.Source
            Severity      = $evt.Severity
            Subject       = $evt.Subject
            OccurredAt    = Convert-ToIsoTimestamp $evt.OccurredAt
            ReceivedAt    = Convert-ToIsoTimestamp $evt.ReceivedAt
            CorrelationId = $evt.CorrelationId
            Payload       = $evt.Payload
        }
    }

    $rows | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
    return $path
}

function Invoke-PostgresEventCopy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Database,
        [Parameter(Mandatory)][string]$CsvPath,
        [int]$Retries = 2
    )

    function Get-DbSetting {
        param([object]$Db, [string]$Name)
        if ($Db -is [hashtable]) {
            return ($Db.ContainsKey($Name) ? $Db[$Name] : $null)
        }
        $prop = $Db.PSObject.Properties[$Name]
        return $(if ($prop) { $prop.Value } else { $null })
    }

    $psqlPath = Get-DbSetting $Database 'PsqlPath'
    if (-not $psqlPath) { $psqlPath = 'psql' }
    $command = Get-Command -Name $psqlPath -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "psql executable '$psqlPath' not found in PATH. Set Database.PsqlPath in config.json."
    }

    $host = (Get-DbSetting $Database 'Host') ?? 'localhost'
    $port = (Get-DbSetting $Database 'Port') ?? 5432
    $databaseName = (Get-DbSetting $Database 'Database') ?? (Get-DbSetting $Database 'Name')
    $username = (Get-DbSetting $Database 'Username') ?? (Get-DbSetting $Database 'User')
    if (-not $databaseName) {
        throw 'Database name must be specified in the configuration.'
    }
    if (-not $username) {
        throw 'Database username must be specified in the configuration.'
    }

    $password = Resolve-SystemDashboardSecret -Secret (Get-DbSetting $Database 'PasswordSecret') -Fallback (Get-DbSetting $Database 'Password')
    if ([string]::IsNullOrEmpty($password)) {
        throw 'Database password is not configured. Provide Database.Password or Database.PasswordSecret.'
    }

    $schema = (Get-DbSetting $Database 'Schema') ?? 'telemetry'
    $copyCommand = "\copy $schema.events (event_type, source, severity, subject, occurred_at, received_at, correlation_id, payload) FROM '$CsvPath' WITH (FORMAT csv, HEADER true, DELIMITER ',')"
    $argsBase = @('-h', $host, '-p', [string]$port, '-U', $username, '-d', $databaseName, '-c', $copyCommand)

    $attempt = 0
    do {
        $attempt++
        $env:PGPASSWORD = $password
        try {
            $output = & $command.Source @argsBase 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                throw "psql exited with code $LASTEXITCODE. Output: $output"
            }
            return
        }
        catch {
            if ($attempt -gt $Retries) { throw }
            Start-Sleep -Seconds ([math]::Min(5, $attempt * 2))
        }
        finally {
            Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
        }
    } while ($attempt -le $Retries)
}

function Invoke-EventIngestion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Events,
        [Parameter(Mandatory)][object]$Ingestion,
        [Parameter(Mandatory)][object]$Database
    )

    $batch = @($Events)
    if ($batch.Count -eq 0) { return }

    $stagingDir = $Ingestion.StagingDirectory ?? './var/staging'
    $csvPath = Write-EventBatchToCsv -Events $batch -TargetDirectory $stagingDir -Prefix 'events'
    try {
        Invoke-PostgresEventCopy -Database $Database -CsvPath $csvPath
    }
    finally {
        Remove-Item -LiteralPath $csvPath -ErrorAction SilentlyContinue
    }
}

function Get-WindowsEventBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][hashtable]$State
    )

    $events = @()
    $nextState = @{ Logs = @{} }
    $logNames = @($Config.LogNames)
    $levels = @($Config.Levels)
    $maxEvents = [int]($Config.MaxEvents ?? 200)

    foreach ($logName in $logNames) {
        $prev = $null
        if ($State.Logs.ContainsKey($logName)) {
            $prev = $State.Logs[$logName]
        }

        $startTime = (Get-Date).AddMinutes(-10)
        if ($prev -and $prev.LastTimeUtc) {
            try {
                $startTime = [DateTime]::Parse($prev.LastTimeUtc, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal)
            }
            catch {
                $startTime = (Get-Date).AddMinutes(-10)
            }
        }

        $filter = @{ LogName = $logName; StartTime = $startTime }
        if ($levels.Count -gt 0) { $filter.Level = $levels }

        $batch = Get-WinEvent -FilterHashtable $filter -MaxEvents $maxEvents -ErrorAction SilentlyContinue
        if ($prev -and $prev.LastRecordId) {
            $batch = $batch | Where-Object { $_.RecordId -gt $prev.LastRecordId }
        }

        if ($batch) {
            $events += $batch
            $latest = $batch | Sort-Object RecordId | Select-Object -Last 1
            if ($latest) {
                $nextState.Logs[$logName] = @{
                    LastRecordId = $latest.RecordId
                    LastTimeUtc  = $latest.TimeCreated.ToUniversalTime().ToString('o')
                }
                continue
            }
        }

        if ($prev) {
            $nextState.Logs[$logName] = $prev
        }
    }

    return [pscustomobject]@{
        Events    = $events
        NextState = $nextState
    }
}

function Convert-WinEventToTelemetryEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Diagnostics.Eventing.Reader.EventRecord]$Event
    )

    $payload = [ordered]@{
        log_name   = $Event.LogName
        provider   = $Event.ProviderName
        event_id   = $Event.Id
        record_id  = $Event.RecordId
        level      = $Event.LevelDisplayName
        task       = $Event.TaskDisplayName
        machine    = $Event.MachineName
        message    = $Event.Message
    } | ConvertTo-Json -Compress

    return [pscustomobject]@{
        EventType     = 'windows_event'
        Source        = $Event.LogName
        Severity      = ConvertTo-EventSeverity -LevelDisplayName $Event.LevelDisplayName -Level $Event.Level
        Subject       = $Event.ProviderName
        OccurredAt    = $Event.TimeCreated
        ReceivedAt    = (Get-Date).ToUniversalTime()
        CorrelationId = "$($Event.LogName):$($Event.RecordId)"
        Payload       = $payload
    }
}

function Invoke-AsusLogFetch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter()][hashtable]$State
    )

    function Get-AsusSetting {
        param([object]$Settings, [string]$Name)
        if ($Settings -is [hashtable]) {
            return ($Settings.ContainsKey($Name) ? $Settings[$Name] : $null)
        }
        $prop = $Settings.PSObject.Properties[$Name]
        return $(if ($prop) { $prop.Value } else { $null })
    }

    $uri = (Get-AsusSetting $Config 'Uri') ?? (Get-AsusSetting $Config 'Url')
    if (-not $uri) {
        throw 'Asus log endpoint URI must be configured (Service.Asus.Uri).'
    }

    $params = @{ Uri = $uri; Method = 'Get' }
    $timeoutSeconds = Get-AsusSetting $Config 'TimeoutSeconds'
    if ($timeoutSeconds) { $params.TimeoutSec = [int]$timeoutSeconds }
    $headers = Get-AsusSetting $Config 'Headers'
    if ($headers) { $params.Headers = $headers }

    $username = (Get-AsusSetting $Config 'Username') ?? (Get-AsusSetting $Config 'User')
    if ($username) {
        $password = Resolve-SystemDashboardSecret -Secret (Get-AsusSetting $Config 'PasswordSecret') -Fallback (Get-AsusSetting $Config 'Password')
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
        $parsed = ConvertFrom-AsusLine -Line $line -DefaultHost ((Get-AsusSetting $Config 'HostName') ?? 'asus-router')
        $parsed | Add-Member -NotePropertyName Source -NotePropertyValue 'asus'
        $parsed | Add-Member -NotePropertyName RemoteEndpoint -NotePropertyValue ((Get-AsusSetting $Config 'Uri') ?? '')
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
    $eventsConfig = $config.Service.Events
    $database = @{}
    $config.Database.PSObject.Properties | ForEach-Object { $database[$_.Name] = $_.Value }

    $eventsStateDir = $null
    if ($eventsConfig.StatePath) {
        $eventsStateDir = Split-Path -Parent $eventsConfig.StatePath
    }

    foreach ($dir in @($config.Service.Syslog.BufferDirectory, $config.Service.Asus.DownloadPath, ($config.Service.Asus.StatePath | Split-Path -Parent), $eventsStateDir, $ingestion.StagingDirectory)) {
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

    $nextFlush = (Get-Date).AddSeconds($ingestion.BatchIntervalSeconds)
    $nextAsus = (Get-Date)
    $nextWifiScan = (Get-Date)
    $nextEvents = (Get-Date)
    $asusState = Load-AsusState -Path $config.Service.Asus.StatePath
    $eventsState = Load-EventIngestionState -Path $eventsConfig.StatePath

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
                        Write-TelemetryLog -LogPath $logPath -Message "Syslog listener error: $($_.Exception.Message)" -Level 'WARN'
                    }
                }
                catch {
                    Write-TelemetryLog -LogPath $logPath -Message "Unexpected error in syslog listener: $_" -Level 'WARN'
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

            if ($eventsConfig.Enabled -and $now -ge $nextEvents) {
                if (-not $IsWindows) {
                    Write-TelemetryLog -LogPath $logPath -Message "Event ingestion is enabled but the host is not Windows. Skipping." -Level 'WARN'
                    $nextEvents = $now.AddSeconds($eventsConfig.PollIntervalSeconds)
                }
                else {
                    try {
                        $batchInfo = Get-WindowsEventBatch -Config $eventsConfig -State $eventsState
                        $winEvents = @($batchInfo.Events)
                        if ($winEvents.Count -gt 0) {
                            $payload = $winEvents | ForEach-Object { Convert-WinEventToTelemetryEvent -Event $_ }
                            Invoke-EventIngestion -Events $payload -Ingestion $ingestion -Database $database
                            $eventsState = $batchInfo.NextState
                            Save-EventIngestionState -State $eventsState -Path $eventsConfig.StatePath
                            Write-TelemetryLog -LogPath $logPath -Message "Ingested $($winEvents.Count) Windows events." -Level 'INFO'
                        }
                        elseif ($batchInfo.NextState.Logs.Count -gt 0) {
                            $eventsState = $batchInfo.NextState
                            Save-EventIngestionState -State $eventsState -Path $eventsConfig.StatePath
                        }
                    }
                    catch {
                        Write-TelemetryLog -LogPath $logPath -Message "Windows event ingestion failed: $_" -Level 'WARN'
                    }
                    $nextEvents = $now.AddSeconds($eventsConfig.PollIntervalSeconds)
                }
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
        Save-AsusState -State $asusState -Path $config.Service.Asus.StatePath
        if ($eventsConfig.Enabled) {
            Save-EventIngestionState -State $eventsState -Path $eventsConfig.StatePath
        }
        Write-TelemetryLog -LogPath $logPath -Message 'Telemetry service stopping.' -Level 'INFO'
    }
}

Export-ModuleMember -Function *-SystemDashboard*, Write-TelemetryLog, ConvertFrom-SyslogLine, ConvertFrom-AsusLine, Invoke-SyslogIngestion, Invoke-AsusLogFetch, Invoke-AsusWifiClientScan, Start-TelemetryService, Invoke-PostgresStatement

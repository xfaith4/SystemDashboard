#requires -Version 7
<#
.SYNOPSIS
    System Monitor WebApp backend (Pode) + collectors + OpenAI advisory.
.DESCRIPTION
    - Serves REST/HTML with Pode
    - Collects Windows Events (Application/System) to SQLite
    - Streams live metrics via SSE
    - Router clients via provider model (Asuswrt over ssh.exe; GenericSnmp via snmpwalk if present)
    - Syslog polling (SolarWinds) + optional UDP 514 listener
    - OpenAI advisory endpoint with redaction & basic cost controls
.NOTES
    Author persona: Senior SRE/IT Ops Architect; direct, pragmatic.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Exported functions
Export-ModuleMember -Function `
    Start-SystemDashboard, Stop-SystemDashboard, `
    Initialize-Database, Invoke-AIAnalysis, `
    Get-RouterClients, Get-EventRows, Get-SyslogRows

# --- Imports ---
# Pode must be available: Install-Module Pode -Scope CurrentUser
if (-not (Get-Module -ListAvailable -Name Pode)) {
    Write-Warning "Module 'Pode' not found. Install with: Install-Module Pode -Scope CurrentUser"
}
Import-Module Pode -ErrorAction Stop

# Try to load Microsoft.Data.Sqlite (inbox with modern PowerShell/.NET 6+)
# Fall back with a friendly error if not available.
try {
    Add-Type -AssemblyName Microsoft.Data.Sqlite
} catch {
    Write-Warning "Microsoft.Data.Sqlite not found in the GAC. On most PS7 installs it's present. If not, install the .NET package or add the assembly manually."
}

# --- Paths & Globals ---
$Script:Root       = Split-Path -Parent $PSCommandPath
$Script:RepoRoot   = Split-Path -Parent (Split-Path -Parent $Script:Root)
$Script:WebRoot    = Join-Path $Script:RepoRoot 'webroot'
$Script:LogsDir    = Join-Path $Script:RepoRoot 'logs'
$Script:ConfigPath = if ($env:SYSTEMDASHBOARD_CONFIG) { $env:SYSTEMDASHBOARD_CONFIG } else { Join-Path $Script:RepoRoot 'config.json' }
$Script:Server     = $null
$Script:SseClients = [System.Collections.Concurrent.ConcurrentBag[System.IO.StreamWriter]]::new()
$Script:SyslogUdp  = $null
$Script:DbConn     = $null
$Script:DbKind     = 'sqlite' # sqlite | postgres
$Script:StopToken  = [System.Threading.CancellationTokenSource]::new()
$Script:TelemetryDb = $null

# Ensure logs directory exists
if (-not (Test-Path $Script:LogsDir)) { New-Item -ItemType Directory -Path $Script:LogsDir | Out-Null }

function Write-AppLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')]$Level='INFO',
        [hashtable]$Data
    )
    $entry = [ordered]@{
        ts    = (Get-Date).ToString('o')
        level = $Level
        msg   = $Message
        data  = $Data
    } | ConvertTo-Json -Compress
    Add-Content -LiteralPath (Join-Path $Script:LogsDir 'app.log') -Value $entry
    if ($Level -eq 'ERROR') { Write-Error $Message } elseif ($Level -eq 'WARN') { Write-Warning $Message } else { Write-Verbose $Message }
}

function Get-Config {
    if (-not (Test-Path $Script:ConfigPath)) {
        throw "Config file not found at $($Script:ConfigPath)."
    }
    $cfg = Get-Content $Script:ConfigPath -Raw | ConvertFrom-Json

    # Env overrides
    if ($env:MON_PORT)      { $cfg.http.port = [int]$env:MON_PORT }
    if ($env:MON_BIND)      { $cfg.http.bind = $env:MON_BIND }
    if ($env:MON_DB)        { $cfg.database.kind = $env:MON_DB }
    if ($env:MON_DB -eq 'postgres' -and $env:POSTGRES_CONN_STRING) { $cfg.database.postgresConnection = $env:POSTGRES_CONN_STRING }
    if ($env:OPENAI_API_KEY){ $cfg.ai.apiKey = $env:OPENAI_API_KEY }
    if ($env:ROUTER_PROVIDER){ $cfg.router.provider = $env:ROUTER_PROVIDER }
    if ($env:ROUTER_HOST)   { $cfg.router.host = $env:ROUTER_HOST }
    if ($env:ROUTER_PORT)   { $cfg.router.port = [int]$env:ROUTER_PORT }
    if ($env:ROUTER_USER)   { $cfg.router.user = $env:ROUTER_USER }

    return $cfg
}

function Resolve-TelemetrySecret {
    param([object]$Secret)
    if ($null -eq $Secret) { return $null }
    if ($Secret -is [string]) {
        if ($Secret.StartsWith('env:', [System.StringComparison]::OrdinalIgnoreCase)) {
            $name = $Secret.Substring(4)
            return [Environment]::GetEnvironmentVariable($name)
        }
        elseif ($Secret.StartsWith('file:', [System.StringComparison]::OrdinalIgnoreCase)) {
            $path = $Secret.Substring(5)
            if (-not (Test-Path -LiteralPath $path)) { return $null }
            return (Get-Content -LiteralPath $path -Raw).Trim()
        }
        else {
            return $Secret
        }
    }
    return $Secret
}

function Initialize-TelemetryContext {
    param([object]$Config)

    $Script:TelemetryDb = $null
    if (-not $Config.telemetry) { return }
    if ($Config.telemetry.enabled -ne $true) { return }
    $db = $Config.telemetry.database
    if (-not $db) { Write-AppLog -Level 'WARN' -Message "telemetry.enabled is true but telemetry.database is missing."; return }

    $psql = $db.psqlPath ?? 'psql'
    $psqlCmd = Get-Command -Name $psql -ErrorAction SilentlyContinue
    if (-not $psqlCmd) {
        Write-AppLog -Level 'WARN' -Message "Telemetry enabled but psql '$psql' not found in PATH. Disabling telemetry syslog view."
        return
    }

    $pwd = Resolve-TelemetrySecret -Secret ($db.passwordSecret ?? $db.password)
    if ([string]::IsNullOrWhiteSpace($pwd)) {
        Write-AppLog -Level 'WARN' -Message "Telemetry Postgres password is not configured (telemetry.database.password or passwordSecret)."
        return
    }

    $Script:TelemetryDb = @{
        Host     = $db.host ?? 'localhost'
        Port     = [int]($db.port ?? 5432)
        Database = $db.database ?? $db.name
        Username = $db.username ?? $db.user
        Password = $pwd
        PsqlPath = $db.psqlPath ?? 'psql'
        Schema   = $db.schema ?? 'telemetry'
        PsqlCmd  = $psqlCmd.Source
    }

    # Verify connectivity once
    try {
        $pingArgs = @(
            '-h', $Script:TelemetryDb.Host,
            '-p', [string]$Script:TelemetryDb.Port,
            '-U', $Script:TelemetryDb.Username,
            '-d', $Script:TelemetryDb.Database,
            '-t', '-A', '-q', '-c', 'SELECT 1;'
        )
        $env:PGPASSWORD = $pwd
        $out = & $Script:TelemetryDb.PsqlCmd @pingArgs
        $exit = $LASTEXITCODE
        if ($exit -ne 0) { throw "psql exit $exit" }
        Write-AppLog -Message "Telemetry Postgres reachable; using it for /api/syslog."
    }
    catch {
        Write-AppLog -Level 'WARN' -Message "Telemetry Postgres connectivity failed: $($_.Exception.Message). Falling back to local syslog store."
        $Script:TelemetryDb = $null
    }
    finally {
        Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    }
}

function Invoke-TelemetryQuery {
    param(
        [Parameter(Mandatory)][string]$Sql
    )
    if (-not $Script:TelemetryDb) { throw "Telemetry DB is not configured." }
    $db = $Script:TelemetryDb
    $psql = $db.PsqlPath
    $args = @(
        '-h', $db.Host,
        '-p', [string]$db.Port,
        '-U', $db.Username,
        '-d', $db.Database,
        '-t', '-A', '-F', '|',
        '-q', '-v', 'ON_ERROR_STOP=1',
        '-c', $Sql
    )
    $env:PGPASSWORD = $db.Password
    try {
        $output = & $psql @args
        $exit = $LASTEXITCODE
    }
    finally {
        Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    }
    if ($exit -ne 0) {
        throw "psql exited with code $exit when running telemetry query."
    }
    return $output
}

function ConvertTo-SqlLiteral {
    param([string]$Value)
    if ($null -eq $Value) { return 'NULL' }
    return "'{0}'" -f ($Value.Replace("'", "''"))
}

function Get-TelemetrySyslogRows {
    [CmdletBinding()]
    param(
        [string]$Host,
        [string]$Severity,
        [string]$Since = 'PT1H',
        [int]$Skip = 0,
        [int]$Take = 200
    )
    if (-not $Script:TelemetryDb) { return @() }
    try {
        $sinceTs = (Get-Date).ToUniversalTime() - [System.Xml.XmlConvert]::ToTimeSpan($Since)
        $schema = $Script:TelemetryDb.Schema ?? 'telemetry'
        $filters = @("received_utc >= '{0}'::timestamptz" -f $sinceTs.ToString('o'))
        if ($Host)     { $filters += "source_host = {0}" -f (ConvertTo-SqlLiteral -Value $Host) }
        if ($Severity) { $filters += "severity = {0}" -f (ConvertTo-SqlLiteral -Value $Severity) }
        $where = $filters -join ' AND '
        $sql = @"
SELECT received_utc, source_host, facility, severity, message, raw_message, remote_endpoint, source
FROM $schema.syslog_recent
WHERE $where
ORDER BY received_utc DESC
LIMIT $Take OFFSET $Skip;
"@
        $rows = Invoke-TelemetryQuery -Sql $sql
        if (-not $rows) { return @() }
        $parsed = $rows | Where-Object { $_ -and ($_ -is [string]) } | ConvertFrom-Csv -Delimiter '|' -Header 'received_utc','source_host','facility','severity','message','raw_message','remote_endpoint','source'
        return $parsed | ForEach-Object {
            [pscustomobject]@{
                ts       = $_.received_utc
                host     = $_.source_host
                facility = $_.facility
                severity = $_.severity
                message  = $_.message
                tags     = $_.source
                remote   = $_.remote_endpoint
            }
        }
    }
    catch {
        Write-AppLog -Level 'WARN' -Message "Telemetry syslog query failed: $($_.Exception.Message)"
        return @()
    }
}

# --- Database helpers (SQLite by default) ---
function Initialize-Database {
    [CmdletBinding()]
    param([Parameter()][object]$Config)

    if (-not $Config) { $Config = Get-Config }
    $Script:DbKind = ($Config.database.kind ?? 'sqlite').ToLowerInvariant()

    if ($Script:DbKind -eq 'sqlite') {
        $dbPath = $Config.database.sqlitePath
        $connStr = "Data Source=$dbPath;Cache=Shared"
        try {
            $Script:DbConn = [Microsoft.Data.Sqlite.SqliteConnection]::new($connStr)
            $Script:DbConn.Open()
        } catch {
            throw "SQLite open failed: $($_.Exception.Message). Ensure Microsoft.Data.Sqlite is available and path is writable."
        }

        $cmd = $Script:DbConn.CreateCommand()
        $cmd.CommandText = @"
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS events(
  id INTEGER PRIMARY KEY,
  log TEXT NOT NULL,
  level TEXT,
  time TEXT NOT NULL,
  eventId INTEGER,
  source TEXT,
  message TEXT
);
CREATE INDEX IF NOT EXISTS ix_events_time ON events(time);
CREATE TABLE IF NOT EXISTS syslog(
  id INTEGER PRIMARY KEY,
  ts TEXT NOT NULL,
  host TEXT,
  facility TEXT,
  severity TEXT,
  message TEXT,
  tags TEXT
);
CREATE INDEX IF NOT EXISTS ix_syslog_ts ON syslog(ts);
"@
        $null = $cmd.ExecuteNonQuery()
    }
    elseif ($Script:DbKind -eq 'postgres') {
        Write-AppLog -Level 'WARN' -Message "database.kind=postgres is not wired in this build; falling back to sqlite. Use telemetry.* for Postgres-backed syslog."
        $Config.database.kind = 'sqlite'
        Initialize-Database -Config $Config
        return
    }
}

function Invoke-Db {
    param([string]$Sql, [hashtable]$Params)
    if ($Script:DbKind -ne 'sqlite') { throw "Only sqlite implemented in this drop." }
    $cmd = $Script:DbConn.CreateCommand()
    $cmd.CommandText = $Sql
    if ($Params) {
        foreach ($k in $Params.Keys) {
            $p = $cmd.CreateParameter()
            $p.ParameterName = $k
            $p.Value = $Params[$k]
            $null = $cmd.Parameters.Add($p)
        }
    }
    return $cmd
}

# --- Event log collection ---
function Collect-EventLogs {
    param([object]$Config)
    try {
        $since = (Get-Date).AddDays(-7)
        $logs = @('Application','System')
        foreach ($log in $logs) {
            $filter = @{ LogName=$log; StartTime=$since }
            $events = Get-WinEvent -FilterHashtable $filter -ErrorAction Stop |
                Select-Object -Property TimeCreated, Id, LevelDisplayName, ProviderName, Message

            foreach ($e in $events) {
                $cmd = Invoke-Db -Sql @"
INSERT INTO events(log, level, time, eventId, source, message)
VALUES (@log, @level, @time, @id, @source, @message);
"@ -Params @{
                    '@log'     = $log
                    '@level'   = ($e.LevelDisplayName ?? '')
                    '@time'    = $e.TimeCreated.ToString('o')
                    '@id'      = $e.Id
                    '@source'  = ($e.ProviderName ?? '')
                    '@message' = ($e.Message ?? '')
                }
                $null = $cmd.ExecuteNonQuery()
            }
        }

        # Retention: keep 7d
        $cut = (Get-Date).AddDays(-7).ToString('o')
        $del = Invoke-Db -Sql "DELETE FROM events WHERE time < @cut" -Params @{ '@cut' = $cut }
        $null = $del.ExecuteNonQuery()
    } catch {
        Write-AppLog -Level 'ERROR' -Message "Collect-EventLogs failed: $($_.Exception.Message)"
    }
}

function Get-EventRows {
    [CmdletBinding()]
    param(
        [ValidateSet('Application','System')]$Log,
        [string]$Level,
        [string]$Since = 'PT24H',
        [int]$Skip = 0,
        [int]$Take = 200
    )
    $sinceTs = (Get-Date) - [System.Xml.XmlConvert]::ToTimeSpan($Since)
    $sql = "SELECT log,level,time,eventId,source,message FROM events WHERE time >= @since"
    $p = @{ '@since' = $sinceTs.ToString('o') }
    if ($Log) { $sql += " AND log = @log"; $p['@log'] = $Log }
    if ($Level) { $sql += " AND level = @level"; $p['@level'] = $Level }
    $sql += " ORDER BY time DESC LIMIT @take OFFSET @skip"
    $p['@take'] = $Take; $p['@skip'] = $Skip
    $cmd = Invoke-Db -Sql $sql -Params $p
    $r = $cmd.ExecuteReader()
    $rows = @()
    while ($r.Read()) {
        $rows += [pscustomobject]@{
            log     = $r['log']
            level   = $r['level']
            time    = $r['time']
            eventId = [int]$r['eventId']
            source  = $r['source']
            message = $r['message']
        }
    }
    $r.Close()
    return $rows
}

# --- Syslog ingestion (file poll) + optional UDP 514 ---
function Parse-SyslogLine {
    param([string]$Line)
    # Simple RFC3164-ish parse; tolerant.
    $rx = '^(?<ts>\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+(?<host>\S+)\s+(?<msg>.*)$'
    $m = [regex]::Match($Line, $rx)
    if (-not $m.Success) { return $null }
    [pscustomobject]@{
        ts       = (Get-Date $m.Groups['ts'].Value) # assumes current year/timezone
        host     = $m.Groups['host'].Value
        facility = ''
        severity = ''
        message  = $m.Groups['msg'].Value
        tags     = ''
    }
}

function Ingest-SyslogFiles {
    param([object]$Config)
    try {
        $paths = @($Config.syslog.paths)
        foreach ($glob in $paths) {
            Get-ChildItem -Path $glob -File -ErrorAction SilentlyContinue | ForEach-Object {
                Get-Content -Path $_.FullName -ErrorAction SilentlyContinue | ForEach-Object {
                    $row = Parse-SyslogLine -Line $_
                    if ($null -ne $row) {
                        $cmd = Invoke-Db -Sql @"
INSERT INTO syslog(ts,host,facility,severity,message,tags)
VALUES(@ts,@host,@fac,@sev,@msg,@tags);
"@ -Params @{
                            '@ts'   = $row.ts.ToString('o')
                            '@host' = $row.host
                            '@fac'  = $row.facility
                            '@sev'  = $row.severity
                            '@msg'  = $row.message
                            '@tags' = $row.tags
                        }
                        $null = $cmd.ExecuteNonQuery()
                    }
                }
            }
        }
        # Retention (7d)
        $cut = (Get-Date).AddDays(-7).ToString('o')
        $del = Invoke-Db -Sql "DELETE FROM syslog WHERE ts < @cut" -Params @{ '@cut' = $cut }
        $null = $del.ExecuteNonQuery()
    } catch {
        Write-AppLog -Level 'ERROR' -Message "Ingest-SyslogFiles failed: $($_.Exception.Message)"
    }
}

function Start-SyslogUdp {
    param([int]$Port)
    if ($Script:SyslogUdp) { return }
    try {
        $udp = New-Object System.Net.Sockets.UdpClient($Port)
        $Script:SyslogUdp = $udp
        Start-ThreadJob -Name 'SyslogUdp' -ScriptBlock {
            param($udpHandle)
            while ($true) {
                $remote = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any,0)
                $bytes  = $udpHandle.Receive([ref]$remote)
                $line   = [System.Text.Encoding]::UTF8.GetString($bytes)
                # Post back into the DB through a simple runspace-safe file (queue) or event. For simplicity, we log only.
                # (Refinement can add a thread-safe queue drained by main loop.)
                [Console]::WriteLine("SYSLOG-UDP: " + $line)
            }
        } -ArgumentList $udp | Out-Null
        Write-AppLog -Message "Syslog UDP listening on $Port"
    } catch {
        Write-AppLog -Level 'ERROR' -Message "Syslog UDP failed to start: $($_.Exception.Message)"
    }
}

function Get-SyslogRows {
    [CmdletBinding()]
    param(
        [string]$Host,
        [string]$Severity,
        [string]$Since = 'PT1H',
        [int]$Skip = 0,
        [int]$Take = 200
    )
    if ($Script:TelemetryDb) {
        return Get-TelemetrySyslogRows -Host $Host -Severity $Severity -Since $Since -Skip $Skip -Take $Take
    }
    $sinceTs = (Get-Date) - [System.Xml.XmlConvert]::ToTimeSpan($Since)
    $sql = "SELECT ts,host,facility,severity,message,tags FROM syslog WHERE ts >= @since"
    $p = @{ '@since' = $sinceTs.ToString('o') }
    if ($Host)     { $sql += " AND host = @host"; $p['@host'] = $Host }
    if ($Severity) { $sql += " AND severity = @sev"; $p['@sev'] = $Severity }
    $sql += " ORDER BY ts DESC LIMIT @take OFFSET @skip"
    $p['@take'] = $Take; $p['@skip'] = $Skip
    $cmd = Invoke-Db -Sql $sql -Params $p
    $r = $cmd.ExecuteReader()
    $rows = @()
    while ($r.Read()) {
        $rows += [pscustomobject]@{
            ts       = $r['ts']
            host     = $r['host']
            facility = $r['facility']
            severity = $r['severity']
            message  = $r['message']
            tags     = $r['tags']
        }
    }
    $r.Close()
    return $rows
}

# --- Router provider model ---
class RouterClient {
    [string]$IPAddress
    [string]$Hostname
    [string]$MAC
    [string]$Iface
}

class RouterProviderBase {
    [string] GetName() { return 'Base' }
    [bool] TestConnection() { return $false }
    [System.Collections.Generic.List[RouterClient]] GetClients() {
        return [System.Collections.Generic.List[RouterClient]]::new()
    }
}

class AsuswrtSshProvider : RouterProviderBase {
    [string]$Host; [int]$Port; [string]$User; [int]$TimeoutSec = 6
    AsuswrtSshProvider([string]$host,[int]$port,[string]$user){
        $this.Host=$host; $this.Port=$port; $this.User=$user
    }
    [string] GetName(){ return 'AsuswrtSsh' }
    hidden [string[]] Exec([string]$cmd) {
        # Uses built-in ssh.exe (no extra module). Requires trust/on-first-use known_hosts acceptance.
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'ssh'
        $psi.Arguments = "-o StrictHostKeyChecking=no -o ConnectTimeout=$($this.TimeoutSec) -p $($this.Port) $($this.User)@$($this.Host) $cmd"
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.UseShellExecute = $false
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.WaitForExit(7000) | Out-Null
        $out = $p.StandardOutput.ReadToEnd().Split("`n",[System.StringSplitOptions]::RemoveEmptyEntries)
        return $out
    }
    [bool] TestConnection(){
        try { $null = $this.Exec('echo ok'); return $true } catch { return $false }
    }
    [System.Collections.Generic.List[RouterClient]] GetClients(){
        $list = [System.Collections.Generic.List[RouterClient]]::new()
        # Prefer dnsmasq leases; fallback to 'ip neigh'
        $lines = $this.Exec("cat /var/lib/misc/dnsmasq.leases 2>/dev/null || true")
        foreach ($ln in $lines) {
            # ts MAC IP hostname id
            $parts = $ln -split '\s+'
            if ($parts.Count -ge 4) {
                $c = [RouterClient]::new()
                $c.MAC = $parts[1]; $c.IPAddress = $parts[2]; $c.Hostname = $parts[3]; $c.Iface = ''
                $list.Add($c)
            }
        }
        if ($list.Count -eq 0) {
            $n = $this.Exec("ip neigh show")
            foreach ($ln in $n) {
                # 192.168.1.10 dev br0 lladdr 11:22:33:44:55:66 REACHABLE
                $m = [regex]::Match($ln, '^(?<ip>\S+)\s+dev\s+\S+\s+lladdr\s+(?<mac>\S+)')
                if ($m.Success) {
                    $c = [RouterClient]::new()
                    $c.IPAddress = $m.Groups['ip'].Value
                    $c.MAC       = $m.Groups['mac'].Value
                    $c.Hostname  = ''
                    $list.Add($c)
                }
            }
        }
        return $list
    }
}

class GenericSnmpProvider : RouterProviderBase {
    [string]$Host; [int]$Port = 161; [string]$Community = 'public'
    GenericSnmpProvider([string]$host){ $this.Host=$host }
    [string] GetName(){ return 'GenericSnmp' }
    [bool] TestConnection(){
        # Best-effort: require snmpwalk.exe in PATH
        return [bool](Get-Command snmpwalk -ErrorAction SilentlyContinue)
    }
    [System.Collections.Generic.List[RouterClient]] GetClients(){
        if (-not (Get-Command snmpwalk -ErrorAction SilentlyContinue)) {
            throw "snmpwalk.exe not found. Install net-snmp tools or switch provider to AsuswrtSsh."
        }
        $list = [System.Collections.Generic.List[RouterClient]]::new()
        # Very rough ARP table OID; varies by device. This is intentionally minimal.
        $arp = snmpwalk -v2c -c $this.Community $this.Host 1.3.6.1.2.1.4.22.1.2 2>$null
        foreach ($ln in $arp) {
            # ... ip.x.x.x = Hex-STRING: 11 22 33 44 55 66
            $m = [regex]::Match($ln, 'ip\.(?<ip>\d+\.\d+\.\d+\.\d+).*?:\s+Hex-STRING:\s+(?<hex>.+)$')
            if ($m.Success) {
                $ip = $m.Groups['ip'].Value
                $hex = ($m.Groups['hex'].Value -replace '\s+','').ToUpper()
                $mac = ($hex -split '([0-9A-F]{2})' | Where-Object { $_ -match '^[0-9A-F]{2}$' }) -join ':'
                $c = [RouterClient]::new(); $c.IPAddress=$ip; $c.MAC=$mac
                $list.Add($c)
            }
        }
        return $list
    }
}

function Get-RouterClients {
    [CmdletBinding()]
    param([object]$Config)
    if (-not $Config) { $Config = Get-Config }
    $prov = ($Config.router.provider ?? 'AsuswrtSsh')
    if ($prov -ieq 'AsuswrtSsh') {
        $p = [AsuswrtSshProvider]::new($Config.router.host, [int]$Config.router.port, $Config.router.user)
    } elseif ($prov -ieq 'GenericSnmp') {
        $p = [GenericSnmpProvider]::new($Config.router.host)
    } else {
        throw "Unknown router provider '$prov'"
    }
    if (-not ($p.TestConnection())) {
        throw "Router provider '$($p.GetName())' failed connection test."
    }
    return $p.GetClients()
}

# --- Live metrics (polled on request; SSE stream for UI) ---
function Get-LiveMetrics {
    $cpu = [math]::Round((Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue,1)
    $mem = Get-CimInstance Win32_OperatingSystem
    $used = ($mem.TotalVisibleMemorySize - $mem.FreePhysicalMemory)/1KB
    $total = $mem.TotalVisibleMemorySize/1KB
    $memPct = [math]::Round(($used/$total)*100,1)

    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
      Select-Object DeviceID, @{n='UsedGB';e={[math]::Round(($_.Size-$_.FreeSpace)/1GB,1)}}, @{n='TotalGB';e={[math]::Round(($_.Size)/1GB,1)}}

    $tcp  = Get-NetTCPConnection -ErrorAction SilentlyContinue
    [pscustomobject]@{
        ts       = (Get-Date).ToString('o')
        cpuPct   = $cpu
        memPct   = $memPct
        disks    = $disk
        tcpCount = ($tcp | Measure-Object).Count
    }
}

function Write-SseEvent {
    param([System.IO.StreamWriter]$Writer,[string]$Event,[string]$Data)
    $Writer.WriteLine("event: $Event")
    $Writer.WriteLine("data: $Data")
    $Writer.WriteLine()
    $Writer.Flush()
}

# --- OpenAI advisory ---
function Invoke-AIAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Lines,
        [Parameter()][object]$Config
    )
    if (-not $Config) { $Config = Get-Config }
    if ([string]::IsNullOrWhiteSpace($Config.ai.apiKey)) {
        throw "OPENAI_API_KEY not set in env nor config."
    }

    # Cost-controls: dedupe + cap 50
    $unique = $Lines | Where-Object { $_ } | Select-Object -Unique | Select-Object -First 50

    # Redaction (very conservative)
    $redacted = $unique | ForEach-Object {
        $_ -replace '\b\d{1,3}(\.\d{1,3}){3}\b','<IP>' `
           -replace '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b','<EMAIL>' `
           -replace '(?<=\\|/|^)[A-Za-z][A-Za-z0-9._-]{2,}(?=\\|/|$)','<USER>'
    }

    $prompt = @"
You are a seasoned SRE diagnosing Windows/application errors and syslogs.
Given the following log lines, provide:
1) Root-cause hypotheses (bullet list)
2) Actionable remediation steps (config or commands)
3) Confidence (low/med/high)
4) Any signature/pattern match that informed you.

Logs:
- $(($redacted -join "`n- "))
"@

    $body = @{
        model = "gpt-4o-mini"
        messages = @(@{ role="user"; content=$prompt })
        temperature = 0.2
        max_tokens = 500
    } | ConvertTo-Json -Depth 6

    $headers = @{
        "Authorization"="Bearer $($Config.ai.apiKey)"
        "Content-Type"="application/json"
    }
    $resp = Invoke-RestMethod -Method Post -Uri "https://api.openai.com/v1/chat/completions" -Headers $headers -Body $body -TimeoutSec 30
    return $resp.choices[0].message.content
}

# --- Web server (Pode) ---
function Start-SystemDashboard {
    [CmdletBinding()]
    param([object]$Config)

    if (-not $Config) { $Config = Get-Config }
    Initialize-Database -Config $Config
    Initialize-TelemetryContext -Config $Config

    $bind = ($Config.http.bind ?? '127.0.0.1')
    $port = [int]($Config.http.port ?? 5000)

    Start-PodeServer -ScriptBlock {
        param($Config,$WebRoot)

        Add-PodeEndpoint -Address $Config.http.bind -Port $Config.http.port -Protocol Http

        # Security headers (basic)
        Add-PodeResponseHeader -Name 'X-Content-Type-Options' -Value 'nosniff'
        Add-PodeResponseHeader -Name 'Referrer-Policy' -Value 'no-referrer'
        Add-PodeResponseHeader -Name 'Content-Security-Policy' -Value "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self'"

        # Static files
        Add-PodeStaticRoute -Path '/' -Source (Join-Path $WebRoot 'index.html')
        Add-PodeStaticRoute -Path '/styles.css' -Source (Join-Path $WebRoot 'styles.css')
        Add-PodeStaticRoute -Path '/app.js'     -Source (Join-Path $WebRoot 'app.js')

        # Health
        Add-PodeRoute -Method Get -Path '/healthz' -ScriptBlock {
            Write-PodeJsonResponse -Value @{ ok=$true; time=(Get-Date).ToString('o') }
        }
        Add-PodeRoute -Method Get -Path '/readyz' -ScriptBlock {
            $ok = $true
            try { $null = Invoke-Db -Sql "SELECT 1" -Params @{} | ForEach-Object { $_.ExecuteScalar() } } catch { $ok=$false }
            Write-PodeJsonResponse -Value @{ ok=$ok }
        }

        # API: events
        Add-PodeRoute -Method Get -Path '/api/events' -ScriptBlock {
            $log   = Get-PodeRequestQuery -Name 'log'
            $lvl   = Get-PodeRequestQuery -Name 'level'
            $since = (Get-PodeRequestQuery -Name 'since','PT24H')
            $skip  = [int](Get-PodeRequestQuery -Name 'skip','0')
            $take  = [int](Get-PodeRequestQuery -Name 'take','200')
            $rows = Get-EventRows -Log $log -Level $lvl -Since $since -Skip $skip -Take $take
            Write-PodeJsonResponse -Value $rows
        }

        # API: metrics (snapshot)
        Add-PodeRoute -Method Get -Path '/api/metrics' -ScriptBlock {
            Write-PodeJsonResponse -Value (Get-LiveMetrics)
        }

        # Streaming: SSE
        Add-PodeRoute -Method Get -Path '/stream/metrics' -ScriptBlock {
            Set-PodeResponseHeader -Name 'Content-Type' -Value 'text/event-stream'
            Set-PodeResponseHeader -Name 'Cache-Control' -Value 'no-cache'
            $w = New-Object System.IO.StreamWriter($WebEvent.Response.Stream)
            for ($i=0; $i -lt 1200; $i++) { # ~40min at 2s interval
                $payload = (Get-LiveMetrics | ConvertTo-Json -Compress)
                Write-SseEvent -Writer $w -Event 'metrics' -Data $payload
                Start-Sleep -Seconds 2
            }
        }

        # API: router clients
        Add-PodeRoute -Method Get -Path '/api/router/clients' -ScriptBlock {
            try {
                $clients = Get-RouterClients -Config $Config
                Write-PodeJsonResponse -Value $clients
            } catch {
                Set-PodeResponseStatus -Code 502
                Write-PodeJsonResponse -Value @{ error=$_.Exception.Message }
            }
        }

        # API: syslog
        Add-PodeRoute -Method Get -Path '/api/syslog' -ScriptBlock {
            $host  = Get-PodeRequestQuery -Name 'host'
            $sev   = Get-PodeRequestQuery -Name 'severity'
            $since = (Get-PodeRequestQuery -Name 'since','PT1H')
            $skip  = [int](Get-PodeRequestQuery -Name 'skip','0')
            $take  = [int](Get-PodeRequestQuery -Name 'take','200')
            Write-PodeJsonResponse -Value (Get-SyslogRows -Host $host -Severity $sev -Since $since -Skip $skip -Take $take)
        }

        # API: AI assess (requires X-API-Key)
        Add-PodeRoute -Method Post -Path '/api/ai/assess' -ScriptBlock {
            $key = (Get-PodeRequestHeader -Name 'X-API-Key')
            if ([string]::IsNullOrWhiteSpace($key) -or $key -ne $Config.ai.apiKey) {
                Set-PodeResponseStatus -Code 401
                Write-PodeJsonResponse -Value @{ error="Unauthorized: missing/invalid X-API-Key" }
                return
            }
            $body = Read-PodeJsonRequest
            $lines = @($body.lines)
            if (-not $lines -or $lines.Count -eq 0) {
                Set-PodeResponseStatus -Code 400
                Write-PodeJsonResponse -Value @{ error="Body must include 'lines': string[]" }
                return
            }
            try {
                $advice = Invoke-AIAnalysis -Lines $lines -Config $Config
                Write-PodeJsonResponse -Value @{ advice=$advice }
            } catch {
                Set-PodeResponseStatus -Code 502
                Write-PodeJsonResponse -Value @{ error=$_.Exception.Message }
            }
        }

    } -ArgumentList $Config, $Script:WebRoot | Out-Null

    Write-AppLog -Message "Server started on http://$bind:$port"
    # Background loops (simple timers)
    Register-PodeSchedule -Name 'events-collect' -Cron '* */10 * * * *' -ScriptBlock { Collect-EventLogs -Config $Config } | Out-Null  # every 10 minutes
    $useTelemetrySyslog = ($Script:TelemetryDb -ne $null)
    if (-not $useTelemetrySyslog) {
        Register-PodeSchedule -Name 'syslog-poll'    -Cron '*/30 * * * * *' -ScriptBlock { Ingest-SyslogFiles -Config $Config } | Out-Null # every 30 sec
        if ($Config.syslog.enableUdp -eq $true) { Start-SyslogUdp -Port ([int]$Config.syslog.udpPort) }
    }
    else {
        Write-AppLog -Message "Syslog API backed by telemetry Postgres (telemetry.enabled=true); local ingestion disabled."
    }

    Wait-PodeServer
}

function Stop-SystemDashboard {
    try { Stop-PodeServer } catch {}
    try { if ($Script:DbConn) { $Script:DbConn.Close(); $Script:DbConn.Dispose() } } catch {}
    try { if ($Script:SyslogUdp) { $Script:SyslogUdp.Close() } } catch {}
}

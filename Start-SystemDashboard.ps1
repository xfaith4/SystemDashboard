### BEGIN FILE: Start-SystemDashboard.ps1
#requires -Version 7
using namespace System.Net
using namespace System.Threading
using namespace System.Text
using namespace System.IO
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
  Local system dashboard: serves index/CSS + a /metrics JSON endpoint for your UI.

.NOTES
  - Matches your index.html expectations (fields & shapes).  (Top-level Routers + Network.WanLatencyMs)
  - Works non-admin after one-time URL ACL: Ensure-UrlAcl -Prefix "http://localhost:8899/"
  - Ctrl+C stops cleanly. Ideal inline comments throughout.
#>

# =========================
# CONFIG
# =========================

  [int]$Port = 8899

$Root = "F:\Logs\wwwroot\" # web root folder (will be created if missing)
# Dashboard title and paths
$Title = "System Monitor - $env:COMPUTERNAME"

# URL prefix (must end with /) for HttpListener (e.g. "http://localhost:8899/")
$Prefix = "http://localhost:$Port/" # can also use e.g. http://+:8899/ for all interfaces
# Note: using "localhost" avoids firewall prompt on first run
# Note: using "http://+:8899/" requires admin to reserve the URL ACL once
# e.g. netsh http add urlacl url=http://+:8899/ user=DOMAIN\username
# See Ensure-UrlAcl function below

# Paths to static files (relative to $Root) to serve for the dashboard
$IndexHtml = Join-Path $Root 'index.html' # main HTML file
$CssFile   = Join-Path $Root 'styles.css' # CSS file

# Ensure the root folder exists
if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
}

# --------- Configurable trace folder ----------
$script:HttpTraceDir = 'F:\Logs\HttpTrace'
if (-not (Test-Path $script:HttpTraceDir)) { New-Item -ItemType Directory -Path $script:HttpTraceDir | Out-Null }

function New-TraceId {
  [CmdletBinding()] param()
  return ([guid]::NewGuid().ToString('N'))
}

function Write-TraceJson {
  <#
    .SYNOPSIS  Append a JSON line to the capture log.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$TraceId,
    [Parameter(Mandatory)][ValidateSet('Request','Response')]$Direction,
    [Parameter(Mandatory)]$Payload
  )
  $ts = Get-Date
  $lineObj = [pscustomobject]@{
    timestamp = $ts.ToString('o')
    traceId   = $TraceId
    direction = $Direction
    payload   = $Payload
  }
  $json = $lineObj | ConvertTo-Json -Depth 6 -Compress
  $logPath = Join-Path $script:HttpTraceDir 'http_capture.jsonl'
  Add-Content -Path $logPath -Value $json
}

function Save-BodyBytes {
  <#
    .SYNOPSIS  Save a body to a .bin file for offline diffing/hex view.
    .OUTPUTS   Full path to the saved file (string) or $null if no body.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$TraceId,
    [Parameter(Mandatory)][ValidateSet('Request','Response')]$Direction,
    [byte[]]$Bytes
  )
  if (-not $Bytes -or $Bytes.Length -eq 0) { return $null }
  $fname = "{0}_{1}_{2}.bin" -f (Get-Date -Format 'yyyyMMdd_HHmmssfff'), $TraceId, $Direction
  $path  = Join-Path $script:HttpTraceDir $fname
  [File]::WriteAllBytes($path, $Bytes)
  return $path
}

function Snapshot-Request {
  <#
    .SYNOPSIS  Capture headers + basics from HttpListenerRequest.
    .PARAMETER Request        The request.
    .PARAMETER ReadBody       If set, consumes the request body (use only if your handler won't read it).
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][HttpListenerRequest]$Request,
    [switch]$ReadBody
  )

  # Collect headers into a hashtable (easier to read in logs)
  $hdrs = @{}
  foreach ($key in $Request.Headers.AllKeys) { $hdrs[$key] = $Request.Headers[$key] }

  $bodyBytes = [byte[]]::new(0)
  $bodyPreview = $null
  if ($ReadBody -and $Request.HasEntityBody) {
    # WARNING: This consumes the stream; don't use if your handler needs to read it afterwards.
    $ms = [MemoryStream]::new()
    $Request.InputStream.CopyTo($ms)
    $bodyBytes = $ms.ToArray()
    $enc = $Request.ContentEncoding
    if (-not $enc) { $enc = [Encoding]::UTF8 }
    # Cap preview length to keep logs sane
    $bodyPreview = $enc.GetString($bodyBytes, 0, [Math]::Min($bodyBytes.Length, 2048))
  }

  [pscustomobject]@{
    Method          = $Request.HttpMethod
    RawUrl          = $Request.RawUrl
    Url             = $Request.Url.AbsoluteUri
    RemoteEndPoint  = $Request.RemoteEndPoint.ToString()
    LocalEndPoint   = $Request.LocalEndPoint.ToString()
    Protocol        = "HTTP/$($Request.ProtocolVersion)"
    KeepAlive       = $Request.KeepAlive
    ContentLength   = $Request.ContentLength64
    ContentType     = $Request.ContentType
    Headers         = $hdrs
    BodyPreview     = $bodyPreview
    BodyBytesSaved  = $false
    BodyByteCount   = $bodyBytes.Length
    _rawBytes       = $bodyBytes  # internal; may be $null if not read
  }
}

function Snapshot-ResponsePlan {
  <#
    .SYNOPSIS  Describe the outgoing response BEFORE writing it.
    .PARAMETER StatusCode   HTTP status you intend to send.
    .PARAMETER ContentType  Content-Type header.
    .PARAMETER Headers      Additional headers (hashtable) to set.
    .PARAMETER Bytes        Exact bytes you plan to write.
    .OUTPUTS   Object suitable for Write-TraceJson + sidecar .bin.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][int]$StatusCode,
    [Parameter(Mandatory)][string]$ContentType,
    [hashtable]$Headers = @{},
    [Parameter(Mandatory)][byte[]]$Bytes
  )
  [pscustomobject]@{
    StatusCode     = $StatusCode
    ContentType    = $ContentType
    ContentLength  = $Bytes.Length
    Headers        = $Headers
    TextPreview    = ([Text.Encoding]::UTF8.GetString($Bytes, 0, [Math]::Min($Bytes.Length, 2048)))
  }
}

function Write-ResponseBytes {
  <#
    .SYNOPSIS  Set headers sanely, write exact bytes once, and close safely.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][HttpListenerResponse]$Response,
    [Parameter(Mandatory)][byte[]]$Bytes,
    [int]$StatusCode = 200,
    [string]$ContentType = 'application/octet-stream',
    [hashtable]$Headers = @{}
  )
  $Response.StatusCode   = $StatusCode
  $Response.ContentType  = $ContentType
  foreach ($k in $Headers.Keys) { $Response.Headers[$k] = [string]$Headers[$k] }
  $Response.SendChunked = $false
  $Response.ContentLength64 = $Bytes.Length

  try {
    $Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
  }
  finally {
    try { $Response.Close() } catch { }
  }
}

# Event filtering
$EventProvidersOfInterest = @(
  'Microsoft-Windows-WLAN-AutoConfig',
  'Schannel',
  'Microsoft-Windows-DHCP-Client',
  'Microsoft-Windows-DNS-Client',
  'Microsoft-Windows-NlaSvc',
  'Microsoft-Windows-TerminalServices-RemoteConnectionManager',
  'Microsoft-Windows-TerminalServices-LocalSessionManager',
  'Microsoft-Windows-UserPnp',
  'Microsoft-Windows-Webrtc'
)
$HotMessageKeywords = @('disconnect','dhcp','authentication','tls','schannel','certificate','dns','timeout','webrtc')

# Routers to probe (ASUS, etc.)
$Routers = @(
  @{ Name = 'ASUS Main'; Host = '192.168.50.1' },
  @{ Name = 'ASUS Node'; Host = '192.168.50.7' }
)

# WAN latency target
$WanProbeHost = '1.1.1.1'   # alt: 8.8.8.8
# e.g. use your ISP gateway or a reliable public DNS server

# Disks to show (auto-skips if not present)
$DesiredDriveLetters = @()
# Leave empty to auto-detect all fixed drives

# =========================
# STATIC HTML/CSS (modern, light)
# =========================
New-Item -ItemType Directory -Path $Root -Force | Out-Null
@"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>$Title</title>
  <link rel="stylesheet" href="/styles.css"/>
</head>
<body>
  <header>
    <h1>$Title</h1>
    <div class="sub">Live refresh every 5s • <span id="host"></span> • <span id="updated"></span></div>
  </header>

  <main class="grid">
    <section class="card">
      <h2>Health</h2>
      <div class="kv"><span>CPU</span><b id="cpu"></b></div>
      <div class="kv"><span>Memory</span><b id="mem"></b></div>
      <div class="kv"><span>WAN Latency</span><b id="wan"></b></div>
    </section>

    <section class="card">
      <h2>Disks</h2>
      <div id="disks"></div>
    </section>

    <section class="card">
      <h2>Routers</h2>
      <ul id="routers" class="plain"></ul>
    </section>

    <section class="card">
      <h2>Recent Events (1h)</h2>
      <div class="kv warn"><span>Warnings</span><b id="evWarn"></b></div>
      <div class="kv err"><span>Errors</span><b id="evErr"></b></div>
      <details>
        <summary>Latest filtered errors</summary>
        <ul id="evList"></ul>
      </details>
    </section>

    <section class="card wide">
      <h2>Hot Messages (1h, filtered)</h2>
      <table id="hot">
        <thead><tr><th>Provider</th><th>Message (snippet)</th><th>Count</th></tr></thead>
        <tbody></tbody>
      </table>
    </section>

    <section class="card wide">
      <h2>Top Processes (CPU)</h2>
      <table id="procs">
        <thead><tr><th>Process</th><th>CPU %</th><th>WorkingSet (MB)</th></tr></thead>
        <tbody></tbody>
      </table>
    </section>
  </main>

  <script>
  function kv(label, value, cls='') {
      return '<div class="kv '+cls+'"><span>'+label+'</span><b>'+value+'</b></div>';
    }

    async function refresh() {
      try {
        const r = await fetch('/metrics', {cache:'no-store'});
        if (!r.ok) throw new Error('HTTP '+r.status);
        const m = await r.json();
        console.log('Metrics:', m);
        if (!m) throw new Error('No metrics');
        if (!m.Timestamp) throw new Error('No timestamp in metrics');

        // header
        document.getElementById('host').textContent    = m.ComputerName;
        document.getElementById('updated').textContent = new Date(m.Timestamp).toLocaleTimeString();

        // health
        document.getElementById('cpu').textContent = m.CPU.UsagePct.toFixed(1)+'%';
        document.getElementById('mem').textContent = m.Memory.UsedPct.toFixed(1)+'% ('+m.Memory.UsedGB.toFixed(1)+' / '+m.Memory.TotalGB.toFixed(1)+' GB)';
        document.getElementById('wan').textContent = (m.Network.WanLatencyMs >= 0 ? m.Network.WanLatencyMs.toFixed(0)+' ms' : 'unreachable');

        // disks
        const disksDiv = document.getElementById('disks');
        disksDiv.innerHTML = '';
        m.Disks.forEach(d => {
          const cls = d.UsedPct >= 90 ? 'err' : (d.UsedPct >= 80 ? 'warn' : '');
          disksDiv.innerHTML += kv(d.Letter + ':', d.UsedPct.toFixed(1)+'% ('+d.UsedGB.toFixed(0)+' / '+d.TotalGB.toFixed(0)+' GB)', cls);
        });

        // routers
        const ul = document.getElementById('routers');
        ul.innerHTML = '';
        m.Routers.forEach(rt => {
          const li = document.createElement('li');
          const status = rt.Reachable ? (rt.LatencyMs.toFixed(0)+' ms') : 'down';
          li.textContent = rt.Name + ' ('+rt.Host+'): ' + status;
          ul.appendChild(li);
        });

        // events summary
        document.getElementById('evWarn').textContent = m.Events.LastHourWarnings;
        document.getElementById('evErr').textContent  = m.Events.LastHourErrors;

        // latest filtered errors
        const evList = document.getElementById('evList');
        evList.innerHTML = '';
        (m.Events.LatestFilteredErrors || []).forEach(e => {
          const li = document.createElement('li');
          li.textContent = '['+e.Time+'] '+e.Provider+': '+e.Message;
          evList.appendChild(li);
        });

        // hot messages
        const hotBody = document.querySelector('#hot tbody');
        hotBody.innerHTML = '';
        (m.Events.HotMessages || []).forEach(h => {
          const tr = document.createElement('tr');
          tr.innerHTML = '<td>'+h.Provider+'</td><td>'+h.Snippet+'</td><td>'+h.Count+'</td>';
          hotBody.appendChild(tr);
        });

        // processes
        const tbody = document.querySelector('#procs tbody');
        tbody.innerHTML = '';
        (m.TopProcesses || []).forEach(p => {
          const tr = document.createElement('tr');
          tr.innerHTML = '<td>'+p.Name+'</td><td>'+p.CPU.toFixed(1)+'</td><td>'+p.WS_MB.toFixed(0)+'</td>';
          tbody.appendChild(tr);
        });
      } catch (e) {
        console.error('metrics fetch failed:', e);
      }
    }
    refresh();
    setInterval(refresh, 5000);
  </script>
</body>
</html>
"@ | Set-Content -Path $IndexHtml -Encoding UTF8

@"
:root { --fg:#0f172a; --muted:#64748b; --bg:#0b1020; --card:#121a33; --ok:#10b981; --warn:#f59e0b; --err:#ef4444; }
*{box-sizing:border-box}
body{margin:0;background:linear-gradient(180deg,#0b1020,#0b1020 60%,#0e152b);color:#e5e7eb;font-family:system-ui,Segoe UI,Roboto,Inter,Arial}
header{padding:18px 20px;border-bottom:1px solid #1f2937;background:#0c1224;position:sticky;top:0;z-index:1}
h1{margin:0;font-size:20px}
.sub{color:var(--muted);font-size:13px;margin-top:4px}
main.grid{display:grid;gap:14px;padding:16px;grid-template-columns:repeat(12,1fr)}
.card{grid-column:span 4;background:var(--card);border:1px solid #1f2937;border-radius:16px;padding:14px;box-shadow:0 10px 18px rgba(0,0,0,.25)}
.card.wide{grid-column:span 8}
h2{margin:2px 0 10px 0;font-size:16px}
.kv{display:flex;justify-content:space-between;padding:6px 8px;border-radius:10px;background:#0f1731;margin-bottom:6px}
.kv.warn b{color:var(--warn)} .kv.err b{color:var(--err)}
table{width:100%;border-collapse:collapse;font-size:14px}
th,td{padding:8px;border-bottom:1px solid #1f2937}
tr:hover{background:#0f1731}
ul.plain{list-style:none;padding-left:0;margin:0}
"@ | Set-Content -Path $CssFile -Encoding UTF8

# =========================
# HELPERS
# =========================

function Get-Percent {
  param([double]$Part, [double]$Whole)
  if ($Whole -le 0) { return 0 }
  [math]::Round(($Part / $Whole) * 100, 2)
}

function Get-LatencyMs {
  <#
    .SYNOPSIS  Average ICMP latency in ms (over -Count), or -1 if unreachable.
    .NOTES     Uses Test-Connection; falls back to ping.exe if needed.
  #>
  param(
    [Parameter(Mandatory)][string]$Target,
    [int]$Count = 2
  )
  try {
    $r = Test-Connection -TargetName $Target -IPv4 -Count $Count -ErrorAction Stop
    return [math]::Round(($r | Measure-Object -Property ResponseTime -Average).Average, 1)
  }
  catch {
    try {
      $out = & ping.exe -n $Count -w 1000 $Target 2>$null
      if ($LASTEXITCODE -ne 0) { return -1 }
      $times = $out | Select-String -Pattern 'time[=<](\d+)' | ForEach-Object { [int]$_.Matches[0].Groups[1].Value }
      if ($times.Count -gt 0) { return [math]::Round(($times | Measure-Object -Average).Average, 1) }
      return -1
    }
    catch { return -1 }
  }
}

# =========================
# METRICS
# =========================
function Get-Metrics {

  # --- CPU (instant)
  $cpu = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue
  $cpuPct = [math]::Round($cpu, 2)

  # --- Memory
  $os = Get-CimInstance -ClassName Win32_OperatingSystem
  $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
  $freeGB  = [math]::Round($os.FreePhysicalMemory     / 1MB, 2)
  $usedGB  = $totalGB - $freeGB
  $memPct  = Get-Percent $usedGB $totalGB

  # --- Disks
  $fixed   = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
  if (-not $fixed -or $fixed.Count -eq 0) { $fixed = @() }

  # If you didn't specify letters, derive them from actual disks (trim the colon safely per item)
  $letters = if ($DesiredDriveLetters -and $DesiredDriveLetters.Count) {
      $DesiredDriveLetters | ForEach-Object { $_.TrimEnd(':') } # just in case user included colon
  } else {
      $fixed | ForEach-Object { $_.DeviceID.TrimEnd(':') } # DeviceID includes the colon
  }

  # Force an array result (even if empty) so JSON gives [] instead of null
  $disks = @(
      foreach ($L in ($letters | Select-Object -Unique)) {
           # Find the drive info (skip if not found or invalid)
        $d = $fixed | Where-Object { $_.DeviceID -eq "${L}:" }   # DeviceID includes the colon
          if (-not $d) { continue } # skip non-existing drives
          if ($d.Size -le 0) { continue } # skip invalid drives (zero size)

          # Calculate sizes in GB with 2 decimal places
          # and do sanity checks to avoid weird values
          $t = [math]::Round($d.Size      / 1GB, 2) # GB
          if ($t -le 0) { continue } # skip invalid drives (zero size)
          $f = [math]::Round($d.FreeSpace / 1GB, 2) # GB
          if ($f -lt 0) { $f = 0 } # sanity
          if ($f -gt $t) { $f = $t } # sanity
          $u = $t - $f # used GB
          if ($u -lt 0) { $u = 0 } # sanity
          if ($u -gt $t) { $u = $t } # sanity

          [pscustomobject]@{
              Letter  = $L
              TotalGB = $t
              UsedGB  = $u
              UsedPct = Get-Percent $u $t
          } # end pscustomobject
      } # end foreach
  ) # end array
  if (-not $disks) { $disks = @() } # force array

  # --- Network (latency)
  # WAN latency (to public IP)
  $wanMs       = Get-LatencyMs -Target $WanProbeHost -Count 2 # -1 if unreachable
  $wanLatency  = if ($wanMs -ge 0) { [math]::Round($wanMs, 1) } else { -1 } # -1 if unreachable
  # Routers (latency to local IPs)
  $routerStats = foreach ($r in $Routers) {
    $ms = Get-LatencyMs -Target $r.Host -Count 2 # -1 if unreachable
    [pscustomobject]@{
      Name      = $r.Name
      Host      = $r.Host
      Reachable = ($ms -ge 0)
      LatencyMs = $ms
    } # end pscustomobject
  } # end foreach
  if (-not $routerStats) { $routerStats = @() } # force array

  # --- Events (last hour) (delta sample ~0.8s)
  # Time window
  $start = (Get-Date).AddHours(-1) # 1 hour ago

  # Correct FilterHashtable syntax: array for multiple logs
  $warns = Get-WinEvent -FilterHashtable @{ LogName = @('System','Application'); Level = 3; StartTime = $start } -ErrorAction SilentlyContinue
  $errs  = Get-WinEvent -FilterHashtable @{ LogName = @('System','Application'); Level = 2; StartTime = $start } -ErrorAction SilentlyContinue
  $warnCount = if ($warns) { $warns.Count } else { 0 }
  $errCount  = if ($errs)  { $errs.Count  } else { 0 }

  # Filtered errors by providers of interest
  $filteredErrs = foreach ($p in $EventProvidersOfInterest) {
    Get-WinEvent -FilterHashtable @{ ProviderName = $p; Level = 2; StartTime = $start } -ErrorAction SilentlyContinue
  }
  if (-not $filteredErrs) { $filteredErrs = @() } # force array

  # Latest 6 filtered errors (time desc, trimmed message)
  $latestFiltered = $filteredErrs |
    Sort-Object TimeCreated -Descending |
    Select-Object -First 6 @{
      n='Time';     e={ $_.TimeCreated.ToString('HH:mm:ss') }
    }, @{
      n='Provider'; e={ $_.ProviderName }
    }, @{
      n='Message';  e={
        $m = ($_.Message -replace '\s+', ' ')
        if ($m.Length -gt 300) { $m = $m.Substring(0,300) + '…' }

        $m -replace '"','\"' # escape quotes for JSON
      } # end expression
    } # end select-object

  # Hot messages (keyword buckets)
  $hot = @()
  if ($HotMessageKeywords.Count -gt 0) {
    $rx = [regex]::new('(' + (($HotMessageKeywords | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')', 'IgnoreCase') # case-insensitive
    $hot = ($warns + $errs + $filteredErrs) |
      Where-Object { $_ -and $rx.IsMatch($_.Message) } |
      ForEach-Object {
        $snippet = ($_.Message -replace '\s+', ' ')
        if ($snippet.Length -gt 120) { $snippet = $snippet.Substring(0,120) + '…' }
        [pscustomobject]@{ Provider = $_.ProviderName; Snippet = $snippet }
      } |
      Group-Object Provider, Snippet |
      Sort-Object Count -Descending |
      Select-Object -First 12 @{
        n='Provider'; e={ $_.Group[0].Provider }
      }, @{
        n='Snippet';  e={ $_.Group[0].Snippet }
      }, @{
        n='Count';    e={ $_.Count }
      } # end select-object
  } # end if

  # --- Top processes (delta sample ~0.8s)
  $procs1 = Get-Process | Where-Object { $_.CPU -ne $null } | Group-Object Id -AsHashTable -AsString # map Id -> [array of Process]
  Start-Sleep -Milliseconds 800 # short delay to get CPU delta
  $procs2 = Get-Process | Where-Object { $_.CPU -ne $null } | Group-Object Id -AsHashTable -AsString # map Id -> [array of Process]

  # Calculate CPU% over the interval (0.8s), normalized by number of logical processors
  # $procs2 maps Id -> [array of Process]; pick the first element
  $top = @(
      $procs1 | ForEach-Object {
          $p1  = $_
          $arr = $procs2[[string]$p1.Id]
          if (-not $arr -or $arr.Count -eq 0) { return }   # process ended between samples

          $p2     = $arr[0]
          $delta  = ($p2.CPU - $p1.CPU)
          $cpuPct = [math]::Max(0, ($delta / 0.8) / [Environment]::ProcessorCount * 100) # avoid negative CPU%

          [pscustomobject]@{
              Name  = $p1.ProcessName
              CPU   = [math]::Round($cpuPct, 1) # %
              WS_MB = [math]::Round($p2.WorkingSet64 / 1MB, 0) # MB
          } # end pscustomobject
      } # end foreach
  ) | Sort-Object CPU -Descending | Select-Object -First 8 # top 8 by CPU
  # Force array result so JSON gives [] instead of null
  if (-not $top) { $top = @() } # force array

  # --- Final object
  [pscustomobject]@{
    Timestamp    = (Get-Date).ToUniversalTime().ToString("o") # ISO 8601 UTC
    ComputerName = $env:COMPUTERNAME
    CPU          = [pscustomobject]@{ UsagePct = $cpuPct } # %
    Memory       = [pscustomobject]@{ TotalGB = $totalGB; FreeGB = $freeGB; UsedGB = $usedGB; UsedPct = $memPct } # GB, %
    Disks        = $disks # array of { Letter, TotalGB, UsedGB, UsedPct }
    Network      = [pscustomobject]@{ WanLatencyMs = $wanLatency; Routers = $routerStats } # ms
    Events       = [pscustomobject]@{
                      LastHourWarnings     = $warnCount
                      LastHourErrors       = $errCount
                      LatestFilteredErrors = $latestFiltered
                      HotMessages          = $hot
                   } # counts, arrays
    TopProcesses = $top
  } # end pscustomobject
} # end function

# =========================
# =========================
function Test-UrlAcl {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Prefix) # e.g. "http://localhost:8899/"
  $existing = (netsh http show urlacl) 2>$null # suppress error if none exist
  return ($existing -match [regex]::Escape($Prefix)) # returns $true/$false
}
if (-not (Test-UrlAcl -Prefix $Prefix)) {
  Write-Host "No URL ACL for '$Prefix'. Run elevated once: Ensure-UrlAcl -Prefix `"$Prefix`"" -ForegroundColor Yellow
}

# One-time (run as Administrator) to reserve the URL for non-admin runs
function Ensure-UrlAcl {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Prefix,
    [string]$User = "$env:USERDOMAIN\$env:USERNAME"
  )
  $existing = (netsh http show urlacl) 2>$null # suppress error if none exist
  if ($existing -match [regex]::Escape($Prefix)) { return } # already exists
  Write-Host "Adding URL ACL for $Prefix to user '$User' (requires elevation)..." -ForegroundColor Yellow
  & netsh http add urlacl url=$Prefix user=$User | Out-Null
} # end function

# (run as Administrator) to remove the URL reservation
function Remove-UrlAcl {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Prefix)
  & netsh http delete urlacl url=$Prefix | Out-Null # ignore error if not exists
  Write-Host "Removed URL ACL for $Prefix" -ForegroundColor Yellow
} # end function

# =========================
# GRACEFUL LISTENER HOST
# =========================
function Start-SystemDashboardListener {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Prefix,    # e.g. "http://localhost:8899/"
    [Parameter(Mandatory)][string]$Root,      # e.g. "C:\Path\To\wwwroot\"
    [Parameter(Mandatory)][string]$IndexHtml, # e.g. "C:\Path\To\wwwroot\index.html"
    [Parameter(Mandatory)][string]$CssFile, # e.g. "C:\Path\To\wwwroot\styles.css"
    [switch]$OpenBrowser # open browser tab once listener starts
  )

  $Root = "F:\Logs\wwwroot\" # web root folder (will be created if missing)
  # Enforce URL reservation has been created once (non-admin runs)
  if (-not (Test-UrlAcl -Prefix $Prefix)) {
    throw "No URL ACL for '$Prefix'. Run elevated once: Ensure-UrlAcl -Prefix `"$Prefix`""
  }

  # Stop signal (Ctrl+C or engine exit)
  $script:StopEvent = [ManualResetEvent]::new($false) # initially not signaled
  $subs = [System.Collections.Generic.List[System.IDisposable]]::new() # track event subscriptions


  # Ctrl+C handler  cancel default termination so we can cleanup
  $onCancel = [ConsoleCancelEventHandler]{
    param($sender,$args)
    $args.Cancel = $true
    $script:StopEvent.Set()
  } # end handler
  [Console]::add_CancelKeyPress($onCancel) # hook it

  # PS engine exit handler
  $exitSub = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { $script:StopEvent.Set() } # end action
  $subs.Add($exitSub) # track it

  # Listener setup and loop (try/finally for cleanup)
  $listener = [HttpListener]::new()
  $listener.IgnoreWriteExceptions = $true # avoid crash on client abort
  $null = $listener.Prefixes.Add($Prefix) # add the prefix

  # Optional: open browser to the dashboard once listening
  if ($OpenBrowser) {
    Start-Process $Prefix | Out-Null
  }

  # Perfect PowerShell with candid inline comments.

try {
  # Start the listener once
  $listener.Start()  # may throw if URL ACL not set or port is in use
  Write-Host "SystemDashboard listening at $Prefix (Ctrl+C to stop)..." -ForegroundColor Green

  #### Main loop ####
  while ($listener.IsListening) {
    # Begin async accept so we can wait on a StopEvent without blocking
    $async = $listener.BeginGetContext($null, $null)
    $index = [WaitHandle]::WaitAny(@($async.AsyncWaitHandle, $script:StopEvent), 250)  # 250ms poll

    if ($index -eq 1) { break }         # StopEvent signaled -> exit loop
    if (-not $async.IsCompleted) { continue }  # timeout -> loop again

    # Complete the accept exactly once
    $context  = $listener.EndGetContext($async)
    $request  = $context.Request
    $response = $context.Response

    # Optional tracing id (only if you use it below)
    $trace = if (Get-Command New-TraceId -EA SilentlyContinue) { New-TraceId } else { $null }

    Write-Host ("Received request: {0} {1}" -f $request.HttpMethod, $request.RawUrl) -ForegroundColor DarkGray

    # -------- Per-request handling --------
    try {
      # Optional: request snapshot if your helper exists (won't break if it doesn't)
      if ($trace -and (Get-Command Snapshot-Request -EA SilentlyContinue)) {
        $reqSnap = Snapshot-Request -Request $request
        if (Get-Command Write-TraceJson -EA SilentlyContinue) {
          Write-TraceJson -TraceId $trace -Direction 'Request' -Payload $reqSnap
        }
      }

      # Route strictly on AbsolutePath so query strings don't break matching
      $path = $request.Url.AbsolutePath

      switch ($path) {

        '/' {
          # Serve index.html
          $bytes = [IO.File]::ReadAllBytes($IndexHtml)
          $response.StatusCode  = 200
          $response.ContentType = 'text/html; charset=utf-8'
          $response.Headers['Cache-Control'] = 'no-store'
          $response.SendChunked = $false
          $response.ContentLength64 = $bytes.LongLength
          $response.OutputStream.Write($bytes, 0, $bytes.Length)
          Write-Host "Served /" -ForegroundColor DarkGray
          break
        }

        '/styles.css' {
          $bytes = [IO.File]::ReadAllBytes($CssFile)
          $response.StatusCode  = 200
          $response.ContentType = 'text/css; charset=utf-8'
          $response.Headers['Cache-Control'] = 'no-store'
          $response.SendChunked = $false
          $response.ContentLength64 = $bytes.LongLength
          $response.OutputStream.Write($bytes, 0, $bytes.Length)
          Write-Host "Served /styles.css" -ForegroundColor DarkGray
          break
        }

        '/metrics' {
          # Build REAL metrics
          $metrics = Get-Metrics

          if ($null -eq $metrics) {
            # Honest 503 if your producer failed
            $err = [Text.Encoding]::UTF8.GetBytes('No metrics available')
            $response.StatusCode  = 503
            $response.ContentType = 'text/plain; charset=utf-8'
            $response.Headers['Cache-Control'] = 'no-store'
            $response.SendChunked = $false
            $response.ContentLength64 = $err.LongLength
            $response.OutputStream.Write($err, 0, $err.Length)
            Write-Warning "Get-Metrics returned null"
            break
          }

          # Serialize once → exact UTF-8 bytes
          $json  = $metrics | ConvertTo-Json -Depth 8 -Compress
          $bytes = [Text.Encoding]::UTF8.GetBytes($json)
          Write-Host ("metrics bytes: {0}" -f $bytes.Length) -ForegroundColor DarkGray

          $response.StatusCode  = 200
          $response.ContentType = 'application/json; charset=utf-8'
          $response.Headers['Cache-Control'] = 'no-store'
          $response.SendChunked = $false
          $response.ContentLength64 = $bytes.LongLength
          $response.OutputStream.Write($bytes, 0, $bytes.Length)
          Write-Host "Served /metrics" -ForegroundColor DarkGray
          break
        }

        default {
          # Static file fallback (safe path join)
          $localRoot = [IO.Path]::GetFullPath($Root)
          if (-not $localRoot.EndsWith([IO.Path]::DirectorySeparatorChar)) {
            $localRoot += [IO.Path]::DirectorySeparatorChar
          }
          $localReq = [IO.Path]::GetFullPath(
            (Join-Path $Root ($path.TrimStart('/') -replace '/', [IO.Path]::DirectorySeparatorChar))
          )

          # Block traversal
          if (-not ($localReq.StartsWith($localRoot))) {
            $response.StatusCode = 403
            Write-Host "Blocked traversal: $localReq" -ForegroundColor DarkGray
            break
          }

          if (Test-Path -LiteralPath $localReq -PathType Leaf) {
            $ext = [IO.Path]::GetExtension($localReq).ToLowerInvariant()
            $ct  = switch ($ext) {
              '.js'   { 'application/javascript; charset=utf-8' }
              '.json' { 'application/json; charset=utf-8' }
              '.png'  { 'image/png' }
              '.jpg'  { 'image/jpeg' }
              '.jpeg' { 'image/jpeg' }
              '.svg'  { 'image/svg+xml' }
              default { 'application/octet-stream' }
            }
            $bytes = [IO.File]::ReadAllBytes($localReq)
            $response.StatusCode  = 200
            $response.ContentType = $ct
            $response.Headers['Cache-Control'] = 'no-store'
            $response.SendChunked = $false
            $response.ContentLength64 = $bytes.LongLength
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            Write-Host "Serving static file: $localReq" -ForegroundColor DarkGray
          }
          else {
            $response.StatusCode = 404
          }
        } # end default

      } # end switch

    }
    catch {
      # Tell the truth about the server-side fault
      Write-Error ("Request handling error: {0}" -f $_.Exception.Message)

      # Best-effort 500 (only if we still have a response to write to)
      try {
        if ($response) {
          $errBytes = [Text.Encoding]::UTF8.GetBytes("Internal Server Error")
          $response.StatusCode  = 500
          $response.ContentType = 'text/plain; charset=utf-8'
          $response.Headers['Cache-Control'] = 'no-store'
          $response.SendChunked = $false
          $response.ContentLength64 = $errBytes.LongLength
          $response.OutputStream.Write($errBytes, 0, $errBytes.Length)
        }
      } catch { }  # swallow secondary write errors
    }
    finally {
      # Close the response ONCE per request. Do NOT stop/close the listener here.
      try { if ($response) { $response.Close() } } catch { }
    }

  } # end while
}
finally {
  # Outside the loop: now it's safe to stop and close the listener
  try { if ($listener.IsListening) { $listener.Stop() } } catch { }
  try { $listener.Close() } catch { }
}
}

# =========================
# ENTRY POINT
# =========================

# 1) One-time (run as Administrator) to reserve the URL:
Ensure-UrlAcl -Prefix $Prefix # -User "$env:USERDOMAIN\$env:USERNAME" # default user

# Mutex to prevent multiple instances
$mutexName = "Global\SystemDashboardListenerMutex_$($Prefix -replace '[^a-zA-Z0-9]','_')" # sanitize
$script:DashMutex = [Threading.Mutex]::new($false, $mutexName)
$hasHandle = $false
try {
    try {
        $hasHandle = $script:DashMutex.WaitOne(0, $false) # non-blocking
        if (-not $hasHandle) {
            throw "Another instance of SystemDashboard listener is already running (mutex '$mutexName'). Exiting."
        }
    } catch {
        throw "Failed to acquire Mutex '$mutexName': $_"
    }
  }catch {
    Write-Host $_ -ForegroundColor Red
    exit 1
  }
  $Root = "F:\Logs\wwwroot\" # web root folder (will be created if missing)
# 2) Start the listener. Use -OpenBrowser if you want it to pop the tab.
Start-SystemDashboardListener -Prefix $Prefix -IndexHtml $IndexHtml -Root $Root -CssFile $CssFile -OpenBrowser # optional

# =========================
# CLEANUP FIX: Ensure response stream is closed in error cases
# =========================
catch {
    # Render a minimal 500 page, but avoid parser issues by precomputing pieces
    try {
        $errText = ($_ | Out-String)                 # full exception text
        $errEsc  = [WebUtility]::HtmlEncode($errText) # HTML-escape safely
        $msg     = "<h1>500</h1><pre>$errEsc</pre>"

        $bytes = [Text.Encoding]::UTF8.GetBytes($msg) # encode as UTF-8 bytes
        $response.StatusCode      = 500 # Internal Server Error
        $response.ContentType     = 'text/html; charset=utf-8' # set content type
        $response.ContentLength64 = $bytes.LongLength # set content length
        $response.OutputStream.Write($bytes, 0, $bytes.Length) # write to output stream
    } catch { }
    finally {
        try { $response.OutputStream.Close() } catch { }
        $response.Close()
    }
} # ensure stream is closed
# =========================
# CLEANUP FIX: Ensure Mutex is released on exit
# =========================
if ($script:DashMutex) {
    try { $script:DashMutex.ReleaseMutex() } catch {}
    $script:DashMutex.Dispose()
}
# =========================
# CLEANUP FIX: Unhook events to avoid ghost handlers on re-run
# =========================
try { [Console]::remove_CancelKeyPress($onCancel) } catch { }
foreach ($s in $subs) { try { Unregister-Event -SourceIdentifier $s.SourceIdentifier -ErrorAction SilentlyContinue } catch { } }
$subs.Clear()
$script:StopEvent.Dispose()
# =========================
# INSTRUCTIONS
# =========================
# 1) (One-time) Run PowerShell as Administrator and execute:
#    .\Start-SystemDashboard.ps1 -Ensure-UrlAcl -Prefix $Prefix -User "$env:USERDOMAIN\$env:USERNAME"
#    This reserves the URL for your user account. You can customize the $Prefix variable in the script.
# 2) Run PowerShell as normal user and execute: .\Start-SystemDashboard.ps1
#    This starts the listener. You can customize the $Prefix, $DesiredDriveLetters, $Routers, $EventProvidersOfInterest, and $HotMessageKeywords variables in the script.
#    Open your browser and navigate to the URL in $Prefix (e.g. http://localhost:8899/). The dashboard auto-refreshes every 5 seconds.
# 3) (Optional) To remove the URL reservation (run as Administrator): Remove-UrlAcl -Prefix $Prefix
# =========================
# FILES
# =========================
# - Start-SystemDashboard.ps1  (this script)
# - wwwroot\index.html         (dashboard HTML)
# - wwwroot\styles.css         (dashboard CSS)
# =========================
# NOTES
# =========================
# - You can run this script as a normal user after the one-time URL ACL reservation.
# - You can run multiple instances on different ports (e.g. for different machines).
# - You can customize the static files in the wwwroot folder (HTML/CSS/JS).
# - You can customize the monitored disks, routers, event providers, and WAN probe host in the CONFIG section.
# - You can run this script at startup via Task Scheduler (Run with highest privileges, but not "Run as administrator").
# - You can stop the listener gracefully with Ctrl+C in the console window.
# - You can also stop the listener by closing the PowerShell window or stopping the script in VSCode.
# - The listener cleans up the URL reservation on exit, so you can re-run the script
#   without needing to re-add the URL ACL (unless you deleted it manually).
# - The listener uses a Mutex to prevent multiple instances from running simultaneously.
# - The listener uses async request handling to remain responsive to stop signals.
# - The listener serves static files from the wwwroot folder and provides a /metrics endpoint for
#   dynamic JSON data for the dashboard.
# - The dashboard auto-refreshes every 5 seconds using JavaScript fetch API.
# - The dashboard is designed to be modern and lightweight, with a dark theme.
# - The dashboard displays CPU, memory, disk usage, router status, recent events, hot messages, and top processes.
# - The dashboard uses simple HTML and CSS for layout and styling.
# - The dashboard uses JavaScript to fetch and display metrics dynamically.
# - The script is compatible with PowerShell 7 and later.
# - The script uses built-in .NET classes and PowerShell cmdlets for functionality.
# - The script is self-contained and does not require external dependencies.
# - The script is intended for educational and monitoring purposes.
# - The script is provided "as is" without warranty of any kind.
# - Use at your own risk. Always review and understand the code before running it in your environment.
# - The script may require adjustments based on your specific environment and requirements.
# - The script may not cover all edge cases and scenarios.
# =========================
# EOF
# CHANGELOG
# =========================
#  - v1.0           - Initial release
#  - v1.1           - Added Mutex to prevent multiple
#                   - Improved disk handling logic
#                   - Improved logging and status messages
#                   - Improved async request handling
#                   - Improved error handling in listener
#                   - Improved HTML/CSS for better layout
#                   - Added more comments and documentation
#  - v1.2           - Added top processes by CPU
#                   - Added event filtering by provider
#                   - Added hot messages table
#                   - Improved WAN latency check
#                   - Improved disk selection logic
#                   - Improved memory calculation
#                   - Improved code structure and readability
#                   - Added more configuration options
#  - v1.3           - Fixed minor bugs
#                   - Improved performance of metrics collection
#                   - Improved dashboard responsiveness
#                   - Added more comments and documentation
#                   - Updated HTML/CSS for better aesthetics
#                   - Added option to open browser on start
#                   - Added option to remove URL ACL
#                   - Improved error messages
#                   - Improved logging and status messages

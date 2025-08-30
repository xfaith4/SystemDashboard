#requires -Version 7
using namespace System.Net
using namespace System.Threading
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =========================
# CONFIG
# =========================


# Listener/URL
$Port   = 8899
$Prefix = "http://localhost:$Port/"

# Dashboard title
$Title = "System Monitor - $env:COMPUTERNAME"

# Static files
$Root      = Join-Path $PSScriptRoot 'wwwroot'
$IndexHtml = Join-Path $Root 'index.html'
$CssFile   = Join-Path $Root 'styles.css'

# Routers to probe (ASUS, etc.)
$Routers = @(
  @{ Name = 'ASUS Main'; Host = '192.168.50.1' },
  @{ Name = 'ASUS Node'; Host = '192.168.50.2' }
)

# WAN latency target
$WanProbeHost = '1.1.1.1'   # alt: 8.8.8.8

# Disks to show (auto-skips if not present)
$DesiredDriveLetters = @('C','D','G')

# Event filtering
$EventProvidersOfInterest = @(
  'Microsoft-Windows-WLAN-AutoConfig',
  'Schannel'
)
$HotMessageKeywords = @('disconnect','dhcp','authentication','tls','schannel','certificate','dns','timeout','webrtc')

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

  # --- Memory
  $os = Get-CimInstance -ClassName Win32_OperatingSystem
  $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
  $freeGB  = [math]::Round($os.FreePhysicalMemory     / 1MB, 2)
  $usedGB  = $totalGB - $freeGB
  $memPct  = Get-Percent $usedGB $totalGB

    # --- Disks
  $fixed   = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"

  # If you didn't specify letters, derive them from actual disks (trim the colon safely per item)
  $letters = if ($DesiredDriveLetters -and $DesiredDriveLetters.Count) {
      $DesiredDriveLetters
  } else {
      $fixed | ForEach-Object { $_.DeviceID.TrimEnd(':') }
  }

  # Force an array result (even if empty) so JSON gives [] instead of null
  $disks = @(
      foreach ($L in ($letters | Select-Object -Unique)) {
          $d = $fixed | Where-Object { $_.DeviceID -eq "${L}:" }   # DeviceID includes the colon
          if (-not $d) { continue }
          $t = [math]::Round($d.Size      / 1GB, 2)
          $f = [math]::Round($d.FreeSpace / 1GB, 2)
          $u = $t - $f
          [pscustomobject]@{
              Letter  = $L
              TotalGB = $t
              UsedGB  = $u
              UsedPct = Get-Percent $u $t
          }
      }
  )
  
  # --- Network
  $wanMs       = Get-LatencyMs -Target $WanProbeHost -Count 2
  $routerStats = foreach ($r in $Routers) {
    $ms = Get-LatencyMs -Target $r.Host -Count 2
    [pscustomobject]@{
      Name      = $r.Name
      Host      = $r.Host
      Reachable = ($ms -ge 0)
      LatencyMs = $ms
    }
  }

  # --- Events (last hour)
  $start = (Get-Date).AddHours(-1)

  # Correct FilterHashtable syntax: array for multiple logs
  $warns = Get-WinEvent -FilterHashtable @{ LogName = @('System','Application'); Level = 3; StartTime = $start } -ErrorAction SilentlyContinue
  $errs  = Get-WinEvent -FilterHashtable @{ LogName = @('System','Application'); Level = 2; StartTime = $start } -ErrorAction SilentlyContinue

  # Filtered errors by providers of interest
  $filteredErrs = foreach ($p in $EventProvidersOfInterest) {
    Get-WinEvent -FilterHashtable @{ ProviderName = $p; Level = 2; StartTime = $start } -ErrorAction SilentlyContinue
  }

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
        $m -replace '"','\'
      }
    }

  # Hot messages (keyword buckets)
  $hot = @()
  if ($HotMessageKeywords.Count -gt 0) {
    $rx = [regex]::new('(' + (($HotMessageKeywords | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')', 'IgnoreCase')
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
      }
  }

  # --- Top processes (delta sample ~0.8s)
  $procs1 = Get-Process | Where-Object { $_.CPU -ne $null }
  Start-Sleep -Milliseconds 800
  $procs2 = Get-Process | Where-Object { $_.CPU -ne $null } | Group-Object Id -AsHashTable -AsString

  # $procs2 maps Id -> [array of Process]; pick the first element
  $top = @(
      $procs1 | ForEach-Object {
          $p1  = $_
          $arr = $procs2[[string]$p1.Id]
          if (-not $arr -or $arr.Count -eq 0) { return }   # process ended between samples

          $p2     = $arr[0]
          $delta  = ($p2.CPU - $p1.CPU)
          $cpuPct = [math]::Max(0, ($delta / 0.8) / [Environment]::ProcessorCount * 100)

          [pscustomobject]@{
              Name  = $p1.ProcessName
              CPU   = [math]::Round($cpuPct, 1)
              WS_MB = [math]::Round($p2.WorkingSet64 / 1MB, 0)
          }
      }
  ) | Sort-Object CPU -Descending | Select-Object -First 8
  # Force array result so JSON gives [] instead of null
  if (-not $top) { $top = @() }
    }
# =========================
# URL ACL helpers
# =========================
function Test-UrlAcl {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Prefix)
  $existing = (netsh http show urlacl) 2>$null
  return ($existing -match [regex]::Escape($Prefix))
}

function Ensure-UrlAcl {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Prefix,
    [string]$User = "$env:USERDOMAIN\$env:USERNAME"
  )
  $existing = (netsh http show urlacl) 2>$null
  if ($existing -match [regex]::Escape($Prefix)) { return }
  Write-Host "Adding URL ACL for $Prefix to user '$User' (requires elevation)..." -ForegroundColor Yellow
  & netsh http add urlacl url=$Prefix user=$User | Out-Null
}

function Remove-UrlAcl {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Prefix)
  & netsh http delete urlacl url=$Prefix | Out-Null
}

# =========================
# GRACEFUL LISTENER HOST
# =========================
function Start-SystemDashboardListener {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Prefix,    # e.g. "http://localhost:8899/"
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$IndexHtml,
    [Parameter(Mandatory)][string]$CssFile,
    [switch]$OpenBrowser
  )

  # Enforce URL reservation has been created once (non-admin runs)
  if (-not (Test-UrlAcl -Prefix $Prefix)) {
    throw "No URL ACL for '$Prefix'. Run elevated once: Ensure-UrlAcl -Prefix `"$Prefix`""
  }

  # Stop signal (Ctrl+C or engine exit)
  $script:StopEvent = [ManualResetEvent]::new($false)
  $subs = [System.Collections.Generic.List[System.IDisposable]]::new()

  # Ctrl+C handler  cancel default termination so we can cleanup
  $onCancel = [ConsoleCancelEventHandler]{
    param($sender,$args)
    $args.Cancel = $true
    $script:StopEvent.Set()
  }
  [Console]::add_CancelKeyPress($onCancel)

  # PS engine exit handler
  $exitSub = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { $script:StopEvent.Set() }
  $subs.Add($exitSub)

  # Listener
  $listener = [HttpListener]::new()
  $listener.IgnoreWriteExceptions = $true
  $null = $listener.Prefixes.Add($Prefix)

  # Optional: open browser to the dashboard once listening
  if ($OpenBrowser) {
    Start-Process $Prefix | Out-Null
  }

  try {
    $listener.Start()
    Write-Host "SystemDashboard listening at $Prefix (Ctrl+C to stop)..." -ForegroundColor Green

    while ($listener.IsListening) {
      # async wait so we can poll for StopEvent
      $async = $listener.BeginGetContext($null,$null)
      $index = [WaitHandle]::WaitAny(@($async.AsyncWaitHandle, $script:StopEvent), 250)
      if ($index -eq 1) { break }
      if (-not $async.IsCompleted) { continue }

      # Request arrives
      $context  = $listener.EndGetContext($async)
      $request  = $context.Request
      $response = $context.Response

      try {
        switch -Regex ($request.RawUrl) {
          '^/$' {
            # Serve index.html
            $bytes = [IO.File]::ReadAllBytes($IndexHtml)
            $response.ContentType = 'text/html; charset=utf-8'
            $response.StatusCode  = 200
            $response.ContentLength64 = $bytes.LongLength
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            break
          }
          '^/styles\.css$' {
            # Serve CSS
            $bytes = [IO.File]::ReadAllBytes($CssFile)
            $response.ContentType = 'text/css; charset=utf-8'
            $response.StatusCode  = 200
            $response.ContentLength64 = $bytes.LongLength
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            break
          }
          '^/metrics$' {
            # NEW: Serve JSON metrics for the dashboard
            $payload = Get-Metrics | ConvertTo-Json -Depth 8 -Compress
            $bytes   = [Text.Encoding]::UTF8.GetBytes($payload)
            $response.ContentType = 'application/json; charset=utf-8'
            $response.StatusCode  = 200
            $response.ContentLength64 = $bytes.LongLength
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            break
          }
          default {
            # Static file fallback relative to $Root (safely)
            $localRoot = [IO.Path]::GetFullPath($Root)
            $localReq  = [IO.Path]::GetFullPath((Join-Path $Root ($request.RawUrl.TrimStart('/') -replace '/', [IO.Path]::DirectorySeparatorChar)))
            if (-not ($localReq.StartsWith($localRoot))) {
              $response.StatusCode = 403
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
              $response.ContentType = $ct
              $response.StatusCode  = 200
              $response.ContentLength64 = $bytes.LongLength
              $response.OutputStream.Write($bytes, 0, $bytes.Length)
            } else {
              $response.StatusCode = 404
            }
          }
        }
      }
      catch {
    # Render a minimal 500 page, but avoid parser issues by precomputing pieces
    try {
        $errText = ($_ | Out-String)                 # full exception text
        $errEsc  = [WebUtility]::HtmlEncode($errText) # HTML-escape safely
        $msg     = "<h1>500</h1><pre>$errEsc</pre>"

        $bytes = [Text.Encoding]::UTF8.GetBytes($msg)
        $response.StatusCode      = 500
        $response.ContentType     = 'text/html; charset=utf-8'
        $response.ContentLength64 = $bytes.LongLength
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
    } catch { }
}

      finally {
        try { $response.OutputStream.Close() } catch { }
        $response.Close()
      }
    } # while
  } finally {

    # Ensure socket and reservation state are cleanly released
    try { if ($listener.IsListening) { $listener.Stop() } } catch { }
    try { $listener.Close() } catch { }
   
    # ... your Stop/Close/unhook code ...
    if ($script:DashMutex) {
        try { $script:DashMutex.ReleaseMutex() } catch {}
        $script:DashMutex.Dispose()
    }


    # Unhook events to avoid ghost handlers on re-run
    try { [Console]::remove_CancelKeyPress($onCancel) } catch { }
    foreach ($s in $subs) { try { Unregister-Event -SourceIdentifier $s.SourceIdentifier -ErrorAction SilentlyContinue } catch { } }

    Write-Host "SystemDashboard listener stopped and cleaned up." -ForegroundColor Cyan
  }
}

# =========================
# ENTRY POINT
# =========================

# 1) One-time (run as Administrator) to reserve the URL:
# Ensure-UrlAcl -Prefix $Prefix

# 2) Start the listener. Use -OpenBrowser if you want it to pop the tab.
if ($MyInvocation.InvocationName -ne '.') {
  Start-SystemDashboardListener -Prefix $Prefix -Root $Root -IndexHtml $IndexHtml -CssFile $CssFile -OpenBrowser
}


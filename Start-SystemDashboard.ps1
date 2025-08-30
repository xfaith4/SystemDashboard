#requires -Version 7
<#
.SYNOPSIS
  System Dashboard: serves a live-monitoring dashboard via HTTP providing CPU, memory, disk, network,
  events, and top processes in real time with auto-refresh.

.DESCRIPTION
  Requires PowerShell 7+. Reserves HTTP URL access (via URL ACL) if needed. Uses Get-Metrics to assemble
  a structured object that the frontend fetches and renders.
.PARAMETER Port
  Port to listen on (default 8899)
.PARAMETER WanProbeHost
  Host to probe for WAN latency (default: 1.1.1.1)
.PARAMETER DesiredDriveLetters
  Array of drive letters to monitor; if omitted, monitors all fixed drives.
.PARAMETER EventProvidersOfInterest
  List of event providers to highlight error messages from.
.PARAMETER HotMessageKeywords
  Keywords to filter “hot” messages from recent events.
.EXAMPLE
  .\SystemDashboard.ps1 -Port 8080 -OpenBrowser
#>

param(
    [int]$Port = 8899,
    [string]$WanProbeHost = '1.1.1.1',
    [string[]]$DesiredDriveLetters = @('C','D','G'),
    [string[]]$EventProvidersOfInterest = @(
         'Microsoft-Windows-WLAN-AutoConfig',
         'Schannel'
    ),
    [string[]]$HotMessageKeywords = @(
         'disconnect','dhcp','authentication','tls','schannel','certificate','dns','timeout','webrtc'
    ),
    [switch]$OpenBrowser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Validate Administrator when setting URL ACL
function Test-IsAdmin {
    $current = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent())
    return $current.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

# Paths
$Prefix        = "http://localhost:$Port/"
$Root          = Join-Path $PSScriptRoot 'wwwroot'
$IndexHtml     = Join-Path $Root 'index.html'
$CssFile       = Join-Path $Root 'styles.css'
$Title         = "System Monitor - $env:COMPUTERNAME"

# Ensure web assets directory
try {
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
} catch {
    Write-Warning "Could not create directory $Root: $_"
}

# Write HTML
$indexHtmlContent = @"
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
    async function refresh() {
      try {
        const r = await fetch('/metrics', {cache:'no-store'});
        if (!r.ok) throw new Error('HTTP '+r.status);
        const m = await r.json();
        document.getElementById('host').textContent = m.ComputerName;
        document.getElementById('updated').textContent = new Date(m.Timestamp).toLocaleTimeString();
        document.getElementById('cpu').textContent = m.CPU.UsagePct.toFixed(1) + '%';
        document.getElementById('mem').textContent = m.Memory.UsedPct.toFixed(1)+'% ('+m.Memory.UsedGB.toFixed(1)+' / '+m.Memory.TotalGB.toFixed(1)+' GB)';
        document.getElementById('wan').textContent = (m.Network.WanLatencyMs >= 0 ? m.Network.WanLatencyMs.toFixed(0)+' ms' : 'unreachable');
        const disksDiv = document.getElementById('disks'); disksDiv.innerHTML = '';
        m.Disks.forEach(d => {
          const cls = d.UsedPct >= 90 ? 'err' : (d.UsedPct >= 80 ? 'warn' : '');
          disksDiv.innerHTML += '<div class="kv '+cls+'"><span>'+d.Letter+':</span><b>'+d.UsedPct.toFixed(1)+'% ('+d.UsedGB.toFixed(0)+' / '+d.TotalGB.toFixed(0)+' GB)</b></div>';
        });
        const ul = document.getElementById('routers'); ul.innerHTML = '';
        m.Network.Routers.forEach(rt => {
          const li = document.createElement('li');
          const status = rt.Reachable ? rt.LatencyMs.toFixed(0)+' ms' : 'down';
          li.textContent = rt.Name+' ('+rt.Host+'): '+status;
          ul.appendChild(li);
        });
        document.getElementById('evWarn').textContent = m.Events.LastHourWarnings;
        document.getElementById('evErr').textContent = m.Events.LastHourErrors;
        const evList = document.getElementById('evList'); evList.innerHTML = '';
        (m.Events.LatestFilteredErrors || []).forEach(e => {
          const li = document.createElement('li');
          li.textContent = '['+e.Time+'] '+e.Provider+': '+e.Message;
          evList.appendChild(li);
        });
        const hotBody = document.querySelector('#hot tbody'); hotBody.innerHTML = '';
        (m.Events.HotMessages || []).forEach(h => {
          const tr = document.createElement('tr');
          tr.innerHTML = '<td>'+h.Provider+'</td><td>'+h.Snippet+'</td><td>'+h.Count+'</td>';
          hotBody.appendChild(tr);
        });
        const tbody = document.querySelector('#procs tbody'); tbody.innerHTML = '';
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
"@
$indexHtmlContent | Set-Content -LiteralPath $IndexHtml -Encoding UTF8

# Write CSS
$cssContent = @"
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
"@
$cssContent | Set-Content -LiteralPath $CssFile -Encoding UTF8

function Get-Percent { param([double]$Part, [double]$Whole) if ($Whole -le 0) { return 0 } [math]::Round(($Part / $Whole) * 100, 2) }

function Get-LatencyMs {
    param([Parameter(Mandatory)][string]$Target, [int]$Count = 2)
    try {
        $ping = New-Object System.Net.NetworkInformation.Ping
        $times = for ($i = 0; $i -lt $Count; $i++) {
            $reply = $ping.Send($Target, 1000)
            if ($reply.Status -eq 'Success') { $reply.RoundtripTime }
        }
        if ($times.Count -gt 0) { return [math]::Round(($times | Measure-Object -Average).Average,1) }
        return -1
    } catch {
        return -1
    }
}

function Get-Metrics {
    # Gather system state
    $cpuRaw = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue
    $os = Get-CimInstance Win32_OperatingSystem
    $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usedGB = $totalGB - $freeGB
    $memPct = Get-Percent $usedGB $totalGB

    $fixed = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
    $letters = if ($DesiredDriveLetters -and $DesiredDriveLetters.Count) { $DesiredDriveLetters } else { $fixed | ForEach-Object { $_.DeviceID.TrimEnd(':') } }
    $disks = @()
    foreach ($L in ($letters | Select-Object -Unique)) {
        $d = $fixed | Where-Object { $_.DeviceID -eq "${L}:" }
        if (-not $d) { continue }
        $t = [math]::Round($d.Size / 1GB, 2)
        $f = [math]::Round($d.FreeSpace / 1GB, 2)
        $u = $t - $f
        $disks += [pscustomobject]@{ Letter=$L; TotalGB=$t; UsedGB=$u; UsedPct=Get-Percent $u $t }
    }

    $wanMs = Get-LatencyMs -Target $WanProbeHost -Count 2
    $routerStats = foreach ($r in $Routers) {
        $ms = Get-LatencyMs -Target $r.Host -Count 2
        [pscustomobject]@{ Name=$r.Name; Host=$r.Host; Reachable=($ms -ge 0); LatencyMs=$ms }
    }

    $start = (Get-Date).AddHours(-1)
    $warns = Get-WinEvent -FilterHashtable @{ LogName=@('System','Application'); Level=3; StartTime=$start } -ErrorAction SilentlyContinue
    $errs  = Get-WinEvent -FilterHashtable @{ LogName=@('System','Application'); Level=2; StartTime=$start } -ErrorAction SilentlyContinue
    $filteredErrs = Get-WinEvent -FilterHashtable @{
        LogName=@('System','Application');
        ProviderName=$EventProvidersOfInterest;
        Level=2;
        StartTime=$start
    } -ErrorAction SilentlyContinue

    $latestFiltered = $filteredErrs |
      Sort-Object TimeCreated -Descending |
      Select-Object -First 6 @{
        n='Time'; e={ $_.TimeCreated.ToString('HH:mm:ss') } }, @{
        n='Provider'; e={ $_.ProviderName } }, @{
        n='Message'; e={
            $m = ($_.Message -replace '\s+', ' ')
            if ($m.Length -gt 300) { $m = $m.Substring(0,300)+'…' }
            $m -replace '"','\'
        }
    }

    $hot = @()
    if ($HotMessageKeywords.Count -gt 0) {
        $rx = [regex]::new('(' + ($HotMessageKeywords | ForEach-Object { [regex]::Escape($_) }) -join '|' + ')', 'IgnoreCase')
        $hot = ($warns + $errs + $filteredErrs) |
          Where-Object { $_ -and $rx.IsMatch($_.Message) } |
          ForEach-Object {
              $snippet = ($_.Message -replace '\s+', ' ')
              if ($snippet.Length -gt 120) { $snippet = $snippet.Substring(0,120)+'…' }
              [pscustomobject]@{ Provider=$_.ProviderName; Snippet=$snippet }
          } |
          Group-Object Provider, Snippet |
          Sort-Object Count -Descending |
          Select-Object -First 12 @{
            n='Provider'; e={ $_.Group[0].Provider } }, @{
            n='Snippet'; e={ $_.Group[0].Snippet } }, @{
            n='Count'; e={ $_.Count }
        }
    }

    # Top processes sampling
    $procs1 = Get-Process | Where-Object { $_.CPU -ne $null }
    Start-Sleep -Milliseconds 800
    $procs2 = Get-Process | Where-Object { $_.CPU -ne $null } | Group-Object Id -AsHashTable -AsString
    $top = @()
    foreach ($p1 in $procs1) {
        if ($procs2[[string]$p1.Id] -and $procs2[[string]$p1.Id].Count -gt 0) {
            $p2 = $procs2[[string]$p1.Id][0]
            $delta = $p2.CPU - $p1.CPU
            $cpuPct = [math]::Max(0, ($delta / 0.8) / [Environment]::ProcessorCount * 100)
            $top += [pscustomobject]@{
                Name  = $p1.ProcessName
                CPU   = [math]::Round($cpuPct,1)
                WS_MB = [math]::Round($p2.WorkingSet64 / 1MB,0)
            }
        }
    }
    $top = $top | Sort-Object CPU -Descending | Select-Object -First 8

    # Build structured output
    return [pscustomobject]@{
      ComputerName = $env:COMPUTERNAME
      Timestamp    = (Get-Date).ToString("o")
      CPU          = @{ UsagePct = [math]::Round($cpuRaw,1) }
      Memory       = @{ UsedPct = $memPct; UsedGB = $usedGB; TotalGB = $totalGB }
      Disks        = $disks
      Network      = @{ WanLatencyMs = $wanMs; Routers = $routerStats }
      Events       = @{
        LastHourWarnings     = ($warns | Measure-Object).Count
        LastHourErrors       = ($errs | Measure-Object).Count
        LatestFilteredErrors = $latestFiltered
        HotMessages          = $hot
      }
      TopProcesses = $top
    }
}

function Test-UrlAcl {
    param([string]$Prefix)
    $existing = (netsh http show urlacl) 2>$null
    return $existing -match [regex]::Escape($Prefix)
}

function Ensure-UrlAcl {
    param([string]$Prefix, [string]$User = "$env:USERDOMAIN\$env:USERNAME")
    if (-not (Test-UrlAcl -Prefix $Prefix)) {
        if (-not (Test-IsAdmin)) { throw "Requires Administrator to register URL ACL: $Prefix" }
        Write-Host "Adding URL ACL for $Prefix to user '$User'..." -ForegroundColor Yellow
        netsh http add urlacl url=$Prefix user=$User | Out-Null
    }
}

function Remove-UrlAcl {
    param([string]$Prefix)
    netsh http delete urlacl url=$Prefix | Out-Null
}

function Start-SystemDashboardListener {
    param(
        [string]$Prefix,
        [string]$Root,
        [string]$IndexHtml,
        [string]$CssFile
    )

    if (-not (Test-UrlAcl -Prefix $Prefix)) {
        throw "No URL ACL for '$Prefix'. Run elevated once: Ensure‑UrlAcl -Prefix '$Prefix'"
    }

    $script:StopEvent = [Threading.ManualResetEvent]::new($false)
    $subs = [System.Collections.Generic.List[System.IDisposable]]::new()

    $onCancel = [ConsoleCancelEventHandler]{
        param($s,$a) $a.Cancel = $true; $script:StopEvent.Set()
    }
    [Console]::add_CancelKeyPress($onCancel)
    $exitSub = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { $script:StopEvent.Set() }
    $subs.Add($exitSub)

    $listener = [Net.HttpListener]::new()
    $listener.IgnoreWriteExceptions = $true
    $listener.Prefixes.Add($Prefix)

    if ($OpenBrowser) { Start-Process $Prefix | Out-Null }

    try {
        $listener.Start()
        Write-Host "Dashboard listening at $Prefix (Ctrl+C to stop)..." -ForegroundColor Green
        while ($listener.IsListening) {
            $async = $listener.BeginGetContext($null,$null)
            $idx = [Threading.WaitHandle]::WaitAny(@($async.AsyncWaitHandle, $script:StopEvent), 250)
            if ($idx -eq 1) { break }
            if (-not $async.IsCompleted) { continue }

            $context = $listener.EndGetContext($async)
            $req = $context.Request; $res = $context.Response

            try {
                switch -Regex ($req.RawUrl) {
                    '^/$' {
                        $bytes = [IO.File]::ReadAllBytes($IndexHtml)
                        $res.ContentType = 'text/html; charset=utf-8'; $res.StatusCode=200
                        $res.ContentLength64 = $bytes.Length
                        $res.OutputStream.Write($bytes,0,$bytes.Length)
                        $res.OutputStream.Flush()
                        break
                    }
                    '^/styles\.css$' {
                        $bytes = [IO.File]::ReadAllBytes($CssFile)
                        $res.ContentType = 'text/css; charset=utf-8'; $res.StatusCode=200
                        $res.ContentLength64 = $bytes.Length
                        $res.OutputStream.Write($bytes,0,$bytes.Length)
                        $res.OutputStream.Flush()
                        break
                    }
                    '^/metrics$' {
                        $payload = Get-Metrics | ConvertTo-Json -Depth 5 -Compress
                        $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
                        $res.ContentType = 'application/json; charset=utf-8'; $res.StatusCode=200
                        $res.ContentLength64 = $bytes.Length
                        $res.OutputStream.Write($bytes,0,$bytes.Length)
                        $res.OutputStream.Flush()
                        break
                    }
                    default {
                        $rootFull = [IO.Path]::GetFullPath($Root)
                        $localReq = [IO.Path]::GetFullPath(Join-Path $Root ($req.RawUrl.TrimStart('/') -replace '/', [IO.Path]::DirectorySeparatorChar))
                        if (-not ($localReq.StartsWith($rootFull))) {
                            $res.StatusCode = 403
                            break
                        }
                        if (Test-Path -LiteralPath $localReq -PathType Leaf) {
                            $ext = [IO.Path]::GetExtension($localReq).ToLowerInvariant()
                            $ct = switch ($ext) {
                                '.js'   { 'application/javascript; charset=utf-8' }
                                '.json' { 'application/json; charset=utf-8' }
                                '.png'  { 'image/png' }
                                '.jpg' or '.jpeg' { 'image/jpeg' }
                                '.svg'  { 'image/svg+xml' }
                                default { 'application/octet-stream' }
                            }
                            $bytes = [IO.File]::ReadAllBytes($localReq)
                            $res.ContentType = $ct; $res.StatusCode=200
                            $res.ContentLength64 = $bytes.Length
                            $res.OutputStream.Write($bytes,0,$bytes.Length)
                            $res.OutputStream.Flush()
                        } else {
                            $res.StatusCode = 404
                        }
                    }
                }
            } catch {
                try {
                    $errEsc = [WebUtility]::HtmlEncode($_ | Out-String)
                    $msg = "<h1>500</h1><pre>$errEsc</pre>"
                    $bytes = [Text.Encoding]::UTF8.GetBytes($msg)
                    $res.StatusCode=500; $res.ContentType='text/html; charset=utf-8'
                    $res.ContentLength64 = $bytes.Length
                    $res.OutputStream.Write($bytes,0,$bytes.Length)
                    $res.OutputStream.Flush()
                } catch {}
            } finally {
                try { $res.OutputStream.Close() } catch {}
                $res.Close()
            }
        }
    }
    finally {
        try { if ($listener.IsListening) { $listener.Stop() }; $listener.Close() } catch {}
        Write-Host "Dashboard stopped." -ForegroundColor Cyan
        [Console]::remove_CancelKeyPress($onCancel) | Out-Null
        foreach ($s in $subs) {
            try { Unregister-Event -SourceIdentifier $s.SourceIdentifier -ErrorAction SilentlyContinue } catch {}
        }
    }
}

# URL ACL setup
Ensure-UrlAcl -Prefix $Prefix

# Entry
Start-SystemDashboardListener -Prefix $Prefix -Root $Root -IndexHtml $IndexHtml -CssFile $CssFile

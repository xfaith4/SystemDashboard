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

function Ensure-UrlAcl {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string] $Prefix)
  if (-not $IsWindows) { return }
  try {
    $exists = netsh http show urlacl | Select-String -SimpleMatch $Prefix -Quiet
    if (-not $exists) {
      $user = "$env:USERDOMAIN\$env:USERNAME"
      Start-Process -FilePath netsh -ArgumentList @('http','add','urlacl',"url=$Prefix",("user={0}" -f $user)) -Wait -WindowStyle Hidden | Out-Null
    }
  } catch {
    Write-Verbose "Ensure-UrlAcl failed: $_"
  }
}

function Remove-UrlAcl {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string] $Prefix)
  if (-not $IsWindows) { return }
  try {
    Start-Process -FilePath netsh -ArgumentList @('http','delete','urlacl',"url=$Prefix") -Wait -WindowStyle Hidden | Out-Null
  } catch {
    Write-Verbose "Remove-UrlAcl failed: $_"
  }
}

function Start-SystemDashboardListener {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string] $Prefix,
    [Parameter(Mandatory)] [string] $Root,
    [Parameter(Mandatory)] [string] $IndexHtml,
    [Parameter(Mandatory)] [string] $CssFile,
    [Parameter()] [string] $PingTarget = '1.1.1.1'
  )

  Ensure-UrlAcl -Prefix $Prefix

  $l = [System.Net.HttpListener]::new()
  $l.Prefixes.Add($Prefix)
  $l.Start()
  Write-Host "Listening on $Prefix"

  # Cache for network deltas
  $prevNet = @{}
  try {
    while ($true) {
      $context = $l.GetContext()
      $req = $context.Request
      $res = $context.Response

      if ($req.RawUrl -eq '/metrics') {
        $nowUtc = (Get-Date).ToUniversalTime().ToString('o')
        $computerName = $env:COMPUTERNAME

        # CPU
        $cpuPct = 0
        try { $cpuPct = [math]::Round((Get-Counter '\\Processor(_Total)\\% Processor Time').CounterSamples.CookedValue, 2) } catch { $cpuPct = -1 }

        # Memory
        $os = Get-CimInstance Win32_OperatingSystem
        $totalMemGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $freeMemGB  = [math]::Round($os.FreePhysicalMemory    / 1MB, 2)
        $usedMemGB  = $totalMemGB - $freeMemGB
        $memPct     = if ($totalMemGB -gt 0) { [math]::Round(($usedMemGB / $totalMemGB), 4) } else { 0 }

        # Disks
        $fixedDrives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
        $disks = $fixedDrives | ForEach-Object {
          $sizeGB = [math]::Round($_.Size      / 1GB,  2)
          $freeGB = [math]::Round($_.FreeSpace / 1GB,  2)
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
              $recvBps = [math]::Round((($stats.InboundBytes  - $prev.InboundBytes )), 2)
              $netUsage += [pscustomobject]@{ Adapter=$name; BytesSentPerSec=$sentBps; BytesRecvPerSec=$recvBps }
            }
            $prevNet[$name] = $stats
          }
        } catch {}

        # Ping latency
        $latencyMs = -1
        try {
          $ping = Test-Connection -ComputerName $PingTarget -Count 1 -ErrorAction Stop
          if ($ping) { $latencyMs = [int]($ping | Select-Object -First 1).ResponseTime }
        } catch {}

        # Top processes
        $topProcs = Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 | ForEach-Object {
          [pscustomobject]@{ Name=$_.ProcessName; CPU=$([math]::Round($_.CPU,2)); Id=$_.Id }
        }

        $metrics = [pscustomobject]@{
          Time          = $nowUtc
          ComputerName  = $computerName
          CPU           = @{ Pct = $cpuPct }
          Memory        = @{ TotalGB=$totalMemGB; FreeGB=$freeMemGB; UsedGB=$usedMemGB; Pct=$memPct }
          Disk          = $disks
          Uptime        = @{ Days=$uptime.Days; Hours=$uptime.Hours; Minutes=$uptime.Minutes }
          Events        = @{ Warnings=$warnSummary; Errors=$errSummary }
          Network       = @{ Usage=$netUsage; LatencyMs=$latencyMs }
          Processes     = $topProcs
        }

        $json = $metrics | ConvertTo-Json -Depth 5
        $buf  = [Text.Encoding]::UTF8.GetBytes($json)
        $res.ContentType = 'application/json'
        $res.OutputStream.Write($buf,0,$buf.Length)
        $res.Close()
        continue
      }

      # Static files
      $file = Switch ($req.RawUrl) {
        '/'           { $IndexHtml }
        '/index.html' { $IndexHtml }
        '/styles.css' { $CssFile }
        Default       { Join-Path $Root ($req.RawUrl.TrimStart('/')) }
      }
      if (Test-Path $file) {
        $bytes = [IO.File]::ReadAllBytes($file)
        $res.ContentType = if ($file -like '*.css') { 'text/css' } else { 'text/html' }
        $res.OutputStream.Write($bytes,0,$bytes.Length)
      } else {
        $res.StatusCode = 404
        $res.StatusDescription = 'Not Found'
      }
      $res.Close()
    }
  } finally {
    try { $l.Stop(); $l.Close() } catch {}
  }
}

Export-ModuleMember -Function Start-SystemDashboardListener, Ensure-UrlAcl, Remove-UrlAcl
### END FILE: SystemDashboard Listener


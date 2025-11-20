<# 
.SYNOPSIS
Snapshot your PC’s health into a concise JSON + text report with OK/Warn/Critical statuses.

.DESCRIPTION
- Pure PowerShell (no installs) with optional hooks:
  * NVIDIA: uses nvidia-smi if found in PATH.
  * SMART: uses smartctl.exe if found (smartmontools).
  * HWiNFO: ingests latest CSV log row if you’ve enabled sensor logging.
- Outputs: SystemHealth-Latest.json, SystemHealth-Latest.txt, and appends to SystemHealth-History.jsonl.

.NOTES
- Tested on PowerShell 7+ and Windows PowerShell 5.1.
- Inline comments kept practical and direct.
#>

[CmdletBinding()]
param(
    # Where to write reports
    [string]$OutDir = "$env:ProgramData\SystemState",

    # If true, attempt to call 'smartctl.exe' for each physical disk
    [switch]$IncludeSmart,

    # If true, try to read most recent HWiNFO CSV from default logs folder
    [switch]$IncludeHwinfo
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Helpers -----------------------------------------------------------------

function New-DirIfMissing {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Add-Status {
    <# Maintain worst-severity across checks. Order: OK < Warn < Critical. #>
    param(
        [ValidateSet('OK','Warn','Critical')][string]$Current,
        [ValidateSet('OK','Warn','Critical')][string]$Incoming
    )
    $order = @{ OK = 0; Warn = 1; Critical = 2 }
    if ($order[$Incoming] -gt $order[$Current]) { $Incoming } else { $Current }
}

function Get-ShortCPUUtil {
    <# Lightweight CPU util (3 samples x 500ms). #>
    $vals = for ($i=0; $i -lt 3; $i++) {
        (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue
        Start-Sleep -Milliseconds 500
    }
    [math]::Round(($vals | Measure-Object -Average).Average,1)
}

function Get-NvidiaInfo {
    <# Query nvidia-smi if present. #>
    try {
        $smi = Get-Command 'nvidia-smi' -ErrorAction Stop
        $csv = & $smi.Source --query-gpu=name,temperature.gpu,utilization.gpu,memory.total,memory.used,clocks.gr --format=csv,noheader,nounits
        $parts = $csv -split ',\s*'
        [pscustomobject]@{
            Name        = $parts[0]
            TempC       = [int]$parts[1]
            UtilPercent = [int]$parts[2]
            MemTotalMB  = [int]$parts[3]
            MemUsedMB   = [int]$parts[4]
            CoreClockMHz= [int]$parts[5]
        }
    } catch { $null }
}

function Get-OSInfo {
    $os   = Get-CimInstance Win32_OperatingSystem
    $cs   = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $tpm  = Get-CimInstance -Namespace root\cimv2\security\microsofttpm -Class Win32_Tpm -ErrorAction SilentlyContinue
    [pscustomobject]@{
        ComputerName   = $env:COMPUTERNAME
        UserName       = $env:UserName
        UptimeHours    = [math]::Round((New-TimeSpan -Start $os.LastBootUpTime -End (Get-Date)).TotalHours,1)
        OS             = "$($os.Caption) (Build $($os.BuildNumber))"
        BIOSVersion    = ($bios.SMBIOSBIOSVersion)
        SecureBoot     = (Confirm-SecureBootUEFI -ErrorAction SilentlyContinue)
        TPMPresent     = [bool]$tpm
        TotalRAMGB     = [math]::Round($cs.TotalPhysicalMemory/1GB,1)
    }
}

function Get-CPUInfo {
    $cpu = Get-CimInstance Win32_Processor
    $util = Get-ShortCPUUtil
    [pscustomobject]@{
        Name         = $cpu.Name.Trim()
        Cores        = $cpu.NumberOfCores
        Logical      = $cpu.NumberOfLogicalProcessors
        BaseMHz      = [int]($cpu.MaxClockSpeed)
        CurrentMHz   = [int]((Get-Counter '\Processor Information(_Total)\Processor Frequency').CounterSamples.CookedValue)
        UtilPercent  = $util
    }
}

function Get-MemoryInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    $totalMB = [math]::Round($os.TotalVisibleMemorySize/1024,1)
    $freeMB  = [math]::Round($os.FreePhysicalMemory/1024,1)
    $usedPct = [math]::Round((($totalMB-$freeMB)/$totalMB)*100,1)
    $commitPct = [math]::Round(($os.TotalVirtualMemorySize - $os.FreeVirtualMemory)/$os.TotalVirtualMemorySize*100,1)
    [pscustomobject]@{
        TotalGB       = [math]::Round($totalMB/1024,1)
        UsedPercent   = $usedPct
        CommitPercent = $commitPct
    }
}

function Get-VolumeHealth {
    <#
    .SYNOPSIS
    Return per-volume free space with OK/Warn/Critical status.
    #>
    [CmdletBinding()]
    param(
        [int]$WarnPercent = 15,
        [int]$CriticalPercent = 10,
        [string]$ExportJson
    )

    $rows = @()

    Get-Volume |
      Where-Object {
          $_.DriveLetter -and                  # only lettered volumes
          $_.DriveType -eq 'Fixed' -and        # skip CD/USB/etc.
          $_.Size -gt 0                        # avoid divide-by-zero
      } |
      ForEach-Object {
          # Label normalization — prefer FileSystemLabel, else FriendlyName, else partition metadata
          $label = if ($_.PSObject.Properties['FileSystemLabel'] -and $_.FileSystemLabel) {
                       $_.FileSystemLabel
                   } elseif ($_.PSObject.Properties['FriendlyName'] -and $_.FriendlyName) {
                       $_.FriendlyName
                   } else {
                       (Get-Partition -DriveLetter $_.DriveLetter -ErrorAction SilentlyContinue |
                           Select-Object -ExpandProperty FriendlyName -ErrorAction SilentlyContinue) ?? ''
                   }

          $sizeBytes = [double]$_.Size
          $freePct   = [math]::Round(($_.SizeRemaining / $sizeBytes) * 100, 1)

          $status = if ($freePct -lt $CriticalPercent) { 'Critical' }
                    elseif ($freePct -lt $WarnPercent) { 'Warn' }
                    else { 'OK' }

          $rows += [pscustomobject]@{
              Drive       = ($_.DriveLetter + ':')
              Label       = $label
              FileSystem  = $_.FileSystemType
              SizeGB      = [math]::Round($sizeBytes/1GB,1)
              FreeGB      = [math]::Round($_.SizeRemaining/1GB,1)
              FreePercent = $freePct
              Status      = $status
          }
      }

    if ($PSBoundParameters.ContainsKey('ExportJson')) {
        $dir = Split-Path -Parent -Path $ExportJson
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $rows | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $ExportJson
        try { $resolved = (Resolve-Path -LiteralPath $ExportJson).Path } catch { $resolved = $ExportJson }
        Write-Host ("[Get-VolumeHealth] JSON written to: {0}" -f $resolved) -ForegroundColor Cyan
    }

    # Colorized console summary
    $rows | Sort-Object Drive | ForEach-Object {
        switch ($_.Status) {
            'OK'       { $color = 'Green' }
            'Warn'     { $color = 'Yellow' }
            'Critical' { $color = 'Red' }
        }
        "{0,-3} {1,-22} {2,-6} Size:{3,7}GB  Free:{4,7}GB  ({5,5}%)  [{6}]" -f `
            $_.Drive, ($_.Label ?? ''), $_.FileSystem, $_.SizeGB, $_.FreeGB, $_.FreePercent, $_.Status |
            Write-Host -ForegroundColor $color
    }

    return $rows
}

function Get-DiskReliability {
    <# StorageReliabilityCounters for drives that expose them. #>
    $counters = @()
    try { $counters = Get-StorageReliabilityCounter -ErrorAction Stop } catch { }
    $map = @{}
    foreach ($c in $counters) {
        $map[$c.DeviceId] = [pscustomobject]@{
            WearPercent      = $c.PercentUsed
            ReadErrorsTotal  = $c.ReadErrorsTotal
            WriteErrorsTotal = $c.WriteErrorsTotal
            TemperatureC     = $c.Temperature
            PowerOnHours     = $c.PowerOnHours
            MediaErrors      = $c.MediaAndDataIntegrityErrors
        }
    }
    $map
}

function Get-SMARTInfo {
    <# Use smartctl.exe if present and -IncludeSmart is set. #>
    if (-not $IncludeSmart) { return @{} }
    $smart = Get-Command smartctl.exe -ErrorAction SilentlyContinue
    if (-not $smart) { return @{} }

    $info = @{}
    Get-PhysicalDisk | ForEach-Object {
        $pd = $_
        $number = ($pd.DeviceId -replace '[^\d]','')
        if (-not $number) { return }
        $json = & $smart.Source -a "\\.\PhysicalDrive$number" --json 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $json) { return }
        try {
            $obj = $json | ConvertFrom-Json -AsHashtable
            $wear = $null
            if ($obj.nvme_smart_health_information_log.percent_used) { $wear = $obj.nvme_smart_health_information_log.percent_used }
            elseif ($obj.smart_status) { $wear = $obj.smart_status.passed ? 0 : 100 }
            $info[$pd.FriendlyName] = [pscustomobject]@{
                Model       = $obj.model_name
                Serial      = $obj.serial_number
                WearPercent = $wear
                TempC       = $obj.temperature.current
                Realloc     = $obj.ata_smart_attributes.table | Where-Object {$_.name -eq 'Reallocated_Sector_Ct'} | Select-Object -ExpandProperty raw.value -ErrorAction Ignore
                StatusOK    = $obj.smart_status.passed
            }
        } catch { }
    }
    $info
}

function Get-EventsHealth {
    <#
      Count nasty stuff in last 24h: Kernel-Power (41), Disk, WHEA-Logger, BugCheck.
      Fix: force-array with @() so .Count always exists.
    #>
    $since = (Get-Date).AddDays(-1)

    $filter = @{
        LogName   = @('System','Application')
        StartTime = $since
        Level     = 1,2,3   # Critical, Error, Warning
    }

    # Always make this an array (even if 0 or 1 events)
    $events = @( Get-WinEvent -FilterHashtable $filter -ErrorAction SilentlyContinue )

    $kp41   = @( $events | Where-Object { $_.Id -eq 41 -and $_.ProviderName -eq 'Microsoft-Windows-Kernel-Power' } ).Count
    $disk   = @( $events | Where-Object { $_.ProviderName -match '^(Disk|storahci|stornvme|iaStor|nvme)' } ).Count
    $whea   = @( $events | Where-Object { $_.ProviderName -eq 'Microsoft-Windows-WHEA-Logger' } ).Count
    $bugchk = @( $events | Where-Object { $_.ProviderName -eq 'Microsoft-Windows-WER-SystemErrorReporting' -or $_.Id -eq 1001 } ).Count
    $errs   = @( $events | Where-Object { $_.LevelDisplayName -in 'Critical','Error' } ).Count
    $warns  = @( $events | Where-Object { $_.LevelDisplayName -eq 'Warning' } ).Count

    [pscustomobject]@{
        SinceHours    = 24
        KernelPower41 = $kp41
        DiskErrors    = $disk
        WHEA          = $whea
        BugChecks     = $bugchk
        TotalErrors   = $errs
        TotalWarnings = $warns
    }
}


function Get-ReliabilityIndex {
    <# Windows Reliability Monitor daily StabilityIndex (1..10). #>
    $metrics = Get-CimInstance -Namespace root\cimv2 -Class Win32_ReliabilityStabilityMetrics -ErrorAction SilentlyContinue
    if (-not $metrics) { return $null }
    $today = ($metrics | Sort-Object -Property TimeGenerated -Descending | Select-Object -First 1).SystemStabilityIndex
    $start = (Get-Date).AddDays(-14)
    $recent = $metrics | Where-Object { $_.TimeGenerated -ge $start }
    $avg = if ($recent) { [math]::Round(($recent.SystemStabilityIndex | Measure-Object -Average).Average,2) } else { $null }
    [pscustomobject]@{
        Today = [math]::Round($today,2)
        Avg14Days = $avg
    }
}

function Read-HWiNFOCsvLatest {
    <# Parse latest HWiNFO CSV last row for temps (if -IncludeHwinfo). #>
    if (-not $IncludeHwinfo) { return $null }
    $default = Join-Path $env:PUBLIC 'Documents\HWiNFO'
    if (-not (Test-Path $default)) { return $null }
    $csv = Get-ChildItem $default -Filter *.csv -Recurse | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $csv) { return $null }
    try {
        $lines = Get-Content -LiteralPath $csv.FullName -Tail 2
        $header = (Get-Content -LiteralPath $csv.FullName -TotalCount 1)
        $cols = $header.Split(',')
        $vals = ($lines | Select-Object -Last 1).Split(',')
        $map = @{}
        for ($i=0; $i -lt [math]::Min($cols.Count,$vals.Count); $i++) { $map[$cols[$i]] = $vals[$i] }
        $cpuTemp = ($map.Keys | Where-Object { $_ -match '(?i)cpu\s*package.*\[\s*°?C\]' } | Select-Object -First 1)
        $gpuTemp = ($map.Keys | Where-Object { $_ -match '(?i)gpu.*temperature.*\[\s*°?C\]' } | Select-Object -First 1)
        [pscustomobject]@{
            CpuTempC = if ($cpuTemp) { [int]$map[$cpuTemp] } else { $null }
            GpuTempC = if ($gpuTemp) { [int]$map[$gpuTemp] } else { $null }
            Source   = $csv.FullName
        }
    } catch { $null }
}

function Resolve-SafePath {
    param([Parameter(Mandatory)][string]$Path)
    try { (Resolve-Path -LiteralPath $Path).Path } catch { $Path }
}

# --- Collect -----------------------------------------------------------------

New-DirIfMissing -Path $OutDir

$overall = 'OK'
$advice  = New-Object System.Collections.Generic.List[string]

$os      = Get-OSInfo
$cpu     = Get-CPUInfo
$mem     = Get-MemoryInfo
$vols    = Get-VolumeHealth
$reliab  = Get-ReliabilityIndex
$events  = Get-EventsHealth
$gpu     = Get-NvidiaInfo
$diskRel = Get-DiskReliability
$smart   = Get-SMARTInfo
$hwcsv   = Read-HWiNFOCsvLatest

# --- Evaluate statuses -------------------------------------------------------

foreach ($v in $vols) {
    $overall = Add-Status $overall $v.Status
    if ($v.Status -eq 'Warn')     { $advice.Add("Drive $($v.Drive) is low on space ($($v.FreePercent)% free). Aim for ≥15%.") }
    if ($v.Status -eq 'Critical') { $advice.Add("Drive $($v.Drive) is CRITICAL on space ($($v.FreePercent)% free). Free space now or move data.") }
}

if ($mem.UsedPercent -ge 85) { $overall = Add-Status $overall 'Warn'; $advice.Add("High RAM usage ($($mem.UsedPercent)%). Consider closing heavy apps or adding RAM.") }
if ($cpu.UtilPercent -ge 90) { $overall = Add-Status $overall 'Warn'; $advice.Add("Sustained high CPU load ($($cpu.UtilPercent)%). Check background tasks.") }

if ($events.KernelPower41 -gt 0 -or $events.BugChecks -gt 0) { $overall = Add-Status $overall 'Warn'; $advice.Add("Recent unexpected shutdowns/bugchecks detected. Review Event Viewer.") }
if ($events.DiskErrors    -gt 0)                              { $overall = Add-Status $overall 'Critical'; $advice.Add("Disk-related errors in last 24h. Back up and inspect SMART/connection health.") }
if ($events.WHEA          -gt 0)                              { $overall = Add-Status $overall 'Warn'; $advice.Add("Hardware error reports (WHEA). Could be CPU/RAM/PCIe instability; monitor.") }

if ($hwcsv -and $hwcsv.CpuTempC -ge 90) { $overall = Add-Status $overall 'Critical'; $advice.Add("CPU temperature $($hwcsv.CpuTempC)°C. Check cooler/fans/paste.") }
if ($gpu   -and $gpu.TempC     -ge 85)  { $overall = Add-Status $overall 'Warn';     $advice.Add("GPU temperature $($gpu.TempC)°C. Improve airflow or fan curve.") }

if ($reliab -and $reliab.Today -lt 5) { $overall = Add-Status $overall 'Warn'; $advice.Add("Low Reliability Index today ($($reliab.Today)). Inspect recent crashes/installs.") }

# --- Build object ------------------------------------------------------------

$report = [pscustomobject]@{
    TimestampUTC = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
    Overall      = $overall
    Summary      = if ($advice.Count) { $advice } else { @('System looks healthy. No action required.') }
    OS           = $os
    CPU          = $cpu
    Memory       = $mem
    GPU          = $gpu
    Volumes      = $vols
    DiskReliability = $diskRel.GetEnumerator() | ForEach-Object { @{ DeviceId = $_.Key; Data = $_.Value } }
    SMART        = $smart
    Events24h    = $events
    Reliability  = $reliab
    TempsFromHWiNFO = $hwcsv
}

# --- Persist (single, authoritative) -----------------------------------------

$jsonPath = Join-Path $OutDir 'SystemHealth-Latest.json'
$txtPath  = Join-Path $OutDir 'SystemHealth-Latest.txt'
$histPath = Join-Path $OutDir 'SystemHealth-History.jsonl'

# JSON
$report | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $jsonPath -Encoding UTF8

# Text summary
$lines = @()
$lines += "Overall: $($report.Overall)"
$lines += "Uptime:  $($os.UptimeHours) h | OS: $($os.OS) | RAM: $($mem.UsedPercent)% used"
if ($gpu) { $lines += "GPU: $($gpu.Name) | Util: $($gpu.UtilPercent)% | Temp: $($gpu.TempC)°C" }
if ($hwcsv -and $hwcsv.CpuTempC) { $lines += "CPU Temp (HWiNFO): $($hwcsv.CpuTempC)°C" }
$lines += "Volumes:"
$lines += ($report.Volumes | Sort-Object Drive | ForEach-Object { "  $($_.Drive)  Free: $($_.FreeGB) GB ($($_.FreePercent)%)  [$($_.Status)]" })
$lines += "Events (24h): KernelPower41=$($events.KernelPower41)  DiskErr=$($events.DiskErrors)  WHEA=$($events.WHEA)  BugChecks=$($events.BugChecks)"
$lines += ""
$lines += "Advice:"
$lines += ($report.Summary | ForEach-Object { "  - $_" })
$lines -join [Environment]::NewLine | Out-File -LiteralPath $txtPath -Encoding UTF8

# History (jsonl)
($report | ConvertTo-Json -Depth 6 -Compress) | Add-Content -LiteralPath $histPath

# Resolve to absolute paths and print loudly
$resolved = [pscustomobject]@{
    OutDir   = (Resolve-SafePath $OutDir)
    JsonPath = (Resolve-SafePath $jsonPath)
    TxtPath  = (Resolve-SafePath $txtPath)
    HistPath = (Resolve-SafePath $histPath)
}

Write-Host "Wrote:" -ForegroundColor Green
Write-Host ("  JSON : {0}" -f $resolved.JsonPath) -ForegroundColor Cyan
Write-Host ("  Text : {0}" -f $resolved.TxtPath)  -ForegroundColor Cyan
Write-Host ("  Hist : {0}" -f $resolved.HistPath) -ForegroundColor Cyan

# Emit paths so callers can capture them
$resolved

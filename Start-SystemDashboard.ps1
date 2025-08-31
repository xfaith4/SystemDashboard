
#requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Port = 8892
$Prefix = "http://localhost:$Port/"
$Root = "F:\Logs\wwwroot"
$IndexHtml = Join-Path $Root 'index.html'
$CssFile   = Join-Path $Root 'styles.css'

$l = [System.Net.HttpListener]::new()
$l.Prefixes.Add($Prefix)
$l.Start()
Write-Host "Listening on $Prefix"

while ($true) {
    $c = $l.GetContext()
    $r = $c.Request
    $s = $c.Response

    if ($r.RawUrl -eq '/metrics') {
        $cpu = [math]::Round((Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue,2)
        $os = Get-CimInstance Win32_OperatingSystem
        $tGB = [math]::Round($os.TotalVisibleMemorySize/1MB,2)
        $fGB = [math]::Round($os.FreePhysicalMemory/1MB,2)
        $uGB = $tGB - $fGB
        $mPct = $uGB / $tGB

        $fixed = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
        $disks = foreach ($d in $fixed) {
            $t = [math]::Round($d.Size/1GB,2)
            $f = [math]::Round($d.FreeSpace/1GB,2)
            [pscustomobject]@{
                L = $d.DeviceID.TrimEnd(':')
                T = $t
                U = ($t - $f)
                P = ($t - $f) / $t
            }
        }

        $since = (Get-Date).AddHours(-1)
        $warns = Get-WinEvent -FilterHashtable @{LogName=@('System','Application');Level=3;StartTime=$since} -ErrorAction SilentlyContinue
        $errs  = Get-WinEvent -FilterHashtable @{LogName=@('System','Application');Level=2;StartTime=$since} -ErrorAction SilentlyContinue

        $warnSummary = $warns | Group-Object ProviderName | ForEach-Object {
            [pscustomobject]@{ Source = $_.Name; Count = $_.Count }
        }
        $errSummary = $errs | Group-Object ProviderName | ForEach-Object {
            [pscustomobject]@{ Source = $_.Name; Count = $_.Count }
        }

        $metrics = [pscustomobject]@{
            Time = (Get-Date).ToUniversalTime().ToString("o")
            Name = $env:COMPUTERNAME
            CPU  = @{Pct = $cpu}
            Mem  = @{T=$tGB; F=$fGB; U=$uGB; P=$mPct}
            Disk = $disks
            Events = @{Warnings = $warnSummary; Errors = $errSummary}
        }

        $json = $metrics | ConvertTo-Json -Depth 4
        $buf = [System.Text.Encoding]::UTF8.GetBytes($json)
        $s.ContentType = 'application/json'
        $s.OutputStream.Write($buf,0,$buf.Length)
        $s.Close()
        continue
    }

    $path = Join-Path $Root ($r.RawUrl.TrimStart('/'))
    if ($r.RawUrl -eq '/' -or $r.RawUrl -eq '/index.html') { $path = $IndexHtml }
    elseif ($r.RawUrl -eq '/styles.css') { $path = $CssFile }

    if (Test-Path $path) {
        $b = [System.IO.File]::ReadAllBytes($path)
        $s.ContentType = if ($path -like '*.css') {'text/css'} else {'text/html'}
        $s.OutputStream.Write($b,0,$b.Length)
    } else {
        $s.StatusCode = 404
        $s.StatusDescription = 'Not Found'
    }

    $s.Close()
}

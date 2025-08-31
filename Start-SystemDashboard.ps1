### BEGIN FILE
#requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ----- CONFIG -----
$Port = 8892
$Prefix = "http://localhost:$Port/"
$Root = "F:\Logs\wwwroot"    # <-- adjust to your wwwroot folder
$IndexHtml = Join-Path $Root 'index.html'
$CssFile   = Join-Path $Root 'styles.css'


# ----- Start HTTP listener -----
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($Prefix)
$listener.Start()
Write-Host "Listening on $Prefix"

while ($true) {
    # Wait for request
    $ctx = $listener.GetContext()

    $req  = $ctx.Request
    $resp = $ctx.Response

    if ($req.RawUrl -eq '/metrics') {
        # --- COLLECT METRICS ---
        # CPU
        $cpuPct = [math]::Round((Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue,2)
        # Memory
        $os = Get-CimInstance Win32_OperatingSystem
        $totalGB = [math]::Round($os.TotalVisibleMemorySize/1MB,2)
        $freeGB  = [math]::Round($os.FreePhysicalMemory/1MB,2)
        $usedGB  = $totalGB - $freeGB
        $memPct  = $usedGB / $totalGB
        # Disks
        $fixed = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
        $letters = $fixed | ForEach-Object { $_.DeviceID.TrimEnd(':') }
        $disks = foreach ($L in $letters) {
            $d = $fixed | Where DeviceID -eq "$($L):"
            $t = [math]::Round($d.Size/1GB,2)
            $f = [math]::Round($d.FreeSpace/1GB,2)
            [pscustomobject]@{
                Letter  = $L
                TotalGB = $t
                UsedGB  = ($t - $f)
                UsedPct =($t - $f) / $t
            }
        }
        # Events (last 1h)
        $since = (Get-Date).AddHours(-1)
        $warns=@(); $errs=@()
        $warns = Get-WinEvent -FilterHashtable @{LogName=@('System','Application');Level=3;StartTime=$since} -ErrorAction SilentlyContinue
        $errs  = Get-WinEvent -FilterHashtable @{LogName=@('System','Application');Level=2;StartTime=$since} -ErrorAction SilentlyContinue
        #$warnCount = $warns.count
        #$errCount  = $errs.count

        # Build PSCustomObject
        $metrics = [pscustomobject]@{
            Timestamp    = (Get-Date).ToUniversalTime().ToString("o")
            ComputerName = $env:COMPUTERNAME
            CPU          = [pscustomobject]@{ UsagePct = $cpuPct }
            Memory       = [pscustomobject]@{ TotalGB=$totalGB; FreeGB=$freeGB; UsedGB=$usedGB; UsedPct=$memPct }
            Disks        = $disks
            #Events       = [pscustomobject]@{ LastHourWarnings=$warnCount; LastHourErrors=$errCount }
        }

        # Return JSON
        $json = $metrics | ConvertTo-Json -Depth 4
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
        $resp.ContentType = 'application/json'
        $resp.OutputStream.Write($buffer,0,$buffer.Length)
        $resp.Close()
        continue
    }

    # --- Serve static files ---
    $localPath = Join-Path $Root ($req.RawUrl.TrimStart('/'))
    if ($req.RawUrl -eq '/' -or $req.RawUrl -eq '/index.html') { $localPath = $IndexHtml }
    elseif ($req.RawUrl -eq '/styles.css') { $localPath = $CssFile }

    if (Test-Path $localPath) {
        $bytes = [System.IO.File]::ReadAllBytes($localPath)
        $resp.ContentType = if ($localPath -like '*.css') {'text/css'} else {'text/html'}
        $resp.OutputStream.Write($bytes,0,$bytes.Length)
    } else {
        $resp.StatusCode = 404
        $resp.StatusDescription = 'Not Found'
    }

    $resp.Close()
}
### END FILE

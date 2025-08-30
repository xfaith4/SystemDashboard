#requires -Version 7
<#
.SYNOPSIS
  A robust and flexible PowerShell system dashboard serving live health metrics via HTTP.

.DESCRIPTION
  - Auto-selects available port or uses specified port unless in use.
  - Resolves working directory dynamically.
  - Logs activity to file.
  - Handles Ctrl+C gracefully if supported.
  - HTTP back-end is bound explicitly to 127.0.0.1.
  - Ready for headless contexts (e.g., CI, services).

.PARAMETER Port
  Preferred port to use (0 = auto-select).

.PARAMETER OpenBrowser
  Switch to automatically open the dashboard in default browser.
#>

param(
    [int]$Port = 0,
    [switch]$OpenBrowser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Resolve script directory reliably ---
$ScriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$Root      = Join-Path $ScriptDir 'wwwroot'
$IndexHtml = Join-Path $Root 'index.html'
$CssFile   = Join-Path $Root 'styles.css'

# --- Logging setup ---
$LogDir  = Join-Path $env:LOCALAPPDATA 'SystemDashboard'
$LogFile = Join-Path $LogDir 'dashboard.log'
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$ts][$Level] $Message"
    Add-Content -Path $LogFile -Value $line
    Write-Host $line
}

Write-Log "Script starting from $ScriptDir"

# --- Port availability ---
function Test-PortAvailable {
    param([int]$Port)
    try {
        $tcp = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
        $tcp.Start(); $tcp.Stop()
        return $true
    } catch { return $false }
}

function Find-AvailablePort {
    param($Start = 8899, $End = 8999)
    for ($p = $Start; $p -le $End; $p++) {
        if (Test-PortAvailable -Port $p) {
            return $p
        }
    }
    throw "No available ports between $Start and $End."
}

if ($Port -le 0) {
    Write-Log "Auto-selecting port..."
    $Port = Find-AvailablePort
} elseif (-not (Test-PortAvailable -Port $Port)) {
    throw "Port $Port already in use."
}

$Prefix = "http://127.0.0.1:$Port/"
Write-Log "Using Prefix: $Prefix"

# --- Ensure web assets are ready ---
try {
    if (-not (Test-Path $IndexHtml)) {
        Write-Warning "Missing index.html at $IndexHtml"
    }
    if (-not (Test-Path $CssFile)) {
        Write-Warning "Missing styles.css at $CssFile"
    }
    Write-Log "Web assets confirmed."
} catch {
    Write-Log "Failed checking web assets: $_" -Level "ERROR"
    throw
}

# --- HTTP listener ---
function Start-SystemDashboardListener {
    Write-Log "Starting listener on $Prefix..."
    $script:StopEvent = [System.Threading.ManualResetEvent]::new($false)
    $onCancel = $null

    try {
        $listener = [System.Net.HttpListener]::new()
        $listener.Prefixes.Add($Prefix)
        $listener.Start()

        if ($OpenBrowser) {
            Start-Process $Prefix
        }

        # Safe Ctrl+C handling
        try {
            if ($Host.UI.RawUI.KeyAvailable -or $Host.Name -ne 'ServerRemoteHost') {
                $onCancel = [ConsoleCancelEventHandler]{
                    param($sender, $args)
                    $args.Cancel = $true
                    $script:StopEvent.Set()
                }
                [Console]::add_CancelKeyPress($onCancel)
            }
        } catch {
            Write-Log "Could not register Ctrl+C handler (non-interactive host)" -Level "WARN"
        }

        Write-Log "Dashboard listening. Press Ctrl+C to stop."
        Write-Host "Dashboard listening at $Prefix (Ctrl+C to stop)..." -ForegroundColor Green

        while ($listener.IsListening) {
            $async = $listener.BeginGetContext($null, $null)
            $index = [System.Threading.WaitHandle]::WaitAny(@($async.AsyncWaitHandle, $script:StopEvent), 250)
            if ($index -eq 1) { break }
            if (-not $async.IsCompleted) { continue }

            $context = $listener.EndGetContext($async)
            $req = $context.Request
            $res = $context.Response
            Write-Log "[$($req.HttpMethod)] $($req.RawUrl)"

            try {
                switch -Regex ($req.RawUrl) {
                    '^/$' {
                        $res.ContentType = 'text/html; charset=utf-8'
                        $b = [IO.File]::ReadAllBytes($IndexHtml)
                        $res.ContentLength64 = $b.Length
                        $res.StatusCode = 200
                        $res.OutputStream.Write($b, 0, $b.Length)
                        $res.OutputStream.Flush()
                        break
                    }

                    '^/styles\.css$' {
                        $res.ContentType = 'text/css; charset=utf-8'
                        $b = [IO.File]::ReadAllBytes($CssFile)
                        $res.ContentLength64 = $b.Length
                        $res.StatusCode = 200
                        $res.OutputStream.Write($b, 0, $b.Length)
                        $res.OutputStream.Flush()
                        break
                    }

                    '^/metrics$' {
                        if (-not (Get-Command Get-Metrics -ErrorAction SilentlyContinue)) {
                            throw "Get-Metrics not implemented in this version"
                        }
                        $metrics = Get-Metrics
                        $json = $metrics | ConvertTo-Json -Depth 5 -Compress
                        $b = [Text.Encoding]::UTF8.GetBytes($json)
                        $res.ContentType = 'application/json; charset=utf-8'
                        $res.ContentLength64 = $b.Length
                        $res.StatusCode = 200
                        $res.OutputStream.Write($b, 0, $b.Length)
                        $res.OutputStream.Flush()
                        break
                    }

                    default {
                        $reqPath  = $req.RawUrl.TrimStart('/') -replace '/', [IO.Path]::DirectorySeparatorChar
                        $fullPath = [IO.Path]::GetFullPath((Join-Path $Root $reqPath))
                        $basePath = [IO.Path]::GetFullPath($Root)

                        if ($fullPath.StartsWith($basePath) -and (Test-Path $fullPath -PathType Leaf)) {
                            $ext = [IO.Path]::GetExtension($fullPath).ToLowerInvariant()
                            $type = switch ($ext) {
                                '.js'   { 'application/javascript' }
                                '.css'  { 'text/css' }
                                '.json' { 'application/json' }
                                '.html' { 'text/html' }
                                default { 'application/octet-stream' }
                            }
                            $b = [IO.File]::ReadAllBytes($fullPath)
                            $res.ContentType = $type
                            $res.StatusCode = 200
                            $res.ContentLength64 = $b.Length
                            $res.OutputStream.Write($b, 0, $b.Length)
                            $res.OutputStream.Flush()
                        } else {
                            $res.StatusCode = 404
                            $msg = "404 Not Found: $($req.RawUrl)"
                            $b = [Text.Encoding]::UTF8.GetBytes($msg)
                            $res.ContentType = 'text/plain'
                            $res.ContentLength64 = $b.Length
                            $res.OutputStream.Write($b, 0, $b.Length)
                        }
                    }
                }
            } catch {
                $errText = $_ | Out-String
                $errMsg = [WebUtility]::HtmlEncode($errText)
                Write-Log "500 error: $errText" -Level "ERROR"
                $html = "<h1>500 Internal Server Error</h1><pre>$errMsg</pre>"
                $b = [Text.Encoding]::UTF8.GetBytes($html)
                $res.StatusCode = 500
                $res.ContentType = 'text/html'
                $res.ContentLength64 = $b.Length
                $res.OutputStream.Write($b, 0, $b.Length)
            } finally {
                try { $res.OutputStream.Close() } catch {}
                $res.Close()
            }
        }

    } finally {
        try {
            if ($listener.IsListening) { $listener.Stop() }
            $listener.Close()
        } catch {}
        if ($onCancel) { try { [Console]::remove_CancelKeyPress($onCancel) } catch {} }
        Write-Log "Dashboard stopped."
        Write-Host "Dashboard stopped." -ForegroundColor Cyan
    }
}

# --- Entry ---
Start-SystemDashboardListener

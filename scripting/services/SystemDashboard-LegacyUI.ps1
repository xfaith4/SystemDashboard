# SystemDashboard Legacy UI Service
# Runs the legacy PowerShell dashboard listener as a persistent process

param(
    [string]$Action = "start",
    [string]$ConfigPath = (Join-Path $PSScriptRoot "..\..\config.json")
)

$RootPath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$LogDir = Join-Path $RootPath "var\log"
$RunDir = Join-Path $RootPath "var\run"
$LogFile = Join-Path $LogDir "dashboard-ui.log"
$PidFile = Join-Path $RunDir "dashboard-legacy.pid"
$PrefixFile = Join-Path $RunDir "dashboard-legacy.prefix"
$script:ActivePrefix = $null

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
if (-not (Test-Path $RunDir)) {
    New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
}

function Write-ServiceLog {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $LogFile -Append -Encoding utf8
    Write-Host "$timestamp - $Message"
}

function Resolve-ConfiguredPrefix {
    param([string]$ConfigPath)

    $defaultPrefix = 'http://localhost:15000/'
    if (-not $ConfigPath -or -not (Test-Path -LiteralPath $ConfigPath)) {
        return $defaultPrefix
    }

    try {
        $cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        if ($cfg.Prefix) {
            return [string]$cfg.Prefix
        }
    } catch {
        return $defaultPrefix
    }

    return $defaultPrefix
}

function Get-PrefixPort {
    param([string]$Prefix)

    try {
        $uri = [System.Uri]$Prefix
        if ($uri.Port -gt 0) {
            return $uri.Port
        }
    } catch {
        # ignore
    }

    return 15000
}

function Get-PrefixCandidates {
    param(
        [string]$Prefix,
        [int]$MaxPorts = 10
    )

    try {
        $uri = [System.Uri]$Prefix
        $scheme = $uri.Scheme
        $hostname = $uri.Host
        $port = if ($uri.Port -gt 0) { $uri.Port } else { 15000 }
    } catch {
        return @($Prefix)
    }

    $candidates = @()
    for ($i = 0; $i -lt $MaxPorts; $i++) {
        $candidates += ('{0}://{1}:{2}/' -f $scheme, $hostname, ($port + $i))
    }

    return $candidates
}

function Test-PrefixHealth {
    param([string]$Prefix)

    $metricsUrl = ($Prefix.TrimEnd('/') + '/metrics')
    $appUrl = ($Prefix.TrimEnd('/') + '/app.js')
    try {
        $metricsResponse = Invoke-WebRequest -Uri $metricsUrl -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
        if ($metricsResponse.StatusCode -lt 200 -or $metricsResponse.StatusCode -ge 400) {
            return $false
        }
        $appResponse = Invoke-WebRequest -Uri $appUrl -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
        return ($appResponse.StatusCode -ge 200 -and $appResponse.StatusCode -lt 400)
    } catch {
        return $false
    }
}

function Get-DashboardProcess {
    if (-not (Test-Path $PidFile)) {
        return $null
    }
    $dashboardPid = Get-Content -LiteralPath $PidFile -ErrorAction SilentlyContinue
    if (-not $dashboardPid) { return $null }
    $proc = Get-Process -Id $dashboardPid -ErrorAction SilentlyContinue
    if (-not $proc) {
        return $null
    }

    $scriptPath = (Resolve-Path -LiteralPath $PSCommandPath).Path
    try {
        $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $dashboardPid" -ErrorAction SilentlyContinue
        $cmdLine = $processInfo.CommandLine
        if ($cmdLine -and ($cmdLine -match [regex]::Escape($scriptPath) -or $cmdLine -match 'SystemDashboard-LegacyUI\.ps1')) {
            return $proc
        }
    }
    catch {
        # Fall back to trusting the PID if we can't inspect the command line.
        return $proc
    }

    Write-ServiceLog "Stale PID file detected (PID: $dashboardPid); removing."
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    return $null
}

function Test-DashboardHealth {
    param([string]$ConfigPath)

    $prefix = Resolve-ConfiguredPrefix -ConfigPath $ConfigPath
    $candidates = Get-PrefixCandidates -Prefix $prefix
    if ($script:ActivePrefix) {
        $candidates = @($script:ActivePrefix) + ($candidates | Where-Object { $_ -ne $script:ActivePrefix })
    }

    foreach ($candidate in $candidates) {
        if (Test-PrefixHealth -Prefix $candidate) {
            if ($script:ActivePrefix -ne $candidate) {
                $script:ActivePrefix = $candidate
                try {
                    Set-Content -LiteralPath $PrefixFile -Value $candidate -Encoding ascii
                } catch {
                    # ignore logging failures
                }
                Write-ServiceLog "Detected legacy dashboard listener at $candidate"
            }
            return $true
        }
    }

    return $false
}

function Clear-UrlAclConflicts {
    param([int]$Port)

    if (-not $IsWindows) {
        return
    }
    try {
        $entries = netsh http show urlacl | Select-String -Pattern "http.*:$Port/" | ForEach-Object {
            $line = $_.Line
            if ($line -match 'Reserved URL\s*:\s*(\S+)') {
                return $Matches[1]
            }
            if ($line -match '(http[s]?://\S+)') {
                return $Matches[1]
            }
            return $null
        } | Where-Object { $_ }

        foreach ($url in ($entries | Sort-Object -Unique)) {
            Write-ServiceLog "Removing URLACL: $url"
            Start-Process -FilePath netsh -ArgumentList @('http','delete','urlacl',"url=$url") -Wait -WindowStyle Hidden | Out-Null
        }
    }
    catch {
        Write-ServiceLog "WARNING: Failed to clear URLACL conflicts: $($_.Exception.Message)"
    }
}

function Start-DashboardService {
    $existing = Get-DashboardProcess
    if ($existing) {
        if (Test-DashboardHealth -ConfigPath $ConfigPath) {
            Write-ServiceLog "Dashboard already running (PID: $($existing.Id))"
        }
        else {
            Write-ServiceLog "Stale dashboard process detected (PID: $($existing.Id)); restarting."
            Stop-Process -Id $existing.Id -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
    }

    $defaultConfig = Join-Path $RootPath "config.json"
    $resolvedConfig = $ConfigPath

    if ($resolvedConfig -and (Test-Path -LiteralPath $resolvedConfig)) {
        $resolvedConfig = (Resolve-Path -LiteralPath $resolvedConfig).Path
    } else {
        $resolvedConfig = $defaultConfig
    }

    if ($resolvedConfig -and (-not ($resolvedConfig.StartsWith($RootPath, [System.StringComparison]::OrdinalIgnoreCase)))) {
        Write-ServiceLog "WARNING: Ignoring config outside repo root: $resolvedConfig"
        $resolvedConfig = $defaultConfig
    }

    if (-not (Test-Path -LiteralPath $resolvedConfig)) {
        Write-ServiceLog "ERROR: Config not found at $resolvedConfig"
        exit 1
    }

    try {
        $cfg = Get-Content -LiteralPath $resolvedConfig -Raw | ConvertFrom-Json
        $hasDatabase = $cfg.PSObject.Properties.Name -contains 'Database'
        if (-not $hasDatabase) {
            $resolvedConfig = $defaultConfig
        }
    }
    catch {
        $resolvedConfig = $defaultConfig
    }

    if (-not (Test-Path -LiteralPath $resolvedConfig)) {
        Write-ServiceLog "ERROR: Config not found at $resolvedConfig"
        exit 1
    }

    $env:SYSTEMDASHBOARD_ROOT = Join-Path $RootPath 'wwwroot'
    $env:SYSTEMDASHBOARD_CONFIG = $resolvedConfig
    $env:SYSTEMDASHBOARD_LISTENER_LOG = Join-Path $LogDir 'dashboard-listener.log'

    $connectionFile = Join-Path $RootPath 'var\database-connection.json'
    if (Test-Path -LiteralPath $connectionFile) {
        try {
            $connectionInfo = Get-Content -LiteralPath $connectionFile -Raw | ConvertFrom-Json
            if ($connectionInfo.IngestPassword -and -not $env:SYSTEMDASHBOARD_DB_PASSWORD) {
                $env:SYSTEMDASHBOARD_DB_PASSWORD = $connectionInfo.IngestPassword
            }
            if ($connectionInfo.ReaderPassword -and -not $env:SYSTEMDASHBOARD_DB_READER_PASSWORD) {
                $env:SYSTEMDASHBOARD_DB_READER_PASSWORD = $connectionInfo.ReaderPassword
            }
        } catch {
            Write-ServiceLog "WARNING: Failed to load database secrets: $($_.Exception.Message)"
        }
    }

    $autoHealScript = Join-Path $RootPath 'scripting\auto-heal.ps1'
    if (Test-Path -LiteralPath $autoHealScript) {
        try {
            $enabled = $env:SYSTEMDASHBOARD_AUTOHEAL_ENABLED
            if (-not $enabled -or $enabled.ToLower() -notin @('0','false','no')) {
                Write-ServiceLog "Launching auto-heal check..."
                Start-Process -FilePath 'pwsh.exe' -ArgumentList @(
                    '-NoProfile',
                    '-File',
                    $autoHealScript,
                    '-ConfigPath',
                    $resolvedConfig
                ) -WindowStyle Hidden | Out-Null
            }
        } catch {
            Write-ServiceLog "WARNING: Auto-heal launch failed: $($_.Exception.Message)"
        }
    }

    Write-ServiceLog "Starting legacy dashboard listener..."
    Write-ServiceLog "Config: $resolvedConfig"

    $launcher = Join-Path $RootPath 'Start-SystemDashboard.ps1'
    if (-not (Test-Path -LiteralPath $launcher)) {
        Write-ServiceLog "ERROR: Launcher not found at $launcher"
        exit 1
    }

    $configuredPrefix = Resolve-ConfiguredPrefix -ConfigPath $resolvedConfig
    $configuredPort = Get-PrefixPort -Prefix $configuredPrefix
    Clear-UrlAclConflicts -Port $configuredPort

    $launcherArgs = @(
        '-NoProfile',
        '-File',
        $launcher,
        '-Mode',
        'Legacy',
        '-ConfigPath',
        $resolvedConfig,
        '-SkipPreflight',
        '-SkipDatabaseCheck',
        '-SkipInstall'
    )

    $failCount = 0
    while ($true) {
        try {
            $proc = Start-Process -FilePath 'pwsh.exe' -ArgumentList $launcherArgs -WorkingDirectory $RootPath -PassThru
            Set-Content -LiteralPath $PidFile -Value $proc.Id -Encoding ascii
            Write-ServiceLog "Legacy dashboard process started (PID: $($proc.Id))"
        }
        catch {
            Write-ServiceLog "ERROR: Legacy dashboard failed to start: $($_.Exception.Message)"
            Start-Sleep -Seconds 10
            continue
        }

        while ($true) {
            Start-Sleep -Seconds 10
            $proc.Refresh()
            if ($proc.HasExited) {
                Write-ServiceLog "Legacy dashboard process exited (code: $($proc.ExitCode))."
                break
            }
            if (-not (Test-DashboardHealth -ConfigPath $resolvedConfig)) {
                $failCount += 1
                Write-ServiceLog "Legacy dashboard health check failed ($failCount)."
                if ($failCount -ge 3) {
                    Write-ServiceLog "Restarting legacy dashboard process due to failed health checks."
                    try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
                    break
                }
            }
            else {
                $failCount = 0
            }
        }
        Remove-Item -LiteralPath $PidFile -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

function Stop-DashboardService {
    $proc = Get-DashboardProcess
    if ($proc) {
        Write-ServiceLog "Stopping legacy dashboard (PID: $($proc.Id))"
        Stop-Process -Id $proc.Id -Force
    }
    if (Test-Path $PidFile) {
        Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-DashboardStatus {
    $proc = Get-DashboardProcess
    if ($proc) {
        Write-ServiceLog "Legacy dashboard running (PID: $($proc.Id))"
        return $true
    }
    Write-ServiceLog "Legacy dashboard not running"
    return $false
}

switch ($Action.ToLower()) {
    "start" { Start-DashboardService }
    "stop" { Stop-DashboardService }
    "restart" {
        Stop-DashboardService
        Start-Sleep -Seconds 2
        Start-DashboardService
    }
    "status" { Get-DashboardStatus }
    default {
        Write-Host "Usage: $($MyInvocation.MyCommand.Name) -Action [start|stop|restart|status]"
        exit 1
    }
}

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
$CrashLog = Join-Path $LogDir "dashboard-crash-history.log"
$ServiceLogMaxMB = if ($env:SYSTEMDASHBOARD_SERVICE_LOG_MAX_MB) { [int]$env:SYSTEMDASHBOARD_SERVICE_LOG_MAX_MB } else { 5 }
$ServiceLogMaxFiles = if ($env:SYSTEMDASHBOARD_SERVICE_LOG_MAX_FILES) { [int]$env:SYSTEMDASHBOARD_SERVICE_LOG_MAX_FILES } else { 5 }
$RestartWindowSeconds = if ($env:SYSTEMDASHBOARD_RESTART_WINDOW_SECONDS) { [int]$env:SYSTEMDASHBOARD_RESTART_WINDOW_SECONDS } else { 300 }
$RestartBaseDelaySeconds = if ($env:SYSTEMDASHBOARD_RESTART_BASE_SECONDS) { [int]$env:SYSTEMDASHBOARD_RESTART_BASE_SECONDS } else { 2 }
$RestartMaxDelaySeconds = if ($env:SYSTEMDASHBOARD_RESTART_MAX_SECONDS) { [int]$env:SYSTEMDASHBOARD_RESTART_MAX_SECONDS } else { 60 }
$script:CrashTimes = New-Object 'System.Collections.Generic.List[DateTime]'
$script:ActivePrefix = $null

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
if (-not (Test-Path $RunDir)) {
    New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
}

function Rotate-LogFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$MaxSizeMB = 5,
        [int]$MaxFiles = 5
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $info = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $info -or $info.Length -lt ($MaxSizeMB * 1MB)) {
        return
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $archivePath = "{0}.{1}.log" -f $Path, $timestamp
    try {
        Move-Item -LiteralPath $Path -Destination $archivePath -Force
    } catch {
        return
    }

    if ($MaxFiles -le 0) {
        return
    }

    $dir = Split-Path -Parent $Path
    $base = [System.IO.Path]::GetFileName($Path)
    $archives = Get-ChildItem -LiteralPath $dir -Filter "$base.*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

    if ($archives.Count -gt $MaxFiles) {
        $archives | Select-Object -Skip $MaxFiles | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Write-ServiceLog {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Rotate-LogFile -Path $LogFile -MaxSizeMB $ServiceLogMaxMB -MaxFiles $ServiceLogMaxFiles
    "$timestamp - $Message" | Out-File -FilePath $LogFile -Append -Encoding utf8
    Write-Host "$timestamp - $Message"
}

function Write-CrashEvent {
    param(
        [string]$EventType,
        [string]$Reason,
        [int]$ExitCode,
        [int]$ProcessId,
        [string]$Prefix,
        [string]$StdoutLog,
        [string]$StderrLog
    )

    Rotate-LogFile -Path $CrashLog -MaxSizeMB $ServiceLogMaxMB -MaxFiles $ServiceLogMaxFiles
    $entry = [ordered]@{
        timestamp = (Get-Date).ToString('o')
        event = $EventType
        reason = $Reason
        exit_code = $ExitCode
        pid = $ProcessId
        prefix = $Prefix
        stdout_log = $StdoutLog
        stderr_log = $StderrLog
    }
    ($entry | ConvertTo-Json -Compress) | Out-File -FilePath $CrashLog -Append -Encoding utf8
}

function Register-Crash {
    $script:CrashTimes.Add((Get-Date))
}

function Get-RestartDelaySeconds {
    $now = Get-Date
    while ($script:CrashTimes.Count -gt 0 -and ($now - $script:CrashTimes[0]).TotalSeconds -gt $RestartWindowSeconds) {
        $script:CrashTimes.RemoveAt(0)
    }

    $count = $script:CrashTimes.Count
    if ($count -le 1) {
        return $RestartBaseDelaySeconds
    }

    $exp = [Math]::Min($count - 1, 6)
    $delay = [Math]::Min($RestartBaseDelaySeconds * [Math]::Pow(2, $exp), $RestartMaxDelaySeconds)
    return [int][Math]::Round($delay)
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

    $statusUrl = ($Prefix.TrimEnd('/') + '/api/status')
    $metricsUrl = ($Prefix.TrimEnd('/') + '/metrics')
    try {
        $statusResponse = Invoke-WebRequest -Uri $statusUrl -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
        if ($statusResponse.StatusCode -ge 200 -and $statusResponse.StatusCode -lt 400) {
            return $true
        }
    } catch {
        # fall through to metrics check
    }

    try {
        $metricsResponse = Invoke-WebRequest -Uri $metricsUrl -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
        return ($metricsResponse.StatusCode -ge 200 -and $metricsResponse.StatusCode -lt 400)
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
    $restartDelay = 0
    while ($true) {
        if ($restartDelay -gt 0) {
            Write-ServiceLog "Delaying restart for $restartDelay seconds..."
            Start-Sleep -Seconds $restartDelay
        }

        $runStamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $stdoutLog = Join-Path $LogDir "dashboard-listener-$runStamp.out.log"
        $stderrLog = Join-Path $LogDir "dashboard-listener-$runStamp.err.log"
        $restartReason = $null
        $exitCode = $null

        try {
            $proc = Start-Process -FilePath 'pwsh.exe' -ArgumentList $launcherArgs -WorkingDirectory $RootPath -PassThru `
                -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
            Set-Content -LiteralPath $PidFile -Value $proc.Id -Encoding ascii
            Write-ServiceLog "Legacy dashboard process started (PID: $($proc.Id))"
            Write-ServiceLog "Listener stdout: $stdoutLog"
            Write-ServiceLog "Listener stderr: $stderrLog"
        }
        catch {
            $restartReason = "start_failed"
            Write-ServiceLog "ERROR: Legacy dashboard failed to start: $($_.Exception.Message)"
            Write-CrashEvent -EventType 'start_failed' -Reason $_.Exception.Message -ExitCode 1 -ProcessId 0 -Prefix $script:ActivePrefix -StdoutLog $stdoutLog -StderrLog $stderrLog
            Register-Crash
            $restartDelay = Get-RestartDelaySeconds
            continue
        }

        while ($true) {
            Start-Sleep -Seconds 10
            $proc.Refresh()
            if ($proc.HasExited) {
                $exitCode = $proc.ExitCode
                $restartReason = "exit"
                Write-ServiceLog "Legacy dashboard process exited (code: $($proc.ExitCode))."
                break
            }
            if (-not (Test-DashboardHealth -ConfigPath $resolvedConfig)) {
                $failCount += 1
                Write-ServiceLog "Legacy dashboard health check failed ($failCount)."
                if ($failCount -ge 3) {
                    $restartReason = "health_check_failed"
                    Write-ServiceLog "Restarting legacy dashboard process due to failed health checks."
                    try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
                    break
                }
            }
            else {
                $failCount = 0
            }
        }

        if (-not $restartReason) {
            $restartReason = "exit"
        }

        $exitValue = if ($null -ne $exitCode) { $exitCode } else { 0 }
        $pidValue = if ($proc) { $proc.Id } else { 0 }
        Write-CrashEvent -EventType $restartReason -Reason $restartReason -ExitCode $exitValue -ProcessId $pidValue -Prefix $script:ActivePrefix -StdoutLog $stdoutLog -StderrLog $stderrLog
        Register-Crash
        $restartDelay = Get-RestartDelaySeconds

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

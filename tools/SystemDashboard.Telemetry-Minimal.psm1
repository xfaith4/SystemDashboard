#requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:TelemetryLogLevels = @{
    'DEBUG' = 0
    'INFO'  = 1
    'WARN'  = 2
    'ERROR' = 3
}
$script:TelemetryLogLevel = (($env:SYSTEMDASHBOARD_LOG_LEVEL ?? 'INFO')).ToUpperInvariant()
if (-not $script:TelemetryLogLevels.ContainsKey($script:TelemetryLogLevel)) {
    $script:TelemetryLogLevel = 'INFO'
}

function Write-TelemetryLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$Message,
        [Parameter()][ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')][string]$Level = 'INFO'
    )

    $effectiveLevel = if ($script:TelemetryLogLevels.ContainsKey($script:TelemetryLogLevel)) {
        $script:TelemetryLogLevel
    } else {
        'INFO'
    }

    if ($script:TelemetryLogLevels[$Level] -lt $script:TelemetryLogLevels[$effectiveLevel]) {
        return
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    # Ensure log directory exists
    $logDir = Split-Path $LogPath -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    Add-Content -Path $LogPath -Value $logEntry -ErrorAction SilentlyContinue
    Write-Host $logEntry
}

function Set-TelemetryLogLevel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('DEBUG','INFO','WARN','ERROR')][string]$Level
    )

    $script:TelemetryLogLevel = $Level.ToUpperInvariant()
}

function Read-SystemDashboardConfig {
    [CmdletBinding()]
    param(
        [Parameter()][string]$ConfigPath
    )

    if (-not $ConfigPath -or -not (Test-Path $ConfigPath)) {
        throw "Configuration file not found: $ConfigPath"
    }

    try {
        $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
        return $config
    }
    catch {
        throw "Failed to parse configuration file: $_"
    }
}

function Start-TelemetryService {
    [CmdletBinding()]
    param(
        [Parameter()][string]$ConfigPath
    )

    # Set default config path if not provided
    if (-not $ConfigPath) {
        $ConfigPath = Join-Path $PSScriptRoot '..' 'config.json'
    }

    try {
        # Load configuration
        $config = Read-SystemDashboardConfig -ConfigPath $ConfigPath
        $logPath = $config.Service.LogPath

        $effectiveLogLevel = $env:SYSTEMDASHBOARD_LOG_LEVEL ?? $config.Logging.LogLevel ?? $config.Service.LogLevel ?? 'INFO'
        try {
            Set-TelemetryLogLevel -Level $effectiveLogLevel.ToUpperInvariant()
        }
        catch {
            Set-TelemetryLogLevel -Level 'INFO'
        }

        if (-not [System.IO.Path]::IsPathRooted($logPath)) {
            $logPath = Join-Path (Split-Path $ConfigPath -Parent) $logPath
        }

        Write-TelemetryLog -LogPath $logPath -Message "SystemDashboard Telemetry Service starting..." -Level 'INFO'
        Write-TelemetryLog -LogPath $logPath -Message "Configuration loaded from: $ConfigPath" -Level 'INFO'
        Write-TelemetryLog -LogPath $logPath -Message "Database: $($config.Database.Host):$($config.Database.Port)/$($config.Database.Database)" -Level 'INFO'

        # Initialize UDP syslog listener
        $syslogPort = $config.Service.Syslog.Port
        $syslogEndpoint = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, $syslogPort)
        $udpClient = $null

        try {
            $udpClient = [System.Net.Sockets.UdpClient]::new()
            $udpClient.Client.Bind($syslogEndpoint)
            $udpClient.Client.ReceiveTimeout = 1000  # 1 second timeout
            Write-TelemetryLog -LogPath $logPath -Message "Syslog UDP listener bound to port $syslogPort" -Level 'INFO'
        }
        catch {
            Write-TelemetryLog -LogPath $logPath -Message "Failed to bind UDP listener to port $syslogPort - $($_.Exception.Message)" -Level 'ERROR'
            if ($udpClient) { $udpClient.Close() }
            $udpClient = $null
        }

        # Service main loop
        $heartbeatCounter = 0
        $messageCount = 0

        while ($true) {
            # Check for syslog messages (non-blocking)
            if ($udpClient) {
                try {
                    $remote = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
                    $bytes = $udpClient.Receive([ref]$remote)
                    if ($bytes.Length -gt 0) {
                        $messageCount++
                        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
                        Write-TelemetryLog -LogPath $logPath -Message "Syslog message #$messageCount from $($remote.Address): $($text.Substring(0, [Math]::Min(100, $text.Length)))" -Level 'INFO'

                        # TODO: Parse and store the syslog message
                        # For now, just log that we received it
                    }
                }
                catch [System.Net.Sockets.SocketException] {
                    # Timeout is expected, ignore
                    if ($_.Exception.NativeErrorCode -ne 10060) {
                        Write-TelemetryLog -LogPath $logPath -Message "Syslog listener error: $($_.Exception.Message)" -Level 'WARN'
                    }
                }
                catch {
                    Write-TelemetryLog -LogPath $logPath -Message "Unexpected syslog listener error: $($_.Exception.Message)" -Level 'WARN'
                }
            }

            Start-Sleep -Seconds 1
            $heartbeatCounter++

            if ($heartbeatCounter % 300 -eq 0) {  # Log every 5 minutes (300 seconds)
                $status = if ($udpClient) { "UDP listener active on port $syslogPort" } else { "UDP listener not active" }
                Write-TelemetryLog -LogPath $logPath -Message "Service heartbeat #$($heartbeatCounter/300) - $status - Messages received: $messageCount" -Level 'INFO'
            }
        }
    }
    catch {
        if ($logPath) {
            Write-TelemetryLog -LogPath $logPath -Message "Service error: $_" -Level 'ERROR'
        }
        throw
    }
    finally {
        if ($udpClient) {
            $udpClient.Close()
            if ($logPath) {
                Write-TelemetryLog -LogPath $logPath -Message "UDP listener closed" -Level 'INFO'
            }
        }
    }
}

# Export the functions
Export-ModuleMember -Function Start-TelemetryService, Write-TelemetryLog, Set-TelemetryLogLevel

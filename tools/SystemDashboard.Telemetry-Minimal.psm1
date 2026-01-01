#requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-TelemetryLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$Message,
        [Parameter()][ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')][string]$Level = 'INFO'
    )

    $maxBytes = 50MB
    $maxFiles = 5

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    # Ensure log directory exists
    $logDir = Split-Path $LogPath -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    if (Test-Path -LiteralPath $LogPath) {
        try {
            $currentSize = (Get-Item -LiteralPath $LogPath -ErrorAction Stop).Length
            if ($currentSize -ge $maxBytes) {
                $name = [System.IO.Path]::GetFileNameWithoutExtension($LogPath)
                $ext = [System.IO.Path]::GetExtension($LogPath)
                $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
                $archive = Join-Path $logDir "$name.$stamp$ext"
                try {
                    Move-Item -LiteralPath $LogPath -Destination $archive -Force -ErrorAction Stop
                }
                catch {
                    $archive = Join-Path $logDir "$name.$stamp.$([Guid]::NewGuid().ToString('N'))$ext"
                    Move-Item -LiteralPath $LogPath -Destination $archive -Force -ErrorAction Stop
                }

                $archives = @(Get-ChildItem -LiteralPath $logDir -Filter "$name.*$ext" -File -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending)
                if ($archives.Count -gt $maxFiles) {
                    $archives | Select-Object -Skip $maxFiles | ForEach-Object {
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
        catch {
            # Best-effort rotation only; do not fail the service due to log I/O.
        }
    }

    Add-Content -Path $LogPath -Value $logEntry -ErrorAction SilentlyContinue
    Write-Host $logEntry
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
Export-ModuleMember -Function Start-TelemetryService, Write-TelemetryLog

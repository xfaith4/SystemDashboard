# Setup Windows Event Log Exporter for Prometheus
# This script downloads and configures windows_exporter with event log collection

$exporterDir = "G:\Storage\BenStuff\Development\Observability\windows_exporter"
$exporterUrl = "https://github.com/prometheus-community/windows_exporter/releases/latest/download/windows_exporter.exe"
$configFile = "$exporterDir\eventlog_config.yml"

# Create directory if it doesn't exist
if (!(Test-Path $exporterDir)) {
    New-Item -ItemType Directory -Path $exporterDir -Force
}

# Download windows_exporter if not exists
$exporterPath = "$exporterDir\windows_exporter.exe"
if (!(Test-Path $exporterPath)) {
    Write-Host "Downloading windows_exporter..."
    Invoke-WebRequest -Uri $exporterUrl -OutFile $exporterPath
}

# Create event log configuration
$eventLogConfig = @"
# Windows Event Log Exporter Configuration
collectors:
  eventlog:
    enabled: true
    # Common Windows Event Logs to monitor
    sources:
      - System
      - Application
      - Security
      - Setup
      - Microsoft-Windows-Windows Defender/Operational
      - Microsoft-Windows-PowerShell/Operational
      - Microsoft-Windows-TaskScheduler/Operational
      - Microsoft-Windows-TerminalServices-LocalSessionManager/Operational

    # Event levels to collect (1=Critical, 2=Error, 3=Warning, 4=Information, 5=Verbose)
    levels:
      - 1  # Critical
      - 2  # Error
      - 3  # Warning
      - 4  # Information

    # Maximum events per scrape (to prevent memory issues)
    max_events_per_source: 100

    # Time window for events (in seconds, 0 = all available)
    time_window: 3600  # Last hour
"@

# Write configuration file
$eventLogConfig | Out-File -FilePath $configFile -Encoding UTF8

Write-Host "Event log exporter setup complete!"
Write-Host "Configuration saved to: $configFile"
Write-Host ""
Write-Host "To start the exporter manually:"
Write-Host "cd `"$exporterDir`""
Write-Host ".\windows_exporter.exe --config.file=`"$configFile`" --web.listen-address=:9417"
Write-Host ""
Write-Host "Or use the start-eventlog-exporter.ps1 script"

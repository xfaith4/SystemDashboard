# Start Windows Event Log Exporter
# This script starts the windows_exporter with event log collection enabled

# Run without profile to avoid module loading errors
if ($PSVersionTable.PSVersion.Major -ge 6) {
    Write-Host "Running in PowerShell Core - profiles may cause issues with legacy modules"
}

$exporterDir = "G:\Storage\BenStuff\Development\Observability\windows_exporter"
$exporterPath = "$exporterDir\windows_exporter.exe"
$configFile = "$exporterDir\eventlog_config.yml"

# Check if exporter exists
if (!(Test-Path $exporterPath)) {
    Write-Error "Windows exporter not found. Please run setup-eventlog-exporter.ps1 first."
    exit 1
}

# Check if config exists
if (!(Test-Path $configFile)) {
    Write-Error "Configuration file not found. Please run setup-eventlog-exporter.ps1 first."
    exit 1
}

Write-Host "Starting Windows Event Log Exporter on port 9417..."
Write-Host "Event logs being monitored:"
Write-Host "- System"
Write-Host "- Application"
Write-Host "- Security"
Write-Host "- Setup"
Write-Host "- Windows Defender"
Write-Host "- PowerShell"
Write-Host "- Task Scheduler"
Write-Host "- Terminal Services"
Write-Host ""
Write-Host "Metrics available at: http://localhost:9417/metrics"
Write-Host "Press CTRL+C to stop"

# Start the exporter
Set-Location $exporterDir
& $exporterPath --config.file="$configFile" --web.listen-address=:9417 --collectors.enabled="eventlog"

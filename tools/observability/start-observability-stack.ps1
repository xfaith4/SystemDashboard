# Comprehensive startup script for Observability stack with Windows Event Logs
# This script starts Prometheus, PromLens, and Event Log exporters

Write-Host "Starting Observability Stack with Windows Event Log Monitoring..." -ForegroundColor Green

# Base directory
$baseDir = "G:\Storage\BenStuff\Development\Observability"

# Start Custom PowerShell Event Log Exporter
Write-Host "Starting custom PowerShell Event Log Exporter on port 9418..." -ForegroundColor Yellow
$eventLogJob = Start-Job -ScriptBlock {
    param($scriptPath)
    & $scriptPath
} -ArgumentList "$baseDir\eventlog-exporter.ps1"

# Wait a moment for the exporter to start
Start-Sleep -Seconds 3

# Check if windows_exporter is available and start it
$windowsExporterPath = "$baseDir\windows_exporter\windows_exporter.exe"
if (Test-Path $windowsExporterPath) {
    Write-Host "Starting Windows Exporter with Event Log collection on port 9417..." -ForegroundColor Yellow
    $windowsExporterJob = Start-Job -ScriptBlock {
        param($exporterPath, $configPath)
        Set-Location (Split-Path $exporterPath)
        & $exporterPath --config.file="$configPath" --web.listen-address=:9417 --collectors.enabled="eventlog"
    } -ArgumentList $windowsExporterPath, "$baseDir\windows_exporter\eventlog_config.yml"
    Start-Sleep -Seconds 3
}

# Verify PromLens executable exists
$promlensPath = "$baseDir\promlens\promlens.exe"
if (-Not (Test-Path $promlensPath)) {
    Write-Error "PromLens executable not found at $promlensPath. Please ensure it is correctly installed."
    exit 1
}

# Start PromLens with error handling
try {
    Write-Host "Starting PromLens..." -ForegroundColor Yellow
    $promlensArgs = @(
        "--web.listen-address=:9091"
        "--web.default-prometheus-url=http://localhost:9418"
    )
    $promlensProcess = Start-Process $promlensPath -ArgumentList $promlensArgs -WorkingDirectory "$($baseDir)\promlens" -PassThru -ErrorAction Stop
    Write-Host "PromLens process started successfully." -ForegroundColor Green
} catch {
    Write-Error "Failed to start PromLens: $_"
    exit 1
}

# Wait for PromLens to start and open browser
Write-Host "Waiting for PromLens to start..." -ForegroundColor Yellow
$attempt = 0
$maxAttempts = 15
while ($attempt -lt $maxAttempts) {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:9091" -UseBasicParsing -TimeoutSec 2
        if ($response.StatusCode -eq 200) {
            Write-Host "PromLens is ready!" -ForegroundColor Green
            break
        }
    }
    catch {
        Start-Sleep -Seconds 2
    }
    $attempt++
}

# Open browser
Start-Process http://localhost:9091

Write-Host ""
Write-Host "=== Observability Stack Started ===" -ForegroundColor Green
Write-Host "PromLens Web UI: http://localhost:9091" -ForegroundColor Cyan
Write-Host "Custom Event Log Exporter: http://localhost:9418/metrics" -ForegroundColor Cyan
if (Test-Path $windowsExporterPath) {
    Write-Host "Windows Exporter: http://localhost:9417/metrics" -ForegroundColor Cyan
}
Write-Host ""
Write-Host "Available Event Log Metrics:" -ForegroundColor Yellow
Write-Host "- windows_eventlog_events_total" -ForegroundColor White
Write-Host "- windows_eventlog_latest_event_timestamp" -ForegroundColor White
Write-Host "- windows_eventlog_scrape_errors_total" -ForegroundColor White
Write-Host ""
Write-Host "Example PromQL Queries:" -ForegroundColor Yellow
Write-Host 'rate(windows_eventlog_events_total[5m])' -ForegroundColor White
Write-Host 'windows_eventlog_events_total{level="Error"}' -ForegroundColor White
Write-Host 'sum by (source) (windows_eventlog_events_total)' -ForegroundColor White
Write-Host ""
Write-Host "Press CTRL+C to stop all services" -ForegroundColor Red

# Keep the script running and monitor jobs
try {
    while ($true) {
        Start-Sleep -Seconds 30

        # Check if jobs are still running
        if ($eventLogJob.State -eq "Failed") {
            Write-Warning "Event Log Exporter job failed"
            break
        }

        if ($windowsExporterJob -and $windowsExporterJob.State -eq "Failed") {
            Write-Warning "Windows Exporter job failed"
        }
    }
}
finally {
    Write-Host "Stopping services..." -ForegroundColor Red

    # Stop jobs
    if ($eventLogJob) { Stop-Job $eventLogJob -PassThru | Remove-Job }
    if ($windowsExporterJob) { Stop-Job $windowsExporterJob -PassThru | Remove-Job }

    # Stop PromLens
    if ($promlensProcess -and !$promlensProcess.HasExited) {
        $promlensProcess.Kill()
    }

    Write-Host "All services stopped." -ForegroundColor Green
}

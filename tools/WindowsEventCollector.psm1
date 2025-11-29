# Windows Event Log Collector for System Dashboard
# This module collects Windows Event Log entries and sends them to the database

function Collect-WindowsEvents {
    param(
        [int]$MaxEvents = 50,
        [string[]]$LogNames = @('Application', 'System', 'Security'),
        [int]$MinutesBack = 5
    )

    Write-TelemetryLog "Collecting Windows Events from logs: $($LogNames -join ', ')"

    $events = @()
    $startTime = (Get-Date).AddMinutes(-$MinutesBack)

    foreach ($logName in $LogNames) {
        try {
            $logEvents = Get-WinEvent -FilterHashtable @{
                LogName = $logName
                StartTime = $startTime
                Level = @(1,2,3,4)  # Critical, Error, Warning, Information
            } -MaxEvents $MaxEvents -ErrorAction SilentlyContinue

            foreach ($event in $logEvents) {
                $events += @{
                    EventUtc = $event.TimeCreated.ToUniversalTime()
                    SourceHost = $env:COMPUTERNAME
                    ProviderName = $event.ProviderName
                    EventId = $event.Id
                    Level = $event.Level
                    LevelText = $event.LevelDisplayName
                    Message = $event.Message
                    Source = 'windows_eventlog'
                }
            }
        }
        catch {
            Write-TelemetryLog "Warning: Could not collect from log '$logName': $($_.Exception.Message)"
        }
    }

    Write-TelemetryLog "Collected $($events.Count) Windows events"
    return $events
}

function Send-EventsToDatabase {
    param(
        [array]$Events,
        [string]$TableName = 'telemetry.eventlog_windows_template'
    )

    if ($Events.Count -eq 0) {
        return
    }

    $config = Get-TelemetryConfig
    $connectionString = "Host=$($config.Database.Host);Port=$($config.Database.Port);Database=$($config.Database.Database);Username=$($config.Database.Username);Password=$($env:SYSTEMDASHBOARD_DB_PASSWORD)"

    try {
        # Create batch insert SQL
        $values = @()
        foreach ($event in $Events) {
            $eventUtc = $event.EventUtc.ToString('yyyy-MM-dd HH:mm:ss')
            $sourceHost = $event.SourceHost -replace "'", "''"
            $providerName = $event.ProviderName -replace "'", "''"
            $message = ($event.Message -replace "'", "''").Substring(0, [Math]::Min(8000, $event.Message.Length))
            $levelText = $event.LevelText -replace "'", "''"

            $values += "('$eventUtc', '$sourceHost', '$providerName', $($event.EventId), $($event.Level), '$levelText', '$message', '$($event.Source)')"
        }

        $sql = @"
INSERT INTO $TableName (event_utc, source_host, provider_name, event_id, level, level_text, message, source)
VALUES $($values -join ',')
ON CONFLICT DO NOTHING;
"@

        # For now, save to staging file for the main service to process
        $stagingDir = $config.Service.Ingestion.StagingDirectory
        if (-not (Test-Path $stagingDir)) {
            New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
        }

        $stagingFile = Join-Path $stagingDir "windows_events_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"
        $sql | Out-File -FilePath $stagingFile -Encoding UTF8

        Write-TelemetryLog "Staged $($Events.Count) Windows events to $stagingFile"
    }
    catch {
        Write-TelemetryLog "Error staging Windows events: $($_.Exception.Message)"
    }
}

function Start-WindowsEventCollection {
    param(
        [int]$IntervalSeconds = 300  # 5 minutes
    )

    Write-TelemetryLog "Starting Windows Event collection (interval: $IntervalSeconds seconds)"

    while ($true) {
        try {
            $events = Collect-WindowsEvents -MaxEvents 100 -MinutesBack 10
            if ($events.Count -gt 0) {
                Send-EventsToDatabase -Events $events
            }

            Start-Sleep -Seconds $IntervalSeconds
        }
        catch {
            Write-TelemetryLog "Error in Windows Event collection loop: $($_.Exception.Message)"
            Start-Sleep -Seconds 60  # Wait 1 minute before retry
        }
    }
}

# Export functions
Export-ModuleMember -Function Collect-WindowsEvents, Send-EventsToDatabase, Start-WindowsEventCollection

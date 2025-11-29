# Enhanced Windows Event Collector with continuous monitoring
# Integrates with the main telemetry service for real-time event collection

function Start-ContinuousEventCollection {
    param(
        [int]$IntervalSeconds = 300,  # 5 minutes
        [string]$StagingDirectory = './var/staging'
    )

    Write-TelemetryLog "Starting continuous Windows Event collection"
    Write-TelemetryLog "Collection interval: $IntervalSeconds seconds"
    Write-TelemetryLog "Staging directory: $StagingDirectory"

    # Ensure staging directory exists
    if (-not (Test-Path $StagingDirectory)) {
        New-Item -ItemType Directory -Path $StagingDirectory -Force | Out-Null
    }

    # Track last collection time to avoid duplicates
    $lastCollectionTime = Get-Date

    while ($true) {
        try {
            Write-TelemetryLog "Collecting Windows events since $lastCollectionTime"

            # Collect from multiple event logs
            $eventSources = @(
                @{ LogName = 'Application'; MinLevel = 1; MaxEvents = 50 },
                @{ LogName = 'System'; MinLevel = 1; MaxEvents = 50 },
                @{ LogName = 'Security'; MinLevel = 2; MaxEvents = 25 }  # Only errors and critical
            )

            $totalCollected = 0

            foreach ($eventSource in $eventSources) {
                try {
                    $events = Get-WinEvent -FilterHashtable @{
                        LogName = $eventSource.LogName
                        StartTime = $lastCollectionTime
                        Level = @(1, 2, 3, 4) | Where-Object { $_ -ge $eventSource.MinLevel }
                    } -MaxEvents $eventSource.MaxEvents -ErrorAction SilentlyContinue

                    if ($events) {
                        $processedEvents = foreach ($evt in $events) {
                            @{
                                EventUtc = $evt.TimeCreated.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss.fff')
                                SourceHost = $env:COMPUTERNAME
                                ProviderName = $evt.ProviderName
                                EventId = $evt.Id
                                Level = $evt.Level
                                LevelText = $evt.LevelDisplayName
                                TaskCategory = $evt.TaskDisplayName
                                Message = if ($evt.Message) { $evt.Message.Substring(0, [Math]::Min(4000, $evt.Message.Length)) } else { '' }
                                LogName = $eventSource.LogName
                            }
                        }

                        # Stage the events
                        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
                        $filename = "windows_events_$($eventSource.LogName)_${timestamp}.json"
                        $filepath = Join-Path $StagingDirectory $filename

                        $stageData = @{
                            SourceType = 'windows_eventlog'
                            TargetTable = 'telemetry.eventlog_windows_template'
                            CollectionTime = Get-Date
                            EventCount = $processedEvents.Count
                            Events = $processedEvents
                        }

                        $stageData | ConvertTo-Json -Depth 5 | Out-File -FilePath $filepath -Encoding UTF8

                        $totalCollected += $processedEvents.Count
                        Write-TelemetryLog "Staged $($processedEvents.Count) events from $($eventSource.LogName) log"
                    }
                }
                catch {
                    Write-TelemetryLog "Warning: Could not collect from $($eventSource.LogName) log: $($_.Exception.Message)"
                }
            }

            Write-TelemetryLog "Total events collected this cycle: $totalCollected"
            $lastCollectionTime = Get-Date

            # Sleep until next collection
            Start-Sleep -Seconds $IntervalSeconds
        }
        catch {
            Write-TelemetryLog "Error in continuous event collection: $($_.Exception.Message)"
            Start-Sleep -Seconds 60  # Wait 1 minute before retrying
        }
    }
}

function Test-WindowsEventCollection {
    Write-Host "🧪 Testing Windows Event Collection" -ForegroundColor Yellow

    # Create a test event
    Write-Host "Creating test event..." -ForegroundColor Cyan
    try {
        Write-EventLog -LogName Application -Source "Application Error" -EventId 9999 -EntryType Information -Message "System Dashboard continuous collection test at $(Get-Date)"
        Write-Host "✅ Test event created" -ForegroundColor Green
    }
    catch {
        Write-Host "⚠️ Could not create test event: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Test event retrieval
    Write-Host "Testing event retrieval..." -ForegroundColor Cyan
    try {
        $recentEvents = Get-WinEvent -FilterHashtable @{
            LogName = 'Application'
            StartTime = (Get-Date).AddMinutes(-5)
        } -MaxEvents 10 -ErrorAction SilentlyContinue

        Write-Host "✅ Retrieved $($recentEvents.Count) recent events" -ForegroundColor Green

        if ($recentEvents.Count -gt 0) {
            Write-Host "Recent events:" -ForegroundColor White
            $recentEvents | Select-Object -First 3 | ForEach-Object {
                Write-Host "  • $($_.TimeCreated): $($_.ProviderName) - $($_.LevelDisplayName)" -ForegroundColor Gray
            }
        }
    }
    catch {
        Write-Host "❌ Error retrieving events: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Test staging
    Write-Host "Testing staging process..." -ForegroundColor Cyan
    $stagingDir = './var/staging'
    if (-not (Test-Path $stagingDir)) {
        New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
    }

    $testData = @{
        SourceType = 'windows_eventlog_test'
        TargetTable = 'telemetry.eventlog_windows_template'
        CollectionTime = Get-Date
        Events = @(
            @{
                EventUtc = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
                SourceHost = $env:COMPUTERNAME
                ProviderName = 'Test Provider'
                EventId = 9999
                Level = 4
                LevelText = 'Information'
                Message = 'Test event for staging verification'
            }
        )
    }

    $testFile = Join-Path $stagingDir "test_events_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $testData | ConvertTo-Json -Depth 3 | Out-File -FilePath $testFile -Encoding UTF8

    Write-Host "✅ Test staging file created: $testFile" -ForegroundColor Green
    Write-Host "📊 Continuous Windows Event Collection is ready!" -ForegroundColor Green
}

Export-ModuleMember -Function Start-ContinuousEventCollection, Test-WindowsEventCollection

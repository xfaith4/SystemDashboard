# Windows Event Log to Prometheus Exporter
# This PowerShell script acts as a simple event log exporter

param(
    [int]$Port = 9418,
    [int]$MaxEvents = 50,
    [int]$IntervalSeconds = 60
)

Add-Type -AssemblyName System.Web

# Event log sources to monitor
$eventSources = @(
    @{Name = "System"; LogName = "System" },
    @{Name = "Application"; LogName = "Application" },
    @{Name = "Security"; LogName = "Security" },
    @{Name = "PowerShell"; LogName = "Microsoft-Windows-PowerShell/Operational" },
    @{Name = "Defender"; LogName = "Microsoft-Windows-Windows Defender/Operational" }
)

# Event level mappings
$eventLevels = @{
    1 = "Critical"
    2 = "Error"
    3 = "Warning"
    4 = "Information"
    5 = "Verbose"
}

function Get-EventLogMetrics {
    $metrics = @()
    $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    foreach ($source in $eventSources) {
        try {
            # Get recent events
            $events = Get-WinEvent -LogName $source.LogName -MaxEvents $MaxEvents -ErrorAction SilentlyContinue |
            Where-Object { $_.TimeCreated -gt (Get-Date).AddHours(-1) }

            if ($events) {
                # Count events by level
                $eventCounts = $events | Group-Object LevelDisplayName |
                ForEach-Object {
                    @{Level = $_.Name; Count = $_.Count }
                }

                foreach ($count in $eventCounts) {
                    $metricName = "windows_eventlog_events_total"
                    $labels = "source=`"$($source.Name)`",level=`"$($count.Level)`""
                    $metrics += "$metricName{$labels} $($count.Count) $timestamp"
                }

                # Latest event timestamp
                $latestEvent = ($events | Sort-Object TimeCreated -Descending | Select-Object -First 1).TimeCreated
                $latestTimestamp = [DateTimeOffset]$latestEvent.ToUniversalTime().ToUnixTimeSeconds()
                $metricName = "windows_eventlog_latest_event_timestamp"
                $labels = "source=`"$($source.Name)`""
                $metrics += "$metricName{$labels} $latestTimestamp $timestamp"
            }
            else {
                # No events found
                $metricName = "windows_eventlog_events_total"
                $labels = "source=`"$($source.Name)`",level=`"NoEvents`""
                $metrics += "$metricName{$labels} 0 $timestamp"
            }
        }
        catch {
            Write-Warning "Error accessing log $($source.LogName): $($_.Exception.Message)"
            # Error metric
            $metricName = "windows_eventlog_scrape_errors_total"
            $labels = "source=`"$($source.Name)`""
            $metrics += "$metricName{$labels} 1 $timestamp"
        }
    }

    return $metrics
}

function Start-HttpListener {
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://localhost:$Port/")
    $listener.Start()

    Write-Host "Windows Event Log Exporter started on port $Port"
    Write-Host "Metrics endpoint: http://localhost:$Port/metrics"
    Write-Host "Press CTRL+C to stop"

    try {
        while ($listener.IsListening) {
            $context = $listener.GetContext()
            $request = $context.Request
            $response = $context.Response

            # Add CORS headers for all responses
            $response.Headers.Add("Access-Control-Allow-Origin", "*")
            $response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            $response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")

            if ($request.HttpMethod -eq "OPTIONS") {
                # Handle CORS preflight requests
                $response.StatusCode = 200
            }
            elseif ($request.Url.AbsolutePath -eq "/metrics") {
                $metrics = Get-EventLogMetrics
                $content = ($metrics -join "`n") + "`n"

                $response.ContentType = "text/plain; charset=utf-8"
                $response.StatusCode = 200

                $buffer = [System.Text.Encoding]::UTF8.GetBytes($content)
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            elseif ($request.Url.AbsolutePath -eq "/") {
                $html = @"
<!DOCTYPE html>
<html>
<head><title>Windows Event Log Exporter</title></head>
<body>
<h1>Windows Event Log Exporter</h1>
<p><a href="/metrics">Metrics</a></p>
<p>Monitoring event logs: $($eventSources.Name -join ', ')</p>
</body>
</html>
"@
                $response.ContentType = "text/html"
                $response.StatusCode = 200

                $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            elseif ($request.Url.AbsolutePath -eq "/api/v1/query") {
                # Basic query endpoint - return simple metric data
                $query = $request.QueryString["query"]
                $metrics = Get-EventLogMetrics

                $jsonResponse = @{
                    status = "success"
                    data   = @{
                        resultType = "vector"
                        result     = @()
                    }
                }

                # Parse simple queries and return matching metrics
                foreach ($metric in $metrics) {
                    if ($metric -match '^(\w+)\{(.+?)\}\s+(\d+)\s+\d+$') {
                        $metricName = $matches[1]
                        $labels = $matches[2]
                        $value = $matches[3]

                        if ($query -eq $metricName -or $query -eq "1") {
                            $jsonResponse.data.result += @{
                                metric = @{__name__ = $metricName }
                                value  = @([double]0, [double]$value)
                            }

                            # Parse labels
                            $labelPairs = $labels -split ',' | ForEach-Object {
                                $key, $val = $_ -split '='
                                @{ $key.Trim('"') = $val.Trim('"') }
                            }

                            $jsonResponse.data.result[-1].metric += $labelPairs
                        }
                    }
                }

                $response.ContentType = "application/json"
                $response.StatusCode = 200

                $json = ConvertTo-Json -InputObject $jsonResponse -Depth 3
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            elseif ($request.Url.AbsolutePath -eq "/api/v1/label/__name__/values") {
                # Return available metric names
                $metricNames = @("windows_eventlog_events_total", "windows_eventlog_latest_event_timestamp", "windows_eventlog_scrape_errors_total")

                $jsonResponse = @{
                    status = "success"
                    data   = $metricNames
                }

                $response.ContentType = "application/json"
                $response.StatusCode = 200

                $json = ConvertTo-Json -InputObject $jsonResponse
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            else {
                $response.StatusCode = 404
            }

            $response.Close()
        }
    }
    finally {
        $listener.Stop()
    }
}

# Start the HTTP listener
Start-HttpListener

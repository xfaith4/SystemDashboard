# Data Source Manager for System Dashboard
# Extensible framework for adding new telemetry data sources

class DataSourceManager {
    [hashtable]$Sources
    [string]$StagingDirectory

    DataSourceManager([string]$stagingDir) {
        $this.Sources = @{}
        $this.StagingDirectory = $stagingDir
    }

    [void]RegisterSource([string]$name, [hashtable]$config) {
        $this.Sources[$name] = $config
        Write-TelemetryLog "Registered data source: $name"
    }

    [void]CollectFromAllSources() {
        foreach ($sourceName in $this.Sources.Keys) {
            try {
                $this.CollectFromSource($sourceName)
            }
            catch {
                Write-TelemetryLog "Error collecting from source '$sourceName': $($_.Exception.Message)"
            }
        }
    }

    [void]CollectFromSource([string]$sourceName) {
        $source = $this.Sources[$sourceName]
        if (-not $source.Enabled) { return }

        Write-TelemetryLog "Collecting from data source: $sourceName"

        switch ($source.Type) {
            'WindowsEventLog' { $this.CollectWindowsEvents($source) }
            'IISLogs' { $this.CollectIISLogs($source) }
            'PerformanceCounters' { $this.CollectPerformanceCounters($source) }
            'CustomScript' { $this.CollectFromScript($source) }
            'SQLQuery' { $this.CollectFromSQL($source) }
            'WebAPI' { $this.CollectFromWebAPI($source) }
            default { Write-TelemetryLog "Unknown source type: $($source.Type)" }
        }
    }

    [void]CollectWindowsEvents([hashtable]$config) {
        $events = Get-WinEvent -FilterHashtable @{
            LogName = $config.LogNames
            StartTime = (Get-Date).AddMinutes(-$config.IntervalMinutes)
            Level = $config.LevelsToCapture
        } -MaxEvents $config.MaxEvents -ErrorAction SilentlyContinue

        if ($events) {
            $this.StageData('windows_events', $events, $config.TargetTable)
        }
    }

    [void]CollectIISLogs([hashtable]$config) {
        $logFiles = Get-ChildItem -Path $config.LogPath -Filter "*.log" |
            Where-Object { $_.LastWriteTime -gt (Get-Date).AddHours(-1) }

        foreach ($logFile in $logFiles) {
            $newLines = Get-Content $logFile | Select-Object -Last $config.MaxLines
            if ($newLines) {
                $this.StageData('iis_logs', $newLines, $config.TargetTable)
            }
        }
    }

    [void]CollectPerformanceCounters([hashtable]$config) {
        $counters = Get-Counter -Counter $config.Counters -SampleInterval 1 -MaxSamples 1
        $data = foreach ($counter in $counters.CounterSamples) {
            @{
                Counter = $counter.Path
                Value = $counter.CookedValue
                Timestamp = $counter.Timestamp
                InstanceName = $counter.InstanceName
            }
        }

        if ($data) {
            $this.StageData('performance_counters', $data, $config.TargetTable)
        }
    }

    [void]CollectFromScript([hashtable]$config) {
        $result = & $config.ScriptPath $config.Parameters
        if ($result) {
            $this.StageData($config.Name, $result, $config.TargetTable)
        }
    }

    [void]CollectFromSQL([hashtable]$config) {
        # Execute SQL query and return results
        # Implementation would depend on SQL provider (SqlServer, MySQL, etc.)
        Write-TelemetryLog "SQL collection not yet implemented for: $($config.Name)"
    }
    [void]CollectFromWebAPI([hashtable]$config) {
        try {
            $headers = $config.Headers ?? @{}
            $response = Invoke-RestMethod -Uri $config.Endpoint -Headers $headers -TimeoutSec 30

            if ($response) {
                $this.StageData($config.Name, $response, $config.TargetTable)
            }
        }
        catch {
            Write-TelemetryLog "Web API collection failed for $($config.Name): $($_.Exception.Message)"
        }
    }

    [void]StageData([string]$sourceName, [object]$data, [string]$targetTable) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $filename = "${sourceName}_${timestamp}.json"
        $filepath = Join-Path $this.StagingDirectory $filename

        $stageData = @{
            SourceName = $sourceName
            TargetTable = $targetTable
            Timestamp = Get-Date
            Data = $data
        }

        $stageData | ConvertTo-Json -Depth 10 | Out-File -FilePath $filepath -Encoding UTF8
        Write-TelemetryLog "Staged $($data.Count) records from $sourceName to $filename"
    }
}

# Default data source configurations
function Get-DefaultDataSources {
    return @{
        'WindowsEvents' = @{
            Type = 'WindowsEventLog'
            Enabled = $true
            LogNames = @('Application', 'System', 'Security')
            LevelsToCapture = @(1, 2, 3, 4)  # Critical, Error, Warning, Info
            IntervalMinutes = 5
            MaxEvents = 100
            TargetTable = 'telemetry.eventlog_windows_template'
        }

        'IISLogs' = @{
            Type = 'IISLogs'
            Enabled = $false  # Requires IIS to be installed
            LogPath = 'C:\inetpub\logs\LogFiles\W3SVC1'
            MaxLines = 1000
            TargetTable = 'telemetry.iis_requests_template'
        }

        'SystemPerformance' = @{
            Type = 'PerformanceCounters'
            Enabled = $true
            Counters = @(
                '\Processor(_Total)\% Processor Time',
                '\Memory\Available MBytes',
                '\System\System Up Time'
            )
            TargetTable = 'telemetry.performance_metrics'
        }

        'SQLServerHealth' = @{
            Type = 'SQLQuery'
            Enabled = $false
            ConnectionString = 'Server=localhost;Trusted_Connection=true;'
            Query = 'SELECT name, state_desc FROM sys.databases'
            TargetTable = 'telemetry.sql_health'
        }

        'WebServiceHealth' = @{
            Type = 'WebAPI'
            Enabled = $false
            Endpoint = 'https://api.example.com/health'
            Headers = @{ 'Accept' = 'application/json' }
            TargetTable = 'telemetry.service_health'
        }
    }
}

# Initialize and export
function Initialize-DataSourceManager {
    param([string]$StagingDirectory = './var/staging')

    $manager = [DataSourceManager]::new($StagingDirectory)

    # Register default sources
    $defaultSources = Get-DefaultDataSources
    foreach ($sourceName in $defaultSources.Keys) {
        $manager.RegisterSource($sourceName, $defaultSources[$sourceName])
    }

    return $manager
}

Export-ModuleMember -Function Initialize-DataSourceManager, Get-DefaultDataSources

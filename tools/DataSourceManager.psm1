### BEGIN FILE: DataSourceManager.psm1
#requires -Version 5.1

Set-StrictMode -Version Latest

# Fallback logger in case Write-TelemetryLog is not defined by the host.
# This keeps the module self-contained and avoids hard failures on import.
if (-not (Get-Command -Name Write-TelemetryLog -ErrorAction SilentlyContinue)) {
    function global:__FallbackLog {
        param(
            [string]$Message,
            [string]$Level = 'Info'
        )
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[LOG][$Level] $ts $Message"
    }

    Set-Alias -Name Write-TelemetryLog -Value __FallbackLog -Scope Local
}


# Data Source Manager for System Dashboard
# Extensible framework for adding new telemetry data sources
class DataSourceManager {
    [hashtable]$Sources
    [string]$StagingDirectory

    DataSourceManager([string]$stagingDir) {
        # Initialize the sources hashtable and normalize/record the staging directory
        $this.Sources = @{}

        # PowerShell 5.1-safe resolution: try to resolve the path, but fall back
        # to the original string if it doesn't exist yet. StageData() will
        # create the directory when needed.
        $resolved = $null
        try {
            $resolved = Resolve-Path -LiteralPath $stagingDir -ErrorAction Stop
        }
        catch {
            $resolved = $null
        }

        if ($resolved) {
            $this.StagingDirectory = $resolved.ProviderPath
        }
        else {
            $this.StagingDirectory = $stagingDir
        }
    }

    [void]RegisterSource([string]$name, [hashtable]$config) {
        if (-not $config) {
            Write-TelemetryLog "Attempted to register source '$name' with null/empty config." 'Warning'
            return
        }

        # Ensure the config knows its own logical name
        if (-not $config.ContainsKey('Name')) {
            $config['Name'] = $name
        }

        # Default Enabled = $true unless explicitly set to $false
        if (-not $config.ContainsKey('Enabled')) {
            $config['Enabled'] = $true
        }

        $this.Sources[$name] = $config
        Write-TelemetryLog "Registered data source: $name"
    }

    [void]CollectFromAllSources() {
        foreach ($sourceName in $this.Sources.Keys) {
            try {
                $this.CollectFromSource($sourceName)
            }
            catch {
                Write-TelemetryLog (
                    "Error collecting from source '{0}': {1}" -f $sourceName, $_.Exception.Message
                ) 'Error'
            }
        }
    }

    [void]CollectFromSource([string]$sourceName) {
        if (-not $this.Sources.ContainsKey($sourceName)) {
            Write-TelemetryLog "CollectFromSource called with unknown source '$sourceName'." 'Warning'
            return
        }

        $source = $this.Sources[$sourceName]

        # Treat missing Enabled as true; anything explicitly $false is skipped.
        if ($source.ContainsKey('Enabled') -and -not $source.Enabled) {
            Write-TelemetryLog "Source '$sourceName' is disabled; skipping collection."
            return
        }

        if (-not $source.ContainsKey('Type')) {
            Write-TelemetryLog "Source '$sourceName' has no Type defined; skipping." 'Warning'
            return
        }

        Write-TelemetryLog "Collecting from data source: $sourceName"

        switch ($source.Type) {
            'WindowsEventLog' { $this.CollectWindowsEvents($source) }
            'IISLogs' { $this.CollectIISLogs($source) }
            'PerformanceCounters' { $this.CollectPerformanceCounters($source) }
            'CustomScript' { $this.CollectFromScript($source) }
            'SQLQuery' { $this.CollectFromSQL($source) }
            'WebAPI' { $this.CollectFromWebAPI($source) }
            default {
                Write-TelemetryLog "Unknown source type for '$sourceName': $($source.Type)" 'Warning'
            }
        }
    }

    [void]CollectWindowsEvents([hashtable]$config) {
        if (-not $config.LogNames) {
            Write-TelemetryLog "WindowsEventLog source '$($config.Name)' missing LogNames; skipping." 'Warning'
            return
        }

        $intervalMinutes = if ($config.IntervalMinutes) { [int]$config.IntervalMinutes } else { 5 }
        $maxEvents = if ($config.MaxEvents) { [int]$config.MaxEvents } else { 100 }

        # Build the filter hashtable. Level can be a single Int32 or an array.
        $filter = @{
            LogName   = $config.LogNames
            StartTime = (Get-Date).AddMinutes(-$intervalMinutes)
        }

        if ($config.LevelsToCapture) {
            $filter['Level'] = $config.LevelsToCapture
        }

        try {
            $events = Get-WinEvent -FilterHashtable $filter -MaxEvents $maxEvents -ErrorAction Stop
        }
        catch {
            Write-TelemetryLog (
                "Failed to read Windows Event Logs for '$($config.Name)': $($_.Exception.Message)"
            ) 'Error'
            return
        }

        if ($events) {
            $this.StageData('windows_events', $events, $config.TargetTable)
        }
        else {
            Write-TelemetryLog "No Windows Event Log entries found for '$($config.Name)' in interval."
        }
    }

    [void]CollectIISLogs([hashtable]$config) {
        if (-not $config.LogPath) {
            Write-TelemetryLog "IISLogs source '$($config.Name)' missing LogPath; skipping." 'Warning'
            return
        }

        $maxLines = if ($config.MaxLines) { [int]$config.MaxLines } else { 1000 }

        try {
            $logFiles = Get-ChildItem -Path $config.LogPath -Filter "*.log" -ErrorAction Stop |
                Where-Object { $_.LastWriteTime -gt (Get-Date).AddHours(-1) }
        }
        catch {
            Write-TelemetryLog (
                "Failed to enumerate IIS logs for '$($config.Name)': $($_.Exception.Message)"
            ) 'Error'
            return
        }

        foreach ($logFile in $logFiles) {
            try {
                $newLines = Get-Content -LiteralPath $logFile.FullName -ErrorAction Stop |
                    Select-Object -Last $maxLines
            }
            catch {
                Write-TelemetryLog (
                    "Failed to read IIS log '$($logFile.FullName)': $($_.Exception.Message)"
                ) 'Error'
                continue
            }

            if ($newLines) {
                $this.StageData('iis_logs', $newLines, $config.TargetTable)
            }
        }
    }

    [void]CollectPerformanceCounters([hashtable]$config) {
        if (-not $config.Counters) {
            Write-TelemetryLog "PerformanceCounters source '$($config.Name)' missing Counters; skipping." 'Warning'
            return
        }

        try {
            $counters = Get-Counter -Counter $config.Counters -SampleInterval 1 -MaxSamples 1 -ErrorAction Stop
        }
        catch {
            Write-TelemetryLog (
                "Get-Counter failed for '$($config.Name)': $($_.Exception.Message)"
            ) 'Error'
            return
        }

        $data = foreach ($counter in $counters.CounterSamples) {
            @{
                Counter      = $counter.Path
                Value        = $counter.CookedValue
                Timestamp    = $counter.Timestamp
                InstanceName = $counter.InstanceName
            }
        }

        if ($data) {
            $this.StageData('performance_counters', $data, $config.TargetTable)
        }
        else {
            Write-TelemetryLog "No performance counter data collected for '$($config.Name)'."
        }
    }

    [void]CollectFromScript([hashtable]$config) {
        if (-not $config.ScriptPath) {
            Write-TelemetryLog "CustomScript source '$($config.Name)' missing ScriptPath; skipping." 'Warning'
            return
        }

        $scriptPath = $config.ScriptPath

        if (-not (Test-Path -LiteralPath $scriptPath)) {
            Write-TelemetryLog "CustomScript path not found for '$($config.Name)': $scriptPath" 'Error'
            return
        }

        $parameters = @{}
        if ($config.ContainsKey('Parameters') -and $config.Parameters) {
            if ($config.Parameters -is [hashtable]) {
                $parameters = $config.Parameters
            }
            else {
                # Fallback: wrap arbitrary value in a single parameter if needed.
                $parameters = @{ Value = $config.Parameters }
            }
        }

        try {
            $result = if ($parameters.Count -gt 0) {
                & $scriptPath @parameters
            }
            else {
                & $scriptPath
            }
        }
        catch {
            Write-TelemetryLog (
                "CustomScript execution failed for '$($config.Name)': $($_.Exception.Message)"
            ) 'Error'
            return
        }

        if ($null -ne $result) {
            # Use the logical source name for staged files here
            $this.StageData($config.Name, $result, $config.TargetTable)
        }
        else {
            Write-TelemetryLog "CustomScript for '$($config.Name)' returned no data."
        }
    }

    [void]CollectFromSQL([hashtable]$config) {
        # Placeholder for actual SQL implementation
        Write-TelemetryLog "SQL collection not yet implemented for: $($config.Name)"
    }

    [void]CollectFromWebAPI([hashtable]$config) {
        if (-not $config.Endpoint) {
            Write-TelemetryLog "WebAPI source '$($config.Name)' missing Endpoint; skipping." 'Warning'
            return
        }

        # PS 5.1 compatible "null-coalesce" for headers
        $headers = @{}
        if ($config.ContainsKey('Headers') -and $config.Headers) {
            $headers = $config.Headers
        }

        $method = if ($config.ContainsKey('Method') -and $config.Method) {
            $config.Method
        }
        else {
            'GET'
        }

        $body = $null
        if ($config.ContainsKey('Body')) {
            $body = $config.Body
        }

        try {
            if ($method -eq 'GET') {
                $response = Invoke-RestMethod -Uri $config.Endpoint -Headers $headers -TimeoutSec 30
            }
            else {
                $response = Invoke-RestMethod -Uri $config.Endpoint -Headers $headers -Method $method -Body $body -TimeoutSec 30
            }

            if ($null -ne $response) {
                $this.StageData($config.Name, $response, $config.TargetTable)
            }
            else {
                Write-TelemetryLog "WebAPI '$($config.Name)' returned no data."
            }
        }
        catch {
            Write-TelemetryLog (
                "Web API collection failed for '$($config.Name)': $($_.Exception.Message)"
            ) 'Error'
        }
    }

    [void]StageData([string]$sourceName, [object]$data, [string]$targetTable) {
        if (-not $this.StagingDirectory) {
            Write-TelemetryLog "StagingDirectory is not set; cannot stage data for '$sourceName'." 'Error'
            return
        }

        # Ensure staging directory exists before writing
        if (-not (Test-Path -LiteralPath $this.StagingDirectory)) {
            try {
                New-Item -ItemType Directory -Path $this.StagingDirectory -Force | Out-Null
            }
            catch {
                Write-TelemetryLog (
                    "Failed to create staging directory '$($this.StagingDirectory)': $($_.Exception.Message)"
                ) 'Error'
                return
            }
        }

        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $filename = "{0}_{1}.json" -f $sourceName, $timestamp
        $filepath = Join-Path -Path $this.StagingDirectory -ChildPath $filename

        $stageData = @{
            SourceName  = $sourceName
            TargetTable = $targetTable
            Timestamp   = Get-Date
            Data        = $data
        }

        try {
            $json = $stageData | ConvertTo-Json -Depth 10
            $json | Out-File -FilePath $filepath -Encoding UTF8 -Force
        }
        catch {
            Write-TelemetryLog (
                "Failed to stage data for '$sourceName' to '$filepath': $($_.Exception.Message)"
            ) 'Error'
            return
        }

        # Safe-ish record count: 0 for $null, otherwise arrayified count
        $recordCount = if ($null -eq $data) { 0 } else { @($data).Count }

        Write-TelemetryLog (
            "Staged {0} records from '{1}' to '{2}'" -f $recordCount, $sourceName, $filename
        )
    }
}

function Get-DefaultDataSources {
    <#
    .SYNOPSIS
        Returns the default data source configuration hashtable.

    .OUTPUTS
        [hashtable] where keys are source names and values are source configs.
    #>
    return @{
        'WindowsEvents'     = @{
            Type            = 'WindowsEventLog'
            Enabled         = $true
            LogNames        = @('Application', 'System', 'Security')
            LevelsToCapture = @(1, 2, 3, 4)  # Critical, Error, Warning, Info
            IntervalMinutes = 5
            MaxEvents       = 100
            TargetTable     = 'telemetry.eventlog_windows_template'
        }

        'IISLogs'           = @{
            Type        = 'IISLogs'
            Enabled     = $false  # Requires IIS to be installed
            LogPath     = 'C:\inetpub\logs\LogFiles\W3SVC1'
            MaxLines    = 1000
            TargetTable = 'telemetry.iis_requests_template'
        }

        'SystemPerformance' = @{
            Type        = 'PerformanceCounters'
            Enabled     = $true
            Counters    = @(
                '\Processor(_Total)\% Processor Time',
                '\Memory\Available MBytes',
                '\System\System Up Time'
            )
            TargetTable = 'telemetry.performance_metrics'
        }

        'SQLServerHealth'   = @{
            Type             = 'SQLQuery'
            Enabled          = $false
            ConnectionString = 'Server=localhost;Trusted_Connection=true;'
            Query            = 'SELECT name, state_desc FROM sys.databases'
            TargetTable      = 'telemetry.sql_health'
        }

        'WebServiceHealth'  = @{
            Type        = 'WebAPI'
            Enabled     = $false
            Endpoint    = 'https://api.example.com/health'
            Headers     = @{ 'Accept' = 'application/json' }
            TargetTable = 'telemetry.service_health'
        }
    }
}

function Initialize-DataSourceManager {
    <#
    .SYNOPSIS
        Creates and initializes a DataSourceManager instance with default sources.

    .PARAMETER StagingDirectory
        Folder where staged JSON payloads will be written.

    .OUTPUTS
        [DataSourceManager]
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$StagingDirectory = './var/staging'
    )

    $manager = [DataSourceManager]::new($StagingDirectory)

    # Register default sources
    $defaultSources = Get-DefaultDataSources
    foreach ($sourceName in $defaultSources.Keys) {
        $manager.RegisterSource($sourceName, $defaultSources[$sourceName])
    }

    return $manager
}

Export-ModuleMember -Function Initialize-DataSourceManager, Get-DefaultDataSources
### END FILE: DataSourceManager.psm1

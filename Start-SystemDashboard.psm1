### BEGIN FILE: SystemDashboard Listener
#requires -Version 7
<# 
.SYNOPSIS 
    HTTP-based system metrics endpoint with extended telemetry.
.DESCRIPTION 
    Exposes CPU, memory, disk, events, network, uptime, processes, and latency. 
    Provides a Start-SystemDashboardListener function used by tests.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Determine config path with fallback for empty $PSScriptRoot
# In some contexts (e.g., pwsh -Command), $PSScriptRoot may be empty
# Use $PSCommandPath as fallback, then Get-Location as last resort
$script:ModuleRoot = if ($PSScriptRoot) { 
    $PSScriptRoot 
} elseif ($PSCommandPath) { 
    Split-Path -Parent $PSCommandPath 
} else { 
    Get-Location 
}

$ConfigPath = if ($env:SYSTEMDASHBOARD_CONFIG) { 
    $env:SYSTEMDASHBOARD_CONFIG 
} else { 
    Join-Path $script:ModuleRoot 'config.json' 
}

$script:Config = @{}
$script:ConfigPath = $null
$script:ConfigBase = $script:ModuleRoot
if ($ConfigPath -and (Test-Path -LiteralPath $ConfigPath -ErrorAction SilentlyContinue)) {
    $resolvedConfig = (Resolve-Path -LiteralPath $ConfigPath).Path
    $script:ConfigPath = $resolvedConfig
    $script:ConfigBase = Split-Path -Parent $resolvedConfig
    $script:Config = Get-Content -LiteralPath $resolvedConfig -Raw | ConvertFrom-Json
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    $ts = Get-Date -Format o
    Write-Information "[$ts] [$Level] $Message" -InformationAction Continue
}

function Get-MockSystemMetrics {
    [CmdletBinding()]
    param()
    
    Write-Log -Level 'INFO' -Message "Generating mock system metrics for demonstration purposes"
    
    $nowUtc = (Get-Date).ToUniversalTime()
    $computerName = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { "MockHost" }
    
    # Mock CPU, Memory, Disk data
    $cpuPct = Get-Random -Minimum 5 -Maximum 85
    $totalMemGB = 16.0
    $usedMemGB = Get-Random -Minimum 4.0 -Maximum 12.0
    $freeMemGB = $totalMemGB - $usedMemGB
    $memPct = [math]::Round(($usedMemGB / $totalMemGB), 4)
    
    $disks = @(
        [pscustomobject]@{
            Drive = "C"
            TotalGB = 500.0
            UsedGB = Get-Random -Minimum 100.0 -Maximum 400.0
            UsedPct = 0.6
        },
        [pscustomobject]@{
            Drive = "D"
            TotalGB = 1000.0
            UsedGB = Get-Random -Minimum 200.0 -Maximum 800.0
            UsedPct = 0.4
        }
    )
    
    # Mock uptime
    $uptime = @{
        Days = Get-Random -Minimum 0 -Maximum 30
        Hours = Get-Random -Minimum 0 -Maximum 23
        Minutes = Get-Random -Minimum 0 -Maximum 59
    }
    
    # Mock events
    $warnSources = @('Application Error', 'System', 'DNS Client', 'Service Control Manager')
    $errSources = @('Application Error', 'System', 'DCOM')
    $warnSummary = $warnSources | ForEach-Object { 
        [pscustomobject]@{ Source=$_; Count=(Get-Random -Minimum 1 -Maximum 10) } 
    }
    $errSummary = $errSources | ForEach-Object { 
        [pscustomobject]@{ Source=$_; Count=(Get-Random -Minimum 1 -Maximum 5) } 
    }
    
    # Mock network
    $netUsage = @(
        [pscustomobject]@{ 
            Adapter="Ethernet"; 
            BytesSentPerSec=(Get-Random -Minimum 1000 -Maximum 50000); 
            BytesRecvPerSec=(Get-Random -Minimum 5000 -Maximum 100000) 
        }
    )
    $latencyMs = Get-Random -Minimum 1 -Maximum 100
    
    # Mock processes
    $processNames = @('explorer', 'chrome', 'code', 'powershell', 'svchost')
    $topProcs = $processNames | ForEach-Object { 
        [pscustomobject]@{ 
            Name=$_; 
            CPU=([math]::Round((Get-Random -Minimum 0.1 -Maximum 25.5), 2)); 
            Id=(Get-Random -Minimum 1000 -Maximum 9999) 
        } 
    }
    
    return [pscustomobject]@{
        Time          = $nowUtc
        ComputerName  = $computerName
        CPU           = @{ Pct = $cpuPct }
        Memory        = @{ TotalGB=$totalMemGB; FreeGB=$freeMemGB; UsedGB=$usedMemGB; Pct=$memPct }
        Disk          = $disks
        Uptime        = $uptime
        Events        = @{ Warnings=$warnSummary; Errors=$errSummary }
        Network       = @{ Usage=$netUsage; LatencyMs=$latencyMs }
        Processes     = $topProcs
    }
}

function Resolve-ConfigPathValue {
    [CmdletBinding()]
    param(
        [Parameter()][string]$PathValue
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $null
    }

    try {
        $expanded = [Environment]::ExpandEnvironmentVariables($PathValue)
        if ($expanded.StartsWith('~')) {
            $home = [Environment]::GetFolderPath('UserProfile')
            if ($home) {
                $expanded = Join-Path $home ($expanded.Substring(1).TrimStart('\\','/'))
            }
        }

        if ([System.IO.Path]::IsPathRooted($expanded)) {
            return [System.IO.Path]::GetFullPath($expanded)
        }

        $basePath = if ($script:ConfigBase) { $script:ConfigBase } else { $PSScriptRoot }
        return [System.IO.Path]::GetFullPath((Join-Path $basePath $expanded))
    }
    catch {
        throw "Failed to resolve path '$PathValue'. $_"
    }
}

function Get-ContentType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    switch ($extension) {
        '.css'  { 'text/css' }
        '.js'   { 'application/javascript' }
        '.json' { 'application/json' }
        '.svg'  { 'image/svg+xml' }
        '.png'  { 'image/png' }
        '.jpg'  { 'image/jpeg' }
        '.jpeg' { 'image/jpeg' }
        '.ico'  { 'image/x-icon' }
        Default { 'text/html' }
    }
}

function Ensure-UrlAcl {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Prefix)
    if (-not $IsWindows) { return }
    try {
        $exists = netsh http show urlacl | Select-String -SimpleMatch $Prefix -Quiet    
        if (-not $exists) {      
            $user = "$env:USERDOMAIN\$env:USERNAME"      
            Start-Process -FilePath netsh -ArgumentList @('http','add','urlacl',"url=$Prefix",("user={0}" -f $user)) -Wait -WindowStyle Hidden | Out-Null    
        }  
    } catch {
        Write-Log -Level 'WARN' -Message "Ensure-UrlAcl failed: $_"
    }
}

function Remove-UrlAcl {  
    [CmdletBinding()]  
    param([Parameter(Mandatory)][string] $Prefix)  
    if (-not $IsWindows) { return }  
    try {    
        Start-Process -FilePath netsh -ArgumentList @('http','delete','urlacl',"url=$Prefix") -Wait -WindowStyle Hidden | Out-Null  
    } catch {
        Write-Log -Level 'WARN' -Message "Remove-UrlAcl failed: $_"
    }
}

function Start-SystemDashboardListener {
    [CmdletBinding()]
    param(
        [Parameter()][string] $Prefix,
        [Parameter()][string] $Root,
        [Parameter()][string] $IndexHtml,
        [Parameter()][string] $CssFile,
        [Parameter()][string] $PingTarget
    )
    if (-not $Prefix) {
        if ($env:SYSTEMDASHBOARD_PREFIX) { $Prefix = $env:SYSTEMDASHBOARD_PREFIX }
        elseif ($script:Config.Prefix) { $Prefix = $script:Config.Prefix }
    }
    if (-not $Root) {
        if ($env:SYSTEMDASHBOARD_ROOT) { $Root = $env:SYSTEMDASHBOARD_ROOT }
        elseif ($script:Config.Root) { $Root = $script:Config.Root }
    }
    if (-not $IndexHtml -and $script:Config.IndexHtml) { $IndexHtml = $script:Config.IndexHtml }
    if (-not $CssFile -and $script:Config.CssFile) { $CssFile = $script:Config.CssFile }
    if (-not $PingTarget) { $PingTarget = $script:Config.PingTarget }
    if (-not $PingTarget) { $PingTarget = '1.1.1.1' }
    $Root = Resolve-ConfigPathValue $Root
    if (-not $Root) {
        throw 'Prefix, Root, IndexHtml, and CssFile are required.'
    }
    if (-not $IndexHtml) {
        $IndexHtml = [System.IO.Path]::GetFullPath((Join-Path $Root 'index.html'))
    } else {
        $IndexHtml = Resolve-ConfigPathValue $IndexHtml
    }
    if (-not $CssFile) {
        $CssFile = [System.IO.Path]::GetFullPath((Join-Path $Root 'styles.css'))
    } else {
        $CssFile = Resolve-ConfigPathValue $CssFile
    }
    if (-not $Prefix -or -not $Root -or -not $IndexHtml -or -not $CssFile) {
        throw 'Prefix, Root, IndexHtml, and CssFile are required.'
    }
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "Root path not found: $Root"
    }
    foreach ($asset in @($IndexHtml, $CssFile)) {
        if (-not (Test-Path -LiteralPath $asset -PathType Leaf)) {
            throw "Static asset not found: $asset"
        }
    }
    Ensure-UrlAcl -Prefix $Prefix
    $l = [System.Net.HttpListener]::new()
    $l.Prefixes.Add($Prefix)
    $l.Start()
    Write-Log -Message "Listening on $Prefix"
    # Cache for network deltas
    $prevNet = @{}

    try {
        while ($true) {
            $context = $l.GetContext()
            $req = $context.Request
            $res = $context.Response
            $rawPath = $req.RawUrl.Split('?',2)[0]
            $requestPath = [System.Uri]::UnescapeDataString($rawPath)
            if ($requestPath -eq '/metrics') {
                # Try to collect real metrics on Windows, fallback to mock data otherwise
                try {
                    if (-not $IsWindows) {
                        throw "Non-Windows platform detected"
                    }
                    
                    $nowUtc = (Get-Date).ToUniversalTime().ToString('o')
                    $computerName = $env:COMPUTERNAME        
                    # CPU        
                    $cpuPct = 0        
                    try { $cpuPct = [math]::Round((Get-Counter '\\Processor(_Total)\\% Processor Time').CounterSamples.CookedValue, 2) } catch { $cpuPct = -1 }        
                    # Memory        
                    $os = Get-CimInstance Win32_OperatingSystem        
                    $totalMemGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)        
                    $freeMemGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 2)        
                    $usedMemGB  = $totalMemGB - $freeMemGB        
                    $memPct     = if ($totalMemGB -gt 0) { [math]::Round(($usedMemGB / $totalMemGB), 4) } else { 0 }        
                    # Disks        
                    $fixedDrives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"        
                    $disks = $fixedDrives | ForEach-Object {          
                        $sizeGB = [math]::Round($_.Size / 1GB, 2)          
                        $freeGB = [math]::Round($_.FreeSpace / 1GB, 2)          
                        [pscustomobject]@{            
                            Drive = $_.DeviceID.TrimEnd(':')            
                            TotalGB = $sizeGB            
                            UsedGB  = $sizeGB - $freeGB            
                            UsedPct = if ($sizeGB -gt 0) { [math]::Round((($sizeGB - $freeGB) / $sizeGB), 4) } else { 0 }          
                        }        
                    }        
                    # Uptime        
                    $bootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime        
                    $uptime   = (Get-Date) - $bootTime        
                    # Events last hour        
                    $startTime = (Get-Date).AddHours(-1)        
                    $warns = Get-WinEvent -FilterHashtable @{LogName='System','Application'; Level=3; StartTime=$startTime} -ErrorAction SilentlyContinue        
                    $errs  = Get-WinEvent -FilterHashtable @{LogName='System','Application'; Level=2; StartTime=$startTime} -ErrorAction SilentlyContinue        
                    $warnSummary = $warns | Group-Object ProviderName | ForEach-Object { [pscustomobject]@{ Source=$_.Name; Count=$_.Count } }        
                    $errSummary  = $errs  | Group-Object ProviderName | ForEach-Object { [pscustomobject]@{ Source=$_.Name; Count=$_.Count } }        
                    # Network usage delta        
                    $netUsage = @()        
                    try {          
                        Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object {            
                            $name  = $_.Name            
                            $stats = Get-NetAdapterStatistics -Name $name            
                            $prev  = $prevNet[$name]            
                            if ($prev) {              
                                $sentBps = [math]::Round((($stats.OutboundBytes - $prev.OutboundBytes)), 2)              
                                $recvBps = [math]::Round((($stats.InboundBytes  - $prev.InboundBytes)), 2)              
                                $netUsage += [pscustomobject]@{ Adapter=$name; BytesSentPerSec=$sentBps; BytesRecvPerSec=$recvBps }            
                            }            
                            $prevNet[$name] = $stats          
                        }        
                    } catch {}        
                    # Ping latency        
                    $latencyMs = -1        
                    try {          
                        $ping = Test-Connection -ComputerName $PingTarget -Count 1 -ErrorAction Stop          
                        if ($ping) { $latencyMs = [int]($ping | Select-Object -First 1).ResponseTime }        
                    } catch {}        
                    # Top processes        
                    $topProcs = Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 | ForEach-Object {          
                        [pscustomobject]@{ Name=$_.ProcessName; CPU=$([math]::Round($_.CPU,2)); Id=$_.Id }        
                    }        
                    $metrics = [pscustomobject]@{
                        Time          = $nowUtc
                        ComputerName  = $computerName
                        CPU           = @{ Pct = $cpuPct }
                        Memory        = @{ TotalGB=$totalMemGB; FreeGB=$freeMemGB; UsedGB=$usedMemGB; Pct=$memPct }
                        Disk          = $disks
                        Uptime        = @{ Days=$uptime.Days; Hours=$uptime.Hours; Minutes=$uptime.Minutes }
                        Events        = @{ Warnings=$warnSummary; Errors=$errSummary }
                        Network       = @{ Usage=$netUsage; LatencyMs=$latencyMs }
                        Processes     = $topProcs
                    }
                } catch {
                    Write-Log -Level 'WARN' -Message "Failed to collect real metrics ($($_.Exception.Message)). Using mock data."
                    $metrics = Get-MockSystemMetrics
                }
                $json = $metrics | ConvertTo-Json -Depth 5
                $buf  = [Text.Encoding]::UTF8.GetBytes($json)
                $res.ContentType = 'application/json'
                $res.Headers['Cache-Control'] = 'no-store'
                $res.ContentLength64 = $buf.Length
                $res.OutputStream.Write($buf,0,$buf.Length)
                $res.Close()
                continue
            } elseif ($requestPath -eq '/scan-clients') {
                # Scan for connected clients
                $clients = Scan-ConnectedClients
                $json = $clients | ConvertTo-Json -Depth 5
                $buf  = [Text.Encoding]::UTF8.GetBytes($json)
                $res.ContentType = 'application/json'
                $res.OutputStream.Write($buf,0,$buf.Length)
                $res.Close()
                continue
            } elseif ($requestPath -eq '/router-login') {
                # Handle router login
                $credentials = Get-RouterCredentials
                $json = $credentials | ConvertTo-Json -Depth 5
                $buf  = [Text.Encoding]::UTF8.GetBytes($json)
                $res.ContentType = 'application/json'
                $res.OutputStream.Write($buf,0,$buf.Length)
                $res.Close()
                continue
            } elseif ($requestPath -eq '/system-logs') {
                # Retrieve system logs
                $logs = Get-SystemLogs
                $json = $logs | ConvertTo-Json -Depth 5
                $buf  = [Text.Encoding]::UTF8.GetBytes($json)
                $res.ContentType = 'application/json'
                $res.OutputStream.Write($buf,0,$buf.Length)
                $res.Close()
                continue
            }
            # Static files
            $file = switch ($requestPath) {
                '/'           { $IndexHtml }
                '/index.html' { $IndexHtml }
                '/styles.css' { $CssFile }
                Default {
                    $relative = $requestPath.TrimStart('/')
                    if ([string]::IsNullOrWhiteSpace($relative)) {
                        $IndexHtml
                    } else {
                        $normalized = $relative -replace '/', [System.IO.Path]::DirectorySeparatorChar
                        $candidate = [System.IO.Path]::GetFullPath((Join-Path $Root $normalized))
                        if ($candidate.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
                            $candidate
                        } else {
                            $null
                        }
                    }
                }
            }
            if ($file -and (Test-Path -LiteralPath $file -PathType Leaf)) {
                $bytes = [IO.File]::ReadAllBytes($file)
                $res.ContentType = Get-ContentType -Path $file
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes,0,$bytes.Length)
            } else {
                $res.StatusCode = 404
                $res.StatusDescription = 'Not Found'
            }
            $res.Close()
        }
    } catch {
        Write-Log -Level 'ERROR' -Message $_
    } finally {
        try { $l.Stop(); $l.Close() } catch {}
    }
}

function Start-SystemDashboard {
    [CmdletBinding()]
    param(
        [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json')
    )
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Config file not found: $ConfigPath"
    }
    $resolved = (Resolve-Path -LiteralPath $ConfigPath).Path
    $script:ConfigPath = $resolved
    $script:ConfigBase = Split-Path -Parent $resolved
    $script:Config = Get-Content -LiteralPath $resolved -Raw | ConvertFrom-Json
    Start-SystemDashboardListener
}

function Scan-ConnectedClients {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidatePattern('^(?:\d{1,3}\.){3}\d{1,3}$')]
        [string]$NetworkPrefix = '192.168.1'  # e.g. '192.168.1' for /24
    )

    # Return mock data if not on Windows or if Get-NetNeighbor is not available
    if (-not $IsWindows -or -not (Get-Command Get-NetNeighbor -ErrorAction SilentlyContinue)) {
        Write-Log -Level 'INFO' -Message "Generating mock network client data (Windows-specific features not available)"
        return @(
            [PSCustomObject]@{
                IPAddress  = "$NetworkPrefix.10"
                Hostname   = "router.local"
                MACAddress = "00:11:22:33:44:55"
                State      = "Reachable"
            },
            [PSCustomObject]@{
                IPAddress  = "$NetworkPrefix.25"
                Hostname   = "laptop-01"
                MACAddress = "AA:BB:CC:DD:EE:FF"
                State      = "Reachable"
            },
            [PSCustomObject]@{
                IPAddress  = "$NetworkPrefix.50"
                Hostname   = $null
                MACAddress = "11:22:33:44:55:66"
                State      = "Reachable"
            }
        )
    }

    try {
        # 1) Generate all IPs in the /24 (1..254)
        $addresses = 1..254 | ForEach-Object { "$NetworkPrefix.$_" }

        # 2) Fire off parallel ping sweep to populate ARP table
        Write-Log -Level 'INFO' -Message "Pinging $($addresses.Count) addresses to prime ARP cache..."
        $pingParams = @{
            Count        = 1
            Quiet        = $true
            Timeout      = 200      # ms; bump if you have a slow network
        }
        $addresses | ForEach-Object -Parallel {
            Test-Connection -ComputerName $_ @using:pingParams
        } -ThrottleLimit 50       # adjust parallelism to your CPU/network

        # 3) Wait a tick for ARP entries to settle
        Start-Sleep -Milliseconds 500

        # 4) Pull the ARP table entries for our subnet
        $neighbors = Get-NetNeighbor `
            | Where-Object {
                $_.State -eq 'Reachable' -and
                $_.IPAddress -like "$NetworkPrefix.*"
            }

        # 5) Build PSCustomObjects with DNS lookups
        $clients = foreach ($n in $neighbors) {
            # Try to get the DNS name; swallow errors if reverse-DNS is off
            try {
                $name = (Resolve-DnsName -Name $n.IPAddress -ErrorAction Stop).NameHost
            } catch {
                $name = $null
            }

            [PSCustomObject]@{
                IPAddress  = $n.IPAddress
                Hostname   = $name
                MACAddress = $n.LinkLayerAddress
                State      = $n.State
            }
        }

        # 6) Return the list (empty if nothing found)
        return $clients
    } catch {
        Write-Log -Level 'WARN' -Message "Network scan failed: $($_.Exception.Message). Returning empty list."
        return @()
    }
}

function Get-RouterCredentials {
    [CmdletBinding()]
    param(
        # The IP or hostname of your router
        [ValidateNotNullOrEmpty()]
        [string]$RouterIP
    )

    if (-not $RouterIP) {
        if ($env:ROUTER_IP) { $RouterIP = $env:ROUTER_IP }
        elseif ($script:Config.RouterIP) { $RouterIP = $script:Config.RouterIP }
        else { $RouterIP = '192.168.50.1' }
    }

    Import-Module CredentialManager -ErrorAction SilentlyContinue | Out-Null
    $target = "SystemDashboard:$RouterIP"
    $credential = $null
    if (Get-Command Get-StoredCredential -ErrorAction SilentlyContinue) {
        $stored = Get-StoredCredential -Target $target
        if ($stored) {
            $secure = $stored.Password | ConvertTo-SecureString -AsPlainText -Force
            $credential = [PSCredential]::new($stored.UserName, $secure)
        } else {
            $credential = Get-Credential -Message "Enter administrator credentials for router $RouterIP"
            New-StoredCredential -Target $target -UserName $credential.UserName -Password ($credential.GetNetworkCredential().Password) -Persist LocalMachine | Out-Null
        }
    } else {
        $credential = Get-Credential -Message "Enter administrator credentials for router $RouterIP"
    }

    # 2) Quick reachability check
    Write-Log -Level 'INFO' -Message "Pinging router at $RouterIP to verify it’s up..."
    if (-not (Test-Connection -ComputerName $RouterIP -Count 1 -Quiet)) {
        throw "ERROR: Cannot reach router at $RouterIP. Check network connectivity."
    }

    # 3) Verify login via SSH/HTTP here (if SSH module is available).
    if (Get-Command New-SSHSession -ErrorAction SilentlyContinue) {
        try {
            New-SSHSession -ComputerName $RouterIP -Credential $credential -ErrorAction Stop | Remove-SSHSession
            Write-Log -Level 'INFO' -Message "SSH authentication to $RouterIP succeeded."
        } catch {
            throw "ERROR: SSH authentication to $RouterIP failed. $_"
        }
    } else {
        Write-Log -Level 'WARN' -Message "SSH module not available. Skipping router authentication verification."
    }

    # 4) Package up and return
    [PSCustomObject]@{
        RouterIP   = $RouterIP
        Credential = $credential
    }
}

function Get-SystemLogs {
    [CmdletBinding()]
    param(
        # Which Windows Event Log to read (Application, System, Security, etc.)
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$LogName = @('Application','System'),

        # Maximum number of events to retrieve per log
        [Parameter()]
        [ValidateRange(1, 10000)]
        [int]$MaxEvents = 100,

        # Minimum level to include: Info, Warning, Error, Critical
        [Parameter()]
        [ValidateSet('Information','Warning','Error','Critical')]
        [string]$MinimumLevel = 'Warning'
    )

    # Return mock data if not on Windows or if Get-WinEvent is not available
    if (-not $IsWindows -or -not (Get-Command Get-WinEvent -ErrorAction SilentlyContinue)) {
        Write-Log -Level 'INFO' -Message "Generating mock system logs (Windows Event Log not available)"
        $mockEvents = @(
            [PSCustomObject]@{
                LogName     = "Application"
                TimeCreated = (Get-Date).AddMinutes(-30)
                Level       = "Warning"
                EventID     = 1001
                Source      = "Application Error"
                Message     = "Mock application warning - database connection timeout occurred"
            },
            [PSCustomObject]@{
                LogName     = "System"
                TimeCreated = (Get-Date).AddHours(-1)
                Level       = "Error"
                EventID     = 2001
                Source      = "Service Control Manager"
                Message     = "Mock system error - service failed to start"
            },
            [PSCustomObject]@{
                LogName     = "Application"
                TimeCreated = (Get-Date).AddHours(-2)
                Level       = "Information"
                EventID     = 1002
                Source      = "DNS Client"
                Message     = "Mock information event - DNS resolution completed successfully"
            }
        )
        
        # Filter by minimum level if needed
        $levelMap = @{
            'Critical'    = 1
            'Error'       = 2
            'Warning'     = 3
            'Information' = 4
        }
        $minLevelNum = $levelMap[$MinimumLevel]
        
        return $mockEvents | Where-Object { $levelMap[$_.Level] -le $minLevelNum } | Select-Object -First $MaxEvents
    }

    # Map friendly level names to numeric values in Windows events
    $levelMap = @{
        'Critical'    = 1
        'Error'       = 2
        'Warning'     = 3
        'Information' = 4
    }

    # Ensure we got a valid numeric threshold
    $minLevelNum = $levelMap[$MinimumLevel]

    try {
        # Loop through each requested log
        $allLogs = foreach ($log in $LogName) {
            Write-Log -Level 'INFO' -Message "Retrieving up to $MaxEvents entries from '$log' where Level ≥ $MinimumLevel..."
            
            # Query the log with filters applied
            Get-WinEvent `
                -LogName $log `
                -MaxEvents $MaxEvents `
                -ErrorAction Stop |
            Where-Object { $_.LevelDisplayName -and $levelMap[$_.LevelDisplayName] -le $minLevelNum } |
            ForEach-Object {
                # Project only the fields you care about
                [PSCustomObject]@{
                    LogName        = $log
                    TimeCreated    = $_.TimeCreated
                    Level          = $_.LevelDisplayName
                    EventID        = $_.Id
                    Source         = $_.ProviderName
                    Message        = ($_.Message -replace '\r?\n',' ')  # flatten newlines
                }
            }
        }

        return $allLogs
    }
    catch {
        throw "ERROR: Failed to retrieve system logs. $($_.Exception.Message)"
    }
}


Export-ModuleMember -Function Start-SystemDashboardListener, Start-SystemDashboard, Ensure-UrlAcl, Remove-UrlAcl, Scan-ConnectedClients, Get-RouterCredentials, Get-SystemLogs, Get-MockSystemMetrics
### END FILE: SystemDashboard Listener

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

$ConfigPath = if ($env:SYSTEMDASHBOARD_CONFIG) { $env:SYSTEMDASHBOARD_CONFIG } else { Join-Path $PSScriptRoot 'config.json' }
$script:Config = @{}
if (Test-Path $ConfigPath) {
    $script:Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
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
    if (-not $Prefix -or -not $Root -or -not $IndexHtml -or -not $CssFile) {
        throw 'Prefix, Root, IndexHtml, and CssFile are required.'
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
            if ($req.RawUrl -eq '/metrics') {        
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
                $json = $metrics | ConvertTo-Json -Depth 5        
                $buf  = [Text.Encoding]::UTF8.GetBytes($json)        
                $res.ContentType = 'application/json'        
                $res.OutputStream.Write($buf,0,$buf.Length)        
                $res.Close()        
                continue      
            } elseif ($req.RawUrl -eq '/scan-clients') {
                # Scan for connected clients
                $clients = Scan-ConnectedClients
                $json = $clients | ConvertTo-Json -Depth 5
                $buf  = [Text.Encoding]::UTF8.GetBytes($json)
                $res.ContentType = 'application/json'
                $res.OutputStream.Write($buf,0,$buf.Length)
                $res.Close()
                continue
            } elseif ($req.RawUrl -eq '/router-login') {
                # Handle router login
                $credentials = Get-RouterCredentials
                $json = $credentials | ConvertTo-Json -Depth 5
                $buf  = [Text.Encoding]::UTF8.GetBytes($json)
                $res.ContentType = 'application/json'
                $res.OutputStream.Write($buf,0,$buf.Length)
                $res.Close()
                continue
            } elseif ($req.RawUrl -eq '/system-logs') {
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
            $file = Switch ($req.RawUrl) {        
                '/'           { $IndexHtml }        
                '/index.html' { $IndexHtml }        
                '/styles.css' { $CssFile }        
                Default       { Join-Path $Root ($req.RawUrl.TrimStart('/')) }      
            }      
            if (Test-Path $file) {        
                $bytes = [IO.File]::ReadAllBytes($file)        
                $res.ContentType = if ($file -like '*.css') { 'text/css' } else { 'text/html' }        
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
    if (Test-Path $ConfigPath) {
        $script:Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    } else {
        throw "Config file not found: $ConfigPath"
    }
    Start-SystemDashboardListener
}

function Scan-ConnectedClients {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidatePattern('^(?:\d{1,3}\.){3}\d{1,3}$')]
        [string]$NetworkPrefix = '192.168.1'  # e.g. '192.168.1' for /24
    )

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

    # 3) Verify login via SSH/HTTP here.
    try {
        New-SSHSession -ComputerName $RouterIP -Credential $credential -ErrorAction Stop | Remove-SSHSession
    } catch {
        throw "ERROR: Authentication to $RouterIP failed. $_"
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


Export-ModuleMember -Function Start-SystemDashboardListener, Start-SystemDashboard, Ensure-UrlAcl, Remove-UrlAcl, Scan-ConnectedClients, Get-RouterCredentials, Get-SystemLogs
### END FILE: SystemDashboard Listener

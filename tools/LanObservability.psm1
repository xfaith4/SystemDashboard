#requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    LAN Observability Module for SystemDashboard
.DESCRIPTION
    Provides functions for collecting, tracking, and monitoring LAN devices from ASUS router.
    Implements device inventory, time-series snapshots, and syslog correlation.
#>

function Get-LanSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$DbConnection
    )
    
    $settings = @{}
    
    try {
        $cmd = $DbConnection.CreateCommand()
        $cmd.CommandText = "SELECT setting_key, setting_value FROM telemetry.lan_settings"
        $reader = $cmd.ExecuteReader()
        
        while ($reader.Read()) {
            $settings[$reader.GetString(0)] = $reader.GetString(1)
        }
        $reader.Close()
    }
    catch {
        Write-Warning "Failed to load LAN settings: $_"
        # Return defaults
        $settings = @{
            snapshot_retention_days = '7'
            inactive_threshold_minutes = '10'
            poll_interval_seconds = '300'
            syslog_correlation_enabled = 'true'
        }
    }
    
    return $settings
}

function Get-RouterClientListViaHttp {
    <#
    .SYNOPSIS
        Fetches client list from ASUS router via HTTP scraping
    .DESCRIPTION
        Attempts to retrieve the client list by parsing the router's web UI data.
        This method scrapes the same data used by the stock router UI (update_clients.asp).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RouterIP,
        [Parameter()][string]$Username = 'admin',
        [Parameter()][string]$Password,
        [Parameter()][int]$TimeoutSeconds = 30
    )
    
    $clients = @()
    
    try {
        # Build authentication header
        $base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${Username}:${Password}"))
        $headers = @{
            'Authorization' = "Basic $base64Auth"
        }
        
        # Try to fetch client list data
        # Note: Actual endpoint may vary by firmware version; adjust as needed
        $url = "http://${RouterIP}/update_clients.asp"
        
        Write-Verbose "Fetching client list from $url"
        
        $response = Invoke-WebRequest -Uri $url -Headers $headers -TimeoutSec $TimeoutSeconds -UseBasicParsing -ErrorAction Stop
        
        # Parse response - the format varies by router firmware
        # This is a simplified parser; actual implementation may need adjustment based on firmware
        $content = $response.Content
        
        # Look for client data in JavaScript object format
        if ($content -match 'originData\s*=\s*(\{.*?\});') {
            $jsonData = $matches[1]
            $data = $jsonData | ConvertFrom-Json
            
            # Parse client entries (format varies, this is an example)
            foreach ($clientKey in $data.PSObject.Properties.Name) {
                $client = $data.$clientKey
                
                $clientInfo = [PSCustomObject]@{
                    MacAddress = $clientKey
                    IpAddress = $client.ip
                    Hostname = $client.name
                    Vendor = $client.vendor
                    Interface = $client.isWL -eq '1' ? 'wireless' : 'wired'
                    Rssi = if ($client.rssi) { [int]$client.rssi } else { $null }
                    TxRate = if ($client.txRate) { [decimal]$client.txRate } else { $null }
                    RxRate = if ($client.rxRate) { [decimal]$client.rxRate } else { $null }
                    IsOnline = $true
                }
                
                $clients += $clientInfo
            }
        }
        else {
            Write-Warning "Could not parse client data from router response"
        }
    }
    catch {
        Write-Warning "Failed to fetch client list via HTTP: $_"
    }
    
    return $clients
}

function Get-RouterClientListViaSsh {
    <#
    .SYNOPSIS
        Fetches client list from ASUS router via SSH commands
    .DESCRIPTION
        Connects to router via SSH and executes commands to gather client information.
        More reliable than HTTP scraping but requires SSH access and Posh-SSH module.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RouterIP,
        [Parameter()][string]$Username = 'admin',
        [Parameter()][string]$Password,
        [Parameter()][int]$TimeoutSeconds = 30,
        [Parameter()][int]$Port = 22
    )
    
    $clients = @()
    
    # Check if Posh-SSH is available
    if (-not (Get-Module -Name Posh-SSH -ListAvailable)) {
        Write-Warning "Posh-SSH module not available. Install with: Install-Module -Name Posh-SSH"
        return $clients
    }
    
    Import-Module Posh-SSH -ErrorAction SilentlyContinue
    
    try {
        $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($Username, $securePassword)
        
        Write-Verbose "Connecting to router at $RouterIP via SSH"
        $session = New-SSHSession -ComputerName $RouterIP -Credential $credential -Port $Port -AcceptKey -ConnectionTimeout $TimeoutSeconds -ErrorAction Stop
        
        # Get ARP table for IP-to-MAC mapping
        $arpResult = Invoke-SSHCommand -SessionId $session.SessionId -Command "arp -a" -TimeOut $TimeoutSeconds
        $arpTable = @{}
        
        if ($arpResult.Output) {
            foreach ($line in $arpResult.Output) {
                # Parse ARP lines: format is typically "hostname (192.168.x.x) at aa:bb:cc:dd:ee:ff"
                if ($line -match '(\d+\.\d+\.\d+\.\d+).*?([0-9a-fA-F:]{17})') {
                    $ip = $matches[1]
                    $mac = $matches[2].ToUpper()
                    $arpTable[$mac] = $ip
                }
            }
        }
        
        # Get wireless clients from wl command
        $wlResult = Invoke-SSHCommand -SessionId $session.SessionId -Command "wl assoclist" -TimeOut $TimeoutSeconds
        
        if ($wlResult.Output) {
            foreach ($line in $wlResult.Output) {
                # Parse MAC addresses from assoclist output
                if ($line -match '([0-9a-fA-F:]{17})') {
                    $mac = $matches[1].ToUpper()
                    $ip = $arpTable[$mac]
                    
                    # Try to get signal strength for this client
                    $rssiResult = Invoke-SSHCommand -SessionId $session.SessionId -Command "wl -i eth2 rssi $mac" -TimeOut 5
                    $rssi = $null
                    if ($rssiResult.Output -and $rssiResult.Output[0] -match '-?\d+') {
                        $rssi = [int]$matches[0]
                    }
                    
                    $clientInfo = [PSCustomObject]@{
                        MacAddress = $mac
                        IpAddress = $ip
                        Hostname = $null
                        Vendor = $null
                        Interface = 'wireless'
                        Rssi = $rssi
                        TxRate = $null
                        RxRate = $null
                        IsOnline = $true
                    }
                    
                    $clients += $clientInfo
                }
            }
        }
        
        # Get wired clients from ARP table (those not in wireless list)
        foreach ($mac in $arpTable.Keys) {
            if (-not ($clients | Where-Object { $_.MacAddress -eq $mac })) {
                $clientInfo = [PSCustomObject]@{
                    MacAddress = $mac
                    IpAddress = $arpTable[$mac]
                    Hostname = $null
                    Vendor = $null
                    Interface = 'wired'
                    Rssi = $null
                    TxRate = $null
                    RxRate = $null
                    IsOnline = $true
                }
                
                $clients += $clientInfo
            }
        }
        
        Remove-SSHSession -SessionId $session.SessionId | Out-Null
    }
    catch {
        Write-Warning "Failed to fetch client list via SSH: $_"
    }
    
    return $clients
}

function Invoke-RouterClientPoll {
    <#
    .SYNOPSIS
        Polls the router for current client list using configured method
    .DESCRIPTION
        Attempts to retrieve client list using HTTP or SSH based on configuration.
        Normalizes the data into a consistent format for database insertion.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config
    )
    
    $routerIP = $Config.Service.Asus.Uri -replace '^https?://([^/]+).*$', '$1'
    if (-not $routerIP) {
        $routerIP = $Config.RouterIP
    }
    
    $username = $Config.Service.Asus.Username
    $password = if ($Config.Service.Asus.PasswordSecret) {
        Resolve-SystemDashboardSecret -Secret $Config.Service.Asus.PasswordSecret
    } else {
        $env:ASUS_ROUTER_PASSWORD
    }
    
    if (-not $password) {
        Write-Warning "Router password not configured. Set ASUS_ROUTER_PASSWORD environment variable."
        return @()
    }
    
    $clients = @()
    
    # Try SSH first if enabled
    if ($Config.Service.Asus.SSH.Enabled -eq $true) {
        Write-Verbose "Attempting to fetch clients via SSH"
        $sshHost = $Config.Service.Asus.SSH.Host
        $sshPort = $Config.Service.Asus.SSH.Port
        $clients = Get-RouterClientListViaSsh -RouterIP $sshHost -Username $username -Password $password -Port $sshPort
    }
    
    # Fallback to HTTP if SSH didn't work
    if ($clients.Count -eq 0) {
        Write-Verbose "Attempting to fetch clients via HTTP"
        $clients = Get-RouterClientListViaHttp -RouterIP $routerIP -Username $username -Password $password
    }
    
    # Normalize MAC addresses to consistent format (uppercase with colons)
    foreach ($client in $clients) {
        if ($client.MacAddress) {
            # First, remove all non-hex characters to get a clean hex string
            $hexOnly = $client.MacAddress.ToUpper() -replace '[^0-9A-F]', ''
            # Then add colons between each pair of characters
            if ($hexOnly.Length -eq 12) {
                $client.MacAddress = $hexOnly -replace '(..)(?=.)', '$1:'
            }
        }
    }
    
    Write-Verbose "Found $($clients.Count) clients from router"
    return $clients
}

function Upsert-LanDevice {
    <#
    .SYNOPSIS
        Upserts a device into the devices table
    .DESCRIPTION
        Inserts a new device or updates existing device based on MAC address.
        Returns the device_id for the device.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$DbConnection,
        [Parameter(Mandatory)][string]$MacAddress,
        [Parameter()][string]$IpAddress,
        [Parameter()][string]$Hostname,
        [Parameter()][string]$Vendor
    )
    
    try {
        $cmd = $DbConnection.CreateCommand()
        $cmd.CommandText = @"
INSERT INTO telemetry.devices (mac_address, primary_ip_address, hostname, vendor, is_active, last_seen_utc, updated_at)
VALUES (@mac, @ip, @hostname, @vendor, true, NOW(), NOW())
ON CONFLICT (mac_address) 
DO UPDATE SET
    primary_ip_address = COALESCE(EXCLUDED.primary_ip_address, devices.primary_ip_address),
    hostname = COALESCE(EXCLUDED.hostname, devices.hostname),
    vendor = COALESCE(EXCLUDED.vendor, devices.vendor),
    is_active = true,
    last_seen_utc = NOW(),
    updated_at = NOW()
RETURNING device_id;
"@
        
        $cmd.Parameters.AddWithValue('@mac', $MacAddress) | Out-Null
        $cmd.Parameters.AddWithValue('@ip', [string]$IpAddress) | Out-Null
        $cmd.Parameters.AddWithValue('@hostname', [string]$Hostname) | Out-Null
        $cmd.Parameters.AddWithValue('@vendor', [string]$Vendor) | Out-Null
        
        $deviceId = $cmd.ExecuteScalar()
        return [int]$deviceId
    }
    catch {
        Write-Warning "Failed to upsert device $MacAddress : $_"
        return $null
    }
}

function Add-DeviceSnapshot {
    <#
    .SYNOPSIS
        Records a snapshot of device state at current time
    .DESCRIPTION
        Inserts a time-series record of device network statistics.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$DbConnection,
        [Parameter(Mandatory)][int]$DeviceId,
        [Parameter()][string]$IpAddress,
        [Parameter()][string]$Interface,
        [Parameter()][int]$Rssi,
        [Parameter()][decimal]$TxRateMbps,
        [Parameter()][decimal]$RxRateMbps,
        [Parameter()][bool]$IsOnline = $true,
        [Parameter()][string]$RawJson
    )
    
    try {
        # Ensure partition exists for current month
        $partitionCmd = $DbConnection.CreateCommand()
        $partitionCmd.CommandText = "SELECT telemetry.ensure_device_snapshot_partition(CURRENT_DATE);"
        $partitionCmd.ExecuteNonQuery() | Out-Null
        
        $cmd = $DbConnection.CreateCommand()
        $cmd.CommandText = @"
INSERT INTO telemetry.device_snapshots_template 
    (device_id, sample_time_utc, ip_address, interface, rssi, tx_rate_mbps, rx_rate_mbps, is_online, raw_json)
VALUES 
    (@device_id, NOW(), @ip, @interface, @rssi, @tx_rate, @rx_rate, @is_online, @raw_json);
"@
        
        $cmd.Parameters.AddWithValue('@device_id', $DeviceId) | Out-Null
        $cmd.Parameters.AddWithValue('@ip', [string]$IpAddress) | Out-Null
        $cmd.Parameters.AddWithValue('@interface', [string]$Interface) | Out-Null
        
        if ($Rssi) {
            $cmd.Parameters.AddWithValue('@rssi', $Rssi) | Out-Null
        } else {
            $cmd.Parameters.AddWithValue('@rssi', [DBNull]::Value) | Out-Null
        }
        
        if ($TxRateMbps) {
            $cmd.Parameters.AddWithValue('@tx_rate', [decimal]$TxRateMbps) | Out-Null
        } else {
            $cmd.Parameters.AddWithValue('@tx_rate', [DBNull]::Value) | Out-Null
        }
        
        if ($RxRateMbps) {
            $cmd.Parameters.AddWithValue('@rx_rate', [decimal]$RxRateMbps) | Out-Null
        } else {
            $cmd.Parameters.AddWithValue('@rx_rate', [DBNull]::Value) | Out-Null
        }
        
        $cmd.Parameters.AddWithValue('@is_online', $IsOnline) | Out-Null
        $cmd.Parameters.AddWithValue('@raw_json', [string]$RawJson) | Out-Null
        
        $cmd.ExecuteNonQuery() | Out-Null
    }
    catch {
        Write-Warning "Failed to add device snapshot for device $DeviceId : $_"
    }
}

function Invoke-LanDeviceCollection {
    <#
    .SYNOPSIS
        Main collector function - polls router and updates database
    .DESCRIPTION
        Retrieves client list from router, upserts devices, and records snapshots.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][object]$DbConnection
    )
    
    Write-Verbose "Starting LAN device collection"
    
    # Poll router for clients
    $clients = Invoke-RouterClientPoll -Config $Config
    
    if ($clients.Count -eq 0) {
        Write-Warning "No clients retrieved from router"
        return
    }
    
    Write-Verbose "Processing $($clients.Count) clients"
    
    foreach ($client in $clients) {
        try {
            # Upsert device
            $deviceId = Upsert-LanDevice `
                -DbConnection $DbConnection `
                -MacAddress $client.MacAddress `
                -IpAddress $client.IpAddress `
                -Hostname $client.Hostname `
                -Vendor $client.Vendor
            
            if (-not $deviceId) {
                Write-Warning "Failed to upsert device with MAC $($client.MacAddress)"
                continue
            }
            
            # Add snapshot
            $rawJson = $client | ConvertTo-Json -Compress
            
            Add-DeviceSnapshot `
                -DbConnection $DbConnection `
                -DeviceId $deviceId `
                -IpAddress $client.IpAddress `
                -Interface $client.Interface `
                -Rssi $client.Rssi `
                -TxRateMbps $client.TxRate `
                -RxRateMbps $client.RxRate `
                -IsOnline $client.IsOnline `
                -RawJson $rawJson
            
            Write-Verbose "Processed device: $($client.MacAddress) (ID: $deviceId)"
        }
        catch {
            Write-Warning "Error processing client $($client.MacAddress): $_"
        }
    }
    
    Write-Verbose "LAN device collection complete"
}

function Update-DeviceActivityStatus {
    <#
    .SYNOPSIS
        Updates is_active flag on devices based on recent activity
    .DESCRIPTION
        Marks devices as inactive if they haven't been seen recently.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$DbConnection,
        [Parameter()][int]$InactiveThresholdMinutes = 10
    )
    
    try {
        $cmd = $DbConnection.CreateCommand()
        $cmd.CommandText = "SELECT * FROM telemetry.update_device_activity_status(@threshold);"
        $cmd.Parameters.AddWithValue('@threshold', $InactiveThresholdMinutes) | Out-Null
        
        $reader = $cmd.ExecuteReader()
        $updatedCount = 0
        if ($reader.Read()) {
            $updatedCount = $reader.GetInt32(0)
        }
        $reader.Close()
        
        if ($updatedCount -gt 0) {
            Write-Verbose "Marked $updatedCount device(s) as inactive"
        }
    }
    catch {
        Write-Warning "Failed to update device activity status: $_"
    }
}

function Invoke-DeviceSnapshotRetention {
    <#
    .SYNOPSIS
        Cleans up old device snapshots based on retention policy
    .DESCRIPTION
        Deletes snapshots older than the configured retention period.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$DbConnection,
        [Parameter()][int]$RetentionDays = 7
    )
    
    try {
        $cmd = $DbConnection.CreateCommand()
        $cmd.CommandText = "SELECT * FROM telemetry.cleanup_old_device_snapshots(@retention);"
        $cmd.Parameters.AddWithValue('@retention', $RetentionDays) | Out-Null
        
        $reader = $cmd.ExecuteReader()
        $deletedCount = 0
        if ($reader.Read()) {
            $deletedCount = $reader.GetInt64(0)
        }
        $reader.Close()
        
        if ($deletedCount -gt 0) {
            Write-Verbose "Deleted $deletedCount old snapshot(s)"
        }
    }
    catch {
        Write-Warning "Failed to cleanup old snapshots: $_"
    }
}

function Invoke-SyslogDeviceCorrelation {
    <#
    .SYNOPSIS
        Correlates syslog events with devices by parsing MAC/IP addresses
    .DESCRIPTION
        Scans recent syslog messages for device identifiers and creates links.
        Phase 1 implementation: basic MAC/IP matching in message text.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$DbConnection,
        [Parameter()][int]$LookbackHours = 1
    )
    
    try {
        # Get recent syslog entries that haven't been correlated yet
        $cmd = $DbConnection.CreateCommand()
        $cmd.CommandText = @"
SELECT s.id, s.message, s.source_host
FROM telemetry.syslog_generic_template s
WHERE s.received_utc >= NOW() - INTERVAL '@hours hours'
  AND NOT EXISTS (
      SELECT 1 FROM telemetry.syslog_device_links l WHERE l.syslog_id = s.id
  )
ORDER BY s.received_utc DESC
LIMIT 1000;
"@
        $cmd.CommandText = $cmd.CommandText -replace '@hours', $LookbackHours
        
        $reader = $cmd.ExecuteReader()
        $syslogs = @()
        
        while ($reader.Read()) {
            $syslogs += [PSCustomObject]@{
                Id = $reader.GetInt64(0)
                Message = $reader.GetString(1)
            }
        }
        $reader.Close()
        
        if ($syslogs.Count -eq 0) {
            Write-Verbose "No new syslog entries to correlate"
            return
        }
        
        # Get all known devices
        $devicesCmd = $DbConnection.CreateCommand()
        $devicesCmd.CommandText = "SELECT device_id, mac_address, primary_ip_address FROM telemetry.devices;"
        $deviceReader = $devicesCmd.ExecuteReader()
        $devices = @()
        
        while ($deviceReader.Read()) {
            $devices += [PSCustomObject]@{
                Id = $deviceReader.GetInt32(0)
                Mac = $deviceReader.GetString(1)
                Ip = if (-not $deviceReader.IsDBNull(2)) { $deviceReader.GetString(2) } else { $null }
            }
        }
        $deviceReader.Close()
        
        # Try to match syslog messages to devices
        $linksCreated = 0
        foreach ($syslog in $syslogs) {
            $message = $syslog.Message.ToLower()
            
            foreach ($device in $devices) {
                $matched = $false
                $matchType = $null
                
                # Try MAC address match (with various formats)
                $macVariants = @(
                    $device.Mac.Replace(':', '-'),
                    $device.Mac.Replace(':', ''),
                    $device.Mac.ToLower()
                )
                
                foreach ($macVariant in $macVariants) {
                    if ($message -like "*$($macVariant.ToLower())*") {
                        $matched = $true
                        $matchType = 'mac'
                        break
                    }
                }
                
                # Try IP address match
                if (-not $matched -and $device.Ip -and $message -like "*$($device.Ip)*") {
                    $matched = $true
                    $matchType = 'ip'
                }
                
                if ($matched) {
                    # Create link
                    $linkCmd = $DbConnection.CreateCommand()
                    $linkCmd.CommandText = @"
INSERT INTO telemetry.syslog_device_links (syslog_id, device_id, match_type, confidence)
VALUES (@syslog_id, @device_id, @match_type, @confidence)
ON CONFLICT DO NOTHING;
"@
                    $linkCmd.Parameters.AddWithValue('@syslog_id', $syslog.Id) | Out-Null
                    $linkCmd.Parameters.AddWithValue('@device_id', $device.Id) | Out-Null
                    $linkCmd.Parameters.AddWithValue('@match_type', $matchType) | Out-Null
                    $linkCmd.Parameters.AddWithValue('@confidence', 0.9) | Out-Null
                    
                    $linkCmd.ExecuteNonQuery() | Out-Null
                    $linksCreated++
                }
            }
        }
        
        if ($linksCreated -gt 0) {
            Write-Verbose "Created $linksCreated syslog-device link(s)"
        }
    }
    catch {
        Write-Warning "Failed to correlate syslog events with devices: $_"
    }
}

# Export module functions
Export-ModuleMember -Function @(
    'Get-LanSettings'
    'Invoke-RouterClientPoll'
    'Invoke-LanDeviceCollection'
    'Update-DeviceActivityStatus'
    'Invoke-DeviceSnapshotRetention'
    'Invoke-SyslogDeviceCorrelation'
)

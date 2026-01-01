### BEGIN FILE: NetworkClientScan.ps1
<#
.SYNOPSIS
Scan multiple subnets (default: 192.168.50.0/24 and 192.168.101.0/24).
Collect IP, Hostname, MAC, Manufacturer; export to Excel or CSV.

.NOTES
- Works on Windows PowerShell 5.1 and PowerShell 7+.
- PS7 uses parallel ping; PS5.1 runs sequentially.
- Hostnames via DNS (PTR) with sane fallbacks.
- MACs harvested from ARP after pings populate the cache.
- Manufacturer mapping uses a local OUI cache if present:
$env:ProgramData\OUI\oui.csv (from IEEE: Assignment,Organization Name)
- Optional: run Update-OuiCache to download latest vendor list.
#>



[CmdletBinding()]
param(
    [string[]]$Subnets = @('192.168.50', '192.168.101'), # /24 bases to scan
    [int[]]$Range = 1..254,                              # host range in each subnet
    [int]$PingTimeoutSec = 1,                            # integer > 0 for PS5.1
    [string]$OutDir,
    [string]$SyslogPath = "F:\Logs\syslog.log",
    [switch]$SkipDependencyCheck
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Defaults derived from timestamp/desktop if not provided
$TimeStamp = Get-Date -Format yyyyMMdd-HHmm
if (-not $OutDir) { $OutDir = Join-Path $env:USERPROFILE "Desktop\SubnetScan-$TimeStamp" }
$ExcelPath = Join-Path $OutDir "SubnetScan-$TimeStamp.xlsx"
$HtmlPath  = Join-Path $OutDir "SubnetScan-Report.html"
$DbPath    = Join-Path $OutDir "NetworkInventory.sqlite"
$OUIFolder = Join-Path $env:ProgramData 'OUI'
$OUIFile   = Join-Path $OUIFolder 'oui.csv'

Write-Host "Network Client Scan starting at $(Get-Date)" -ForegroundColor Cyan
Write-Host "Output will be saved to: $OutDir"
if (-not (Test-Path $OutDir)) { New-Item -Path $OutDir -ItemType Directory -Force | Out-Null }

# ================== Dependency Checks ==================
function Dependency-Check {
    $RequiredModules = @(
        @{ Name = 'PSSQLite';    MinimumVersion = '1.0.0' }
        @{ Name = 'ImportExcel'; MinimumVersion = '7.1.0' }
    )
    foreach ($mod in $RequiredModules) {
        if (-not (Get-Module -ListAvailable -Name $mod.Name)) {
            Write-Warning "$($mod.Name) module not found. Attempting to install from PSGallery..."
            try {
                Install-Module -Name $mod.Name -MinimumVersion $mod.MinimumVersion -Scope CurrentUser -Force -AllowClobber
            } catch {
                throw "Failed to install required module: $($mod.Name). Error: $($_.Exception.Message)"
            }
        }
        Import-Module $mod.Name -Force
    }
}
if (-not $SkipDependencyCheck) { Dependency-Check }
# =======================================================

# ================== Function Definitions ==================
function Update-OuiCache {
    if (-not (Test-Path $OUIFolder)) { New-Item -Path $OUIFolder -ItemType Directory -Force | Out-Null }
    Write-Host "Downloading IEEE OUI CSV..." -ForegroundColor Cyan
    $url = 'https://standards-oui.ieee.org/oui/oui.csv'
    try {
        Invoke-WebRequest -Uri $url -OutFile $OUIFile -UseBasicParsing
        Write-Host "Saved: $OUIFile" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to download OUI list: $($_.Exception.Message)"
        throw
    }
}

function Get-OuiMap {
    $map = @{}
    $cacheFile = Join-Path $OUIFolder 'oui.clixml'

    if ((Test-Path $cacheFile) -and (Test-Path $OUIFile) -and ((Get-Item $cacheFile).LastWriteTimeUtc -ge (Get-Item $OUIFile).LastWriteTimeUtc)) {
        Write-Host "Loading OUI manufacturer map from XML cache..." -ForegroundColor Gray
        return Import-CliXml -Path $cacheFile
    }

    if (Test-Path $OUIFile) {
        Write-Host "Parsing OUI CSV... (this may take a moment)" -ForegroundColor Gray
        $csvData = Import-Csv -Path $OUIFile
        foreach ($row in $csvData) {
            $hex = ($row.Assignment -replace '[-:\.]','').ToUpper()
            $org = $row.'Organization Name'
            if (-not [string]::IsNullOrWhiteSpace($hex) -and -not [string]::IsNullOrWhiteSpace($org)) {
                $map[$hex] = $org
            }
        }
        # Optionally skip creating XML cache to speed up first run
        # $map | Export-CliXml -Path $cacheFile
        Write-Host "OUI map parsed: $($map.Count) entries." -ForegroundColor Green
    } else {
        Write-Warning "OUI cache not found at $OUIFile. Run Update-OuiCache to create it."
    }
    return $map
}

function Resolve-HostName {
    param([string]$Ip)
    try {
        $res = Resolve-DnsName -Name $Ip -Type PTR -ErrorAction Stop
        ($res | Where-Object { $_.QueryType -eq 'PTR' } | Select-Object -First 1).NameHost
    } catch {
        try {
            $job = Start-Job -ScriptBlock { param($ip) [System.Net.Dns]::GetHostEntry($ip).HostName } -ArgumentList $Ip
            $result = Wait-Job -Job $job -Timeout 2
            if ($result) {
                Receive-Job -Job $job
            } else {
                '' # Timeout, return empty string
            }
            Remove-Job -Job $job -Force
        } catch { '' }
            Write-Verbose "Could not resolve hostname for IP $Ip $($_.Exception.Message)"
            'Unresolved'
        }
}

function Get-Manufacturer {
    param(
        [string]$Mac,
        [hashtable]$OuiMap
    )
    if ([string]::IsNullOrWhiteSpace($Mac)) { return '' }
    $hex = ($Mac -replace '[-:\.]','').ToUpper()
    if ($hex.Length -lt 6) { return '' }
    $prefix6 = $hex.Substring(0,6)
    if ($OuiMap.ContainsKey($prefix6)) { return $OuiMap[$prefix6] }

    switch -Regex ($prefix6) {
        '00155D' { return 'Microsoft (Hyper-V)' }
        'B827EB|DCA632|E45F01' { return 'Raspberry Pi' }
        'F09FC2|24A43C|68D79A' { return 'Ubiquiti' }
        '286CFB|3C0754|403004|60F81D|D0034B' { return 'Apple' }
        '50C7BF|74EA3A|9C5C8E' { return 'TP-Link' }
        '086266|60A44C|04D9F5' { return 'ASUS' }
        default { return '' }
    }
}

function Test-Nmap {
    # Returns $true if nmap is found in the system's PATH.
    # Note: This does not verify if nmap is actually executable or its version.
    return [bool](Get-Command nmap -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' })
}

function Invoke-SubnetScan {
    <#
    .SYNOPSIS
        Scans a given /24 subnet for live hosts and device information.
        Uses nmap if available (for OS/ports/MAC); otherwise, falls back to ping/ARP sweep.
    .PARAMETER SubnetBase
        The base of the subnet to scan, e.g. '192.168.50'
    .PARAMETER Range
        Integer array for host addresses, e.g. 1..254
    .PARAMETER OuiMap
        Hashtable mapping MAC OUI to manufacturer names
    .PARAMETER ThrottleLimit
        Max concurrency for parallel scans (PS7+ only)
    .OUTPUTS
        [PSCustomObject[]] - Each device with fields: Subnet, IP, Hostname, MAC, Manufacturer, OS, OpenPorts, LastSeen
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SubnetBase,
        [Parameter(Mandatory)][int[]]$Range,
        [Parameter(Mandatory)][hashtable]$OuiMap,
        [int]$ThrottleLimit = 32
    )

    $ips = $Range | ForEach-Object { "$SubnetBase.$_" }
    $subnetCidr = "$SubnetBase.0/24"
    $now = Get-Date

    # ----------- NMAP MODE -----------
    if (Test-Nmap) {
        Write-Host "[$subnetCidr] Scanning with nmap..." -ForegroundColor Cyan
        $nmapArgs = @('-T4', '-F', $subnetCidr)
        if ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            $nmapArgs += '-O'
            Write-Host "Running as Administrator: OS detection enabled." -ForegroundColor Yellow
        } else {
            Write-Warning "Not admin: Nmap OS detection (-O) will be skipped."
        }
        $tempXmlPath = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName() + ".xml")
        $nmapArgs += @('-oX', $tempXmlPath)
        $nmapProc = Start-Process nmap -ArgumentList $nmapArgs -Wait -NoNewWindow -PassThru

        if ($nmapProc.ExitCode -ne 0) {
            $stdout = ""
            $stderr = ""
            if ($nmapProc.StandardOutput) { $stdout = $nmapProc.StandardOutput.ReadToEnd() }
            if ($nmapProc.StandardError)  { $stderr = $nmapProc.StandardError.ReadToEnd() }
            Write-Error "Nmap failed with code $($nmapProc.ExitCode). Stdout: $stdout; Stderr: $stderr"
            throw "Nmap process exited with code $($nmapProc.ExitCode)."
        }

        $nmapXml = [xml](Get-Content -Path $tempXmlPath -Raw)
        Remove-Item $tempXmlPath -ErrorAction SilentlyContinue

        $rows = foreach ($nmapHost in $nmapXml.nmaprun.host) {
            if ($nmapHost.status.state -ne 'up') { continue }
            $ip  = $nmapHost.address | Where-Object { $_.addrtype -eq 'ipv4' } | Select-Object -ExpandProperty addr -First 1
            $mac = $nmapHost.address | Where-Object { $_.addrtype -eq 'mac' }  | Select-Object -ExpandProperty addr -First 1
            $osMatch = $nmapHost.os.osmatch | Sort-Object -Property accuracy -Descending | Select-Object -First 1
            [pscustomobject]@{
                Subnet        = "$SubnetBase.0/24"
                IP            = $ip
                Hostname      = Resolve-HostName -Ip $ip
                MAC           = $mac
                Manufacturer  = if ($mac) { (Get-Manufacturer -Mac $mac -OuiMap $OuiMap) } else { '' }
                OS            = if ($osMatch) { "$($osMatch.name) ($($osMatch.accuracy)%)" } else { '' }
                OpenPorts     = if ($nmapHost.ports.port) {
                    ($nmapHost.ports.port | Where-Object { $_.state.state -eq 'open' } | ForEach-Object { "$($_.portid)/$($_.protocol) ($($_.service.name))" }) -join ', '
                } else { '' }
                LastSeen      = $now
            }
        }
        if (-not $rows) {
            Write-Warning "[$subnetCidr] No live hosts found by nmap."
        }
        return $rows
    }

    # ----------- PING/ARP MODE -----------
    Write-Host "[$subnetCidr] Pinging $($ips.Count) addresses..." -ForegroundColor Cyan
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $alive = $ips | ForEach-Object -Parallel {
            if (Test-Connection -TargetName $_ -Count 1 -Quiet -TimeoutSeconds $PingTimeoutSec) { $_ }
        } -ThrottleLimit $ThrottleLimit
    } else {
        $alive = foreach ($ip in $ips) {
            if (Test-Connection -ComputerName $ip -Count 1 -Quiet -TimeoutSeconds $PingTimeoutSec) { $ip }
        }
    }
    $alive = @($alive)

    # Collect MAC addresses
    $arpTable = @{}
    if (Get-Command Get-NetNeighbor -ErrorAction SilentlyContinue) {
        Write-Host "[$subnetCidr] Harvesting MAC addresses using Get-NetNeighbor..." -ForegroundColor Gray
        Get-NetNeighbor -AddressFamily IPv4 | ForEach-Object {
            if ($_.State -in @('Reachable', 'Stale')) {
                $arpTable[$_.IPAddress] = $_.LinkLayerAddress.ToUpper().Replace('-',':')
            }
        }
    } else {
        Write-Host "[$subnetCidr] Harvesting MAC addresses using 'arp -a'..." -ForegroundColor Gray
        (arp -a) | ForEach-Object {
            if ($_ -match '^\s*(\d{1,3}(\.\d{1,3}){3})\s+([0-9a-fA-F:-]{11,17})\s+') {
                $ip  = $matches[1]
                $mac = $matches[3].ToUpper().Replace('-',':')
                $arpTable[$ip] = $mac
            }
        }
    }

    # Parallel hostname resolution
  $hostnameCache = @{}
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $hostnames = ($alive | Sort-Object) | ForEach-Object -Parallel {
        @{ IP = $_; Hostname = (Resolve-DnsName $_ -ErrorAction SilentlyContinue).NameHost }

    } -ThrottleLimit $ThrottleLimit
    foreach ($entry in $hostnames) {
        $hostnameCache[$entry.IP] = $entry.Hostname
    }
} else {
    foreach ($ip in ($alive | Sort-Object)) {
        $hostnameCache[$ip] = Resolve-HostName -Ip $ip
    }
}

    $rows = foreach ($ip in ($alive | Sort-Object)) {
        $mac = if ($arpTable.ContainsKey($ip)) { $arpTable[$ip] } else { '' }
        [pscustomobject]@{
            Subnet        = "$SubnetBase.0/24"
            IP            = $ip
            Hostname      = $hostnameCache[$ip]
            MAC           = $mac
            Manufacturer  = Get-Manufacturer -Mac $mac -OuiMap $OuiMap
            OS            = ''
            OpenPorts     = ''
            LastSeen      = $now
        }
    }

    if (-not $rows) {
        Write-Warning "[$subnetCidr] No live hosts found."
    }
    return $rows
}

function Export-HtmlReport {
    param(
        [Parameter(Mandatory)][object[]]$Data,
        [Parameter(Mandatory)][string]$OutputPath,
        [object[]]$SyslogData
    )

    if (-not $Data) {
        Write-Warning "No data provided to Export-HtmlReport. Skipping report generation."
        return
    }

    # Generate table headers from the first object's properties
    $headers = $Data[0].PSObject.Properties.Name | ForEach-Object { "<th>$_</th>" }
    $headers = "<tr>$($headers -join '')</tr>"

    # Generate table rows, ensuring data is HTML-encoded to prevent display issues
    $tableRows = $Data | ForEach-Object {
        $row = $_
        $cells = $_.PSObject.Properties.Name | ForEach-Object {
            $value = $row.$_
            $encodedValue = [System.Web.HttpUtility]::HtmlEncode($value)
            "<td>$encodedValue</td>"
        }
        "<tr>$($cells -join '')</tr>"
    }

    # --- Generate Syslog Table (if data exists) ---
    $syslogHtml = ''
    if ($SyslogData) {
        $syslogHeaders = "<tr><th>Timestamp</th><th>Message</th></tr>"
        $syslogTableRows = $SyslogData | ForEach-Object {
            $ts = [System.Web.HttpUtility]::HtmlEncode($_.Timestamp)
            $msg = [System.Web.HttpUtility]::HtmlEncode($_.Message)
            "<tr><td>$ts</td><td>$msg</td></tr>"
        }
        $syslogHtml = @"
        <div id="syslog" class="tab-content" style="display:none;">
            <h2>Recent Syslog Events</h2>
            <div style="overflow-x:auto;">
                <table id="syslogTable">
                    <thead>$syslogHeaders</thead>
                    <tbody>$($syslogTableRows -join "`n")</tbody>
                </table>
            </div>
        </div>
"@
    }

    $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Network Scan Report</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; margin: 0; background-color: #f4f7f9; color: #333; }
        .container { max-width: 95%; margin: 2rem auto; padding: 2rem; background-color: #fff; border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.08); }
        h1 { color: #1a2b4d; border-bottom: 2px solid #e2e8f0; padding-bottom: 0.5rem; }
        input[type="text"] { width: 100%; padding: 0.75rem; margin-bottom: 1.5rem; border: 1px solid #cbd5e0; border-radius: 4px; font-size: 1rem; box-sizing: border-box; }
        table { width: 100%; border-collapse: collapse; font-size: 0.9rem; }
        th, td { padding: 0.8rem 1rem; text-align: left; border-bottom: 1px solid #e2e8f0; white-space: nowrap; }
        thead th { background-color: #f8fafc; font-weight: 600; cursor: pointer; user-select: none; position: relative; }
        thead th::after { content: ''; position: absolute; right: 0.5rem; top: 50%; transform: translateY(-50%); border: 4px solid transparent; opacity: 0.3; }
        thead th.sort-asc::after { border-bottom-color: #333; }
        thead th.sort-desc::after { border-top-color: #333; }
        tbody tr:nth-child(even) { background-color: #fdfdff; }
        tbody tr:hover { background-color: #eff6ff; }
        .footer { text-align: center; margin-top: 2rem; font-size: 0.8rem; color: #64748b; }
        .tabs { border-bottom: 2px solid #e2e8f0; margin-bottom: 1.5rem; }
        .tab-button { background: none; border: none; padding: 1rem 1.5rem; font-size: 1rem; cursor: pointer; color: #64748b; }
        .tab-button.active { font-weight: 600; color: #1a2b4d; border-bottom: 2px solid #3b82f6; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Network Scan Report</h1>
        <p>Generated on $(Get-Date).</p>

        <div class="tabs">
            <button class="tab-button" onclick="showTab('inventory')">Inventory</button>
            <button class="tab-button" onclick="showTab('syslog')" $(if (-not $SyslogData) { 'style="display:none;"' })>Syslog</button>
        </div>

        <div id="inventory" class="tab-content" style="display:none;">
            <h2>Device Inventory ($($Data.Count) total)</h2>
            <input type="text" id="filterInput" onkeyup="filterTable()" placeholder="Type to filter results...">
            <div style="overflow-x:auto;">
                <table id="resultsTable">
                    <thead>$headers</thead>
                    <tbody>$($tableRows -join "`n")</tbody>
                </table>
            </div>
        </div>

        $syslogHtml

        <div class="footer">Report generated by NetworkClientScan.ps1</div>
    </div>
<script>
    function showTab(tabName) {
        document.querySelectorAll('.tab-content').forEach(c => c.style.display = 'none');
        document.getElementById(tabName).style.display = 'block';
        document.querySelectorAll('.tab-button').forEach(t => t.classList.remove('active'));
        document.querySelector(`[onclick="showTab('${tabName}')"]`).classList.add('active');
    }
    document.addEventListener('DOMContentLoaded', () => showTab('inventory'));

    const getCellValue = (tr, idx) => tr.children[idx].innerText || tr.children[idx].textContent;
    const comparer = (idx, asc) => (a, b) => ((v1, v2) => v1 !== '' && v2 !== '' && !isNaN(v1) && !isNaN(v2) ? v1 - v2 : v1.toString().localeCompare(v2))(getCellValue(asc ? a : b, idx), getCellValue(asc ? b : a, idx));

    document.querySelectorAll('th').forEach(th => th.addEventListener('click', (() => {
        const table = th.closest('table');
        const tbody = table.querySelector('tbody');
        const thIndex = Array.from(th.parentNode.children).indexOf(th);
        const currentIsAsc = th.classList.contains('sort-asc');

        document.querySelectorAll('th').forEach(h => h.classList.remove('sort-asc', 'sort-desc'));
        th.classList.toggle('sort-asc', !currentIsAsc);
        th.classList.toggle('sort-desc', currentIsAsc);

        Array.from(tbody.querySelectorAll('tr'))
            .sort(comparer(thIndex, !currentIsAsc))
            .forEach(tr => tbody.appendChild(tr));
    })));

    function filterTable() {
        const filter = document.getElementById('filterInput').value.toUpperCase();
        const rows = document.getElementById('resultsTable').getElementsByTagName('tbody')[0].getElementsByTagName('tr');
        for (let i = 0; i < rows.length; i++) {
            rows[i].style.display = rows[i].textContent.toUpperCase().indexOf(filter) > -1 ? '' : 'none';
        }
    }
</script>
</body>
</html>
"@

    try {
        $htmlContent | Set-Content -Path $OutputPath -Encoding UTF8
        Write-Host "HTML report generated: $OutputPath" -ForegroundColor Green
    } catch {
        Write-Error "Failed to write HTML report: $($_.Exception.Message)"
        throw
    }
}

function Initialize-Database {
    param(
        [Parameter(Mandatory)][string]$DbPath
    )
    if (-not (Get-Module -ListAvailable -Name PSSQLite)) {
        throw "Missing PSSQLite module. Run: Install-Module PSSQLite -Scope CurrentUser"
    }
    Import-Module -Name PSSQLite
    Write-Host "Initializing database at $DbPath..." -ForegroundColor Cyan

    $devicesTableSql = @"
CREATE TABLE IF NOT EXISTS Devices (
    IP TEXT PRIMARY KEY,
    Subnet TEXT,
    Hostname TEXT,
    MAC TEXT,
    Manufacturer TEXT,
    OS TEXT,
    OpenPorts TEXT,
    FirstSeen TEXT,
    LastSeen TEXT
);
"@
    $historyTableSql = @"
CREATE TABLE IF NOT EXISTS DeviceHistory (
    HistoryID INTEGER PRIMARY KEY AUTOINCREMENT,
    IP TEXT,
    Subnet TEXT,
    Hostname TEXT,
    MAC TEXT,
    Manufacturer TEXT,
    OS TEXT,
    OpenPorts TEXT,
    FirstSeen TEXT,
    LastSeen TEXT,
    ArchivedAt TEXT
);
"@
    Invoke-SqliteQuery -DataSource $DbPath -Query $devicesTableSql
    $syslogTableSql = @"
CREATE TABLE IF NOT EXISTS SyslogEvents (
    ID INTEGER PRIMARY KEY AUTOINCREMENT,
    Timestamp TEXT NOT NULL,
    Message TEXT NOT NULL UNIQUE
);
"@
    Invoke-SqliteQuery -DataSource $DbPath -Query $historyTableSql
    Invoke-SqliteQuery -DataSource $DbPath -Query $syslogTableSql
    Write-Host "Database schema is up to date." -ForegroundColor Green
}

function Update-Database {
    param(
        [Parameter(Mandatory)][string]$DbPath,
        [Parameter(Mandatory)][object[]]$ScannedDevices
    )
    Write-Host "Updating database with $($ScannedDevices.Count) scan results..." -ForegroundColor Cyan
    $now = Get-Date -Format 'u'

    # Use a transaction for vastly improved performance on bulk operations
    Invoke-SqliteQuery -DataSource $DbPath -Query "BEGIN TRANSACTION;"

    try {
        foreach ($device in $ScannedDevices) {
            $existing = Invoke-SqliteQuery -DataSource $DbPath -Query "SELECT * FROM Devices WHERE IP = @IP" -Parameters @{ IP = $device.IP }

            if (-not $existing) {

                # --- INSERT new device ---
                $insertQuery = @"
INSERT INTO Devices (IP, Subnet, Hostname, MAC, Manufacturer, OS, OpenPorts, FirstSeen, LastSeen)
VALUES (@IP, @Subnet, @Hostname, @MAC, @Manufacturer, @OS, @OpenPorts, @FirstSeen, @LastSeen);
"@
                $params = @{
                    IP = $device.IP; Subnet = $device.Subnet; Hostname = $device.Hostname; MAC = $device.MAC; Manufacturer = $device.Manufacturer;
                    OS = $device.OS; OpenPorts = $device.OpenPorts; FirstSeen = $now; LastSeen = $now
                }
                Invoke-SqliteQuery -DataSource $DbPath -Query $insertQuery -Parameters $params
            } else {
                # --- UPDATE existing device ---
                # If the MAC address has changed, a new physical device is at this IP. Archive the old record.
                if ($existing.MAC -ne $device.MAC -and -not ([string]::IsNullOrWhiteSpace($existing.MAC))) {
                    Write-Host "IP $($device.IP) has a new MAC address. Archiving old record." -ForegroundColor Yellow
                    $archiveQuery = @"
INSERT INTO DeviceHistory (IP, Subnet, Hostname, MAC, Manufacturer, OS, OpenPorts, FirstSeen, LastSeen, ArchivedAt)
SELECT IP, Subnet, Hostname, MAC, Manufacturer, OS, OpenPorts, FirstSeen, LastSeen, @ArchivedAt FROM Devices WHERE IP = @IP;
"@
                    Invoke-SqliteQuery -DataSource $DbPath -Query $archiveQuery -Parameters @{ ArchivedAt = $now; IP = $device.IP }

                    # When archiving, the 'FirstSeen' for the new device should be now.
                    $updateQuery = @"
UPDATE Devices SET Subnet = @Subnet, Hostname = @Hostname, MAC = @MAC, Manufacturer = @Manufacturer, OS = @OS, OpenPorts = @OpenPorts, FirstSeen = @FirstSeen, LastSeen = @LastSeen
WHERE IP = @IP;
"@
                    $params = @{
                        Subnet = $device.Subnet; Hostname = $device.Hostname; MAC = $device.MAC; Manufacturer = $device.Manufacturer; OS = $device.OS;
                        OpenPorts = $device.OpenPorts; FirstSeen = $now; LastSeen = $now; IP = $device.IP
                    }
                    Invoke-SqliteQuery -DataSource $DbPath -Query $updateQuery -Parameters $params
                } else {
                    # The device is the same, just update its details and LastSeen timestamp.
                    $updateQuery = @"
UPDATE Devices SET Subnet = @Subnet, Hostname = @Hostname, OS = @OS, OpenPorts = @OpenPorts, LastSeen = @LastSeen
WHERE IP = @IP;
"@
                    $params = @{
                        Subnet = $device.Subnet; Hostname = $device.Hostname; OS = $device.OS; OpenPorts = $device.OpenPorts; LastSeen = $now; IP = $device.IP
                    }
                    Invoke-SqliteQuery -DataSource $DbPath -Query $updateQuery -Parameters $params
                }
            }
        }
        Invoke-SqliteQuery -DataSource $DbPath -Query "COMMIT;"
        Write-Host "Database update complete." -ForegroundColor Green
    } catch {
        Write-Warning "An error occurred during the database transaction. Rolling back changes."
        Invoke-SqliteQuery -DataSource $DbPath -Query "ROLLBACK;"
        throw
    }
}

function Get-InventoryReportData {
    param(
        [Parameter(Mandatory)][string]$DbPath,
        [Parameter(Mandatory)][string[]]$OnlineIPs
    )
    Write-Host "Generating full inventory report from database..." -ForegroundColor Cyan

    $allDevices = Invoke-SqliteQuery -DataSource $DbPath -Query "SELECT * FROM Devices ORDER BY IP;"
    if (-not $allDevices) { return @() }

    # Create a fast lookup hashtable for online IPs
    $onlineIpMap = @{}
    foreach ($ip in $OnlineIPs) { $onlineIpMap[$ip] = $true }

    # Add a 'Status' property to each device for the report
    $reportData = foreach ($device in $allDevices) {
        $status = if ($onlineIpMap.ContainsKey($device.IP)) { 'Online' } else { 'Offline' }
        $device | Add-Member -MemberType NoteProperty -Name 'Status' -Value $status -PassThru
    }

    # Reorder properties to put Status first
    $props = @('Status') + ($reportData[0].PSObject.Properties.Name | Where-Object { $_ -ne 'Status' })
    return $reportData | Select-Object $props
}

function Get-SyslogEvents {
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$DbPath,
        [int]$Limit = 200
    )
    if (-not (Test-Path $LogPath)) {
        Write-Warning "Syslog file not found at '$LogPath'. Skipping syslog collection."
        return $null
    }

    Write-Host "Reading syslog events from $LogPath..." -ForegroundColor Cyan

    # Get the last message we stored to avoid duplicates.
    # Using a hashtable for fast lookups of existing messages.
    $existingMessages = @{}
    $query = "SELECT Message FROM SyslogEvents;"
    Invoke-SqliteQuery -DataSource $DbPath -Query $query | ForEach-Object {
        $existingMessages[$_.Message] = $true
    }

    # Read new lines and filter out any that are already in the database.
    $newLines = Get-Content -Path $LogPath | Where-Object { -not $existingMessages.ContainsKey($_) }

    if (-not $newLines) {
        Write-Host "No new syslog events found."
    } else {
        Write-Host "Found $($newLines.Count) new syslog events. Storing in database." -ForegroundColor Green
        try {
            Invoke-SqliteQuery -DataSource $DbPath -Query "BEGIN TRANSACTION;"
            foreach ($line in $newLines) {
                # The UNIQUE constraint on the Message column will prevent duplicates if multiple runs happen quickly.
                $params = @{ Timestamp = (Get-Date -Format 'u'); Message = $line }
                Invoke-SqliteQuery -DataSource $DbPath -Query "INSERT OR IGNORE INTO SyslogEvents (Timestamp, Message) VALUES (@Timestamp, @Message);" -Parameters $params
            }
            Invoke-SqliteQuery -DataSource $DbPath -Query "COMMIT;"
        } catch {
            Write-Warning "An error occurred during syslog database transaction. Rolling back."
            Invoke-SqliteQuery -DataSource $DbPath -Query "ROLLBACK;"
        }
    }

    # Return the most recent events for the report.
    return Invoke-SqliteQuery -DataSource $DbPath -Query "SELECT Timestamp, Message FROM SyslogEvents ORDER BY ID DESC LIMIT $Limit;"
}

# ------------------- Execute and export -------------------------------------
Write-Host "Preparing for scan..."
Update-OuiCache
$global:ouiMap   = Get-OuiMap
$allRows  = New-Object System.Collections.Generic.List[object]
$bySubnet = @{}
$DefaultThrottleLimit = 64  # bump up if you want faster scanning

foreach ($s in $Subnets) {
    $rows = Invoke-SubnetScan -SubnetBase $s -Range $Range -OuiMap $ouiMap -ThrottleLimit $DefaultThrottleLimit
    $subnetCidr = "$s.0/24"

    if ($rows) {
        Write-Host "[$subnetCidr] Scan complete. Found $($rows.Count) live hosts." -ForegroundColor Green
        $bySubnet[$s] = $rows
        $allRows.AddRange(@($rows))
    } else {
        Write-Warning "[$subnetCidr] No live hosts found."
        $bySubnet[$s] = @()
    }
}

if ($allRows.Count -eq 0) {
    Write-Warning "No hosts found across all subnets. Generating placeholder report so you can still view syslog data."

    # Prepare empty dataset so downstream logic doesn't crash
    $reportData = @([pscustomobject]@{
        Status       = 'NoData'
        IP           = ''
        Hostname     = ''
        MAC          = ''
        Manufacturer = ''
        LastSeen     = ''
    })
    $syslogEvents = Get-SyslogEvents -LogPath $SyslogPath -DatabasePath $DbPath

    Export-HtmlReport -Data $reportData -SyslogData $syslogEvents -OutputPath $HtmlPath
    Invoke-Item $HtmlPath
    Write-Host "Empty scan report generated: $HtmlPath" -ForegroundColor Yellow
    Write-Host "Scan completed: $(Get-Date -Format u)" -ForegroundColor Cyan
    return
}

# --- Update DB ---
try {
    Update-Database -DatabasePath $DbPath -ScannedDevices $allRows
} catch {
    Write-Warning "Database update failed: $($_.Exception.Message)"
}

# --- Generate Report Data ---
$onlineIps  = $allRows | ForEach-Object { $_.IP }
$reportData = Get-InventoryReportData -DatabasePath $DbPath -OnlineIPs $onlineIps

# --- Get Syslog Data ---
$syslogEvents = Get-SyslogEvents -LogPath $SyslogPath -DatabasePath $DbPath

# --- Export to Excel/CSV ---
Write-Host "Starting export process for $($reportData.Count) inventory devices..."
if (Get-Module -ListAvailable -Name ImportExcel) {
    try {
        $reportData | Export-Excel -Path $ExcelPath -WorksheetName 'Inventory' -AutoSize -FreezeTopRow -BoldTopRow
        if ($syslogEvents) {
            $syslogEvents | Export-Excel -Path $ExcelPath -WorksheetName 'Syslog' -AutoSize -FreezeTopRow -BoldTopRow
        }
        Write-Host "Exported to Excel: $ExcelPath" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to export to Excel: $($_.Exception.Message)"
    }
} else {
    Write-Warning "Module 'ImportExcel' not found. Falling back to CSV export."
    $csvPath = Join-Path $OutDir 'All.csv'
    $reportData | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "Exported to CSV: $csvPath" -ForegroundColor Green
}

# --- Always Generate HTML Report ---
Export-HtmlReport -Data $reportData -SyslogData $syslogEvents -OutputPath $HtmlPath
if (Test-Path $HtmlPath) { Invoke-Item $HtmlPath } else { Write-Warning "HTML report missing: $HtmlPath" }

# --- Console Summary ---
$displayProperties = @('Status','IP','Hostname','MAC','Manufacturer','LastSeen')
$reportData | Sort-Object IP | Format-Table $displayProperties -AutoSize -Wrap
Write-Host "Total devices in inventory: $($reportData.Count) ($($onlineIps.Count) currently online)" -ForegroundColor Green
Write-Host "Scan completed: $(Get-Date -Format u)" -ForegroundColor Cyan

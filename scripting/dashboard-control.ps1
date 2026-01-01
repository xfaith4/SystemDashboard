# System Dashboard Master Control Script
# Complete management interface for all dashboard operations

param(
    [string]$Action = "menu",
    [switch]$RouterMonitoring,
    [switch]$ContinuousEvents,
    [switch]$HealthMonitoring,
    [switch]$Maintenance
)

$repoRoot = Split-Path -Parent $PSScriptRoot

function Show-DashboardMenu {
    Clear-Host
    Write-Host "🎛️  System Dashboard Control Center" -ForegroundColor Cyan
    Write-Host "=" * 50
    Write-Host ""
    Write-Host "Current Status:" -ForegroundColor Yellow
    & (Join-Path $PSScriptRoot 'setup-permanent-services.ps1') -Status
    Write-Host ""
    Write-Host "Available Actions:" -ForegroundColor Yellow
    Write-Host "  1️⃣  Health Check               - Full system health assessment"
    Write-Host "  2️⃣  Maintenance Tasks          - Clean logs, optimize database"
    Write-Host "  3️⃣  Setup Syslog Monitoring    - Configure UDP syslog listener (port 5514)"
    Write-Host "  4️⃣  Setup WiFi Monitoring      - Configure router SSH for WiFi client tracking"
    Write-Host "  5️⃣  Start Continuous Events    - Real-time Windows event collection"
    Write-Host "  6️⃣  Data Source Manager        - Add/configure new data sources"
    Write-Host "  7️⃣  Generate Test Data         - Create sample events for testing"
    Write-Host "  8️⃣  Test Syslog Sender         - Send test syslog messages to verify listener"
    Write-Host "  9️⃣  View Recent Data           - Show latest telemetry records"
    Write-Host "  🔟  Restart Services           - Restart all dashboard services"
    Write-Host "  ⚡  Open Dashboard             - Launch web interface"
    Write-Host "  0️⃣  Exit"
    Write-Host ""

    $choice = Read-Host "Select an action (1-11, 0 to exit)"

    switch ($choice) {
        "1" { Invoke-HealthCheck }
        "2" { Invoke-MaintenanceMenu }
        "3" { Show-SyslogMonitoring }
        "4" { Show-WiFiMonitoring }
        "5" { Start-ContinuousEventsMenu }
        "6" { Show-DataSourceManager }
        "7" { Generate-TestData }
        "8" { Test-SyslogSender }
        "9" { Show-RecentData }
        "10" { Restart-AllServices }
        "11" { Open-DashboardInBrowser }
        "0" { Write-Host "👋 Goodbye!" -ForegroundColor Green; exit }
        default { Write-Host "❌ Invalid choice. Try again." -ForegroundColor Red; Start-Sleep 2; Show-DashboardMenu }
    }
}

function Invoke-HealthCheck {
    Clear-Host
    Import-Module (Join-Path $repoRoot 'tools\SystemMonitoring.psm1') -Force
    $health = Get-SystemDashboardHealth

    Write-Host "`n📊 Health Summary:" -ForegroundColor Yellow
    if ($health.Database -and $health.WebInterface -and $health.TelemetryService) {
        Write-Host "🟢 System is fully operational!" -ForegroundColor Green
    } elseif ($health.Database -and $health.WebInterface) {
        Write-Host "🟡 System is mostly operational with minor issues" -ForegroundColor Yellow
    } else {
        Write-Host "🔴 System has significant issues requiring attention" -ForegroundColor Red
    }

    Read-Host "`nPress Enter to return to menu"
    Show-DashboardMenu
}

function Invoke-MaintenanceMenu {
    Clear-Host
    Write-Host "🔧 Maintenance Tasks" -ForegroundColor Cyan
    Write-Host "=" * 30

    Import-Module .\tools\SystemMonitoring.psm1 -Force
    Invoke-MaintenanceTasks

    Read-Host "`nPress Enter to return to menu"
    Show-DashboardMenu
}

function Show-SyslogMonitoring {
    Clear-Host
    Write-Host "🌐 Router and Syslog Monitoring Setup" -ForegroundColor Cyan
    Write-Host "=" * 35

    Write-Host "System Dashboard collects syslog data through two methods:" -ForegroundColor Yellow
    Write-Host "  🔊 UDP Syslog Listener - Port 5514 (Primary method)" -ForegroundColor Green
    Write-Host "  📡 ASUS Router SSH fetch - Periodic polling (Secondary)" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "⚠️  Note: Using port 5514 instead of standard 514 to avoid requiring admin privileges" -ForegroundColor Yellow
    Write-Host ""

    # Check if syslog port is listening
    try {
        $syslogListening = Get-NetTCPConnection -LocalPort 5514 -ErrorAction SilentlyContinue
        if ($syslogListening) {
            Write-Host "✅ Syslog listener active on UDP port 5514" -ForegroundColor Green
        } else {
            # Check UDP connections (requires admin or different approach)
            Write-Host "📡 Syslog UDP listener configured for port 5514" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "📡 Syslog UDP listener configured for port 5514" -ForegroundColor Cyan
    }

    Write-Host "`n🏠 Configure your router to send syslog messages to:" -ForegroundColor Yellow
    $localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.|::1)' } | Select-Object -First 1).IPAddress
    Write-Host "    IP Address: $localIP" -ForegroundColor White
    Write-Host "    Port: 5514 (non-privileged syslog port)" -ForegroundColor White
    Write-Host "    Protocol: UDP" -ForegroundColor White

    Write-Host "`n📋 Router Configuration Steps:" -ForegroundColor Yellow
    Write-Host "  1. Access router admin panel at: https://192.168.50.1:8443/" -ForegroundColor Gray
    Write-Host "     (or try: http://192.168.1.1, http://192.168.50.1)" -ForegroundColor Gray
    Write-Host "  2. Navigate to Administration > System Log or Syslog settings" -ForegroundColor Gray
    Write-Host "  3. Enable 'Send to Remote Syslog Server' or 'External Log Server'" -ForegroundColor Gray
    Write-Host "  4. Set Remote Server IP: $localIP" -ForegroundColor Gray
    Write-Host "  5. Set Port: 5514 (not the standard 514)" -ForegroundColor Gray
    Write-Host "  6. Set Protocol: UDP" -ForegroundColor Gray
    Write-Host "  7. Set Log Level: All or Info and above" -ForegroundColor Gray
    Write-Host "  8. Apply/Save the settings" -ForegroundColor Gray

    Write-Host "`n🔧 Alternative: Standard Port 514 (Requires Admin)" -ForegroundColor Yellow
    Write-Host "  To use standard port 514, run PowerShell as Administrator and:" -ForegroundColor Gray
    Write-Host "  1. Edit config.json and change Syslog Port from 5514 to 514" -ForegroundColor Gray
    Write-Host "  2. Restart the telemetry service" -ForegroundColor Gray

    # ASUS router specific configuration
    Write-Host "`n📡 ASUS Router SSH Polling (Optional):" -ForegroundColor Yellow
    if ($env:ASUS_ROUTER_PASSWORD) {
        Write-Host "✅ ASUS router password already configured for SSH polling" -ForegroundColor Green
    } else {
        Write-Host "⚠️ ASUS router password not set for SSH polling" -ForegroundColor Yellow
        $setPassword = Read-Host "Would you like to set the ASUS router password for SSH polling? (y/n)"

        if ($setPassword -eq 'y') {
            $password = Read-Host "Enter ASUS router admin password" -AsSecureString
            $env:ASUS_ROUTER_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
            [Environment]::SetEnvironmentVariable("ASUS_ROUTER_PASSWORD", $env:ASUS_ROUTER_PASSWORD, [EnvironmentVariableTarget]::User)
            Write-Host "✅ ASUS router password set for SSH polling" -ForegroundColor Green
        }
    }

    Write-Host "`n🔄 Restarting telemetry service to apply settings..."
    Stop-ScheduledTask -TaskName "SystemDashboard-Telemetry"
    Start-Sleep 3
    Start-ScheduledTask -TaskName "SystemDashboard-Telemetry"
    Write-Host "✅ Telemetry service restarted" -ForegroundColor Green

    Write-Host "`n💡 Test syslog reception using option 7 (Test Syslog Sender)" -ForegroundColor Cyan

    Read-Host "`nPress Enter to return to menu"
    Show-DashboardMenu
}
function Show-WiFiMonitoring {
    Clear-Host
    Write-Host "📡 WiFi Client Monitoring Setup" -ForegroundColor Cyan
    Write-Host "=" * 32

    Write-Host "Configure SSH access to your ASUS router for WiFi client tracking:" -ForegroundColor Yellow
    Write-Host ""

    # Get current SSH configuration status
    try {
        $config = Get-Content ".\config.json" -Raw | ConvertFrom-Json
        $sshEnabled = $config.Service.Asus.SSH.Enabled
        $routerIP = $config.Service.Asus.SSH.Host ?? "192.168.50.1"
        $username = $config.Service.Asus.SSH.Username ?? "admin"
    }
    catch {
        $sshEnabled = $false
        $routerIP = "192.168.50.1"
        $username = "admin"
    }

    if ($sshEnabled) {
        Write-Host "✅ WiFi monitoring via SSH is currently enabled" -ForegroundColor Green
        Write-Host "   Router: $routerIP" -ForegroundColor Gray
        Write-Host "   Username: $username" -ForegroundColor Gray
    } else {
        Write-Host "⚠️ WiFi monitoring via SSH is currently disabled" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "📋 Router SSH Setup Steps:" -ForegroundColor Yellow
    Write-Host "  1. Access router admin: https://192.168.50.1:8443/" -ForegroundColor Gray
    Write-Host "  2. Go to Administration → System" -ForegroundColor Gray
    Write-Host "  3. Set 'Enable SSH' to Yes" -ForegroundColor Gray
    Write-Host "  4. Set SSH Port to 22 (default)" -ForegroundColor Gray
    Write-Host "  5. Set 'Allow SSH Port WAN' as needed" -ForegroundColor Gray
    Write-Host "  6. Apply settings and reboot if prompted" -ForegroundColor Gray

    Write-Host ""
    Write-Host "🔧 WiFi Monitoring Commands Available:" -ForegroundColor Yellow
    Write-Host "  • nvram get wl0_assoclist      - 2.4GHz clients" -ForegroundColor Gray
    Write-Host "  • nvram get wl1_assoclist      - 5GHz clients" -ForegroundColor Gray
    Write-Host "  • arp -a                       - IP to MAC mapping" -ForegroundColor Gray
    Write-Host "  • wl assoclist                 - Associated devices" -ForegroundColor Gray

    Write-Host ""
    Write-Host "🧪 Test Tools:" -ForegroundColor Yellow
    Write-Host "  A) Test router connectivity" -ForegroundColor White
    Write-Host "  B) Show available router commands" -ForegroundColor White
    Write-Host "  C) Test WiFi client gathering (requires SSH setup)" -ForegroundColor White
    Write-Host "  D) Enable WiFi monitoring in system" -ForegroundColor White
    Write-Host "  E) Disable WiFi monitoring in system" -ForegroundColor White

    Write-Host ""
    $action = Read-Host "Select an action (A-E) or press Enter to return to menu"

    switch ($action.ToUpper()) {
        "A" {
            Write-Host "`n🔍 Testing router connectivity..."
            & (Join-Path $PSScriptRoot 'asus-wifi-monitor.ps1') -RouterIP $routerIP -Username $username -TestConnection
        }
        "B" {
            Write-Host "`n📋 Available router commands..."
            & (Join-Path $PSScriptRoot 'asus-wifi-monitor.ps1') -ShowCommands
        }
        "C" {
            Write-Host "`n📡 Testing WiFi client gathering..."
            & (Join-Path $PSScriptRoot 'asus-wifi-monitor.ps1') -RouterIP $routerIP -Username $username
        }
        "D" {
            Write-Host "`n✅ Enabling WiFi monitoring..."
            Enable-WiFiMonitoring -RouterIP $routerIP -Username $username
        }
        "E" {
            Write-Host "`n⚠️ Disabling WiFi monitoring..."
            Disable-WiFiMonitoring
        }
        default {
            # Return to main menu
        }
    }

    if ($action) {
        Read-Host "`nPress Enter to return to menu"
    }
    Show-DashboardMenu
}

function Enable-WiFiMonitoring {
    param([string]$RouterIP, [string]$Username)

    try {
        $config = Get-Content ".\config.json" -Raw | ConvertFrom-Json
        $config.Service.Asus.SSH.Enabled = $true
        $config.Service.Asus.SSH.Host = $RouterIP
        $config.Service.Asus.SSH.Username = $Username

        $config | ConvertTo-Json -Depth 10 | Set-Content ".\config.json" -Encoding UTF8

        Write-Host "✅ WiFi monitoring enabled in configuration" -ForegroundColor Green
        Write-Host "🔄 Restart the telemetry service to apply changes" -ForegroundColor Yellow

        $restart = Read-Host "Restart telemetry service now? (y/n)"
        if ($restart -eq 'y') {
            Stop-ScheduledTask -TaskName "SystemDashboard-Telemetry"
            Start-Sleep 3
            Start-ScheduledTask -TaskName "SystemDashboard-Telemetry"
            Write-Host "✅ Telemetry service restarted" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "❌ Failed to enable WiFi monitoring: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Disable-WiFiMonitoring {
    try {
        $config = Get-Content ".\config.json" -Raw | ConvertFrom-Json
        $config.Service.Asus.SSH.Enabled = $false

        $config | ConvertTo-Json -Depth 10 | Set-Content ".\config.json" -Encoding UTF8

        Write-Host "⚠️ WiFi monitoring disabled in configuration" -ForegroundColor Yellow
        Write-Host "🔄 Restart the telemetry service to apply changes" -ForegroundColor Yellow

        $restart = Read-Host "Restart telemetry service now? (y/n)"
        if ($restart -eq 'y') {
            Stop-ScheduledTask -TaskName "SystemDashboard-Telemetry"
            Start-Sleep 3
            Start-ScheduledTask -TaskName "SystemDashboard-Telemetry"
            Write-Host "✅ Telemetry service restarted" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "❌ Failed to disable WiFi monitoring: $($_.Exception.Message)" -ForegroundColor Red
    }
}

    Clear-Host
    Write-Host "🔄 Continuous Windows Event Collection" -ForegroundColor Cyan
    Write-Host "=" * 40

    Write-Host "This will start continuous Windows event collection in the background."
    Write-Host "Events will be collected every 5 minutes and staged for processing."
    Write-Host ""

    $start = Read-Host "Start continuous event collection? (y/n)"

    if ($start -eq 'y') {
        Import-Module .\tools\ContinuousEventCollector.psm1 -Force

        Write-Host "🧪 Running test first..." -ForegroundColor Yellow
        Test-WindowsEventCollection

        Write-Host "`n🚀 Starting continuous collection..." -ForegroundColor Green
        Write-Host "Press Ctrl+C to stop collection and return to menu" -ForegroundColor Yellow

        try {
            Start-ContinuousEventCollection -IntervalSeconds 300
        }
        catch {
            Write-Host "`n⏸️ Continuous collection stopped" -ForegroundColor Yellow
        }
    }

    Read-Host "`nPress Enter to return to menu"
    Show-DashboardMenu


function Show-DataSourceManager {
    Clear-Host
    Write-Host "📊 Data Source Manager" -ForegroundColor Cyan
    Write-Host "=" * 25

    Import-Module .\tools\DataSourceManager.psm1 -Force
    $sources = Get-DefaultDataSources

    Write-Host "Available Data Sources:" -ForegroundColor Yellow
    foreach ($sourceName in $sources.Keys) {
        $source = $sources[$sourceName]
        $status = if ($source.Enabled) { "✅ Enabled" } else { "⚠️ Disabled" }
        Write-Host "  • $sourceName ($($source.Type)): $status" -ForegroundColor White
    }

    Write-Host "`nTo customize data sources, edit the configuration in:"
    Write-Host "  tools\DataSourceManager.psm1" -ForegroundColor Gray

    Read-Host "`nPress Enter to return to menu"
    Show-DashboardMenu
}

function Start-ContinuousEventsMenu {
    Clear-Host
    Write-Host "🧪 Generate Test Data" -ForegroundColor Cyan
    Write-Host "=" * 22

    Write-Host "Creating test events and data..." -ForegroundColor Yellow

    # Run the test data collection script
    & (Join-Path $PSScriptRoot 'test-data-collection.ps1')

    Write-Host "`n✅ Test data generation completed!" -ForegroundColor Green
    Read-Host "Press Enter to return to menu"
    Show-DashboardMenu
}

function Test-SyslogSender {
    Clear-Host
    Write-Host "📡 Test Syslog Sender" -ForegroundColor Cyan
    Write-Host "=" * 20

    Write-Host "This will send test syslog messages to verify the UDP listener is working." -ForegroundColor Yellow
    Write-Host ""

    $count = Read-Host "How many test messages to send? (default: 5)"
    if ([string]::IsNullOrWhiteSpace($count)) { $count = 5 }

    $facility = Read-Host "Syslog facility (local0, local1, daemon, etc. - default: local0)"
    if ([string]::IsNullOrWhiteSpace($facility)) { $facility = "local0" }

    Write-Host "`n🚀 Sending $count test syslog messages..." -ForegroundColor Green

    try {
        & (Join-Path $PSScriptRoot 'test-syslog-sender.ps1') -Count $count -Facility $facility -Source "dashboard-test"

        Write-Host "`n💡 Check option 8 (View Recent Data) to see if messages were received!" -ForegroundColor Cyan
    }
    catch {
        Write-Host "❌ Error running syslog test: $($_.Exception.Message)" -ForegroundColor Red
    }

    Read-Host "`nPress Enter to return to menu"
    Show-DashboardMenu
}

function Show-RecentData {
    Clear-Host
    Write-Host "📈 Recent Telemetry Data" -ForegroundColor Cyan
    Write-Host "=" * 25

    try {
        Write-Host "Recent Windows Events:" -ForegroundColor Yellow
        docker exec postgres-container psql -U sysdash_reader -d system_dashboard -c "
        SELECT TO_CHAR(received_utc, 'MM-DD HH24:MI') as time,
               provider_name,
               level_text,
               LEFT(message, 60) as message_preview
        FROM telemetry.eventlog_windows_recent
        ORDER BY received_utc DESC
        LIMIT 5;"

        Write-Host "`nRecent IIS Requests:" -ForegroundColor Yellow
        docker exec postgres-container psql -U sysdash_reader -d system_dashboard -c "
        SELECT TO_CHAR(received_utc, 'MM-DD HH24:MI') as time,
               client_ip,
               method,
               status,
               LEFT(uri_stem, 30) as uri
        FROM telemetry.iis_requests_recent
        ORDER BY received_utc DESC
        LIMIT 5;"

        Write-Host "`nRecent Syslog Entries:" -ForegroundColor Yellow
        docker exec postgres-container psql -U sysdash_reader -d system_dashboard -c "
        SELECT TO_CHAR(received_utc, 'MM-DD HH24:MI') as time,
               source,
               severity,
               LEFT(message, 50) as message_preview
        FROM telemetry.syslog_recent
        ORDER BY received_utc DESC
        LIMIT 5;"
    }
    catch {
        Write-Host "❌ Error retrieving data: $($_.Exception.Message)" -ForegroundColor Red
    }

    Read-Host "`nPress Enter to return to menu"
    Show-DashboardMenu
}

function Restart-AllServices {
    Clear-Host
    Write-Host "🔄 Restarting All Services" -ForegroundColor Cyan
    Write-Host "=" * 26

    $services = @('SystemDashboard-Telemetry', 'SystemDashboard-LegacyUI')

    foreach ($service in $services) {
        Write-Host "Restarting $service..." -ForegroundColor Yellow
        Stop-ScheduledTask -TaskName $service
        Start-Sleep 2
        Start-ScheduledTask -TaskName $service
        Write-Host "✅ $service restarted" -ForegroundColor Green
    }

    Write-Host "`n✅ All services restarted successfully!" -ForegroundColor Green
    Start-Sleep 2
    Show-DashboardMenu
}

function Open-DashboardInBrowser {
    Write-Host "🌐 Opening System Dashboard..." -ForegroundColor Cyan
    $configPath = Join-Path $repoRoot "config.json"
    $prefix = "http://localhost:15000/"
    if (Test-Path $configPath) {
        try {
            $config = Get-Content $configPath -Raw | ConvertFrom-Json
            if ($config.Prefix) {
                $prefix = $config.Prefix
            }
        } catch {
            $prefix = "http://localhost:15000/"
        }
    }
    Start-Process $prefix
    Start-Sleep 1
    Show-DashboardMenu
}

# Main execution
if ($Action -eq "menu") {
    Show-DashboardMenu
} elseif ($RouterMonitoring) {
    Enable-RouterMonitoring
} elseif ($ContinuousEvents) {
    Import-Module .\tools\ContinuousEventCollector.psm1 -Force
    Start-ContinuousEventCollection
} elseif ($HealthMonitoring) {
    Import-Module .\tools\SystemMonitoring.psm1 -Force
    Start-HealthMonitoring
} elseif ($Maintenance) {
    Import-Module .\tools\SystemMonitoring.psm1 -Force
    Invoke-MaintenanceTasks
} else {
    Show-DashboardMenu
}

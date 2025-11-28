# ASUS Router WiFi Client Monitor
# Connects to ASUS router via SSH and gathers WiFi client information

param(
    [string]$RouterIP = "192.168.50.1",
    [string]$Username = "xfaith",
    [string]$Password,
    [switch]$ShowCommands,
    [switch]$TestConnection
)

function Show-RouterCommands {
    Write-Host "🔧 ASUS Router CLI Commands for WiFi Monitoring" -ForegroundColor Cyan
    Write-Host "=" * 50
    Write-Host ""
    Write-Host "📡 WiFi Client Information:" -ForegroundColor Yellow
    Write-Host "  nvram get wl0_assoclist        # 2.4GHz connected clients"
    Write-Host "  nvram get wl1_assoclist        # 5GHz connected clients"
    Write-Host "  nvram get wl2_assoclist        # 6GHz clients (WiFi 6E)"
    Write-Host "  wl -i eth1 assoclist           # Alternative 2.4GHz method"
    Write-Host "  wl -i eth2 assoclist           # Alternative 5GHz method"
    Write-Host ""
    Write-Host "🌐 Network Information:" -ForegroundColor Yellow
    Write-Host "  arp -a                         # ARP table (IP to MAC mapping)"
    Write-Host "  cat /proc/net/arp              # Alternative ARP table"
    Write-Host "  ifconfig                       # Network interface status"
    Write-Host "  netstat -an                    # Network connections"
    Write-Host ""
    Write-Host "📊 System Information:" -ForegroundColor Yellow
    Write-Host "  nvram show | grep wl           # WiFi-related settings"
    Write-Host "  ps | grep wl                   # WiFi-related processes"
    Write-Host "  free                           # Memory usage"
    Write-Host "  df -h                          # Disk usage"
    Write-Host ""
    Write-Host "🔍 Advanced Monitoring:" -ForegroundColor Yellow
    Write-Host "  cat /tmp/wifi_clients.txt      # Custom client list (if exists)"
    Write-Host "  dmesg | grep -i wifi           # WiFi-related kernel messages"
    Write-Host "  logread | grep -i assoc        # Recent association logs"
    Write-Host ""
    Write-Host "📝 NVRAM Variables for WiFi:" -ForegroundColor Yellow
    Write-Host "  nvram get wl0_ssid             # 2.4GHz SSID"
    Write-Host "  nvram get wl1_ssid             # 5GHz SSID"
    Write-Host "  nvram get wl0_channel          # 2.4GHz channel"
    Write-Host "  nvram get wl1_channel          # 5GHz channel"
    Write-Host "  nvram get wl0_mode             # 2.4GHz mode (AP/etc)"
    Write-Host "  nvram get wl1_mode             # 5GHz mode"
}

function Test-RouterConnection {
    param(
        [string]$RouterIP,
        [string]$Username,
        [string]$Password
    )

    Write-Host "🔍 Testing Connection to Router" -ForegroundColor Cyan
    Write-Host "=" * 35

    # Test basic connectivity
    Write-Host "Testing ping to $RouterIP..." -ForegroundColor Yellow
    try {
        $ping = Test-Connection -ComputerName $RouterIP -Count 2 -Quiet
        if ($ping) {
            Write-Host "✅ Ping successful" -ForegroundColor Green
        } else {
            Write-Host "❌ Ping failed" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "❌ Ping failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }

    # Test SSH port
    Write-Host "Testing SSH port 22..." -ForegroundColor Yellow
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $connect = $tcpClient.BeginConnect($RouterIP, 22, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne(3000, $false)

        if ($wait -and $tcpClient.Connected) {
            Write-Host "✅ SSH port 22 is open" -ForegroundColor Green
            $tcpClient.Close()
        } else {
            Write-Host "❌ SSH port 22 is not accessible" -ForegroundColor Red
            $tcpClient.Close()
            return $false
        }
    }
    catch {
        Write-Host "❌ SSH port test failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }

    # Note about SSH authentication
    Write-Host ""
    Write-Host "📋 Next Steps for SSH Setup:" -ForegroundColor Yellow
    Write-Host "1. Enable SSH on router (Administration → System → SSH Daemon = Yes)"
    Write-Host "2. Test manual connection: ssh $Username@$RouterIP"
    Write-Host "3. For automation, consider SSH key authentication"
    Write-Host "4. Install Posh-SSH module: Install-Module -Name Posh-SSH"

    return $true
}

function Get-WiFiClientInfo {
    param(
        [string]$RouterIP,
        [string]$Username,
        [string]$Password
    )

    Write-Host "📡 Gathering WiFi Client Information" -ForegroundColor Cyan
    Write-Host "=" * 40

    # Check if Posh-SSH is available
    $poshSSH = Get-Module -Name Posh-SSH -ListAvailable
    if (-not $poshSSH) {
        Write-Host "⚠️ Posh-SSH module not found. Installing..." -ForegroundColor Yellow
        try {
            Install-Module -Name Posh-SSH -Force -Scope CurrentUser
            Import-Module Posh-SSH
            Write-Host "✅ Posh-SSH installed successfully" -ForegroundColor Green
        }
        catch {
            Write-Host "❌ Failed to install Posh-SSH: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "💡 Install manually: Install-Module -Name Posh-SSH" -ForegroundColor Yellow
            return
        }
    } else {
        Import-Module Posh-SSH -ErrorAction SilentlyContinue
    }

    # Commands to execute on router
    $commands = @(
        @{ Name = "2.4GHz Clients (NVRAM)"; Command = "nvram get wl0_assoclist" },
        @{ Name = "5GHz Clients (NVRAM)"; Command = "nvram get wl1_assoclist" },
        @{ Name = "6GHz Clients (NVRAM)"; Command = "nvram get wl2_assoclist" },
        @{ Name = "ARP Table"; Command = "arp -a" },
        @{ Name = "WiFi Interfaces"; Command = "ifconfig | grep -A5 -B1 wl" },
        @{ Name = "Associated Devices (wl tool)"; Command = "wl assoclist" }
    )

    try {
        # Create SSH session
        $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($Username, $securePassword)

        Write-Host "Connecting to $RouterIP..." -ForegroundColor Yellow
        $session = New-SSHSession -ComputerName $RouterIP -Credential $credential -AcceptKey -ErrorAction Stop

        Write-Host "✅ SSH connection established" -ForegroundColor Green
        Write-Host ""

        foreach ($cmd in $commands) {
            Write-Host "🔍 $($cmd.Name):" -ForegroundColor Yellow
            try {
                $result = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd.Command -TimeOut 30
                if ($result.Output) {
                    $result.Output | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
                } else {
                    Write-Host "  (No output)" -ForegroundColor Gray
                }
                Write-Host ""
            }
            catch {
                Write-Host "  ❌ Command failed: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host ""
            }
        }

        # Close SSH session
        Remove-SSHSession -SessionId $session.SessionId | Out-Null
        Write-Host "✅ SSH session closed" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ SSH connection failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        Write-Host "💡 Troubleshooting tips:" -ForegroundColor Yellow
        Write-Host "  • Verify SSH is enabled on router (Administration → System)"
        Write-Host "  • Check username and password"
        Write-Host "  • Ensure router IP is correct: $RouterIP"
        Write-Host "  • Try manual SSH: ssh $Username@$RouterIP"
    }
}

# Main execution
if ($ShowCommands) {
    Show-RouterCommands
    exit
}

if (-not $Password) {
    if ($env:ASUS_ROUTER_PASSWORD) {
        $Password = $env:ASUS_ROUTER_PASSWORD
    } else {
        $Password = Read-Host "Enter router password" -AsSecureString
        $Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))
    }
}

Write-Host "🏠 ASUS Router WiFi Client Monitor" -ForegroundColor Cyan
Write-Host "Router: $RouterIP" -ForegroundColor Gray
Write-Host "User: $Username" -ForegroundColor Gray
Write-Host ""

if ($TestConnection) {
    Test-RouterConnection -RouterIP $RouterIP -Username $Username -Password $Password
} else {
    Get-WiFiClientInfo -RouterIP $RouterIP -Username $Username -Password $Password
}

Write-Host ""
Write-Host "📚 Usage Examples:" -ForegroundColor Yellow
Write-Host "  .\asus-wifi-monitor.ps1 -ShowCommands      # Show available router commands"
Write-Host "  .\asus-wifi-monitor.ps1 -TestConnection    # Test router connectivity"
Write-Host "  .\asus-wifi-monitor.ps1                    # Gather WiFi client info"
Write-Host "  .\asus-wifi-monitor.ps1 -RouterIP 192.168.1.1 -Username admin"

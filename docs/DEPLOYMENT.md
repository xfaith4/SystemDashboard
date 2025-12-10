# SystemDashboard - Production Deployment Guide

This guide covers deploying SystemDashboard in a production environment with best practices for security, reliability, and performance.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Pre-Deployment Checklist](#pre-deployment-checklist)
- [Installation Steps](#installation-steps)
- [Security Configuration](#security-configuration)
- [Service Configuration](#service-configuration)
- [Network Configuration](#network-configuration)
- [Performance Tuning](#performance-tuning)
- [Monitoring Setup](#monitoring-setup)
- [Backup Configuration](#backup-configuration)
- [Validation](#validation)
- [Post-Deployment Tasks](#post-deployment-tasks)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### Hardware Requirements

**Minimum**:
- CPU: 2 cores @ 2.0 GHz
- RAM: 4 GB
- Disk: 20 GB free space (SSD recommended)
- Network: 100 Mbps

**Recommended**:
- CPU: 4 cores @ 2.5 GHz
- RAM: 8 GB
- Disk: 50 GB free space (SSD required)
- Network: 1 Gbps

### Software Requirements

- **Windows Server 2019 or later** (or Windows 11 Pro/Enterprise)
- **PowerShell 7.3+** - [Download](https://github.com/PowerShell/PowerShell/releases)
- **Python 3.10+** - [Download](https://www.python.org/downloads/)
- **Git** - [Download](https://git-scm.com/downloads)
- **.NET Framework 4.8+** (usually pre-installed)

### Network Requirements

- **Inbound UDP 514** - For syslog reception
- **Outbound HTTPS (443)** - For router polling (if applicable)
- **Internal HTTP/HTTPS** - For dashboard access (choose port)

### Access Requirements

- Administrator access to Windows Server
- Ability to create Windows Services
- Ability to create Scheduled Tasks
- Firewall configuration access

## Pre-Deployment Checklist

Before beginning installation, complete these tasks:

- [ ] Server provisioned and accessible
- [ ] DNS name configured (e.g., `sysmon.company.local`)
- [ ] SSL certificate obtained (self-signed or CA-issued)
- [ ] Router credentials available (if monitoring ASUS router)
- [ ] OpenAI API key available (if using AI features)
- [ ] Backup strategy defined
- [ ] Monitoring tools configured
- [ ] Change management ticket approved
- [ ] Maintenance window scheduled

## Installation Steps

### 1. Server Preparation

```powershell
# Update Windows
Install-WindowsUpdate -AcceptAll -AutoReboot

# Install PowerShell 7
winget install Microsoft.PowerShell

# Verify version
pwsh -Version  # Should be 7.3+

# Install Python
winget install Python.Python.3.12

# Verify Python
python --version  # Should be 3.10+

# Install Git
winget install Git.Git

# Reboot to apply changes
Restart-Computer
```

### 2. Clone Repository

```powershell
# Create installation directory
New-Item -ItemType Directory -Path "C:\SystemDashboard" -Force
cd C:\SystemDashboard

# Clone repository
git clone https://github.com/xfaith4/SystemDashboard.git .

# Verify clone
Test-Path .\app\app.py  # Should return True
```

### 3. Configure Environment Variables

```powershell
# Set production environment variables
[System.Environment]::SetEnvironmentVariable('ASUS_ROUTER_PASSWORD', 'your_secure_password', 'Machine')
[System.Environment]::SetEnvironmentVariable('OPENAI_API_KEY', 'sk-...', 'Machine')
[System.Environment]::SetEnvironmentVariable('DASHBOARD_API_KEY', 'your_api_key_here', 'Machine')
[System.Environment]::SetEnvironmentVariable('FLASK_ENV', 'production', 'Machine')

# Verify
[System.Environment]::GetEnvironmentVariable('DASHBOARD_API_KEY', 'Machine')
```

**Security Note**: Store passwords in a secrets manager if available (Azure Key Vault, AWS Secrets Manager, etc.).

### 4. Update Configuration

Edit `config.json` for production:

```json
{
  "Database": {
    "Host": "localhost",
    "Database": "C:\\SystemDashboard\\var\\system_dashboard.db",
    "Schema": "telemetry"
  },
  "Service": {
    "LogPath": "C:\\SystemDashboard\\var\\log\\telemetry-service.log",
    "Syslog": {
      "BindAddress": "0.0.0.0",
      "Port": 514,
      "BufferDirectory": "C:\\SystemDashboard\\var\\syslog-buffer",
      "MaxMessageBytes": 2048
    },
    "Asus": {
      "Enabled": true,
      "Uri": "https://192.168.1.1/syslog.txt",
      "HostName": "RT-AX88U",
      "PollIntervalSeconds": 300,
      "DownloadPath": "C:\\SystemDashboard\\var\\asus",
      "StatePath": "C:\\SystemDashboard\\var\\asus\\state.json"
    },
    "Ingestion": {
      "BatchIntervalSeconds": 30,
      "MinBatchSize": 100,
      "StagingDirectory": "C:\\SystemDashboard\\var\\staging"
    }
  }
}
```

**Key Production Changes**:
- Use absolute paths (not relative)
- Set `Syslog.BindAddress` to `0.0.0.0` to listen on all interfaces
- Increase `PollIntervalSeconds` to reduce load
- Increase `BatchIntervalSeconds` for efficiency

### 5. Initialize Database

```powershell
# Create database with production schema
python scripts/init_db.py

# Verify database
python scripts/init_db.py --verify

# Check database file
Test-Path .\var\system_dashboard.db  # Should return True
(Get-Item .\var\system_dashboard.db).Length / 1MB  # Should show size in MB
```

### 6. Install Services

```powershell
# Run installation script
.\scripts\Install.ps1

# Verify module installation
Get-Module -ListAvailable SystemDashboard

# Verify service registration
Get-Service SystemDashboardTelemetry

# Set service to start automatically
Set-Service -Name SystemDashboardTelemetry -StartupType Automatic
```

### 7. Install Scheduled Tasks

```powershell
# Install permanent services
.\scripts\setup-permanent-services.ps1 -Install

# Verify scheduled tasks
Get-ScheduledTask -TaskName "SystemDashboard-*"

# Expected tasks:
# - SystemDashboard-WebUI
# - SystemDashboard-LANCollector
# - SystemDashboard-SyslogCollector
```

### 8. Apply LAN Observability Schema

```powershell
# Apply LAN schema
.\scripts\apply-lan-schema.ps1

# Verify schema
python -c "import sqlite3; conn=sqlite3.connect('var/system_dashboard.db'); print(conn.execute(\"SELECT name FROM sqlite_master WHERE type='table' AND name='devices'\").fetchone())"
```

## Security Configuration

### 1. Enable API Key Authentication

```powershell
# Set API key (already done in step 3)
$apiKey = [System.Environment]::GetEnvironmentVariable('DASHBOARD_API_KEY', 'Machine')

# Verify app.py will use authentication
Select-String -Path .\app\app.py -Pattern "APIKeyAuth" -Context 2
```

In `app/app.py`, ensure authentication is enabled:

```python
from app.auth import APIKeyAuth, require_api_key

# Initialize authentication
auth = APIKeyAuth(os.getenv('DASHBOARD_API_KEY'))

# Protect sensitive endpoints
@app.route('/api/devices/<mac>', methods=['PUT'])
@require_api_key
def update_device(mac):
    # Protected endpoint
    pass
```

### 2. Generate SSL Certificate

**Option A: Self-Signed Certificate (for internal use)**

```powershell
# Generate certificate
.\scripts\New-SelfSignedCertificate.ps1 -DnsName "sysmon.company.local" -OutputPath "C:\SystemDashboard\certs"

# Expected output:
# - cert.pem (certificate)
# - key.pem (private key)
# - cert.pfx (Windows format)
```

**Option B: CA-Issued Certificate (recommended for production)**

1. Generate Certificate Signing Request (CSR):
   ```powershell
   $cert = New-SelfSignedCertificate -DnsName "sysmon.company.local" -CertStoreLocation "cert:\LocalMachine\My" -KeyExportPolicy Exportable
   $certPath = "cert:\LocalMachine\My\$($cert.Thumbprint)"
   Export-Certificate -Cert $certPath -FilePath "C:\SystemDashboard\certs\request.csr" -Type CERT
   ```

2. Submit CSR to your Certificate Authority
3. Install issued certificate:
   ```powershell
   Import-Certificate -FilePath "C:\SystemDashboard\certs\issued-cert.crt" -CertStoreLocation "cert:\LocalMachine\My"
   ```

### 3. Configure HTTPS in Flask

Edit `app/app.py` to enable HTTPS:

```python
if __name__ == '__main__':
    import ssl
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain('C:/SystemDashboard/certs/cert.pem', 
                             'C:/SystemDashboard/certs/key.pem')
    
    app.run(
        host='0.0.0.0',
        port=5443,  # HTTPS port
        ssl_context=context,
        debug=False  # Must be False in production
    )
```

### 4. Enable Security Features

In `app/app.py`, ensure all security modules are enabled:

```python
from app.security_headers import SecurityHeaders
from app.csrf_protection import CSRFProtection
from app.rate_limiter import RateLimiter
from app.audit_trail import AuditTrail

# Initialize security
security_headers = SecurityHeaders(app)
csrf = CSRFProtection(app)
rate_limiter = RateLimiter(app, default_limit=100)  # 100 requests/min
audit = AuditTrail(get_database_manager())
```

### 5. Configure Windows Firewall

```powershell
# Allow syslog (UDP 514)
New-NetFirewallRule -DisplayName "SystemDashboard Syslog" -Direction Inbound -Protocol UDP -LocalPort 514 -Action Allow

# Allow HTTPS (TCP 5443)
New-NetFirewallRule -DisplayName "SystemDashboard HTTPS" -Direction Inbound -Protocol TCP -LocalPort 5443 -Action Allow

# Verify rules
Get-NetFirewallRule -DisplayName "SystemDashboard*"
```

### 6. Set File Permissions

```powershell
# Restrict database access
$acl = Get-Acl "C:\SystemDashboard\var\system_dashboard.db"
$acl.SetAccessRuleProtection($true, $false)
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl", "Allow")
$acl.AddAccessRule($rule)
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators", "FullControl", "Allow")
$acl.AddAccessRule($rule)
Set-Acl "C:\SystemDashboard\var\system_dashboard.db" $acl

# Restrict config.json
$acl = Get-Acl "C:\SystemDashboard\config.json"
$acl.SetAccessRuleProtection($true, $false)
Set-Acl "C:\SystemDashboard\config.json" $acl
```

## Service Configuration

### 1. Configure Telemetry Service

```powershell
# Set service account (optional: use specific service account)
sc.exe config SystemDashboardTelemetry obj= "NT AUTHORITY\SYSTEM" password= ""

# Set recovery options (restart on failure)
sc.exe failure SystemDashboardTelemetry reset= 86400 actions= restart/60000/restart/60000/restart/60000

# Set service description
sc.exe description SystemDashboardTelemetry "SystemDashboard telemetry collection service"
```

### 2. Configure WebUI Scheduled Task

```powershell
# Get task
$task = Get-ScheduledTask -TaskName "SystemDashboard-WebUI"

# Update to run on startup
$trigger = New-ScheduledTaskTrigger -AtStartup
$task.Triggers = $trigger

# Set to run with highest privileges
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
$task.Principal = $principal

# Update task
Set-ScheduledTask -InputObject $task
```

### 3. Configure Data Retention

Create scheduled task for daily cleanup:

```powershell
$action = New-ScheduledTaskAction -Execute "python" -Argument "C:\SystemDashboard\scripts\run-data-retention.py" -WorkingDirectory "C:\SystemDashboard"
$trigger = New-ScheduledTaskTrigger -Daily -At 2AM
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName "SystemDashboard-DataRetention" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Daily data retention cleanup"
```

Create the retention script:

```python
# scripts/run-data-retention.py
from app.data_retention import get_retention_manager
import logging

logging.basicConfig(level=logging.INFO)
manager = get_retention_manager()
manager.run_cleanup()
manager.run_cleanup(vacuum=False)  # VACUUM separately on weekends
```

### 4. Configure VACUUM Task

```powershell
$action = New-ScheduledTaskAction -Execute "sqlite3" -Argument "C:\SystemDashboard\var\system_dashboard.db 'VACUUM;'" -WorkingDirectory "C:\SystemDashboard"
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3AM
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

Register-ScheduledTask -TaskName "SystemDashboard-Vacuum" -Action $action -Trigger $trigger -Principal $principal -Description "Weekly database VACUUM"
```

## Network Configuration

### 1. Configure Router Syslog

On your ASUS router:

1. Login to router admin panel
2. Navigate to **System Log** → **Log Server**
3. Set **Log Server IP**: `<Windows Server IP>`
4. Set **Log Server Port**: `514`
5. Enable **Send syslog messages**
6. Click **Apply**

### 2. Configure Network Devices

For devices to send syslog:

```bash
# Linux example
echo "*.* @192.168.1.100:514" >> /etc/rsyslog.conf
systemctl restart rsyslog

# Cisco example
logging host 192.168.1.100 transport udp port 514
logging trap informational
```

### 3. Test Syslog Reception

```powershell
# Send test message
$socket = New-Object System.Net.Sockets.UdpClient
$bytes = [System.Text.Encoding]::UTF8.GetBytes("<14>Test message from PowerShell")
$socket.Send($bytes, $bytes.Length, "localhost", 514)
$socket.Close()

# Check if received
python -c "import sqlite3; conn=sqlite3.connect('var/system_dashboard.db'); print(conn.execute('SELECT COUNT(*) FROM syslog_messages WHERE message LIKE \"%PowerShell%\"').fetchone())"
```

### 4. Configure DNS (Optional)

Add DNS entry for dashboard:

```powershell
# If running Windows DNS Server
Add-DnsServerResourceRecordA -Name "sysmon" -ZoneName "company.local" -IPv4Address "192.168.1.100"

# Verify
Resolve-DnsName sysmon.company.local
```

## Performance Tuning

### 1. Optimize Database Settings

Edit `app/db_manager.py` for production:

```python
class DatabaseManager:
    def __init__(self, db_path):
        self.db_path = db_path
        self.max_connections = 10  # Increase for production
        self.query_timeout = 30  # Increase timeout
        self.busy_timeout = 5000  # 5 seconds
```

### 2. Enable Query Caching

In `app/app.py`:

```python
from app.api_utils import cache_response

@app.route('/api/devices')
@cache_response(ttl=300)  # 5-minute cache
def get_devices():
    # Expensive query cached
    pass
```

### 3. Configure Connection Pool

```powershell
# Update config.json
# "MaxConnections": 10  # Increase from default 5
```

### 4. Tune Batch Ingestion

In `config.json`:

```json
"Service": {
  "Ingestion": {
    "BatchIntervalSeconds": 60,  # Increase from 30
    "MinBatchSize": 500,  # Increase from 100
    "StagingDirectory": "C:\\SystemDashboard\\var\\staging"
  }
}
```

### 5. Enable Lazy Loading

Verify in `app/templates/base.html`:

```html
<script src="{{ url_for('static', filename='performance-utils.js') }}"></script>
<script>
  // Initialize lazy loading for charts
  document.addEventListener('DOMContentLoaded', () => {
    const lazyLoader = new ChartLazyLoader();
    lazyLoader.observeAll();
  });
</script>
```

## Monitoring Setup

### 1. Configure Health Check Monitoring

Create a monitoring script:

```powershell
# scripts/check-health.ps1
$response = Invoke-RestMethod -Uri "https://localhost:5443/health/detailed" -SkipCertificateCheck
if ($response.status -ne "healthy") {
    Write-Error "Health check failed: $($response.issues)"
    Send-MailMessage -To "admin@company.com" -From "sysmon@company.local" -Subject "SystemDashboard Health Alert" -Body "Status: $($response.status)"
}
```

Schedule health checks:

```powershell
$action = New-ScheduledTaskAction -Execute "pwsh" -Argument "-File C:\SystemDashboard\scripts\check-health.ps1" -WorkingDirectory "C:\SystemDashboard"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration ([TimeSpan]::MaxValue)

Register-ScheduledTask -TaskName "SystemDashboard-HealthCheck" -Action $action -Trigger $trigger
```

### 2. Configure Performance Monitoring

```powershell
# Check query performance
Invoke-RestMethod -Uri "https://localhost:5443/api/performance/queries" | ConvertTo-Json

# Check resource usage
Invoke-RestMethod -Uri "https://localhost:5443/api/performance/resources" | ConvertTo-Json
```

### 3. Configure Log Rotation

Create log rotation script:

```powershell
# scripts/rotate-logs.ps1
$logDir = "C:\SystemDashboard\var\log"
$maxSizeMB = 100
$maxAge = 30  # days

Get-ChildItem $logDir -Filter "*.log" | ForEach-Object {
    if ($_.Length / 1MB -gt $maxSizeMB) {
        $archiveName = "$($_.BaseName)-$(Get-Date -Format 'yyyyMMdd').log"
        Compress-Archive -Path $_.FullName -DestinationPath "$logDir\archive\$archiveName.zip"
        Clear-Content $_.FullName
    }
}

# Delete old archives
Get-ChildItem "$logDir\archive" -Filter "*.zip" | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$maxAge) } | Remove-Item
```

Schedule log rotation:

```powershell
$action = New-ScheduledTaskAction -Execute "pwsh" -Argument "-File C:\SystemDashboard\scripts\rotate-logs.ps1" -WorkingDirectory "C:\SystemDashboard"
$trigger = New-ScheduledTaskTrigger -Daily -At 1AM

Register-ScheduledTask -TaskName "SystemDashboard-LogRotation" -Action $action -Trigger $trigger
```

## Backup Configuration

### 1. Database Backup

Create backup script:

```powershell
# scripts/backup-database.ps1
param(
    [string]$BackupPath = "C:\Backups\SystemDashboard"
)

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$dbPath = "C:\SystemDashboard\var\system_dashboard.db"
$backupFile = Join-Path $BackupPath "system_dashboard-$timestamp.db"

# Create backup directory
New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null

# Copy database
Copy-Item -Path $dbPath -Destination $backupFile -Force

# Compress backup
Compress-Archive -Path $backupFile -DestinationPath "$backupFile.zip" -Force
Remove-Item $backupFile

Write-Output "Backup created: $backupFile.zip"

# Cleanup old backups (keep last 30 days)
Get-ChildItem $BackupPath -Filter "*.zip" | 
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | 
    Remove-Item -Force
```

Schedule daily backup:

```powershell
$action = New-ScheduledTaskAction -Execute "pwsh" -Argument "-File C:\SystemDashboard\scripts\backup-database.ps1" -WorkingDirectory "C:\SystemDashboard"
$trigger = New-ScheduledTaskTrigger -Daily -At 12AM

Register-ScheduledTask -TaskName "SystemDashboard-Backup" -Action $action -Trigger $trigger -Description "Daily database backup"
```

### 2. Configuration Backup

```powershell
# Backup config.json and certificates
Copy-Item "C:\SystemDashboard\config.json" "C:\Backups\SystemDashboard\config-$(Get-Date -Format 'yyyyMMdd').json"
Copy-Item -Recurse "C:\SystemDashboard\certs" "C:\Backups\SystemDashboard\certs-$(Get-Date -Format 'yyyyMMdd')" -ErrorAction SilentlyContinue
```

### 3. Test Restore Procedure

```powershell
# Test restore
$latestBackup = Get-ChildItem "C:\Backups\SystemDashboard" -Filter "*.zip" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Expand-Archive -Path $latestBackup.FullName -DestinationPath "C:\Temp\restore-test" -Force
Test-Path "C:\Temp\restore-test\system_dashboard-*.db"  # Should return True
```

## Validation

### 1. Service Status Check

```powershell
# Check Windows Service
Get-Service SystemDashboardTelemetry | Select-Object Name, Status, StartType

# Check Scheduled Tasks
Get-ScheduledTask -TaskName "SystemDashboard-*" | Select-Object TaskName, State

# Check processes
Get-Process | Where-Object { $_.Name -like "*python*" -or $_.Name -like "*pwsh*" } | Select-Object Name, CPU, WorkingSet
```

### 2. Database Validation

```powershell
# Verify database exists and is accessible
python scripts/init_db.py --verify

# Check database size
(Get-Item C:\SystemDashboard\var\system_dashboard.db).Length / 1MB

# Check table counts
python -c "import sqlite3; conn=sqlite3.connect('C:/SystemDashboard/var/system_dashboard.db'); print('Devices:', conn.execute('SELECT COUNT(*) FROM devices').fetchone()[0])"
```

### 3. Network Validation

```powershell
# Test UDP 514 listening
Test-NetConnection -ComputerName localhost -Port 514 -InformationLevel Detailed

# Test HTTPS endpoint
Invoke-WebRequest -Uri "https://localhost:5443/health" -SkipCertificateCheck

# Check firewall rules
Get-NetFirewallRule -DisplayName "SystemDashboard*" | Select-Object DisplayName, Enabled, Direction, Action
```

### 4. Security Validation

```powershell
# Verify API key required
try {
    Invoke-RestMethod -Uri "https://localhost:5443/api/devices" -SkipCertificateCheck
    Write-Error "API key not enforced!"
} catch {
    Write-Output "API key enforced correctly: $_"
}

# Test with valid API key
$headers = @{ "X-API-Key" = $env:DASHBOARD_API_KEY }
Invoke-RestMethod -Uri "https://localhost:5443/api/devices" -Headers $headers -SkipCertificateCheck
```

### 5. Performance Baseline

```powershell
# Record baseline metrics
$baseline = @{
    DatabaseSize = (Get-Item C:\SystemDashboard\var\system_dashboard.db).Length / 1MB
    MemoryUsage = (Get-Process python).WorkingSet64 / 1MB
    ResponseTime = (Measure-Command { Invoke-RestMethod -Uri "https://localhost:5443/health" -SkipCertificateCheck }).TotalMilliseconds
}
$baseline | ConvertTo-Json | Out-File "C:\SystemDashboard\baseline.json"
```

## Post-Deployment Tasks

### 1. Update Documentation

- Document server IP/DNS name
- Document certificate details
- Document backup locations
- Document emergency contacts

### 2. Configure Monitoring

- Add health check to monitoring system (Nagios, Zabbix, etc.)
- Set up email alerts for service failures
- Configure disk space alerts

### 3. User Training

- Provide dashboard URL to users
- Share API key if needed
- Conduct walkthrough session
- Share user documentation links

### 4. Change Management

- Update change management ticket with:
  - Deployment date/time
  - Configuration changes
  - Validation results
  - Known issues (if any)

### 5. Post-Deployment Review

Schedule review meeting 1 week after deployment to assess:

- Performance metrics vs. baseline
- Error rates in logs
- User feedback
- Resource utilization

## Troubleshooting

### Service Won't Start

**Problem**: `Start-Service SystemDashboardTelemetry` fails

**Solution**:
```powershell
# Check event log
Get-EventLog -LogName System -Source "Service Control Manager" -Newest 10 | Where-Object { $_.Message -like "*SystemDashboard*" }

# Check service log
Get-Content C:\SystemDashboard\var\log\telemetry-service.log -Tail 50

# Try manual start
pwsh -File C:\SystemDashboard\services\SystemDashboardService.ps1
```

### Database Locked Errors

**Problem**: "Database is locked" errors in logs

**Solution**:
```powershell
# Check for stale lock files
Get-ChildItem C:\SystemDashboard\var -Filter "*.db-*"

# Close any database browsers
Get-Process | Where-Object { $_.Name -like "*DB Browser*" } | Stop-Process

# Restart services
Restart-Service SystemDashboardTelemetry
Stop-ScheduledTask -TaskName "SystemDashboard-*"
Start-ScheduledTask -TaskName "SystemDashboard-*"
```

### High Memory Usage

**Problem**: Python process using > 500MB RAM

**Solution**:
```powershell
# Check database size
(Get-Item C:\SystemDashboard\var\system_dashboard.db).Length / 1GB

# Run data retention
python -c "from app.data_retention import get_retention_manager; get_retention_manager().run_cleanup()"

# VACUUM database
sqlite3 C:\SystemDashboard\var\system_dashboard.db "VACUUM;"

# Restart services
Restart-Service SystemDashboardTelemetry
```

### SSL Certificate Errors

**Problem**: "Certificate verification failed" errors

**Solution**:
```powershell
# Verify certificate exists
Test-Path C:\SystemDashboard\certs\cert.pem
Test-Path C:\SystemDashboard\certs\key.pem

# Check certificate validity
openssl x509 -in C:\SystemDashboard\certs\cert.pem -noout -dates

# Regenerate if expired
.\scripts\New-SelfSignedCertificate.ps1 -DnsName "sysmon.company.local" -OutputPath "C:\SystemDashboard\certs"
```

### No Data Appearing

**Problem**: Dashboard shows no data after deployment

**Solution**:
```powershell
# Verify services running
Get-Service SystemDashboardTelemetry
Get-ScheduledTask -TaskName "SystemDashboard-*"

# Check database has tables
python scripts/init_db.py --verify

# Generate test data
python -c "import sqlite3; conn=sqlite3.connect('C:/SystemDashboard/var/system_dashboard.db'); conn.execute('INSERT INTO devices VALUES (?, ?, ?, ?, ?)', ('AA:BB:CC:DD:EE:FF', 1702202400, 1702288800, 'Test Device', 'Office')); conn.commit()"

# Check logs for errors
Get-Content C:\SystemDashboard\var\log\telemetry-service.log -Tail 100 | Select-String "error"
```

## Deployment Checklist

Use this checklist to verify deployment:

- [ ] Server meets hardware requirements
- [ ] PowerShell 7.3+ installed
- [ ] Python 3.10+ installed
- [ ] Repository cloned to C:\SystemDashboard
- [ ] Environment variables configured
- [ ] config.json updated for production
- [ ] Database initialized and verified
- [ ] Windows Service created and running
- [ ] Scheduled tasks created and running
- [ ] LAN schema applied
- [ ] SSL certificate generated/installed
- [ ] HTTPS enabled in Flask
- [ ] API key authentication enabled
- [ ] Security headers enabled
- [ ] CSRF protection enabled
- [ ] Firewall rules created
- [ ] File permissions restricted
- [ ] Router syslog configured
- [ ] Health check endpoint accessible
- [ ] Backup scheduled
- [ ] Data retention scheduled
- [ ] Log rotation scheduled
- [ ] Monitoring configured
- [ ] Documentation updated
- [ ] Users notified
- [ ] Post-deployment review scheduled

## Next Steps

After successful deployment:

1. Review [MONITORING.md](MONITORING.md) for detailed monitoring setup
2. Review [BACKUP-RESTORE.md](BACKUP-RESTORE.md) for backup procedures
3. Review [PERFORMANCE-TUNING.md](PERFORMANCE-TUNING.md) for optimization tips
4. Review [UPGRADE-GUIDE.md](UPGRADE-GUIDE.md) for future upgrades

---

**Deployment complete!** Your SystemDashboard is now production-ready and monitoring your infrastructure.

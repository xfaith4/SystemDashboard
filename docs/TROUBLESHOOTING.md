# System Dashboard - Troubleshooting Guide

This guide covers common issues and their solutions.

## Service Issues

### Windows Service vs Scheduled Task

The System Dashboard uses **Scheduled Tasks** instead of traditional Windows Services for better reliability with PowerShell-based applications.

**Benefits:**

- More reliable for long-running PowerShell scripts
- Automatic restart on failure
- Better logging and monitoring
- No service timeout issues

**Management:**

```powershell
# View status
Get-ScheduledTask -TaskName "SystemDashboard-*"

# Start/Stop
Start-ScheduledTask -TaskName "SystemDashboard-Telemetry"
Stop-ScheduledTask -TaskName "SystemDashboard-Telemetry"

# View history
Get-ScheduledTaskInfo -TaskName "SystemDashboard-Telemetry"
```

### Service Fails to Start

**Symptoms:**

- Scheduled task shows "Ready" but never runs
- Task runs but stops immediately
- Error in Windows Event Log

**Solutions:**

1. Check service logs:

   ```powershell
   Get-Content ".\var\log\telemetry-service.log" -Tail 50
   ```

2. Verify PowerShell 7 is installed:

   ```powershell
   pwsh --version
   ```

3. Test service script manually:

   ```powershell
   pwsh -File .\services\SystemDashboardService.ps1
   ```

4. Check environment variables:

   ```powershell
   [Environment]::GetEnvironmentVariable("ASUS_ROUTER_PASSWORD", "User")
   ```

5. Reinstall scheduled tasks:

   ```powershell
   .\scripts\setup-permanent-services.ps1 -Uninstall
   .\scripts\setup-permanent-services.ps1 -Install
   ```

## Database Issues

### Database Connection Failed

**Symptoms:**

- Dashboard shows "Database unavailable" or errors
- Flask app shows database errors

**Solutions:**

1. Verify database file exists:

   ```powershell
   Test-Path ".\var\system_dashboard.db"
   ```

2. Initialize database if needed:

   ```powershell
   python scripts/init_db.py
   ```

3. Verify database integrity:

   ```powershell
   python scripts/init_db.py --verify
   ```

4. Check database path in `config.json`:

   ```json
   "Database": {
     "Type": "sqlite",
     "Path": "./var/system_dashboard.db"
   }
   ```

### Database Schema Missing

**Symptoms:**

- "no such table" errors in logs
- Queries fail with missing tables/views

**Solutions:**

1. Initialize the schema:

   ```powershell
   python scripts/init_db.py --force
   ```

2. Verify tables exist:

   ```bash
   sqlite3 var/system_dashboard.db ".tables"
   ```

3. Check views are created:

   ```bash
   sqlite3 var/system_dashboard.db ".schema syslog_recent"
   ```

### Database Permission Issues

**Symptoms:**

- "database is locked" errors
- Write operations fail

**Solutions:**

1. Ensure only one process writes at a time
2. Check file permissions on the database file
3. Close any SQLite browser tools that may have a lock
4. Verify the var/ directory is writable:

   ```powershell
   Test-Path ".\var" -PathType Container
   ```

## Data Collection Issues

### No Syslog Data

**Symptoms:**

- Syslog table is empty
- Router logs not appearing

**Solutions:**

1. Check if service is listening:

   ```powershell
   Get-NetUDPEndpoint | Where-Object LocalPort -eq 514
   ```

2. Test syslog reception:

   ```powershell
   .\scripts\test-syslog-sender.ps1
   ```

3. Configure router to send syslog:
   - Router admin page → System Log
   - Enable remote syslog
   - Set server IP to this machine
   - Set port to 514 (or configured port)

4. Check firewall rules:

   ```powershell
   Get-NetFirewallRule | Where-Object DisplayName -like "*SystemDashboard*"
   ```

### Router Polling Fails

**Symptoms:**

- "Failed to fetch ASUS router logs" in service log
- No router data in database

**Solutions:**

1. Verify router credentials:

   ```powershell
   $env:ASUS_ROUTER_PASSWORD
   ```

2. Test router endpoint:

   ```powershell
   $uri = "http://192.168.50.1/syslog.txt"
   Invoke-WebRequest -Uri $uri -UseBasicParsing
   ```

3. Check router configuration in `config.json`:

   ```json
   "Service": {
     "Asus": {
       "Enabled": true,
       "Uri": "http://192.168.50.1/syslog.txt",
       "HostName": "asus-router"
     }
   }
   ```

4. Enable router log export (router admin page)

### Windows Events Not Collected

**Symptoms:**

- Event logs empty in dashboard
- "Access denied" errors

**Solutions:**

1. Run PowerShell as Administrator (for Security log access)

2. Check Event Log service:

   ```powershell
   Get-Service -Name EventLog
   ```

3. Test event log access:

   ```powershell
   Get-WinEvent -LogName Application -MaxEvents 10
   ```

4. Verify permissions for reading Event Logs

## Web Dashboard Issues

### Dashboard Won't Load

**Symptoms:**

- Browser shows "Connection refused"
- 404 or 500 errors

**Solutions:**

1. Check Flask app is running:

   ```powershell
   Get-ScheduledTask -TaskName "SystemDashboard-WebUI"
   netstat -ano | Select-String ":5000"
   ```

2. Check Flask logs:

   ```powershell
   Get-Content ".\var\log\webui-service.log" -Tail 50
   ```

3. Test manually:

   ```powershell
   .\.venv\Scripts\Activate.ps1
   python .\app\app.py
   ```

4. Verify Python virtual environment exists:

   ```powershell
   Test-Path .\.venv
   ```

### Dashboard Shows No Data

**Symptoms:**

- Dashboard loads but shows empty tables
- "No data available" messages

**Solutions:**

1. Check database connection:

   ```powershell
   Invoke-RestMethod http://localhost:5000/health
   ```

2. Verify data exists:

   ```sql
   SELECT COUNT(*) FROM telemetry.syslog_recent;
   ```

3. Check database environment variables:

   ```powershell
   $env:DASHBOARD_DB_HOST
   $env:DASHBOARD_DB_NAME
   $env:DASHBOARD_DB_USER
   $env:DASHBOARD_DB_PASSWORD
   ```

4. Generate test data:

   ```powershell
   .\scripts\test-data-collection.ps1
   ```

## LAN Observability Issues

### No Devices Appearing

**Symptoms:**

- Device list is empty
- LAN dashboard shows no data

**Solutions:**

1. Check LAN collector service logs

2. Verify database schema includes device tables:

   ```bash
   sqlite3 var/system_dashboard.db ".tables" | grep devices
   ```

3. Test router connection:

   ```powershell
   .\scripts\asus-wifi-monitor.ps1 -TestConnection
   ```

4. Check device data in database:

   ```bash
   sqlite3 var/system_dashboard.db "SELECT COUNT(*) FROM devices;"
   ```

### Syslog Events Not Correlating

**Symptoms:**

- Device details show no associated events
- Correlation seems broken

**Solutions:**

1. Enable correlation in settings:

   ```bash
   sqlite3 var/system_dashboard.db "UPDATE lan_settings SET setting_value = 'true' WHERE setting_key = 'syslog_correlation_enabled';"
   ```

2. Manually trigger correlation:

   ```powershell
   Import-Module .\tools\LanObservability.psm1
   Invoke-SyslogDeviceCorrelation
   ```

3. Check correlation table:

   ```bash
   sqlite3 var/system_dashboard.db "SELECT COUNT(*) FROM syslog_device_links;"
   ```

## Environment Issues

### Python Virtual Environment

**Symptoms:**

- "python not found" or module import errors
- Flask won't start

**Solutions:**

1. Recreate virtual environment:

   ```powershell
   Remove-Item .\.venv -Recurse -Force
   python -m venv .venv
   .\.venv\Scripts\Activate.ps1
   pip install -r requirements.txt
   ```

2. Verify Python version:

   ```powershell
   python --version  # Should be 3.10+
   ```

### PowerShell Module Issues

**Symptoms:**

- "Module not found" errors
- Function not recognized

**Solutions:**

1. Check module installation:

   ```powershell
   Get-Module -ListAvailable SystemDashboard
   ```

2. Reinstall modules:

   ```powershell
   .\scripts\Install.ps1
   ```

3. Import manually:

   ```powershell
   Import-Module .\tools\SystemDashboard.Telemetry.psm1 -Force
   ```

## Performance Issues

### High CPU Usage

**Possible causes:**

- Polling interval too short
- Too many syslog messages
- Inefficient queries

**Solutions:**

1. Increase polling interval in `config.json`
2. Add indexes to frequently queried columns
3. Enable query logging to find slow queries
4. Implement retention policies

### Disk Space Issues

**Solutions:**

1. Check disk usage:

   ```powershell
   Get-PSDrive C | Select-Object Used,Free
   ```

2. Clean old logs:

   ```powershell
   Remove-Item ".\var\log\*.log.old" -Force
   ```

3. Drop old partitions:

   ```sql
   DROP TABLE IF EXISTS telemetry.syslog_generic_2310;  -- October 2023
   ```

4. Implement retention policy for snapshots

## Getting Help

If issues persist:

1. Check service logs in `var/log/`
2. Review Windows Event Logs
3. Enable debug logging in `config.json`
4. Run validation script: `python validate-environment.py`
5. Create an issue on GitHub with:
   - Error messages from logs
   - Service status output
   - Configuration (redact passwords)
   - Steps to reproduce

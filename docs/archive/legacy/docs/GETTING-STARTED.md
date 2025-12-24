# Getting Started with SystemDashboard

Welcome to SystemDashboard! This guide will help you get up and running quickly with your new Windows operations telemetry stack.

## What is SystemDashboard?

SystemDashboard is a comprehensive monitoring solution for Windows environments that collects, analyzes, and visualizes:

- **Windows Event Logs** - Critical system events, errors, and warnings
- **IIS Logs** - Web server access patterns and errors
- **Router Logs** - Network activity and security events from your ASUS router
- **LAN Devices** - Real-time tracking of devices on your network
- **System Metrics** - Performance data and health indicators

All data is stored locally in SQLite and presented through an intuitive web dashboard.

## Quick Start (5 Minutes)

### Prerequisites

Before you begin, ensure you have:

- **Windows 11** (or Windows 10 with PowerShell 7+)
- **PowerShell 7+** - [Download here](https://github.com/PowerShell/PowerShell/releases)
- **Python 3.10+** - [Download here](https://www.python.org/downloads/)
- **Git** - [Download here](https://git-scm.com/downloads)

### Installation Steps

1. **Clone the repository**

   ```powershell
   git clone https://github.com/xfaith4/SystemDashboard.git
   cd SystemDashboard
   ```

2. **Run the unified installer**

   ```powershell
   pwsh .\scripts\Launch.ps1
   ```

   This single command will:
   - Set up environment variables
   - Initialize the SQLite database
   - Install PowerShell modules
   - Create scheduled tasks for automatic startup
   - Apply LAN observability schema

3. **Start the services**

   ```powershell
   # Start telemetry collection
   Start-Service SystemDashboardTelemetry
   
   # Start the web dashboard
   Start-ScheduledTask -TaskName "SystemDashboard-WebUI"
   ```

4. **Open the dashboard**

   Navigate to: **http://localhost:5000**

   You should see the main dashboard with placeholder data until collection begins.

## First-Time Setup

### Configure Router Monitoring (Optional)

To collect logs from your ASUS router:

1. **Set your router password**

   ```powershell
   $env:ASUS_ROUTER_PASSWORD = "your_router_password"
   .\scripts\setup-environment.ps1  # Makes it permanent
   ```

2. **Update router endpoint** in `config.json`:

   ```json
   "Service": {
     "Asus": {
       "Enabled": true,
       "Uri": "http://192.168.1.1/syslog.txt",
       "HostName": "RT-AX88U",
       "PollIntervalSeconds": 300
     }
   }
   ```

3. **Configure your router** to send syslog to your Windows machine:
   - Router admin → System Log → Log Server
   - Set IP to your Windows machine's IP
   - Set port to 514 (UDP)

### Enable AI-Powered Insights (Optional)

For intelligent explanations of events and anomalies:

```powershell
$env:OPENAI_API_KEY = "sk-..."
.\scripts\setup-environment.ps1  # Makes it permanent
```

## Understanding the Dashboard

### Main Dashboard (http://localhost:5000)

The main page shows:

- **System Health** - Overall status indicators
- **Recent Alerts** - Critical events requiring attention
- **Event Trends** - Graphs showing event patterns over time
- **Quick Stats** - Event counts by type and severity

### Events Page (http://localhost:5000/events)

View and filter Windows Event Log entries:

- Filter by severity (Critical, Error, Warning, Information)
- Search by source, message, or event ID
- View detailed event properties
- Export to CSV for analysis

### Router Logs (http://localhost:5000/router)

Monitor network activity:

- Syslog messages from your router
- Security events (failed connections, blocks)
- WAN events (connection drops, IP changes)
- WiFi events (client connections, disconnections)

### LAN Observability (http://localhost:5000/lan)

Track devices on your network:

- **Device Inventory** - All devices that have ever connected
- **Online/Offline Status** - Real-time presence tracking
- **Signal Strength** - WiFi RSSI for wireless devices
- **Network Interface** - Wired vs wireless, 2.4GHz vs 5GHz
- **Device Nicknames** - Add friendly names for easy identification

## Common Tasks

### View Real-Time Logs

```powershell
# Telemetry service logs
Get-Content .\var\log\telemetry-service.log -Tail 20 -Wait

# Web UI logs
Get-Content .\var\log\webui-service.log -Tail 20 -Wait

# LAN collector logs
Get-Content .\var\log\lan-collector.log -Tail 20 -Wait
```

### Check Service Status

```powershell
# Windows service
Get-Service SystemDashboardTelemetry

# Scheduled tasks
Get-ScheduledTask -TaskName "SystemDashboard-*"
```

### Generate Test Data

To verify everything is working:

```powershell
# Generate sample events
.\scripts\test-data-collection.ps1

# Refresh the dashboard - you should see new entries
```

### Query the Database Directly

```powershell
# Using Python
python -c "import sqlite3; conn=sqlite3.connect('var/system_dashboard.db'); print(conn.execute('SELECT COUNT(*) FROM syslog_messages').fetchone()[0])"

# Using sqlite3 CLI (if installed)
sqlite3 var/system_dashboard.db "SELECT COUNT(*) FROM devices;"
```

### Export Data

All tables support CSV export:

1. Navigate to any data table in the dashboard
2. Click the **Export CSV** button
3. File downloads automatically with timestamped name

## Keyboard Shortcuts

The dashboard supports keyboard navigation:

- **`?`** - Show keyboard shortcuts help
- **`h`** - Go to Home
- **`e`** - Go to Events
- **`l`** - Go to LAN Observability
- **`r`** - Go to Router Logs
- **`w`** - Go to Windows Events
- **`Ctrl+R`** - Refresh current page

## Troubleshooting

### Dashboard Shows No Data

**Problem**: Dashboard loads but shows "No data available" or zeros everywhere.

**Solutions**:

1. Verify database is initialized:
   ```powershell
   python scripts/init_db.py --verify
   ```

2. Check services are running:
   ```powershell
   Get-Service SystemDashboardTelemetry
   Get-ScheduledTask -TaskName "SystemDashboard-*"
   ```

3. Generate test data:
   ```powershell
   .\scripts\test-data-collection.ps1
   ```

### Service Won't Start

**Problem**: `Start-Service SystemDashboardTelemetry` fails with an error.

**Solutions**:

1. Check error details:
   ```powershell
   Get-EventLog -LogName System -Source "Service Control Manager" -Newest 5
   ```

2. Verify logs directory exists:
   ```powershell
   Test-Path .\var\log
   ```

3. Reinstall the service:
   ```powershell
   .\scripts\Install.ps1
   ```

### Dashboard Shows "Database Error"

**Problem**: Web UI displays database connection errors.

**Solutions**:

1. Verify database file exists:
   ```powershell
   Test-Path .\var\system_dashboard.db
   ```

2. Check file permissions (should be writable):
   ```powershell
   Get-Acl .\var\system_dashboard.db | Format-List
   ```

3. Recreate database if corrupted:
   ```powershell
   python scripts/init_db.py --force  # WARNING: Deletes all data
   ```

### Router Logs Not Appearing

**Problem**: Router page shows no syslog messages.

**Solutions**:

1. Verify router configuration:
   - Check `config.json` has correct router IP
   - Ensure `Service.Asus.Enabled` is `true`

2. Test router connectivity:
   ```powershell
   Test-NetConnection -ComputerName 192.168.1.1 -Port 80
   ```

3. Check syslog listener is running:
   ```powershell
   Get-ScheduledTask -TaskName "SystemDashboard-SyslogCollector"
   ```

4. Review telemetry logs for errors:
   ```powershell
   Select-String "error" -Path .\var\log\telemetry-service.log -Context 2
   ```

### Port 5000 Already in Use

**Problem**: Flask app fails to start because port 5000 is occupied.

**Solutions**:

1. Find what's using port 5000:
   ```powershell
   Get-NetTCPConnection -LocalPort 5000 | Format-Table -AutoSize
   ```

2. Stop the conflicting process or change the port:
   ```powershell
   # Edit app\app.py, change the last line:
   # app.run(host='0.0.0.0', port=5001, debug=True)
   ```

### High Memory Usage

**Problem**: Services consuming excessive memory (>500MB).

**Solutions**:

1. Check database size:
   ```powershell
   (Get-Item .\var\system_dashboard.db).Length / 1MB
   ```

2. Apply data retention (cleanup old data):
   ```powershell
   python -c "from app.data_retention import get_retention_manager; get_retention_manager().run_cleanup()"
   ```

3. Vacuum database to reclaim space:
   ```powershell
   sqlite3 var/system_dashboard.db "VACUUM;"
   ```

## Next Steps

Now that you have SystemDashboard running:

1. **Customize Alerts** - Review alert thresholds in the dashboard settings
2. **Add Device Nicknames** - Visit LAN page to label your devices
3. **Set Up Monitoring** - Configure email or webhook notifications (see [MONITORING.md](MONITORING.md))
4. **Explore Advanced Features** - Check out [ADVANCED-FEATURES.md](ADVANCED-FEATURES.md)
5. **Secure Your Installation** - Review [SECURITY-SETUP.md](SECURITY-SETUP.md)

## Learning Resources

- **[Dashboard Tour](DASHBOARD-TOUR.md)** - Guided tour with screenshots
- **[Help Guide](HELP.md)** - Comprehensive user manual
- **[FAQ](FAQ.md)** - Frequently asked questions
- **[Troubleshooting](TROUBLESHOOTING.md)** - Detailed troubleshooting guide
- **[LAN Observability](LAN-OBSERVABILITY-README.md)** - Network monitoring deep-dive

## Getting Help

- **Check Logs**: Most issues are explained in log files under `var/log/`
- **Health Check**: Visit http://localhost:5000/health/detailed for system status
- **Documentation**: See the `docs/` directory for detailed guides
- **Issues**: Report bugs at https://github.com/xfaith4/SystemDashboard/issues

## Quick Reference Card

### Essential Commands

| Task | Command |
|------|---------|
| Start telemetry | `Start-Service SystemDashboardTelemetry` |
| Start web UI | `Start-ScheduledTask -TaskName "SystemDashboard-WebUI"` |
| View logs | `Get-Content .\var\log\telemetry-service.log -Tail 20` |
| Check status | `Get-Service SystemDashboardTelemetry` |
| Verify database | `python scripts/init_db.py --verify` |
| Open dashboard | Browse to http://localhost:5000 |

### Essential URLs

- Main Dashboard: http://localhost:5000
- Events: http://localhost:5000/events
- Router Logs: http://localhost:5000/router
- LAN Devices: http://localhost:5000/lan
- Health Check: http://localhost:5000/health/detailed

### Important Locations

- Database: `var/system_dashboard.db`
- Logs: `var/log/*.log`
- Config: `config.json`
- Router state: `var/asus/state.json`

---

**Congratulations!** You now have SystemDashboard monitoring your Windows environment. The system will automatically collect data and provide insights into your infrastructure health.

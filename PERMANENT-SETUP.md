# 🚀 System Dashboard - Permanent Installation Guide

## ✅ **Installation Complete!**

Your System Dashboard is now configured to run permanently on your machine with the following components:

### 📊 **Running Services**

1. **PostgreSQL Database**
   - Running in Docker container `postgres-container`
   - Auto-restarts with Docker daemon
   - Accessible on `localhost:5432`

2. **Telemetry Collection Service**
   - Scheduled Task: `SystemDashboard-Telemetry`
   - Collects Windows events, system metrics, logs
   - Automatically restarts if it fails

3. **Flask Web Dashboard**
   - Scheduled Task: `SystemDashboard-WebUI`
   - Web interface at: **http://localhost:5000**
   - Automatically restarts if it fails

---

## 🔧 **Management Commands**

### Quick Start/Stop
```powershell
# Start all services manually
.\start-dashboard.bat

# Check status of all services
.\setup-permanent-services.ps1 -Status

# Restart a specific service
Stop-ScheduledTask -TaskName "SystemDashboard-WebUI"
Start-ScheduledTask -TaskName "SystemDashboard-WebUI"
```

### Service Management
```powershell
# Uninstall all scheduled tasks
.\setup-permanent-services.ps1 -Uninstall

# Reinstall all scheduled tasks
.\setup-permanent-services.ps1 -Install
```

### Database Management
```powershell
# Start PostgreSQL container
docker start postgres-container

# Stop PostgreSQL container
docker stop postgres-container

# View database logs
docker logs postgres-container
```

---

## 🌐 **Accessing the Dashboard**

**Main URL**: http://localhost:5000

### Available Pages:
- **Dashboard** (`/`) - System overview with KPIs and alerts
- **Events** (`/events`) - Windows Event Log viewer with filtering
- **Router** (`/router`) - Network and router logs
- **WiFi** (`/wifi`) - Connected devices and network clients

### API Endpoints:
- **Health Check**: http://localhost:5000/health
- **Events API**: http://localhost:5000/api/events?level=Error&max=10

---

## 🔄 **Auto-Start Behavior**

### On Windows Boot:
1. **Docker** starts PostgreSQL container automatically
2. **Task Scheduler** starts both services:
   - `SystemDashboard-Telemetry` (data collection)
   - `SystemDashboard-WebUI` (web interface)

### Service Recovery:
- Both services are configured to **automatically restart** if they crash
- **Maximum restart attempts**: 3 times per hour
- **Restart interval**: 1 minute between attempts

---

## 📂 **Important Locations**

```
G:\Development\10_Active\SystemDashboard\
├── services\                           # Service scripts
│   ├── SystemDashboardService.ps1      # Telemetry service
│   └── SystemDashboard-WebUI.ps1       # Web UI service
├── app\                                # Flask web application
│   ├── app.py                          # Main Flask app
│   └── venv\                           # Python virtual environment
├── var\log\                            # Log files
│   ├── webui-service.log               # Web UI service logs
│   └── telemetry-service.log           # Telemetry service logs
├── setup-permanent-services.ps1        # Service installer
└── start-dashboard.bat                 # Quick start script
```

---

## 🛠️ **Troubleshooting**

### If Dashboard Won't Load:
1. Check service status: `.\setup-permanent-services.ps1 -Status`
2. Check web UI logs: `Get-Content ".\var\log\webui-service.log" -Tail 20`
3. Restart web UI service: `Restart-ScheduledTask -TaskName "SystemDashboard-WebUI"`

### If No Data Appears:
1. Check telemetry service: `Get-ScheduledTask -TaskName "SystemDashboard-Telemetry"`
2. Check database connection: `docker exec postgres-container psql -U sysdash_reader -d system_dashboard -c "SELECT NOW();"`
3. Generate test event: `Write-EventLog -LogName Application -Source "Application Error" -EventId 1001 -EntryType Warning -Message "Test event"`

### If Services Won't Start:
1. Run as Administrator: `Start-Process pwsh -Verb RunAs`
2. Reinstall services: `.\setup-permanent-services.ps1 -Install`
3. Check Windows Event Logs for Task Scheduler errors

---

## 🎯 **Next Steps**

1. **Bookmark the dashboard**: http://localhost:5000
2. **Monitor the system**: Check dashboard daily for alerts
3. **Customize alerts**: Edit thresholds in `config.json`
4. **Add more data sources**: Extend telemetry collection as needed

---

## 🔒 **Security Notes**

- Dashboard runs on `localhost` only (not accessible from network)
- Database uses dedicated read-only user for dashboard
- Services run as SYSTEM account with minimal permissions
- No external internet access required for operation

Your System Dashboard is now **fully operational** and will automatically start with Windows! 🎉

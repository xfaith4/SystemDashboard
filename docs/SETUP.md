# System Dashboard - Setup Guide

This guide covers installation, configuration, and permanent setup of the System Dashboard.

## Prerequisites

- PowerShell 7+
- Python 3.10+
- Git

## Quick Installation

### 1. Clone and Configure

```powershell
git clone https://github.com/xfaith4/SystemDashboard.git
cd SystemDashboard
```

### 2. Set Up Environment Variables (Optional)

```powershell
# Router credentials (optional - for ASUS router monitoring)
$env:ASUS_ROUTER_PASSWORD = "your_router_password"

# OpenAI API key (optional - for AI-powered explanations)
$env:OPENAI_API_KEY = "your_api_key"

# Make permanent
.\setup-environment.ps1
```

### 3. Set Up Database

The System Dashboard uses SQLite for simple, file-based storage. Initialize the database:

```powershell
python scripts/init_db.py
```

This creates:
- Database file: `var/system_dashboard.db`
- All required tables for telemetry, LAN observability, and AI feedback
- Views for efficient querying

### 4. Install the Service

```powershell
.\Install.ps1
```

This will:
- Copy PowerShell modules to the system modules directory
- Create Python virtual environment
- Set up runtime directories under `var/`
- Register the telemetry service

### 5. Start Services

**For Development:**
```powershell
# Start telemetry collection
Start-Service SystemDashboardTelemetry

# Start web UI
.\.venv\Scripts\Activate.ps1
python .\app\app.py
```

**For Permanent Installation:**
```powershell
.\setup-permanent-services.ps1
```

This creates scheduled tasks that run on startup:
- `SystemDashboard-Telemetry` - Data collection service
- `SystemDashboard-WebUI` - Flask web dashboard

## Configuration

Edit `config.json` to customize:

- **Database**: Connection settings, credentials
- **Syslog Listener**: Bind address and port (default: UDP 514)
- **ASUS Router**: Polling interval, credentials, endpoint
- **Service**: Log paths, staging directories

## Accessing the Dashboard

Once running, access the web interface at:
- **Main Dashboard**: http://localhost:5000
- **Events**: http://localhost:5000/events
- **Router Logs**: http://localhost:5000/router
- **LAN Observability**: http://localhost:5000/lan

## Management Commands

### Service Management
```powershell
# Check status
Get-ScheduledTask -TaskName "SystemDashboard-*"

# Start/Stop
Start-ScheduledTask -TaskName "SystemDashboard-Telemetry"
Stop-ScheduledTask -TaskName "SystemDashboard-WebUI"

# View logs
Get-Content ".\var\log\telemetry-service.log" -Tail 20 -Wait
Get-Content ".\var\log\webui-service.log" -Tail 20
```

### Database Management
```powershell
# Verify database exists and has correct schema
python scripts/init_db.py --verify

# Recreate database (WARNING: deletes all data)
python scripts/init_db.py --force

# Connect with SQLite (direct query)
sqlite3 var/system_dashboard.db ".tables"
sqlite3 var/system_dashboard.db "SELECT COUNT(*) FROM syslog_messages;"
```

## Troubleshooting

### Service Won't Start
1. Check logs in `var/log/` directory
2. Verify database file exists at `var/system_dashboard.db`
3. Ensure environment variables are set
4. Run `python scripts/init_db.py --verify` to check database

### No Data Appearing
1. Verify database is initialized: `python scripts/init_db.py --verify`
2. Check service is running and collecting data
3. Confirm syslog sources are sending data
4. Generate test data: `.\test-data-collection.ps1`

### Dashboard Shows Errors
1. Verify Flask app can access the database file
2. Check database path in `config.json`
3. Test connection: http://localhost:5000/health
4. Check browser console for JavaScript errors

### Router Logs Not Collected
1. Verify `ASUS_ROUTER_PASSWORD` environment variable
2. Check router endpoint in `config.json`
3. Test router connectivity
4. Review `var/log/telemetry-service.log` for errors

## Security Notes

- Dashboard runs on `localhost` by default (not exposed to network)
- SQLite database file stored locally
- Credentials stored in environment variables only
- Services run as SYSTEM account
- No external internet access required (except optional OpenAI API)

## Next Steps

After installation:
1. Monitor the dashboard for data collection
2. Configure router to send syslog to this machine
3. Set up LAN observability if needed (see [LAN-OBSERVABILITY-README.md](LAN-OBSERVABILITY-README.md))
4. Customize alert thresholds in the Flask app

For advanced features, see [ADVANCED-FEATURES.md](ADVANCED-FEATURES.md).

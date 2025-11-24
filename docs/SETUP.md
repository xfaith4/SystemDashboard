# System Dashboard - Setup Guide

This guide covers installation, configuration, and permanent setup of the System Dashboard.

## Prerequisites

- PowerShell 7+
- PostgreSQL 15/16 (or Docker for PostgreSQL)
- Python 3.10+
- Git

## Quick Installation

### 1. Clone and Configure

```powershell
git clone https://github.com/xfaith4/SystemDashboard.git
cd SystemDashboard
```

### 2. Set Up Environment Variables

```powershell
# Database credentials
$env:SYSTEMDASHBOARD_DB_PASSWORD = "your_ingest_password"
$env:SYSTEMDASHBOARD_DB_READER_PASSWORD = "your_reader_password"

# Router credentials (optional)
$env:ASUS_ROUTER_PASSWORD = "your_router_password"

# Make permanent
.\setup-environment.ps1
```

### 3. Set Up Database

**Option A: Docker (Recommended)**
```powershell
.\setup-database-docker.ps1
```

**Option B: Local PostgreSQL**
```powershell
.\setup-database.ps1
```

This creates:
- Database: `system_dashboard`
- Schema: `telemetry` with partitioned tables
- Users: `sysdash_ingest` (write), `sysdash_reader` (read-only)
- Required functions and views

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
# Docker PostgreSQL
docker start postgres-container
docker stop postgres-container
docker logs postgres-container

# Connect to database
docker exec -it postgres-container psql -U sysdash_reader -d system_dashboard

# Create monthly partition
psql -h localhost -U sysdash_ingest -d system_dashboard -c "SELECT telemetry.ensure_syslog_partition(CURRENT_DATE);"
```

## Troubleshooting

### Service Won't Start
1. Check logs in `var/log/` directory
2. Verify PostgreSQL is running and accessible
3. Ensure environment variables are set
4. Check that `psql` is in PATH

### No Data Appearing
1. Verify current month's partition exists
2. Check service has INSERT permissions
3. Confirm syslog sources are sending data
4. Generate test data: `.\test-data-collection.ps1`

### Dashboard Shows Errors
1. Verify Flask app environment variables are set
2. Check database reader permissions
3. Test connection: http://localhost:5000/health
4. Check browser console for JavaScript errors

### Router Logs Not Collected
1. Verify `ASUS_ROUTER_PASSWORD` environment variable
2. Check router endpoint in `config.json`
3. Test router connectivity
4. Review `var/log/telemetry-service.log` for errors

## Security Notes

- Dashboard runs on `localhost` by default (not exposed to network)
- Uses separate database users with least privilege
- Credentials stored in environment variables only
- Services run as SYSTEM account
- No external internet access required

## Next Steps

After installation:
1. Monitor the dashboard for data collection
2. Configure router to send syslog to this machine
3. Set up LAN observability if needed (see [LAN-OBSERVABILITY-README.md](LAN-OBSERVABILITY-README.md))
4. Customize alert thresholds in the Flask app
5. Set up scheduled partition creation (monthly)

For advanced features, see [ADVANCED-FEATURES.md](ADVANCED-FEATURES.md).

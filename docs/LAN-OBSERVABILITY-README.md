# LAN Observability

This document describes the LAN Observability feature added to the SystemDashboard project.

## Overview

The LAN Observability layer provides comprehensive network device monitoring and tracking for your home/office network. It collects data from your ASUS router over SSH and maintains:

- **Device Inventory**: Stable list of all devices ever seen on your network
- **Time-Series Metrics**: Historical data on signal strength (RSSI), transfer rates, and online/offline status
- **Syslog Correlation**: Links network events from router logs to specific devices
- **Web Dashboard**: Real-time visibility into network health and device behavior

## Architecture

### Data Model

The system uses PostgreSQL with the following main tables:

1. **`telemetry.devices`** - Stable device inventory
   - One row per unique device (identified by MAC address)
   - Tracks hostname, IP, vendor, first/last seen timestamps
   - Boolean `is_active` flag for current status

2. **`telemetry.device_snapshots_template`** - Time-series data (partitioned by month)
   - Periodic snapshots of device state
   - Records IP, interface type, RSSI, TX/RX rates, online status
   - Configurable retention (default: 7 days)

3. **`telemetry.syslog_device_links`** - Correlation table
   - Links syslog events to devices based on MAC/IP matching
   - Stores confidence scores and match types

4. **`telemetry.lan_settings`** - Configuration
   - Runtime settings like retention periods and thresholds

### Components

#### PowerShell Module: `tools/LanObservability.psm1`

Core collection logic:

- `Invoke-RouterClientPoll`: Fetches current client list from router
- `Upsert-LanDevice`: Creates or updates device records
- `Add-DeviceSnapshot`: Records time-series data points
- `Update-DeviceActivityStatus`: Marks devices as active/inactive
- `Invoke-SyslogDeviceCorrelation`: Links syslog messages to devices
- `Invoke-DeviceSnapshotRetention`: Cleans up old data

#### Collector Service: `services/LanCollectorService.ps1`

Runs continuously (or on a schedule) to:

- Poll router every N minutes (configurable, default: 300s / 5 min)
- Update device inventory and record snapshots
- Correlate new syslog events
- Perform daily retention cleanup

#### Flask API: `app/app.py`

RESTful endpoints for UI:

- `GET /api/lan/stats` - Summary statistics
- `GET /api/lan/devices` - Device list with filtering
- `GET /api/lan/devices/online` - Currently online devices
- `GET /api/lan/device/<id>` - Device details
- `GET /api/lan/device/<id>/timeline` - Time-series data
- `GET /api/lan/device/<id>/events` - Associated syslog events

#### Web UI: `app/templates/lan_*.html`

Three main pages:

1. **LAN Overview** (`/lan`) - Dashboard with stats, online devices, and issues
2. **Devices List** (`/lan/devices`) - Searchable/filterable table of all devices
3. **Device Detail** (`/lan/device/<id>`) - Charts and event history for one device

## Installation

### Prerequisites

- PostgreSQL database (already configured for SystemDashboard)
- PowerShell 7+
- Npgsql assembly (for direct database connection in LanCollectorService)
  - Place `Npgsql.dll` in a `lib/` directory, or
  - Install via NuGet: `Install-Package Npgsql`
- ASUS router with SSH access (requires Posh-SSH module: `Install-Module Posh-SSH`)

### Step 1: Apply Database Schema

Run the schema migration script:

```powershell
.\scripts\apply-lan-schema.ps1
```

This creates all necessary tables, functions, and views. It's safe to run multiple times (idempotent).

To force reapplication:

```powershell
.\scripts\apply-lan-schema.ps1 -Force
```

### Step 2: Configure Router Access

Edit `config.json` and ensure the ASUS router settings are correct:

```json
{
  "RouterIP": "192.168.50.1",
  "Service": {
    "Asus": {
      "Enabled": true,
      "RemoteLogPath": "/tmp/syslog.log",
      "HostName": "asus-router",
      "Username": "admin",
      "PasswordSecret": "env:ASUS_ROUTER_PASSWORD",
      "PollIntervalSeconds": 300,
      "SSH": {
        "Enabled": true,
        "Host": "192.168.50.1",
        "Username": "admin",
        "PasswordSecret": "env:ASUS_ROUTER_PASSWORD",
        "Port": 22
      }
    }
  }
}
```

Set your router password as an environment variable:

```powershell
$env:ASUS_ROUTER_PASSWORD = "your_router_password"
```

SSH access is required for log collection and WiFi scanning:

1. Enable SSH on your router (Administration → System → SSH Daemon = Yes)
2. Install Posh-SSH module:

   ```powershell
   Install-Module -Name Posh-SSH -Scope CurrentUser
   ```

### Step 3: Start the Collector Service

Run the collector service:

```powershell
.\services\LanCollectorService.ps1
```

Or run it in the background:

```powershell
Start-Job -ScriptBlock { & ".\services\LanCollectorService.ps1" }
```

For production, consider setting up a Windows scheduled task or service wrapper.

### Step 4: Access the Web UI

Start the Flask dashboard (if not already running):

```powershell
.\services\SystemDashboard-WebUI.ps1 -Action start
```

Navigate to:

- **LAN Overview**: <http://localhost:5000/lan>
- **Devices List**: <http://localhost:5000/lan/devices>

## Configuration

### Settings in Database

The `telemetry.lan_settings` table stores runtime configuration:

| Setting Key | Default | Description |
|-------------|---------|-------------|
| `snapshot_retention_days` | 7 | Days to keep device snapshot history |
| `inactive_threshold_minutes` | 10 | Minutes without snapshot before marking device offline |
| `poll_interval_seconds` | 300 | Seconds between router polls |
| `syslog_correlation_enabled` | true | Enable automatic syslog correlation |

To change settings, update the database:

```sql
UPDATE telemetry.lan_settings
SET setting_value = '14'
WHERE setting_key = 'snapshot_retention_days';
```

### Router Polling Method

All router data is gathered over SSH (Posh-SSH) using router CLI commands; HTTP scraping is no longer used. If polling fails, check:

- Router credentials
- Network connectivity
- Router firmware SSH settings

## Usage

### Monitoring Online Devices

The **LAN Overview** page shows:

- Total device counts (active/inactive, by interface type)
- Currently online devices with signal strength
- Potential issues (weak signal, flapping connections)

### Viewing Device History

1. Navigate to **Devices List** (`/lan/devices`)
2. Filter by status (active/inactive) or interface type
3. Click **View** on any device to see:
   - Device metadata
   - RSSI chart over time
   - TX/RX rate charts
   - Associated syslog events

### Identifying Issues

The system highlights:

- Devices with weak signal (RSSI < -70 dBm)
- Devices going offline frequently (check syslog events)
- Unexpected devices (check first seen timestamp)

## Troubleshooting

### No Devices Appearing

1. Check collector service logs: `var/log/lan-collector.log`
2. Verify router credentials
3. Test router connection:

   ```powershell
   .\scripts\asus-wifi-monitor.ps1 -TestConnection
   ```

4. Check database connectivity

### "Loading..." Never Completes in UI

1. Check Flask app is running
2. Open browser console for errors
3. Test API endpoint directly: <http://localhost:5000/api/lan/stats>

### Syslog Events Not Correlating

1. Verify syslog ingestion is working (check `telemetry.syslog_generic_template`)
2. Check correlation setting:

   ```sql
   SELECT * FROM telemetry.lan_settings WHERE setting_key = 'syslog_correlation_enabled';
   ```

3. Manually run correlation:

   ```powershell
   Import-Module .\tools\LanObservability.psm1
   # Run correlation function with database connection
   ```

### Database Partitioning Issues

If snapshots aren't being recorded, check partitions:

```sql
SELECT tablename FROM pg_tables
WHERE schemaname = 'telemetry' AND tablename LIKE 'device_snapshots_%';
```

Create partition for current month manually if needed:

```sql
SELECT telemetry.ensure_device_snapshot_partition(CURRENT_DATE);
```

## Performance Considerations

- **Snapshot Retention**: Longer retention = more storage. Default 7 days is reasonable for most uses.
- **Polling Interval**: More frequent polling = better granularity but more load. 5 minutes is a good balance.
- **Database Size**: With 20 devices and 5-minute polling, expect ~5,700 snapshots/day, ~40k/week.
  - At ~200 bytes/row, this is about 8 MB/week.
- **Partitioning**: Monthly partitions keep queries fast. Old partitions can be dropped to reclaim space.

## Future Enhancements

Possible improvements for future iterations:

1. **Device Tagging**: Categorize devices (IoT, guest, critical) via UI
2. **Alerting**: Notifications for new devices, offline devices, weak signals
3. **Bandwidth Tracking**: Per-device traffic statistics (requires router support)
4. **Guest Network Isolation**: Separate tracking for guest vs. main network
5. **MAC Vendor Lookup**: Auto-populate vendor from MAC address OUI database
6. **Offline Event Detection**: Specific detection of connect/disconnect events
7. **Integration with Network Mapper**: Cross-reference with active scanning tools

## Credits

Implemented based on requirements in `LAN_Observability_SystemMonitor_Prompt.md`.

Built on top of the existing SystemDashboard infrastructure:

- PostgreSQL telemetry database
- PowerShell 7 modules
- Flask web framework
- Chart.js for visualizations

# Data Source Configuration Guide

This document explains how to configure the System Dashboard to pull real data from various sources.

## Overview

The System Dashboard supports three main data sources:

1. **Windows Event Logs** - Real system events from Windows Event Log
2. **Router Logs** - Log files from network routers/firewalls
3. **System Information** - Real-time system metrics (CPU, memory, disk, network)

## Configuration

### 1. Windows Event Logs

The PowerShell module automatically accesses Windows Event Logs when running on Windows systems.

**Configuration:**

- No additional configuration required on Windows
- Logs are pulled from `Application` and `System` event logs by default
- Access requires appropriate permissions (usually user-level access is sufficient)

**Customization:**
```powershell
# Get logs from specific event logs with filtering
Get-SystemLogs -LogName 'Application','System','Security' -MaxEvents 50 -MinimumLevel 'Error'
```

**Flask App Configuration:**
The Flask app uses PowerShell to retrieve Windows events:

- Automatically detects Windows environment
- Falls back to empty list on non-Windows systems
- Supports filtering by event level (Error, Warning, Information)

### 2. Router Logs

Router logs are read from a file specified by the `ROUTER_LOG_PATH` environment variable.

**Setup:**

1. Configure your router to write logs to a file accessible by the dashboard
2. Set the environment variable:
   ```bash
   export ROUTER_LOG_PATH="/path/to/router/logs.txt"
   ```
   Or on Windows:
   ```cmd
   set ROUTER_LOG_PATH=C:\logs\router.log
   ```

**Log Format:**
The dashboard expects logs in this format:
```
YYYY-MM-DD HH:MM:SS LEVEL MESSAGE
```

Example:
```
2024-01-15 08:30:15 INFO DHCP assigned IP 192.168.1.100 to MAC 00:11:22:33:44:55
2024-01-15 08:30:45 WARN Failed login attempt from 192.168.1.50
2024-01-15 08:31:30 ERROR WAN connection lost - attempting reconnection
```

**Sample Configuration:**
Use the provided `sample-router.log` file for testing:
```bash
export ROUTER_LOG_PATH="./sample-router.log"
```

### 3. System Information

System metrics are collected automatically using native OS tools.

**Windows Metrics:**

- **CPU Usage**: Performance counters via `Get-Counter`
- **Memory Usage**: WMI via `Get-CimInstance Win32_ComputerSystem`
- **Disk Usage**: WMI via `Get-CimInstance Win32_LogicalDisk`
- **Network Info**: PowerShell cmdlets `Get-NetAdapter`
- **Process Info**: `Get-Process` cmdlet

**Network Client Discovery:**

- Uses `Get-NetNeighbor` to find connected devices
- Performs DNS lookups for hostnames
- Returns IP, MAC address, and connection state

**Linux/Unix Metrics:**

- Limited support for cross-platform operation
- Uses standard tools like `ps`, `df`, `free` where available

## Environment Variables

| Variable | Purpose | Default | Example |
|----------|---------|---------|---------|
| `ROUTER_LOG_PATH` | Path to router log file | None | `/var/log/router.log` |
| `CHATTY_THRESHOLD` | Threshold for "chatty" network clients | 500 | `1000` |
| `SYSTEMDASHBOARD_BACKEND` | Backend URL for Flask health checks | `http://localhost:15000/metrics` | `http://server:15000/metrics` |
| `DASHBOARD_PORT` | Flask app port | Automatically assigned from the next open port (see `var/webui-port.txt`) | `8080` |
| `OPENAI_API_KEY` | OpenAI API key for AI suggestions | None | `sk-...` |

## Testing Data Sources

### Test Router Logs
```bash
# Set up sample router log
export ROUTER_LOG_PATH="./sample-router.log"

# Test with Python
cd app
python -c "from app import get_router_logs; print(len(get_router_logs()))"

# Test with Flask
python app.py
# Visit http://localhost:<port>/router (check `var/webui-port.txt` for the current port)
```

### Test Windows Events (Windows only)
```powershell
# Test PowerShell function
Import-Module ./Start-SystemDashboard.psm1
Get-SystemLogs -LogName 'Application' -MaxEvents 5

# Test Flask endpoint
python app/app.py
# Visit http://localhost:<port>/events (check `var/webui-port.txt` for the current port)
```

### Test System Metrics
```powershell
# Start PowerShell listener
./Start-SystemDashboard.ps1

# Test metrics endpoint
Invoke-RestMethod http://localhost:15000/metrics
```

## Validation Tests

The repository includes comprehensive tests that validate real data collection:

```bash
# Run Python tests
python -m pytest tests/test_flask_app.py -v
python tests/test_router_logs.py

# Run PowerShell tests (Windows)
pwsh -Command "Invoke-Pester tests/ -Verbose"
```

## Troubleshooting

### Router Logs Not Appearing

1. Verify `ROUTER_LOG_PATH` environment variable is set
2. Check file exists and is readable
3. Verify log format matches expected pattern
4. Check file encoding (should be UTF-8 compatible)

### Windows Events Not Loading

1. Ensure running on Windows system
2. Check user has permission to read Event Logs
3. Verify PowerShell execution policy allows script execution
4. Check for PowerShell errors in console

### System Metrics Showing Zeros

1. Verify appropriate permissions for system access
2. Check if performance counters are enabled
3. Ensure WMI service is running (Windows)
4. Check for antivirus interference

### Network Discovery Issues

1. Verify network adapter is up and configured
2. Check ARP table has entries: `arp -a`
3. Ensure DNS resolution is working
4. Verify PowerShell network cmdlets are available

## Performance Considerations

- **Event Logs**: Limit `MaxEvents` to reasonable numbers (50-100)
- **Router Logs**: Use `max_lines` parameter to limit file reading
- **System Metrics**: Collection happens on-demand, cached for HTTP responses
- **Network Discovery**: Can be slow with many clients, consider filtering by network prefix

## Security Notes

- Router log files should be readable only by dashboard user
- Windows Event Log access respects system permissions
- Network discovery only shows ARP table entries (local network)
- No credentials are stored in logs or transmitted

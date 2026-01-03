# SystemDashboard - Frequently Asked Questions (FAQ)

## General Questions

### What is SystemDashboard?

SystemDashboard is a Windows-first operations telemetry stack that collects system logs, router data, and network device information into a local SQLite database and presents it through a web-based dashboard. It's designed for IT professionals who need visibility into their Windows infrastructure and home/small office networks.

### Do I need Windows Server to run this?

No. SystemDashboard runs on Windows 11, Windows 10, and Windows Server. It uses PowerShell services and Python, both of which are available on consumer and professional Windows editions.

### Does this require internet access?

No. SystemDashboard operates entirely on your local network. The only optional internet-dependent feature is AI-powered insights (which uses OpenAI's API if you provide a key). All core functionality works offline.

### Is my data sent anywhere?

No. All data stays on your local machine in a SQLite database file (`var/system_dashboard.db`). Nothing is transmitted to external servers unless you explicitly enable optional AI features with your own API key.

### What's the disk space requirement?

- **Minimal**: ~50MB for application code and empty database
- **Typical**: 200-500MB with a week of data collection
- **Heavy**: 1-2GB with months of historical data and high log volume

The system includes automatic data retention policies to prevent unbounded growth.

## Installation & Setup

### Can I install this on multiple machines?

Yes. Each instance maintains its own local database. For centralized monitoring, you would need to aggregate data yourself (not currently built-in).

### Do I need administrator/root access?

Yes, for installation. The installation creates Windows services and scheduled tasks, which require admin privileges. Once installed, services run as SYSTEM.

### Can I run this in a Docker container?

Partially. The Python Flask app and database can run in Docker, but the PowerShell telemetry collection services are Windows-specific and need to run on a Windows host.

### What if I don't have an ASUS router?

Router monitoring is optional. The dashboard works fine without it, collecting only Windows events and LAN device data. Router-specific features will show "No data" if disabled.

### How do I uninstall SystemDashboard?

```powershell
# Stop and remove services
Stop-Service SystemDashboardTelemetry
sc.exe delete SystemDashboardTelemetry

# Remove scheduled tasks
Unregister-ScheduledTask -TaskName "SystemDashboard-*" -Confirm:$false

# Delete files
cd ..
Remove-Item -Recurse -Force SystemDashboard

# Remove PowerShell module (optional)
Remove-Item "$env:ProgramFiles\PowerShell\Modules\SystemDashboard" -Recurse -Force
```

## Configuration

### Where is the database stored?

By default: `var/system_dashboard.db` relative to the installation directory. This can be changed in `config.json` under the `Database` section.

### Can I use PostgreSQL instead of SQLite?

No, not currently. The project is "SQLite first-class" by design for simplicity. PostgreSQL support would require significant refactoring.

### How do I change the web dashboard port?

Edit `app/app.py`, find the last line with `app.run()`, and change the port parameter:

```python
app.run(host='0.0.0.0', port=5001, debug=True)  # Changed from 5000
```

### Where do I configure router credentials?

Set the `ASUS_ROUTER_PASSWORD` environment variable:

```powershell
$env:ASUS_ROUTER_PASSWORD = "your_password"
.\scripts\setup-environment.ps1  # Makes it permanent
```

The router username and URL are in `config.json` under `Service.Asus`.

### How do I enable HTTPS?

See [SECURITY-SETUP.md](SECURITY-SETUP.md) for complete instructions. Summary:

1. Generate certificates: `.\scripts\New-SelfSignedCertificate.ps1`
2. Configure Flask to use SSL in `app/app.py`
3. Update all URLs to use `https://`

## Data Collection

### How often is data collected?

- **Syslog**: Real-time (as messages arrive on UDP 514)
- **Router logs**: Every 5 minutes (configurable in `config.json`)
- **LAN devices**: Every 2 minutes (configurable in LAN collector service)
- **Windows events**: Depends on scheduled task frequency (default: every 5 minutes)

### Why isn't my router sending logs?

Common causes:

1. **Router not configured** - Enable syslog forwarding in router settings
2. **Wrong IP** - Router must send to your Windows machine's IP
3. **Firewall blocking** - Allow UDP 514 inbound on Windows Firewall
4. **Service not running** - Check `SystemDashboard-SyslogCollector` scheduled task

Test with:
```powershell
Test-NetConnection -ComputerName localhost -Port 514 -InformationLevel Detailed
```

### How do I collect IIS logs?

IIS log collection is not yet automated. You can:

1. Configure IIS to send logs via syslog (using third-party tools)
2. Manually import IIS logs using PowerShell scripts
3. Wait for this feature to be added in a future phase

### Can I collect logs from Linux servers?

Yes! Configure your Linux servers to send syslog to your Windows machine's IP:

```bash
# On Linux, edit /etc/rsyslog.conf
*.* @192.168.1.100:514  # Replace with your Windows IP
sudo systemctl restart rsyslog
```

Messages will appear in the Router Logs page.

### How long is data retained?

Default retention periods (configurable in code):

- **Device snapshots**: 90 days
- **Resolved alerts**: 30 days
- **Syslog messages**: 90 days
- **Windows events**: No automatic cleanup (manual cleanup needed)

Run cleanup manually:
```powershell
python -c "from app.data_retention import get_retention_manager; get_retention_manager().run_cleanup()"
```

## Dashboard Usage

### Why does the dashboard show "No data"?

Common reasons:

1. **Database not initialized** - Run `python scripts/init_db.py --verify`
2. **Services not started** - Check `Get-Service SystemDashboardTelemetry`
3. **Fresh install** - Data collection takes a few minutes to populate
4. **No data sources** - Configure router/syslog sources

Generate test data: `.\scripts\test-data-collection.ps1`

### How do I export data?

Every table has an **Export CSV** button. Click it to download data in CSV format with a timestamped filename.

### Can I customize the dashboard colors/theme?

Yes. Edit `app/static/styles.css`. The dashboard uses CSS variables for theming:

```css
:root {
  --primary-color: #2563eb;
  --success-color: #10b981;
  --warning-color: #f59e0b;
  --danger-color: #ef4444;
}
```

### How do I add nicknames to LAN devices?

1. Go to http://localhost:5000/lan
2. Find the device in the table
3. Click the device row to expand details
4. Enter nickname in the "Nickname" field
5. Changes save automatically

### What do the signal strength (RSSI) values mean?

RSSI is measured in dBm (decibel-milliwatts):

- **-30 to -50 dBm**: Excellent signal
- **-51 to -60 dBm**: Good signal
- **-61 to -70 dBm**: Fair signal (usable)
- **-71 to -80 dBm**: Weak signal (may have issues)
- **Below -80 dBm**: Very weak (poor performance)

### Can I set up email alerts?

Not built-in yet (planned for Phase 7). Current workarounds:

1. Use Windows Task Scheduler to run a script that checks the health endpoint
2. Integrate with external monitoring tools (Nagios, Zabbix, etc.)
3. Write a custom PowerShell script using the API endpoints

## Performance

### Why is the dashboard slow?

Common causes and solutions:

1. **Large database** - Run VACUUM to reclaim space:
   ```powershell
   sqlite3 var/system_dashboard.db "VACUUM;"
   ```

2. **Too much data** - Clean up old data:
   ```powershell
   python -c "from app.data_retention import get_retention_manager; get_retention_manager().run_cleanup()"
   ```

3. **Missing indexes** - Verify indexes exist:
   ```powershell
   python scripts/init_db.py --verify
   ```

4. **High CPU usage** - Check for runaway services:
   ```powershell
   Get-Process | Where-Object {$_.Name -like "*SystemDashboard*"} | Select-Object Name, CPU, WS
   ```

### How much memory does this use?

Typical memory usage:

- **Telemetry service**: 50-150MB
- **Flask web app**: 100-200MB
- **LAN collector**: 30-80MB
- **Total**: ~200-400MB

If memory exceeds 500MB per service, investigate for memory leaks or data retention issues.

### Can I run this on a Raspberry Pi?

No. SystemDashboard requires Windows for the PowerShell-based telemetry services. The Python dashboard could theoretically run on Linux, but it's designed to query Windows-collected data.

### Why does the database file keep growing?

Without data retention enforcement, the database will grow unbounded. Solutions:

1. **Enable automatic cleanup**: Schedule the data retention task:
   ```powershell
   # Add to scheduled tasks to run daily
   python -c "from app.data_retention import get_retention_manager; get_retention_manager().run_cleanup()"
   ```

2. **Reduce retention periods**: Edit retention policies in `app/data_retention.py`

3. **VACUUM regularly**: Reclaim space after deletions:
   ```powershell
   sqlite3 var/system_dashboard.db "VACUUM;"
   ```

## Security

### Is the dashboard secure?

By default, the dashboard binds to `localhost` only, meaning it's not accessible from other machines. For security in production:

1. Enable API key authentication (see [SECURITY-SETUP.md](SECURITY-SETUP.md))
2. Use HTTPS with valid certificates
3. Enable CSRF protection
4. Set secure headers (CSP, HSTS, etc.)

All Phase 3 security features are implemented and documented.

### Should I expose this to the internet?

**No, not recommended.** SystemDashboard is designed for internal LAN use. If you need remote access:

1. Use a VPN to your network
2. Set up reverse proxy with authentication (Nginx, Apache)
3. Enable all security features (API keys, HTTPS, CSRF)

### Are passwords stored securely?

Yes. API keys are hashed using bcrypt before storage. The `ASUS_ROUTER_PASSWORD` is stored as an environment variable and never logged in plaintext.

### What about SQL injection?

All database queries use parameterized statements. The codebase has been audited and scanned with CodeQL (zero vulnerabilities found).

## Troubleshooting

### Service starts but crashes immediately

Check logs for errors:

```powershell
Get-Content .\var\log\telemetry-service.log -Tail 50
```

Common causes:
- Database locked by another process
- Missing dependencies (run `pip install -r requirements.txt`)
- Corrupted database (recreate with `python scripts/init_db.py --force`)

### "Database is locked" errors

SQLite supports only one writer at a time. Solutions:

1. Enable WAL mode (already done by default in Phase 1)
2. Close any database browser tools (DB Browser for SQLite)
3. Reduce concurrent writes
4. Check for stale lock files: `var/system_dashboard.db-shm`, `var/system_dashboard.db-wal`

### Flask app shows 500 errors

Check Flask logs:

```powershell
Get-Content .\var\log\webui-service.log -Tail 50
```

Or run Flask in debug mode:

```powershell
$env:FLASK_ENV = "development"
python .\app\app.py
```

### Scheduled tasks not running

Verify tasks exist:

```powershell
Get-ScheduledTask -TaskName "SystemDashboard-*"
```

Check task history:

```powershell
Get-ScheduledTask -TaskName "SystemDashboard-WebUI" | Get-ScheduledTaskInfo
```

Re-register tasks:

```powershell
.\scripts\setup-permanent-services.ps1 -Install
```

### Python module not found errors

Ensure you're using the virtual environment:

```powershell
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

### Changes to config.json not taking effect

Restart all services after config changes:

```powershell
# Restart telemetry service
Restart-Service SystemDashboardTelemetry

# Restart scheduled tasks
Stop-ScheduledTask -TaskName "SystemDashboard-*"
Start-ScheduledTask -TaskName "SystemDashboard-*"
```

## Advanced Topics

### Can I extend the dashboard with custom pages?

Yes. The Flask app is modular. Add new routes in `app/app.py` and templates in `app/templates/`. Example:

```python
@app.route('/custom')
def custom_page():
    return render_template('custom.html')
```

### How do I add custom data sources?

1. Create a new PowerShell module in `tools/`
2. Define ingestion functions following the pattern in `SystemDashboard.Telemetry.psm1`
3. Add database tables in a new migration script
4. Update `app/app.py` to query your new tables

### Can I use this with other routers (non-ASUS)?

Yes, with modifications. The syslog listener is router-agnostic. For log polling:

1. Identify how to fetch logs from your router (API, SSH, etc.)
2. Modify the ASUS poller in `services/SystemDashboardService.ps1`
3. Or configure your router to push logs via syslog (preferred)

### How do I contribute to the project?

See [CONTRIBUTING.md](CONTRIBUTING.md) for:

- Code style guidelines
- How to submit pull requests
- Testing requirements
- Development workflow

### What's on the roadmap?

See [ROADMAP.md](../ROADMAP.md) for the complete plan. Current phase:

- **Phase 5**: Documentation & Onboarding (in progress)
- **Phase 6**: Testing & Quality Assurance (planned)
- **Phase 7**: Production Readiness (planned)

## Performance Optimization

### How can I make queries faster?

1. **Verify indexes** are in place:
   ```powershell
   python scripts/init_db.py --verify
   ```

2. **Use keyset pagination** for large result sets (automatically used for page sizes > 1000)

3. **Enable query caching** (already enabled by default with 5-minute TTL)

4. **Monitor slow queries**:
   ```powershell
   # Check performance endpoint
   curl http://localhost:5000/api/performance/queries
   ```

### How do I reduce memory usage?

1. **Limit collection frequency** in `config.json`
2. **Reduce batch sizes** for ingestion
3. **Enable data retention** to auto-delete old data
4. **Run VACUUM** regularly to compact the database

### Can I run this on low-spec hardware?

Yes. Minimum requirements:

- **CPU**: 2 cores @ 2.0 GHz
- **RAM**: 2GB (4GB recommended)
- **Disk**: 10GB free space
- **Network**: 100 Mbps

For lower specs, reduce collection frequency and enable aggressive data retention.

## Getting Help

### Where can I find more documentation?

- **Getting Started**: [GETTING-STARTED.md](GETTING-STARTED.md)
- **Setup Guide**: [SETUP.md](SETUP.md)
- **Help Guide**: [HELP.md](HELP.md)
- **Troubleshooting**: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- **Security**: [SECURITY-SETUP.md](SECURITY-SETUP.md)
- **LAN Observability**: [LAN-OBSERVABILITY-README.md](LAN-OBSERVABILITY-README.md)

### How do I report a bug?

1. Check logs for error messages
2. Run health check: http://localhost:5000/health/detailed
3. Create an issue at: https://github.com/your-username/SystemDashboard/issues

Include:
- SystemDashboard version (check git commit)
- Windows version
- Error messages from logs
- Steps to reproduce

### Can I get commercial support?

This is an open-source project without official commercial support. Community support is available via GitHub Issues.

### Is there a Discord/Slack community?

Not currently. For now, use GitHub Discussions or Issues for questions and support.

---

## Quick Answer Index

**Q: Is this free?**  
**A:** Yes, open source and free to use.

**Q: Does it work on macOS/Linux?**  
**A:** No, Windows only (PowerShell services are Windows-specific).

**Q: Can I monitor multiple routers?**  
**A:** One router per instance. For multiple routers, configure them all to send syslog.

**Q: Does this support IPv6?**  
**A:** Yes, LAN device tracking supports both IPv4 and IPv6.

**Q: Can I import historical data?**  
**A:** Not directly. You'd need to write custom import scripts for your data format.

**Q: Is there a mobile app?**  
**A:** No, but the dashboard is responsive and works on mobile browsers.

**Q: Can I white-label this?**  
**A:** Yes, it's open source. Customize branding in templates and CSS files.

**Q: How do I upgrade to a new version?**  
**A:** See [UPGRADE-GUIDE.md](UPGRADE-GUIDE.md) for migration procedures.

---

**Still have questions?** Check [HELP.md](HELP.md) for comprehensive usage documentation or create an issue on GitHub!

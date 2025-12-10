# System Dashboard Telemetry Stack

A Windows-first operations telemetry stack that collects logs, enriches them with PowerShell, stores the data in SQLite, and serves professional dashboards for investigation. The repository now ships with four primary components:

1. **Telemetry Windows Service** (`services/SystemDashboardService.ps1`) – a long-running PowerShell service that listens for inbound syslog messages, polls ASUS routers for log exports, and hands batches to the ingestion helpers in `tools/SystemDashboard.Telemetry.psm1` for loading into SQLite.
2. **LAN Observability Collector** (`services/LanCollectorService.ps1`) – a dedicated service for network device monitoring that tracks device presence, signal strength, and behavior over time. See [LAN-OBSERVABILITY-README.md](LAN-OBSERVABILITY-README.md) for details.
3. **Syslog Collector** (`services/SyslogCollectorService.ps1`) – a dedicated listener on UDP 5514 that ingests router/syslog feeds into SQLite (for the Router Logs page and dashboard summaries).
4. **PowerShell HTTP listener** (`Start-SystemDashboard.ps1`/`.psm1`) – exposes metrics and can continue to serve the static dashboard located under `wwwroot/` when you want a lightweight view hosted on Windows.
5. **Flask analytics UI** (`app/app.py`) – a richer dashboard experience that queries SQLite directly, highlights actionable issues (IIS 5xx bursts, authentication storms, Windows event spikes, router anomalies), and provides LAN device visibility and tracking.

The service, ingestion helpers, and UI follow the project guidance of “PowerShell first” for orchestration and “SQLite first-class” for storage. Scheduled tasks can still be layered on for Windows Event Log and IIS ingestion as described in the project charter.

## New: LAN Observability

The SystemDashboard now includes comprehensive network device monitoring:

- **Device Inventory**: Tracks all devices (by MAC address) that have ever appeared on your network
- **Time-Series Metrics**: Records signal strength (RSSI), transfer rates, and online/offline behavior
- **Syslog Correlation**: Links router events to specific devices for troubleshooting
- **Web Dashboard**: Real-time visibility with charts and filtering at `/lan`

To get started with LAN Observability:

```powershell
# Apply the database schema
.\scripts\apply-lan-schema.ps1

# Start the collector service
.\services\LanCollectorService.ps1
```

Recent LAN updates:

- Interface/band detection (wired, wireless 2.4/5 GHz) with RSSI/Tx/Rx and lease type.
- Per-device nickname/location editing (stored on `telemetry.devices`).
- Router syslog correlation shows per-device events in detail pages.

For complete documentation, see [docs/LAN-OBSERVABILITY-README.md](docs/LAN-OBSERVABILITY-README.md).

## Architecture

```
┌────────────────────┐          ┌──────────────────────┐          ┌──────────────────────┐
│ Windows endpoints  │  Syslog  │ SystemDashboard       │ COPY/SQL │ SQLite (telemetry│
│ IIS / Event logs   │────────▶│ Telemetry Service     │────────▶│ schema + partitions) │
│ ASUS router        │  HTTPS  │  • UDP 514 listener    │          │  • syslog_generic_*  │
│                    │────────▶│  • ASUS log poller     │          │  • devices + snapshots│
│                    │          │  • LAN collector       │          │  • materialized views │
└────────────────────┘          │  • PowerShell ingest   │          └──────────────────────┘
                                └──────────────────────┘                    │
                                                                               ▼
                                                                    ┌────────────────────┐
                                                                    │ IIS/static UI      │
                                                                    │ Flask analytics    │
                                                                    │ LAN dashboard      │
                                                                    └────────────────────┘
```

- **Ingest** – `SystemDashboardService` binds to UDP 514 on Windows 11, normalizes syslog payloads (facility/severity parsing, host extraction), polls an ASUS router endpoint at a configurable cadence, and writes batches to SQLite . The service maintains its own durable state (`var/asus/state.json`) and logs to `var/log/telemetry-service.log`.
- **Store** – SQLite hosts the database at `var/system_dashboard.db`. Use `python scripts/init_db.py` to create the database and schema. The schema is defined in `tools/schema-sqlite.sql`.
- **Serve** – The classic PowerShell HTTP listener can still expose metrics at `http://localhost:15000/`. The Flask UI (or an IIS site you publish it to) queries SQLite for recent trends, 5xx spikes, authentication storms, and router anomalies.

## Quick start on Windows 11

1. **Install prerequisites**
   - PowerShell 7+
   - Python 3.10+ (for the Flask UI and database initialization)
   - Git
2. **Clone the repository**

   ```powershell
   git clone https://github.com/your-org/SystemDashboard.git
   cd SystemDashboard
   ```

3. **Configure secrets** (optional)
   - Set `ASUS_ROUTER_PASSWORD` if your router requires authentication.
   - Set `OPENAI_API_KEY` for AI-powered explanations.
4. **Review `config.json`** – update the ASUS router endpoint if needed. Paths can be relative to the repo root.
5. **Initialize the database**

   ```powershell
   python scripts/init_db.py
   ```

   This creates the SQLite database at `var/system_dashboard.db` with all required tables and views.
6. **Install and register the service**

   ```powershell
   pwsh -File .\scripts\Install.ps1
   ```

   This copies the modules into `$env:ProgramFiles\PowerShell\Modules\SystemDashboard`, creates the Python virtual environment, ensures runtime folders exist under `var/`, and registers a Windows service named `SystemDashboardTelemetry` pointing at `services/SystemDashboardService.ps1`.
7. **Install scheduled tasks (WebUI, LAN collector, Syslog collector)**

   ```powershell
   pwsh -File .\scripts\setup-permanent-services.ps1 -Install
   ```

   Tasks created: `SystemDashboard-WebUI`, `SystemDashboard-LANCollector`, `SystemDashboard-SyslogCollector`.
8. **Start ingestion**

   ```powershell
   Start-Service SystemDashboardTelemetry
   Get-Content .\var\log\telemetry-service.log -Tail 20 -Wait
   ```

   You should see entries indicating syslog packets received and ASUS log batches ingested.
9. **Run the web UI (dev)**

   ```powershell
   .\.venv\Scripts\Activate.ps1
   python .\app\app.py
   ```

   Running `Start-SystemDashboard.ps1` now also opens `http://localhost:15000/` in your default browser. Use `.\Start-SystemDashboard.ps1 -NoBrowser` if you need to keep it headless or run inside automation.

Browse to `http://localhost:5000/` for the analytics dashboard. For production you can host the contents of `wwwroot/` (or the Flask app behind IIS) at `http://localhost:8088/` per the project brief.

## Unified launch script

Use `scripts/Launch.ps1` (or the accompanying `scripts/Launch.bat`/`scripts/Launch.sh` wrappers) to run the root-level helper scripts in their recommended order without invoking each file separately. The default pipeline performs:

- `Environment` → runs `scripts/setup-environment.ps1` (use `-EnvironmentPermanent` to persist the vars).
- `Database` → runs `scripts/setup-database.ps1` (switch to `-DatabaseMode docker` to call `scripts/setup-database-docker.ps1`).
- `Install` → runs `scripts/Install.ps1`.
- `PermanentServices` → runs `scripts/setup-permanent-services.ps1 -Install`.
- `ScheduledTask` → runs `scripts/setup-scheduled-task.ps1`.
- `LanSchema` → runs `scripts/apply-lan-schema.ps1` (pass `-ForceLanSchema` or `-LanConfigPath` as needed).

You can limit what runs by setting the `-Stages` argument (e.g., `-Stages Environment,Install`). Additional argument passthroughs exist (`-DatabaseArgs`, `-InstallArgs`, `-ScheduledTaskArgs`, `-LanArgs`) if you need to forward flags to the underlying scripts.

```powershell
pwsh .\scripts\Launch.ps1
.\scripts\Launch.bat
./scripts/Launch.sh
```

Use `pwsh .\scripts\Launch.ps1 -ForceLanSchema -DatabaseMode docker` to adjust the defaults.

## Configuration reference (`config.json`)

| Key | Description |
| --- | --- |
| `Prefix`, `Root`, `IndexHtml`, `CssFile` | Legacy settings for the PowerShell HTTP listener. |
| `PingTarget` | Target used by the listener for latency checks. |
| `RouterIP` | Still used by `Get-RouterCredentials` when invoking legacy router helper functions. |
| `Database` | SQLite connection details (`Host`, `Port`, `Database`, `Username`, `PasswordSecret` or `Password`, `Schema`, optional `PsqlPath`). Passwords can reference environment variables using the `env:` prefix. |
| `Service.LogPath` | Where the telemetry service writes its own operational log. |
| `Service.Syslog` | Syslog listener binding (`BindAddress`, `Port`, `BufferDirectory`, `MaxMessageBytes`). |
| `Service.Asus` | Router polling configuration (`Enabled`, `Uri`, `HostName`, optional credentials, `PollIntervalSeconds`, `DownloadPath`, `StatePath`). |
| `Service.Ingestion` | Batch behavior (`BatchIntervalSeconds`, `MinBatchSize`, `StagingDirectory`) used before invoking SQLite `COPY`. |

All paths are expanded relative to the location of `config.json` unless absolute.

## Telemetry service internals

- **Syslog listener** – A PowerShell loop backed by `System.Net.Sockets.UdpClient` that normalizes `<PRI>` values, extracts timestamp/host/app, and queues messages for ingestion.
- **ASUS log poller** – Periodically calls the configured router URI, filters out lines already seen (based on the most recent timestamp), and appends new entries to `var/asus/asus-log-YYYYMMDD.log` for audit.
- **Ingestion** – Batches are inserted directly into SQLite tables. Failures are logged with level `ERROR`. The service persists ASUS polling state so restarts resume where they left off.
- **Extensibility** – The module `tools/SystemDashboard.Telemetry.psm1` exposes `Start-TelemetryService`, `Invoke-AsusLogFetch`, `Invoke-SyslogIngestion`, and configuration helpers so you can plug additional sources (Windows Event Logs, IIS logs) into the same ingestion path or scheduled tasks.

## Flask dashboard highlights

The Flask app uses `sqlite3` to query SQLite and renders actionable sections:

- IIS 5xx surge detection (last 5 minutes vs. trailing baseline)
- Authentication storms (401/403 bursts by client IP)
- Windows critical/error event spikes (events page now has severity/source/keyword charts)
- Router anomalies and syslog drill-down (router page shows severity mix, WAN drop ports, Wi-Fi events)
- LAN device inventory with per-device detail, RSSI/Tx/Rx, lease type, nickname/location editing, and wireless band detection

If the database is unreachable, the UI gracefully falls back to mock data so development on non-Windows hosts remains possible.

Set the following environment variables before starting the Flask app when running on Windows:

```powershell
$env:DASHBOARD_DB_HOST = 'localhost'
$env:DASHBOARD_DB_NAME = 'system_dashboard'
$env:DASHBOARD_DB_USER = 'sysdash_reader'
$env:DASHBOARD_DB_PASSWORD = '<read-only password>'
$env:AUTH_FAILURE_THRESHOLD = '10'   # optional override for auth burst detection
```

`requirements.txt` installs the Flask package. SQLite3 is part of Pythons standard library so no database drivers are needed.

## Database operations

- Run `python scripts/init_db.py` to create or recreate the database with the schema.
- Run `python scripts/init_db.py --verify` to check the database structure.
- Use `python scripts/init_db.py --force` to reset the database (warning: deletes all data).
- The database is stored at `var/system_dashboard.db` by default.

## Troubleshooting

For detailed troubleshooting, see [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

**Quick fixes:**

- **Service fails to start** – Check `var/log/telemetry-service.log` for errors.
- **No data in SQLite** – Ensure the database has been initialized with `python scripts/init_db.py`.
- **ASUS fetch errors** – Verify SSH connectivity to the router, the configured remote log path, and credentials/environment variables. The service backs off quietly but logs warnings.
- **Flask app shows placeholders** – Confirm the database exists and is readable.

## Documentation

### Getting Started
- **[Getting Started Guide](docs/GETTING-STARTED.md)** - **START HERE** - 5-minute quick start guide
- **[FAQ](docs/FAQ.md)** - Frequently asked questions with answers
- **[Setup Guide](docs/SETUP.md)** - Complete installation and configuration instructions
- **[Dashboard Tour](docs/DASHBOARD-TOUR.md)** - Guided tour of the dashboard (coming soon)

### User Guides
- **[Help Guide](docs/HELP.md)** - **Dashboard user guide** - How to use the dashboard, interpret metrics, and troubleshoot issues
- **[LAN Observability](docs/LAN-OBSERVABILITY-README.md)** - Network device monitoring
- **[Advanced Features](docs/ADVANCED-FEATURES.md)** - Router monitoring, scaling, and maintenance
- **[Data Sources](docs/DATA-SOURCES.md)** - Configuring Windows Events, router logs, and system metrics
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and solutions

### Developer Documentation
- **[Architecture](docs/ARCHITECTURE.md)** - System architecture with diagrams
- **[API Reference](docs/API-REFERENCE.md)** - Complete REST API documentation
- **[Database Schema](docs/DATABASE-SCHEMA.md)** - Database structure and ER diagrams
- **[Contributing Guide](docs/CONTRIBUTING.md)** - How to contribute to the project
- **[Implementation Guide](docs/IMPLEMENTATION-GUIDE.md)** - Code examples for roadmap items

### Operations Documentation
- **[Deployment Guide](docs/DEPLOYMENT.md)** - Production deployment with security and monitoring
- **[Backup & Restore](docs/BACKUP-RESTORE.md)** - Backup strategies and restore procedures
- **[Monitoring Setup](docs/MONITORING.md)** - Monitoring configuration (coming soon)
- **[Performance Tuning](docs/PERFORMANCE-TUNING.md)** - Optimization guide (coming soon)
- **[Upgrade Guide](docs/UPGRADE-GUIDE.md)** - Version upgrade procedures (coming soon)

### Project Management
- **[Roadmap](ROADMAP.md)** - **Production readiness plan** - Feature hardening and UI polish
- **[Changelog](docs/CHANGELOG.md)** - Version history
- **[Security Summary](docs/SECURITY-SUMMARY.md)** - Security analysis and recommendations

## Tests

Python tests use pytest:

```bash
# Run all Python tests
pytest tests/

# Run specific test suites
pytest tests/test_health_check.py
pytest tests/test_rate_limiter.py
pytest tests/test_graceful_shutdown.py
```

Pester tests for PowerShell modules:

```powershell
pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path tests"
```

## Production Features

### Phase 1: Service Reliability

- **Health Monitoring** (`/health/detailed`) - Comprehensive health checks with database connectivity, schema integrity, and data freshness monitoring
- **Rate Limiting** - Per-client API rate limiting to prevent abuse (configurable per endpoint)
- **Graceful Shutdown** - Clean shutdown with signal handlers and cleanup functions

See [Phase 1 Improvements](docs/PHASE1-IMPROVEMENTS.md) for detailed documentation and usage examples.

### Phase 2: UI Polish & Professionalism

- **Form Validation & Autosave** - Real-time validation with automatic saving
- **Keyboard Shortcuts** - Navigate with `?` for help, `h`/`e`/`l`/`r`/`w` for pages
- **Table Enhancements** - CSV export, sortable columns, auto-refresh indicators
- **State Persistence** - Search and filter state remembered across navigation

See [Phase 2 Completion Summary](docs/PHASE2-COMPLETION-SUMMARY.md) for complete details.

### Phase 3: Security & Hardening

- **Security Headers** - CSP, HSTS, X-Frame-Options, X-Content-Type-Options for protection
- **API Key Authentication** - Optional authentication for sensitive endpoints
- **CSRF Protection** - Double-submit cookie pattern for state-changing operations
- **Audit Logging** - Comprehensive tracking of configuration changes with sensitive data masking
- **HTTPS Support** - SSL certificate generation and configuration guidance

See [Phase 3 Completion Summary](docs/PHASE3-COMPLETION-SUMMARY.md) and [Security Setup Guide](docs/SECURITY-SETUP.md) for detailed documentation.

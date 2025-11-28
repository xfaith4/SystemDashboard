# System Dashboard Telemetry Stack

A Windows-first operations telemetry stack that collects logs, enriches them with PowerShell, stores the data in PostgreSQL, and serves professional dashboards for investigation. The repository now ships with four primary components:

1. **Telemetry Windows Service** (`services/SystemDashboardService.ps1`) – a long-running PowerShell service that listens for inbound syslog messages, polls ASUS routers for log exports, and hands batches to the ingestion helpers in `tools/SystemDashboard.Telemetry.psm1` for loading into PostgreSQL.
2. **LAN Observability Collector** (`services/LanCollectorService.ps1`) – a dedicated service for network device monitoring that tracks device presence, signal strength, and behavior over time. See [LAN-OBSERVABILITY-README.md](LAN-OBSERVABILITY-README.md) for details.
3. **Syslog Collector** (`services/SyslogCollectorService.ps1`) – a dedicated listener on UDP 5514 that ingests router/syslog feeds into PostgreSQL (for the Router Logs page and dashboard summaries).
4. **PowerShell HTTP listener** (`Start-SystemDashboard.ps1`/`.psm1`) – exposes metrics and can continue to serve the static dashboard located under `wwwroot/` when you want a lightweight view hosted on Windows.
5. **Flask analytics UI** (`app/app.py`) – a richer dashboard experience that queries PostgreSQL directly, highlights actionable issues (IIS 5xx bursts, authentication storms, Windows event spikes, router anomalies), and provides LAN device visibility and tracking.

The service, ingestion helpers, and UI follow the project guidance of “PowerShell first” for orchestration and “PostgreSQL first-class” for storage. Scheduled tasks can still be layered on for Windows Event Log and IIS ingestion as described in the project charter.

## New: LAN Observability

The SystemDashboard now includes comprehensive network device monitoring:

- **Device Inventory**: Tracks all devices (by MAC address) that have ever appeared on your network
- **Time-Series Metrics**: Records signal strength (RSSI), transfer rates, and online/offline behavior  
- **Syslog Correlation**: Links router events to specific devices for troubleshooting
- **Web Dashboard**: Real-time visibility with charts and filtering at `/lan`

To get started with LAN Observability:

```powershell
# Apply the database schema
.\apply-lan-schema.ps1

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
│ Windows endpoints  │  Syslog  │ SystemDashboard       │ COPY/SQL │ PostgreSQL (telemetry│
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

- **Ingest** – `SystemDashboardService` binds to UDP 514 on Windows 11, normalizes syslog payloads (facility/severity parsing, host extraction), polls an ASUS router endpoint at a configurable cadence, and writes batches to PostgreSQL using `psql` `COPY`. The service maintains its own durable state (`var/asus/state.json`) and logs to `var/log/telemetry-service.log`.
- **Store** – PostgreSQL hosts wide, partitioned tables. Use `tools/schema.sql` to create the base schema and helper function for monthly partitions (`telemetry.ensure_syslog_partition`). Ingestion scripts call `COPY` into the `telemetry.syslog_generic_YYMM` partitions.
- **Serve** – The classic PowerShell HTTP listener can still expose metrics at `http://localhost:15000/`. The Flask UI (or an IIS site you publish it to) queries PostgreSQL for recent trends, 5xx spikes, authentication storms, and router anomalies.

## Quick start on Windows 11

1. **Install prerequisites**
   - PowerShell 7+
   - PostgreSQL 15/16 with `psql` in your `PATH`
   - Python 3.10+ (for the Flask UI)
   - Git
2. **Clone the repository**
   ```powershell
   git clone https://github.com/your-org/SystemDashboard.git
   cd SystemDashboard
   ```
3. **Configure secrets**
   - Set `SYSTEMDASHBOARD_DB_PASSWORD` in the environment (the service reads it at runtime).
   - Set `ASUS_ROUTER_PASSWORD` if your router requires authentication.
4. **Review `config.json`** – update PostgreSQL host, database, user, and the ASUS router endpoint if needed. Paths can be relative to the repo root.
5. **Provision the schema**
   ```powershell
   psql -h <host> -U <user> -d system_dashboard -f .\tools\schema.sql
   ```
   Optionally call `SELECT telemetry.ensure_syslog_partition(CURRENT_DATE);` to create the current month’s partition.
6. **Install and register the service**
   ```powershell
   pwsh -File .\Install.ps1
   ```
   This copies the modules into `$env:ProgramFiles\PowerShell\Modules\SystemDashboard`, creates the Python virtual environment, ensures runtime folders exist under `var/`, and registers a Windows service named `SystemDashboardTelemetry` pointing at `services/SystemDashboardService.ps1`.
7. **Install scheduled tasks (WebUI, LAN collector, Syslog collector)**
   ```powershell
   pwsh -File .\setup-permanent-services.ps1 -Install
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
   Browse to `http://localhost:5000/` for the analytics dashboard. For production you can host the contents of `wwwroot/` (or the Flask app behind IIS) at `http://localhost:8088/` per the project brief.

## Configuration reference (`config.json`)

| Key | Description |
| --- | --- |
| `Prefix`, `Root`, `IndexHtml`, `CssFile` | Legacy settings for the PowerShell HTTP listener. |
| `PingTarget` | Target used by the listener for latency checks. |
| `RouterIP` | Still used by `Get-RouterCredentials` when invoking legacy router helper functions. |
| `Database` | PostgreSQL connection details (`Host`, `Port`, `Database`, `Username`, `PasswordSecret` or `Password`, `Schema`, optional `PsqlPath`). Passwords can reference environment variables using the `env:` prefix. |
| `Service.LogPath` | Where the telemetry service writes its own operational log. |
| `Service.Syslog` | Syslog listener binding (`BindAddress`, `Port`, `BufferDirectory`, `MaxMessageBytes`). |
| `Service.Asus` | Router polling configuration (`Enabled`, `Uri`, `HostName`, optional credentials, `PollIntervalSeconds`, `DownloadPath`, `StatePath`). |
| `Service.Ingestion` | Batch behavior (`BatchIntervalSeconds`, `MinBatchSize`, `StagingDirectory`) used before invoking PostgreSQL `COPY`. |

All paths are expanded relative to the location of `config.json` unless absolute.

## Telemetry service internals

- **Syslog listener** – A PowerShell loop backed by `System.Net.Sockets.UdpClient` that normalizes `<PRI>` values, extracts timestamp/host/app, and queues messages for ingestion.
- **ASUS log poller** – Periodically calls the configured router URI, filters out lines already seen (based on the most recent timestamp), and appends new entries to `var/asus/asus-log-YYYYMMDD.log` for audit.
- **Ingestion** – Batches are written to CSV in `var/staging/` and loaded via `psql \copy` into the `telemetry.syslog_generic_YYMM` partition. Failures are logged with level `ERROR`. The service persists ASUS polling state so restarts resume where they left off.
- **Extensibility** – The module `tools/SystemDashboard.Telemetry.psm1` exposes `Start-TelemetryService`, `Invoke-AsusLogFetch`, `Invoke-SyslogIngestion`, and configuration helpers so you can plug additional sources (Windows Event Logs, IIS logs) into the same ingestion path or scheduled tasks.

## Flask dashboard highlights

The Flask app uses `psycopg2` to query PostgreSQL and renders actionable sections:

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

`requirements.txt` installs `psycopg2-binary` alongside Flask so no additional packages are required.

## Database operations

- Run `tools/schema.sql` after provisioning PostgreSQL.
- Call `SELECT telemetry.ensure_syslog_partition(date_trunc('month', NOW()));` at the start of each month (or automate it) so ingestion always has a live partition.
- Create read/write roles that align with the project charter (`sysdash_ingest` for the service, `sysdash_reader` for dashboards).
- Consider materialized views for top KPIs (IIS 5xx, auth failures, router drops). Refresh them via scheduled tasks using PowerShell.

## Troubleshooting

For detailed troubleshooting, see [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

**Quick fixes:**
- **Service fails to start** – Check `var/log/telemetry-service.log`. Missing `psql` or incorrect credentials are the most common causes.
- **No data in PostgreSQL** – Ensure `telemetry.ensure_syslog_partition` has been called for the current month and that the service account has `INSERT` permissions on the schema.
- **ASUS fetch errors** – Verify SSH connectivity to the router, the configured remote log path, and credentials/environment variables. The service backs off quietly but logs warnings.
- **Flask app shows placeholders** – Confirm database environment variables are set and that the reader role can execute the dashboard queries.

## Documentation

- **[Help Guide](docs/HELP.md)** - **Dashboard user guide** - How to use the dashboard, interpret metrics, and troubleshoot issues
- **[Setup Guide](docs/SETUP.md)** - Complete installation and configuration instructions
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and solutions
- **[LAN Observability](docs/LAN-OBSERVABILITY-README.md)** - Network device monitoring
- **[Advanced Features](docs/ADVANCED-FEATURES.md)** - Router monitoring, scaling, and maintenance
- **[Data Sources](docs/DATA-SOURCES.md)** - Configuring Windows Events, router logs, and system metrics
- **[Security Summary](docs/SECURITY-SUMMARY.md)** - Security analysis and recommendations
- **[Changelog](docs/CHANGELOG.md)** - Version history

## Tests

Pester tests for the legacy listener are under `tests/`. Run `pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path tests"` on Windows.

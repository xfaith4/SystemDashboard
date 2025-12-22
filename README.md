<<<<<<< HEAD

# SystemDashboard (Unified)

Canonically run the Pode-based build under `2025-09-11/` via `Start-SystemDashboard.Unified.ps1`. Older variants (legacy listener + Flask UI, WindSurf telemetry blend) remain in-tree for now while we merge features.

## Quick start (unified Pode build)

- Requires PowerShell 7+ and the Pode module (`Install-Module Pode -Scope CurrentUser`).
- From this directory run:

  ```powershell
  pwsh -NoProfile -File .\Start-SystemDashboard.Unified.ps1
  ```

- Browse to `http://127.0.0.1:5000` (defaults from `2025-09-11/config.json`). Adjust bind/port or DB in that config.
- Optional telemetry service (syslog/ASUS to Postgres): enable `telemetry.enabled` in `2025-09-11/config.json` and run:

  ```powershell
  pwsh -NoProfile -File .\telemetry\Start-TelemetryService.ps1
  ```

  The Pode API will read `/api/syslog` from Postgres when telemetry is enabled.
- To create the telemetry schema on Postgres, ensure `SYSTEMDASHBOARD_DB_PASSWORD` is set and run:

  ```powershell
  pwsh -NoProfile -File .\telemetry\Apply-TelemetrySchema.ps1
  ```

- Event Log Explorer (optional ASP.NET portable UI): from `tools/EventLogExplorer` you can publish or run:

  ```powershell
  dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:PublishTrimmed=true -o ./publish
  .\publish\EventLogExplorer.exe
  ```

## Layout (current consolidation)

- `Start-SystemDashboard.Unified.ps1` – entrypoint to the modern Pode stack under `2025-09-11/`.
- `2025-09-11/` – Pode server, SQLite/Postgres support, HTMX-style web UI, service installer, tests.
- `telemetry/` – WindSurf telemetry service (syslog UDP + ASUS poller) and schema; now wired behind the Pode `/api/syslog` when enabled.
- `tools/EventLogExplorer/` – the Gemini C# Event Log Explorer (portable ASP.NET) relocated into this repo.
- `tools/observability/` – Prometheus/Loki/promtail configs and eventlog exporter/startup scripts.
- `tools/router/` – router utilities (ASUS backup, client list).
- `tools/router/syslog-parser/` – ASUS/router syslog analyzer that emits CSV + JSON summaries.
- `tools/scripts/` – miscellaneous helper scripts (system health report, NVIDIA ETW, etc.).
- `tools/network/` – subnet inventory scanner (NetworkClientScan) with Pester tests.
- Archived: legacy listener scripts/zips moved to `_archive/root-scripts/`. Other legacy repos moved to `_archive/` for reference.
- Archives/IDE output (`SystemDashboard*.zip`, `.vs/`) are being ignored going forward via `.gitignore`.

## In-flight next steps

- Fold the WindSurf telemetry service (Postgres + syslog/ASUS ingestion) in as an optional add-on.
- Decide how to include the Gemini C# Event Log Explorer (embed as a feature or ship as a companion tool).
- Remove remaining duplication once the above pieces land (single config schema, single UI).
=======

# System Dashboard Telemetry Stack

A Windows-first operations telemetry stack that collects logs, enriches them with PowerShell, stores the data in PostgreSQL, and serves professional dashboards for investigation. The repository now ships with three primary components:

1. **Telemetry Windows Service** (`services/SystemDashboardService.ps1`) – a long-running PowerShell service that listens for inbound syslog messages, polls ASUS routers for log exports, and hands batches to the ingestion helpers in `tools/SystemDashboard.Telemetry.psm1` for loading into PostgreSQL.
2. **PowerShell HTTP listener** (`Start-SystemDashboard.ps1`/`.psm1`) – exposes metrics and can continue to serve the static dashboard located under `wwwroot/` when you want a lightweight view hosted on Windows.
3. **Flask analytics UI** (`app/app.py`) – a richer dashboard experience that queries PostgreSQL directly, highlights actionable issues (IIS 5xx bursts, authentication storms, Windows event spikes, router anomalies), and provides drill-down views.

The service, ingestion helpers, and UI follow the project guidance of “PowerShell first” for orchestration and “PostgreSQL first-class” for storage. Scheduled tasks can still be layered on for Windows Event Log and IIS ingestion as described in the project charter.

## Architecture

```
┌────────────────────┐          ┌──────────────────────┐          ┌──────────────────────┐
│ Windows endpoints  │  Syslog  │ SystemDashboard       │ COPY/SQL │ PostgreSQL (telemetry│
│ IIS / Event logs   │────────▶│ Telemetry Service     │────────▶│ schema + partitions) │
│ ASUS router        │  HTTPS  │  • UDP 514 listener    │          │  • syslog_generic_*  │
│                    │────────▶│  • ASUS log poller     │          │  • materialized views │
└────────────────────┘          │  • PowerShell ingest   │          └──────────────────────┘
                                └──────────────────────┘                    │
                                                                               ▼
                                                                    ┌────────────────────┐
                                                                    │ IIS/static UI      │
                                                                    │ Flask analytics    │
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
7. **Start ingestion**

   ```powershell
   Start-Service SystemDashboardTelemetry
   Get-Content .\var\log\telemetry-service.log -Tail 20 -Wait
   ```

   You should see entries indicating syslog packets received and ASUS log batches ingested.
8. **Run the web UI**

   ```powershell
   .\.venv\Scripts\Activate.ps1
   python .\app\app.py
   ```

   Browse to `http://localhost:<port>/` for the analytics dashboard; the currently assigned port is tracked in `var/webui-port.txt` and the service will pick the next available port starting at 5000. For production you can host the contents of `wwwroot/` (or the Flask app behind IIS) at `http://localhost:8088/` per the project brief.

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
- Windows critical/error event spikes over the last 10 minutes
- Router anomalies (WAN drops, DHCP storms, failed logins)
- Recent raw syslog entries for drill-down

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

- **Service fails to start** – Check `var/log/telemetry-service.log`. Missing `psql` or incorrect credentials are the most common causes.
- **No data in PostgreSQL** – Ensure `telemetry.ensure_syslog_partition` has been called for the current month and that the service account has `INSERT` permissions on the schema.
- **ASUS fetch errors** – Verify the router URI allows HTTP GET and that credentials/environment variables are configured. The service backs off quietly but logs warnings.
- **Flask app shows placeholders** – Confirm database environment variables are set and that the reader role can execute the dashboard queries.

## Tests

Pester tests for the legacy listener are under `tests/`. Run `pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path tests"` on Windows.
>>>>>>> 7b56c8a6e4bc5c9c145d426fd33c74dd97862afa

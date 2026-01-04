# SystemDashboard

Unified telemetry ingestion + dashboards for Windows events, syslog, and LAN activity, powered by PowerShell and Flask.

## Highlights

- Ingests Windows events, syslog, and router telemetry into PostgreSQL.
- Serves a lightweight legacy UI (PowerShell) and a richer Flask analytics UI.
- Provides device inventory, timeline charts, and anomaly-friendly summaries.
- Includes automation for database setup, scheduled tasks, and health checks.

## Architecture (high level)

- Collectors (PowerShell + services) -> PostgreSQL -> Dashboard UI(s)
- Legacy UI: `Start-SystemDashboard.ps1` serving `wwwroot/`
- Flask UI: `app/app.py` with direct Postgres queries

## Quick start

1. Optional: create `config.local.json` for your machine (preferred over `config.json`).
2. Set required secrets (see `.env.example`).
3. Import the scripting module:

   ```powershell
   Import-Module .\scripting\SystemDashboard.Scripting.psm1 -Force
   ```

4. Install dependencies:

   ```powershell
   Install-SystemDashboard -ConfigPath .\config.json
   ```

5. Initialize the database:
   - Local Postgres: `Initialize-SystemDashboardDatabase`
   - Docker Postgres: `Initialize-SystemDashboardDockerDatabase`
6. Launch the dashboard:

   ```powershell
   pwsh -NoProfile -File .\Start-SystemDashboard.ps1 -Mode Legacy
   ```

## Screenshots

See `docs/screenshots/README.md` for naming and capture guidance.

## Operational commands (from the module)

- `Apply-SystemDashboardLanSchema -ConfigPath .\config.json` – add LAN observability tables.
- `Install-SystemDashboardScheduledTask` – register the telemetry scheduled task.
- `Manage-SystemDashboardServices -Install|-Uninstall|-Status` – manage the scheduled-task based services.
- `Ensure-SystemDashboardLanDependencies` – download LAN collector dependencies.
- `Invoke-SystemDashboardControl` – open the interactive operations menu.
- `Invoke-SystemDashboardAutoHeal` – run the one-time health probe with optional AI suggestions.
- `Test-SystemDashboardTelemetryDatabase` – verify reader connectivity to Postgres.

## Resiliency & diagnostics

- Listener degrades gracefully when assets/config are missing; check `/api/status` for startup issues and last error.
- Database calls use connect/query timeouts plus a circuit breaker; tune with `SYSTEMDASHBOARD_DB_CONNECT_TIMEOUT`, `SYSTEMDASHBOARD_DB_STATEMENT_TIMEOUT`, and `SYSTEMDASHBOARD_DB_CIRCUIT_*`.
- Local Postgres port auto-detection checks configured port first, then fallbacks via `SYSTEMDASHBOARD_DB_PORT_FALLBACKS` or `Database.PortFallbacks`.
- Service restart backoff and crash history live in `var/log/dashboard-crash-history.log`; adjust with `SYSTEMDASHBOARD_RESTART_*`.
- Listener/service logs: `var/log/dashboard-listener.log`, `var/log/dashboard-ui.log`, and per-run stdout/stderr `dashboard-listener-*.out.log` / `dashboard-listener-*.err.log`.
- Optional structured logs and rotation via `SYSTEMDASHBOARD_LOG_FORMAT`, `SYSTEMDASHBOARD_LOG_MAX_MB`, `SYSTEMDASHBOARD_LOG_MAX_FILES`, `SYSTEMDASHBOARD_SERVICE_LOG_MAX_MB`, and `SYSTEMDASHBOARD_SERVICE_LOG_MAX_FILES`.

## Documentation

- Deployment guide: [DEPLOYMENT.md](./DEPLOYMENT.md)
- Current working configuration: [CURRENT_CONFIGURATION.md](./CURRENT_CONFIGURATION.md)
- Lessons learned: [LESSONS_LEARNED.md](./LESSONS_LEARNED.md)
- Portfolio summary: [PORTFOLIO.md](./PORTFOLIO.md)
- Change log: [CHANGELOG.md](./CHANGELOG.md)
- Legacy and in-depth references are preserved under `docs/_Archive/` and `docs/archive/legacy/`.
- Retired helper scripts remain available under `scripting/_Archive/`.

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
   ```
   Import-Module .\scripting\SystemDashboard.Scripting.psm1 -Force
   ```
4. Install dependencies:
   ```
   Install-SystemDashboard -ConfigPath .\config.json
   ```
5. Initialize the database:
   - Local Postgres: `Initialize-SystemDashboardDatabase`
   - Docker Postgres: `Initialize-SystemDashboardDockerDatabase`
6. Launch the dashboard:
   ```
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

## Documentation
- Deployment guide: [DEPLOYMENT.md](./DEPLOYMENT.md)
- Current working configuration: [CURRENT_CONFIGURATION.md](./CURRENT_CONFIGURATION.md)
- Lessons learned: [LESSONS_LEARNED.md](./LESSONS_LEARNED.md)
- Portfolio summary: [PORTFOLIO.md](./PORTFOLIO.md)
- Change log: [CHANGELOG.md](./CHANGELOG.md)
- Legacy and in-depth references are preserved under `docs/_Archive/` and `docs/archive/legacy/`.
- Retired helper scripts remain available under `scripting/_Archive/`.

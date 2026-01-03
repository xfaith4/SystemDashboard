# Current Configuration (Working State)

This captures the working setup that successfully loads telemetry in the legacy and Flask UIs.

## Runtime profile
- Mode: Legacy PowerShell HTTP listener serving `wwwroot/`.
- Entry point: `Start-SystemDashboard.ps1 -Mode Legacy`.
- Listener prefix (from `config.json`): `http://localhost:15000/`.
  - If 15000 is reserved, the listener auto-tries 15001-15009 and logs the chosen prefix.

## Configuration file
The source of truth is `config.json` (used by both PowerShell and Flask). Current values:
- Prefix: `http://localhost:15000/`
- Root: `./wwwroot`
- IndexHtml: `./wwwroot/index.html`
- CssFile: `./wwwroot/styles.css`
- RouterIP: `192.168.50.1`
- Database:
  - Host: `localhost`
  - Port: `5433`
  - Database: `system_dashboard`
  - Schema: `telemetry`
  - Username (ingest): `sysdash_ingest`
  - PasswordSecret: `env:SYSTEMDASHBOARD_DB_PASSWORD`
  - PsqlPath: `C:/Program Files/PostgreSQL/18/bin/psql.exe`

## Secrets and environment variables
The launcher sets these for the UI and API paths:
- `SYSTEMDASHBOARD_CONFIG`: absolute path to `config.json`.
- `SYSTEMDASHBOARD_DB_PASSWORD`: ingest user password (used by collectors).
- `SYSTEMDASHBOARD_DB_READER_PASSWORD`: reader password for dashboards.
- `DASHBOARD_DB_HOST`, `DASHBOARD_DB_PORT`, `DASHBOARD_DB_NAME`, `DASHBOARD_DB_USER`, `DASHBOARD_DB_PASSWORD`: used by Flask and utilities.

If you use `var/database-connection.json`, it should look like this:
```json
{
  "IngestPassword": "REPLACE_ME",
  "ReaderPassword": "REPLACE_ME"
}
```

## Replication steps (fresh clone)
1. Install prerequisites: PowerShell 7, Python 3.10+, and PostgreSQL 14+ (or Docker Desktop).
2. Set secrets (environment variables or `var/database-connection.json`).
3. From repo root, run:
   ```
   pwsh -NoProfile -File .\Start-SystemDashboard.ps1 -Mode Legacy
   ```
4. Open the URL logged by the listener (port may auto-increment).

## Automation-friendly sequence
These are idempotent and safe to re-run:
```
Import-Module .\scripting\SystemDashboard.Scripting.psm1 -Force
Install-SystemDashboard -ConfigPath .\config.json
Initialize-SystemDashboardDatabase
Apply-SystemDashboardLanSchema -ConfigPath .\config.json
Install-SystemDashboardScheduledTask
Manage-SystemDashboardServices -Install
```

## Validation checklist
- `Test-SystemDashboardTelemetryDatabase -ConfigPath .\config.json`
- `GET /api/health` returns `ok: true`
- `GET /api/timeline` returns JSON array (not partial JSON)

## Screenshots
See `docs/screenshots/README.md` for capture guidance and naming.

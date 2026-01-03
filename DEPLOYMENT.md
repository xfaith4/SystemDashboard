# Deployment, configuration, and launch

## Prerequisites
- PowerShell 7+
- Python 3.10+ on PATH
- PostgreSQL 14+ reachable locally **or** Docker Desktop available
- Optional: admin PowerShell session on Windows for scheduled tasks/services

## Prepare the environment
1. Import the module (run from repo root):
   ```
   Import-Module .\scripting\SystemDashboard.Scripting.psm1 -Force
   ```
2. Install dependencies (creates `.venv`, copies modules, registers telemetry task if needed):
   ```
   Install-SystemDashboard -ConfigPath .\config.json
   ```
3. Configure the database:
   - Local PostgreSQL:
     ```
     Initialize-SystemDashboardDatabase
     ```
   - Docker-backed PostgreSQL:
     ```
     Initialize-SystemDashboardDockerDatabase
     ```
4. Optional LAN schema for observability:
   ```
   Apply-SystemDashboardLanSchema -ConfigPath .\config.json
   ```
5. Install the scheduled task (telemetry collector):
   ```
   Install-SystemDashboardScheduledTask
   ```
6. Manage the full service set (legacy UI, LAN collector, syslog collector):
   ```
   Manage-SystemDashboardServices -Install   # or -Status / -Uninstall
   ```

## Launch and verification
- Start the dashboard with preflight checks (known-good legacy path):
  ```
  pwsh -NoProfile -File .\Start-SystemDashboard.ps1 -Mode Legacy [-DatabaseMode docker]
  ```
- If port 15000 is reserved, the listener auto-tries 15001-15009 and logs the chosen prefix.
- Check database connectivity as the reader account:
  ```
  Test-SystemDashboardTelemetryDatabase -ConfigPath .\config.json
  ```
- Run the auto-heal probe (one-time GPT-guided diagnostics):
  ```
  Invoke-SystemDashboardAutoHeal
  ```
- Interactive operations/maintenance menu:
  ```
  Invoke-SystemDashboardControl
  ```

## Configuration notes
- Default config lives at `config.json`. If you create `config.local.json`, the launcher will prefer it automatically.
- Override with `-ConfigPath` where provided.
- Database passwords can be supplied via `SYSTEMDASHBOARD_DB_PASSWORD` / `SYSTEMDASHBOARD_DB_READER_PASSWORD` or `var/database-connection.json`.
- LAN collector dependencies download to `lib/` via `Ensure-SystemDashboardLanDependencies`.

For historical guidance and prior phase notes, see `docs/_Archive/` and `docs/archive/legacy/`.

# SystemDashboard

SystemDashboard ingests system, syslog, and router telemetry and exposes dashboards served by PowerShell or Flask entrypoints. The repository now ships with a single scripting module to keep operational tasks in one place and a trimmed documentation set.

## Quick start
- Import the scripting module:  
  `Import-Module .\scripting\SystemDashboard.Scripting.psm1 -Force`
- Install dependencies (first run):  
  `Install-SystemDashboard -ConfigPath .\config.json`
- Initialize the database (choose your backend):  
  - Local Postgres: `Initialize-SystemDashboardDatabase`
  - Docker Postgres: `Initialize-SystemDashboardDockerDatabase`
- Launch the dashboard:  
  `pwsh -NoProfile -File .\Start-SystemDashboard.ps1 [-DatabaseMode docker]`

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
- Change log: [CHANGELOG.md](./CHANGELOG.md)
- Legacy and in-depth references are preserved under `docs/_Archive/` and `docs/archive/legacy/`.
- Retired helper scripts remain available under `scripting/_Archive/`.

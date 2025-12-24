# System Dashboard Documentation

## Quick start
- From repo root, run `pwsh -NoProfile -File .\Start-SystemDashboard.ps1`.
- The entrypoint performs preflight checks (admin, dependencies, database) and then launches the dashboard.
- Use `-DatabaseMode docker` if you run Postgres in Docker.
- Use `-Mode Unified|Legacy|Flask` to select the dashboard runtime.

## Common tasks
- Install dependencies and register the scheduled task: `pwsh -NoProfile -File .\scripting\Install.ps1`
- Initialize Postgres (local): `pwsh -NoProfile -File .\scripting\setup-database.ps1`
- Initialize Postgres (Docker): `pwsh -NoProfile -File .\scripting\setup-database-docker.ps1`
- Apply LAN schema: `pwsh -NoProfile -File .\scripting\apply-lan-schema.ps1`
- Scheduled task install: `pwsh -NoProfile -File .\scripting\setup-scheduled-task.ps1`
- Service/task manager: `pwsh -NoProfile -File .\scripting\setup-permanent-services.ps1 -Status`

## Docs map
- Setup and dependencies: `docs/SETUP.md`
- Operations and service management: `docs/OPERATIONS.md`
- Architecture and data sources: `docs/REFERENCE.md`
- Legacy material is archived under `docs/archive/legacy/`.

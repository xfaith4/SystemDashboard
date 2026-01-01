# Operations

## Start the dashboard
From repo root:

```
pwsh -NoProfile -File .\Start-SystemDashboard.ps1
```

Optional flags:
- `-DatabaseMode docker` if Postgres runs in Docker
- `-Mode Unified|Legacy|Flask` to choose runtime
- `-SkipPreflight` to skip admin/dependency/db checks

## Scheduled tasks
Install telemetry collection task:

```
pwsh -NoProfile -File .\scripting\setup-scheduled-task.ps1
```

Start/stop:

```
Start-ScheduledTask -TaskName 'SystemDashboard-Telemetry'
Stop-ScheduledTask -TaskName 'SystemDashboard-Telemetry'
```

## Permanent services helper
Use the dashboard control script for status and health checks:

```
pwsh -NoProfile -File .\scripting\dashboard-control.ps1
```

## Logs
Common log locations:
- `var/log/telemetry-service.log`
- `var/log/lan-collector.log`
- `var/log/syslog-collector.log`

## Action engine (MVP)
Queue and approve actions via the Flask API:

```
POST /api/v1/actions
POST /api/v1/actions/{id}/approve
POST /api/v1/actions/{id}/execute
```

Configured via `config.json` under `Actions` (safe allowlist + approval gates).

## Troubleshooting quick hits
- Database failures: run `pwsh -NoProfile -File .\scripting\setup-database.ps1` and re-check.
- Missing credentials: ensure `SYSTEMDASHBOARD_DB_PASSWORD` is set or `var/database-connection.json` exists.
- Port conflicts: verify `config.json` ports are free and rerun.

## Verify telemetry ingestion
Check whether syslog/events/metrics rows are landing in Postgres:

```
pwsh -NoProfile -File .\scripting\Check-TelemetryDatabase.ps1
```

If Postgres shows 0 rows but `telemetry-service.log` shows lots of “Syslog message #…”, you likely have the minimal telemetry listener still running (it logs but doesn’t insert). Find what owns the UDP port and stop it:

```
Get-NetUDPEndpoint -LocalPort 5514 | Select-Object LocalAddress,LocalPort,OwningProcess
Get-Process -Id (Get-NetUDPEndpoint -LocalPort 5514).OwningProcess
```

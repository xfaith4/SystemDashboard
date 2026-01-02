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
- `-RestartTasks` to stop/start scheduled tasks before launch

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

## LAN collector dependencies
The LAN collector needs `Npgsql.dll` and related assemblies. Setup scripts call `scripting/setup-lan-collector-deps.ps1` during install, but you can run it manually if needed:

```
pwsh -NoProfile -File .\scripting\setup-lan-collector-deps.ps1
```

## Logging config
`config.json` includes a top-level `Logging.LogLevel` (default `INFO`). The LAN collector also reads `Service.LogLevel` as a fallback.

## Auto-heal (startup suggestion check)
When the legacy UI scheduled task starts, it runs a one-time health check. If `/api/health` reports a failure and `OPENAI_API_KEY` is set, it sends a redacted context bundle to GPT and writes the response to `var/log/auto-heal-response.json`.

Environment toggles:
- `OPENAI_API_KEY` (required to send a GPT request)
- `SYSTEMDASHBOARD_AI_ENDPOINT` (optional, default: `https://api.openai.com/v1/chat/completions`)
- `SYSTEMDASHBOARD_AI_MODEL` (optional, default: `gpt-4o-mini`)
- `SYSTEMDASHBOARD_AUTOHEAL_ENABLED` (set to `false` to disable)

Manual run:

```
pwsh -NoProfile -File .\scripting\auto-heal.ps1
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

## Router KPI summary
Syslog ingestion generates a rolling KPI summary at:
- `var/syslog/router-kpis.json`

The legacy UI reads it via:
- `GET /api/router/kpis`

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

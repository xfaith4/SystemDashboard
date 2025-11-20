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

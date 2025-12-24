# Consolidation status

Current canonical build: `2025-09-11/` (PowerShell 7 + Pode + SQLite/Postgres option). Use `Start-SystemDashboard.Unified.ps1` from repo root.

Ready now
- Unified entrypoint that imports `2025-09-11/modules/SystemDashboard.psd1` and uses its `config.json`.
- Root README points to the canonical stack and explains layout.
- Legacy README conflict in `SystemDashboard-1` resolved; `.gitignore` added to cut noise from archives/IDE output.
- WindSurf telemetry service vendored under `telemetry/` with a config shim; when `telemetry.enabled=true` the Pode API serves `/api/syslog` from Postgres instead of local SQLite.
- Gemini Event Log Explorer relocated into `tools/EventLogExplorer/` under the canonical repo (source + publish artifacts).
- Telemetry tightened: psql connectivity is verified at startup; syslog ingestion has retry/backoff; Pode falls back to local store if Postgres is unreachable.

To merge next
- Decide how to surface the Gemini C# Event Log Explorer (embed as a feature/API or ship as companion). Align ports/secrets.
- Remove duplicate UIs/listeners under `wwwroot/`, `SystemDashboard-1/`, and `WindSurf/app` once feature parity is confirmed.
- Add CI smoke (Pester for Pode API/SSE) and lint/build checks for whichever C#/Python pieces survive the merge.

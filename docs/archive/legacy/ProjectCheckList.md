Here’s what’s left at the root and how it could fold into the canonical SystemDashboard/:

Observability stack bits (Prometheus/Loki/promtail/eventlog exporter): prometheus.yaml, loki-local-config.yaml, promtail-local-config.yaml, eventlog-exporter.ps1, setup-eventlog-exporter.ps1, start-eventlog-exporter.ps1, start-observability-stack.ps1, start-up.ps1, setup.ps1. These can be tucked under SystemDashboard/tools/observability/ with a README and sample configs.
Router/client utilities: Backup-ASUSRouter.ps1, RouterClientList/ (likely router inventory), could become SystemDashboard/tools/router/ if still useful.
Health scripts: Generate-SystemHealthReport.ps1, Get-NVIDIAETWsession.ps1, All Active IPs.ps1, FindEmptyDirectories.ps1, duplicates4.ps1 — consider a SystemDashboard/tools/scripts/ folder and document them, or leave in _archive if not essential.
Syslog-Parser/: could be a supporting tool and lives under SystemDashboard/tools/syslog-parser/ or in_archive if obsolete.
UniversalDashboard/: old dashboard scaffold; likely archive unless you want a reference.
3rdPartyTools/: leave as-is; not part of the core code.
windows_exporter/: existing exporter; can stay separate, just note it in docs.
data/, Network/, HTMLFun/, nmap/, promlens/: appear ancillary; keep in_archive unless needed.
If you want a project plan to track consolidation + enhancements, here’s a concise, actionable one (you can paste into an issue or task tracker):

Milestone: Codebase consolidation

Move remaining runtime scripts into the repo: create SystemDashboard/tools/observability/ and place prometheus*.yaml, loki-local-config.yaml, promtail-local-config.yaml, eventlog-exporter.ps1, setup-eventlog-exporter.ps1, start-eventlog-exporter.ps1, start-observability-stack.ps1, start-up.ps1, setup.ps1 there with a short README.
Router/utility scripts: create SystemDashboard/tools/router/ for Backup-ASUSRouter.ps1 and any RouterClientList outputs; create SystemDashboard/tools/scripts/ for misc helpers (Generate-SystemHealthReport.ps1, Get-NVIDIAETWsession.ps1, All Active IPs.ps1, FindEmptyDirectories.ps1, duplicates4.ps1), or move them to _archive if they’re not needed.
Syslog-Parser/ and UniversalDashboard/: move to_archive unless you want to integrate them; if integrating, place under SystemDashboard/tools/ with a README.
Update SystemDashboard/README.md to list the tools folders and note that _archive/ holds everything else.
Milestone: Telemetry hardening
5) Add a simple /api/telemetry/health in Pode that reports whether Postgres telemetry is being used and last ingestion status.
6) Add retry/backoff logging and a small status file/log for telemetry ingestion in telemetry/.
7) Provide a one-line script/README snippet to apply telemetry/schema.sql and verify connectivity.

Milestone: CI/tests
8) Add Pester smoke tests for /healthz, /api/metrics, /api/syslog (telemetry on/off cases).
9) Add a lightweight build step for tools/EventLogExplorer if it stays as a companion (dotnet publish validation).

Milestone: UX/feature alignment
10) Decide whether to embed Event Log Explorer into the Pode UI or keep as a companion tool; update docs accordingly.
11) Prune duplicate legacy UIs (wwwroot/ stub, archive-only UIs) once feature parity is confirmed.

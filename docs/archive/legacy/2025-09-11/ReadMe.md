# System Monitor WebApp (PowerShell 7 + Pode)

A lean, local-first monitoring web app that pulls **Windows Event Logs**, **live system metrics**, **router clients**, and **syslogs** — and can **Ask AI** (OpenAI) for concise remediation advice with PII redaction.

## Why this approach
- **Small footprint**: PowerShell 7 + Pode, no Node/SPA build.
- **Safe defaults**: Binds to `127.0.0.1:5000`, strict-ish headers, AI endpoint requires API key.
- **Batteries included**: SQLite for events/syslog, SSE for live metrics, provider model for routers.

## Quick start
```powershell
# 1) Pre-req: PowerShell 7+, Pode
Install-Module Pode -Scope CurrentUser

# 2) Clone and run
pwsh -NoProfile -File .\Start-SystemDashboard.ps1

# 3) Browse
# http://127.0.0.1:5000

Configuration

Edit config.json (env vars override):

Key	Description
http.bind / http.port	Default 127.0.0.1:5000
database.kind	sqlite (default) or postgres (stub)
database.sqlitePath	Path to .db file
router.provider	AsuswrtSsh (default) or GenericSnmp
router.host/port/user	Router access parameters
syslog.paths	Glob(s) for SolarWinds logs
syslog.enableUdp	false by default; set true to enable UDP 514
ai.apiKey	Required for /api/ai/assess
Env overrides	MON_PORT, MON_BIND, MON_DB, POSTGRES_CONN_STRING, OPENAI_API_KEY, ROUTER_*

Feature flags ready for refinement: postgres_optional, syslog_udp_optional.

Endpoints

GET /healthz – process is up

GET /readyz – DB reachable

GET /api/events?log=System&level=Error&since=PT24H&skip=0&take=200

GET /api/metrics – snapshot

GET /api/router/clients

GET /api/syslog?host=&severity=&since=PT1H

GET /stream/metrics – SSE stream emitting {cpuPct, memPct, tcpCount, ...} every 2s

POST /api/ai/assess – body: { "lines": ["..."] }, header: X-API-Key: <value>

Security hardening

Keep default localhost bind. For LAN access, reverse-proxy with TLS (IIS/NGINX) and add auth.

Rotate logs/app.log via OS scheduler or logrotate-style job.

Use a unique X-API-Key for /api/ai/assess. Do not expose publicly.

Windows Service (optional)

Install NSSM (recommended) or use sc.exe:

.\scripts\Install-WindowsService.ps1

Troubleshooting

Pode not found: Install-Module Pode -Scope CurrentUser

SQLite assembly: On most PS7 installs, Microsoft.Data.Sqlite is present. If not, install .NET package or place the assembly side-by-side.

Router provider:

AsuswrtSsh: requires ssh.exe and router shell enabled (read-only commands).

GenericSnmp: requires snmpwalk.exe in PATH.

Syslog: Ensure syslog.paths points to SolarWinds Free Syslog Server files.

Tests
Invoke-Pester .\tests\Pester.Tests.ps1

License

MIT (local use focus).

### END FILE

### BEGIN FILE: Start-SystemDashboard.ps1
```powershell
# Convenience entrypoint so you can run: pwsh -NoProfile -File .\Start-SystemDashboard.ps1
Import-Module "$PSScriptRoot\modules\SystemDashboard.psd1" -Force
$cfgPath = Join-Path $PSScriptRoot 'config.json'
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
# Create data dir if needed
$dir = Split-Path -Parent $cfg.database.sqlitePath
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
Start-SystemDashboard -Config $cfg


Whats ready vs. what to refine next

✅ Ready now: Local-first server, SSE live metrics, event/syslog storage (SQLite), router clients via ssh/snmpwalk, AI endpoint w/ redaction + API key, dark UI with HTMX, health endpoints, service installer, basic tests.

🧩 Suggested next passes (your prompt already planned these):

Postgres option via Npgsql + migrations and /readyz DB health.

WebSocket alternative to SSE (reconnect/backoff on the client).

Auth & roles (cookie auth for UI, API key for write routes).

Observability: internal counters /metrics + Overview status widget.

More robust syslog UDP with a thread-safe queue → DB writer.
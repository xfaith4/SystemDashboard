# Deployment & Analytics Readiness Review

**Date:** December 16, 2025 (review date)  
**Scope:** Code-level review of deployment posture, dashboard analytics quality, LAN/syslog value, and OpenAI-assisted guidance.

## Deployment Process Posture
- **Stack:** PowerShell ingestion services (`services/*`), SQLite storage (`var/system_dashboard.db`), Flask analytics UI (`app/app.py`), and static dashboard fallback (`wwwroot/`).
- **Bootstrap:** `scripts/Launch.ps1` orchestrates environment, database init, install, and scheduled tasks; `scripts/setup-database.ps1`/`scripts/init_db.py` handle schema creation; `Start-SystemDashboard.ps1`/`start-dashboard.bat` host the UI.
- **Production steps:** Covered in `docs/DEPLOYMENT.md` and `scripts/setup-permanent-services.ps1` (services + scheduled tasks). No additional build artifacts are required beyond Python/PowerShell dependencies.

## Front Dashboard Analytics - Market Monitoring Parity
- **What's implemented:** IIS 5xx spike detection, auth burst detection, Windows critical/error surfacing, router/syslog anomaly pulls (`syslog_recent`), LAN device inventory with snapshots/tags, health scoring, and 7-day trend lines with fallback mock data.
- **Data sources:** SQLite-backed views (`iis_requests_recent`, `eventlog_windows_recent`, `syslog_recent`, `lan_*`) with graceful mock mode when the DB is absent so the UI stays usable.
- **Gaps vs. typical market monitoring tools:** Limited alerting/escalation, no multi-tenant RBAC, and statistical baselines are simplified (no stddev on SQLite). Long-term retention/rollups rely on upstream jobs rather than continuous aggregation services.
- **Verdict:** Fit for small-scale ops/home lab monitoring with actionable visuals; not equivalent to enterprise APM/market surveillance platforms without added alerting, baselining, and retention controls.

## LAN Insight via Router Syslogs & Configuration Anomalies
- **Router coverage:** `/api/router/logs` with filtering/sorting/pagination and `/api/router/summary` parsing WAN drops, IGMP drops, Wi-Fi events, rstats/UPnP signals.
- **LAN observability:** LAN collector schema (`lan_observability-schema.sql`) plus device snapshots/tags exposed through the Flask endpoints and LAN pages; mock data preserves UX when offline.
- **Value:** Provides clear per-device and per-event drill-down for home/SMB LANs; anomaly depth depends on router/syslog richness and database freshness.

## OpenAI Suggestion Capability
- **Implemented APIs:** `/api/ai/suggest` (event-specific suggestions) and `/api/ai/explain` (router log / Windows event / chart summaries) in `app/app.py`.
- **Config:** Requires `OPENAI_API_KEY` (and optional `OPENAI_MODEL`/`OPENAI_API_BASE`); graceful fallback text is returned when the key is absent.
- **Usage:** Endpoints accept JSON payloads and return HTML-safe explanations/severity plus recommended actions; designed to surface stability/security improvements.

## Recommendations (Minimal to Proceed)
1. Ensure production runs set `OPENAI_API_KEY` and database path (`DASHBOARD_DB_PATH`) so analytics render real data instead of mock summaries.
2. Add alerting/webhook layer if parity with commercial monitoring is needed (beyond current UI-driven insights).
3. Keep SQLite views refreshed and LAN collector scheduled to maintain high-fidelity LAN/router insights.

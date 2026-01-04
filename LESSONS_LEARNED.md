# Lessons Learned

## What worked

- Centralizing the database configuration in `config.json` and reading it from both PowerShell and Flask removed config drift.
- Verifying database connectivity early (`app/test_db_connection.py`) saved time chasing UI symptoms.
- Adding listener port fallback kept the legacy UI available even when port 15000 was reserved.

## Pain points and fixes

- Mixed config sources caused Flask to fall back to SQLite while the legacy listener used Postgres.
- `psql` JSON output can span multiple lines; returning only the first line produced invalid JSON and broke the timeline.
- StrictMode exposed scalar `.Count` access; avoiding `.Count` on scalars prevented runtime crashes.
- HttpListener conflicts on `http://localhost:15000/` required either URL ACL cleanup or automatic port retry.

## Process improvements

- Run `Start-SystemDashboard.ps1 -Mode Legacy` until Unified dependencies (like Pode) are installed.
- Keep secrets in env vars or `var/database-connection.json`; avoid embedding passwords in config files.
- Treat the console log as the source of truth for the final bound port and document it.

## Follow-up ideas

- Capture a known-good "golden path" runbook and keep it in sync with `config.json`.
- Add a small health check script for `/api/health` + `/api/timeline` to validate UI expectations.
- Optionally persist the chosen prefix to `var/ui-prefix.txt` for automation and tooling.

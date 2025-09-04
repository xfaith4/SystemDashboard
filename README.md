# System Dashboard

A lightweight system dashboard with a Flask-based web interface.

## Features
- Primary dashboard with navigation to drill-down panels.
- System events and router log drill-down pages.
- Wi-Fi client list highlighting chatty nodes.

## Development
```bash
pip install flask
python app/app.py
```
Visit `http://localhost:5000` in your browser.
SystemDashboard - Enhanced

Overview
- Flask UI for viewing system events, router logs, and Wi‑Fi clients.
- PowerShell listener for lightweight metrics at `http://localhost:<port>/metrics` used by tests.
- New: Interactive event log search/filter, quick insights, and OpenAI suggestions for fixes.

Run the Flask app
- Install Python 3.10+ and Flask (`pip install flask`).
- Set env var `OPENAI_API_KEY` to enable AI suggestions (optional).
- Start: `python app/app.py` then open `http://localhost:5000`.

Event Logs (Windows)
- The Events page loads Windows Application/System logs via PowerShell when running on Windows.
- If not on Windows or PowerShell fails, sample data is shown.

OpenAI Suggestions
- Set `OPENAI_API_KEY` and optionally `OPENAI_MODEL` (default `gpt-4o-mini`) and `OPENAI_API_BASE`.
- Click “Ask AI” on an event row to get probable causes and fixes.

PowerShell Listener
- Tests expect a function `Start-SystemDashboardListener` exported from `Start-SystemDashboard.ps1`.
- Helper functions `Ensure-UrlAcl` and `Remove-UrlAcl` are included for HTTP.sys URL ACLs.
- Sample usage:
  - `$prefix = 'http://localhost:15000/'`
  - `$root = "$PWD/wwwroot"; New-Item -ItemType Directory $root -Force | Out-Null`
  - `Set-Content "$root/index.html" '<html></html>'`
  - `Set-Content "$root/styles.css" 'body{}'`
  - `Start-SystemDashboardListener -Prefix $prefix -Root $root -IndexHtml "$root/index.html" -CssFile "$root/styles.css"`

Notes
- Network access is required for OpenAI suggestions.
- The UI includes client-side filtering; server endpoint `/api/events` supports a `level` query param.

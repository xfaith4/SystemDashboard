# System Dashboard

A lightweight operations telemetry stack. The repository ships with two entry points:

- **PowerShell HTTP listener** (`Start-SystemDashboard.ps1`/`.psm1`) that exposes system metrics and serves the static dashboard at the configured prefix (defaults to `http://localhost:15000/`).
- **Flask development UI** (`app/app.py`) for iterating on the web experience and experimenting with additional data sources or AI assisted insights.

The default dashboard lives in `wwwroot/` and renders CPU, memory, disk usage, event log summaries, top processes, and network throughput by calling the listener's `/metrics` endpoint.

## Repository layout

| Path | Purpose |
| --- | --- |
| `Start-SystemDashboard.ps1` | Bootstrap script that imports the module and respects `config.json`. |
| `Start-SystemDashboard.psm1` | PowerShell module exporting the listener and helper functions. |
| `wwwroot/` | Static HTML/CSS/JS served by the listener. |
| `config.json` | Listener configuration (prefix, static root, ping target, router IP, …). |
| `app/` | Flask app used for richer UI/AI experiments. |
| `tests/` | Pester tests for the PowerShell module. |

## Prerequisites

- Windows with PowerShell 7+ for the HTTP listener and system metrics.
- Administrator rights the first time you bind to a new HTTP prefix (needed for HTTP.sys URL ACLs).
- Python 3.10+ if you want to run the optional Flask app.

## Run the PowerShell dashboard listener

1. Open a PowerShell 7 prompt.
2. Clone or download this repository and change into the root directory.
3. On first launch run as Administrator so the script can reserve the HTTP prefix.
4. Start the listener:
   ```powershell
   pwsh -File .\Start-SystemDashboard.ps1
   # or
   Import-Module .\Start-SystemDashboard.psm1
   Start-SystemDashboard
   ```
5. Browse to the configured prefix (default `http://localhost:15000/`). You should see live metrics refreshing every five seconds.
6. Press `Ctrl+C` to stop the foreground session. To run it in the background you can use `Start-Job` or register a scheduled task/service once you are satisfied with the configuration.

The listener automatically:
- Registers the URL ACL on Windows via `Ensure-UrlAcl`.
- Serves `wwwroot/index.html`, `wwwroot/styles.css`, `wwwroot/app.js`, and any additional files in that directory tree.
- Responds to `/metrics` with JSON containing CPU, memory, disk, uptime, network, process, and recent event log summaries.

### Configuration

`config.json` drives the listener. All path values can be absolute or relative to the configuration file itself (the module normalises them internally).

```json
{
  "Prefix": "http://localhost:15000/",
  "Root": "./wwwroot",
  "IndexHtml": "./wwwroot/index.html",
  "CssFile": "./wwwroot/styles.css",
  "PingTarget": "1.1.1.1",
  "RouterIP": "192.168.50.1"
}
```

| Setting | Description |
| --- | --- |
| `Prefix` | HTTP prefix the listener binds to. Override with the `SYSTEMDASHBOARD_PREFIX` environment variable. |
| `Root` | Directory containing static assets. Override with `SYSTEMDASHBOARD_ROOT`. |
| `IndexHtml`, `CssFile` | Optional overrides if your static files use non-default names. |
| `PingTarget` | Target for latency checks reported on the dashboard. |
| `RouterIP` | Used by `Get-RouterCredentials` when interacting with the router helper functions. |

## Run the Flask development server (optional)

The Flask app offers a richer, extensible UI that can call into the same data sources.

```bash
python -m venv .venv
source .venv/bin/activate  # On Windows use: .venv\Scripts\Activate.ps1
pip install -r requirements.txt
python app/app.py
```

- The app listens on port `5000` by default. Change it with the `DASHBOARD_PORT` environment variable.
- Set `OPENAI_API_KEY` (and optionally `OPENAI_MODEL`/`OPENAI_API_BASE`) to enable AI-generated remediation suggestions inside the Events view.

Browse to `http://localhost:5000/` to view the Flask UI.

## Tests

Pester tests for the PowerShell module live in the `tests/` directory. Run them with:

```powershell
pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path tests"
```

Some tests are skipped on non-Windows hosts because they rely on Windows-specific cmdlets.

## Troubleshooting

- If the listener fails to start with an `Access is denied` error, rerun PowerShell as Administrator so the URL ACL can be created, or choose an unreserved prefix by editing `config.json`.
- To adjust the dashboard look and feel, edit the files in `wwwroot/`. The listener automatically serves new assets without requiring changes to the PowerShell module.
- When running on a workstation without real data, the dashboard may show zeros or placeholders; populate the backing metrics by generating load or ingesting logs as described in the project goals.

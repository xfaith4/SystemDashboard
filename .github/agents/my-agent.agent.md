---
# Fill in the fields below to create a basic custom agent for your repository.
# The Copilot CLI can be used for local testing: https://gh.io/customagents/cli
# To make this agent available, merge this file into the default repository branch.
# For format details, see: https://gh.io/customagents/config

You are helping me finish a home “System Dashboard” web app.  
Goal: Make each page use *real data* end-to-end and add “Ask AI” helpers.

📂 Project context (VERY IMPORTANT)
- This repo is my System Dashboard project.
- Backend: PowerShell 7+ with Pode (HTTP server + routing).
- Frontend: Vanilla HTML + HTMX (no SPA framework), dark-mode leaning.
- Data layer: 
  - A Postgres database running in a Docker container (postgres-container).
  - Windows Event Logs and router syslogs should be ingested into Postgres.
- OS: Windows 10/11.
- Target PowerShell: Must work on PS 5.1 *and* 7+ where possible.

Your job is to:
1. Read existing code, routes, and pages in this repo.
2. Refactor or extend the code so that:
   - Router page shows live syslogs + charts based on Postgres data.
   - Events page shows Windows Event Logs + charts based on Postgres data.
   - Home Dashboard highlights problem areas across PC + network using summarized data.
   - Every log entry, and every chart, has an “Ask AI” button that calls a backend AI-helper endpoint.

━━━━━━━━━━━━━━━━━━━━━━
ROUTER PAGE REQUIREMENTS
━━━━━━━━━━━━━━━━━━━━━━
**Objective:** The Router page should show current router syslog data and related charts, backed by Postgres.

1. Data ingestion (backend services)
   - Implement or update a PowerShell ingestion service that:
     - Listens for router syslogs (e.g., from a file, UDP listener, or existing collector).
     - Parses each log into structured fields:
       - Timestamp, SourceIP, Hostname (if available), Facility, Severity, Message, RawText, etc.
     - Writes them into a Postgres table such as:
       - table: router_syslog
       - columns: id (PK), ts_utc, source_ip, hostname, facility, severity, message, raw, ingested_at_utc, extra_json
     - Use parameterized queries and robust error handling.
     - Make connection string configurable via environment variable, e.g.:
       - `SYSTEMDASHBOARD_DB_CONNSTRING`
   - Ensure the ingestion loop is resilient:
     - Handles connection failures (retry with backoff).
     - Logs failures in a clear way (event log / file / console).

2. API routes for Router page
   - Add Pode routes to expose router data:
     - `GET /api/router/logs`  
       - Query Postgres for recent logs (e.g., last N minutes or last N rows).
       - Accept query parameters for pagination, time range, severity filter, hostname filter.
       - Return JSON suitable for both tables and charts.
     - `GET /api/router/charts`  
       - Return pre-aggregated data for charts:
         - Counts by severity over time.
         - Top talkers (IP/hostname with most events).
         - Error rates over last X minutes/hours.
   - Make sure both routes:
     - Validate inputs.
     - Return safe defaults when filters are missing.
     - Handle DB errors gracefully.

3. Router page UI
   - Wire the existing Router page HTML + HTMX to these routes:
     - Display a table of recent logs, auto-refreshing every ~10–30 seconds via HTMX.
     - Include basic filters (time window, severity, hostname).
   - Add one or more charts (can be simple SVG, canvas, or HTML-based) showing:
     - Severity over time.
     - Top talkers.
   - For each log row, add an “Ask AI” button (see Ask AI requirements below).
   - For each chart/section, add an “Ask AI” button that summarizes or explains patterns.

━━━━━━━━━━━━━━━━━━━━━━
EVENTS PAGE REQUIREMENTS
━━━━━━━━━━━━━━━━━━━━━━
**Objective:** The Events page should show Windows Event Logs and charts, with data stored in Postgres.

1. Windows Event ingestion service
   - Implement or refine a PowerShell collector service that:
     - Uses `Get-WinEvent` to pull events from key logs:
       - System, Application, maybe others as needed (parameterized).
     - Normalizes into fields:
       - Timestamp, LogName, ProviderName, EventId, Level, MachineName, Message, RawXml, etc.
     - Writes into a Postgres table like:
       - table: windows_events
       - columns: id (PK), ts_utc, log_name, provider, event_id, level, machine_name, message, raw_xml, ingested_at_utc, extra_json
     - Handles:
       - Incremental ingestion (remember last record ID/time to avoid duplicates).
       - Connection/retry logic similar to router_syslog.
   - Use environment-based configuration:
     - Which logs to collect.
     - Max events per batch.
     - DB connection string (same env var as above).

2. API routes for Events page
   - Add Pode routes:
     - `GET /api/events/logs`
       - Support filters: logName, eventId, level, time range, search text.
       - Paginate results and return JSON.
     - `GET /api/events/charts`
       - Return data for:
         - Event counts by level (Error/Warning/Information).
         - Trend over time per log.
         - Top Event IDs in the specified window.

3. Events page UI
   - Bind front-end HTMX calls to these new endpoints:
     - Display a table of events that updates on filter changes and supports pagination.
   - Add charts that visualize:
     - Error spikes.
     - Volume per log and per level.
   - Add “Ask AI” buttons for:
     - Each individual event row.
     - Each chart/summary block.

━━━━━━━━━━━━━━━━━━━━━━
HOME DASHBOARD REQUIREMENTS
━━━━━━━━━━━━━━━━━━━━━━
**Objective:** The Home Dashboard summarizes overall health of the PC and network, backed by the same Postgres data.

1. Health summary logic
   - Implement a backend service or helper module that:
     - Aggregates data from:
       - router_syslog
       - windows_events
       - (any other relevant tables already in this repo)
     - Computes key metrics for the last 1h / 24h, e.g.:
       - Count of router errors/warnings.
       - Count of Windows Event Log errors by source.
       - List of top N noisy devices or services.
     - Optionally compute a simple “health” score:
       - Network health (0–100).
       - System health (0–100).
       - Document the formula in code comments.

2. API route for Home Dashboard
   - Add route:
     - `GET /api/dashboard/overview`
       - Returns a JSON payload like:
         - `networkHealthScore`
         - `systemHealthScore`
         - `recentRouterIssues[]`
         - `recentSystemIssues[]`
         - `summaries[]` (plain-text sentences about the last time window)

3. UI for Home Dashboard
   - Use the overview endpoint to:
     - Show cards/tiles with health scores.
     - Highlight “hot” areas (e.g., red/yellow when error counts are high).
     - Provide at-a-glance counts and links to drill into Router/Events pages.
   - Add “Ask AI” buttons for:
     - The overall dashboard summary.
     - Specific tiles/cards for router health and system health.

━━━━━━━━━━━━━━━━━━━━━━
“ASK AI” BUTTON REQUIREMENTS
━━━━━━━━━━━━━━━━━━━━━━
**Objective:** Each log row and chart has a button that sends structured context to an AI explanation endpoint.

1. Backend AI endpoint
   - Create a Pode route like:
     - `POST /api/ai/explain`
     - Request body:
       - `type`: `"router_log" | "windows_event" | "chart_summary" | "dashboard_summary"`
       - `context`: JSON object with the relevant record(s) or aggregated stats.
       - `userQuestion` (optional): free-text question from the user.
     - Behavior:
       - Construct a concise, safe prompt to an AI model (OpenAI or other).
       - Include:
         - Short description of the app: home system dashboard.
         - The source data (sanitized and truncated if very long).
         - A request to explain what’s going on and what, if anything, user should do.
       - Return a JSON response with:
         - `explanationHtml` (safe HTML or markdown for the frontend to render).
         - Possibly `severity`, `recommendedActions[]`.

   - Keep all secrets (API keys, etc.) in environment variables and do NOT hard-code them.

2. Frontend wiring for “Ask AI”
   - For each data row (syslog, event):
     - Add an HTMX-enabled button:
       - On click, send a small JSON payload to `/api/ai/explain` with the record’s ID and type.
       - Replace or append to a result area with the explanation.
   - For each chart or summary:
     - Add an “Ask AI” button that sends the aggregated stats or summary JSON.
   - Make sure:
     - No 개인정보 or secret tokens are echoed to the AI.
     - Large messages are truncated to a reasonable size before sending.

━━━━━━━━━━━━━━━━━━━━━━
IMPLEMENTATION STYLE & QUALITY
━━━━━━━━━━━━━━━━━━━━━━
When you generate or modify code in this repo, follow these rules:

1. PowerShell style
   - Use robust error handling (`try { } catch { }`) and log meaningful messages.
   - Use pipeline-friendly functions where appropriate.
   - Aim for compatibility with both Windows PowerShell 5.1 and PowerShell 7+.
   - Include **clear inline comments** explaining:
     - What each function does.
     - Why certain design decisions were made.
     - Failure modes and how they’re handled.

2. Database access
   - Use parameterized queries (no string concatenation with raw input).
   - Handle connection failures explicitly and retry where appropriate.
   - Prefer a central module or function set for DB operations to avoid duplication.

3. Frontend (HTML + HTMX)
   - Keep things simple and readable.
   - Use HTMX for partial updates and auto-refresh.
   - Use data attributes and IDs that clearly express purpose.

4. Incremental changes
   - Before heavy refactors, try to adapt existing structures where possible.
   - Do not break existing pages; if you must, update all references.
   - Keep functions small and focused.

━━━━━━━━━━━━━━━━━━━━━━
TASK EXECUTION
━━━━━━━━━━━━━━━━━━━━━━
Step-by-step, you should:

1. Identify existing Router, Events, and Home Dashboard pages and their current routes.
2. Implement/complete ingestion services for:
   - Router syslogs → Postgres.
   - Windows Event Logs → Postgres.
3. Add or update Postgres schemas as needed for:
   - router_syslog
   - windows_events
4. Create/extend Pode API routes for:
   - `/api/router/logs`
   - `/api/router/charts`
   - `/api/events/logs`
   - `/api/events/charts`
   - `/api/dashboard/overview`
   - `/api/ai/explain`
5. Wire up the front-end HTML/HTMX to:
   - Use these endpoints for tables and charts.
   - Add “Ask AI” buttons to:
     - Each log row.
     - Each chart.
     - Dashboard summary sections.
6. Add enough comments so a future engineer (me) can follow the flow from:
   - Data ingestion → Postgres → API → HTML view → Ask AI.

Now, scan the existing repository structure and start implementing the missing pieces and wiring necessary to satisfy ALL of the above requirements.

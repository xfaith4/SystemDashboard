# LAN Observability Phase – SystemMonitor Repo Prompt

You are an expert PowerShell + Pode + SQLite engineer helping me implement a **LAN Observability** phase inside my existing **SystemMonitor** repository.

I’m running on Windows, using **PowerShell 7+** (with some scripts compatible with 5.1), and the stack for this project is:

- **Backend**: PowerShell 7, Pode (HTTP server + routing).
- **Data store**: SQLite via PowerShell modules.
- **Frontend**: Simple HTML + HTMX / vanilla JS (no SPA build chain).
- **Logging/metrics**: The project already collects Windows Event Logs, syslog, and other telemetry.

Your job is to **extend this existing codebase**, not rewrite it from scratch.

---

## High-level goal for this phase

Implement a **LAN observability layer** focused on my home network, driven primarily from my **Asuswrt-Merlin router** and **local syslogs**. This replaces the old “NetworkTracker reporting” idea, but keeps the database and upgrades it to a time-series/trend-friendly design.

**Core vision:**

- Build a long-lived inventory of all devices that ever appear on my LAN (clients and guests).
- Track **online/offline behavior**, RSSI trends, and Tx/Rx activity per device over time.
- Correlate this device activity with **router syslogs** and other network events.
- Expose the data via a **clean Web UI** in the existing SystemMonitor web app.

This is the **LAN portion of a larger observability project**.

---

## Data sources to use

1. **Router client list (Asuswrt-Merlin)**  
   - Prefer the same data the stock UI uses (e.g., `update_clients.asp` / `originData` object).
   - Extract per-client data such as:
     - IP
     - MAC
     - Host name / nickname
     - Vendor
     - Interface (wired / wireless, band if available)
     - RSSI (signal strength)
     - TxRate / RxRate (current or recent)
     - Any `isWL` / `activity` flags available
   - Access options:
     - HTTP scraping (`Invoke-WebRequest` against router UI, parsing JS/JSON), **or**
     - SSH commands to the router if that’s more reliable on this firmware.
   - Implementation detail: pick the simplest reliable approach that works well inside a scheduled collector script.

2. **Syslog from the router**  
   - The project already ingests syslog (e.g. via a local syslog server).
   - Use the syslog database / files already present in this repo.
   - At minimum, associate syslog events with devices by:
     - MAC or IP where present in the message,
     - Or using existing parsed fields if syslogs are already structured.

---

## Data model requirements (SQLite)

We are **ditching the old NetworkTracker reporting layer** but **keeping and evolving the database backend**.

Create or migrate to a schema that supports:

1. **Devices** (stable inventory)  
   - One row per distinct device (MAC is the main identity).
   - Fields:
     - `DeviceId` (PK, integer)
     - `MacAddress` (unique, normalized format)
     - `PrimaryIpAddress` (last known / preferred)
     - `Hostname`
     - `Nickname`
     - `Manufacturer` / `Vendor`
     - `FirstSeenUtc` (datetime)
     - `LastSeenUtc` (datetime)
     - `IsActive` (boolean or derived)
     - Optional: a JSON or text `Tags` field (guest, IoT, critical, etc.).

2. **DeviceSnapshots** (time-series stats)  
   - One row per device per sample interval.
   - Fields:
     - `SnapshotId` (PK)
     - `DeviceId` (FK to Devices)
     - `SampleTimeUtc` (datetime)
     - `IpAddress` at that moment
     - `Interface` (e.g., `wired`, `2.4GHz`, `5GHz`, etc.)
     - `Rssi` (integer, nullable)
     - `TxRateMbps` (real, nullable)
     - `RxRateMbps` (real, nullable)
     - `IsOnline` (boolean)
     - Optional: `RawJson` or `SourcePayload` for debugging (string).

3. **SyslogEvents** (if not already in schema)  
   - If a syslog table already exists, integrate with it rather than recreate it.
   - At minimum ensure you have:
     - `SyslogId` (PK)
     - `TimestampUtc`
     - `Host` (router)
     - `Message`
     - Parsed fields (facility, severity, program).
   - Add **optional foreign keys or link tables** to associate SyslogEvents with Devices where you can parse a MAC/IP from the message.

4. **Retention**  
   - Implement an optional cleanup job that keeps:
     - Full `DeviceSnapshots` for (configurable) **7 days** by default.
     - Keeps `Devices` indefinitely.
   - Make retention window configurable (e.g., via config file or settings table).

Please implement **idempotent migrations** so that an existing SystemMonitor DB can be updated safely without dropping user data.

---

## Collectors and scheduling

Add a **LAN collector** module that runs periodically (e.g., via a timer, scheduled task, or existing collector scheduler in SystemMonitor).

### New collector responsibilities

1. **Router client snapshot collector**  
   - Poll the router client list on a configurable interval (e.g., every 1–5 minutes).
   - Normalize the router response into a list of objects with:
     - IP, MAC, Hostname, Vendor, Interface, RSSI, TxRate, RxRate, etc.
   - For each object:
     - Upsert a row in `Devices` based on `MacAddress`.
     - Append a row to `DeviceSnapshots` with current stats.
     - Update `Devices.LastSeenUtc` and `PrimaryIpAddress`.
   - Mark `IsActive` based on recent snapshot activity (e.g., if we saw the device within the last N minutes).

2. **Offline detection**  
   - Use `DeviceSnapshots` to determine when a device has likely gone offline.
   - Example: if no snapshots exist for a device in the last N minutes, mark it as offline.
   - Store offline/online state in `DeviceSnapshots.IsOnline` and optionally a derived indicator on `Devices`.

3. **Syslog correlation (phase 1)**  
   - For now, **do not overcomplicate** this step:
     - Parse MAC/IP from syslog messages where easy.
     - When you can match a syslog event to a known Device, store the `DeviceId` in the syslog row or a link table.
   - We’ll use this later in the Web UI to overlay syslog events on device timelines.

4. **Retention**  
   - Implement a periodic cleanup routine:
     - Delete old `DeviceSnapshots` older than N days (default 7).
     - Optionally purge orphaned syslog events if desired (configurable).
   - Make retention policy configurable in a central settings/config file.

---

## Web UI / API requirements

Extend the **existing SystemMonitor web UI** with a dedicated **LAN Observability** section.

### Top-level navigation

- Add a **“LAN / Network”** or similar top-level menu entry.
- Under it, provide at least:
  - **Overview Dashboard**
  - **Devices List**
  - **Device Detail**

### 1. Overview Dashboard

A page that gives me at-a-glance visibility:

- Current **device counts**:
  - Total known devices
  - Currently online vs offline
  - Count by interface (wired, 2.4, 5 GHz, etc.)
- A **table or grid** of currently online devices with:
  - Hostname / Nickname
  - IP
  - MAC
  - RSSI (if Wi-Fi)
  - Tx/Rx rate summary
- A small **“recent issues”** widget:
  - Devices with flapping online/offline state in the last 24h.
  - Devices with very poor RSSI / low TxRate that might indicate trouble.

Use HTMX or simple AJAX calls to refresh sections without reloading the whole page.

### 2. Devices List

A searchable/filterable table of **all devices**, not just online:

- Columns:
  - Hostname / Nickname
  - MAC
  - Primary IP
  - Vendor
  - FirstSeen / LastSeen timestamps
  - Current status (Online / Offline)
  - Interface type last seen
- Filters:
  - Online / Offline
  - Interface (wired / wifi)
  - Manufacturer
- Each row links to **Device Detail**.

### 3. Device Detail

For a single device (by `DeviceId` or `MacAddress`):

- Show device metadata (from `Devices` table).
- Show a **time-series view** for recent period (24h / 7d):
  - RSSI over time (line chart).
  - TxRate/RxRate over time (line or area chart).
  - Online/offline intervals (can be a simple line or colored background).
- Display **recent syslog events** associated with this device:
  - Table: Timestamp, Severity, Message.
- Optionally, mark syslog events on the chart timeline for later refinement.

Charts do not need to be fancy; use something like Chart.js or a simple lightweight chart library if the project already uses one. Prefer minimal dependencies.

Backend should expose data via **JSON endpoints** that the front-end pages can query (e.g. `/api/lan/devices`, `/api/lan/device/{id}/timeline`, `/api/lan/device/{id}/events`).

---

## Coding and style expectations

Please follow these guidelines:

1. **Language / runtime**  
   - PowerShell 7+ as the primary target.
   - Avoid 5.1-only features; keep code compatible where reasonable.
   - Assume Windows host.

2. **PowerShell style**  
   - Use clear, descriptive function names (`Get-LanDeviceSnapshots`, `Invoke-RouterClientPoll`, etc.).
   - Include **inline comments that explain design intent and failure modes**, not just “what this line does”.
   - Handle failures robustly:
     - Timeouts or HTTP errors from the router,
     - JSON parsing failures,
     - SQLite lock / busy issues.

3. **Repo integration**  
   - Scan the **existing SystemMonitor repo structure** before coding.
     - Reuse existing patterns for:
       - Config handling,
       - Database access helpers,
       - Logging,
       - Pode route definitions.
   - Place new LAN collector code in a directory/module that matches the existing conventions (e.g. `modules/LanObservability` or similar, aligned with existing naming).
   - Wire the collector into any existing scheduler or service startup logic already in the repo.

4. **Schema changes**  
   - If there is an existing database module/migration logic, integrate with it.
   - Do NOT assume a clean DB; implement safe migrations (e.g., check if a table/column exists before creating).
   - Provide reasonable defaults but keep retention and polling intervals configurable.

5. **Testing / observability**  
   - Where possible, add small unit/integration tests following whatever testing framework the repo already uses.
   - Add log messages when:
     - Router queries fail,
     - JSON parsing fails,
     - Snapshot writes are skipped or cleaned up.

6. **Iteration approach**  
   - Step 1: Discover current repo layout and any existing network / DB code.
   - Step 2: Propose a short, concrete plan (files to add/modify, modules, routes).
   - Step 3: Implement DB schema/migrations.
   - Step 4: Implement router client collector and integration with DB.
   - Step 5: Implement LAN API endpoints and Web UI pages.
   - Step 6: Wire up retention job and ensure configuration knobs exist.
   - Step 7: Do a quick cleanup pass for naming consistency and comments.

When you create or modify larger files, keep changes understandable and incremental rather than huge refactors. Follow the existing coding style in the repo as much as possible.

---

Use this prompt as your guide and start by inspecting the SystemMonitor repo, then implement the **LAN Observability** phase as described.

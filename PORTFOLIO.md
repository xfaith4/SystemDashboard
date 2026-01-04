# Portfolio Notes

## One-line summary

SystemDashboard is a telemetry ingestion + analytics dashboard for Windows events, syslog, and LAN/router activity, with a PowerShell-backed legacy UI and a Flask analytics UI.

## What this project demonstrates

- End-to-end telemetry pipeline: collection, storage, and visualization.
- Operational scripting: automated setup, scheduled tasks, and health checks.
- Security-aware configuration: secrets via environment variables, not in source.
- Practical troubleshooting: database validation, API health checks, and fallbacks.

## Key features to highlight

- Timeline visualization of LAN events with category breakdowns.
- Device inventory and recent activity summaries.
- Syslog/event summaries with severity and source grouping.
- One-command setup scripts for Postgres and collectors.

## Stack

- PowerShell 7 (collectors, legacy UI)
- Python + Flask (analytics UI)
- PostgreSQL (telemetry storage)
- HTML/CSS/JS (dashboard frontend)

## Screenshots

Place curated screenshots in `docs/screenshots/` and reference them in your portfolio.

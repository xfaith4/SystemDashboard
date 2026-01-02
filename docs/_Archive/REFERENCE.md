# Reference

## Repository layout
- `Start-SystemDashboard.ps1` - single entrypoint with preflight checks
- `scripting/` - operational scripts and service utilities
- `tools/` - PowerShell modules and helper libraries
- `app/` - Flask app (legacy UI)
- `2025-09-11/` - unified Pode-based dashboard module
- `wwwroot/` - static UI assets

## Data sources
- UDP syslog listener (default port 5514)
- ASUS router polling (SSH/HTTP depending on config)
- Windows Event Log (LAN observability)

## Schemas
- PostgreSQL schema: `tools/schema.sql`
- LAN observability additions: `lan-observability-schema.sql`
- SQLite schema (fallback/testing): `tools/schema-sqlite.sql`

## Config highlights
`config.json` contains:
- `Database.Host`, `Database.Port`, `Database.Database`, `Database.Username`, `Database.PasswordSecret`
- `Service.Syslog.Port`, `Service.Syslog.BufferDirectory`
- `Service.Asus.*` for router settings

## API (Flask)
Versioned endpoints under `/api/v1`:
- `GET /api/v1/health`
- `GET /api/v1/incidents`
- `GET /api/v1/events`
- `GET /api/v1/actions`
- `POST /api/v1/actions`

# Setup

## Requirements
- Windows with PowerShell 7+ (Linux/macOS should work for the Python pieces, but scripts target Windows).
- Python 3.10+ available on PATH.
- PostgreSQL 14+ installed locally OR Docker Desktop running PostgreSQL.

## Install dependencies
Run from repo root:

```
pwsh -NoProfile -File .\scripting\Install.ps1
```

This creates `.venv/`, installs Python dependencies, and registers the scheduled task by default.
Use `-UseWindowsService` if you explicitly need the legacy Windows Service.

## Database setup
Local PostgreSQL:

```
pwsh -NoProfile -File .\scripting\setup-database.ps1
```

Docker PostgreSQL:

```
pwsh -NoProfile -File .\scripting\setup-database-docker.ps1
```

The setup scripts store generated passwords in `var/database-connection.json` and set:
- `SYSTEMDASHBOARD_DB_PASSWORD`
- `SYSTEMDASHBOARD_DB_READER_PASSWORD`

## Troubleshooting (PostgreSQL)
If you see `connection refused` to `localhost:5432`, PostgreSQL is not listening on that port.

- Check the Windows service: `Get-Service postgresql*`
- Start it (admin PowerShell): `Start-Service postgresql-x64-18` (adjust version as needed)
- Verify the port: `Test-NetConnection localhost -Port 5432`
- If PostgreSQL listens on a different port, update `config.json` -> `Database.Port`, or use `.\Start-SystemDashboard.ps1 -DatabaseMode docker`.

## Environment variables
Optional but useful:
- `SYSTEMDASHBOARD_ROOT` - repo root path
- `ASUS_ROUTER_PASSWORD` - router credentials for LAN collection

## Config file
Default config lives at `config.json`. The entrypoint accepts `-ConfigPath` to override.

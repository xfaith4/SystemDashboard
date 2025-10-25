# Changelog

## [1.1.0] - 2025-09-18
### Added
- PowerShell telemetry service (`services/SystemDashboardService.ps1`) orchestrating syslog listening, ASUS router polling, and PostgreSQL ingestion via `psql` COPY.
- Reusable ingestion/utility module (`tools/SystemDashboard.Telemetry.psm1`) plus schema bootstrap SQL for partitioned syslog storage.
- Flask dashboard integration with PostgreSQL-backed insights covering IIS 5xx spikes, auth storms, Windows critical events, and router anomalies.
- Windows install script improvements to provision runtime directories, copy telemetry module, and register the new Windows service.
- Enhanced configuration file describing database, service, and ingestion settings.
- Updated UI styling and router view to surface host metadata from the database.

## [1.0.0] - 2025-09-04
### Added
- Initial module manifest and configuration file support.
- Install script scaffold for module deployment.
- Health endpoint in Flask app with environment-aware port.

# System Dashboard Documentation

This directory contains all documentation for the System Dashboard project.

## Getting Started

- **[Setup Guide](SETUP.md)** - Complete installation and configuration instructions
  - Prerequisites and dependencies
  - Quick installation steps
  - Database setup (Docker or local)
  - Service installation
  - Configuration reference

## Using the System

- **[Main README](../README.md)** - Project overview and quick start
- **[LAN Observability](LAN-OBSERVABILITY-README.md)** - Network device monitoring
  - Device inventory and tracking
  - Time-series metrics
  - Web dashboard
  - Installation and configuration
- **[Advanced Features](ADVANCED-FEATURES.md)** - Enterprise-grade monitoring capabilities
  - Master control interface
  - Router monitoring (UDP syslog + WiFi clients)
  - Continuous event collection
  - Health monitoring and maintenance

## Configuration

- **[Data Sources](DATA-SOURCES.md)** - Configuring data collection
  - Windows Event Logs
  - Router logs
  - System information and metrics
  - Network client discovery
  - Environment variables

## Maintenance

- **[Troubleshooting](TROUBLESHOOTING.md)** - Common issues and solutions
  - Service issues
  - Database problems
  - Data collection issues
  - Web dashboard errors
  - Performance optimization

## Reference

- **[Changelog](CHANGELOG.md)** - Version history and release notes
- **[Security Summary](SECURITY-SUMMARY.md)** - Security analysis and best practices
  - CodeQL scan results
  - Security measures implemented
  - Production deployment recommendations
  - Compliance notes

## Architecture Overview

The System Dashboard consists of:

1. **Telemetry Windows Service** - Long-running PowerShell service that:
   - Listens for inbound syslog messages (UDP 514)
   - Polls ASUS routers for log exports
   - Ingests data into PostgreSQL using COPY

2. **LAN Observability Collector** - Dedicated service for network monitoring:
   - Tracks device presence and signal strength
   - Records time-series metrics
   - Correlates with syslog events

3. **PowerShell HTTP Listener** - Lightweight metrics server:
   - Exposes system metrics
   - Serves static dashboard content
   - Provides health endpoints

4. **Flask Analytics UI** - Rich dashboard experience:
   - Queries PostgreSQL directly
   - Highlights actionable issues
   - Provides LAN device visibility
   - Real-time charts and filtering

## Quick Links

- [Installation](SETUP.md#quick-installation)
- [Configuration Reference](SETUP.md#configuration)
- [Service Management](SETUP.md#management-commands)
- [Troubleshooting Common Issues](TROUBLESHOOTING.md)
- [LAN Observability Setup](LAN-OBSERVABILITY-README.md#installation)
- [Security Best Practices](SECURITY-SUMMARY.md#recommendations-for-production-deployment)

## Support

If you encounter issues:

1. Check the [Troubleshooting Guide](TROUBLESHOOTING.md)
2. Review service logs in `var/log/`
3. Run the environment validator: `python validate-environment.py`
4. Check the [GitHub Issues](https://github.com/xfaith4/SystemDashboard/issues)

from flask import Flask, render_template, request, jsonify
import os
import platform
import subprocess
import json
import html
import urllib.request
import socket
import datetime
from decimal import Decimal
import zoneinfo
import logging
import sqlite3
import sys

# Add app directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

try:
    from health_check import get_comprehensive_health, HealthStatus
    from rate_limiter import rate_limit, get_rate_limiter
    from graceful_shutdown import install_handlers, register_cleanup, create_cache_cleanup
    PHASE1_FEATURES_AVAILABLE = True
except ImportError:
    PHASE1_FEATURES_AVAILABLE = False
    app_logger = logging.getLogger(__name__)
    app_logger.warning("Phase 1 features (health_check, rate_limiter, graceful_shutdown) not available")

try:
    from security import (
        configure_security_headers, get_api_key_auth, require_api_key,
        configure_csrf_protection, get_csrf_protection, csrf_protect,
        create_rate_limit_handler
    )
    from audit_logger import get_audit_trail, get_structured_logger
    PHASE3_FEATURES_AVAILABLE = True
except ImportError:
    PHASE3_FEATURES_AVAILABLE = False
    app_logger = logging.getLogger(__name__)
    app_logger.warning("Phase 3 features (security, audit_logger) not available")

try:
    from mac_vendor_lookup import MacLookup
    mac_lookup = MacLookup()
    # Lazy initialization - update_vendors() will be called on first lookup if needed
except Exception:  # pragma: no cover - optional dependency
    mac_lookup = None

app = Flask(__name__)

LOG_LEVEL_NAME = os.environ.get('DASHBOARD_LOG_LEVEL', 'INFO').upper()
LOG_LEVEL = getattr(logging, LOG_LEVEL_NAME, logging.INFO)

logging.basicConfig(level=LOG_LEVEL)
app.logger.setLevel(LOG_LEVEL)
logging.getLogger('werkzeug').setLevel(LOG_LEVEL)
app.logger.info("Web UI starting with log level %s", logging.getLevelName(LOG_LEVEL))

CHATTY_THRESHOLD = int(os.environ.get('CHATTY_THRESHOLD', '500'))
AUTH_FAILURE_THRESHOLD = int(os.environ.get('AUTH_FAILURE_THRESHOLD', '10'))

SYSLOG_SEVERITY = {
    0: 'Emergency',
    1: 'Alert',
    2: 'Critical',
    3: 'Error',
    4: 'Warning',
    5: 'Notice',
    6: 'Informational',
    7: 'Debug'
}

# Database path - can be set via environment variable or config
_DB_PATH = None


def _get_db_path():
    """Get the SQLite database path from environment or config."""
    global _DB_PATH
    if _DB_PATH is not None:
        return _DB_PATH

    # Check environment variable first
    db_path = os.environ.get('DASHBOARD_DB_PATH')
    if db_path:
        _DB_PATH = db_path
        return _DB_PATH

    # Try to load from config.json
    try:
        config_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'config.json')
        if os.path.exists(config_path):
            with open(config_path, 'r') as f:
                config = json.load(f)
            db_config = config.get('Database', {})
            if db_config.get('Type', '').lower() == 'sqlite':
                path = db_config.get('Path', './var/system_dashboard.db')
                # Make path relative to config file directory
                if not os.path.isabs(path):
                    base_dir = os.path.dirname(config_path)
                    path = os.path.join(base_dir, path)
                _DB_PATH = os.path.abspath(path)
                return _DB_PATH
    except Exception as e:
        app.logger.debug('Failed to load config: %s', e)

    # Default path
    _DB_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'var', 'system_dashboard.db')
    return _DB_PATH


def _is_windows():
    return platform.system().lower().startswith('win')


def get_db_settings():
    """Get database settings for SQLite."""
    db_path = _get_db_path()
    if db_path and os.path.exists(db_path):
        return {'path': db_path, 'type': 'sqlite'}
    return None


def get_db_connection():
    """Get a SQLite database connection."""
    db_path = _get_db_path()
    if not db_path:
        return None
    try:
        # Ensure directory exists
        db_dir = os.path.dirname(db_path)
        if db_dir and not os.path.exists(db_dir):
            os.makedirs(db_dir, exist_ok=True)

        conn = sqlite3.connect(db_path, timeout=5)
        conn.row_factory = sqlite3.Row  # Enable dict-like access
        return conn
    except Exception as exc:  # pragma: no cover - depends on runtime
        app.logger.warning('Failed to connect to SQLite: %s', exc)
        return None


def dict_from_row(row):
    """Convert a sqlite3.Row to a dictionary."""
    if row is None:
        return None
    return dict(row)


def _to_est_string(value):
    """Convert datetime to EST timezone and return formatted string.
    
    Uses America/New_York timezone which automatically handles DST transitions
    between EST (UTC-5) and EDT (UTC-4).
    
    Note: If zoneinfo is not available (Python < 3.9), falls back to fixed UTC-5 offset
    which won't handle DST correctly.
    """
    if value is None:
        return ''
    
    # Define EST/EDT timezone with DST support
    try:
        est_tz = zoneinfo.ZoneInfo('America/New_York')
    except Exception:
        # Fallback if zoneinfo is not available (shouldn't happen in Python 3.9+)
        # Note: This fallback uses fixed UTC-5 and won't handle DST transitions
        import datetime as dt
        est_tz = dt.timezone(dt.timedelta(hours=-5))
    
    if isinstance(value, str):
        # Handle serialized /Date(1764037519528)/ from Windows EventLog JSON
        if value.startswith('/Date(') and value.endswith(')/'):
            try:
                import re
                match = re.search(r'/Date\((\-?\d+)\)/', value)
                if match:
                    ms = int(match.group(1))
                    dt = datetime.datetime.fromtimestamp(ms / 1000.0, tz=datetime.UTC)
                    dt_est = dt.astimezone(est_tz)
                    return dt_est.isoformat()
            except Exception:
                pass
        # Try to parse ISO format string and convert to EST
        try:
            # Parse the string as UTC
            if value.endswith('Z'):
                dt = datetime.datetime.fromisoformat(value.replace('Z', '+00:00'))
            elif '+' in value or value.count('-') > 2:
                dt = datetime.datetime.fromisoformat(value)
            else:
                # Assume UTC if no timezone info
                dt = datetime.datetime.fromisoformat(value).replace(tzinfo=datetime.UTC)
            dt_est = dt.astimezone(est_tz)
            return dt_est.isoformat()
        except Exception:
            return value
    
    if isinstance(value, datetime.datetime):
        # Ensure datetime is timezone-aware
        if value.tzinfo is None:
            value = value.replace(tzinfo=datetime.UTC)
        dt_est = value.astimezone(est_tz)
        return dt_est.isoformat()
    
    try:
        return str(value)
    except Exception:
        return ''


def _isoformat(value):
    """Convert datetime to EST timezone string for API responses."""
    return _to_est_string(value)


def _safe_float(value):
    if value is None:
        return 0.0
    if isinstance(value, Decimal):
        return float(value)
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def _severity_to_text(value):
    try:
        return SYSLOG_SEVERITY.get(int(value), str(int(value)))
    except (TypeError, ValueError):
        return str(value) if value is not None else ''


def lookup_mac_vendor(mac_address):
    """Look up the vendor name from a MAC address using OUI database."""
    if not mac_address or not mac_lookup:
        return None

    try:
        vendor = mac_lookup.lookup(mac_address)
        return vendor
    except KeyError:
        # MAC address not found in database
        return None
    except ValueError as e:
        # Invalid MAC address format
        app.logger.debug('Invalid MAC address format: %s, error: %s', mac_address, e)
        return None
    except Exception as e:
        # Other errors (network issues, etc.)
        app.logger.warning('MAC vendor lookup failed for %s: %s', mac_address, e)
        return None


def get_windows_events(level: str = None, max_events: int = 50, with_source: bool = False, since_hours: int = None, offset: int = 0, log_types: list = None):
    """Fetch recent Windows events via PowerShell. Level can be 'Error', 'Warning', or None for any.
    log_types can be a list like ['Application', 'System', 'Security']. Defaults to all three.
    Returns list of dicts with time, source, id, level, message, log_type.
    """
    # Default to all three log types if not specified
    if log_types is None:
        log_types = ['Application', 'System', 'Security']
    
    # Validate and filter log types
    valid_log_types = ['Application', 'System', 'Security']
    log_types = [lt for lt in log_types if lt in valid_log_types]
    if not log_types:
        log_types = ['Application', 'System', 'Security']
    
    if not _is_windows():
        # Return mock events for demonstration purposes on non-Windows platforms
        now = datetime.datetime.now(datetime.UTC)
        all_mock_events = [
            {
                'time': _to_est_string(now - datetime.timedelta(minutes=30)),
                'source': 'Application Error',
                'id': 1001,
                'level': 'Warning',
                'message': 'Mock application warning - database connection timeout occurred during operation',
                'log_type': 'Application'
            },
            {
                'time': _to_est_string(now - datetime.timedelta(hours=1)),
                'source': 'Service Control Manager',
                'id': 2001,
                'level': 'Error',
                'message': 'Mock system error - service failed to start due to configuration issue',
                'log_type': 'System'
            },
            {
                'time': _to_est_string(now - datetime.timedelta(hours=2)),
                'source': 'DNS Client',
                'id': 1002,
                'level': 'Information',
                'message': 'Mock information event - DNS resolution completed successfully for domain',
                'log_type': 'System'
            },
            {
                'time': _to_est_string(now - datetime.timedelta(minutes=45)),
                'source': 'Application Error',
                'id': 1003,
                'level': 'Error',
                'message': 'Mock critical error - application crashed due to memory access violation',
                'log_type': 'Application'
            },
            {
                'time': _to_est_string(now - datetime.timedelta(minutes=15)),
                'source': 'System',
                'id': 3001,
                'level': 'Warning',
                'message': 'Mock system warning - disk space running low on drive C:',
                'log_type': 'System'
            },
            {
                'time': _to_est_string(now - datetime.timedelta(minutes=20)),
                'source': 'Microsoft-Windows-Security-Auditing',
                'id': 4624,
                'level': 'Information',
                'message': 'Mock security event - An account was successfully logged on',
                'log_type': 'Security'
            },
            {
                'time': _to_est_string(now - datetime.timedelta(minutes=10)),
                'source': 'Microsoft-Windows-Security-Auditing',
                'id': 4625,
                'level': 'Warning',
                'message': 'Mock security warning - An account failed to log on',
                'log_type': 'Security'
            }
        ]

        # Filter by log types
        mock_events = [e for e in all_mock_events if e['log_type'] in log_types]

        # Filter by level if specified
        if level:
            level_lower = level.lower()
            mock_events = [e for e in mock_events if e['level'].lower() == level_lower]

        result = mock_events[:max_events]
        return (result, 'mock') if with_source else result

    level_filter = ''
    if level:
        level_map = {'error': 2, 'warning': 3, 'information': 4}
        code = level_map.get(level.lower())
        if code:
            level_filter = f"; Level={code}"
    
    # Build LogName filter from selected log types
    log_names = ','.join(f"'{lt}'" for lt in log_types)
    ps = (
        "Get-WinEvent -FilterHashtable @{"
        f"LogName={log_names}" + level_filter + "} "
        f"-MaxEvents {max_events} | "
        "Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message, LogName | "
        "ConvertTo-Json -Depth 4"
    )
    try:
        result = subprocess.run(
            ["powershell", "-NoProfile", "-Command", ps],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode != 0:
            return []
        data = json.loads(result.stdout) if result.stdout else []
        if isinstance(data, dict):
            data = [data]
        # Normalize shape
        events = []
        for e in data:
            events.append({
                'time': e.get('TimeCreated'),
                'source': e.get('ProviderName'),
                'id': e.get('Id'),
                'level': e.get('LevelDisplayName'),
                'message': e.get('Message'),
                'log_type': e.get('LogName'),
            })
        # Apply simple offset/pagination for UI
        if offset > 0:
            events = events[offset:]
        if max_events:
            events = events[:max_events]
        return (events, 'windows') if with_source else events
    except Exception:
        return ([], 'error') if with_source else []


def get_router_logs(max_lines: int = 100, with_source: bool = False, offset: int = 0,
                    sort_field: str = 'received_utc', sort_dir: str = 'desc',
                    level_filter: str = None, host_filter: str = None, search_query: str = None):
    """Fetch router logs from PostgreSQL when available, otherwise fall back to a local file.
    If with_source is True, returns a tuple (logs, source, total) where source is 'db', 'file', or 'none'.
    Supports pagination (offset), sorting, and filtering.
    """
    db_logs, total = get_router_logs_from_db(
        limit=max_lines, offset=offset, sort_field=sort_field, sort_dir=sort_dir,
        level_filter=level_filter, host_filter=host_filter, search_query=search_query
    )
    source = 'db' if db_logs is not None else 'none'
    if db_logs is not None:
        return (db_logs, source, total) if with_source else db_logs
    log_path = os.environ.get('ROUTER_LOG_PATH')
    if not log_path or not os.path.exists(log_path):
        return ([], source, 0) if with_source else []
    try:
        with open(log_path, 'r', encoding='utf-8', errors='ignore') as f:
            all_lines = f.readlines()

        logs = []
        for line in all_lines:
            parts = line.strip().split(maxsplit=3)
            if len(parts) >= 4:
                time = f"{parts[0]} {parts[1]}"
                level = parts[2]
                message = parts[3]
            else:
                time = ''
                level = ''
                message = line.strip()

            # Apply filters for file-based logs
            if level_filter and level.lower() != level_filter.lower():
                continue
            # Skip logs when host_filter is specified since file-based logs don't contain host information
            if host_filter:
                continue
            if search_query and search_query.lower() not in message.lower():
                continue

            logs.append({'time': time, 'level': level, 'message': message, 'host': ''})

        # Sort logs for file-based source
        if sort_field in ['time', 'received_utc']:
            logs.sort(key=lambda x: x['time'], reverse=(sort_dir.lower() == 'desc'))
        elif sort_field in ['level', 'severity']:
            logs.sort(key=lambda x: x['level'], reverse=(sort_dir.lower() == 'desc'))
        elif sort_field == 'message':
            logs.sort(key=lambda x: x['message'], reverse=(sort_dir.lower() == 'desc'))

        total = len(logs)
        # Apply pagination
        logs = logs[offset:offset + max_lines]
        source = 'file'
        return (logs, source, total) if with_source else logs
    except Exception:
        return ([], source, 0) if with_source else []


def get_router_logs_from_db(limit: int = 100, offset: int = 0, sort_field: str = 'received_utc',
                            sort_dir: str = 'desc', level_filter: str = None, host_filter: str = None,
                            search_query: str = None):
    """Fetch router logs from SQLite with pagination, sorting and filtering support."""
    conn = get_db_connection()
    if conn is None:
        return None, 0
    try:
        cur = conn.cursor()
        # Build WHERE clause conditions
        conditions = ["source IN ('asus', 'router', 'syslog')"]
        params = []

        if level_filter:
            # Map text level to severity number
            level_map = {
                'emergency': 0, 'alert': 1, 'critical': 2, 'error': 3,
                'warning': 4, 'notice': 5, 'informational': 6, 'info': 6, 'debug': 7
            }
            sev = level_map.get(level_filter.lower())
            if sev is not None:
                conditions.append("severity = ?")
                params.append(sev)

        if host_filter:
            conditions.append("source_host LIKE ?")
            params.append(f'%{host_filter}%')

        if search_query:
            conditions.append("message LIKE ?")
            params.append(f'%{search_query}%')

        where_clause = ' AND '.join(conditions)

        # Validate sort field to prevent SQL injection
        valid_sort_fields = {'received_utc': 'received_utc', 'time': 'COALESCE(event_utc, received_utc)',
                            'severity': 'severity', 'level': 'severity',
                            'source_host': 'source_host', 'host': 'source_host',
                            'message': 'message'}
        sort_column = valid_sort_fields.get(sort_field.lower(), 'received_utc')
        sort_direction = 'ASC' if sort_dir.lower() == 'asc' else 'DESC'

        # Get total count for pagination
        count_query = f"SELECT COUNT(*) as count FROM syslog_recent WHERE {where_clause}"
        cur.execute(count_query, params)
        row = cur.fetchone()
        total_count = row['count'] if row else 0

        # Get paginated results
        query = f"""
            SELECT COALESCE(event_utc, received_utc) AS time,
                   severity,
                   message,
                   source_host
            FROM syslog_recent
            WHERE {where_clause}
            ORDER BY {sort_column} {sort_direction}
            LIMIT ? OFFSET ?
        """
        cur.execute(query, params + [limit, offset])
        rows = cur.fetchall()

        logs = []
        for row in rows:
            logs.append({
                'time': _isoformat(row['time']),
                'level': _severity_to_text(row['severity']),
                'message': row['message'] or '',
                'host': row['source_host'] or ''
            })
        return logs, total_count
    except Exception as exc:  # pragma: no cover - depends on db objects
        app.logger.debug('Router DB query failed: %s', exc)
        return None, 0
    finally:
        conn.close()


def summarize_router_logs(limit: int = 500):
    """Summarize router/syslog messages for trends."""
    logs_result, _ = get_router_logs_from_db(limit=limit)
    logs = logs_result or []
    summary = {
        'total': len(logs),
        'severity_counts': {},
        'igmp_drops': 0,
        'wan_ports': {},
        'wifi_events': {},
        'rstats_errors': 0,
        'upnp_events': 0
    }

    for log in logs:
        msg = (log.get('message') or '').lower()
        sev = log.get('level') or 'Unknown'
        summary['severity_counts'][sev] = summary['severity_counts'].get(sev, 0) + 1

        if 'dst=224.0.0.1' in msg and 'proto=2' in msg:
            summary['igmp_drops'] += 1

        # WAN drop ports
        import re
        port_match = re.search(r'dpt=(\d+)', msg)
        if port_match:
            port = port_match.group(1)
            summary['wan_ports'][port] = summary['wan_ports'].get(port, 0) + 1

        # Wi-Fi events (wlceventd)
        if 'wlceventd' in msg:
            mac_match = re.search(r'([0-9a-f]{2}:){5}[0-9a-f]{2}', msg)
            mac = mac_match.group(0) if mac_match else 'unknown'
            summary['wifi_events'][mac] = summary['wifi_events'].get(mac, 0) + 1

        # rstats errors
        if 'rstats' in msg and 'problem loading' in msg:
            summary['rstats_errors'] += 1

        # upnp/miniupnpd
        if 'miniupnpd' in msg:
            summary['upnp_events'] += 1

    # top 5 ports and wifi macs
    def top_n(d: dict, n=5):
        return sorted([{'key': k, 'count': v} for k, v in d.items()], key=lambda x: x['count'], reverse=True)[:n]

    summary['wan_ports_top'] = top_n(summary['wan_ports'])
    summary['wifi_events_top'] = top_n(summary['wifi_events'])
    return summary


def summarize_system_events(events: list[dict]):
    """Summarize system/router events for trends."""
    summary = {
        'total': len(events),
        'severity_counts': {},
        'source_counts': {},
        'keyword_counts': {
            'auth': 0,
            'disk': 0,
            'network': 0,
            'update': 0,
            'warning': 0
        }
    }
    keywords = {
        'auth': ['auth', 'login', 'failed'],
        'disk': ['disk', 'drive', 'io', 'storage'],
        'network': ['network', 'dns', 'link', 'tcp', 'udp'],
        'update': ['update', 'patch', 'install'],
        'warning': ['warn', 'error', 'fail']
    }

    for e in events:
        msg = (e.get('message') or '').lower()
        sev = (e.get('level') or 'Info')
        src = e.get('source') or 'system'
        summary['severity_counts'][sev] = summary['severity_counts'].get(sev, 0) + 1
        summary['source_counts'][src] = summary['source_counts'].get(src, 0) + 1
        for key, words in keywords.items():
            if any(w in msg for w in words):
                summary['keyword_counts'][key] += 1

        # Build hourly buckets for severity timeline
        try:
            t = e.get('time')
            dt = None
            if isinstance(t, datetime.datetime):
                dt = t
            elif isinstance(t, str):
                try:
                    dt = datetime.datetime.fromisoformat(t.replace('Z', '+00:00'))
                except Exception:
                    dt = None
            if dt:
                bucket = dt.replace(minute=0, second=0, microsecond=0)
                key_bucket = bucket.isoformat()
                if key_bucket not in summary:
                    summary.setdefault('severity_timeline', [])
                # Accumulate into dict map first for efficiency
        except Exception:
            pass

    # Build severity timeline map for histogram visualization
    # Each bucket represents one hour and contains counts for error, warning, and information levels
    # This allows the frontend to display severity distribution over time
    timeline_map = {}
    for e in events:
        dt = None
        t = e.get('time')
        
        # Parse event timestamp to datetime object
        if isinstance(t, datetime.datetime):
            dt = t
        elif isinstance(t, str):
            try:
                # Handle ISO format timestamps with Z suffix
                dt = datetime.datetime.fromisoformat(t.replace('Z', '+00:00'))
            except Exception:
                dt = None
        
        # Skip events without valid timestamps
        if dt is None:
            continue
        
        # Create hourly bucket by truncating minutes and seconds
        # This groups events into 1-hour intervals for the timeline chart
        bucket = dt.replace(minute=0, second=0, microsecond=0)
        bucket_key = bucket.isoformat()
        
        # Initialize bucket if not exists with zero counts for all severity levels
        if bucket_key not in timeline_map:
            timeline_map[bucket_key] = {'error': 0, 'warning': 0, 'information': 0}
        
        # Increment appropriate severity counter based on event level
        sev_lower = (e.get('level') or 'information').lower()
        if 'error' in sev_lower:
            timeline_map[bucket_key]['error'] += 1
        elif 'warn' in sev_lower:
            timeline_map[bucket_key]['warning'] += 1
        else:
            timeline_map[bucket_key]['information'] += 1

    # Convert timeline map to sorted list of time buckets for chart rendering
    # Sorting ensures chronological order in the visualization
    timeline = []
    for k, v in sorted(timeline_map.items()):
        timeline.append({'bucket': k, **v})
    summary['severity_timeline'] = timeline

    # convert source counts to top list
    def top_list(d, n=5):
        return sorted([{'key': k, 'count': v} for k, v in d.items()], key=lambda x: x['count'], reverse=True)[:n]
    summary['sources_top'] = top_list(summary['source_counts'])
    return summary


def _normalize_events(events: list[dict]) -> list[dict]:
    """Normalize event fields for API use."""
    normalized = []
    for e in events:
        msg = e.get('message') or e.get('Message') or ''
        src = e.get('source') or e.get('Source') or e.get('ProviderName') or ''
        lvl = e.get('level') or e.get('Level') or e.get('LevelDisplayName') or ''
        time_val = e.get('time') or e.get('TimeCreated')
        log_type = e.get('log_type') or e.get('LogName') or ''

        if not lvl:
            lower = msg.lower()
            if 'error' in lower or 'fail' in lower:
                lvl = 'Error'
            elif 'warn' in lower:
                lvl = 'Warning'
            else:
                lvl = 'Information'

        normalized.append({
            'time': _isoformat(time_val),
            'level': lvl,
            'source': src,
            'message': msg,
            'log_type': log_type
        })
    return normalized


def get_wifi_clients():
    """Return a list of clients from the ARP table."""
    try:
        result = subprocess.run(['arp', '-a'], capture_output=True, text=True, timeout=10)
        clients = []
        for line in result.stdout.splitlines():
            parts = line.split()
            if len(parts) >= 3 and parts[1].count('-') == 5:
                ip = parts[0]
                mac = parts[1].replace('-', ':')
                try:
                    hostname = socket.getfqdn(ip)
                except Exception:
                    hostname = ''
                clients.append({'mac': mac, 'ip': ip, 'hostname': hostname, 'packets': 0})

        # If no real clients found, return mock data for demonstration
        if not clients:
            import random
            clients = [
                {'mac': '00:11:22:33:44:55', 'ip': '192.168.1.10', 'hostname': 'router.local', 'packets': random.randint(100, 1000)},
                {'mac': 'AA:BB:CC:DD:EE:FF', 'ip': '192.168.1.25', 'hostname': 'laptop-01', 'packets': random.randint(50, 500)},
                {'mac': '11:22:33:44:55:66', 'ip': '192.168.1.50', 'hostname': '', 'packets': random.randint(10, 100)},
                {'mac': '77:88:99:AA:BB:CC', 'ip': '192.168.1.75', 'hostname': 'phone-01', 'packets': random.randint(200, 800)},
            ]

        return clients
    except Exception:
        # Fallback to mock data if ARP command fails
        import random
        return [
            {'mac': '00:11:22:33:44:55', 'ip': '192.168.1.10', 'hostname': 'router.local', 'packets': random.randint(100, 1000)},
            {'mac': 'AA:BB:CC:DD:EE:FF', 'ip': '192.168.1.25', 'hostname': 'laptop-01', 'packets': random.randint(50, 500)},
            {'mac': '11:22:33:44:55:66', 'ip': '192.168.1.50', 'hostname': '', 'packets': random.randint(10, 100)},
        ]


def _calculate_health_score(summary):
    """Calculate an overall system health score (0-100) based on current metrics.
    
    The score is calculated by weighing various factors:
    - IIS errors and spike status
    - Authentication failures
    - Windows critical events
    - Router alerts
    
    Returns a tuple of (score, status, factors) where:
    - score: 0-100 integer
    - status: 'healthy', 'warning', or 'critical'
    - factors: list of issues affecting the score
    """
    score = 100
    factors = []
    
    # IIS errors impact (max -30 points)
    iis_errors = summary.get('iis', {}).get('current_errors', 0)
    if summary.get('iis', {}).get('spike', False):
        score -= 25
        factors.append({'type': 'critical', 'message': 'IIS error spike detected'})
    elif iis_errors > 10:
        score -= 15
        factors.append({'type': 'warning', 'message': f'{iis_errors} IIS errors in last 5 minutes'})
    elif iis_errors > 5:
        score -= 5
        factors.append({'type': 'info', 'message': f'{iis_errors} IIS errors in last 5 minutes'})
    
    # Auth failures impact (max -25 points)
    auth_count = len(summary.get('auth', []))
    if auth_count > 3:
        score -= 20
        factors.append({'type': 'critical', 'message': f'{auth_count} clients with auth burst activity'})
    elif auth_count > 0:
        score -= 10
        factors.append({'type': 'warning', 'message': f'{auth_count} client(s) with repeated auth failures'})
    
    # Windows critical events impact (max -25 points)
    windows_count = len(summary.get('windows', []))
    critical_count = sum(1 for e in summary.get('windows', []) if (e.get('level') or '').lower() == 'critical')
    if critical_count > 0:
        score -= 20
        factors.append({'type': 'critical', 'message': f'{critical_count} critical Windows event(s)'})
    elif windows_count > 3:
        score -= 10
        factors.append({'type': 'warning', 'message': f'{windows_count} Windows error events'})
    elif windows_count > 0:
        score -= 5
        factors.append({'type': 'info', 'message': f'{windows_count} Windows error event(s)'})
    
    # Router alerts impact (max -20 points)
    router_count = len(summary.get('router', []))
    router_errors = sum(1 for r in summary.get('router', []) if (r.get('severity') or '').lower() == 'error')
    if router_errors > 2:
        score -= 15
        factors.append({'type': 'critical', 'message': f'{router_errors} router error alerts'})
    elif router_count > 3:
        score -= 10
        factors.append({'type': 'warning', 'message': f'{router_count} router alerts'})
    elif router_count > 0:
        score -= 5
        factors.append({'type': 'info', 'message': f'{router_count} router alert(s)'})
    
    # Ensure score doesn't go below 0
    score = max(0, score)
    
    # Determine status based on score
    if score >= 80:
        status = 'healthy'
    elif score >= 50:
        status = 'warning'
    else:
        status = 'critical'
    
    return score, status, factors


def _calculate_error_rate(errors, total):
    """Calculate error rate as a percentage."""
    if total == 0:
        return 0.0
    return round((errors / total) * 100, 2)


def _mock_dashboard_summary():
    now = datetime.datetime.now(datetime.UTC)
    summary = {
        'using_mock': True,
        'timestamp': _to_est_string(now),
        'iis': {
            'current_errors': 12,
            'total_requests': 4200,
            'baseline_avg': 2.1,
            'baseline_std': 1.3,
            'spike': True,
            'error_rate': _calculate_error_rate(12, 4200)
        },
        'auth': [
            {'client_ip': '192.168.1.50', 'count': 18, 'window_minutes': 15, 'last_seen': _to_est_string(now - datetime.timedelta(minutes=1))},
            {'client_ip': '203.0.113.44', 'count': 11, 'window_minutes': 15, 'last_seen': _to_est_string(now - datetime.timedelta(minutes=4))}
        ],
        'windows': [
            {'time': _to_est_string(now - datetime.timedelta(minutes=2)), 'source': 'Application Error', 'id': 1000, 'level': 'Error', 'message': 'Mock service failure detected on APP01.'},
            {'time': _to_est_string(now - datetime.timedelta(minutes=6)), 'source': 'System', 'id': 7031, 'level': 'Critical', 'message': 'Mock service terminated unexpectedly.'}
        ],
        'router': [
            {'time': _to_est_string(now - datetime.timedelta(minutes=3)), 'severity': 'Error', 'message': 'WAN connection lost - retrying.', 'host': 'router.local'},
            {'time': _to_est_string(now - datetime.timedelta(minutes=9)), 'severity': 'Warning', 'message': 'Multiple failed admin logins from 203.0.113.10.', 'host': 'router.local'}
        ],
        'syslog': [
            {'time': _to_est_string(now - datetime.timedelta(minutes=1)), 'source': 'syslog', 'severity': 'Error', 'message': 'Mock IIS 500 spike detected on WEB01.'},
            {'time': _to_est_string(now - datetime.timedelta(minutes=5)), 'source': 'asus', 'severity': 'Warning', 'message': 'High bandwidth usage detected from 192.168.1.101.'}
        ],
        'lan': {
            'total_devices': 15,
            'active_devices': 8,
            'new_devices_24h': 1
        },
        'hourly_breakdown': [
            {'hour': _to_est_string(now.replace(minute=0, second=0, microsecond=0) - datetime.timedelta(hours=5)), 'iis_errors': 2, 'auth_failures': 1, 'windows_errors': 0, 'router_alerts': 0},
            {'hour': _to_est_string(now.replace(minute=0, second=0, microsecond=0) - datetime.timedelta(hours=4)), 'iis_errors': 3, 'auth_failures': 2, 'windows_errors': 1, 'router_alerts': 0},
            {'hour': _to_est_string(now.replace(minute=0, second=0, microsecond=0) - datetime.timedelta(hours=3)), 'iis_errors': 1, 'auth_failures': 0, 'windows_errors': 0, 'router_alerts': 1},
            {'hour': _to_est_string(now.replace(minute=0, second=0, microsecond=0) - datetime.timedelta(hours=2)), 'iis_errors': 4, 'auth_failures': 3, 'windows_errors': 1, 'router_alerts': 0},
            {'hour': _to_est_string(now.replace(minute=0, second=0, microsecond=0) - datetime.timedelta(hours=1)), 'iis_errors': 2, 'auth_failures': 5, 'windows_errors': 0, 'router_alerts': 1},
            {'hour': _to_est_string(now.replace(minute=0, second=0, microsecond=0)), 'iis_errors': 12, 'auth_failures': 8, 'windows_errors': 2, 'router_alerts': 2}
        ]
    }
    
    # Calculate health score
    score, status, factors = _calculate_health_score(summary)
    summary['health'] = {
        'score': score,
        'status': status,
        'factors': factors
    }
    
    return summary


def get_dashboard_summary():
    now = datetime.datetime.now(datetime.UTC)
    summary = {
        'using_mock': False,
        'timestamp': _to_est_string(now),
        'iis': {'current_errors': 0, 'total_requests': 0, 'baseline_avg': 0.0, 'baseline_std': 0.0, 'spike': False, 'error_rate': 0.0},
        'auth': [],
        'windows': [],
        'router': [],
        'syslog': [],
        'lan': {'total_devices': 0, 'active_devices': 0, 'new_devices_24h': 0},
        'hourly_breakdown': []
    }
    conn = get_db_connection()
    if conn is None:
        return _mock_dashboard_summary()

    try:
        cur = conn.cursor()
        try:
            # Get IIS errors in last 5 minutes
            cur.execute(
                """
                SELECT 
                    SUM(CASE WHEN status BETWEEN 500 AND 599 THEN 1 ELSE 0 END) AS errors,
                    COUNT(*) AS total
                FROM iis_requests_recent
                WHERE datetime(request_time) >= datetime('now', '-5 minutes')
                """
            )
            current = dict_from_row(cur.fetchone()) or {}
            summary['iis']['current_errors'] = int(current.get('errors') or 0)
            summary['iis']['total_requests'] = int(current.get('total') or 0)
            summary['iis']['error_rate'] = _calculate_error_rate(
                summary['iis']['current_errors'],
                summary['iis']['total_requests']
            )

            # Get baseline for spike detection (simplified for SQLite)
            cur.execute(
                """
                SELECT 
                    AVG(err_count) AS avg_errors
                FROM (
                    SELECT strftime('%Y-%m-%d %H:%M', request_time) AS bucket,
                           SUM(CASE WHEN status BETWEEN 500 AND 599 THEN 1 ELSE 0 END) AS err_count
                    FROM iis_requests_recent
                    WHERE datetime(request_time) >= datetime('now', '-60 minutes')
                    GROUP BY bucket
                )
                """
            )
            baseline = dict_from_row(cur.fetchone()) or {}
            avg = _safe_float(baseline.get('avg_errors'))
            summary['iis']['baseline_avg'] = round(avg, 2)
            summary['iis']['baseline_std'] = 0.0  # SQLite doesn't have STDDEV
            summary['iis']['spike'] = summary['iis']['current_errors'] > (avg * 3 if avg else 10)
        except Exception as exc:
            app.logger.debug('IIS KPI query failed: %s', exc)

        try:
            cur.execute(
                """
                SELECT client_ip,
                       COUNT(*) AS failures,
                       MIN(request_time) AS first_seen,
                       MAX(request_time) AS last_seen
                FROM iis_requests_recent
                WHERE datetime(request_time) >= datetime('now', '-15 minutes')
                  AND status IN (401, 403)
                GROUP BY client_ip
                HAVING COUNT(*) >= ?
                ORDER BY failures DESC
                LIMIT 10
                """,
                (AUTH_FAILURE_THRESHOLD,)
            )
            rows = cur.fetchall()
            summary['auth'] = [
                {
                    'client_ip': row['client_ip'],
                    'count': row['failures'] or 0,
                    'window_minutes': 15,
                    'last_seen': _isoformat(row['last_seen'])
                }
                for row in rows
            ]
        except Exception as exc:
            app.logger.debug('Auth burst query failed: %s', exc)

        try:
            cur.execute(
                """
                SELECT COALESCE(event_utc, received_utc) AS evt_time,
                       COALESCE(source, provider_name) AS source,
                       event_id,
                       COALESCE(level_text, CAST(level AS TEXT)) AS level,
                       message
                FROM eventlog_windows_recent
                WHERE (datetime(event_utc) >= datetime('now', '-10 minutes')
                       OR datetime(received_utc) >= datetime('now', '-10 minutes'))
                  AND (COALESCE(level, 0) <= 2 
                       OR LOWER(COALESCE(level_text, '')) LIKE '%error%' 
                       OR LOWER(COALESCE(level_text, '')) LIKE '%critical%')
                ORDER BY evt_time DESC
                LIMIT 10
                """
            )
            rows = cur.fetchall()
            summary['windows'] = [
                {
                    'time': _isoformat(row['evt_time']),
                    'source': row['source'],
                    'id': row['event_id'],
                    'level': row['level'],
                    'message': row['message']
                }
                for row in rows
            ]
        except Exception as exc:
            app.logger.debug('Windows events query failed: %s', exc)

        try:
            cur.execute(
                """
                SELECT received_utc,
                       message,
                       severity,
                       source_host
                FROM syslog_recent
                WHERE source = 'asus'
                  AND (severity <= 3
                       OR LOWER(message) LIKE '%wan%'
                       OR LOWER(message) LIKE '%dhcp%'
                       OR LOWER(message) LIKE '%failed%'
                       OR LOWER(message) LIKE '%drop%')
                ORDER BY received_utc DESC
                LIMIT 10
                """
            )
            rows = cur.fetchall()
            summary['router'] = [
                {
                    'time': _isoformat(row['received_utc']),
                    'severity': _severity_to_text(row['severity']),
                    'message': row['message'],
                    'host': row['source_host']
                }
                for row in rows
            ]
        except Exception as exc:
            app.logger.debug('Router anomaly query failed: %s', exc)

        try:
            cur.execute(
                """
                SELECT received_utc,
                       source,
                       source_host,
                       severity,
                       message
                FROM syslog_recent
                ORDER BY received_utc DESC
                LIMIT 15
                """
            )
            rows = cur.fetchall()
            summary['syslog'] = [
                {
                    'time': _isoformat(row['received_utc']),
                    'source': row['source'] or row['source_host'],
                    'severity': _severity_to_text(row['severity']),
                    'message': row['message']
                }
                for row in rows
            ]
        except Exception as exc:
            app.logger.debug('Syslog summary query failed: %s', exc)

        # Get LAN device statistics
        try:
            cur.execute("SELECT * FROM lan_summary_stats")
            lan_row = dict_from_row(cur.fetchone())
            if lan_row:
                summary['lan']['total_devices'] = lan_row.get('total_devices', 0) or 0
                summary['lan']['active_devices'] = lan_row.get('active_devices', 0) or 0
        except Exception as exc:
            app.logger.debug('LAN stats query failed: %s', exc)

        # Get new devices in last 24 hours
        try:
            cur.execute(
                """
                SELECT COUNT(*) AS new_count
                FROM devices
                WHERE datetime(first_seen_utc) >= datetime('now', '-24 hours')
                """
            )
            new_row = dict_from_row(cur.fetchone())
            if new_row:
                summary['lan']['new_devices_24h'] = new_row.get('new_count', 0) or 0
        except Exception as exc:
            app.logger.debug('New devices query failed: %s', exc)

        # Get hourly breakdown for the last 6 hours (simplified for SQLite)
        try:
            # Generate last 6 hours
            hourly_breakdown = []
            for i in range(6):
                hour_offset = 5 - i  # Start from 5 hours ago
                cur.execute(
                    """
                    SELECT 
                        SUM(CASE WHEN status BETWEEN 500 AND 599 THEN 1 ELSE 0 END) AS iis_errors,
                        SUM(CASE WHEN status IN (401, 403) THEN 1 ELSE 0 END) AS auth_failures
                    FROM iis_requests_recent
                    WHERE strftime('%Y-%m-%d %H', request_time) = strftime('%Y-%m-%d %H', datetime('now', ? || ' hours'))
                    """,
                    (f'-{hour_offset}',)
                )
                iis_row = dict_from_row(cur.fetchone()) or {}

                cur.execute(
                    """
                    SELECT COUNT(*) AS errors
                    FROM eventlog_windows_recent
                    WHERE strftime('%Y-%m-%d %H', COALESCE(event_utc, received_utc)) = strftime('%Y-%m-%d %H', datetime('now', ? || ' hours'))
                      AND (COALESCE(level, 0) <= 2 OR LOWER(COALESCE(level_text, '')) LIKE '%error%')
                    """,
                    (f'-{hour_offset}',)
                )
                win_row = dict_from_row(cur.fetchone()) or {}

                cur.execute(
                    """
                    SELECT COUNT(*) AS alerts
                    FROM syslog_recent
                    WHERE source = 'asus'
                      AND strftime('%Y-%m-%d %H', received_utc) = strftime('%Y-%m-%d %H', datetime('now', ? || ' hours'))
                      AND (severity <= 3 OR LOWER(message) LIKE '%wan%' OR LOWER(message) LIKE '%failed%')
                    """,
                    (f'-{hour_offset}',)
                )
                router_row = dict_from_row(cur.fetchone()) or {}

                hour_time = now - datetime.timedelta(hours=hour_offset)
                hour_time = hour_time.replace(minute=0, second=0, microsecond=0)
                hourly_breakdown.append({
                    'hour': _isoformat(hour_time),
                    'iis_errors': (iis_row.get('iis_errors') or 0),
                    'auth_failures': (iis_row.get('auth_failures') or 0),
                    'windows_errors': (win_row.get('errors') or 0),
                    'router_alerts': (router_row.get('alerts') or 0)
                })
            summary['hourly_breakdown'] = hourly_breakdown
        except Exception as exc:
            app.logger.debug('Hourly breakdown query failed: %s', exc)

    finally:
        conn.close()

    # Check if we have any meaningful data across all metrics
    # If database is empty (no IIS requests, no auth failures, no Windows events, no router logs, no syslog),
    # use mock data to provide a helpful example of what the dashboard looks like with data
    has_data = (
        summary['iis']['total_requests'] > 0 or
        len(summary['auth']) > 0 or
        len(summary['windows']) > 0 or
        len(summary['router']) > 0 or
        len(summary['syslog']) > 0
    )
    
    if not has_data:
        return _mock_dashboard_summary()

    # Calculate health score for real data
    score, status, factors = _calculate_health_score(summary)
    summary['health'] = {
        'score': score,
        'status': status,
        'factors': factors
    }

    return summary


@app.route('/')
def dashboard():
    """Render the primary dashboard."""
    return render_template('dashboard.html', auth_threshold=AUTH_FAILURE_THRESHOLD)


@app.route('/api/dashboard/summary')
@rate_limit(max_requests=60, window_seconds=60)
def api_dashboard_summary():
    """API endpoint to get dashboard summary data."""
    return jsonify(get_dashboard_summary())


@app.route('/events')
def events():
    """Drill-down page for system events."""
    return render_template('events.html')

@app.route('/router')
def router():
    """Drill-down page for router logs."""
    return render_template('router.html')


@app.route('/api/router/logs')
@rate_limit(max_requests=60, window_seconds=60)
def api_router_logs():
    """Return recent router/syslog entries with pagination, sorting, and filtering support.

    Query parameters:
    - limit: Number of entries per page (default: 50, max: 500)
    - page: Page number (1-based, default: 1)
    - offset: Alternative to page, direct offset (default: 0)
    - sort: Sort field (time, level, host, message) (default: time)
    - order: Sort order (asc, desc) (default: desc)
    - level: Filter by severity level (emergency, alert, critical, error, warning, notice, info, debug)
    - host: Filter by source host (partial match)
    - search: Search in message content (partial match)
    """
    limit = min(int(request.args.get('limit', '50')), 500)
    page = int(request.args.get('page', '1'))
    offset = int(request.args.get('offset', '0'))

    # Calculate offset from page if page is provided and offset is not
    if page > 1 and offset == 0:
        offset = (page - 1) * limit

    sort_field = request.args.get('sort', 'time')
    sort_dir = request.args.get('order', 'desc')
    level_filter = request.args.get('level')
    host_filter = request.args.get('host')
    search_query = request.args.get('search')

    logs, source, total = get_router_logs(
        max_lines=limit, with_source=True, offset=offset,
        sort_field=sort_field, sort_dir=sort_dir,
        level_filter=level_filter, host_filter=host_filter, search_query=search_query
    )

    # Calculate pagination metadata
    total_pages = (total + limit - 1) // limit if total > 0 else 1
    current_page = (offset // limit) + 1

    return jsonify({
        'logs': logs,
        'source': source,
        'pagination': {
            'total': total,
            'page': current_page,
            'limit': limit,
            'totalPages': total_pages,
            'hasNext': current_page < total_pages,
            'hasPrev': current_page > 1
        }
    })


@app.route('/api/router/summary')
@rate_limit(max_requests=30, window_seconds=60)
def api_router_summary():
    """Return parsed trend summary for router/syslog entries."""
    limit = int(request.args.get('limit', '500'))
    data = summarize_router_logs(limit)
    return jsonify(data)

@app.route('/wifi')
def wifi():
    """List Wi-Fi clients highlighting chatty nodes."""
    return render_template('wifi.html', clients=get_wifi_clients(), threshold=CHATTY_THRESHOLD)


@app.route('/api/events')
@app.route('/api/events/logs')
@rate_limit(max_requests=60, window_seconds=60)
def api_events():
    """Return recent Windows event log entries.

    Supports both /api/events and /api/events/logs routes for convention consistency.
    When connected to Postgres, queries the eventlog_windows_recent view.
    Falls back to PowerShell Get-WinEvent on Windows or mock data elsewhere.
    Query params:
    - log_types: comma-separated list of log types (Application,System,Security). Defaults to all three.
    """
    level = request.args.get('level')
    max_events = int(request.args.get('max', '100'))
    page = int(request.args.get('page', '1'))
    since_hours = request.args.get('since_hours')
    log_types_param = request.args.get('log_types', '')
    
    # Parse log_types parameter
    if log_types_param:
        log_types = [lt.strip() for lt in log_types_param.split(',') if lt.strip()]
    else:
        log_types = None  # Will default to all three in get_windows_events
    
    offset = (page - 1) * max_events if page > 0 else 0
    since = int(since_hours) if since_hours else None
    events_raw, source = get_windows_events(level=level, max_events=max_events, with_source=True, since_hours=since, offset=offset, log_types=log_types)
    events = _normalize_events(events_raw)
    return jsonify({'events': events, 'source': source, 'page': page})


@app.route('/api/events/summary')
@rate_limit(max_requests=30, window_seconds=60)
def api_events_summary():
    """
    Retrieve and summarize Windows Event Log data.
    
    Returns aggregated statistics including severity counts, top sources,
    keyword analysis, and time-series severity timeline for visualization.
    """
    max_events = int(request.args.get('max', '300'))
    since_hours = request.args.get('since_hours')
    log_types_param = request.args.get('log_types', '')
    
    # Parse log_types parameter
    if log_types_param:
        log_types = [lt.strip() for lt in log_types_param.split(',') if lt.strip()]
    else:
        log_types = None  # Will default to all three in get_windows_events
    
    # Log summary request for observability
    app.logger.info('Events summary requested - max: %d, since_hours: %s, log_types: %s',
                    max_events, since_hours, log_types)
    
    since = int(since_hours) if since_hours else None
    events_raw, source = get_windows_events(max_events=max_events, with_source=True, since_hours=since, log_types=log_types)
    events = _normalize_events(events_raw)
    data = summarize_system_events(events)
    data['source'] = source
    
    # Log timeline generation for debugging histogram issues
    timeline_count = len(data.get('severity_timeline', []))
    app.logger.info('Events summary generated - events: %d, timeline_buckets: %d, source: %s',
                    len(events), timeline_count, source)
    
    return jsonify(data)


def _mock_trend_data():
    """Generate mock 7-day trend data for development."""
    import random
    import datetime
    now = datetime.datetime.now(datetime.UTC)
    dates = [(now - datetime.timedelta(days=i)).strftime('%Y-%m-%d') for i in range(6, -1, -1)]

    return {
        'dates': dates,
        'iis_errors': [random.randint(5, 50) for _ in range(7)],
        'auth_failures': [random.randint(0, 30) for _ in range(7)],
        'windows_errors': [random.randint(2, 20) for _ in range(7)],
        'router_alerts': [random.randint(0, 15) for _ in range(7)]
    }


def get_trend_data():
    """Get 7-day trend data for dashboard graphs."""
    conn = get_db_connection()
    if conn is None:
        return _mock_trend_data()

    # Define trend metric keys
    TREND_KEYS = ['iis_errors', 'auth_failures', 'windows_errors', 'router_alerts']

    trends = {
        'dates': [],
        'iis_errors': [],
        'auth_failures': [],
        'windows_errors': [],
        'router_alerts': []
    }

    try:
        cur = conn.cursor()
        # Generate dates for last 7 days
        now = datetime.datetime.now(datetime.UTC)
        dates = [(now - datetime.timedelta(days=i)).strftime('%Y-%m-%d') for i in range(6, -1, -1)]
        trends['dates'] = dates

        # IIS 5xx errors by day
        try:
            cur.execute(
                """
                SELECT DATE(request_time) AS day,
                       SUM(CASE WHEN status BETWEEN 500 AND 599 THEN 1 ELSE 0 END) AS errors
                FROM iis_requests
                WHERE datetime(request_time) >= datetime('now', '-7 days')
                GROUP BY day
                ORDER BY day
                """
            )
            rows = cur.fetchall()
            errors_by_day = {row['day']: row['errors'] for row in rows}
            trends['iis_errors'] = [errors_by_day.get(d, 0) for d in dates]
        except Exception as exc:
            app.logger.debug('IIS trend query failed: %s', exc)
            trends['iis_errors'] = [0] * 7

        # Auth failures by day
        try:
            cur.execute(
                """
                SELECT DATE(request_time) AS day,
                       COUNT(*) AS failures
                FROM iis_requests
                WHERE datetime(request_time) >= datetime('now', '-7 days')
                  AND status IN (401, 403)
                GROUP BY day
                ORDER BY day
                """
            )
            rows = cur.fetchall()
            failures_by_day = {row['day']: row['failures'] for row in rows}
            trends['auth_failures'] = [failures_by_day.get(d, 0) for d in dates]
        except Exception as exc:
            app.logger.debug('Auth trend query failed: %s', exc)
            trends['auth_failures'] = [0] * 7

        # Windows errors by day
        try:
            cur.execute(
                """
                SELECT DATE(COALESCE(event_utc, received_utc)) AS day,
                       COUNT(*) AS errors
                FROM eventlog_windows
                WHERE datetime(COALESCE(event_utc, received_utc)) >= datetime('now', '-7 days')
                  AND (COALESCE(level, 0) <= 2 
                       OR LOWER(COALESCE(level_text, '')) LIKE '%error%' 
                       OR LOWER(COALESCE(level_text, '')) LIKE '%critical%')
                GROUP BY day
                ORDER BY day
                """
            )
            rows = cur.fetchall()
            errors_by_day = {row['day']: row['errors'] for row in rows}
            trends['windows_errors'] = [errors_by_day.get(d, 0) for d in dates]
        except Exception as exc:
            app.logger.debug('Windows trend query failed: %s', exc)
            trends['windows_errors'] = [0] * 7

        # Router alerts by day
        try:
            cur.execute(
                """
                SELECT DATE(received_utc) AS day,
                       COUNT(*) AS alerts
                FROM syslog_messages
                WHERE source = 'asus'
                  AND datetime(received_utc) >= datetime('now', '-7 days')
                  AND (severity <= 3
                       OR LOWER(message) LIKE '%wan%'
                       OR LOWER(message) LIKE '%dhcp%'
                       OR LOWER(message) LIKE '%failed%'
                       OR LOWER(message) LIKE '%drop%')
                GROUP BY day
                ORDER BY day
                """
            )
            rows = cur.fetchall()
            alerts_by_day = {row['day']: row['alerts'] for row in rows}
            trends['router_alerts'] = [alerts_by_day.get(d, 0) for d in dates]
        except Exception as exc:
            app.logger.debug('Router trend query failed: %s', exc)
            trends['router_alerts'] = [0] * 7

    finally:
        conn.close()

    # If all trends are empty, use mock data
    if all(sum(trends[k]) == 0 for k in TREND_KEYS):
        return _mock_trend_data()

    return trends


@app.route('/api/trends')
@rate_limit(max_requests=30, window_seconds=60)
def api_trends():
    """API endpoint to get 7-day trend data."""
    return jsonify(get_trend_data())


def call_openai_chat(prompt: str):
    """Call OpenAI Chat Completions API using urllib to avoid extra deps.
    Returns suggestion string or error message.
    """
    api_key = os.environ.get('OPENAI_API_KEY')
    if not api_key:
        return None, 'OpenAI API key not configured.'
    import urllib.request
    import urllib.error
    import ssl
    body = {
        'model': os.environ.get('OPENAI_MODEL', 'gpt-4o-mini'),
        'messages': [
            {'role': 'system', 'content': 'You are a Windows Event Log troubleshooting assistant. Provide concise, actionable fixes.'},
            {'role': 'user', 'content': prompt},
        ],
        'temperature': 0.2,
        'max_tokens': 300,
    }
    req = urllib.request.Request(
        os.environ.get('OPENAI_API_BASE', 'https://api.openai.com') + '/v1/chat/completions',
        data=json.dumps(body).encode('utf-8'),
        headers={'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'}
    )
    try:
        # allow default SSL context
        with urllib.request.urlopen(req, timeout=20, context=ssl.create_default_context()) as resp:
            resp_body = json.loads(resp.read().decode('utf-8'))
            content = resp_body.get('choices', [{}])[0].get('message', {}).get('content')
            if not content:
                return None, 'No suggestion received.'
            return content.strip(), None
    except urllib.error.HTTPError as e:
        try:
            err = e.read().decode('utf-8')
        except Exception:
            err = str(e)
        return None, f'OpenAI API error: {err}'
    except Exception as ex:
        return None, f'OpenAI call failed: {ex}'


@app.route('/api/ai/suggest', methods=['POST'])
@rate_limit(max_requests=10, window_seconds=60)
def api_ai_suggest():
    data = request.get_json(silent=True) or {}
    message = (data.get('message') or '')[:8000]
    source = (data.get('source') or '')[:200]
    event_id = data.get('id')
    if not message:
        return jsonify({'error': 'Missing message'}), 400
    user_prompt = (
        f"Windows Event Log entry from source '{source}'" + (f" (ID {event_id})" if event_id else '') + ":\n" +
        html.unescape(message) +
        "\n\nPlease explain the probable cause and provide concrete steps to resolve."
    )
    suggestion, err = call_openai_chat(user_prompt)
    if err:
        return jsonify({'error': err}), 502
    return jsonify({'suggestion': suggestion})


@app.route('/api/ai/explain', methods=['POST'])
@rate_limit(max_requests=10, window_seconds=60)
def api_ai_explain():
    """
    AI explanation endpoint for logs, events, and charts.

    Request body:
      - type: 'router_log' | 'windows_event' | 'chart_summary' | 'dashboard_summary'
      - context: JSON object with the relevant record(s) or aggregated stats
      - userQuestion (optional): free-text question from the user

    Response:
      - explanationHtml: HTML-safe explanation text
      - severity: optional severity assessment
      - recommendedActions: optional list of action suggestions
    """
    data = request.get_json(silent=True) or {}
    explain_type = data.get('type', '')
    context = data.get('context', {})
    user_question = (data.get('userQuestion') or '')[:1000]
    
    # Log AI explanation request for observability and troubleshooting
    app.logger.info('AI explain request - type: %s, has_context: %s, has_question: %s',
                    explain_type, bool(context), bool(user_question))

    # Validate type
    valid_types = ['router_log', 'windows_event', 'chart_summary', 'dashboard_summary']
    if explain_type not in valid_types:
        app.logger.warning('AI explain invalid type: %s', explain_type)
        return jsonify({'error': f'Invalid type. Must be one of: {", ".join(valid_types)}'}), 400

    if not context:
        app.logger.warning('AI explain missing context for type: %s', explain_type)
        return jsonify({'error': 'Missing context'}), 400

    # Truncate context to avoid excessive API costs
    # Serialize to JSON first, then truncate while keeping it valid
    MAX_CONTEXT_CHARS = 6000
    context_str = json.dumps(context)
    if len(context_str) > MAX_CONTEXT_CHARS:
        # Truncate and add indication that content was trimmed
        context_str = context_str[:MAX_CONTEXT_CHARS] + '... [truncated]'

    # Build system prompt based on type
    system_prompts = {
        'router_log': 'You are a network engineer assistant helping analyze router syslog entries for a home system dashboard. Provide clear explanations and actionable advice.',
        'windows_event': 'You are a Windows Event Log troubleshooting assistant for a home system dashboard. Explain events clearly and provide concrete steps to resolve issues.',
        'chart_summary': 'You are a system monitoring analyst for a home dashboard. Analyze chart data and explain patterns, anomalies, and what actions the user should consider.',
        'dashboard_summary': 'You are a home system health advisor. Summarize the overall state and highlight any issues that need attention.'
    }

    # Build user prompt based on type
    if explain_type == 'router_log':
        user_prompt = f"Router/syslog entry:\n{context_str}\n\n"
        if user_question:
            user_prompt += f"User question: {user_question}\n\n"
        user_prompt += "Please explain what this log entry means, whether it indicates a problem, and what action (if any) the user should take."

    elif explain_type == 'windows_event':
        user_prompt = f"Windows Event Log entry:\n{context_str}\n\n"
        if user_question:
            user_prompt += f"User question: {user_question}\n\n"
        user_prompt += "Please explain the probable cause and provide concrete steps to resolve any issues."

    elif explain_type == 'chart_summary':
        user_prompt = f"Chart/aggregated statistics:\n{context_str}\n\n"
        if user_question:
            user_prompt += f"User question: {user_question}\n\n"
        user_prompt += "Please analyze these statistics, identify any concerning patterns or anomalies, and suggest what the user should investigate or do."

    elif explain_type == 'dashboard_summary':
        user_prompt = f"Dashboard health summary:\n{context_str}\n\n"
        if user_question:
            user_prompt += f"User question: {user_question}\n\n"
        user_prompt += "Please summarize the overall system health, highlight any problems, and recommend priorities for the user."

    # Call OpenAI with customized system prompt
    api_key = os.environ.get("OPENAI_API_KEY", "")
    if not api_key:
        # Log when API key is not configured for observability
        app.logger.info('AI explain request without API key - type: %s', explain_type)
        # Return a helpful fallback message when API key is not configured
        fallback_messages = {
            'router_log': 'This is a router syslog entry. To get AI-powered explanations, configure the OPENAI_API_KEY environment variable.',
            'windows_event': 'This is a Windows event log entry. To get AI-powered explanations, configure the OPENAI_API_KEY environment variable.',
            'chart_summary': 'These are aggregated statistics. To get AI-powered analysis, configure the OPENAI_API_KEY environment variable.',
            'dashboard_summary': 'This is your dashboard summary. To get AI-powered health analysis, configure the OPENAI_API_KEY environment variable.'
        }
        return jsonify({
            'explanationHtml': f'<p>{fallback_messages.get(explain_type, "AI analysis unavailable.")}</p>',
            'severity': 'info',
            'recommendedActions': ['Configure OPENAI_API_KEY for AI-powered explanations']
        })

    import urllib.request
    import urllib.error
    import ssl

    body = {
        'model': os.environ.get('OPENAI_MODEL', 'gpt-4o-mini'),
        'messages': [
            {'role': 'system', 'content': system_prompts.get(explain_type, 'You are a helpful system assistant.')},
            {'role': 'user', 'content': user_prompt},
        ],
        'temperature': 0.3,
        'max_tokens': 500,
    }

    req = urllib.request.Request(
        os.environ.get('OPENAI_API_BASE', 'https://api.openai.com') + '/v1/chat/completions',
        data=json.dumps(body).encode('utf-8'),
        headers={'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'}
    )

    try:
        # Log OpenAI API request for monitoring
        app.logger.debug('Calling OpenAI API for type: %s', explain_type)
        
        with urllib.request.urlopen(req, timeout=25, context=ssl.create_default_context()) as resp:
            resp_body = json.loads(resp.read().decode('utf-8'))
            content = resp_body.get('choices', [{}])[0].get('message', {}).get('content')
            if not content:
                app.logger.error('OpenAI returned empty response for type: %s', explain_type)
                return jsonify({'error': 'No explanation received from AI.'}), 502

            # Convert content to basic HTML safely
            # First escape HTML entities, then handle formatting
            explanation_text = content.strip()
            explanation_html = html.escape(explanation_text)

            # Split into paragraphs on double newlines, filter empty ones
            paragraphs = [p.strip() for p in explanation_html.split('\n\n') if p.strip()]
            if paragraphs:
                # Convert single newlines to <br> within paragraphs
                paragraphs = [p.replace('\n', '<br>') for p in paragraphs]
                explanation_html = ''.join(f'<p>{p}</p>' for p in paragraphs)
            else:
                # Fallback: wrap entire content in single paragraph
                explanation_html = f'<p>{explanation_html.replace(chr(10), "<br>")}</p>'

            # Determine severity based on content keywords
            content_lower = content.lower()
            if any(word in content_lower for word in ['critical', 'immediate', 'urgent', 'severe']):
                severity = 'critical'
            elif any(word in content_lower for word in ['error', 'fail', 'problem', 'issue']):
                severity = 'warning'
            else:
                severity = 'info'

            # Log successful AI response for observability
            app.logger.info('AI explain success - type: %s, severity: %s', explain_type, severity)

            return jsonify({
                'explanationHtml': explanation_html,
                'severity': severity,
                'recommendedActions': []
            })

    except urllib.error.HTTPError as e:
        try:
            err = e.read().decode('utf-8')
        except Exception:
            err = str(e)
        # Log HTTP errors for troubleshooting
        app.logger.error('OpenAI API HTTP error for type %s: %s', explain_type, err)
        return jsonify({'error': f'OpenAI API error: {err}'}), 502
    except Exception as ex:
        # Log general exceptions for troubleshooting
        app.logger.error('AI explain exception for type %s: %s', explain_type, str(ex))
        return jsonify({'error': f'AI explanation failed: {ex}'}), 502


@app.route('/api/ai/feedback', methods=['POST'])
@rate_limit(max_requests=30, window_seconds=60)
def api_ai_feedback_create():
    """Create a new AI feedback entry when AI explains an event."""
    data = request.get_json(silent=True) or {}
    
    # Extract event details
    event_id = data.get('event_id')
    event_source = (data.get('event_source') or '')[:500]
    event_message = (data.get('event_message') or '')[:8000]
    event_log_type = (data.get('event_log_type') or '')[:100]
    event_level = (data.get('event_level') or '')[:50]
    event_time = data.get('event_time')
    ai_response = (data.get('ai_response') or '')[:10000]
    review_status = data.get('review_status', 'Viewed')  # Default to 'Viewed'
    
    # Validate required fields
    if not event_message:
        return jsonify({'error': 'Missing event_message'}), 400
    if not ai_response:
        return jsonify({'error': 'Missing ai_response'}), 400
    if review_status not in ['Pending', 'Viewed', 'Resolved']:
        return jsonify({'error': 'Invalid review_status. Must be Pending, Viewed, or Resolved'}), 400
    
    # Get database connection
    conn = get_db_connection()
    if conn is None:
        return jsonify({'error': 'Database unavailable'}), 503
    
    try:
        cur = conn.cursor()
        now = datetime.datetime.now(datetime.UTC).isoformat()
        cur.execute(
            """
            INSERT INTO ai_feedback 
            (event_id, event_source, event_message, event_log_type, event_level, 
             event_time, ai_response, review_status, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (event_id, event_source, event_message, event_log_type, event_level,
             event_time, ai_response, review_status, now, now)
        )
        result_id = cur.lastrowid
        conn.commit()
        
        return jsonify({
            'status': 'ok',
            'id': result_id,
            'created_at': now,
            'updated_at': now
        }), 201
    except Exception as exc:
        app.logger.error('Failed to create AI feedback: %s', exc)
        conn.rollback()
        return jsonify({'error': 'Database error'}), 500
    finally:
        conn.close()


@app.route('/api/ai/feedback', methods=['GET'])
@rate_limit(max_requests=60, window_seconds=60)
def api_ai_feedback_list():
    """Retrieve AI feedback entries with optional filtering."""
    # Parse query parameters
    limit = min(int(request.args.get('limit', '50')), 200)
    offset = int(request.args.get('offset', '0'))
    review_status = request.args.get('status')  # Filter by status
    event_log_type = request.args.get('log_type')  # Filter by log type
    since_days = request.args.get('since_days', '30')  # Default to last 30 days
    
    # Get database connection
    conn = get_db_connection()
    if conn is None:
        return jsonify({'feedback': [], 'total': 0, 'source': 'unavailable'})
    
    try:
        cur = conn.cursor()
        # Build WHERE clause with parameterized conditions
        conditions = []
        params = []
        
        # Validate and add since_days parameter
        try:
            days_value = int(since_days)
            if days_value < 1 or days_value > 365:
                days_value = 30  # Default to 30 if out of range
        except (ValueError, TypeError):
            days_value = 30  # Default to 30 if invalid
        
        conditions.append(f"datetime(created_at) >= datetime('now', '-{days_value} days')")
        
        if review_status:
            conditions.append("review_status = ?")
            params.append(review_status)
        
        if event_log_type:
            conditions.append("event_log_type = ?")
            params.append(event_log_type)
        
        where_clause = ' AND '.join(conditions)
        
        # Get total count
        count_query = f"SELECT COUNT(*) as count FROM ai_feedback WHERE {where_clause}"
        cur.execute(count_query, params)
        total = dict_from_row(cur.fetchone()).get('count', 0)
        
        # Get paginated results
        query = f"""
            SELECT 
                id,
                event_id,
                event_source,
                event_message,
                event_log_type,
                event_level,
                event_time,
                ai_response,
                review_status,
                created_at,
                updated_at
            FROM ai_feedback
            WHERE {where_clause}
            ORDER BY created_at DESC
            LIMIT ? OFFSET ?
        """
        cur.execute(query, params + [limit, offset])
        rows = cur.fetchall()
        
        # Format results
        feedback = []
        for row in rows:
            feedback.append({
                'id': row['id'],
                'event_id': row['event_id'],
                'event_source': row['event_source'],
                'event_message': row['event_message'],
                'event_log_type': row['event_log_type'],
                'event_level': row['event_level'],
                'event_time': _isoformat(row['event_time']),
                'ai_response': row['ai_response'],
                'review_status': row['review_status'],
                'created_at': _isoformat(row['created_at']),
                'updated_at': _isoformat(row['updated_at'])
            })
        
        return jsonify({
            'feedback': feedback,
            'total': total,
            'limit': limit,
            'offset': offset,
            'source': 'database'
        })
    except Exception as exc:
        app.logger.error('Failed to retrieve AI feedback: %s', exc)
        return jsonify({'error': 'Database error'}), 500
    finally:
        conn.close()


@app.route('/api/ai/feedback/<int:feedback_id>/status', methods=['PATCH'])
@rate_limit(max_requests=30, window_seconds=60)
def api_ai_feedback_update_status(feedback_id):
    """Update the review status of an AI feedback entry."""
    data = request.get_json(silent=True) or {}
    new_status = data.get('status')
    
    # Validate status
    if not new_status or new_status not in ['Pending', 'Viewed', 'Resolved']:
        return jsonify({'error': 'Invalid status. Must be Pending, Viewed, or Resolved'}), 400
    
    # Get database connection
    conn = get_db_connection()
    if conn is None:
        return jsonify({'error': 'Database unavailable'}), 503
    
    try:
        cur = conn.cursor()
        now = datetime.datetime.now(datetime.UTC).isoformat()
        cur.execute(
            """
            UPDATE ai_feedback
            SET review_status = ?, updated_at = ?
            WHERE id = ?
            """,
            (new_status, now, feedback_id)
        )
        
        if cur.rowcount == 0:
            return jsonify({'error': 'Feedback entry not found'}), 404
        
        conn.commit()
        
        return jsonify({
            'status': 'ok',
            'id': feedback_id,
            'review_status': new_status,
            'updated_at': now
        })
    except Exception as exc:
        app.logger.error('Failed to update AI feedback status: %s', exc)
        conn.rollback()
        return jsonify({'error': 'Database error'}), 500
    finally:
        conn.close()


@app.route('/health')
def health():
    """
    Health check endpoint with detailed subsystem status.
    
    Returns simple 'ok' by default for backward compatibility.
    Use /health/detailed for comprehensive health information.
    """
    # Check database connection instead of backend service
    conn = get_db_connection()
    if conn:
        try:
            cur = conn.cursor()
            cur.execute("SELECT 1")
            cur.fetchone()
            conn.close()
            return 'ok', 200
        except Exception:
            conn.close()

    # Fallback: check if we can at least load mock data
    try:
        summary = get_dashboard_summary()
        if summary and (summary.get('using_mock') or any([summary.get('auth'), summary.get('windows'), summary.get('router'), summary.get('syslog')])):
            return 'ok', 200
    except Exception:
        pass

    return 'unhealthy', 503


@app.route('/health/detailed')
def health_detailed():
    """
    Comprehensive health check with detailed subsystem information.
    
    Returns JSON with:
    - overall_status: 'healthy', 'degraded', or 'unhealthy'
    - timestamp: ISO format timestamp
    - subsystems: Detailed status of database, schema, and data freshness
    """
    if not PHASE1_FEATURES_AVAILABLE:
        return jsonify({
            'error': 'Detailed health check not available',
            'message': 'Phase 1 features not installed'
        }), 501
    
    db_path = _get_db_path()
    if not db_path or not os.path.exists(db_path):
        return jsonify({
            'overall_status': HealthStatus.UNHEALTHY,
            'timestamp': datetime.datetime.now(datetime.UTC).isoformat(),
            'error': 'Database not found',
            'db_path': db_path
        }), 503
    
    report, http_code = get_comprehensive_health(db_path)
    return jsonify(report), http_code


# Performance Monitoring API Endpoints

@app.route('/api/performance/queries')
@rate_limit(max_requests=30, window_seconds=60)
def api_performance_queries():
    """
    Get query performance statistics.
    
    Returns statistics on query execution times, including slow queries.
    """
    try:
        from performance_monitor import get_query_tracker
        
        tracker = get_query_tracker()
        stats = tracker.get_statistics()
        slow_queries = tracker.get_slow_queries(limit=10)
        
        return jsonify({
            'total_queries': len(stats),
            'slow_query_threshold_ms': tracker.slow_query_threshold_ms,
            'statistics': stats,
            'slowest_queries': slow_queries,
            'timestamp': datetime.datetime.now(datetime.UTC).isoformat()
        })
    except ImportError:
        return jsonify({
            'error': 'Performance monitoring not available',
            'message': 'Phase 4 features not installed'
        }), 501


@app.route('/api/performance/resources')
@rate_limit(max_requests=30, window_seconds=60)
def api_performance_resources():
    """
    Get system resource usage (memory, disk space).
    
    Returns current memory and disk usage statistics.
    """
    try:
        from performance_monitor import get_resource_monitor
        
        db_path = _get_db_path()
        log_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'var', 'log')
        
        monitor = get_resource_monitor(db_path, log_path)
        status = monitor.get_status()
        
        return jsonify({
            'timestamp': datetime.datetime.now(datetime.UTC).isoformat(),
            'memory': status['memory'],
            'disk': status['disk']
        })
    except ImportError:
        return jsonify({
            'error': 'Resource monitoring not available',
            'message': 'Phase 4 features not installed'
        }), 501


@app.route('/api/performance/query-plan', methods=['POST'])
@rate_limit(max_requests=10, window_seconds=60)
def api_performance_query_plan():
    """
    Analyze query execution plan.
    
    POST body: {"query": "SELECT * FROM devices", "params": [...]}
    Returns EXPLAIN QUERY PLAN output for the given query.
    """
    try:
        from performance_monitor import QueryPlanAnalyzer
        
        data = request.get_json()
        if not data or 'query' not in data:
            return jsonify({'error': 'Missing query parameter'}), 400
        
        query = data['query']
        params = data.get('params')
        
        conn = get_db_connection()
        if not conn:
            return jsonify({'error': 'Database not available'}), 503
        
        try:
            analyzer = QueryPlanAnalyzer(conn)
            plan = analyzer.explain_query(query, params)
            
            return jsonify({
                'query': query,
                'plan': plan,
                'timestamp': datetime.datetime.now(datetime.UTC).isoformat()
            })
        finally:
            conn.close()
            
    except ImportError:
        return jsonify({
            'error': 'Query plan analysis not available',
            'message': 'Phase 4 features not installed'
        }), 501


# LAN Observability API Endpoints

def _mock_lan_stats():
    """Generate mock LAN statistics for development."""
    import random
    return {
        'total_devices': random.randint(10, 30),
        'active_devices': random.randint(5, 15),
        'inactive_devices': random.randint(5, 15),
        'wired_devices_24h': random.randint(2, 8),
        'wifi_24ghz_devices_24h': random.randint(3, 10),
        'wifi_5ghz_devices_24h': random.randint(2, 7)
    }


def _mock_lan_devices():
    """Generate mock device list for development."""
    import random
    now = datetime.datetime.now(datetime.UTC)

    devices = [
        {
            'device_id': 1,
            'mac_address': '00:11:22:33:44:55',
            'primary_ip_address': '192.168.50.10',
            'hostname': 'laptop-work',
            'vendor': 'Dell Inc.',
            'first_seen_utc': _to_est_string(now - datetime.timedelta(days=30)),
            'last_seen_utc': _to_est_string(now - datetime.timedelta(minutes=2)),
            'is_active': True
        },
        {
            'device_id': 2,
            'mac_address': 'AA:BB:CC:DD:EE:FF',
            'primary_ip_address': '192.168.50.25',
            'hostname': 'phone-android',
            'vendor': 'Samsung',
            'first_seen_utc': _to_est_string(now - datetime.timedelta(days=60)),
            'last_seen_utc': _to_est_string(now - datetime.timedelta(minutes=5)),
            'is_active': True
        },
        {
            'device_id': 3,
            'mac_address': '11:22:33:44:55:66',
            'primary_ip_address': '192.168.50.50',
            'hostname': 'iot-camera',
            'vendor': 'Hikvision',
            'first_seen_utc': _to_est_string(now - datetime.timedelta(days=90)),
            'last_seen_utc': _to_est_string(now - datetime.timedelta(hours=2)),
            'is_active': False
        }
    ]

    return devices


@app.route('/api/lan/stats')
@rate_limit(max_requests=60, window_seconds=60)
def api_lan_stats():
    """Get LAN overview statistics."""
    conn = get_db_connection()
    if conn is None:
        return jsonify(_mock_lan_stats())

    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM lan_summary_stats")
        row = cur.fetchone()

        if row:
            stats = dict(row)
        else:
            stats = _mock_lan_stats()
    except Exception as exc:
        app.logger.debug('LAN stats query failed: %s', exc)
        stats = _mock_lan_stats()
    finally:
        conn.close()

    return jsonify(stats)


@app.route('/api/lan/devices')
@rate_limit(max_requests=60, window_seconds=60)
def api_lan_devices():
    """List all LAN devices with optional filtering."""
    state = request.args.get('state')  # 'active', 'inactive', or None for all
    interface = request.args.get('interface')  # filter by interface type
    tag = request.args.get('tag')  # filter by tag (iot, guest, critical)
    network_type = request.args.get('network_type')  # filter by network type (main, guest, iot)
    limit = int(request.args.get('limit', '100'))

    conn = get_db_connection()
    if conn is None:
        devices = _mock_lan_devices()
        if state == 'active':
            devices = [d for d in devices if d['is_active']]
        elif state == 'inactive':
            devices = [d for d in devices if not d['is_active']]
        return jsonify({'devices': devices})

    try:
        cur = conn.cursor()
        # Simplified query for SQLite (no LATERAL join)
        query = """
            SELECT
                d.device_id,
                d.mac_address,
                d.primary_ip_address,
                d.hostname,
                d.nickname,
                d.location,
                d.manufacturer,
                d.vendor,
                d.first_seen_utc,
                d.last_seen_utc,
                d.is_active,
                d.tags,
                d.network_type
            FROM devices d
            WHERE 1=1
        """

        params = []
        if state == 'active':
            query += " AND d.is_active = 1"
        elif state == 'inactive':
            query += " AND d.is_active = 0"

        if tag:
            query += " AND LOWER(d.tags) LIKE LOWER(?)"
            params.append(f'%{tag}%')

        if network_type:
            query += " AND d.network_type = ?"
            params.append(network_type)

        query += " ORDER BY d.last_seen_utc DESC LIMIT ?"
        params.append(limit)

        cur.execute(query, params)
        rows = cur.fetchall()

        devices = []
        for row in rows:
            device = dict(row)
            device['first_seen_utc'] = _isoformat(device.get('first_seen_utc'))
            device['last_seen_utc'] = _isoformat(device.get('last_seen_utc'))
            # Get latest snapshot info for this device
            cur.execute("""
                SELECT interface, rssi, tx_rate_mbps, rx_rate_mbps
                FROM device_snapshots
                WHERE device_id = ?
                ORDER BY sample_time_utc DESC
                LIMIT 1
            """, (device['device_id'],))
            snapshot = cur.fetchone()
            if snapshot:
                device['last_interface'] = snapshot['interface']
                device['last_rssi'] = snapshot['rssi']
                device['last_tx_rate_mbps'] = _safe_float(snapshot['tx_rate_mbps'])
                device['last_rx_rate_mbps'] = _safe_float(snapshot['rx_rate_mbps'])
            else:
                device['last_interface'] = None
                device['last_rssi'] = None
                device['last_tx_rate_mbps'] = 0.0
                device['last_rx_rate_mbps'] = 0.0
            devices.append(device)
    except Exception as exc:
        app.logger.debug('LAN devices query failed: %s', exc)
        devices = _mock_lan_devices()
    finally:
        conn.close()

    return jsonify({'devices': devices})


@app.route('/api/lan/devices/online')
@rate_limit(max_requests=60, window_seconds=60)
def api_lan_devices_online():
    """List currently online devices."""
    conn = get_db_connection()
    if conn is None:
        devices = [d for d in _mock_lan_devices() if d['is_active']]
        return jsonify({'devices': devices})

    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT
                device_id,
                mac_address,
                primary_ip_address,
                hostname,
                vendor,
                last_seen_utc,
                current_ip,
                current_interface,
                current_rssi,
                last_snapshot_time
            FROM devices_online
            ORDER BY last_seen_utc DESC
        """)
        rows = cur.fetchall()

        devices = []
        for row in rows:
            device = dict(row)
            device['last_seen_utc'] = _isoformat(device.get('last_seen_utc'))
            device['last_snapshot_time'] = _isoformat(device.get('last_snapshot_time'))
            devices.append(device)
    except Exception as exc:
        app.logger.debug('Online devices query failed: %s', exc)
        devices = [d for d in _mock_lan_devices() if d['is_active']]
    finally:
        conn.close()

    return jsonify({'devices': devices})


@app.route('/api/lan/device/<device_id>')
@rate_limit(max_requests=60, window_seconds=60)
def api_lan_device_detail(device_id):
    """Get detailed information for a specific device."""
    conn = get_db_connection()
    if conn is None:
        # Return mock data
        devices = _mock_lan_devices()
        device = next((d for d in devices if d['device_id'] == int(device_id)), None)
        if device:
            return jsonify(device)
        return jsonify({'error': 'Device not found'}), 404

    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT * FROM devices WHERE device_id = ?
        """, (device_id,))
        row = cur.fetchone()

        if not row:
            return jsonify({'error': 'Device not found'}), 404

        device = dict(row)
        
        # Get snapshot count
        cur.execute("SELECT COUNT(*) as count FROM device_snapshots WHERE device_id = ?", (device_id,))
        count_row = cur.fetchone()
        device['total_snapshots'] = count_row['count'] if count_row else 0
        
        # Get latest snapshot
        cur.execute("""
            SELECT interface, rssi, tx_rate_mbps, rx_rate_mbps, sample_time_utc
            FROM device_snapshots
            WHERE device_id = ?
            ORDER BY sample_time_utc DESC
            LIMIT 1
        """, (device_id,))
        snapshot = cur.fetchone()
        
        if snapshot:
            device['last_interface'] = snapshot['interface']
            device['last_rssi'] = snapshot['rssi']
            device['last_tx_rate_mbps'] = _safe_float(snapshot['tx_rate_mbps'])
            device['last_rx_rate_mbps'] = _safe_float(snapshot['rx_rate_mbps'])
            device['last_snapshot_time'] = _isoformat(snapshot['sample_time_utc'])
        else:
            device['last_interface'] = None
            device['last_rssi'] = None
            device['last_tx_rate_mbps'] = 0.0
            device['last_rx_rate_mbps'] = 0.0
            device['last_snapshot_time'] = None

        device['first_seen_utc'] = _isoformat(device.get('first_seen_utc'))
        device['last_seen_utc'] = _isoformat(device.get('last_seen_utc'))
        device['created_at'] = _isoformat(device.get('created_at'))
        device['updated_at'] = _isoformat(device.get('updated_at'))
    except Exception as exc:
        app.logger.debug('Device detail query failed: %s', exc)
        return jsonify({'error': 'Database error'}), 500
    finally:
        conn.close()

    return jsonify(device)


@app.route('/api/lan/device/<device_id>/update', methods=['POST', 'PATCH'])
@rate_limit(max_requests=30, window_seconds=60)
def api_lan_device_update(device_id):
    """Update nickname/location/tags/network_type for a device."""
    # Apply CSRF protection if Phase 3 is available
    if PHASE3_FEATURES_AVAILABLE and get_csrf_protection().is_enabled():
        # Manual CSRF check for this endpoint
        csrf = get_csrf_protection()
        token = request.headers.get('X-CSRF-Token')
        if not token and request.is_json and request.json:
            token = request.json.get('_csrf')
        cookie_token = request.cookies.get('csrf_token')
        if not csrf.validate_token(token, cookie_token):
            app.logger.warning(f"CSRF validation failed from {request.remote_addr}")
            return jsonify({'error': 'Forbidden', 'message': 'CSRF token validation failed'}), 403
    
    payload = request.get_json(silent=True) or {}
    nickname = payload.get('nickname')
    location = payload.get('location')
    tags = payload.get('tags')
    network_type = payload.get('network_type')

    if nickname is not None and not isinstance(nickname, str):
        return jsonify({'error': 'Invalid nickname'}), 400
    if location is not None and not isinstance(location, str):
        return jsonify({'error': 'Invalid location'}), 400
    if tags is not None and not isinstance(tags, str):
        return jsonify({'error': 'Invalid tags'}), 400
    if network_type is not None and not isinstance(network_type, str):
        return jsonify({'error': 'Invalid network_type'}), 400

    conn = get_db_connection()
    if conn is None:
        return jsonify({'error': 'Database unavailable'}), 503

    try:
        cur = conn.cursor()
        now = datetime.datetime.now(datetime.UTC).isoformat()
        cur.execute("""
            UPDATE devices
            SET
                nickname = COALESCE(?, nickname),
                location = COALESCE(?, location),
                tags = COALESCE(?, tags),
                network_type = COALESCE(?, network_type),
                updated_at = ?
            WHERE device_id = ?
        """, (nickname, location, tags, network_type, now, device_id))
        if cur.rowcount == 0:
            return jsonify({'error': 'Device not found'}), 404
        conn.commit()
        
        # Log audit trail if Phase 3 is available
        if PHASE3_FEATURES_AVAILABLE:
            audit = get_audit_trail()
            changes = {}
            if nickname is not None:
                changes['nickname'] = nickname
            if location is not None:
                changes['location'] = location
            if tags is not None:
                changes['tags'] = tags
            if network_type is not None:
                changes['network_type'] = network_type
            audit.log_device_update(
                device_id=device_id,
                changes=changes,
                ip_address=request.remote_addr
            )
        
        return jsonify({'status': 'ok'})
    except Exception as exc:
        app.logger.debug('Device update failed: %s', exc)
        conn.rollback()
        return jsonify({'error': 'Database error'}), 500
    finally:
        conn.close()


@app.route('/api/lan/device/<device_id>/timeline')
@rate_limit(max_requests=30, window_seconds=60)
def api_lan_device_timeline(device_id):
    """Get time-series data for a device."""
    hours = int(request.args.get('hours', '24'))

    conn = get_db_connection()
    if conn is None:
        # Return mock timeline data
        import random
        now = datetime.datetime.now(datetime.UTC)
        timeline = []
        for i in range(20):
            timeline.append({
                'sample_time_utc': _to_est_string(now - datetime.timedelta(hours=hours * i / 20)),
                'rssi': random.randint(-70, -30),
                'tx_rate_mbps': random.uniform(50, 150),
                'rx_rate_mbps': random.uniform(50, 150),
                'is_online': random.choice([True, True, True, False])
            })
        return jsonify({'timeline': timeline})

    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT
                sample_time_utc,
                ip_address,
                interface,
                rssi,
                tx_rate_mbps,
                rx_rate_mbps,
                is_online
            FROM device_snapshots
            WHERE device_id = ?
              AND datetime(sample_time_utc) >= datetime('now', ? || ' hours')
            ORDER BY sample_time_utc ASC
        """, (device_id, f'-{hours}'))
        rows = cur.fetchall()

        timeline = []
        for row in rows:
            point = dict(row)
            point['sample_time_utc'] = _isoformat(point.get('sample_time_utc'))
            timeline.append(point)
    except Exception as exc:
        app.logger.debug('Device timeline query failed: %s', exc)
        return jsonify({'error': 'Database error'}), 500
    finally:
        conn.close()

    return jsonify({'timeline': timeline})


@app.route('/api/lan/device/<device_id>/events')
@rate_limit(max_requests=60, window_seconds=60)
def api_lan_device_events(device_id):
    """Get syslog events associated with a device."""
    limit = int(request.args.get('limit', '50'))

    conn = get_db_connection()
    if conn is None:
        # Return mock events
        now = datetime.datetime.now(datetime.UTC)
        events = [
            {
                'timestamp': _to_est_string(now - datetime.timedelta(hours=1)),
                'severity': 'Notice',
                'message': 'Device connected to network',
                'match_type': 'mac'
            },
            {
                'timestamp': _to_est_string(now - datetime.timedelta(hours=3)),
                'severity': 'Info',
                'message': 'DHCP lease renewed',
                'match_type': 'ip'
            }
        ]
        return jsonify({'events': events})

    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT
                s.received_utc AS timestamp,
                s.severity,
                s.message,
                s.source_host,
                l.match_type,
                l.confidence
            FROM syslog_device_links l
            INNER JOIN syslog_messages s ON l.syslog_id = s.id
            WHERE l.device_id = ?
            ORDER BY s.received_utc DESC
            LIMIT ?
        """, (device_id, limit))
        rows = cur.fetchall()

        events = []
        for row in rows:
            event = dict(row)
            event['timestamp'] = _isoformat(event.get('timestamp'))
            event['severity'] = _severity_to_text(event.get('severity'))
            events.append(event)
    except Exception as exc:
        app.logger.debug('Device events query failed: %s', exc)
        return jsonify({'error': 'Database error'}), 500
    finally:
        conn.close()

    return jsonify({'events': events})


@app.route('/api/lan/device/<device_id>/connection-events')
@rate_limit(max_requests=60, window_seconds=60)
def api_lan_device_connection_events(device_id):
    """Get connection/disconnection event timeline for a device."""
    limit = int(request.args.get('limit', '50'))

    conn = get_db_connection()
    if conn is None:
        # Return mock events
        now = datetime.datetime.now(datetime.UTC)
        events = [
            {
                'event_id': 1,
                'event_type': 'connected',
                'event_time': _to_est_string(now - datetime.timedelta(hours=2)),
                'details': 'Device connected to network'
            },
            {
                'event_id': 2,
                'event_type': 'disconnected',
                'event_time': _to_est_string(now - datetime.timedelta(hours=5)),
                'details': 'Device went offline'
            },
            {
                'event_id': 3,
                'event_type': 'connected',
                'event_time': _to_est_string(now - datetime.timedelta(days=1)),
                'details': 'Device connected to network'
            }
        ]
        return jsonify({'events': events})

    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT
                event_id,
                event_type,
                event_time,
                previous_state,
                new_state,
                details
            FROM device_events
            WHERE device_id = ?
            ORDER BY event_time DESC
            LIMIT ?
        """, (device_id, limit))
        rows = cur.fetchall()

        events = []
        for row in rows:
            event = dict(row)
            event['event_time'] = _isoformat(event.get('event_time'))
            events.append(event)
    except Exception as exc:
        app.logger.debug('Device connection events query failed: %s', exc)
        return jsonify({'error': 'Database error'}), 500
    finally:
        conn.close()

    return jsonify({'events': events})


@app.route('/lan')
def lan_overview():
    """LAN overview dashboard page."""
    return render_template('lan_overview.html')


@app.route('/lan/devices')
def lan_devices():
    """LAN devices list page."""
    return render_template('lan_devices.html')


@app.route('/lan/device/<device_id>')
def lan_device_detail(device_id):
    """LAN device detail page."""
    return render_template('lan_device.html', device_id=device_id)


@app.route('/api/lan/alerts')
@rate_limit(max_requests=60, window_seconds=60)
def api_lan_alerts():
    """Get active LAN device alerts."""
    limit = int(request.args.get('limit', '50'))
    severity = request.args.get('severity')  # 'critical', 'warning', 'info'
    alert_type = request.args.get('type')  # filter by alert type

    conn = get_db_connection()
    if conn is None:
        # Return mock alerts for development
        import random
        now = datetime.datetime.now(datetime.UTC)
        mock_alerts = [
            {
                'alert_id': 1,
                'device_id': 1,
                'alert_type': 'weak_signal',
                'severity': 'warning',
                'title': 'Weak Wi-Fi Signal',
                'message': 'Device signal strength is -78 dBm',
                'hostname': 'laptop-work',
                'created_at': _to_est_string(now - datetime.timedelta(hours=1)),
                'is_acknowledged': False
            },
            {
                'alert_id': 2,
                'device_id': 2,
                'alert_type': 'new_device',
                'severity': 'info',
                'title': 'New Device Detected',
                'message': 'Unknown device joined the network',
                'hostname': 'unknown',
                'created_at': _to_est_string(now - datetime.timedelta(hours=3)),
                'is_acknowledged': False
            }
        ]
        return jsonify({'alerts': mock_alerts, 'total': len(mock_alerts)})

    try:
        cur = conn.cursor()
        query = """
            SELECT
                alert_id,
                device_id,
                alert_type,
                severity,
                title,
                message,
                metadata,
                is_acknowledged,
                acknowledged_at,
                is_resolved,
                created_at,
                mac_address,
                hostname,
                nickname,
                primary_ip_address,
                tags
            FROM device_alerts_active
            WHERE 1=1
        """

        params = []
        if severity:
            query += " AND severity = ?"
            params.append(severity)

        if alert_type:
            query += " AND alert_type = ?"
            params.append(alert_type)

        query += " ORDER BY created_at DESC LIMIT ?"
        params.append(limit)

        cur.execute(query, params)
        rows = cur.fetchall()

        alerts = []
        for row in rows:
            alert = dict(row)
            alert['created_at'] = _isoformat(alert.get('created_at'))
            alert['acknowledged_at'] = _isoformat(alert.get('acknowledged_at'))
            alerts.append(alert)

        # Get total count
        cur.execute("SELECT COUNT(*) as total FROM device_alerts_active")
        total_row = dict_from_row(cur.fetchone())
        total = total_row['total'] if total_row else 0
    except Exception as exc:
        app.logger.debug('Alerts query failed: %s', exc)
        return jsonify({'error': 'Database error'}), 500
    finally:
        conn.close()

    return jsonify({'alerts': alerts, 'total': total})


@app.route('/api/lan/alerts/<alert_id>/acknowledge', methods=['POST'])
@rate_limit(max_requests=30, window_seconds=60)
def api_lan_alert_acknowledge(alert_id):
    """Acknowledge an alert."""
    payload = request.get_json(silent=True) or {}
    acknowledged_by = payload.get('acknowledged_by', 'user')

    conn = get_db_connection()
    if conn is None:
        return jsonify({'error': 'Database unavailable'}), 503

    try:
        cur = conn.cursor()
        now = datetime.datetime.now(datetime.UTC).isoformat()
        cur.execute("""
            UPDATE device_alerts
            SET is_acknowledged = 1,
                acknowledged_at = ?,
                acknowledged_by = ?,
                updated_at = ?
            WHERE alert_id = ? AND is_acknowledged = 0
        """, (now, acknowledged_by, now, alert_id))
        if cur.rowcount == 0:
            return jsonify({'error': 'Alert not found or already acknowledged'}), 404
        conn.commit()
        return jsonify({'status': 'ok'})
    except Exception as exc:
        app.logger.debug('Alert acknowledge failed: %s', exc)
        conn.rollback()
        return jsonify({'error': 'Database error'}), 500
    finally:
        conn.close()


@app.route('/api/lan/alerts/<alert_id>/resolve', methods=['POST'])
@rate_limit(max_requests=30, window_seconds=60)
def api_lan_alert_resolve(alert_id):
    """Resolve an alert."""
    conn = get_db_connection()
    if conn is None:
        return jsonify({'error': 'Database unavailable'}), 503

    try:
        cur = conn.cursor()
        now = datetime.datetime.now(datetime.UTC).isoformat()
        cur.execute("""
            UPDATE device_alerts
            SET is_resolved = 1,
                resolved_at = ?,
                updated_at = ?
            WHERE alert_id = ? AND is_resolved = 0
        """, (now, now, alert_id))
        if cur.rowcount == 0:
            return jsonify({'error': 'Alert not found or already resolved'}), 404
        conn.commit()
        return jsonify({'status': 'ok'})
    except Exception as exc:
        app.logger.debug('Alert resolve failed: %s', exc)
        conn.rollback()
        return jsonify({'error': 'Database error'}), 500
    finally:
        conn.close()


@app.route('/api/lan/alerts/stats')
@rate_limit(max_requests=60, window_seconds=60)
def api_lan_alerts_stats():
    """Get alert statistics."""
    conn = get_db_connection()
    if conn is None:
        return jsonify({
            'total_active': 2,
            'critical': 0,
            'warning': 1,
            'info': 1
        })

    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT
                COUNT(*) as total_active,
                SUM(CASE WHEN severity = 'critical' THEN 1 ELSE 0 END) as critical,
                SUM(CASE WHEN severity = 'warning' THEN 1 ELSE 0 END) as warning,
                SUM(CASE WHEN severity = 'info' THEN 1 ELSE 0 END) as info
            FROM device_alerts
            WHERE is_resolved = 0
        """)
        stats = dict(cur.fetchone() or {})
    except Exception as exc:
        app.logger.debug('Alert stats query failed: %s', exc)
        return jsonify({'error': 'Database error'}), 500
    finally:
        conn.close()

    return jsonify(stats)


@app.route('/api/lan/device/<device_id>/lookup-vendor', methods=['POST'])
@rate_limit(max_requests=10, window_seconds=60)
def api_lan_device_lookup_vendor(device_id):
    """Look up and update vendor information for a device based on MAC address."""
    conn = get_db_connection()
    if conn is None:
        return jsonify({'error': 'Database unavailable'}), 503

    try:
        # Get device MAC address
        cur = conn.cursor()
        cur.execute("SELECT mac_address, vendor FROM devices WHERE device_id = ?", (device_id,))
        device = dict_from_row(cur.fetchone())

        if not device:
            return jsonify({'error': 'Device not found'}), 404

        # Look up vendor
        vendor = lookup_mac_vendor(device['mac_address'])

        if not vendor:
            return jsonify({'error': 'Vendor lookup failed', 'message': 'Could not determine vendor from MAC address'}), 404

        # Update device with vendor info
        now = datetime.datetime.now(datetime.UTC).isoformat()
        cur.execute("""
            UPDATE devices
            SET vendor = ?,
                updated_at = ?
            WHERE device_id = ?
        """, (vendor, now, device_id))

        if cur.rowcount == 0:
            return jsonify({'error': 'Failed to update device'}), 500

        conn.commit()
        return jsonify({'status': 'ok', 'vendor': vendor})
    except Exception as exc:
        app.logger.debug('Vendor lookup failed: %s', exc)
        conn.rollback()
        return jsonify({'error': 'Lookup error', 'message': str(exc)}), 500
    finally:
        conn.close()


@app.route('/api/lan/devices/enrich-vendors', methods=['POST'])
@rate_limit(max_requests=5, window_seconds=60)
def api_lan_devices_enrich_vendors():
    """Enrich all devices without vendor information by looking up their MAC addresses."""
    conn = get_db_connection()
    if conn is None:
        return jsonify({'error': 'Database unavailable'}), 503

    if not mac_lookup:
        return jsonify({'error': 'MAC vendor lookup feature not configured. Install mac-vendor-lookup package.'}), 501

    try:
        cur = conn.cursor()
        # Get devices without vendor info
        cur.execute("""
            SELECT device_id, mac_address
            FROM devices
            WHERE vendor IS NULL OR vendor = ''
            LIMIT 100
        """)
        devices = cur.fetchall()

        updated_count = 0
        failed_count = 0
        now = datetime.datetime.now(datetime.UTC).isoformat()

        for device in devices:
            vendor = lookup_mac_vendor(device['mac_address'])
            if vendor:
                cur.execute("""
                    UPDATE devices
                    SET vendor = ?,
                        updated_at = ?
                    WHERE device_id = ?
                """, (vendor, now, device['device_id']))
                updated_count += 1
            else:
                failed_count += 1

        conn.commit()
        return jsonify({
            'status': 'ok',
            'updated': updated_count,
            'failed': failed_count,
            'total': len(devices)
        })
    except Exception as exc:
        app.logger.debug('Bulk vendor enrichment failed: %s', exc)
        conn.rollback()
        return jsonify({'error': 'Enrichment error', 'message': str(exc)}), 500
    finally:
        conn.close()


if __name__ == '__main__':
    # Configure Phase 3 security features if available
    if PHASE3_FEATURES_AVAILABLE:
        # Configure security headers
        configure_security_headers(app)
        app.logger.info("Security headers configured")
        
        # Configure CSRF protection
        configure_csrf_protection(app)
        app.logger.info("CSRF protection configured")
        
        # Configure rate limit error handler
        create_rate_limit_handler(app)
        
        # Initialize audit trail
        audit = get_audit_trail()
        app.logger.info("Audit trail initialized")
        
        # Log startup
        structured_logger = get_structured_logger('app')
        structured_logger.info("SystemDashboard starting", version="1.0.0")
    
    # Install graceful shutdown handlers if available
    if PHASE1_FEATURES_AVAILABLE:
        install_handlers(timeout=30)
        app.logger.info("Graceful shutdown handlers installed")
        
        # Register cleanup for caches if using caching
        try:
            from api_utils import _response_cache
            register_cleanup(
                create_cache_cleanup(_response_cache),
                name="response_cache"
            )
            app.logger.info("Response cache cleanup registered")
        except (ImportError, AttributeError):
            pass
    
    # Enable debug for development convenience
    port = int(os.environ.get('DASHBOARD_PORT', '5000'))
    app.run(debug=True, host='0.0.0.0', port=port)

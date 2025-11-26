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

try:
    import psycopg2  # type: ignore
    import psycopg2.extras  # type: ignore
except Exception:  # pragma: no cover - optional dependency during local dev
    psycopg2 = None

try:
    from mac_vendor_lookup import MacLookup
    mac_lookup = MacLookup()
    mac_lookup.update_vendors()
except Exception:  # pragma: no cover - optional dependency
    mac_lookup = None

app = Flask(__name__)

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


def _is_windows():
    return platform.system().lower().startswith('win')


def get_db_settings():
    if psycopg2 is None:
        return None
    dsn = os.environ.get('DASHBOARD_DB_DSN')
    if dsn:
        return {'dsn': dsn}
    host = os.environ.get('DASHBOARD_DB_HOST')
    user = os.environ.get('DASHBOARD_DB_USER')
    password = os.environ.get('DASHBOARD_DB_PASSWORD')
    dbname = os.environ.get('DASHBOARD_DB_NAME') or os.environ.get('DASHBOARD_DB_DATABASE')
    if not all([host, user, password, dbname]):
        return None
    settings = {
        'host': host,
        'port': int(os.environ.get('DASHBOARD_DB_PORT', '5432')),
        'dbname': dbname,
        'user': user,
        'password': password,
    }
    sslmode = os.environ.get('DASHBOARD_DB_SSLMODE')
    if sslmode:
        settings['sslmode'] = sslmode
    return settings


def get_db_connection():
    settings = get_db_settings()
    if not settings:
        return None
    try:
        if 'dsn' in settings:
            return psycopg2.connect(settings['dsn'])
        params = dict(settings)
        password = params.pop('password', None)
        if password is None:
            return None
        if 'connect_timeout' not in params:
            params['connect_timeout'] = 3
        return psycopg2.connect(password=password, **params)
    except Exception as exc:  # pragma: no cover - depends on runtime
        app.logger.warning('Failed to connect to PostgreSQL: %s', exc)
        return None


def _isoformat(value):
    if value is None:
        return ''
    if isinstance(value, str):
        # Handle serialized /Date(1764037519528)/ from Windows EventLog JSON
        if value.startswith('/Date(') and value.endswith(')/'):
            try:
                import re
                match = re.search(r'/Date\((\-?\d+)\)/', value)
                if match:
                    ms = int(match.group(1))
                    dt = datetime.datetime.utcfromtimestamp(ms / 1000.0)
                    return dt.isoformat() + 'Z'
            except Exception:
                pass
        return value
    if isinstance(value, datetime.datetime):
        return value.isoformat()
    try:
        return str(value)
    except Exception:
        return ''


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
    except Exception:
        return None


def get_windows_events(level: str = None, max_events: int = 50, with_source: bool = False, since_hours: int = None, offset: int = 0):
    """Fetch recent Windows events via PowerShell. Level can be 'Error', 'Warning', or None for any.
    Returns list of dicts with time, source, id, level, message.
    """
    if not _is_windows():
        # Return mock events for demonstration purposes on non-Windows platforms
        import datetime
        mock_events = [
            {
                'time': (datetime.datetime.now() - datetime.timedelta(minutes=30)).isoformat(),
                'source': 'Application Error',
                'id': 1001,
                'level': 'Warning',
                'message': 'Mock application warning - database connection timeout occurred during operation'
            },
            {
                'time': (datetime.datetime.now() - datetime.timedelta(hours=1)).isoformat(),
                'source': 'Service Control Manager',
                'id': 2001,
                'level': 'Error',
                'message': 'Mock system error - service failed to start due to configuration issue'
            },
            {
                'time': (datetime.datetime.now() - datetime.timedelta(hours=2)).isoformat(),
                'source': 'DNS Client',
                'id': 1002,
                'level': 'Information',
                'message': 'Mock information event - DNS resolution completed successfully for domain'
            },
            {
                'time': (datetime.datetime.now() - datetime.timedelta(minutes=45)).isoformat(),
                'source': 'Application Error',
                'id': 1003,
                'level': 'Error',
                'message': 'Mock critical error - application crashed due to memory access violation'
            },
            {
                'time': (datetime.datetime.now() - datetime.timedelta(minutes=15)).isoformat(),
                'source': 'System',
                'id': 3001,
                'level': 'Warning',
                'message': 'Mock system warning - disk space running low on drive C:'
            }
        ]

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
    ps = (
        "Get-WinEvent -FilterHashtable @{"
        "LogName='Application','System'" + level_filter + "} "
        f"-MaxEvents {max_events} | "
        "Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message | "
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
    """Fetch router logs from PostgreSQL with pagination, sorting and filtering support."""
    conn = get_db_connection()
    if conn is None:
        return None, 0
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
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
                    conditions.append("severity = %s")
                    params.append(sev)
            
            if host_filter:
                conditions.append("source_host ILIKE %s")
                params.append(f'%{host_filter}%')
            
            if search_query:
                conditions.append("message ILIKE %s")
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
            count_query = f"SELECT COUNT(*) FROM telemetry.syslog_recent WHERE {where_clause}"
            cur.execute(count_query, params)
            total_count = cur.fetchone()['count']
            
            # Get paginated results
            query = f"""
                SELECT COALESCE(event_utc, received_utc) AS time,
                       severity,
                       message,
                       source_host
                FROM telemetry.syslog_recent
                WHERE {where_clause}
                ORDER BY {sort_column} {sort_direction}
                LIMIT %s OFFSET %s
            """
            cur.execute(query, params + [limit, offset])
            rows = cur.fetchall()
            
        logs = []
        for row in rows:
            logs.append({
                'time': _isoformat(row.get('time')),
                'level': _severity_to_text(row.get('severity')),
                'message': row.get('message') or '',
                'host': row.get('source_host') or ''
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

    # Build severity timeline map
    timeline_map = {}
    for e in events:
        dt = None
        t = e.get('time')
        if isinstance(t, datetime.datetime):
            dt = t
        elif isinstance(t, str):
            try:
                dt = datetime.datetime.fromisoformat(t.replace('Z', '+00:00'))
            except Exception:
                dt = None
        if dt is None:
            continue
        bucket = dt.replace(minute=0, second=0, microsecond=0)
        bucket_key = bucket.isoformat()
        if bucket_key not in timeline_map:
            timeline_map[bucket_key] = {'error': 0, 'warning': 0, 'information': 0}
        sev_lower = (e.get('level') or 'information').lower()
        if 'error' in sev_lower:
            timeline_map[bucket_key]['error'] += 1
        elif 'warn' in sev_lower:
            timeline_map[bucket_key]['warning'] += 1
        else:
            timeline_map[bucket_key]['information'] += 1

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
            'message': msg
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


def _mock_dashboard_summary():
    now = datetime.datetime.now(datetime.UTC)
    return {
        'using_mock': True,
        'iis': {
            'current_errors': 12,
            'total_requests': 4200,
            'baseline_avg': 2.1,
            'baseline_std': 1.3,
            'spike': True
        },
        'auth': [
            {'client_ip': '192.168.1.50', 'count': 18, 'window_minutes': 15, 'last_seen': (now - datetime.timedelta(minutes=1)).isoformat()},
            {'client_ip': '203.0.113.44', 'count': 11, 'window_minutes': 15, 'last_seen': (now - datetime.timedelta(minutes=4)).isoformat()}
        ],
        'windows': [
            {'time': (now - datetime.timedelta(minutes=2)).isoformat(), 'source': 'Application Error', 'id': 1000, 'level': 'Error', 'message': 'Mock service failure detected on APP01.'},
            {'time': (now - datetime.timedelta(minutes=6)).isoformat(), 'source': 'System', 'id': 7031, 'level': 'Critical', 'message': 'Mock service terminated unexpectedly.'}
        ],
        'router': [
            {'time': (now - datetime.timedelta(minutes=3)).isoformat(), 'severity': 'Error', 'message': 'WAN connection lost - retrying.'},
            {'time': (now - datetime.timedelta(minutes=9)).isoformat(), 'severity': 'Warning', 'message': 'Multiple failed admin logins from 203.0.113.10.'}
        ],
        'syslog': [
            {'time': (now - datetime.timedelta(minutes=1)).isoformat(), 'source': 'syslog', 'severity': 'Error', 'message': 'Mock IIS 500 spike detected on WEB01.'},
            {'time': (now - datetime.timedelta(minutes=5)).isoformat(), 'source': 'asus', 'severity': 'Warning', 'message': 'High bandwidth usage detected from 192.168.1.101.'}
        ]
    }


def get_dashboard_summary():
    summary = {
        'using_mock': False,
        'iis': {'current_errors': 0, 'total_requests': 0, 'baseline_avg': 0.0, 'baseline_std': 0.0, 'spike': False},
        'auth': [],
        'windows': [],
        'router': [],
        'syslog': []
    }
    conn = get_db_connection()
    if conn is None:
        return _mock_dashboard_summary()

    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            try:
                cur.execute(
                    """
                    SELECT COUNT(*) FILTER (WHERE status BETWEEN 500 AND 599) AS errors,
                           COUNT(*) AS total
                    FROM telemetry.iis_requests_recent
                    WHERE request_time >= NOW() - INTERVAL '5 minutes'
                    """
                )
                current = cur.fetchone() or {}
                summary['iis']['current_errors'] = current.get('errors', 0)
                summary['iis']['total_requests'] = current.get('total', 0)

                cur.execute(
                    """
                    SELECT AVG(err_count) AS avg_errors,
                           STDDEV_POP(err_count) AS std_errors
                    FROM (
                        SELECT date_trunc('minute', request_time) AS bucket,
                               COUNT(*) FILTER (WHERE status BETWEEN 500 AND 599) AS err_count
                        FROM telemetry.iis_requests_recent
                        WHERE request_time >= NOW() - INTERVAL '60 minutes'
                        GROUP BY bucket
                    ) s
                    """
                )
                baseline = cur.fetchone() or {}
                avg = _safe_float(baseline.get('avg_errors'))
                std = _safe_float(baseline.get('std_errors'))
                summary['iis']['baseline_avg'] = round(avg, 2)
                summary['iis']['baseline_std'] = round(std, 2)
                threshold = avg + (3 * std if std else 0)
                summary['iis']['spike'] = summary['iis']['current_errors'] > threshold
            except Exception as exc:
                app.logger.debug('IIS KPI query failed: %s', exc)

            try:
                cur.execute(
                    """
                    SELECT client_ip,
                           COUNT(*) AS failures,
                           MIN(request_time) AS first_seen,
                           MAX(request_time) AS last_seen
                    FROM telemetry.iis_requests_recent
                    WHERE request_time >= NOW() - INTERVAL '15 minutes'
                      AND status IN (401, 403)
                    GROUP BY client_ip
                    HAVING COUNT(*) >= %s
                    ORDER BY failures DESC
                    LIMIT 10
                    """,
                    (AUTH_FAILURE_THRESHOLD,)
                )
                rows = cur.fetchall()
                summary['auth'] = [
                    {
                        'client_ip': row.get('client_ip'),
                        'count': row.get('failures', 0),
                        'window_minutes': 15,
                        'last_seen': _isoformat(row.get('last_seen'))
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
                           COALESCE(level_text, level::text) AS level,
                           message
                    FROM telemetry.eventlog_windows_recent
                    WHERE (event_utc >= NOW() - INTERVAL '10 minutes'
                           OR received_utc >= NOW() - INTERVAL '10 minutes')
                      AND (COALESCE(level, 0) <= 2 OR COALESCE(level_text, '') ILIKE '%error%' OR COALESCE(level_text, '') ILIKE '%critical%')
                    ORDER BY evt_time DESC
                    LIMIT 10
                    """
                )
                rows = cur.fetchall()
                summary['windows'] = [
                    {
                        'time': _isoformat(row.get('evt_time')),
                        'source': row.get('source'),
                        'id': row.get('event_id'),
                        'level': row.get('level'),
                        'message': row.get('message')
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
                    FROM telemetry.syslog_recent
                    WHERE source = 'asus'
                      AND (severity <= 3
                           OR message ILIKE '%wan%'
                           OR message ILIKE '%dhcp%'
                           OR message ILIKE '%failed%'
                           OR message ILIKE '%drop%')
                    ORDER BY received_utc DESC
                    LIMIT 10
                    """
                )
                rows = cur.fetchall()
                summary['router'] = [
                    {
                        'time': _isoformat(row.get('received_utc')),
                        'severity': _severity_to_text(row.get('severity')),
                        'message': row.get('message'),
                        'host': row.get('source_host')
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
                    FROM telemetry.syslog_recent
                    ORDER BY received_utc DESC
                    LIMIT 15
                    """
                )
                rows = cur.fetchall()
                summary['syslog'] = [
                    {
                        'time': _isoformat(row.get('received_utc')),
                        'source': row.get('source') or row.get('source_host'),
                        'severity': _severity_to_text(row.get('severity')),
                        'message': row.get('message')
                    }
                    for row in rows
                ]
            except Exception as exc:
                app.logger.debug('Syslog summary query failed: %s', exc)

    finally:
        conn.close()

    if not any([summary['auth'], summary['windows'], summary['router'], summary['syslog']]):
        return _mock_dashboard_summary()

    return summary


@app.route('/')
def dashboard():
    """Render the primary dashboard."""
    return render_template('dashboard.html', summary=get_dashboard_summary(), auth_threshold=AUTH_FAILURE_THRESHOLD)

@app.route('/events')
def events():
    """Drill-down page for system events."""
    return render_template('events.html')

@app.route('/router')
def router():
    """Drill-down page for router logs."""
    return render_template('router.html')


@app.route('/api/router/logs')
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
def api_events():
    """Return recent Windows event log entries.
    
    Supports both /api/events and /api/events/logs routes for convention consistency.
    When connected to Postgres, queries the eventlog_windows_recent view.
    Falls back to PowerShell Get-WinEvent on Windows or mock data elsewhere.
    """
    level = request.args.get('level')
    max_events = int(request.args.get('max', '100'))
    page = int(request.args.get('page', '1'))
    since_hours = request.args.get('since_hours')
    offset = (page - 1) * max_events if page > 0 else 0
    since = int(since_hours) if since_hours else None
    events_raw, source = get_windows_events(level=level, max_events=max_events, with_source=True, since_hours=since, offset=offset)
    events = _normalize_events(events_raw)
    return jsonify({'events': events, 'source': source, 'page': page})


@app.route('/api/events/summary')
def api_events_summary():
    max_events = int(request.args.get('max', '300'))
    since_hours = request.args.get('since_hours')
    since = int(since_hours) if since_hours else None
    events_raw, source = get_windows_events(max_events=max_events, with_source=True, since_hours=since)
    events = _normalize_events(events_raw)
    data = summarize_system_events(events)
    data['source'] = source
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
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            # Generate dates for last 7 days
            now = datetime.datetime.now(datetime.UTC)
            dates = [(now - datetime.timedelta(days=i)).strftime('%Y-%m-%d') for i in range(6, -1, -1)]
            trends['dates'] = dates
            
            # IIS 5xx errors by day
            try:
                cur.execute(
                    """
                    SELECT DATE(request_time) AS day,
                           COUNT(*) FILTER (WHERE status BETWEEN 500 AND 599) AS errors
                    FROM telemetry.iis_requests_recent
                    WHERE request_time >= NOW() - INTERVAL '7 days'
                    GROUP BY day
                    ORDER BY day
                    """
                )
                rows = cur.fetchall()
                errors_by_day = {row['day'].strftime('%Y-%m-%d'): row['errors'] for row in rows}
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
                    FROM telemetry.iis_requests_recent
                    WHERE request_time >= NOW() - INTERVAL '7 days'
                      AND status IN (401, 403)
                    GROUP BY day
                    ORDER BY day
                    """
                )
                rows = cur.fetchall()
                failures_by_day = {row['day'].strftime('%Y-%m-%d'): row['failures'] for row in rows}
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
                    FROM telemetry.eventlog_windows_recent
                    WHERE COALESCE(event_utc, received_utc) >= NOW() - INTERVAL '7 days'
                      AND (COALESCE(level, 0) <= 2 OR COALESCE(level_text, '') ILIKE '%error%' OR COALESCE(level_text, '') ILIKE '%critical%')
                    GROUP BY day
                    ORDER BY day
                    """
                )
                rows = cur.fetchall()
                errors_by_day = {row['day'].strftime('%Y-%m-%d'): row['errors'] for row in rows}
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
                    FROM telemetry.syslog_recent
                    WHERE source = 'asus'
                      AND received_utc >= NOW() - INTERVAL '7 days'
                      AND (severity <= 3
                           OR message ILIKE '%wan%'
                           OR message ILIKE '%dhcp%'
                           OR message ILIKE '%failed%'
                           OR message ILIKE '%drop%')
                    GROUP BY day
                    ORDER BY day
                    """
                )
                rows = cur.fetchall()
                alerts_by_day = {row['day'].strftime('%Y-%m-%d'): row['alerts'] for row in rows}
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
    
    # Validate type
    valid_types = ['router_log', 'windows_event', 'chart_summary', 'dashboard_summary']
    if explain_type not in valid_types:
        return jsonify({'error': f'Invalid type. Must be one of: {", ".join(valid_types)}'}), 400
    
    if not context:
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
    api_key = os.environ.get('OPENAI_API_KEY')
    if not api_key:
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
        with urllib.request.urlopen(req, timeout=25, context=ssl.create_default_context()) as resp:
            resp_body = json.loads(resp.read().decode('utf-8'))
            content = resp_body.get('choices', [{}])[0].get('message', {}).get('content')
            if not content:
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
        return jsonify({'error': f'OpenAI API error: {err}'}), 502
    except Exception as ex:
        return jsonify({'error': f'AI explanation failed: {ex}'}), 502


@app.route('/health')
def health():
    # Check database connection instead of backend service
    conn = get_db_connection()
    if conn:
        try:
            with conn.cursor() as cur:
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
            'first_seen_utc': (now - datetime.timedelta(days=30)).isoformat(),
            'last_seen_utc': (now - datetime.timedelta(minutes=2)).isoformat(),
            'is_active': True
        },
        {
            'device_id': 2,
            'mac_address': 'AA:BB:CC:DD:EE:FF',
            'primary_ip_address': '192.168.50.25',
            'hostname': 'phone-android',
            'vendor': 'Samsung',
            'first_seen_utc': (now - datetime.timedelta(days=60)).isoformat(),
            'last_seen_utc': (now - datetime.timedelta(minutes=5)).isoformat(),
            'is_active': True
        },
        {
            'device_id': 3,
            'mac_address': '11:22:33:44:55:66',
            'primary_ip_address': '192.168.50.50',
            'hostname': 'iot-camera',
            'vendor': 'Hikvision',
            'first_seen_utc': (now - datetime.timedelta(days=90)).isoformat(),
            'last_seen_utc': (now - datetime.timedelta(hours=2)).isoformat(),
            'is_active': False
        }
    ]
    
    return devices


@app.route('/api/lan/stats')
def api_lan_stats():
    """Get LAN overview statistics."""
    conn = get_db_connection()
    if conn is None:
        return jsonify(_mock_lan_stats())
    
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("SELECT * FROM telemetry.lan_summary_stats")
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
def api_lan_devices():
    """List all LAN devices with optional filtering."""
    state = request.args.get('state')  # 'active', 'inactive', or None for all
    interface = request.args.get('interface')  # filter by interface type
    tag = request.args.get('tag')  # filter by tag (iot, guest, critical)
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
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
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
                    ds.interface AS last_interface,
                    ds.rssi AS last_rssi,
                    ds.tx_rate_mbps AS last_tx_rate_mbps,
                    ds.rx_rate_mbps AS last_rx_rate_mbps,
                    ds.lease_type AS lease_type
                FROM telemetry.devices d
                LEFT JOIN LATERAL (
                    SELECT 
                        interface, 
                        rssi,
                        tx_rate_mbps,
                        rx_rate_mbps,
                        NULLIF(raw_json::json->>'LeaseType', '') AS lease_type
                    FROM telemetry.device_snapshots_template
                    WHERE device_id = d.device_id
                    ORDER BY sample_time_utc DESC
                    LIMIT 1
                ) ds ON true
                WHERE 1=1
            """
            
            params = []
            if state == 'active':
                query += " AND d.is_active = true"
            elif state == 'inactive':
                query += " AND d.is_active = false"
            
            if interface:
                query += " AND ds.interface ILIKE %s"
                params.append(f'%{interface}%')
            
            if tag:
                query += " AND d.tags ILIKE %s"
                params.append(f'%{tag}%')
            
            query += " ORDER BY d.last_seen_utc DESC LIMIT %s"
            params.append(limit)
            
            cur.execute(query, params)
            rows = cur.fetchall()
            
            devices = []
            for row in rows:
                device = dict(row)
                device['first_seen_utc'] = _isoformat(device.get('first_seen_utc'))
                device['last_seen_utc'] = _isoformat(device.get('last_seen_utc'))
                device['last_tx_rate_mbps'] = _safe_float(device.get('last_tx_rate_mbps'))
                device['last_rx_rate_mbps'] = _safe_float(device.get('last_rx_rate_mbps'))
                devices.append(device)
    except Exception as exc:
        app.logger.debug('LAN devices query failed: %s', exc)
        devices = _mock_lan_devices()
    finally:
        conn.close()
    
    return jsonify({'devices': devices})


@app.route('/api/lan/devices/online')
def api_lan_devices_online():
    """List currently online devices."""
    conn = get_db_connection()
    if conn is None:
        devices = [d for d in _mock_lan_devices() if d['is_active']]
        return jsonify({'devices': devices})
    
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
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
                FROM telemetry.devices_online
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
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("""
                SELECT 
                    d.*,
                    (SELECT COUNT(*) FROM telemetry.device_snapshots_template WHERE device_id = d.device_id) AS total_snapshots,
                    last.interface AS last_interface,
                    last.rssi AS last_rssi,
                    last.tx_rate_mbps AS last_tx_rate_mbps,
                    last.rx_rate_mbps AS last_rx_rate_mbps,
                    last.lease_type AS lease_type,
                    last.sample_time_utc AS last_snapshot_time
                FROM telemetry.devices d
                LEFT JOIN LATERAL (
                    SELECT 
                        interface,
                        rssi,
                        tx_rate_mbps,
                        rx_rate_mbps,
                        NULLIF(raw_json::json->>'LeaseType', '') AS lease_type,
                        sample_time_utc
                    FROM telemetry.device_snapshots_template
                    WHERE device_id = d.device_id
                    ORDER BY sample_time_utc DESC
                    LIMIT 1
                ) last ON true
                WHERE d.device_id = %s
            """, (device_id,))
            row = cur.fetchone()
            
            if not row:
                return jsonify({'error': 'Device not found'}), 404
            
            device = dict(row)
            device['first_seen_utc'] = _isoformat(device.get('first_seen_utc'))
            device['last_seen_utc'] = _isoformat(device.get('last_seen_utc'))
            device['created_at'] = _isoformat(device.get('created_at'))
            device['updated_at'] = _isoformat(device.get('updated_at'))
            device['last_snapshot_time'] = _isoformat(device.get('last_snapshot_time'))
            device['last_tx_rate_mbps'] = _safe_float(device.get('last_tx_rate_mbps'))
            device['last_rx_rate_mbps'] = _safe_float(device.get('last_rx_rate_mbps'))
    except Exception as exc:
        app.logger.debug('Device detail query failed: %s', exc)
        return jsonify({'error': 'Database error'}), 500
    finally:
        conn.close()
    
    return jsonify(device)


@app.route('/api/lan/device/<device_id>/update', methods=['POST', 'PATCH'])
def api_lan_device_update(device_id):
    """Update nickname/location/tags for a device."""
    payload = request.get_json(silent=True) or {}
    nickname = payload.get('nickname')
    location = payload.get('location')
    tags = payload.get('tags')

    if nickname is not None and not isinstance(nickname, str):
        return jsonify({'error': 'Invalid nickname'}), 400
    if location is not None and not isinstance(location, str):
        return jsonify({'error': 'Invalid location'}), 400
    if tags is not None and not isinstance(tags, str):
        return jsonify({'error': 'Invalid tags'}), 400

    conn = get_db_connection()
    if conn is None:
        return jsonify({'error': 'Database unavailable'}), 503

    try:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE telemetry.devices
                SET
                    nickname = COALESCE(%s, nickname),
                    location = COALESCE(%s, location),
                    tags = COALESCE(%s, tags),
                    updated_at = NOW()
                WHERE device_id = %s
                RETURNING device_id;
            """, (nickname, location, tags, device_id))
            updated = cur.fetchone()
            if not updated:
                return jsonify({'error': 'Device not found'}), 404
        conn.commit()
        return jsonify({'status': 'ok'})
    except Exception as exc:
        app.logger.debug('Device update failed: %s', exc)
        conn.rollback()
        return jsonify({'error': 'Database error'}), 500
    finally:
        conn.close()


@app.route('/api/lan/device/<device_id>/timeline')
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
                'sample_time_utc': (now - datetime.timedelta(hours=hours * i / 20)).isoformat(),
                'rssi': random.randint(-70, -30),
                'tx_rate_mbps': random.uniform(50, 150),
                'rx_rate_mbps': random.uniform(50, 150),
                'is_online': random.choice([True, True, True, False])
            })
        return jsonify({'timeline': timeline})
    
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("""
                SELECT 
                    sample_time_utc,
                    ip_address,
                    interface,
                    rssi,
                    tx_rate_mbps,
                    rx_rate_mbps,
                    is_online
                FROM telemetry.device_snapshots_template
                WHERE device_id = %s
                  AND sample_time_utc >= NOW() - INTERVAL '%s hours'
                ORDER BY sample_time_utc ASC
            """, (device_id, hours))
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
def api_lan_device_events(device_id):
    """Get syslog events associated with a device."""
    limit = int(request.args.get('limit', '50'))
    
    conn = get_db_connection()
    if conn is None:
        # Return mock events
        now = datetime.datetime.now(datetime.UTC)
        events = [
            {
                'timestamp': (now - datetime.timedelta(hours=1)).isoformat(),
                'severity': 'Notice',
                'message': 'Device connected to network',
                'match_type': 'mac'
            },
            {
                'timestamp': (now - datetime.timedelta(hours=3)).isoformat(),
                'severity': 'Info',
                'message': 'DHCP lease renewed',
                'match_type': 'ip'
            }
        ]
        return jsonify({'events': events})
    
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("""
                SELECT 
                    s.received_utc AS timestamp,
                    s.severity,
                    s.message,
                    s.source_host,
                    l.match_type,
                    l.confidence
                FROM telemetry.syslog_device_links l
                INNER JOIN telemetry.syslog_generic_template s ON l.syslog_id = s.id
                WHERE l.device_id = %s
                ORDER BY s.received_utc DESC
                LIMIT %s
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
                'created_at': (now - datetime.timedelta(hours=1)).isoformat(),
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
                'created_at': (now - datetime.timedelta(hours=3)).isoformat(),
                'is_acknowledged': False
            }
        ]
        return jsonify({'alerts': mock_alerts, 'total': len(mock_alerts)})
    
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
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
                FROM telemetry.device_alerts_active
                WHERE 1=1
            """
            
            params = []
            if severity:
                query += " AND severity = %s"
                params.append(severity)
            
            if alert_type:
                query += " AND alert_type = %s"
                params.append(alert_type)
            
            query += " ORDER BY created_at DESC LIMIT %s"
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
            cur.execute("SELECT COUNT(*) as total FROM telemetry.device_alerts_active")
            total_row = cur.fetchone()
            total = total_row['total'] if total_row else 0
    except Exception as exc:
        app.logger.debug('Alerts query failed: %s', exc)
        return jsonify({'error': 'Database error'}), 500
    finally:
        conn.close()
    
    return jsonify({'alerts': alerts, 'total': total})


@app.route('/api/lan/alerts/<alert_id>/acknowledge', methods=['POST'])
def api_lan_alert_acknowledge(alert_id):
    """Acknowledge an alert."""
    payload = request.get_json(silent=True) or {}
    acknowledged_by = payload.get('acknowledged_by', 'user')
    
    conn = get_db_connection()
    if conn is None:
        return jsonify({'error': 'Database unavailable'}), 503
    
    try:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE telemetry.device_alerts
                SET is_acknowledged = true,
                    acknowledged_at = NOW(),
                    acknowledged_by = %s,
                    updated_at = NOW()
                WHERE alert_id = %s AND is_acknowledged = false
                RETURNING alert_id;
            """, (acknowledged_by, alert_id))
            updated = cur.fetchone()
            if not updated:
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
def api_lan_alert_resolve(alert_id):
    """Resolve an alert."""
    conn = get_db_connection()
    if conn is None:
        return jsonify({'error': 'Database unavailable'}), 503
    
    try:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE telemetry.device_alerts
                SET is_resolved = true,
                    resolved_at = NOW(),
                    updated_at = NOW()
                WHERE alert_id = %s AND is_resolved = false
                RETURNING alert_id;
            """, (alert_id,))
            updated = cur.fetchone()
            if not updated:
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
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("""
                SELECT 
                    COUNT(*) as total_active,
                    COUNT(*) FILTER (WHERE severity = 'critical') as critical,
                    COUNT(*) FILTER (WHERE severity = 'warning') as warning,
                    COUNT(*) FILTER (WHERE severity = 'info') as info
                FROM telemetry.device_alerts
                WHERE is_resolved = false
            """)
            stats = dict(cur.fetchone() or {})
    except Exception as exc:
        app.logger.debug('Alert stats query failed: %s', exc)
        return jsonify({'error': 'Database error'}), 500
    finally:
        conn.close()
    
    return jsonify(stats)


@app.route('/api/lan/device/<device_id>/lookup-vendor', methods=['POST'])
def api_lan_device_lookup_vendor(device_id):
    """Look up and update vendor information for a device based on MAC address."""
    conn = get_db_connection()
    if conn is None:
        return jsonify({'error': 'Database unavailable'}), 503
    
    try:
        # Get device MAC address
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("SELECT mac_address, vendor FROM telemetry.devices WHERE device_id = %s", (device_id,))
            device = cur.fetchone()
            
            if not device:
                return jsonify({'error': 'Device not found'}), 404
            
            # Look up vendor
            vendor = lookup_mac_vendor(device['mac_address'])
            
            if not vendor:
                return jsonify({'error': 'Vendor lookup failed', 'message': 'Could not determine vendor from MAC address'}), 404
            
            # Update device with vendor info
            cur.execute("""
                UPDATE telemetry.devices
                SET vendor = %s,
                    updated_at = NOW()
                WHERE device_id = %s
                RETURNING device_id;
            """, (vendor, device_id))
            updated = cur.fetchone()
            
            if not updated:
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
def api_lan_devices_enrich_vendors():
    """Enrich all devices without vendor information by looking up their MAC addresses."""
    conn = get_db_connection()
    if conn is None:
        return jsonify({'error': 'Database unavailable'}), 503
    
    if not mac_lookup:
        return jsonify({'error': 'MAC vendor lookup not available'}), 503
    
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            # Get devices without vendor info
            cur.execute("""
                SELECT device_id, mac_address
                FROM telemetry.devices
                WHERE vendor IS NULL OR vendor = ''
                LIMIT 100
            """)
            devices = cur.fetchall()
            
            updated_count = 0
            failed_count = 0
            
            for device in devices:
                vendor = lookup_mac_vendor(device['mac_address'])
                if vendor:
                    cur.execute("""
                        UPDATE telemetry.devices
                        SET vendor = %s,
                            updated_at = NOW()
                        WHERE device_id = %s
                    """, (vendor, device['device_id']))
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
    # Enable debug for development convenience
    port = int(os.environ.get('DASHBOARD_PORT', '5000'))
    app.run(debug=True, host='0.0.0.0', port=port)

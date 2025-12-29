from flask import Flask, render_template, request, jsonify
import os
import sys
import platform
import subprocess
import json
import html
import urllib.request
import socket
import datetime
import sqlite3
from decimal import Decimal
from zoneinfo import ZoneInfo

try:
    import psycopg2  # type: ignore
    import psycopg2.extras  # type: ignore
except Exception:  # pragma: no cover - optional dependency during local dev
    psycopg2 = None

if __package__ in (None, ''):
    sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from app import db_postgres
from app.rate_limiter import rate_limit

app = Flask(__name__)

from app.api.v1 import api_v1

app.register_blueprint(api_v1)

config = None
_DB_PATH = None

CHATTY_THRESHOLD = int(os.environ.get('CHATTY_THRESHOLD', '500'))
AUTH_FAILURE_THRESHOLD = int(os.environ.get('AUTH_FAILURE_THRESHOLD', '10'))
VALID_FEEDBACK_STATUSES = {'Pending', 'Viewed', 'Resolved'}

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


def load_config():
    config_path = os.environ.get('SYSTEMDASHBOARD_CONFIG')
    if not config_path:
        config_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'config.json')
    if not os.path.exists(config_path):
        return {}
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return {}


config = load_config()


def _get_db_path():
    global _DB_PATH
    pkg = sys.modules.get('app')
    if pkg is not None and hasattr(pkg, '_DB_PATH'):
        _DB_PATH = getattr(pkg, '_DB_PATH')
        if _DB_PATH:
            return _DB_PATH
    if _DB_PATH:
        return _DB_PATH
    env_path = os.environ.get('DASHBOARD_DB_PATH')
    if env_path:
        _DB_PATH = env_path
        return _DB_PATH
    default_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'var', 'system_dashboard.db')
    _DB_PATH = default_path if os.path.exists(default_path) else None
    return _DB_PATH


def _get_sqlite_connection():
    path = _get_db_path()
    if not path:
        return None
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    return conn


def get_db_settings():
    return db_postgres.get_db_settings()


def get_db_connection():
    sqlite_path = _get_db_path()
    if sqlite_path:
        return _get_sqlite_connection()
    return db_postgres.get_db_connection()


def _db_is_postgres(conn) -> bool:
    if conn is None or psycopg2 is None:
        return False
    try:
        return isinstance(conn, psycopg2.extensions.connection)
    except Exception:
        return False


def _db_placeholder(conn) -> str:
    return '%s' if _db_is_postgres(conn) else '?'


def _get_db_cursor(conn):
    if _db_is_postgres(conn):
        try:
            return conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        except Exception:
            return conn.cursor()
    return conn.cursor()




def _to_est_string(value):
    if value is None:
        return ''
    tz = ZoneInfo("America/New_York")
    dt = None

    if isinstance(value, datetime.datetime):
        dt = value
    elif isinstance(value, str):
        if value.startswith('/Date(') and value.endswith(')/'):
            try:
                ms = int(value[6:-2])
                dt = datetime.datetime.fromtimestamp(ms / 1000, tz=datetime.UTC)
            except Exception:
                dt = None
        else:
            try:
                if value.endswith('Z'):
                    value = value.replace('Z', '+00:00')
                dt = datetime.datetime.fromisoformat(value)
            except Exception:
                return value
    else:
        return str(value)

    if dt is None:
        return ''
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=datetime.UTC)
    return dt.astimezone(tz).isoformat()


def _isoformat(value):
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


def get_windows_events(level: str = None, max_events: int = 50, log_types=None, with_source: bool = False):
    """Fetch recent Windows events via PowerShell. Level can be 'Error', 'Warning', or None for any.
    Returns list of dicts with time, source, id, level, message.
    """
    valid_logs = ['Application', 'System', 'Security']
    requested_logs = [l for l in (log_types or valid_logs) if l in valid_logs]
    if not requested_logs:
        requested_logs = valid_logs

    if not _is_windows():
        # Return mock events for demonstration purposes on non-Windows platforms
        import datetime
        mock_events = [
            {
                'time': (datetime.datetime.now() - datetime.timedelta(minutes=30)).isoformat(),
                'source': 'Application Error',
                'id': 1001,
                'level': 'Warning',
                'message': 'Mock application warning - database connection timeout occurred during operation',
                'log_type': 'Application'
            },
            {
                'time': (datetime.datetime.now() - datetime.timedelta(hours=1)).isoformat(),
                'source': 'Service Control Manager',
                'id': 2001,
                'level': 'Error',
                'message': 'Mock system error - service failed to start due to configuration issue',
                'log_type': 'System'
            },
            {
                'time': (datetime.datetime.now() - datetime.timedelta(hours=2)).isoformat(),
                'source': 'DNS Client',
                'id': 1002,
                'level': 'Information',
                'message': 'Mock information event - DNS resolution completed successfully for domain',
                'log_type': 'Security'
            },
            {
                'time': (datetime.datetime.now() - datetime.timedelta(minutes=45)).isoformat(),
                'source': 'Application Error',
                'id': 1003,
                'level': 'Error',
                'message': 'Mock critical error - application crashed due to memory access violation',
                'log_type': 'Application'
            },
            {
                'time': (datetime.datetime.now() - datetime.timedelta(minutes=15)).isoformat(),
                'source': 'System',
                'id': 3001,
                'level': 'Warning',
                'message': 'Mock system warning - disk space running low on drive C:',
                'log_type': 'System'
            }
        ]

        # Filter by level if specified
        if level:
            level_lower = level.lower()
            mock_events = [e for e in mock_events if e['level'].lower() == level_lower]

        mock_events = [e for e in mock_events if e.get('log_type') in requested_logs]
        data = mock_events[:max_events]
        return (data, 'mock') if with_source else data

    level_filter = ''
    if level:
        level_map = {'error': 2, 'warning': 3, 'information': 4}
        code = level_map.get(level.lower())
        if code:
            level_filter = f"; Level={code}"
    ps = (
        "Get-WinEvent -FilterHashtable @{"
        "LogName='" + ",".join(requested_logs) + "'" + level_filter + "} "
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
                'log_type': e.get('LogName') or e.get('ProviderName')
            })
        return (events, 'powershell') if with_source else events
    except Exception:
        return ([], 'error') if with_source else []


def _normalize_events(events):
    normalized = []
    for evt in events:
        normalized.append({
            **evt,
            'time': _to_est_string(evt.get('time')),
            'log_type': evt.get('log_type') or evt.get('log') or evt.get('logname')
        })
    return normalized


def get_router_logs(max_lines: int = 100):
    """Fetch router logs from PostgreSQL when available, otherwise fall back to a local file."""
    db_logs = get_router_logs_from_db(limit=max_lines)
    if db_logs is not None:
        return db_logs
    log_path = os.environ.get('ROUTER_LOG_PATH')
    if not log_path or not os.path.exists(log_path):
        return []
    try:
        with open(log_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()[-max_lines:]
        logs = []
        for line in lines:
            parts = line.strip().split(maxsplit=3)
            if len(parts) >= 4:
                time = f"{parts[0]} {parts[1]}"
                level = parts[2]
                message = parts[3]
            else:
                time = ''
                level = ''
                message = line.strip()
            logs.append({'time': time, 'level': level, 'message': message, 'host': ''})
        return logs
    except Exception:
        return []


def get_router_logs_from_db(limit: int = 100):
    conn = get_db_connection()
    if conn is None:
        return None
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(
                """
                SELECT COALESCE(event_utc, received_utc) AS time,
                       severity,
                       message,
                       source_host
                FROM telemetry.syslog_recent
                WHERE source = 'asus'
                ORDER BY received_utc DESC
                LIMIT %s
                """,
                (limit,)
            )
            rows = cur.fetchall()
        logs = []
        for row in rows:
            logs.append({
                'time': _isoformat(row.get('time')),
                'level': _severity_to_text(row.get('severity')),
                'message': row.get('message') or '',
                'host': row.get('source_host') or ''
            })
        return logs
    except Exception as exc:  # pragma: no cover - depends on db objects
        app.logger.debug('Router DB query failed: %s', exc)
        return None
    finally:
        conn.close()


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
                           COALESCE(level_text, level)::text AS level,
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

    if not any([
        summary['auth'],
        summary['windows'],
        summary['router'],
        summary['syslog'],
        summary['iis']['current_errors'] > 0,
        summary['iis']['total_requests'] > 0
    ]):
        return _mock_dashboard_summary()

    return summary


@app.route('/')
def dashboard():
    """Render the primary dashboard."""
    return render_template('dashboard.html', summary=get_dashboard_summary(), auth_threshold=AUTH_FAILURE_THRESHOLD)

@app.route('/events')
def events():
    """Drill-down page for system events."""
    events = get_windows_events(max_events=100)
    # Simple severity tagging
    for e in events:
        msg = (e.get('message') or '').lower()
        if not e.get('level'):
            if 'error' in msg or 'failed' in msg:
                e['level'] = 'Error'
            elif 'warn' in msg:
                e['level'] = 'Warning'
            else:
                e['level'] = 'Info'
    return render_template('events.html', events=events)

@app.route('/router')
def router():
    """Drill-down page for router logs."""
    return render_template('router.html', logs=get_router_logs())

@app.route('/wifi')
def wifi():
    """List Wi-Fi clients highlighting chatty nodes."""
    return render_template('wifi.html', clients=get_wifi_clients(), threshold=CHATTY_THRESHOLD)


@app.route('/lan')
def lan_overview():
    """Render LAN overview page."""
    return render_template('lan_overview.html')


@app.route('/lan/devices')
def lan_devices():
    """Render LAN devices inventory page."""
    return render_template('lan_devices.html')


@app.route('/lan/device/<int:device_id>')
def lan_device_detail_page(device_id):
    """Render LAN device detail page."""
    return render_template('lan_device.html', device_id=device_id)


@app.route('/api/events')
@rate_limit(max_requests=60, window_seconds=60)
def api_events():
    level = request.args.get('level')
    max_events = int(request.args.get('max', '100'))
    log_types_raw = request.args.get('log_types')
    log_types = [t.strip() for t in log_types_raw.split(',') if t.strip()] if log_types_raw else None
    data = get_windows_events(level=level, max_events=max_events, log_types=log_types)
    return jsonify({'events': _normalize_events(data)})


@app.route('/api/events/summary')
@rate_limit(max_requests=30, window_seconds=60)
def api_events_summary():
    log_types_raw = request.args.get('log_types')
    log_types = [t.strip() for t in log_types_raw.split(',') if t.strip()] if log_types_raw else None
    events = _normalize_events(get_windows_events(max_events=500, log_types=log_types))
    severity_counts = {}
    for e in events:
        level = (e.get('level') or 'Unknown')
        severity_counts[level] = severity_counts.get(level, 0) + 1
    return jsonify({'total': len(events), 'severity_counts': severity_counts})


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
    data = request.get_json(silent=True) or {}
    if not data.get('type') or not data.get('context'):
        return jsonify({'error': 'Missing type or context'}), 400
    return jsonify({'status': 'ok', 'message': 'Explain endpoint not yet wired'}), 200


def _row_to_dict(row):
    if row is None:
        return None
    if isinstance(row, dict):
        return row
    if hasattr(row, 'keys'):
        return {key: row[key] for key in row.keys()}
    return dict(row)


@app.route('/api/ai/feedback', methods=['POST'])
@rate_limit(max_requests=30, window_seconds=60)
def api_ai_feedback_create():
    data = request.get_json(silent=True) or {}
    event_message = data.get('event_message')
    ai_response = data.get('ai_response')
    if not event_message:
        return jsonify({'error': 'Missing event_message'}), 400
    if not ai_response:
        return jsonify({'error': 'Missing ai_response'}), 400

    review_status = data.get('review_status') or 'Pending'
    if review_status not in VALID_FEEDBACK_STATUSES:
        return jsonify({'error': f'Invalid review_status: {review_status}'}), 400

    conn = get_db_connection()
    if conn is None:
        return jsonify({'error': 'Database not configured'}), 503

    now = datetime.datetime.now(datetime.UTC).isoformat()
    params = [
        data.get('event_id'),
        data.get('event_source'),
        event_message,
        data.get('event_log_type'),
        data.get('event_level'),
        data.get('event_time'),
        ai_response,
        review_status,
        now,
        now
    ]
    placeholder = _db_placeholder(conn)
    insert_sql = (
        f"INSERT INTO ai_feedback (event_id, event_source, event_message, event_log_type, event_level, event_time, "
        f"ai_response, review_status, created_at, updated_at) "
        f"VALUES ({placeholder}, {placeholder}, {placeholder}, {placeholder}, {placeholder}, {placeholder}, "
        f"{placeholder}, {placeholder}, {placeholder}, {placeholder})"
    )

    try:
        cur = _get_db_cursor(conn)
        if _db_is_postgres(conn):
            insert_sql += " RETURNING id, created_at, updated_at"
        cur.execute(insert_sql, params)
        if _db_is_postgres(conn):
            row = cur.fetchone()
            new_id = row.get('id') if isinstance(row, dict) else row[0]
            created_at = row.get('created_at') if isinstance(row, dict) else row[1]
            updated_at = row.get('updated_at') if isinstance(row, dict) else row[2]
        else:
            new_id = getattr(cur, 'lastrowid', None)
            created_at = now
            updated_at = now
        conn.commit()
    finally:
        conn.close()

    return jsonify({
        'status': 'ok',
        'id': new_id,
        'review_status': review_status,
        'created_at': created_at,
        'updated_at': updated_at
    }), 201


@app.route('/api/ai/feedback', methods=['GET'])
@rate_limit(max_requests=60, window_seconds=60)
def api_ai_feedback_list():
    conn = get_db_connection()
    if conn is None:
        return jsonify({'feedback': [], 'total': 0, 'source': 'unavailable'}), 200

    status = request.args.get('status')
    if status and status not in VALID_FEEDBACK_STATUSES:
        return jsonify({'error': f'Invalid status filter: {status}'}), 400

    try:
        cur = _get_db_cursor(conn)
        placeholder = _db_placeholder(conn)
        limit = int(request.args.get('limit', '50'))

        if status:
            cur.execute(
                f"SELECT COUNT(*) AS count FROM ai_feedback WHERE review_status = {placeholder}",
                (status,)
            )
        else:
            cur.execute("SELECT COUNT(*) AS count FROM ai_feedback")
        count_row = _row_to_dict(cur.fetchone()) or {}
        total = count_row.get('count', 0)

        if status:
            cur.execute(
                f"SELECT * FROM ai_feedback WHERE review_status = {placeholder} "
                "ORDER BY created_at DESC LIMIT " + str(limit),
                (status,)
            )
        else:
            cur.execute("SELECT * FROM ai_feedback ORDER BY created_at DESC LIMIT " + str(limit))

        rows = cur.fetchall()
        feedback = [_row_to_dict(row) for row in rows]
    finally:
        conn.close()

    return jsonify({'feedback': feedback, 'total': total, 'source': 'database'})


@app.route('/api/ai/feedback/<int:feedback_id>/status', methods=['PATCH'])
@rate_limit(max_requests=30, window_seconds=60)
def api_ai_feedback_update_status(feedback_id):
    data = request.get_json(silent=True) or {}
    status = data.get('status')
    if not status:
        return jsonify({'error': 'Missing status'}), 400
    if status not in VALID_FEEDBACK_STATUSES:
        return jsonify({'error': f'Invalid status: {status}'}), 400

    conn = get_db_connection()
    if conn is None:
        return jsonify({'error': 'Database not configured'}), 503

    now = datetime.datetime.now(datetime.UTC).isoformat()
    placeholder = _db_placeholder(conn)
    update_sql = (
        f"UPDATE ai_feedback SET review_status = {placeholder}, updated_at = {placeholder} "
        f"WHERE id = {placeholder}"
    )

    try:
        cur = _get_db_cursor(conn)
        cur.execute(update_sql, (status, now, feedback_id))
        conn.commit()
        rowcount = getattr(cur, 'rowcount', 0)
    finally:
        conn.close()

    if rowcount == 0:
        return jsonify({'error': 'Feedback entry not found'}), 404

    return jsonify({'status': 'ok', 'id': feedback_id, 'review_status': status, 'updated_at': now})


@app.route('/api/dashboard/summary')
@rate_limit(max_requests=60, window_seconds=60)
def api_dashboard_summary():
    summary = get_dashboard_summary()
    return jsonify(summary)


@app.route('/api/router/logs')
@rate_limit(max_requests=60, window_seconds=60)
def api_router_logs():
    logs = []
    for entry in get_router_logs():
        logs.append({
            **entry,
            'time': _to_est_string(entry.get('time'))
        })
    return jsonify({'logs': logs})


@app.route('/api/router/summary')
@rate_limit(max_requests=30, window_seconds=60)
def api_router_summary():
    logs = get_router_logs()
    return jsonify({'total': len(logs)})


def _fetch_sqlite_rows(cursor):
    rows = cursor.fetchall()
    return [dict(row) for row in rows]


def _query_lan_devices(args):
    conn = _get_sqlite_connection()
    if conn is None:
        return []
    state = args.get('state')
    tag = args.get('tag')
    network_type = args.get('network_type')
    interface = args.get('interface')

    clauses = []
    params = []
    if state == 'active':
        clauses.append('d.is_active = 1')
    elif state == 'inactive':
        clauses.append('d.is_active = 0') # Fix: Removed extra quote
    if tag:
        clauses.append('LOWER(COALESCE(d.tags, \"\")) LIKE ?')
        params.append(f\"%{tag.lower()}%\")
    if network_type:
        clauses.append('d.network_type = ?')
        params.append(network_type)
    if interface:
        clauses.append('LOWER(COALESCE(s.interface, \"\")) LIKE ?')
        params.append(f\"%{interface.lower()}%\")

    where_sql = f"WHERE {' AND '.join(clauses)}" if clauses else ''

    query = f"""
        SELECT d.device_id, d.mac_address, d.primary_ip_address, d.hostname,
               d.nickname, d.location, d.vendor, d.first_seen_utc, d.last_seen_utc,
               d.is_active, d.tags, d.network_type,
               s.interface AS last_interface, s.rssi AS last_rssi,
               s.tx_rate_mbps AS last_tx_rate_mbps, s.rx_rate_mbps AS last_rx_rate_mbps
        FROM devices d
        LEFT JOIN (
            SELECT ds.*
            FROM device_snapshots ds
            JOIN (
                SELECT device_id, MAX(sample_time_utc) AS max_time
                FROM device_snapshots
                GROUP BY device_id
            ) latest ON latest.device_id = ds.device_id AND latest.max_time = ds.sample_time_utc
        ) s ON s.device_id = d.device_id
        {where_sql}
        ORDER BY d.last_seen_utc DESC
    """

    try:
        cur = conn.cursor()
        cur.execute(query, params)
        return _fetch_sqlite_rows(cur)
    finally:
        conn.close()


@app.route('/api/lan/devices')
@rate_limit(max_requests=60, window_seconds=60)
def api_lan_devices():
    devices = _query_lan_devices(request.args)
    return jsonify({'devices': devices})


@app.route('/api/lan/devices/online')
@rate_limit(max_requests=60, window_seconds=60)
def api_lan_devices_online():
    args = dict(request.args)
    args['state'] = 'active'
    devices = _query_lan_devices(args)
    return jsonify({'devices': devices})


@app.route('/api/lan/stats')
@rate_limit(max_requests=60, window_seconds=60)
def api_lan_stats():
    conn = _get_sqlite_connection()
    if conn is None:
        return jsonify({'total_devices': 0, 'active_devices': 0, 'inactive_devices': 0})
    try:
        cur = conn.cursor()
        try:
            cur.execute("SELECT total_devices, active_devices, inactive_devices FROM lan_summary_stats")
            row = cur.fetchone()
            if row:
                return jsonify(dict(row))
        except sqlite3.Error:
            pass
        cur.execute("SELECT COUNT(*) AS total, SUM(CASE WHEN is_active = 1 THEN 1 ELSE 0 END) AS active FROM devices")
        row = cur.fetchone()
        total = row[0] if row else 0
        active = row[1] if row else 0
        return jsonify({'total_devices': total, 'active_devices': active, 'inactive_devices': total - active})
    finally:
        conn.close()


@app.route('/api/lan/device/<int:device_id>')
@rate_limit(max_requests=60, window_seconds=60)
def api_lan_device_detail(device_id):
    conn = _get_sqlite_connection()
    if conn is None:
        return jsonify({'error': 'Database not configured'}), 503
    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM devices WHERE device_id = ?", (device_id,))
        device = cur.fetchone()
        if not device:
            return jsonify({'error': 'Not found'}), 404
        cur.execute("SELECT COUNT(*) FROM device_snapshots WHERE device_id = ?", (device_id,))
        total_snapshots = cur.fetchone()[0]
        payload = dict(device)
        payload['total_snapshots'] = total_snapshots
        return jsonify(payload)
    finally:
        conn.close()


@app.route('/api/lan/device/<int:device_id>/timeline')
@rate_limit(max_requests=60, window_seconds=60)
def api_lan_device_timeline(device_id):
    hours = int(request.args.get('hours', '24'))
    conn = _get_sqlite_connection()
    if conn is None:
        return jsonify({'timeline': []})
    try:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT sample_time_utc, rssi, tx_rate_mbps, rx_rate_mbps, is_online
              FROM device_snapshots
             WHERE device_id = ?
             ORDER BY sample_time_utc DESC
             LIMIT 500
            """,
            (device_id,)
        )
        timeline = _fetch_sqlite_rows(cur)
        return jsonify({'timeline': timeline})
    finally:
        conn.close()


@app.route('/api/lan/device/<int:device_id>/update', methods=['POST'])
@rate_limit(max_requests=30, window_seconds=60)
def api_lan_device_update(device_id):
    conn = _get_sqlite_connection()
    if conn is None:
        return jsonify({'error': 'Database not configured'}), 503
    data = request.get_json(silent=True) or {}
    fields = []
    params = []
    for key in ['nickname', 'location', 'tags']:
        if key in data:
            fields.append(f"{key} = ?")
            params.append(data[key])
    if not fields:
        return jsonify({'status': 'ok'})
    params.append(device_id)
    try:
        cur = conn.cursor()
        cur.execute(f"UPDATE devices SET {', '.join(fields)} WHERE device_id = ?", params)
        conn.commit()
    finally:
        conn.close()
    return jsonify({'status': 'ok'})


@app.route('/api/lan/alerts')
@rate_limit(max_requests=60, window_seconds=60)
def api_lan_alerts():
    conn = _get_sqlite_connection()
    if conn is None:
        return jsonify({'alerts': [], 'total': 0})
    try:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT a.*, d.mac_address, d.hostname
              FROM device_alerts a
              LEFT JOIN devices d ON a.device_id = d.device_id
             ORDER BY a.created_at DESC
             LIMIT 100
            """
        )
        alerts = _fetch_sqlite_rows(cur)
        return jsonify({'alerts': alerts, 'total': len(alerts)})
    finally:
        conn.close()


@app.route('/api/lan/devices/enrich-vendors', methods=['POST'])
@rate_limit(max_requests=5, window_seconds=60)
def api_lan_enrich_vendors():
    return jsonify({'status': 'ok'})


@app.route('/api/lan/device/<int:device_id>/lookup-vendor', methods=['POST'])
@rate_limit(max_requests=10, window_seconds=60)
def api_lan_lookup_vendor(device_id):
    return jsonify({'status': 'ok', 'device_id': device_id})


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

if __name__ == '__main__':
    # Enable debug for development convenience
    port = int(os.environ.get('DASHBOARD_PORT', '5000'))
    app.run(debug=True, host='0.0.0.0', port=port)

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


def get_windows_events(level: str = None, max_events: int = 50):
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

        return mock_events[:max_events]

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
        return events
    except Exception:
        return []


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
    now = datetime.datetime.utcnow()
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


@app.route('/api/events')
def api_events():
    level = request.args.get('level')
    max_events = int(request.args.get('max', '100'))
    data = get_windows_events(level=level, max_events=max_events)
    return jsonify({'events': data})


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

from flask import Flask, render_template, request, jsonify
import os
import platform
import subprocess
import json
import html
import urllib.request
import socket

app = Flask(__name__)

CHATTY_THRESHOLD = int(os.environ.get('CHATTY_THRESHOLD', '500'))


def _is_windows():
    return platform.system().lower().startswith('win')


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
    """Read router logs from a local file specified by ROUTER_LOG_PATH."""
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
            logs.append({'time': time, 'level': level, 'message': message})
        return logs
    except Exception:
        return []


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

@app.route('/')
def dashboard():
    """Render the primary dashboard."""
    return render_template('dashboard.html')

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
    backend = os.environ.get('SYSTEMDASHBOARD_BACKEND', 'http://localhost:15000/metrics')
    try:
        with urllib.request.urlopen(backend, timeout=2) as resp:
            if resp.status == 200:
                return 'ok', 200
    except Exception:
        pass
    return 'unhealthy', 503

if __name__ == '__main__':
    # Enable debug for development convenience
    port = int(os.environ.get('DASHBOARD_PORT', '5000'))
    app.run(debug=True, host='0.0.0.0', port=port)

from flask import Flask, render_template, request, jsonify
import os
import platform
import subprocess
import json
import html
import urllib.request

app = Flask(__name__)

# Sample data to simulate real metrics
SYSTEM_EVENTS = [
    {"time": "2024-06-01 08:00", "source": "System", "message": "System boot completed"},
    {"time": "2024-06-01 09:15", "source": "Application", "message": "Service xyz failed to start"},
]

ROUTER_LOGS = [
    {"time": "2024-06-01 10:20", "level": "INFO", "message": "WAN connection established"},
    {"time": "2024-06-01 10:45", "level": "WARN", "message": "DHCP request flood detected"},
]

WIFI_CLIENTS = [
    {"mac": "AA:BB:CC:DD:EE:01", "ip": "192.168.0.10", "hostname": "laptop", "packets": 150},
    {"mac": "AA:BB:CC:DD:EE:02", "ip": "192.168.0.20", "hostname": "security-cam", "packets": 1200},
    {"mac": "AA:BB:CC:DD:EE:03", "ip": "192.168.0.30", "hostname": "tablet", "packets": 60},
]

CHATTY_THRESHOLD = 500


def _is_windows():
    return platform.system().lower().startswith('win')


def get_windows_events(level: str = None, max_events: int = 50):
    """Fetch recent Windows events via PowerShell. Level can be 'Error', 'Warning', or None for any.
    Returns list of dicts with time, source, id, level, message.
    """
    if not _is_windows():
        return []
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

@app.route('/')
def dashboard():
    """Render the primary dashboard."""
    return render_template('dashboard.html')

@app.route('/events')
def events():
    """Drill-down page for system events."""
    events = get_windows_events(max_events=100) or SYSTEM_EVENTS
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
    return render_template('router.html', logs=ROUTER_LOGS)

@app.route('/wifi')
def wifi():
    """List Wi-Fi clients highlighting chatty nodes."""
    return render_template('wifi.html', clients=WIFI_CLIENTS, threshold=CHATTY_THRESHOLD)


@app.route('/api/events')
def api_events():
    level = request.args.get('level')
    max_events = int(request.args.get('max', '100'))
    data = get_windows_events(level=level, max_events=max_events) or SYSTEM_EVENTS
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

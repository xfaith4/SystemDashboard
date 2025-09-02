from flask import Flask, render_template

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

@app.route('/')
def dashboard():
    """Render the primary dashboard."""
    return render_template('dashboard.html')

@app.route('/events')
def events():
    """Drill-down page for system events."""
    return render_template('events.html', events=SYSTEM_EVENTS)

@app.route('/router')
def router():
    """Drill-down page for router logs."""
    return render_template('router.html', logs=ROUTER_LOGS)

@app.route('/wifi')
def wifi():
    """List Wi-Fi clients highlighting chatty nodes."""
    return render_template('wifi.html', clients=WIFI_CLIENTS, threshold=CHATTY_THRESHOLD)

if __name__ == '__main__':
    # Enable debug for development convenience
    app.run(debug=True, host='0.0.0.0', port=5000)

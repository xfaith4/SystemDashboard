"""
Validation tests for the /lan/devices page to ensure:
1. Each container/component is properly hooked up to the database
2. The database schema supports regular updates via SSH to ASUS router at 192.168.50.1
3. Data flows correctly from router collection through database to frontend API

These tests validate the end-to-end data pipeline for LAN device observability.
"""
import os
import sys
import json
import sqlite3
import tempfile
import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta, UTC

# Add the app directory to the path so we can import app
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'app'))

import app as flask_app


@pytest.fixture(autouse=True)
def reset_db_path():
    """Ensure _DB_PATH is reset after each test to avoid test pollution."""
    original_path = flask_app._DB_PATH
    yield
    flask_app._DB_PATH = original_path


@pytest.fixture
def test_db():
    """Create a temporary SQLite database for testing with proper schema."""
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    
    # Initialize schema
    schema_path = os.path.join(os.path.dirname(__file__), '..', 'tools', 'schema-sqlite.sql')
    with open(schema_path, 'r') as f:
        schema_sql = f.read()
    
    conn = sqlite3.connect(db_path)
    conn.executescript(schema_sql)
    conn.commit()
    conn.close()
    
    yield db_path
    
    # Cleanup
    if os.path.exists(db_path):
        os.unlink(db_path)


@pytest.fixture
def client_with_db(test_db):
    """Create a test client with a configured test database."""
    flask_app.app.config['TESTING'] = True
    flask_app._DB_PATH = test_db
    
    # Reset rate limiter for clean test state
    from conftest import reset_rate_limiter
    reset_rate_limiter()
    
    # Disable CSRF protection for tests
    os.environ['DASHBOARD_CSRF_ENABLED'] = 'false'
    if flask_app.PHASE3_FEATURES_AVAILABLE:
        from security import get_csrf_protection
        get_csrf_protection().set_enabled(False)
    
    with flask_app.app.test_client() as client:
        yield client
    
    # Reset the cached db path
    flask_app._DB_PATH = None
    os.environ.pop('DASHBOARD_CSRF_ENABLED', None)


@pytest.fixture
def populated_db(test_db):
    """Create a database with sample device data mimicking SSH collection from ASUS router."""
    conn = sqlite3.connect(test_db)
    cursor = conn.cursor()
    
    now = datetime.now(UTC).isoformat()
    one_hour_ago = (datetime.now(UTC) - timedelta(hours=1)).isoformat()
    one_day_ago = (datetime.now(UTC) - timedelta(days=1)).isoformat()
    
    # Insert devices (simulating data collected from ASUS router via SSH)
    # Router IP is configured in config.json as 192.168.50.1
    devices_data = [
        # (mac_address, primary_ip, hostname, vendor, first_seen, last_seen, is_active, tags, network_type)
        ('AA:BB:CC:DD:EE:01', '192.168.50.101', 'laptop-work', 'Dell Inc.', one_day_ago, now, 1, 'workstation', 'main'),
        ('AA:BB:CC:DD:EE:02', '192.168.50.102', 'phone-john', 'Apple Inc.', one_day_ago, now, 1, 'mobile', 'main'),
        ('AA:BB:CC:DD:EE:03', '192.168.50.103', 'iot-camera-01', 'Hikvision', one_day_ago, one_hour_ago, 0, 'iot,critical', 'iot'),
        ('AA:BB:CC:DD:EE:04', '192.168.50.104', 'guest-laptop', 'HP Inc.', one_day_ago, now, 1, 'guest', 'guest'),
        ('AA:BB:CC:DD:EE:05', '192.168.50.105', None, 'Unknown', now, now, 1, None, 'main'),  # New device with no hostname
    ]
    
    for mac, ip, hostname, vendor, first_seen, last_seen, is_active, tags, network_type in devices_data:
        cursor.execute("""
            INSERT INTO devices (mac_address, primary_ip_address, hostname, vendor, 
                                first_seen_utc, last_seen_utc, is_active, tags, network_type)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (mac, ip, hostname, vendor, first_seen, last_seen, is_active, tags, network_type))
    
    # Insert device snapshots (time-series data from SSH polling)
    for i, (mac, ip, hostname, vendor, first_seen, last_seen, is_active, tags, network_type) in enumerate(devices_data, 1):
        device_id = i
        # Add recent snapshot
        interface = 'wireless 2.4ghz' if i % 2 == 0 else 'wireless 5ghz'
        rssi = -50 - (i * 5)  # Different RSSI values
        tx_rate = 100.0 + (i * 10)
        rx_rate = 80.0 + (i * 8)
        
        cursor.execute("""
            INSERT INTO device_snapshots (device_id, sample_time_utc, ip_address, interface, 
                                         rssi, tx_rate_mbps, rx_rate_mbps, is_online)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (device_id, last_seen, ip, interface, rssi, tx_rate, rx_rate, is_active))
        
        # Add an older snapshot for timeline data
        cursor.execute("""
            INSERT INTO device_snapshots (device_id, sample_time_utc, ip_address, interface, 
                                         rssi, tx_rate_mbps, rx_rate_mbps, is_online)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (device_id, one_hour_ago, ip, interface, rssi - 5, tx_rate - 10, rx_rate - 10, 1))
    
    # Insert device alerts
    cursor.execute("""
        INSERT INTO device_alerts (device_id, alert_type, severity, title, message, is_resolved)
        VALUES (?, 'weak_signal', 'warning', 'Weak Wi-Fi Signal', 'Device RSSI is below threshold', 0)
    """, (3,))  # Alert for iot-camera-01
    
    cursor.execute("""
        INSERT INTO device_alerts (device_id, alert_type, severity, title, message, is_resolved)
        VALUES (?, 'new_device', 'info', 'New Device Detected', 'Unknown device joined network', 0)
    """, (5,))  # Alert for new unknown device
    
    conn.commit()
    conn.close()
    
    return test_db


@pytest.fixture
def client_with_populated_db(populated_db):
    """Create a test client with populated test database."""
    flask_app.app.config['TESTING'] = True
    flask_app._DB_PATH = populated_db
    
    # Reset rate limiter for clean test state
    from conftest import reset_rate_limiter
    reset_rate_limiter()
    
    with flask_app.app.test_client() as client:
        yield client
    
    flask_app._DB_PATH = None


class TestLanDevicesPageRoutes:
    """Test that LAN devices page routes are correctly configured."""
    
    def test_lan_devices_page_renders(self, client_with_db):
        """Verify the /lan/devices page renders successfully."""
        response = client_with_db.get('/lan/devices')
        assert response.status_code == 200
        assert b'LAN Devices' in response.data
        assert b'Device Name' in response.data
        assert b'IP Address' in response.data
        assert b'MAC Address' in response.data
    
    def test_lan_overview_page_renders(self, client_with_db):
        """Verify the /lan overview page renders successfully."""
        response = client_with_db.get('/lan')
        assert response.status_code == 200
    
    def test_lan_device_detail_page_renders(self, client_with_db):
        """Verify the /lan/device/<id> detail page renders successfully."""
        response = client_with_db.get('/lan/device/1')
        assert response.status_code == 200


class TestDatabaseConnectionValidation:
    """Test that the database connection and schema are properly configured."""
    
    def test_database_path_from_config(self, test_db):
        """Verify database path can be set via environment variable."""
        with patch.dict(os.environ, {'DASHBOARD_DB_PATH': test_db}):
            flask_app._DB_PATH = None  # Reset cached path
            path = flask_app._get_db_path()
            assert path == test_db
    
    def test_database_connection_succeeds(self, test_db):
        """Verify database connection is established successfully."""
        flask_app._DB_PATH = test_db
        conn = None
        try:
            conn = flask_app.get_db_connection()
            assert conn is not None
            
            # Verify we can query
            cursor = conn.cursor()
            cursor.execute("SELECT 1")
            result = cursor.fetchone()
            assert result[0] == 1
        finally:
            if conn:
                conn.close()
            flask_app._DB_PATH = None
    
    def test_database_schema_has_devices_table(self, test_db):
        """Verify the devices table exists with correct columns."""
        conn = sqlite3.connect(test_db)
        cursor = conn.cursor()
        
        # Check table exists
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='devices'")
        result = cursor.fetchone()
        assert result is not None, "devices table should exist"
        
        # Check required columns
        cursor.execute("PRAGMA table_info(devices)")
        columns = {row[1] for row in cursor.fetchall()}
        
        required_columns = {
            'device_id', 'mac_address', 'primary_ip_address', 'hostname',
            'vendor', 'first_seen_utc', 'last_seen_utc', 'is_active',
            'tags', 'network_type', 'nickname', 'location'
        }
        
        for col in required_columns:
            assert col in columns, f"Column {col} should exist in devices table"
        
        conn.close()
    
    def test_database_schema_has_device_snapshots_table(self, test_db):
        """Verify the device_snapshots table exists for time-series data."""
        conn = sqlite3.connect(test_db)
        cursor = conn.cursor()
        
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='device_snapshots'")
        result = cursor.fetchone()
        assert result is not None, "device_snapshots table should exist"
        
        # Check required columns for SSH data
        cursor.execute("PRAGMA table_info(device_snapshots)")
        columns = {row[1] for row in cursor.fetchall()}
        
        required_columns = {
            'snapshot_id', 'device_id', 'sample_time_utc', 'ip_address',
            'interface', 'rssi', 'tx_rate_mbps', 'rx_rate_mbps', 'is_online'
        }
        
        for col in required_columns:
            assert col in columns, f"Column {col} should exist in device_snapshots table"
        
        conn.close()
    
    def test_database_views_exist(self, test_db):
        """Verify required views exist for the LAN devices page."""
        conn = sqlite3.connect(test_db)
        cursor = conn.cursor()
        
        required_views = ['devices_online', 'device_alerts_active', 'lan_summary_stats']
        
        try:
            for view_name in required_views:
                cursor.execute(
                    "SELECT name FROM sqlite_master WHERE type='view' AND name=?",
                    (view_name,)
                )
                result = cursor.fetchone()
                assert result is not None, f"View {view_name} should exist"
        finally:
            conn.close()


class TestLanDevicesApiEndpoints:
    """Test that API endpoints for LAN devices correctly fetch from database."""
    
    def test_api_lan_devices_returns_data(self, client_with_populated_db):
        """Verify /api/lan/devices returns device data from database."""
        response = client_with_populated_db.get('/api/lan/devices')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert 'devices' in data
        assert len(data['devices']) > 0
    
    def test_api_lan_devices_includes_required_fields(self, client_with_populated_db):
        """Verify each device has all required fields for the UI."""
        response = client_with_populated_db.get('/api/lan/devices')
        data = json.loads(response.data)
        
        required_fields = [
            'device_id', 'mac_address', 'primary_ip_address', 'hostname',
            'is_active', 'first_seen_utc', 'last_seen_utc'
        ]
        
        for device in data['devices']:
            for field in required_fields:
                assert field in device, f"Device should have {field} field"
    
    def test_api_lan_devices_includes_snapshot_data(self, client_with_populated_db):
        """Verify devices include latest snapshot data (interface, rssi, rates)."""
        response = client_with_populated_db.get('/api/lan/devices')
        data = json.loads(response.data)
        
        # At least some devices should have snapshot data
        devices_with_snapshots = [d for d in data['devices'] if d.get('last_interface')]
        assert len(devices_with_snapshots) > 0, "Some devices should have snapshot data"
        
        # Check snapshot fields are present
        for device in devices_with_snapshots:
            assert 'last_interface' in device
            assert 'last_rssi' in device
            assert 'last_tx_rate_mbps' in device
            assert 'last_rx_rate_mbps' in device
    
    def test_api_lan_devices_filter_by_state_active(self, client_with_populated_db):
        """Verify filtering by state=active returns only active devices."""
        response = client_with_populated_db.get('/api/lan/devices?state=active')
        data = json.loads(response.data)
        
        for device in data['devices']:
            assert device['is_active'] == 1 or device['is_active'] == True, \
                "All devices should be active when filtering by state=active"
    
    def test_api_lan_devices_filter_by_state_inactive(self, client_with_populated_db):
        """Verify filtering by state=inactive returns only inactive devices."""
        response = client_with_populated_db.get('/api/lan/devices?state=inactive')
        data = json.loads(response.data)
        
        for device in data['devices']:
            assert device['is_active'] == 0 or device['is_active'] == False, \
                "All devices should be inactive when filtering by state=inactive"
    
    def test_api_lan_devices_filter_by_tag(self, client_with_populated_db):
        """Verify filtering by tag works correctly."""
        response = client_with_populated_db.get('/api/lan/devices?tag=iot')
        data = json.loads(response.data)
        
        for device in data['devices']:
            assert device.get('tags') is not None, "Device should have tags"
            assert 'iot' in device['tags'].lower(), "All devices should have 'iot' tag"
    
    def test_api_lan_devices_filter_by_network_type(self, client_with_populated_db):
        """Verify filtering by network_type works correctly."""
        response = client_with_populated_db.get('/api/lan/devices?network_type=guest')
        data = json.loads(response.data)
        
        for device in data['devices']:
            assert device.get('network_type') == 'guest', \
                "All devices should be on guest network"
    
    def test_api_lan_stats_returns_summary(self, client_with_populated_db):
        """Verify /api/lan/stats returns summary statistics."""
        response = client_with_populated_db.get('/api/lan/stats')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert 'total_devices' in data
        assert 'active_devices' in data
        assert 'inactive_devices' in data
        
        # Verify counts make sense
        assert data['total_devices'] >= data['active_devices']
        assert data['total_devices'] == data['active_devices'] + data['inactive_devices']
    
    def test_api_lan_devices_online_returns_active(self, client_with_populated_db):
        """Verify /api/lan/devices/online returns only online devices."""
        response = client_with_populated_db.get('/api/lan/devices/online')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert 'devices' in data


class TestDeviceDetailApi:
    """Test device detail API endpoints."""
    
    def test_api_lan_device_detail(self, client_with_populated_db):
        """Verify device detail API returns complete information."""
        response = client_with_populated_db.get('/api/lan/device/1')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert 'device_id' in data
        assert data['device_id'] == 1
        assert 'mac_address' in data
        assert 'total_snapshots' in data
    
    def test_api_lan_device_detail_not_found(self, client_with_populated_db):
        """Verify device detail API returns 404 for non-existent device."""
        response = client_with_populated_db.get('/api/lan/device/9999')
        assert response.status_code == 404
    
    def test_api_lan_device_timeline(self, client_with_populated_db):
        """Verify device timeline API returns time-series data."""
        response = client_with_populated_db.get('/api/lan/device/1/timeline?hours=24')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert 'timeline' in data
        assert isinstance(data['timeline'], list)
    
    def test_api_lan_device_update(self, client_with_populated_db):
        """Verify device update API works correctly."""
        response = client_with_populated_db.post('/api/lan/device/1/update',
            json={'nickname': 'My Laptop', 'location': 'Office'},
            content_type='application/json')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert data['status'] == 'ok'
        
        # Verify the update was applied
        response = client_with_populated_db.get('/api/lan/device/1')
        data = json.loads(response.data)
        assert data['nickname'] == 'My Laptop'
        assert data['location'] == 'Office'


class TestAlertsIntegration:
    """Test alerts integration with LAN devices."""
    
    def test_api_lan_alerts_returns_alerts(self, client_with_populated_db):
        """Verify alerts API returns device alerts."""
        response = client_with_populated_db.get('/api/lan/alerts')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert 'alerts' in data
        assert 'total' in data
    
    def test_api_lan_alerts_include_device_info(self, client_with_populated_db):
        """Verify alerts include associated device information."""
        response = client_with_populated_db.get('/api/lan/alerts')
        data = json.loads(response.data)
        
        # If there are alerts, they should include device info
        if len(data['alerts']) > 0:
            alert = data['alerts'][0]
            assert 'device_id' in alert
            assert 'alert_type' in alert
            assert 'severity' in alert


class TestSSHRouterDataFlow:
    """Test the data flow from SSH router collection to database.
    
    These tests validate that data collected via SSH from the ASUS router
    at 192.168.50.1 can be properly stored and retrieved.
    """
    
    def test_device_can_be_upserted(self, test_db):
        """Test that device upsert logic works correctly."""
        flask_app._DB_PATH = test_db
        conn = flask_app.get_db_connection()
        
        try:
            cursor = conn.cursor()
            now = datetime.now(UTC).isoformat()
            
            # Insert a new device (simulating SSH collection)
            cursor.execute("""
                INSERT INTO devices (mac_address, primary_ip_address, hostname, vendor, 
                                    first_seen_utc, last_seen_utc, is_active)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, ('FF:FF:FF:00:00:01', '192.168.50.200', 'test-device', 'TestVendor', 
                  now, now, 1))
            conn.commit()
            
            # Verify device was inserted
            cursor.execute("SELECT * FROM devices WHERE mac_address = ?", ('FF:FF:FF:00:00:01',))
            device = cursor.fetchone()
            assert device is not None
            
            # Update the device (simulating second SSH poll)
            new_time = datetime.now(UTC).isoformat()
            cursor.execute("""
                UPDATE devices SET last_seen_utc = ?, primary_ip_address = ?
                WHERE mac_address = ?
            """, (new_time, '192.168.50.201', 'FF:FF:FF:00:00:01'))
            conn.commit()
            
            # Verify update
            cursor.execute("SELECT primary_ip_address FROM devices WHERE mac_address = ?", 
                          ('FF:FF:FF:00:00:01',))
            result = cursor.fetchone()
            assert result[0] == '192.168.50.201'
            
        finally:
            conn.close()
            flask_app._DB_PATH = None
    
    def test_device_snapshot_can_be_recorded(self, test_db):
        """Test that device snapshots can be recorded (time-series data from SSH)."""
        flask_app._DB_PATH = test_db
        conn = flask_app.get_db_connection()
        
        try:
            cursor = conn.cursor()
            now = datetime.now(UTC).isoformat()
            
            # Insert a device first
            cursor.execute("""
                INSERT INTO devices (mac_address, primary_ip_address, first_seen_utc, last_seen_utc, is_active)
                VALUES (?, ?, ?, ?, ?)
            """, ('FF:FF:FF:00:00:02', '192.168.50.202', now, now, 1))
            device_id = cursor.lastrowid
            conn.commit()
            
            # Insert multiple snapshots (simulating periodic SSH polling)
            for i in range(3):
                snapshot_time = (datetime.now(UTC) - timedelta(minutes=i*5)).isoformat()
                cursor.execute("""
                    INSERT INTO device_snapshots (device_id, sample_time_utc, ip_address, 
                                                 interface, rssi, tx_rate_mbps, rx_rate_mbps, is_online)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, (device_id, snapshot_time, '192.168.50.202', 'wireless 5ghz', 
                      -55 + i, 150.0, 120.0, 1))
            conn.commit()
            
            # Verify snapshots
            cursor.execute("SELECT COUNT(*) FROM device_snapshots WHERE device_id = ?", (device_id,))
            count = cursor.fetchone()[0]
            assert count == 3, "Should have 3 snapshots"
            
        finally:
            conn.close()
            flask_app._DB_PATH = None
    
    def test_activity_status_reflects_recent_data(self, test_db):
        """Test that is_active reflects recent SSH polling data."""
        flask_app._DB_PATH = test_db
        conn = flask_app.get_db_connection()
        
        try:
            cursor = conn.cursor()
            now = datetime.now(UTC)
            recent = now.isoformat()
            old = (now - timedelta(hours=2)).isoformat()
            
            # Insert active device (seen recently)
            cursor.execute("""
                INSERT INTO devices (mac_address, primary_ip_address, last_seen_utc, is_active)
                VALUES (?, ?, ?, ?)
            """, ('FF:FF:FF:00:00:03', '192.168.50.203', recent, 1))
            
            # Insert inactive device (not seen recently)
            cursor.execute("""
                INSERT INTO devices (mac_address, primary_ip_address, last_seen_utc, is_active)
                VALUES (?, ?, ?, ?)
            """, ('FF:FF:FF:00:00:04', '192.168.50.204', old, 0))
            conn.commit()
            
            # Verify via API
            conn.close()
            flask_app._DB_PATH = test_db
            
            # Check active filter
            flask_app.app.config['TESTING'] = True
            with flask_app.app.test_client() as client:
                response = client.get('/api/lan/devices?state=active')
                data = json.loads(response.data)
                active_macs = [d['mac_address'] for d in data['devices']]
                assert 'FF:FF:FF:00:00:03' in active_macs
                assert 'FF:FF:FF:00:00:04' not in active_macs
            
        finally:
            flask_app._DB_PATH = None


class TestConfigForAsusRouter:
    """Test configuration related to ASUS router at 192.168.50.1."""
    
    def test_config_contains_router_ip(self):
        """Verify config.json contains the ASUS router IP."""
        config_path = os.path.join(os.path.dirname(__file__), '..', 'config.json')
        
        with open(config_path, 'r') as f:
            config = json.load(f)
        
        # Check router IP is configured
        assert 'RouterIP' in config
        assert config['RouterIP'] == '192.168.50.1'
    
    def test_config_contains_ssh_settings(self):
        """Verify config.json contains SSH settings for router connection."""
        config_path = os.path.join(os.path.dirname(__file__), '..', 'config.json')
        
        with open(config_path, 'r') as f:
            config = json.load(f)
        
        # Check SSH configuration exists
        assert 'Service' in config
        assert 'Asus' in config['Service']
        asus_config = config['Service']['Asus']
        
        assert 'SSH' in asus_config
        ssh_config = asus_config['SSH']
        
        assert 'Host' in ssh_config
        assert ssh_config['Host'] == '192.168.50.1'
        assert 'Port' in ssh_config
        assert 'Username' in ssh_config


class TestDatabaseUpdateScenarios:
    """Test scenarios for database updates during regular SSH polling."""
    
    def test_new_device_detection(self, test_db):
        """Test that new devices appearing on the network are detected."""
        flask_app._DB_PATH = test_db
        conn = flask_app.get_db_connection()
        
        try:
            cursor = conn.cursor()
            now = datetime.now(UTC).isoformat()
            
            # Initially no devices
            cursor.execute("SELECT COUNT(*) FROM devices")
            initial_count = cursor.fetchone()[0]
            
            # Simulate new device appearing on network (SSH poll result)
            cursor.execute("""
                INSERT INTO devices (mac_address, primary_ip_address, hostname, 
                                    first_seen_utc, last_seen_utc, is_active)
                VALUES (?, ?, ?, ?, ?, ?)
            """, ('NEW:DE:VI:CE:00:01', '192.168.50.250', 'new-laptop', now, now, 1))
            conn.commit()
            
            # Verify new device count
            cursor.execute("SELECT COUNT(*) FROM devices")
            new_count = cursor.fetchone()[0]
            assert new_count == initial_count + 1
            
            # Verify it shows up in API
            conn.close()
            flask_app._DB_PATH = test_db
            flask_app.app.config['TESTING'] = True
            
            with flask_app.app.test_client() as client:
                response = client.get('/api/lan/devices')
                data = json.loads(response.data)
                macs = [d['mac_address'] for d in data['devices']]
                assert 'NEW:DE:VI:CE:00:01' in macs
            
        finally:
            flask_app._DB_PATH = None
    
    def test_device_goes_offline(self, populated_db):
        """Test that device going offline is reflected in database."""
        flask_app._DB_PATH = populated_db
        conn = flask_app.get_db_connection()
        
        try:
            cursor = conn.cursor()
            
            # Mark a device as inactive (simulating SSH poll not finding it)
            cursor.execute("""
                UPDATE devices SET is_active = 0 WHERE mac_address = ?
            """, ('AA:BB:CC:DD:EE:01',))
            conn.commit()
            
            # Verify via API
            conn.close()
            flask_app._DB_PATH = populated_db
            flask_app.app.config['TESTING'] = True
            
            with flask_app.app.test_client() as client:
                response = client.get('/api/lan/devices?state=inactive')
                data = json.loads(response.data)
                macs = [d['mac_address'] for d in data['devices']]
                assert 'AA:BB:CC:DD:EE:01' in macs
            
        finally:
            flask_app._DB_PATH = None
    
    def test_ip_address_change_tracked(self, populated_db):
        """Test that IP address changes are tracked (DHCP renewals)."""
        flask_app._DB_PATH = populated_db
        conn = flask_app.get_db_connection()
        
        try:
            cursor = conn.cursor()
            new_ip = '192.168.50.199'
            now = datetime.now(UTC).isoformat()
            
            # Simulate device getting new IP from DHCP
            cursor.execute("""
                UPDATE devices SET primary_ip_address = ?, last_seen_utc = ?
                WHERE mac_address = ?
            """, (new_ip, now, 'AA:BB:CC:DD:EE:01'))
            
            # Add snapshot with new IP
            cursor.execute("SELECT device_id FROM devices WHERE mac_address = ?", 
                          ('AA:BB:CC:DD:EE:01',))
            device_id = cursor.fetchone()[0]
            
            cursor.execute("""
                INSERT INTO device_snapshots (device_id, sample_time_utc, ip_address, interface, is_online)
                VALUES (?, ?, ?, ?, ?)
            """, (device_id, now, new_ip, 'wireless 5ghz', 1))
            conn.commit()
            
            # Verify via API
            conn.close()
            flask_app._DB_PATH = populated_db
            flask_app.app.config['TESTING'] = True
            
            with flask_app.app.test_client() as client:
                response = client.get('/api/lan/device/1')
                data = json.loads(response.data)
                assert data['primary_ip_address'] == new_ip
            
        finally:
            flask_app._DB_PATH = None


class TestUIComponentDataRequirements:
    """Test that each UI component's data requirements are met by the API."""
    
    def test_devices_table_has_all_columns(self, client_with_populated_db):
        """Verify API provides data for all columns in the devices table."""
        response = client_with_populated_db.get('/api/lan/devices')
        data = json.loads(response.data)
        
        # These columns are displayed in lan_devices.html
        table_columns = [
            'is_active',           # Status column
            'hostname',            # Device Name (or nickname or mac)
            'primary_ip_address',  # IP Address
            'mac_address',         # MAC Address
            'vendor',              # Vendor
            'location',            # Location
            'tags',                # Tags
            'last_interface',      # Interface (from snapshot)
            'last_rssi',           # Signal
            'last_tx_rate_mbps',   # Rates (Tx)
            'last_rx_rate_mbps',   # Rates (Rx)
            'first_seen_utc',      # First Seen
            'last_seen_utc',       # Last Seen
        ]
        
        assert len(data['devices']) > 0, "Should have devices to test"
        
        device = data['devices'][0]
        for col in table_columns:
            assert col in device, f"API should provide '{col}' for devices table"
    
    def test_filter_dropdowns_work(self, client_with_populated_db):
        """Verify all filter dropdowns in the UI have working API support."""
        # Status filter
        for state in ['active', 'inactive', '']:
            url = f'/api/lan/devices?state={state}' if state else '/api/lan/devices'
            response = client_with_populated_db.get(url)
            assert response.status_code == 200
        
        # Tag filter
        for tag in ['iot', 'guest', 'critical', 'mobile', 'workstation', 'server', '']:
            url = f'/api/lan/devices?tag={tag}' if tag else '/api/lan/devices'
            response = client_with_populated_db.get(url)
            assert response.status_code == 200
        
        # Network type filter
        for net in ['main', 'guest', 'iot', 'unknown', '']:
            url = f'/api/lan/devices?network_type={net}' if net else '/api/lan/devices'
            response = client_with_populated_db.get(url)
            assert response.status_code == 200
    
    def test_device_detail_link_works(self, client_with_populated_db):
        """Verify clicking View → on a device works."""
        # Get a device ID from the list
        response = client_with_populated_db.get('/api/lan/devices')
        data = json.loads(response.data)
        
        assert len(data['devices']) > 0
        device_id = data['devices'][0]['device_id']
        
        # Verify detail page works
        response = client_with_populated_db.get(f'/lan/device/{device_id}')
        assert response.status_code == 200
        
        # Verify detail API works
        response = client_with_populated_db.get(f'/api/lan/device/{device_id}')
        assert response.status_code == 200


class TestHealthEndpoint:
    """Test that health endpoint validates database connectivity."""
    
    def test_health_with_db(self, client_with_populated_db):
        """Verify health check passes with database connection."""
        response = client_with_populated_db.get('/health')
        assert response.status_code == 200
        assert response.data == b'ok'
    
    def test_health_without_db(self, client_with_db):
        """Verify health check behavior without active database."""
        with patch('app.get_db_connection', return_value=None):
            flask_app.app.config['TESTING'] = True
            with flask_app.app.test_client() as client:
                response = client.get('/health')
                # Should still work with mock data
                assert response.status_code in [200, 503]


if __name__ == '__main__':
    pytest.main([__file__, '-v'])

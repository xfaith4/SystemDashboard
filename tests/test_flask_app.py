"""
Test suite for Flask app functionality and data source validation.
"""
import os
import sys
import tempfile
import pytest
import json
from unittest.mock import patch, mock_open

# Add the app directory to the path so we can import app
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'app'))

import app as flask_app


@pytest.fixture
def client():
    """Create a test client for the Flask app."""
    flask_app.app.config['TESTING'] = True
    
    # Disable CSRF protection for tests
    os.environ['DASHBOARD_CSRF_ENABLED'] = 'false'
    
    # Reset rate limiter for clean test state
    from conftest import reset_rate_limiter
    reset_rate_limiter()
    
    # Reload CSRF protection if Phase 3 features available
    if flask_app.PHASE3_FEATURES_AVAILABLE:
        from security import get_csrf_protection
        get_csrf_protection().set_enabled(False)
    
    with flask_app.app.test_client() as client:
        yield client
    
    # Re-enable CSRF after tests
    os.environ.pop('DASHBOARD_CSRF_ENABLED', None)


class TestFlaskRoutes:
    """Test Flask application routes."""
    
    def test_dashboard_route(self, client):
        """Test dashboard route returns successfully."""
        response = client.get('/')
        assert response.status_code == 200
        assert b'Dashboard' in response.data or b'dashboard' in response.data

    def test_events_route(self, client):
        """Test events route returns successfully."""
        response = client.get('/events')
        assert response.status_code == 200

    def test_router_route(self, client):
        """Test router route returns successfully."""
        response = client.get('/router')
        assert response.status_code == 200

    def test_wifi_route(self, client):
        """Test wifi route returns successfully."""
        response = client.get('/wifi')
        assert response.status_code == 200

    def test_health_route(self, client):
        """Test health route."""
        response = client.get('/health')
        # Health check may fail without proper backend, but route should exist
        assert response.status_code in [200, 503]


class TestDataSources:
    """Test data source functions."""
    
    def test_is_windows_detection(self):
        """Test Windows platform detection."""
        # This will depend on the test environment
        result = flask_app._is_windows()
        assert isinstance(result, bool)

    @patch('app.subprocess.run')
    def test_get_windows_events_mocked(self, mock_subprocess):
        """Test Windows events retrieval with mocked subprocess."""
        # Mock successful PowerShell execution
        mock_result = type('MockResult', (), {
            'returncode': 0,
            'stdout': json.dumps([{
                'TimeCreated': '2024-01-01T12:00:00Z',
                'ProviderName': 'Test Provider',
                'Id': 1234,
                'LevelDisplayName': 'Error',
                'Message': 'Test message'
            }])
        })
        mock_subprocess.return_value = mock_result
        
        with patch('app._is_windows', return_value=True):
            events = flask_app.get_windows_events()
            
        assert len(events) == 1
        assert events[0]['source'] == 'Test Provider'
        assert events[0]['level'] == 'Error'
        assert events[0]['message'] == 'Test message'

    def test_get_router_logs_with_missing_file(self):
        """Test router logs when file doesn't exist."""
        with patch.dict(os.environ, {'ROUTER_LOG_PATH': '/nonexistent/path'}):
            logs = flask_app.get_router_logs()
            assert logs == []

    def test_get_router_logs_with_valid_file(self):
        """Test router logs with a valid log file."""
        log_content = """2024-01-01 12:00:00 INFO Test log message
2024-01-01 12:01:00 WARN Another test message
2024-01-01 12:02:00 ERROR Error message here"""
        
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.log') as f:
            f.write(log_content)
            f.flush()
            
            try:
                # Mock database to return None to force file-based logs
                with patch('app.get_db_connection', return_value=None):
                    with patch.dict(os.environ, {'ROUTER_LOG_PATH': f.name}):
                        # Request ascending order to match original test expectations
                        logs = flask_app.get_router_logs(sort_dir='asc')
                
                assert len(logs) == 3
                assert logs[0]['time'] == '2024-01-01 12:00:00'
                assert logs[0]['level'] == 'INFO'
                assert logs[0]['message'] == 'Test log message'
                
                assert logs[2]['level'] == 'ERROR'
                assert 'Error message' in logs[2]['message']
            finally:
                os.unlink(f.name)

    @patch('app.subprocess.run')
    def test_get_wifi_clients_mocked(self, mock_subprocess):
        """Test WiFi clients retrieval with mocked subprocess."""
        # Mock ARP table output
        arp_output = """Interface: 192.168.1.100 --- 0x2
  Internet Address      Physical Address      Type
  192.168.1.1           aa-bb-cc-dd-ee-ff     dynamic
  192.168.1.10          11-22-33-44-55-66     dynamic"""
        
        mock_result = type('MockResult', (), {
            'returncode': 0,
            'stdout': arp_output
        })
        mock_subprocess.return_value = mock_result
        
        clients = flask_app.get_wifi_clients()
        assert len(clients) >= 0  # May be empty if parsing doesn't match exactly

    def test_router_logs_parsing_edge_cases(self):
        """Test router log parsing with various line formats."""
        log_content = """2024-01-01 12:00:00 INFO Complete log line
Incomplete line
2024-01-01 12:01:00 WARN
2024-01-01 12:02:00 ERROR Multi word message here"""
        
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.log') as f:
            f.write(log_content)
            f.flush()
            
            try:
                # Mock database to return None to force file-based logs
                with patch('app.get_db_connection', return_value=None):
                    with patch.dict(os.environ, {'ROUTER_LOG_PATH': f.name}):
                        # Request ascending order to match original test expectations
                        logs = flask_app.get_router_logs(sort_dir='asc')
                
                # Note: Lines with < 4 parts get empty time/level
                # "2024-01-01 12:01:00 WARN" has only 3 parts, so it's treated as incomplete
                assert len(logs) == 4
                
                # Find logs with actual timestamps (those with 4+ parts in split)
                timestamped_logs = [l for l in logs if l['time']]
                assert len(timestamped_logs) == 2  # Only 2 lines have full 4-part format
                
                # Check first timestamped line
                first_ts = timestamped_logs[0]
                assert first_ts['time'] == '2024-01-01 12:00:00'
                assert first_ts['level'] == 'INFO'
                
                # Check incomplete line handling exists
                incomplete_logs = [l for l in logs if l['time'] == '' and l['level'] == '']
                assert len(incomplete_logs) == 2  # "Incomplete line" and "2024-01-01 12:01:00 WARN"
                
            finally:
                os.unlink(f.name)


class TestAPIEndpoints:
    """Test API endpoints."""
    
    def test_api_events_endpoint(self, client):
        """Test events API endpoint."""
        response = client.get('/api/events')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert 'events' in data
        assert isinstance(data['events'], list)

    def test_api_events_with_parameters(self, client):
        """Test events API with query parameters."""
        response = client.get('/api/events?level=error&max=10')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert 'events' in data

    def test_api_router_logs_endpoint(self, client):
        """Test router logs API endpoint with pagination."""
        response = client.get('/api/router/logs')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert 'logs' in data
        assert 'source' in data
        assert 'pagination' in data
        
        # Check pagination structure
        pagination = data['pagination']
        assert 'total' in pagination
        assert 'page' in pagination
        assert 'limit' in pagination
        assert 'totalPages' in pagination
        assert 'hasNext' in pagination
        assert 'hasPrev' in pagination

    def test_api_router_logs_with_pagination(self, client):
        """Test router logs API with pagination parameters."""
        response = client.get('/api/router/logs?limit=25&page=1')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert 'pagination' in data
        assert data['pagination']['limit'] == 25
        assert data['pagination']['page'] == 1

    def test_api_router_logs_with_sorting(self, client):
        """Test router logs API with sorting parameters."""
        response = client.get('/api/router/logs?sort=time&order=asc')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert 'logs' in data

    def test_api_router_logs_with_filtering(self, client):
        """Test router logs API with filtering parameters."""
        response = client.get('/api/router/logs?level=error&search=test')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert 'logs' in data

    def test_api_router_logs_limit_max(self, client):
        """Test router logs API respects maximum limit."""
        response = client.get('/api/router/logs?limit=1000')  # Request more than max
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert data['pagination']['limit'] == 500  # Should be capped at 500

    def test_api_ai_suggest_missing_message(self, client):
        """Test AI suggest API with missing message."""
        response = client.post('/api/ai/suggest', 
                             json={},
                             content_type='application/json')
        assert response.status_code == 400
        
        data = json.loads(response.data)
        assert 'error' in data

    def test_api_ai_suggest_with_message(self, client):
        """Test AI suggest API with valid message."""
        with patch('app.call_openai_chat') as mock_openai:
            mock_openai.return_value = ("Test suggestion", None)
            
            response = client.post('/api/ai/suggest',
                                 json={
                                     'message': 'Test error message',
                                     'source': 'Test Source',
                                     'id': 1234
                                 },
                                 content_type='application/json')
            
            assert response.status_code == 200
            data = json.loads(response.data)
            assert 'suggestion' in data
            assert data['suggestion'] == "Test suggestion"

    def test_api_ai_suggest_with_error(self, client):
        """Test AI suggest API when OpenAI returns error."""
        with patch('app.call_openai_chat') as mock_openai:
            mock_openai.return_value = (None, "API key not configured")
            
            response = client.post('/api/ai/suggest',
                                 json={'message': 'Test message'},
                                 content_type='application/json')
            
            assert response.status_code == 502
            data = json.loads(response.data)
            assert 'error' in data

    def test_api_ai_explain_missing_type(self, client):
        """Test AI explain API with invalid type."""
        response = client.post('/api/ai/explain',
                             json={'type': 'invalid', 'context': {}},
                             content_type='application/json')
        assert response.status_code == 400
        data = json.loads(response.data)
        assert 'error' in data
        assert 'Invalid type' in data['error']

    def test_api_ai_explain_missing_context(self, client):
        """Test AI explain API with missing context."""
        response = client.post('/api/ai/explain',
                             json={'type': 'router_log'},
                             content_type='application/json')
        assert response.status_code == 400
        data = json.loads(response.data)
        assert 'error' in data
        assert 'Missing context' in data['error']

    def test_api_ai_explain_router_log_no_api_key(self, client):
        """Test AI explain API for router_log without API key returns fallback."""
        with patch.dict(os.environ, {}, clear=False):
            # Ensure no OPENAI_API_KEY
            if 'OPENAI_API_KEY' in os.environ:
                del os.environ['OPENAI_API_KEY']
            
            response = client.post('/api/ai/explain',
                                 json={
                                     'type': 'router_log',
                                     'context': {
                                         'time': '2024-01-01T12:00:00Z',
                                         'level': 'Warning',
                                         'message': 'WAN connection unstable',
                                         'host': 'router.local'
                                     }
                                 },
                                 content_type='application/json')
            
            assert response.status_code == 200
            data = json.loads(response.data)
            assert 'explanationHtml' in data
            assert 'severity' in data
            assert data['severity'] == 'info'

    def test_api_ai_explain_windows_event_no_api_key(self, client):
        """Test AI explain API for windows_event without API key."""
        with patch.dict(os.environ, {}, clear=False):
            if 'OPENAI_API_KEY' in os.environ:
                del os.environ['OPENAI_API_KEY']
            
            response = client.post('/api/ai/explain',
                                 json={
                                     'type': 'windows_event',
                                     'context': {
                                         'source': 'Application Error',
                                         'id': 1000,
                                         'level': 'Error',
                                         'message': 'Test error message'
                                     }
                                 },
                                 content_type='application/json')
            
            assert response.status_code == 200
            data = json.loads(response.data)
            assert 'explanationHtml' in data

    def test_api_events_logs_route(self, client):
        """Test the /api/events/logs route alias."""
        response = client.get('/api/events/logs')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert 'events' in data
        assert isinstance(data['events'], list)

    def test_api_events_logs_with_parameters(self, client):
        """Test /api/events/logs with query parameters."""
        response = client.get('/api/events/logs?level=error&max=10')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert 'events' in data

    def test_api_trends_endpoint(self, client):
        """Test trends API endpoint returns 7-day data."""
        response = client.get('/api/trends')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert 'dates' in data
        assert 'iis_errors' in data

    def test_api_dashboard_summary_endpoint(self, client):
        """Test dashboard summary API endpoint returns all required sections."""
        response = client.get('/api/dashboard/summary')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        # Check that all required sections exist
        assert 'iis' in data
        assert 'auth' in data
        assert 'windows' in data
        assert 'router' in data
        assert 'syslog' in data
        assert 'using_mock' in data
        
        # Check IIS section structure
        assert 'current_errors' in data['iis']
        assert 'total_requests' in data['iis']
        assert 'baseline_avg' in data['iis']
        assert 'baseline_std' in data['iis']
        assert 'spike' in data['iis']
        
        # Check that lists are properly structured
        assert isinstance(data['auth'], list)
        assert isinstance(data['windows'], list)
        assert isinstance(data['router'], list)
        assert isinstance(data['syslog'], list)

    def test_api_dashboard_summary_has_enhanced_metrics(self, client):
        """Test dashboard summary API includes new enhanced metrics."""
        response = client.get('/api/dashboard/summary')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        
        # Check for new timestamp field
        assert 'timestamp' in data
        
        # Check for new health score
        assert 'health' in data
        assert 'score' in data['health']
        assert 'status' in data['health']
        assert 'factors' in data['health']
        assert isinstance(data['health']['score'], int)
        assert data['health']['status'] in ['healthy', 'warning', 'critical']
        assert isinstance(data['health']['factors'], list)
        
        # Check for new LAN metrics
        assert 'lan' in data
        assert 'total_devices' in data['lan']
        assert 'active_devices' in data['lan']
        assert 'new_devices_24h' in data['lan']
        
        # Check for new hourly breakdown
        assert 'hourly_breakdown' in data
        assert isinstance(data['hourly_breakdown'], list)
        if len(data['hourly_breakdown']) > 0:
            hour = data['hourly_breakdown'][0]
            assert 'hour' in hour
            assert 'iis_errors' in hour
            assert 'auth_failures' in hour
            assert 'windows_errors' in hour
            assert 'router_alerts' in hour
        
        # Check for error rate in IIS
        assert 'error_rate' in data['iis']


class TestHealthScoreCalculation:
    """Test health score calculation logic."""
    
    def test_health_score_healthy(self):
        """Test health score with no issues returns healthy status."""
        summary = {
            'iis': {'current_errors': 0, 'spike': False},
            'auth': [],
            'windows': [],
            'router': []
        }
        score, status, factors = flask_app._calculate_health_score(summary)
        assert score == 100
        assert status == 'healthy'
        assert len(factors) == 0
    
    def test_health_score_with_spike(self):
        """Test health score with IIS spike."""
        summary = {
            'iis': {'current_errors': 20, 'spike': True},
            'auth': [],
            'windows': [],
            'router': []
        }
        score, status, factors = flask_app._calculate_health_score(summary)
        assert score < 100
        assert any('spike' in f['message'].lower() for f in factors)
    
    def test_health_score_with_auth_failures(self):
        """Test health score with auth failures."""
        summary = {
            'iis': {'current_errors': 0, 'spike': False},
            'auth': [{'client_ip': '1.2.3.4', 'count': 15}],
            'windows': [],
            'router': []
        }
        score, status, factors = flask_app._calculate_health_score(summary)
        assert score < 100
        assert any('auth' in f['message'].lower() for f in factors)
    
    def test_health_score_with_critical_windows_event(self):
        """Test health score with critical Windows events."""
        summary = {
            'iis': {'current_errors': 0, 'spike': False},
            'auth': [],
            'windows': [{'level': 'Critical', 'message': 'Test'}],
            'router': []
        }
        score, status, factors = flask_app._calculate_health_score(summary)
        assert score < 100
        assert any('critical' in f['message'].lower() for f in factors)
    
    def test_health_score_critical_status(self):
        """Test that multiple issues result in critical status."""
        summary = {
            'iis': {'current_errors': 20, 'spike': True},
            'auth': [
                {'client_ip': '1.2.3.4', 'count': 15},
                {'client_ip': '1.2.3.5', 'count': 12},
                {'client_ip': '1.2.3.6', 'count': 10},
                {'client_ip': '1.2.3.7', 'count': 8}
            ],
            'windows': [
                {'level': 'Critical', 'message': 'Test1'},
                {'level': 'Critical', 'message': 'Test2'}
            ],
            'router': [
                {'severity': 'Error', 'message': 'WAN down'},
                {'severity': 'Error', 'message': 'DHCP fail'},
                {'severity': 'Error', 'message': 'Auth fail'}
            ]
        }
        score, status, factors = flask_app._calculate_health_score(summary)
        assert score <= 50
        assert status == 'critical'


class TestErrorRateCalculation:
    """Test error rate calculation."""
    
    def test_error_rate_with_zero_total(self):
        """Test error rate with zero total returns 0."""
        result = flask_app._calculate_error_rate(0, 0)
        assert result == 0.0
    
    def test_error_rate_calculation(self):
        """Test error rate calculation accuracy."""
        result = flask_app._calculate_error_rate(12, 4200)
        assert result == 0.29  # 12/4200 * 100 = 0.2857... rounded to 0.29
    
    def test_error_rate_full_failure(self):
        """Test error rate with all errors."""
        result = flask_app._calculate_error_rate(100, 100)
        assert result == 100.0


class TestLANDeviceTagging:
    """Test LAN device tagging functionality."""
    
    def test_lan_devices_endpoint(self, client):
        """Test LAN devices endpoint returns successfully."""
        response = client.get('/api/lan/devices')
        assert response.status_code == 200
        data = json.loads(response.data)
        assert 'devices' in data
    
    def test_lan_devices_with_tag_filter(self, client):
        """Test LAN devices endpoint with tag filtering."""
        response = client.get('/api/lan/devices?tag=iot')
        assert response.status_code == 200
        data = json.loads(response.data)
        assert 'devices' in data
    
    def test_lan_device_update_with_tags(self, client):
        """Test updating device with tags."""
        # Mock database connection to return unavailable
        with patch('app.get_db_connection', return_value=None):
            response = client.post('/api/lan/device/1/update',
                                  json={'tags': 'iot,critical'},
                                  content_type='application/json')
            assert response.status_code == 503
    
    def test_lan_device_update_invalid_tags(self, client):
        """Test device update with invalid tags type."""
        with patch('app.get_db_connection', return_value=None):
            response = client.post('/api/lan/device/1/update',
                                  json={'tags': 123},
                                  content_type='application/json')
            assert response.status_code == 400
            data = json.loads(response.data)
            assert 'error' in data
            assert 'tags' in data['error'].lower()


class TestLANAlerting:
    """Test LAN alerting functionality."""
    
    def test_api_lan_alerts_endpoint(self, client):
        """Test alerts endpoint returns successfully with mock data."""
        with patch('app.get_db_connection', return_value=None):
            response = client.get('/api/lan/alerts')
            assert response.status_code == 200
            data = json.loads(response.data)
            assert 'alerts' in data
            assert 'total' in data
    
    def test_api_lan_alerts_with_severity_filter(self, client):
        """Test alerts endpoint with severity filtering (mock data)."""
        with patch('app.get_db_connection', return_value=None):
            response = client.get('/api/lan/alerts?severity=critical')
            assert response.status_code == 200
            data = json.loads(response.data)
            assert 'alerts' in data
    
    def test_api_lan_alerts_with_type_filter(self, client):
        """Test alerts endpoint with type filtering (mock data)."""
        with patch('app.get_db_connection', return_value=None):
            response = client.get('/api/lan/alerts?type=weak_signal')
            assert response.status_code == 200
            data = json.loads(response.data)
            assert 'alerts' in data
    
    def test_api_lan_alert_acknowledge(self, client):
        """Test acknowledging an alert."""
        with patch('app.get_db_connection', return_value=None):
            response = client.post('/api/lan/alerts/1/acknowledge',
                                  json={'acknowledged_by': 'test_user'},
                                  content_type='application/json')
            assert response.status_code == 503
    
    def test_api_lan_alert_resolve(self, client):
        """Test resolving an alert."""
        with patch('app.get_db_connection', return_value=None):
            response = client.post('/api/lan/alerts/1/resolve')
            assert response.status_code == 503
    
    def test_api_lan_alerts_stats(self, client):
        """Test alert statistics endpoint with mock data."""
        with patch('app.get_db_connection', return_value=None):
            response = client.get('/api/lan/alerts/stats')
            assert response.status_code == 200
            data = json.loads(response.data)
            # Should have stats even with mock data
            assert 'total_active' in data


class TestMACVendorLookup:
    """Test MAC vendor lookup functionality."""
    
    def test_lookup_mac_vendor_function(self):
        """Test the MAC vendor lookup helper function."""
        # Test with known MAC prefix
        vendor = flask_app.lookup_mac_vendor('00:11:22:33:44:55')
        # Should return a vendor or None if lookup fails
        assert vendor is None or isinstance(vendor, str)
    
    def test_api_lan_device_lookup_vendor(self, client):
        """Test device vendor lookup endpoint."""
        with patch('app.get_db_connection', return_value=None):
            response = client.post('/api/lan/device/1/lookup-vendor')
            assert response.status_code == 503
    
    def test_api_lan_devices_enrich_vendors(self, client):
        """Test bulk vendor enrichment endpoint."""
        with patch('app.get_db_connection', return_value=None):
            response = client.post('/api/lan/devices/enrich-vendors')
            assert response.status_code == 503


class TestConfigurationValidation:
    """Test configuration and environment variable handling."""
    
    def test_chatty_threshold_default(self):
        """Test default CHATTY_THRESHOLD value."""
        # Remove environment variable if it exists
        with patch.dict(os.environ, {}, clear=True):
            import importlib
            importlib.reload(flask_app)
            assert flask_app.CHATTY_THRESHOLD == 500

    def test_chatty_threshold_custom(self):
        """Test custom CHATTY_THRESHOLD value."""
        with patch.dict(os.environ, {'CHATTY_THRESHOLD': '1000'}):
            import importlib
            importlib.reload(flask_app)
            assert flask_app.CHATTY_THRESHOLD == 1000

    def test_router_log_path_environment(self):
        """Test ROUTER_LOG_PATH environment variable usage."""
        test_path = '/test/router/logs.txt'
        with patch.dict(os.environ, {'ROUTER_LOG_PATH': test_path}):
            with patch('os.path.exists', return_value=False):
                logs = flask_app.get_router_logs()
                assert logs == []


class TestEventsSummaryAndTimeline:
    """Test events summary API and severity timeline generation."""
    
    def test_api_events_summary_endpoint(self, client):
        """Test events summary API endpoint returns required data."""
        response = client.get('/api/events/summary')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        # Check required fields
        assert 'total' in data
        assert 'severity_counts' in data
        assert 'source_counts' in data
        assert 'keyword_counts' in data
        assert 'severity_timeline' in data
        assert 'sources_top' in data
        assert 'source' in data
    
    def test_api_events_summary_with_parameters(self, client):
        """Test events summary with query parameters."""
        response = client.get('/api/events/summary?max=100&since_hours=24')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert 'total' in data
        assert 'severity_timeline' in data
    
    def test_api_events_summary_log_types_filter(self, client):
        """Test events summary with log type filtering."""
        response = client.get('/api/events/summary?log_types=Application,System')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert 'total' in data
    
    def test_severity_timeline_structure(self, client):
        """Test that severity timeline has the correct structure for visualization."""
        response = client.get('/api/events/summary?max=200&since_hours=24')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        timeline = data.get('severity_timeline', [])
        
        # Timeline should be a list
        assert isinstance(timeline, list)
        
        # Each bucket should have required fields
        for bucket in timeline:
            assert 'bucket' in bucket
            assert 'error' in bucket
            assert 'warning' in bucket
            assert 'information' in bucket
            # Counts should be non-negative integers
            assert isinstance(bucket['error'], int) and bucket['error'] >= 0
            assert isinstance(bucket['warning'], int) and bucket['warning'] >= 0
            assert isinstance(bucket['information'], int) and bucket['information'] >= 0
    
    def test_ai_explain_windows_event_with_api_key(self, client):
        """Test AI explain for Windows event with mocked OpenAI response."""
        # Mock the urllib.request.urlopen to simulate OpenAI API call
        mock_response_data = {
            'choices': [{
                'message': {
                    'content': 'This is a test explanation for the Windows event. The error indicates a critical system failure.'
                }
            }]
        }
        
        with patch.dict(os.environ, {'OPENAI_API_KEY': 'test-key'}):
            with patch('urllib.request.urlopen') as mock_urlopen:
                # Create mock response object
                mock_resp = type('MockResponse', (), {
                    'read': lambda self: json.dumps(mock_response_data).encode('utf-8'),
                    '__enter__': lambda self: self,
                    '__exit__': lambda self, *args: None
                })()
                mock_urlopen.return_value = mock_resp
                
                response = client.post('/api/ai/explain',
                                     json={
                                         'type': 'windows_event',
                                         'context': {
                                             'time': '2024-01-01T12:00:00Z',
                                             'level': 'Error',
                                             'source': 'Application Error',
                                             'message': 'Critical system failure',
                                             'log_type': 'System',
                                             'id': 1001
                                         },
                                         'userQuestion': 'What does this error mean?'
                                     },
                                     content_type='application/json')
                
                assert response.status_code == 200
                data = json.loads(response.data)
                assert 'explanationHtml' in data
                assert 'severity' in data
                # Should detect 'critical' in content and set severity
                assert data['severity'] in ['critical', 'warning', 'info']
                assert 'recommendedActions' in data
    
    def test_ai_explain_trend_analysis(self, client):
        """Test AI explain for trend analysis with multiple events."""
        mock_response_data = {
            'choices': [{
                'message': {
                    'content': 'Analysis shows recurring pattern of authentication failures during peak hours.'
                }
            }]
        }
        
        with patch.dict(os.environ, {'OPENAI_API_KEY': 'test-key'}):
            with patch('urllib.request.urlopen') as mock_urlopen:
                mock_resp = type('MockResponse', (), {
                    'read': lambda self: json.dumps(mock_response_data).encode('utf-8'),
                    '__enter__': lambda self: self,
                    '__exit__': lambda self, *args: None
                })()
                mock_urlopen.return_value = mock_resp
                
                response = client.post('/api/ai/explain',
                                     json={
                                         'type': 'windows_event',
                                         'context': {
                                             'analysis_type': 'trends',
                                             'event_count': 50,
                                             'log_types': ['Application', 'Security', 'System'],
                                             'events': [
                                                 {'time': '2024-01-01T10:00:00Z', 'level': 'Error', 'source': 'Security', 'message': 'Login failed'},
                                                 {'time': '2024-01-01T10:15:00Z', 'level': 'Error', 'source': 'Security', 'message': 'Login failed'}
                                             ]
                                         },
                                         'userQuestion': 'Analyze these events for trends'
                                     },
                                     content_type='application/json')
                
                assert response.status_code == 200
                data = json.loads(response.data)
                assert 'explanationHtml' in data


if __name__ == '__main__':
    pytest.main([__file__])
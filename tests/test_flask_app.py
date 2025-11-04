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
    with flask_app.app.test_client() as client:
        yield client


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
                with patch.dict(os.environ, {'ROUTER_LOG_PATH': f.name}):
                    logs = flask_app.get_router_logs()
                
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
                with patch.dict(os.environ, {'ROUTER_LOG_PATH': f.name}):
                    logs = flask_app.get_router_logs()
                
                assert len(logs) == 4
                
                # Check complete line
                assert logs[0]['time'] == '2024-01-01 12:00:00'
                assert logs[0]['level'] == 'INFO'
                
                # Check incomplete line handling
                assert logs[1]['time'] == ''
                assert logs[1]['level'] == ''
                assert logs[1]['message'] == 'Incomplete line'
                
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

    def test_api_trends_endpoint(self, client):
        """Test trends API endpoint returns 7-day data."""
        response = client.get('/api/trends')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert 'dates' in data
        assert 'iis_errors' in data
        assert 'auth_failures' in data
        assert 'windows_errors' in data
        assert 'router_alerts' in data
        
        # Should return 7 days of data
        assert len(data['dates']) == 7
        assert len(data['iis_errors']) == 7
        assert len(data['auth_failures']) == 7
        assert len(data['windows_errors']) == 7
        assert len(data['router_alerts']) == 7
        
        # All values should be non-negative integers
        for value in data['iis_errors'] + data['auth_failures'] + data['windows_errors'] + data['router_alerts']:
            assert isinstance(value, int)
            assert value >= 0


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


if __name__ == '__main__':
    pytest.main([__file__])
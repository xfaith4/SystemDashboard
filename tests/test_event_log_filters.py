"""
Test suite for event log filtering functionality.
"""
import os
import sys
import pytest

# Add the app directory to the path so we can import app
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'app'))

import app as flask_app


@pytest.fixture
def client():
    """Create a test client for the Flask app."""
    flask_app.app.config['TESTING'] = True
    with flask_app.app.test_client() as client:
        yield client


class TestEventLogFilters:
    """Test event log filtering by log type."""
    
    def test_get_windows_events_defaults_to_all_three_logs(self):
        """Test that get_windows_events defaults to all three log types."""
        events, source = flask_app.get_windows_events(max_events=10, with_source=True)
        assert source == 'mock'  # We're not on Windows
        assert len(events) > 0
        
        # Should have events from all three log types
        log_types = set(e.get('log_type') for e in events)
        assert 'Application' in log_types
        assert 'System' in log_types
        assert 'Security' in log_types
    
    def test_get_windows_events_filter_application_only(self):
        """Test filtering to Application log only."""
        events, source = flask_app.get_windows_events(
            max_events=10, 
            with_source=True, 
            log_types=['Application']
        )
        assert source == 'mock'
        assert len(events) > 0
        
        # Should only have Application events
        log_types = set(e.get('log_type') for e in events)
        assert log_types == {'Application'}
    
    def test_get_windows_events_filter_security_only(self):
        """Test filtering to Security log only."""
        events, source = flask_app.get_windows_events(
            max_events=10, 
            with_source=True, 
            log_types=['Security']
        )
        assert source == 'mock'
        assert len(events) > 0
        
        # Should only have Security events
        log_types = set(e.get('log_type') for e in events)
        assert log_types == {'Security'}
    
    def test_get_windows_events_filter_system_only(self):
        """Test filtering to System log only."""
        events, source = flask_app.get_windows_events(
            max_events=10, 
            with_source=True, 
            log_types=['System']
        )
        assert source == 'mock'
        assert len(events) > 0
        
        # Should only have System events
        log_types = set(e.get('log_type') for e in events)
        assert log_types == {'System'}
    
    def test_get_windows_events_filter_multiple_logs(self):
        """Test filtering to multiple log types."""
        events, source = flask_app.get_windows_events(
            max_events=10, 
            with_source=True, 
            log_types=['Application', 'Security']
        )
        assert source == 'mock'
        assert len(events) > 0
        
        # Should have events from Application and Security but not System
        log_types = set(e.get('log_type') for e in events)
        assert 'Application' in log_types
        assert 'Security' in log_types
        assert 'System' not in log_types
    
    def test_get_windows_events_invalid_log_types_defaults_to_all(self):
        """Test that invalid log types default to all three."""
        events, source = flask_app.get_windows_events(
            max_events=10, 
            with_source=True, 
            log_types=['InvalidLog']
        )
        assert source == 'mock'
        assert len(events) > 0
        
        # Should have events from all three log types as fallback
        log_types = set(e.get('log_type') for e in events)
        assert 'Application' in log_types
        assert 'System' in log_types
        assert 'Security' in log_types
    
    def test_normalize_events_preserves_log_type(self):
        """Test that _normalize_events preserves log_type field."""
        events = [
            {
                'time': '2024-01-01T12:00:00Z',
                'source': 'TestSource',
                'level': 'Information',
                'message': 'Test message',
                'log_type': 'Application'
            }
        ]
        normalized = flask_app._normalize_events(events)
        assert len(normalized) == 1
        assert normalized[0]['log_type'] == 'Application'


class TestEventAPIWithLogTypes:
    """Test API endpoints with log_types parameter."""
    
    def test_api_events_with_log_types_parameter(self, client):
        """Test /api/events endpoint with log_types parameter."""
        response = client.get('/api/events?log_types=Application,Security')
        assert response.status_code == 200
        
        data = response.get_json()
        assert 'events' in data
        assert len(data['events']) > 0
        
        # All events should be from Application or Security
        log_types = set(e.get('log_type') for e in data['events'])
        assert log_types.issubset({'Application', 'Security'})
    
    def test_api_events_without_log_types_returns_all(self, client):
        """Test /api/events endpoint without log_types returns all."""
        response = client.get('/api/events')
        assert response.status_code == 200
        
        data = response.get_json()
        assert 'events' in data
        assert len(data['events']) > 0
        
        # Should have events from all three log types
        log_types = set(e.get('log_type') for e in data['events'])
        assert 'Application' in log_types
        assert 'System' in log_types
        assert 'Security' in log_types
    
    def test_api_events_summary_with_log_types(self, client):
        """Test /api/events/summary endpoint with log_types parameter."""
        response = client.get('/api/events/summary?log_types=System')
        assert response.status_code == 200
        
        data = response.get_json()
        assert 'total' in data
        assert 'severity_counts' in data
        assert data['total'] > 0
    
    def test_api_events_with_single_log_type(self, client):
        """Test /api/events with a single log type."""
        response = client.get('/api/events?log_types=Security&max=50')
        assert response.status_code == 200
        
        data = response.get_json()
        assert 'events' in data
        
        # All events should be from Security log
        log_types = set(e.get('log_type') for e in data['events'])
        if data['events']:  # If there are events
            assert log_types == {'Security'}
    
    def test_api_events_with_empty_log_types(self, client):
        """Test /api/events with empty log_types parameter."""
        response = client.get('/api/events?log_types=')
        assert response.status_code == 200
        
        data = response.get_json()
        assert 'events' in data
        # Should default to all three
        log_types = set(e.get('log_type') for e in data['events'])
        assert len(log_types) >= 1

"""
Test suite for EST timezone conversion functionality.
"""
import os
import sys
import datetime
import zoneinfo
import pytest

# Add the app directory to the path so we can import app
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'app'))

import app as flask_app


def test_to_est_string_with_utc_datetime():
    """Test conversion of UTC datetime to EST string."""
    # Create a UTC datetime
    utc_dt = datetime.datetime(2024, 1, 15, 12, 0, 0, tzinfo=datetime.UTC)
    
    # Convert to EST
    result = flask_app._to_est_string(utc_dt)
    
    # EST is UTC-5 (or UTC-4 during DST)
    # January 15 is during EST (not EDT), so it should be 7:00 AM EST
    assert result is not None
    assert '2024-01-15' in result
    assert '07:00:00' in result or '07:00' in result
    # Verify timezone offset is present
    assert '-05:00' in result


def test_to_est_string_with_iso_string():
    """Test conversion of ISO format string to EST."""
    # UTC timestamp string
    utc_str = "2024-07-15T12:00:00Z"
    
    # Convert to EST
    result = flask_app._to_est_string(utc_str)
    
    # July 15 is during EDT (Eastern Daylight Time, UTC-4)
    assert result is not None
    assert '2024-07-15' in result
    assert '08:00:00' in result or '08:00' in result
    # Verify timezone offset is present
    assert '-04:00' in result


def test_to_est_string_with_none():
    """Test that None input returns empty string."""
    result = flask_app._to_est_string(None)
    assert result == ''


def test_to_est_string_with_windows_date_format():
    """Test conversion of Windows EventLog date format to EST."""
    # Windows date format: /Date(1705320000000)/
    # This represents 2024-01-15 12:00:00 UTC
    windows_date = "/Date(1705320000000)/"
    
    result = flask_app._to_est_string(windows_date)
    
    # Should convert to EST
    assert result is not None
    assert '2024-01-15' in result
    # EST is UTC-5 in January
    assert '07:00' in result


def test_isoformat_wraps_to_est_string():
    """Test that _isoformat properly wraps _to_est_string."""
    utc_dt = datetime.datetime(2024, 1, 15, 12, 0, 0, tzinfo=datetime.UTC)
    
    result = flask_app._isoformat(utc_dt)
    
    # Should produce EST timestamp
    assert result is not None
    assert '2024-01-15' in result
    assert '07:00' in result
    assert '-05:00' in result


def test_api_events_returns_est_timestamps(client):
    """Test that API events endpoint returns EST timestamps."""
    response = client.get('/api/events?max=5')
    assert response.status_code == 200
    
    data = response.json
    events = data.get('events', [])
    
    # Check that events have time fields (if any exist)
    if events:
        for event in events:
            time_str = event.get('time', '')
            if time_str and time_str != '':
                # Should have timezone offset in the string
                # EST is either -05:00 or -04:00
                assert '-04:00' in time_str or '-05:00' in time_str, f"Expected EST timezone in {time_str}"


def test_api_router_logs_returns_est_timestamps(client):
    """Test that API router logs endpoint returns EST timestamps."""
    response = client.get('/api/router/logs?limit=5')
    assert response.status_code == 200
    
    data = response.json
    logs = data.get('logs', [])
    
    # Check that logs have time fields (if any exist)
    if logs:
        for log in logs:
            time_str = log.get('time', '')
            if time_str and time_str != '':
                # Should have timezone offset in the string
                # EST is either -05:00 or -04:00
                assert '-04:00' in time_str or '-05:00' in time_str, f"Expected EST timezone in {time_str}"


def test_api_dashboard_summary_returns_est_timestamps(client):
    """Test that API dashboard summary returns EST timestamps."""
    response = client.get('/api/dashboard/summary')
    assert response.status_code == 200
    
    data = response.json
    
    # Check various timestamp fields in the response
    for auth_item in data.get('auth', []):
        last_seen = auth_item.get('last_seen', '')
        if last_seen and last_seen != '':
            assert '-04:00' in last_seen or '-05:00' in last_seen, f"Expected EST timezone in {last_seen}"
    
    for windows_event in data.get('windows', []):
        time_str = windows_event.get('time', '')
        if time_str and time_str != '':
            assert '-04:00' in time_str or '-05:00' in time_str, f"Expected EST timezone in {time_str}"
    
    for router_entry in data.get('router', []):
        time_str = router_entry.get('time', '')
        if time_str and time_str != '':
            assert '-04:00' in time_str or '-05:00' in time_str, f"Expected EST timezone in {time_str}"


@pytest.fixture
def client():
    """Create a test client for the Flask app."""
    flask_app.app.config['TESTING'] = True
    with flask_app.app.test_client() as client:
        yield client

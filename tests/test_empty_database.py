"""
Test that dashboard correctly handles an empty database scenario.

When database is connected but contains no data, the dashboard should
show mock data to provide a helpful example, rather than showing zeros.
"""
import sys
import os
import sqlite3
from unittest.mock import MagicMock, patch

# Add the app directory to the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import app as flask_app


class MockRow(dict):
    """Mock SQLite Row that supports both dict access and attribute access."""
    def __getitem__(self, key):
        return super().get(key)


def make_mock_cursor(fetchone_results=None, fetchall_results=None):
    """Create a mock cursor that behaves like SQLite cursor."""
    mock_cursor = MagicMock()
    
    fetchone_iter = iter(fetchone_results or [])
    fetchall_iter = iter(fetchall_results or [])
    
    def fetchone_side_effect():
        try:
            result = next(fetchone_iter)
            return MockRow(result) if result else None
        except StopIteration:
            return None
    
    def fetchall_side_effect():
        try:
            result = next(fetchall_iter)
            return [MockRow(r) for r in result] if result else []
        except StopIteration:
            return []
    
    mock_cursor.fetchone.side_effect = fetchone_side_effect
    mock_cursor.fetchall.side_effect = fetchall_side_effect
    mock_cursor.rowcount = 0
    
    return mock_cursor


def test_empty_database_returns_mock_data():
    """Test that an empty but connected database returns mock data."""
    
    # Create a mock database connection that returns empty results
    mock_conn = MagicMock()
    mock_cursor = make_mock_cursor(
        fetchone_results=[
            {'errors': 0, 'total': 0},  # IIS current query
            {'avg_errors': 0},  # IIS baseline query
            {'count': 0},  # LAN stats
            {'new_count': 0},  # New devices
        ] + [{'errors': 0, 'iis_errors': 0, 'auth_failures': 0}] * 20,  # Hourly breakdown
        fetchall_results=[
            [],  # Auth query
            [],  # Windows query
            [],  # Router query
            [],  # Syslog query
        ]
    )
    mock_conn.cursor.return_value = mock_cursor
    
    # Patch get_db_connection to return our mock
    with patch('app.get_db_connection', return_value=mock_conn):
        result = flask_app.get_dashboard_summary()
    
    # Verify that mock data is returned
    assert result['using_mock'] is True, 'Should use mock data when database is empty'
    assert result['iis']['current_errors'] > 0, 'Mock data should have IIS errors'
    assert len(result['auth']) > 0, 'Mock data should have auth failures'
    assert len(result['windows']) > 0, 'Mock data should have Windows events'
    assert len(result['router']) > 0, 'Mock data should have router alerts'
    assert len(result['syslog']) > 0, 'Mock data should have syslog entries'


def test_database_with_iis_data_only():
    """Test that database with only IIS data returns real data."""
    
    # Create a mock database connection with IIS data but nothing else
    mock_conn = MagicMock()
    mock_cursor = make_mock_cursor(
        fetchone_results=[
            {'errors': 5, 'total': 100},  # IIS current query - has data!
            {'avg_errors': 2.5},  # IIS baseline query
            {'count': 0},  # LAN stats
            {'new_count': 0},  # New devices
        ] + [{'errors': 0, 'iis_errors': 0, 'auth_failures': 0}] * 20,  # Hourly breakdown
        fetchall_results=[
            [],  # Auth query
            [],  # Windows query
            [],  # Router query
            [],  # Syslog query
        ]
    )
    mock_conn.cursor.return_value = mock_cursor
    
    # Patch get_db_connection to return our mock
    with patch('app.get_db_connection', return_value=mock_conn):
        result = flask_app.get_dashboard_summary()
    
    # Verify that real data is returned (not mock)
    assert result['using_mock'] is False, 'Should use real data when IIS data exists'
    assert result['iis']['current_errors'] == 5, 'Should return actual IIS errors'
    assert result['iis']['total_requests'] == 100, 'Should return actual total requests'


def test_database_with_syslog_data_only():
    """Test that database with only syslog data returns real data."""
    
    # Create a mock database connection with syslog data but nothing else
    mock_conn = MagicMock()
    mock_cursor = make_mock_cursor(
        fetchone_results=[
            {'errors': 0, 'total': 0},  # IIS current query - no data
            {'avg_errors': 0},  # IIS baseline query
            {'count': 0},  # LAN stats
            {'new_count': 0},  # New devices
        ] + [{'errors': 0, 'iis_errors': 0, 'auth_failures': 0}] * 20,  # Hourly breakdown
        fetchall_results=[
            [],  # Auth query
            [],  # Windows query
            [],  # Router query
            [{
                'received_utc': '2024-01-01T12:00:00Z',
                'source': 'test',
                'source_host': 'test-host',
                'severity': 6,
                'message': 'Test message'
            }],  # Syslog query
        ]
    )
    mock_conn.cursor.return_value = mock_cursor
    
    # Patch get_db_connection to return our mock
    with patch('app.get_db_connection', return_value=mock_conn):
        result = flask_app.get_dashboard_summary()
    
    # Verify that real data is returned (not mock)
    assert result['using_mock'] is False, 'Should use real data when syslog data exists'
    assert len(result['syslog']) > 0, 'Should have syslog entries'


if __name__ == '__main__':
    test_empty_database_returns_mock_data()
    print('✓ test_empty_database_returns_mock_data passed')
    
    test_database_with_iis_data_only()
    print('✓ test_database_with_iis_data_only passed')
    
    test_database_with_syslog_data_only()
    print('✓ test_database_with_syslog_data_only passed')
    
    print('\n✓ All tests passed!')

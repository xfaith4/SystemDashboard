"""Tests for health check module."""

import pytest
import sqlite3
import os
import sys
import tempfile
import datetime

# Add the app directory to the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'app'))

from health_check import (
    check_database_health,
    check_data_freshness,
    check_schema_integrity,
    get_comprehensive_health,
    HealthStatus
)


@pytest.fixture
def temp_db():
    """Create a temporary database for testing."""
    fd, path = tempfile.mkstemp(suffix='.db')
    os.close(fd)
    
    # Create basic schema
    conn = sqlite3.connect(path)
    cursor = conn.cursor()
    
    # Create required tables
    cursor.execute("""
        CREATE TABLE devices (
            device_id INTEGER PRIMARY KEY,
            mac_address TEXT UNIQUE NOT NULL,
            is_active INTEGER DEFAULT 1
        )
    """)
    
    cursor.execute("""
        CREATE TABLE device_snapshots (
            snapshot_id INTEGER PRIMARY KEY,
            device_id INTEGER,
            snapshot_time_utc TEXT,
            FOREIGN KEY (device_id) REFERENCES devices(device_id)
        )
    """)
    
    cursor.execute("""
        CREATE TABLE device_alerts (
            alert_id INTEGER PRIMARY KEY,
            device_id INTEGER,
            severity TEXT
        )
    """)
    
    cursor.execute("""
        CREATE TABLE ai_feedback (
            feedback_id INTEGER PRIMARY KEY,
            rating INTEGER
        )
    """)
    
    cursor.execute("""
        CREATE TABLE syslog_recent (
            id INTEGER PRIMARY KEY,
            syslog_timestamp_utc TEXT,
            message TEXT
        )
    """)
    
    # Create required views
    cursor.execute("""
        CREATE VIEW lan_summary_stats AS
        SELECT COUNT(*) as total FROM devices
    """)
    
    cursor.execute("""
        CREATE VIEW device_alerts_active AS
        SELECT * FROM device_alerts WHERE severity = 'critical'
    """)
    
    conn.commit()
    conn.close()
    
    yield path
    
    # Cleanup
    try:
        os.unlink(path)
    except:
        pass


class TestDatabaseHealth:
    """Test database health checks."""
    
    def test_healthy_database(self, temp_db):
        """Test health check with healthy database."""
        result = check_database_health(temp_db)
        
        assert result['status'] == HealthStatus.HEALTHY
        assert result['response_time_ms'] is not None
        assert result['response_time_ms'] < 100
        assert result['error'] is None
    
    def test_nonexistent_database(self):
        """Test health check with nonexistent database."""
        result = check_database_health('/nonexistent/path/db.db')
        
        assert result['status'] == HealthStatus.UNHEALTHY
        assert result['error'] is not None
        assert 'unable to open database' in result['error'].lower()
    
    def test_database_timeout(self, temp_db):
        """Test health check respects timeout."""
        # This should complete quickly
        result = check_database_health(temp_db, timeout=0.1)
        assert result['response_time_ms'] is not None


class TestDataFreshness:
    """Test data freshness checks."""
    
    def test_fresh_data(self, temp_db):
        """Test with fresh data."""
        conn = sqlite3.connect(temp_db)
        cursor = conn.cursor()
        
        # Insert recent snapshot
        now = datetime.datetime.now(datetime.UTC)
        cursor.execute("""
            INSERT INTO devices (mac_address) VALUES ('AA:BB:CC:DD:EE:FF')
        """)
        cursor.execute("""
            INSERT INTO device_snapshots (device_id, snapshot_time_utc)
            VALUES (1, ?)
        """, (now.isoformat(),))
        
        # Insert recent syslog
        cursor.execute("""
            INSERT INTO syslog_recent (syslog_timestamp_utc, message)
            VALUES (?, 'test message')
        """, (now.isoformat(),))
        
        conn.commit()
        conn.close()
        
        result = check_data_freshness(temp_db, max_age_minutes=5)
        
        assert result['status'] == HealthStatus.HEALTHY
        assert 'device_snapshots' in result['checks']
        assert result['checks']['device_snapshots']['status'] == HealthStatus.HEALTHY
        assert 'syslog' in result['checks']
        assert result['checks']['syslog']['status'] == HealthStatus.HEALTHY
    
    def test_stale_data(self, temp_db):
        """Test with stale data."""
        conn = sqlite3.connect(temp_db)
        cursor = conn.cursor()
        
        # Insert old snapshot (2 hours ago)
        old_time = datetime.datetime.now(datetime.UTC) - datetime.timedelta(hours=2)
        cursor.execute("""
            INSERT INTO devices (mac_address) VALUES ('AA:BB:CC:DD:EE:FF')
        """)
        cursor.execute("""
            INSERT INTO device_snapshots (device_id, snapshot_time_utc)
            VALUES (1, ?)
        """, (old_time.isoformat(),))
        
        conn.commit()
        conn.close()
        
        result = check_data_freshness(temp_db, max_age_minutes=60)
        
        assert result['status'] == HealthStatus.DEGRADED
        assert result['checks']['device_snapshots']['status'] == HealthStatus.DEGRADED
    
    def test_no_data(self, temp_db):
        """Test with no data."""
        result = check_data_freshness(temp_db)
        
        assert result['status'] == HealthStatus.DEGRADED
        assert 'device_snapshots' in result['checks']
        assert 'syslog' in result['checks']


class TestSchemaIntegrity:
    """Test schema integrity checks."""
    
    def test_valid_schema(self, temp_db):
        """Test with valid schema."""
        result = check_schema_integrity(temp_db)
        
        assert result['status'] == HealthStatus.HEALTHY
        assert len(result['missing_tables']) == 0
        assert len(result['missing_views']) == 0
    
    def test_missing_table(self, temp_db):
        """Test with missing table."""
        # Drop a required table
        conn = sqlite3.connect(temp_db)
        cursor = conn.cursor()
        cursor.execute("DROP TABLE ai_feedback")
        conn.commit()
        conn.close()
        
        result = check_schema_integrity(temp_db)
        
        assert result['status'] == HealthStatus.UNHEALTHY
        assert 'ai_feedback' in result['missing_tables']
    
    def test_missing_view(self, temp_db):
        """Test with missing view."""
        # Drop a required view
        conn = sqlite3.connect(temp_db)
        cursor = conn.cursor()
        cursor.execute("DROP VIEW lan_summary_stats")
        conn.commit()
        conn.close()
        
        result = check_schema_integrity(temp_db)
        
        assert result['status'] == HealthStatus.UNHEALTHY
        assert 'lan_summary_stats' in result['missing_views']


class TestComprehensiveHealth:
    """Test comprehensive health check."""
    
    def test_healthy_system(self, temp_db):
        """Test with fully healthy system."""
        # Add fresh data
        conn = sqlite3.connect(temp_db)
        cursor = conn.cursor()
        now = datetime.datetime.now(datetime.UTC)
        
        cursor.execute("INSERT INTO devices (mac_address) VALUES ('AA:BB:CC:DD:EE:FF')")
        cursor.execute(
            "INSERT INTO device_snapshots (device_id, snapshot_time_utc) VALUES (1, ?)",
            (now.isoformat(),)
        )
        cursor.execute(
            "INSERT INTO syslog_recent (syslog_timestamp_utc, message) VALUES (?, 'test')",
            (now.isoformat(),)
        )
        
        conn.commit()
        conn.close()
        
        report, http_code = get_comprehensive_health(temp_db)
        
        assert report['overall_status'] == HealthStatus.HEALTHY
        assert http_code == 200
        assert 'database' in report['subsystems']
        assert 'schema' in report['subsystems']
        assert 'data_freshness' in report['subsystems']
    
    def test_degraded_system(self, temp_db):
        """Test with degraded system (stale data)."""
        report, http_code = get_comprehensive_health(temp_db)
        
        # No data = degraded
        assert report['overall_status'] == HealthStatus.DEGRADED
        assert http_code == 200  # Still serving requests
    
    def test_unhealthy_system(self):
        """Test with unhealthy system (no database)."""
        report, http_code = get_comprehensive_health('/nonexistent/db.db')
        
        assert report['overall_status'] == HealthStatus.UNHEALTHY
        assert http_code == 503
        assert 'database' in report['subsystems']

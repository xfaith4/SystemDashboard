"""
Tests for data retention module.
"""

import os
import sys
import pytest
import sqlite3
from datetime import datetime, timedelta

# Add the app directory to the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'app'))

from data_retention import DataRetentionManager, get_retention_manager


@pytest.fixture
def test_db():
    """Create a test database with sample data."""
    conn = sqlite3.connect(':memory:')
    cursor = conn.cursor()
    
    # Create tables
    cursor.execute('''
        CREATE TABLE device_snapshots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            mac TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            status TEXT,
            signal_strength INTEGER
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE device_alerts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id INTEGER NOT NULL,
            severity TEXT NOT NULL,
            message TEXT,
            created_at TEXT NOT NULL,
            resolved INTEGER DEFAULT 0,
            resolved_at TEXT
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE syslog_recent (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            severity TEXT,
            message TEXT,
            source TEXT
        )
    ''')
    
    conn.commit()
    yield conn
    conn.close()


def insert_snapshots(conn, days_old_list):
    """Helper to insert test snapshots at various ages."""
    cursor = conn.cursor()
    for days_old in days_old_list:
        timestamp = (datetime.utcnow() - timedelta(days=days_old)).strftime('%Y-%m-%d %H:%M:%S')
        cursor.execute(
            "INSERT INTO device_snapshots (mac, timestamp, status) VALUES (?, ?, ?)",
            ('AA:BB:CC:DD:EE:FF', timestamp, 'online')
        )
    conn.commit()


def insert_alerts(conn, resolved_days_old_list, unresolved_days_old_list):
    """Helper to insert test alerts (both resolved and unresolved)."""
    cursor = conn.cursor()
    
    # Insert resolved alerts
    for days_old in resolved_days_old_list:
        created_at = (datetime.utcnow() - timedelta(days=days_old)).strftime('%Y-%m-%d %H:%M:%S')
        resolved_at = (datetime.utcnow() - timedelta(days=days_old - 0.5)).strftime('%Y-%m-%d %H:%M:%S')
        cursor.execute(
            "INSERT INTO device_alerts (device_id, severity, message, created_at, resolved, resolved_at) VALUES (?, ?, ?, ?, ?, ?)",
            (1, 'warning', 'Test alert', created_at, 1, resolved_at)
        )
    
    # Insert unresolved alerts
    for days_old in unresolved_days_old_list:
        created_at = (datetime.utcnow() - timedelta(days=days_old)).strftime('%Y-%m-%d %H:%M:%S')
        cursor.execute(
            "INSERT INTO device_alerts (device_id, severity, message, created_at, resolved) VALUES (?, ?, ?, ?, ?)",
            (1, 'warning', 'Test alert', created_at, 0)
        )
    
    conn.commit()


def insert_syslog(conn, days_old_list):
    """Helper to insert test syslog entries."""
    cursor = conn.cursor()
    for days_old in days_old_list:
        timestamp = (datetime.utcnow() - timedelta(days=days_old)).strftime('%Y-%m-%d %H:%M:%S')
        cursor.execute(
            "INSERT INTO syslog_recent (timestamp, severity, message, source) VALUES (?, ?, ?, ?)",
            (timestamp, 'info', 'Test log', 'router')
        )
    conn.commit()


class TestDataRetentionManager:
    """Test DataRetentionManager class."""
    
    def test_initialization(self, test_db):
        """Test manager initialization."""
        manager = DataRetentionManager(test_db)
        assert manager.connection == test_db
    
    def test_cleanup_old_snapshots_basic(self, test_db):
        """Test basic snapshot cleanup."""
        # Insert snapshots: 3, 5, 10, 15 days old
        insert_snapshots(test_db, [3, 5, 10, 15])
        
        manager = DataRetentionManager(test_db)
        deleted = manager.cleanup_old_snapshots(retention_days=7)
        
        # Should delete 2 snapshots (10 and 15 days old)
        assert deleted == 2
        
        # Verify remaining count
        cursor = test_db.cursor()
        cursor.execute("SELECT COUNT(*) FROM device_snapshots")
        assert cursor.fetchone()[0] == 2
    
    def test_cleanup_old_snapshots_none_to_delete(self, test_db):
        """Test cleanup when no old snapshots exist."""
        # Insert recent snapshots
        insert_snapshots(test_db, [1, 2, 3])
        
        manager = DataRetentionManager(test_db)
        deleted = manager.cleanup_old_snapshots(retention_days=7)
        
        assert deleted == 0
        
        # All snapshots should remain
        cursor = test_db.cursor()
        cursor.execute("SELECT COUNT(*) FROM device_snapshots")
        assert cursor.fetchone()[0] == 3
    
    def test_cleanup_old_snapshots_all_old(self, test_db):
        """Test cleanup when all snapshots are old."""
        # Insert old snapshots
        insert_snapshots(test_db, [10, 15, 20, 30])
        
        manager = DataRetentionManager(test_db)
        deleted = manager.cleanup_old_snapshots(retention_days=7)
        
        assert deleted == 4
        
        # No snapshots should remain
        cursor = test_db.cursor()
        cursor.execute("SELECT COUNT(*) FROM device_snapshots")
        assert cursor.fetchone()[0] == 0
    
    def test_cleanup_old_snapshots_invalid_retention(self, test_db):
        """Test that invalid retention days raises error."""
        manager = DataRetentionManager(test_db)
        
        with pytest.raises(ValueError, match="must be at least 1"):
            manager.cleanup_old_snapshots(retention_days=0)
        
        with pytest.raises(ValueError):
            manager.cleanup_old_snapshots(retention_days=-5)
    
    def test_cleanup_old_alerts_basic(self, test_db):
        """Test basic alert cleanup."""
        # Insert resolved alerts: 20, 40, 60 days old
        # Insert unresolved alerts: 20, 40 days old
        insert_alerts(test_db, [20, 40, 60], [20, 40])
        
        manager = DataRetentionManager(test_db)
        deleted = manager.cleanup_old_alerts(retention_days=30)
        
        # Should delete 2 resolved alerts (40 and 60 days old)
        # Unresolved alerts should be kept regardless of age
        assert deleted == 2
        
        # Verify remaining count (1 resolved + 2 unresolved)
        cursor = test_db.cursor()
        cursor.execute("SELECT COUNT(*) FROM device_alerts")
        assert cursor.fetchone()[0] == 3
        
        # Verify unresolved alerts remain
        cursor.execute("SELECT COUNT(*) FROM device_alerts WHERE resolved = 0")
        assert cursor.fetchone()[0] == 2
    
    def test_cleanup_old_alerts_keeps_unresolved(self, test_db):
        """Test that unresolved alerts are never deleted."""
        # Insert old unresolved alerts
        insert_alerts(test_db, [], [100, 200, 365])
        
        manager = DataRetentionManager(test_db)
        deleted = manager.cleanup_old_alerts(retention_days=30)
        
        assert deleted == 0
        
        # All unresolved alerts should remain
        cursor = test_db.cursor()
        cursor.execute("SELECT COUNT(*) FROM device_alerts")
        assert cursor.fetchone()[0] == 3
    
    def test_cleanup_old_syslog_basic(self, test_db):
        """Test basic syslog cleanup."""
        # Insert syslog: 5, 10, 20, 30 days old
        insert_syslog(test_db, [5, 10, 20, 30])
        
        manager = DataRetentionManager(test_db)
        deleted = manager.cleanup_old_syslog(retention_days=14)
        
        # Should delete 2 entries (20 and 30 days old)
        assert deleted == 2
        
        cursor = test_db.cursor()
        cursor.execute("SELECT COUNT(*) FROM syslog_recent")
        assert cursor.fetchone()[0] == 2
    
    def test_get_table_sizes(self, test_db):
        """Test getting table sizes."""
        insert_snapshots(test_db, [1, 2, 3])
        insert_alerts(test_db, [1, 2], [3, 4, 5])
        insert_syslog(test_db, [1, 2, 3, 4])
        
        manager = DataRetentionManager(test_db)
        sizes = manager.get_table_sizes()
        
        assert sizes['device_snapshots'] == 3
        assert sizes['device_alerts'] == 5
        assert sizes['syslog_recent'] == 4
    
    def test_get_table_sizes_empty(self, test_db):
        """Test getting sizes of empty tables."""
        manager = DataRetentionManager(test_db)
        sizes = manager.get_table_sizes()
        
        assert sizes['device_snapshots'] == 0
        assert sizes['device_alerts'] == 0
        assert sizes['syslog_recent'] == 0
    
    def test_vacuum_database(self, test_db):
        """Test database vacuum operation."""
        manager = DataRetentionManager(test_db)
        
        # Should not raise an exception
        manager.vacuum_database()
    
    def test_run_full_cleanup(self, test_db):
        """Test full cleanup across all tables."""
        # Setup test data
        insert_snapshots(test_db, [1, 5, 10, 15])
        insert_alerts(test_db, [5, 35, 45], [100])
        insert_syslog(test_db, [1, 10, 20])
        
        manager = DataRetentionManager(test_db)
        results = manager.run_full_cleanup(
            snapshot_retention_days=7,
            alert_retention_days=30,
            syslog_retention_days=14,
            vacuum=False
        )
        
        # Check results
        assert results['deleted']['device_snapshots'] == 2  # 10, 15 days old
        assert results['deleted']['device_alerts'] == 2      # 35, 45 days old
        assert results['deleted']['syslog_recent'] == 1      # 20 days old
        assert results['errors'] == []
        assert results['vacuum_performed'] == False
    
    def test_run_full_cleanup_with_vacuum(self, test_db):
        """Test full cleanup with vacuum."""
        insert_snapshots(test_db, [10, 15])
        
        manager = DataRetentionManager(test_db)
        results = manager.run_full_cleanup(
            snapshot_retention_days=7,
            vacuum=True
        )
        
        assert results['deleted']['device_snapshots'] == 2
        assert results['vacuum_performed'] == True
        assert results['errors'] == []
    
    def test_run_full_cleanup_no_vacuum_when_nothing_deleted(self, test_db):
        """Test that vacuum is skipped when nothing is deleted."""
        insert_snapshots(test_db, [1, 2])
        
        manager = DataRetentionManager(test_db)
        results = manager.run_full_cleanup(
            snapshot_retention_days=7,
            vacuum=True
        )
        
        assert sum(results['deleted'].values()) == 0
        assert results['vacuum_performed'] == False


class TestGetRetentionManager:
    """Test get_retention_manager context manager."""
    
    def test_context_manager(self, test_db):
        """Test context manager usage."""
        with get_retention_manager(test_db) as manager:
            assert isinstance(manager, DataRetentionManager)
            assert manager.connection == test_db
    
    def test_context_manager_operations(self, test_db):
        """Test operations within context manager."""
        insert_snapshots(test_db, [10, 15])
        
        with get_retention_manager(test_db) as manager:
            deleted = manager.cleanup_old_snapshots(retention_days=7)
            assert deleted == 2
        
        # Verify cleanup occurred
        cursor = test_db.cursor()
        cursor.execute("SELECT COUNT(*) FROM device_snapshots")
        assert cursor.fetchone()[0] == 0


class TestDataRetentionEdgeCases:
    """Test edge cases and error handling."""
    
    def test_cleanup_with_missing_table(self):
        """Test cleanup when table doesn't exist."""
        conn = sqlite3.connect(':memory:')
        manager = DataRetentionManager(conn)
        
        # Should raise an error since table doesn't exist
        with pytest.raises(sqlite3.OperationalError):
            manager.cleanup_old_snapshots(7)
    
    def test_boundary_condition_exact_retention(self, test_db):
        """Test snapshot exactly at retention boundary."""
        # Insert snapshot exactly 7 days old (to the second)
        exactly_7_days = datetime.utcnow() - timedelta(days=7, seconds=0)
        cursor = test_db.cursor()
        cursor.execute(
            "INSERT INTO device_snapshots (mac, timestamp, status) VALUES (?, ?, ?)",
            ('AA:BB:CC:DD:EE:FF', exactly_7_days.strftime('%Y-%m-%d %H:%M:%S'), 'online')
        )
        test_db.commit()
        
        manager = DataRetentionManager(test_db)
        deleted = manager.cleanup_old_snapshots(retention_days=7)
        
        # Snapshot at exactly 7 days should be kept (not older than cutoff)
        assert deleted == 0
    
    def test_cleanup_with_various_timestamp_formats(self, test_db):
        """Test cleanup works with different timestamp formats."""
        cursor = test_db.cursor()
        
        # Insert with different timestamp formats
        old_time1 = (datetime.utcnow() - timedelta(days=10)).strftime('%Y-%m-%d %H:%M:%S')
        old_time2 = (datetime.utcnow() - timedelta(days=15)).strftime('%Y-%m-%d %H:%M:%S.%f')
        
        cursor.execute(
            "INSERT INTO device_snapshots (mac, timestamp, status) VALUES (?, ?, ?)",
            ('AA:BB:CC:DD:EE:FF', old_time1, 'online')
        )
        cursor.execute(
            "INSERT INTO device_snapshots (mac, timestamp, status) VALUES (?, ?, ?)",
            ('AA:BB:CC:DD:EE:FF', old_time2, 'online')
        )
        test_db.commit()
        
        manager = DataRetentionManager(test_db)
        deleted = manager.cleanup_old_snapshots(retention_days=7)
        
        # Both should be deleted
        assert deleted == 2

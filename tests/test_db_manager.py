"""
Test suite for database manager with connection pooling and retry logic.
"""
import os
import sys
import tempfile
import pytest
import sqlite3
import time
from threading import Thread
from unittest.mock import patch, MagicMock

# Add the app directory to the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'app'))

from db_manager import ConnectionPool, DatabaseManager, get_db_manager


@pytest.fixture
def temp_db():
    """Create a temporary database for testing."""
    fd, path = tempfile.mkstemp(suffix='.db')
    os.close(fd)
    yield path
    try:
        os.unlink(path)
    except Exception:
        pass


@pytest.fixture
def db_with_schema(temp_db):
    """Create a temporary database with test schema."""
    conn = sqlite3.connect(temp_db)
    cursor = conn.cursor()
    
    # Create required tables
    cursor.execute('''
        CREATE TABLE devices (
            device_id INTEGER PRIMARY KEY,
            mac_address TEXT NOT NULL UNIQUE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE device_snapshots (
            snapshot_id INTEGER PRIMARY KEY,
            device_id INTEGER,
            sample_time_utc TIMESTAMP,
            FOREIGN KEY (device_id) REFERENCES devices(device_id)
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE device_alerts (
            alert_id INTEGER PRIMARY KEY,
            device_id INTEGER,
            severity TEXT,
            FOREIGN KEY (device_id) REFERENCES devices(device_id)
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE ai_feedback (
            id INTEGER PRIMARY KEY,
            message TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE syslog_recent (
            id INTEGER PRIMARY KEY,
            message TEXT,
            received_utc TIMESTAMP
        )
    ''')
    
    # Create required views
    cursor.execute('''
        CREATE VIEW lan_summary_stats AS
        SELECT COUNT(*) as total_devices FROM devices
    ''')
    
    cursor.execute('''
        CREATE VIEW device_alerts_active AS
        SELECT * FROM device_alerts
    ''')
    
    conn.commit()
    conn.close()
    
    yield temp_db


class TestConnectionPool:
    """Test connection pool functionality."""
    
    def test_pool_creation(self, temp_db):
        """Test that connection pool can be created."""
        pool = ConnectionPool(temp_db, max_connections=3)
        assert pool.db_path == temp_db
        assert pool.max_connections == 3
        assert len(pool.connections) == 0
        
    def test_get_connection(self, temp_db):
        """Test getting a connection from the pool."""
        pool = ConnectionPool(temp_db)
        
        with pool.get_connection() as conn:
            assert conn is not None
            cursor = conn.cursor()
            cursor.execute("SELECT 1")
            result = cursor.fetchone()
            assert result[0] == 1
            
    def test_connection_reuse(self, temp_db):
        """Test that connections are reused from the pool."""
        pool = ConnectionPool(temp_db, max_connections=2)
        
        # Get and release a connection
        with pool.get_connection() as conn1:
            conn1_id = id(conn1)
            
        # Get another connection - should be the same one
        with pool.get_connection() as conn2:
            conn2_id = id(conn2)
            
        assert conn1_id == conn2_id
        
    def test_concurrent_connections(self, temp_db):
        """Test multiple concurrent connections."""
        pool = ConnectionPool(temp_db, max_connections=5)
        results = []
        
        def query_db():
            with pool.get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT 1")
                result = cursor.fetchone()
                results.append(result[0])
                time.sleep(0.1)  # Simulate some work
                
        # Create multiple threads
        threads = [Thread(target=query_db) for _ in range(10)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
            
        assert len(results) == 10
        assert all(r == 1 for r in results)
        
    def test_wal_mode_enabled(self, temp_db):
        """Test that WAL mode is enabled for connections."""
        pool = ConnectionPool(temp_db)
        
        with pool.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("PRAGMA journal_mode")
            mode = cursor.fetchone()[0]
            assert mode.lower() == 'wal'
            
    def test_foreign_keys_enabled(self, temp_db):
        """Test that foreign keys are enabled."""
        pool = ConnectionPool(temp_db)
        
        with pool.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("PRAGMA foreign_keys")
            enabled = cursor.fetchone()[0]
            assert enabled == 1
            
    def test_close_all_connections(self, temp_db):
        """Test closing all connections in the pool."""
        pool = ConnectionPool(temp_db, max_connections=3)
        
        # Create some connections
        with pool.get_connection() as conn1:
            pass
        with pool.get_connection() as conn2:
            pass
            
        assert len(pool.connections) > 0
        
        pool.close_all()
        assert len(pool.connections) == 0
        assert len(pool.in_use) == 0


class TestDatabaseManager:
    """Test database manager functionality."""
    
    def test_manager_creation(self, temp_db):
        """Test that database manager can be created."""
        manager = DatabaseManager(temp_db)
        assert manager.db_path == temp_db
        assert manager.max_retries == 3
        
    def test_execute_simple_query(self, temp_db):
        """Test executing a simple query."""
        manager = DatabaseManager(temp_db)
        
        # Create a table
        manager.execute_with_retry('''
            CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)
        ''')
        
        # Insert data
        manager.execute_with_retry(
            "INSERT INTO test (name) VALUES (?)",
            ('test_name',)
        )
        
        # Query data
        with manager.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT name FROM test")
            result = cursor.fetchone()
            assert result['name'] == 'test_name'
            
    def test_schema_validation_success(self, db_with_schema):
        """Test schema validation with all required objects present."""
        manager = DatabaseManager(db_with_schema)
        is_valid, missing = manager.validate_schema()
        
        assert is_valid is True
        assert len(missing) == 0
        
    def test_schema_validation_missing_table(self, temp_db):
        """Test schema validation with missing table."""
        manager = DatabaseManager(temp_db)
        is_valid, missing = manager.validate_schema()
        
        assert is_valid is False
        assert len(missing) > 0
        assert any('table:devices' in m for m in missing)
        
    def test_schema_validation_missing_view(self, temp_db):
        """Test schema validation with missing view."""
        # Create tables but not views
        conn = sqlite3.connect(temp_db)
        cursor = conn.cursor()
        
        for table in ['devices', 'device_snapshots', 'device_alerts', 'ai_feedback', 'syslog_recent']:
            cursor.execute(f'CREATE TABLE {table} (id INTEGER PRIMARY KEY)')
            
        conn.commit()
        conn.close()
        
        manager = DatabaseManager(temp_db)
        is_valid, missing = manager.validate_schema()
        
        assert is_valid is False
        assert any('view:' in m for m in missing)
        
    def test_retry_on_locked_database(self, temp_db):
        """Test retry logic when database is locked."""
        manager = DatabaseManager(temp_db, max_retries=2)
        
        # Create a table first
        manager.execute_with_retry('''
            CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)
        ''')
        
        # Mock the execute to fail once with locked error, then succeed
        original_get_connection = manager.pool.get_connection
        call_count = [0]
        
        class MockConnection:
            def __init__(self, real_conn):
                self.real_conn = real_conn
                self.in_transaction = False
                
            def cursor(self):
                call_count[0] += 1
                if call_count[0] == 1:
                    raise sqlite3.OperationalError("database is locked")
                return self.real_conn.cursor()
                
            def commit(self):
                return self.real_conn.commit()
                
            def rollback(self):
                return self.real_conn.rollback()
                
            def close(self):
                return self.real_conn.close()
        
        from contextlib import contextmanager
        
        @contextmanager
        def mock_get_connection():
            with original_get_connection() as conn:
                yield MockConnection(conn)
        
        with patch.object(manager.pool, 'get_connection', mock_get_connection):
            # Should retry and succeed
            cursor = manager.execute_with_retry(
                "INSERT INTO test (value) VALUES (?)",
                ('test',)
            )
            assert call_count[0] == 2  # Failed once, succeeded on retry
            
    def test_transaction_rollback_on_error(self, db_with_schema):
        """Test that transactions are rolled back on error."""
        manager = DatabaseManager(db_with_schema)
        
        # Insert a device
        manager.execute_with_retry(
            "INSERT INTO devices (mac_address) VALUES (?)",
            ('AA:BB:CC:DD:EE:FF',)
        )
        
        # Try to insert duplicate (should fail due to UNIQUE constraint)
        with pytest.raises(sqlite3.IntegrityError):
            manager.execute_with_retry(
                "INSERT INTO devices (mac_address) VALUES (?)",
                ('AA:BB:CC:DD:EE:FF',)
            )
            
        # Verify only one record exists
        with manager.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT COUNT(*) as count FROM devices")
            count = cursor.fetchone()['count']
            assert count == 1


class TestGetDbManager:
    """Test global database manager singleton."""
    
    def test_get_manager_creates_instance(self, temp_db):
        """Test that get_db_manager creates a new instance."""
        manager = get_db_manager(temp_db)
        assert manager is not None
        assert manager.db_path == temp_db
        
    def test_get_manager_returns_same_instance(self, temp_db):
        """Test that get_db_manager returns the same instance."""
        manager1 = get_db_manager(temp_db)
        manager2 = get_db_manager(temp_db)
        assert manager1 is manager2
        
    def test_get_manager_creates_new_for_different_path(self, temp_db):
        """Test that get_db_manager creates new instance for different path."""
        manager1 = get_db_manager(temp_db)
        
        # Create another temp db
        fd, temp_db2 = tempfile.mkstemp(suffix='.db')
        os.close(fd)
        
        try:
            manager2 = get_db_manager(temp_db2)
            assert manager1 is not manager2
            assert manager2.db_path == temp_db2
        finally:
            try:
                os.unlink(temp_db2)
            except Exception:
                pass


class TestConcurrentAccess:
    """Test concurrent database access scenarios."""
    
    def test_concurrent_writes(self, db_with_schema):
        """Test multiple concurrent write operations."""
        manager = DatabaseManager(db_with_schema, max_retries=5)
        errors = []
        
        def insert_device(mac_suffix):
            try:
                manager.execute_with_retry(
                    "INSERT INTO devices (mac_address) VALUES (?)",
                    (f'AA:BB:CC:DD:EE:{mac_suffix:02X}',)
                )
            except Exception as e:
                errors.append(str(e))
                
        # Create multiple threads writing concurrently
        threads = [Thread(target=insert_device, args=(i,)) for i in range(20)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
            
        # All writes should succeed
        assert len(errors) == 0
        
        # Verify all records were inserted
        with manager.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT COUNT(*) as count FROM devices")
            count = cursor.fetchone()['count']
            assert count == 20
            
    def test_concurrent_read_write(self, db_with_schema):
        """Test concurrent reads and writes."""
        manager = DatabaseManager(db_with_schema)
        results = []
        
        def writer():
            for i in range(5):
                manager.execute_with_retry(
                    "INSERT INTO devices (mac_address) VALUES (?)",
                    (f'AA:BB:CC:DD:{i:02X}:FF',)
                )
                time.sleep(0.01)
                
        def reader():
            for _ in range(10):
                with manager.get_connection() as conn:
                    cursor = conn.cursor()
                    cursor.execute("SELECT COUNT(*) as count FROM devices")
                    count = cursor.fetchone()['count']
                    results.append(count)
                time.sleep(0.01)
                
        # Start writer and multiple readers
        writer_thread = Thread(target=writer)
        reader_threads = [Thread(target=reader) for _ in range(3)]
        
        writer_thread.start()
        for t in reader_threads:
            t.start()
            
        writer_thread.join()
        for t in reader_threads:
            t.join()
            
        # Should have captured various counts as writes progressed
        assert len(results) == 30
        assert max(results) >= 5  # Final count should be at least 5


if __name__ == '__main__':
    pytest.main([__file__, '-v'])

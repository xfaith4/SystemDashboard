"""Tests for performance monitoring module."""

import pytest
import sqlite3
import tempfile
import os
import sys
import time
import importlib.util

# Add the app directory to the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

if importlib.util.find_spec("psutil") is None:
    pytest.skip("psutil not installed", allow_module_level=True)

from app.performance_monitor import (
    QueryPerformanceTracker,
    QueryPlanAnalyzer,
    ResourceMonitor,
    get_query_tracker,
    get_resource_monitor,
    track_query_performance
)


class TestQueryPerformanceTracker:
    """Test QueryPerformanceTracker class."""
    
    def test_initialization(self):
        """Test tracker initialization."""
        tracker = QueryPerformanceTracker(slow_query_threshold_ms=200)
        assert tracker.slow_query_threshold_ms == 200
        assert tracker.enabled is True
        assert len(tracker.query_stats) == 0
    
    def test_enable_disable(self):
        """Test enabling and disabling tracker."""
        tracker = QueryPerformanceTracker()
        assert tracker.enabled is True
        
        tracker.disable()
        assert tracker.enabled is False
        
        tracker.enable()
        assert tracker.enabled is True
    
    def test_track_query_basic(self):
        """Test basic query tracking."""
        tracker = QueryPerformanceTracker(slow_query_threshold_ms=1000)
        
        query = "SELECT * FROM devices"
        with tracker.track_query(query) as timing:
            time.sleep(0.01)  # 10ms
        
        assert timing['duration_ms'] > 0
        assert timing['slow_query'] is False
        
        stats = tracker.get_statistics()
        assert query in stats
        assert stats[query]['count'] == 1
        assert stats[query]['avg_ms'] > 0
    
    def test_track_slow_query(self):
        """Test slow query detection."""
        tracker = QueryPerformanceTracker(slow_query_threshold_ms=5)
        
        query = "SELECT * FROM large_table"
        with tracker.track_query(query) as timing:
            time.sleep(0.01)  # 10ms, should exceed 5ms threshold
        
        assert timing['slow_query'] is True
    
    def test_track_multiple_queries(self):
        """Test tracking multiple queries."""
        tracker = QueryPerformanceTracker()
        
        queries = [
            "SELECT * FROM devices",
            "SELECT * FROM snapshots",
            "SELECT * FROM devices"  # Duplicate
        ]
        
        for query in queries:
            with tracker.track_query(query):
                pass
        
        stats = tracker.get_statistics()
        assert len(stats) == 2  # Two unique queries
        assert stats["SELECT * FROM devices"]['count'] == 2
        assert stats["SELECT * FROM snapshots"]['count'] == 1
    
    def test_statistics_calculation(self):
        """Test statistics calculation."""
        tracker = QueryPerformanceTracker()
        
        query = "SELECT * FROM test"
        
        # Execute same query multiple times with different durations
        for _ in range(3):
            with tracker.track_query(query):
                time.sleep(0.01)
        
        stats = tracker.get_statistics()
        assert stats[query]['count'] == 3
        assert stats[query]['avg_ms'] > 0
        assert stats[query]['max_ms'] >= stats[query]['avg_ms']
        assert stats[query]['min_ms'] <= stats[query]['avg_ms']
    
    def test_get_slow_queries(self):
        """Test getting slowest queries."""
        tracker = QueryPerformanceTracker(slow_query_threshold_ms=1000)
        
        # Create queries with different speeds
        queries = [
            ("SELECT 1", 0.001),
            ("SELECT * FROM large_table", 0.03),
            ("SELECT COUNT(*) FROM huge_table", 0.02)
        ]
        
        for query, sleep_time in queries:
            with tracker.track_query(query):
                time.sleep(sleep_time)
        
        slow_queries = tracker.get_slow_queries(limit=2)
        assert len(slow_queries) <= 2
        assert 'query' in slow_queries[0]
        assert 'avg_ms' in slow_queries[0]
        
        # Check ordering (slowest first)
        if len(slow_queries) == 2:
            assert slow_queries[0]['avg_ms'] >= slow_queries[1]['avg_ms']
    
    def test_reset_statistics(self):
        """Test resetting statistics."""
        tracker = QueryPerformanceTracker()
        
        with tracker.track_query("SELECT * FROM test"):
            pass
        
        assert len(tracker.get_statistics()) == 1
        
        tracker.reset_statistics()
        assert len(tracker.get_statistics()) == 0
    
    def test_track_query_with_params(self):
        """Test tracking query with parameters."""
        tracker = QueryPerformanceTracker()
        
        query = "SELECT * FROM devices WHERE mac = ?"
        params = ("AA:BB:CC:DD:EE:FF",)
        
        with tracker.track_query(query, params) as timing:
            pass
        
        assert timing['duration_ms'] >= 0
    
    def test_disabled_tracker(self):
        """Test that disabled tracker doesn't record stats."""
        tracker = QueryPerformanceTracker()
        tracker.disable()
        
        with tracker.track_query("SELECT * FROM test"):
            pass
        
        stats = tracker.get_statistics()
        assert len(stats) == 0


class TestQueryPlanAnalyzer:
    """Test QueryPlanAnalyzer class."""
    
    @pytest.fixture
    def test_db(self):
        """Create a temporary test database."""
        fd, path = tempfile.mkstemp(suffix='.db')
        os.close(fd)
        
        conn = sqlite3.connect(path)
        conn.execute("""
            CREATE TABLE test_table (
                id INTEGER PRIMARY KEY,
                name TEXT,
                value INTEGER
            )
        """)
        conn.execute("CREATE INDEX idx_value ON test_table(value)")
        conn.commit()
        
        yield conn
        
        conn.close()
        os.unlink(path)
    
    def test_explain_query_simple(self, test_db):
        """Test explaining a simple query."""
        analyzer = QueryPlanAnalyzer(test_db)
        
        plan = analyzer.explain_query("SELECT * FROM test_table")
        
        assert isinstance(plan, list)
        assert len(plan) > 0
        assert 'detail' in plan[0]
    
    def test_explain_query_with_index(self, test_db):
        """Test explaining a query that uses an index."""
        analyzer = QueryPlanAnalyzer(test_db)
        
        plan = analyzer.explain_query("SELECT * FROM test_table WHERE value = ?", (42,))
        
        assert isinstance(plan, list)
        assert len(plan) > 0
        
        # Should mention the index in the plan
        plan_text = ' '.join([step['detail'] for step in plan])
        assert 'idx_value' in plan_text or 'SEARCH' in plan_text.upper()
    
    def test_explain_query_invalid(self, test_db):
        """Test explaining an invalid query."""
        analyzer = QueryPlanAnalyzer(test_db)
        
        # Invalid SQL should return empty list
        plan = analyzer.explain_query("SELECT * FROM nonexistent_table")
        assert plan == []
    
    def test_analyze_and_log(self, test_db, caplog):
        """Test analyze_and_log method."""
        analyzer = QueryPlanAnalyzer(test_db)
        
        with caplog.at_level('INFO'):
            plan = analyzer.analyze_and_log("SELECT * FROM test_table")
        
        assert isinstance(plan, list)
        # Check that something was logged
        assert len(caplog.records) > 0


class TestResourceMonitor:
    """Test ResourceMonitor class."""
    
    @pytest.fixture
    def test_db_path(self):
        """Create a temporary database file."""
        fd, path = tempfile.mkstemp(suffix='.db')
        os.close(fd)
        
        # Create a small database file
        conn = sqlite3.connect(path)
        conn.execute("CREATE TABLE test (id INTEGER)")
        conn.commit()
        conn.close()
        
        yield path
        
        if os.path.exists(path):
            os.unlink(path)
    
    @pytest.fixture
    def test_log_path(self):
        """Create a temporary log directory."""
        import tempfile
        log_dir = tempfile.mkdtemp()
        
        # Create a small log file
        log_file = os.path.join(log_dir, 'test.log')
        with open(log_file, 'w') as f:
            f.write("test log content\n")
        
        yield log_dir
        
        # Cleanup
        import shutil
        if os.path.exists(log_dir):
            shutil.rmtree(log_dir)
    
    def test_initialization(self, test_db_path, test_log_path):
        """Test resource monitor initialization."""
        monitor = ResourceMonitor(test_db_path, test_log_path)
        assert monitor.db_path == test_db_path
        assert monitor.log_path == test_log_path
        assert monitor.disk_space_warning_threshold_pct == 85
        assert monitor.disk_space_critical_threshold_pct == 95
    
    def test_get_memory_usage(self, test_db_path, test_log_path):
        """Test memory usage reporting."""
        monitor = ResourceMonitor(test_db_path, test_log_path)
        memory = monitor.get_memory_usage()
        
        assert isinstance(memory, dict)
        # Should have memory info or error
        if 'error' not in memory:
            assert 'rss_mb' in memory
            assert 'vms_mb' in memory
            assert 'percent' in memory
            assert memory['rss_mb'] > 0
    
    def test_get_disk_usage(self, test_db_path, test_log_path):
        """Test disk usage reporting."""
        monitor = ResourceMonitor(test_db_path, test_log_path)
        disk = monitor.get_disk_usage()
        
        assert isinstance(disk, dict)
        
        if 'database' in disk and 'error' not in disk['database']:
            assert 'size_mb' in disk['database']
            assert disk['database']['size_mb'] >= 0
            assert 'partition_total_gb' in disk['database']
            assert 'status' in disk['database']
        
        if 'logs' in disk and 'error' not in disk['logs']:
            assert 'total_mb' in disk['logs']
            assert disk['logs']['total_mb'] >= 0
    
    def test_get_status(self, test_db_path, test_log_path):
        """Test comprehensive status reporting."""
        monitor = ResourceMonitor(test_db_path, test_log_path)
        status = monitor.get_status()
        
        assert isinstance(status, dict)
        assert 'memory' in status
        assert 'disk' in status


class TestGlobalFunctions:
    """Test module-level functions."""
    
    def test_get_query_tracker(self):
        """Test global query tracker getter."""
        tracker1 = get_query_tracker()
        tracker2 = get_query_tracker()
        
        # Should return same instance
        assert tracker1 is tracker2
    
    def test_get_resource_monitor(self):
        """Test global resource monitor getter."""
        monitor1 = get_resource_monitor('./var/test.db')
        monitor2 = get_resource_monitor('./var/test.db')
        
        # Should return same instance
        assert monitor1 is monitor2
    
    def test_track_query_performance_decorator(self):
        """Test query performance tracking decorator."""
        tracker = get_query_tracker()
        tracker.reset_statistics()
        
        @track_query_performance
        def sample_query():
            time.sleep(0.01)
            return "result"
        
        result = sample_query()
        assert result == "result"
        
        stats = tracker.get_statistics()
        # Should have recorded the function call
        assert len(stats) > 0

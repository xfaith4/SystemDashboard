"""
Performance monitoring module for tracking slow queries and resource usage.

This module provides:
- Slow query logging for queries exceeding configurable thresholds
- Query plan analysis with EXPLAIN QUERY PLAN
- Performance metrics collection and reporting
- Memory and disk space monitoring
"""

import sqlite3
import time
import logging
import os
import psutil
import threading
from contextlib import contextmanager
from typing import Optional, Dict, Any, List, Callable
from functools import wraps

logger = logging.getLogger(__name__)


class QueryPerformanceTracker:
    """Track and log slow queries for performance analysis."""
    
    def __init__(self, slow_query_threshold_ms: int = 100):
        """
        Initialize query performance tracker.
        
        Args:
            slow_query_threshold_ms: Threshold in milliseconds for slow query logging
        """
        self.slow_query_threshold_ms = slow_query_threshold_ms
        self.query_stats: Dict[str, Dict[str, Any]] = {}
        self.lock = threading.Lock()
        self.enabled = True
        
    def disable(self):
        """Disable query tracking (useful for testing)."""
        self.enabled = False
        
    def enable(self):
        """Enable query tracking."""
        self.enabled = True
        
    @contextmanager
    def track_query(self, query: str, params: Optional[tuple] = None):
        """
        Context manager to track query execution time.
        
        Args:
            query: SQL query string
            params: Query parameters
            
        Yields:
            Dict with timing information
            
        Example:
            with tracker.track_query("SELECT * FROM devices") as timing:
                cursor.execute(query)
        """
        if not self.enabled:
            yield {'duration_ms': 0}
            return
            
        start_time = time.perf_counter()
        timing_info = {'duration_ms': 0, 'slow_query': False}
        
        try:
            yield timing_info
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000
            timing_info['duration_ms'] = duration_ms
            
            # Normalize query for statistics (remove extra whitespace)
            normalized_query = ' '.join(query.split())
            
            # Update statistics
            with self.lock:
                if normalized_query not in self.query_stats:
                    self.query_stats[normalized_query] = {
                        'count': 0,
                        'total_ms': 0,
                        'max_ms': 0,
                        'min_ms': float('inf')
                    }
                
                stats = self.query_stats[normalized_query]
                stats['count'] += 1
                stats['total_ms'] += duration_ms
                stats['max_ms'] = max(stats['max_ms'], duration_ms)
                stats['min_ms'] = min(stats['min_ms'], duration_ms)
            
            # Log slow queries
            if duration_ms > self.slow_query_threshold_ms:
                timing_info['slow_query'] = True
                param_str = str(params)[:100] if params else 'None'
                logger.warning(
                    f"Slow query ({duration_ms:.2f}ms > {self.slow_query_threshold_ms}ms): "
                    f"{normalized_query[:200]} | params: {param_str}"
                )
    
    def get_statistics(self) -> Dict[str, Dict[str, Any]]:
        """
        Get query statistics.
        
        Returns:
            Dict mapping queries to their statistics
        """
        with self.lock:
            # Calculate averages
            result = {}
            for query, stats in self.query_stats.items():
                result[query] = {
                    'count': stats['count'],
                    'total_ms': round(stats['total_ms'], 2),
                    'avg_ms': round(stats['total_ms'] / stats['count'], 2),
                    'max_ms': round(stats['max_ms'], 2),
                    'min_ms': round(stats['min_ms'], 2) if stats['min_ms'] != float('inf') else 0
                }
            return result
    
    def get_slow_queries(self, limit: int = 10) -> List[Dict[str, Any]]:
        """
        Get the slowest queries by average execution time.
        
        Args:
            limit: Maximum number of queries to return
            
        Returns:
            List of query statistics sorted by average time (descending)
        """
        stats = self.get_statistics()
        sorted_queries = sorted(
            [(query, data) for query, data in stats.items()],
            key=lambda x: x[1]['avg_ms'],
            reverse=True
        )
        return [
            {'query': query[:200], **data}
            for query, data in sorted_queries[:limit]
        ]
    
    def reset_statistics(self):
        """Reset all query statistics."""
        with self.lock:
            self.query_stats.clear()


class QueryPlanAnalyzer:
    """Analyze query execution plans for optimization opportunities."""
    
    def __init__(self, connection: sqlite3.Connection):
        """
        Initialize query plan analyzer.
        
        Args:
            connection: SQLite database connection
        """
        self.connection = connection
    
    def explain_query(self, query: str, params: Optional[tuple] = None) -> List[Dict[str, Any]]:
        """
        Get the query execution plan.
        
        Args:
            query: SQL query to analyze
            params: Query parameters
            
        Returns:
            List of query plan steps
            
        Example:
            plan = analyzer.explain_query("SELECT * FROM devices WHERE mac = ?", ("AA:BB:CC:DD:EE:FF",))
        """
        explain_query = f"EXPLAIN QUERY PLAN {query}"
        cursor = self.connection.cursor()
        
        try:
            if params:
                cursor.execute(explain_query, params)
            else:
                cursor.execute(explain_query)
            
            results = cursor.fetchall()
            return [
                {
                    'id': row[0] if len(row) > 0 else None,
                    'parent': row[1] if len(row) > 1 else None,
                    'detail': row[3] if len(row) > 3 else str(row)
                }
                for row in results
            ]
        except sqlite3.Error as e:
            logger.error(f"Error analyzing query plan: {e}")
            return []
        finally:
            cursor.close()
    
    def analyze_and_log(self, query: str, params: Optional[tuple] = None):
        """
        Analyze query plan and log the results.
        
        Args:
            query: SQL query to analyze
            params: Query parameters
        """
        plan = self.explain_query(query, params)
        
        logger.info(f"Query plan for: {query[:100]}")
        for step in plan:
            logger.info(f"  - {step['detail']}")
        
        # Check for common issues
        issues = []
        for step in plan:
            detail = step['detail'].lower()
            if 'scan' in detail and 'index' not in detail:
                issues.append("⚠️  Full table scan detected - consider adding an index")
            if 'temp b-tree' in detail:
                issues.append("⚠️  Temporary B-tree created - query may benefit from index")
        
        if issues:
            logger.warning("Query optimization opportunities:")
            for issue in issues:
                logger.warning(f"  {issue}")
        
        return plan


class ResourceMonitor:
    """Monitor system resource usage (memory, disk space)."""
    
    def __init__(self, db_path: str, log_path: str = './var/log'):
        """
        Initialize resource monitor.
        
        Args:
            db_path: Path to SQLite database
            log_path: Path to log directory
        """
        self.db_path = db_path
        self.log_path = log_path
        self.disk_space_warning_threshold_pct = 85
        self.disk_space_critical_threshold_pct = 95
        
    def get_memory_usage(self) -> Dict[str, Any]:
        """
        Get current process memory usage.
        
        Returns:
            Dict with memory usage statistics in MB
        """
        try:
            process = psutil.Process()
            memory_info = process.memory_info()
            
            return {
                'rss_mb': round(memory_info.rss / 1024 / 1024, 2),
                'vms_mb': round(memory_info.vms / 1024 / 1024, 2),
                'percent': round(process.memory_percent(), 2)
            }
        except (ImportError, AttributeError):
            return {'error': 'psutil not available'}
    
    def get_disk_usage(self) -> Dict[str, Any]:
        """
        Get disk space usage for database and log directories.
        
        Returns:
            Dict with disk usage statistics
        """
        result = {}
        
        # Check database directory
        if os.path.exists(self.db_path):
            db_dir = os.path.dirname(self.db_path) or '.'
            try:
                usage = psutil.disk_usage(db_dir)
                db_size = os.path.getsize(self.db_path) / 1024 / 1024  # MB
                
                result['database'] = {
                    'size_mb': round(db_size, 2),
                    'partition_total_gb': round(usage.total / 1024 / 1024 / 1024, 2),
                    'partition_used_gb': round(usage.used / 1024 / 1024 / 1024, 2),
                    'partition_free_gb': round(usage.free / 1024 / 1024 / 1024, 2),
                    'partition_percent': usage.percent
                }
                
                # Check thresholds
                if usage.percent >= self.disk_space_critical_threshold_pct:
                    result['database']['status'] = 'critical'
                    logger.error(
                        f"Database partition critically low on space: "
                        f"{usage.percent}% used (threshold: {self.disk_space_critical_threshold_pct}%)"
                    )
                elif usage.percent >= self.disk_space_warning_threshold_pct:
                    result['database']['status'] = 'warning'
                    logger.warning(
                        f"Database partition low on space: "
                        f"{usage.percent}% used (threshold: {self.disk_space_warning_threshold_pct}%)"
                    )
                else:
                    result['database']['status'] = 'ok'
                    
            except (OSError, FileNotFoundError) as e:
                result['database'] = {'error': str(e)}
        
        # Check log directory
        if os.path.exists(self.log_path):
            try:
                usage = psutil.disk_usage(self.log_path)
                
                # Calculate total log size
                total_log_size = 0
                for root, dirs, files in os.walk(self.log_path):
                    for file in files:
                        file_path = os.path.join(root, file)
                        try:
                            total_log_size += os.path.getsize(file_path)
                        except OSError:
                            pass
                
                result['logs'] = {
                    'total_mb': round(total_log_size / 1024 / 1024, 2),
                    'partition_percent': usage.percent
                }
            except (OSError, FileNotFoundError) as e:
                result['logs'] = {'error': str(e)}
        
        return result
    
    def get_status(self) -> Dict[str, Any]:
        """
        Get comprehensive resource status.
        
        Returns:
            Dict with memory and disk usage
        """
        return {
            'memory': self.get_memory_usage(),
            'disk': self.get_disk_usage()
        }


# Global instances
_query_tracker: Optional[QueryPerformanceTracker] = None
_resource_monitor: Optional[ResourceMonitor] = None


def get_query_tracker(slow_query_threshold_ms: int = 100) -> QueryPerformanceTracker:
    """
    Get or create the global query performance tracker.
    
    Args:
        slow_query_threshold_ms: Threshold for slow query logging
        
    Returns:
        QueryPerformanceTracker instance
    """
    global _query_tracker
    if _query_tracker is None:
        _query_tracker = QueryPerformanceTracker(slow_query_threshold_ms)
    return _query_tracker


def get_resource_monitor(db_path: str, log_path: str = './var/log') -> ResourceMonitor:
    """
    Get or create the global resource monitor.
    
    Args:
        db_path: Path to SQLite database
        log_path: Path to log directory
        
    Returns:
        ResourceMonitor instance
    """
    global _resource_monitor
    if _resource_monitor is None:
        _resource_monitor = ResourceMonitor(db_path, log_path)
    return _resource_monitor


def track_query_performance(func: Callable) -> Callable:
    """
    Decorator to track query performance for database operations.
    
    Usage:
        @track_query_performance
        def get_devices(conn):
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM devices")
            return cursor.fetchall()
    """
    @wraps(func)
    def wrapper(*args, **kwargs):
        tracker = get_query_tracker()
        
        # Simple function-level tracking
        query_name = f"{func.__module__}.{func.__name__}"
        with tracker.track_query(query_name):
            return func(*args, **kwargs)
    
    return wrapper

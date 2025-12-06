"""
Database connection manager with connection pooling, retry logic, and schema validation.

This module provides enhanced database management features for SQLite:
- Connection pooling to prevent "database is locked" errors
- Retry logic with exponential backoff for transient failures
- Schema validation at startup
- Query timeouts to prevent hanging queries
"""

import sqlite3
import os
import time
import logging
from contextlib import contextmanager
from threading import Lock
from typing import Optional, List, Dict, Any

logger = logging.getLogger(__name__)


class ConnectionPool:
    """Simple connection pool for SQLite with thread-safe access."""
    
    def __init__(self, db_path: str, max_connections: int = 5, timeout: int = 10):
        """
        Initialize connection pool.
        
        Args:
            db_path: Path to SQLite database file
            max_connections: Maximum number of connections in pool
            timeout: Timeout in seconds for database operations
        """
        self.db_path = db_path
        self.max_connections = max_connections
        self.timeout = timeout
        self.connections: List[sqlite3.Connection] = []
        self.in_use: set = set()
        self.lock = Lock()
        
    def _create_connection(self) -> sqlite3.Connection:
        """Create a new database connection with proper settings."""
        # Ensure directory exists
        db_dir = os.path.dirname(self.db_path)
        if db_dir and not os.path.exists(db_dir):
            os.makedirs(db_dir, exist_ok=True)
            
        conn = sqlite3.connect(
            self.db_path,
            timeout=self.timeout,
            check_same_thread=False,  # Allow connection reuse across threads
            isolation_level=None  # Autocommit mode for better concurrency
        )
        conn.row_factory = sqlite3.Row  # Enable dict-like access
        
        # Enable WAL mode for better concurrent access
        conn.execute('PRAGMA journal_mode=WAL')
        # Set busy timeout
        conn.execute(f'PRAGMA busy_timeout={self.timeout * 1000}')
        # Enable foreign keys
        conn.execute('PRAGMA foreign_keys=ON')
        
        return conn
    
    @contextmanager
    def get_connection(self):
        """
        Get a connection from the pool as a context manager.
        
        Usage:
            with pool.get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT ...")
        """
        conn = None
        try:
            with self.lock:
                # Try to get an available connection
                if self.connections:
                    conn = self.connections.pop()
                elif len(self.in_use) < self.max_connections:
                    conn = self._create_connection()
                    
            # If no connection available, create a temporary one
            if conn is None:
                logger.debug("All connections in use, creating temporary connection")
                conn = self._create_connection()
                temp_conn = True
            else:
                temp_conn = False
                with self.lock:
                    self.in_use.add(id(conn))
                    
            yield conn
            
        finally:
            if conn:
                try:
                    # Rollback any uncommitted transaction
                    if conn.in_transaction:
                        conn.rollback()
                except Exception as e:
                    logger.warning(f"Error during connection cleanup: {e}")
                    
                if temp_conn:
                    # Close temporary connection
                    conn.close()
                else:
                    # Return to pool
                    with self.lock:
                        self.in_use.discard(id(conn))
                        if len(self.connections) < self.max_connections:
                            self.connections.append(conn)
                        else:
                            conn.close()
    
    def close_all(self):
        """Close all connections in the pool."""
        with self.lock:
            for conn in self.connections:
                try:
                    conn.close()
                except Exception as e:
                    logger.warning(f"Error closing connection: {e}")
            self.connections.clear()
            self.in_use.clear()


class DatabaseManager:
    """Database manager with retry logic and schema validation."""
    
    # Required tables for schema validation
    REQUIRED_TABLES = [
        'devices',
        'device_snapshots',
        'device_alerts',
        'ai_feedback',
        'syslog_recent'
    ]
    
    # Required views for schema validation
    REQUIRED_VIEWS = [
        'lan_summary_stats',
        'device_alerts_active'
    ]
    
    def __init__(self, db_path: str, max_retries: int = 3):
        """
        Initialize database manager.
        
        Args:
            db_path: Path to SQLite database file
            max_retries: Maximum number of retry attempts for transient failures
        """
        self.db_path = db_path
        self.max_retries = max_retries
        self.pool = ConnectionPool(db_path)
        self._validated = False
        
    def execute_with_retry(self, query: str, params: tuple = None, max_retries: Optional[int] = None) -> Any:
        """
        Execute a query with exponential backoff retry logic.
        
        Args:
            query: SQL query to execute
            params: Query parameters
            max_retries: Maximum retry attempts (uses instance default if None)
            
        Returns:
            Query result
            
        Raises:
            sqlite3.Error: If query fails after all retries
        """
        if max_retries is None:
            max_retries = self.max_retries
            
        last_error = None
        for attempt in range(max_retries + 1):
            try:
                with self.pool.get_connection() as conn:
                    cursor = conn.cursor()
                    if params:
                        cursor.execute(query, params)
                    else:
                        cursor.execute(query)
                    
                    # Commit if it's a write operation
                    if query.strip().upper().startswith(('INSERT', 'UPDATE', 'DELETE')):
                        conn.commit()
                    
                    return cursor
                    
            except sqlite3.OperationalError as e:
                last_error = e
                if 'locked' in str(e).lower() and attempt < max_retries:
                    # Exponential backoff: 0.1s, 0.2s, 0.4s, etc.
                    wait_time = 0.1 * (2 ** attempt)
                    logger.warning(f"Database locked, retrying in {wait_time}s (attempt {attempt + 1}/{max_retries})")
                    time.sleep(wait_time)
                else:
                    raise
            except Exception as e:
                logger.error(f"Database query failed: {e}")
                raise
                
        # If we get here, all retries failed
        raise last_error
        
    def validate_schema(self) -> tuple[bool, List[str]]:
        """
        Validate that all required tables and views exist.
        
        Returns:
            Tuple of (is_valid, missing_objects)
        """
        if self._validated:
            return True, []
            
        missing = []
        
        try:
            with self.pool.get_connection() as conn:
                cursor = conn.cursor()
                
                # Check tables
                cursor.execute(
                    "SELECT name FROM sqlite_master WHERE type='table'"
                )
                existing_tables = {row['name'] for row in cursor.fetchall()}
                
                for table in self.REQUIRED_TABLES:
                    if table not in existing_tables:
                        missing.append(f"table:{table}")
                        
                # Check views
                cursor.execute(
                    "SELECT name FROM sqlite_master WHERE type='view'"
                )
                existing_views = {row['name'] for row in cursor.fetchall()}
                
                for view in self.REQUIRED_VIEWS:
                    if view not in existing_views:
                        missing.append(f"view:{view}")
                        
        except Exception as e:
            logger.error(f"Schema validation failed: {e}")
            return False, [f"error: {str(e)}"]
            
        if not missing:
            self._validated = True
            logger.info("Database schema validation passed")
            return True, []
        else:
            logger.warning(f"Database schema validation failed. Missing: {', '.join(missing)}")
            return False, missing
            
    def get_connection(self):
        """Get a connection from the pool (context manager)."""
        return self.pool.get_connection()
        
    def close(self):
        """Close all connections."""
        self.pool.close_all()


# Global database manager instance
_db_manager: Optional[DatabaseManager] = None
_db_manager_lock = Lock()


def get_db_manager(db_path: str) -> DatabaseManager:
    """
    Get or create the global database manager instance.
    
    Args:
        db_path: Path to SQLite database file
        
    Returns:
        DatabaseManager instance
    """
    global _db_manager
    
    with _db_manager_lock:
        if _db_manager is None or _db_manager.db_path != db_path:
            if _db_manager:
                _db_manager.close()
            _db_manager = DatabaseManager(db_path)
            
    return _db_manager

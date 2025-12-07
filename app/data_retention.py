"""
Data retention module for automatic cleanup of old records.

This module provides utilities for enforcing data retention policies
by automatically cleaning up old snapshots, alerts, and logs.
"""

import sqlite3
import logging
from datetime import datetime, timedelta, timezone
from typing import Dict, Any, Optional
from contextlib import contextmanager

logger = logging.getLogger(__name__)


class DataRetentionManager:
    """Manage data retention policies for SQLite database."""
    
    def __init__(self, connection: sqlite3.Connection):
        """
        Initialize data retention manager.
        
        Args:
            connection: SQLite database connection
        """
        self.connection = connection
        
    def cleanup_old_snapshots(self, retention_days: int = 7) -> int:
        """
        Delete device snapshots older than the retention period.
        
        Args:
            retention_days: Number of days to retain snapshots
            
        Returns:
            Number of snapshots deleted
            
        Example:
            manager = DataRetentionManager(conn)
            deleted = manager.cleanup_old_snapshots(retention_days=7)
            print(f"Deleted {deleted} old snapshots")
        """
        if retention_days < 1:
            raise ValueError("retention_days must be at least 1")
            
        try:
            cursor = self.connection.cursor()
            cutoff_date = datetime.now(timezone.utc) - timedelta(days=retention_days)
            cutoff_str = cutoff_date.strftime('%Y-%m-%d %H:%M:%S')
            
            # Delete old snapshots
            cursor.execute(
                "DELETE FROM device_snapshots WHERE timestamp < ?",
                (cutoff_str,)
            )
            
            deleted_count = cursor.rowcount
            self.connection.commit()
            
            if deleted_count > 0:
                logger.info(
                    f"Data retention: Deleted {deleted_count} device snapshot(s) "
                    f"older than {retention_days} days (cutoff: {cutoff_str})"
                )
            else:
                logger.debug(
                    f"Data retention: No device snapshots older than {retention_days} days"
                )
            
            return deleted_count
            
        except sqlite3.Error as e:
            logger.error(f"Failed to cleanup old snapshots: {e}")
            self.connection.rollback()
            raise
    
    def cleanup_old_alerts(self, retention_days: int = 30) -> int:
        """
        Delete resolved alerts older than the retention period.
        
        Args:
            retention_days: Number of days to retain resolved alerts
            
        Returns:
            Number of alerts deleted
            
        Example:
            deleted = manager.cleanup_old_alerts(retention_days=30)
        """
        if retention_days < 1:
            raise ValueError("retention_days must be at least 1")
            
        try:
            cursor = self.connection.cursor()
            cutoff_date = datetime.now(timezone.utc) - timedelta(days=retention_days)
            cutoff_str = cutoff_date.strftime('%Y-%m-%d %H:%M:%S')
            
            # Delete old resolved alerts (keep unresolved ones)
            cursor.execute(
                """
                DELETE FROM device_alerts 
                WHERE resolved = 1 
                  AND resolved_at < ?
                """,
                (cutoff_str,)
            )
            
            deleted_count = cursor.rowcount
            self.connection.commit()
            
            if deleted_count > 0:
                logger.info(
                    f"Data retention: Deleted {deleted_count} resolved alert(s) "
                    f"older than {retention_days} days"
                )
            
            return deleted_count
            
        except sqlite3.Error as e:
            logger.error(f"Failed to cleanup old alerts: {e}")
            self.connection.rollback()
            raise
    
    def cleanup_old_syslog(self, retention_days: int = 14) -> int:
        """
        Delete syslog entries older than the retention period.
        
        Args:
            retention_days: Number of days to retain syslog entries
            
        Returns:
            Number of syslog entries deleted
            
        Example:
            deleted = manager.cleanup_old_syslog(retention_days=14)
        """
        if retention_days < 1:
            raise ValueError("retention_days must be at least 1")
            
        try:
            cursor = self.connection.cursor()
            cutoff_date = datetime.now(timezone.utc) - timedelta(days=retention_days)
            cutoff_str = cutoff_date.strftime('%Y-%m-%d %H:%M:%S')
            
            # Delete old syslog entries
            cursor.execute(
                "DELETE FROM syslog_recent WHERE timestamp < ?",
                (cutoff_str,)
            )
            
            deleted_count = cursor.rowcount
            self.connection.commit()
            
            if deleted_count > 0:
                logger.info(
                    f"Data retention: Deleted {deleted_count} syslog entrie(s) "
                    f"older than {retention_days} days"
                )
            
            return deleted_count
            
        except sqlite3.Error as e:
            logger.error(f"Failed to cleanup old syslog entries: {e}")
            self.connection.rollback()
            raise
    
    def vacuum_database(self) -> None:
        """
        Vacuum the database to reclaim space from deleted rows.
        
        Note: This can be a slow operation on large databases.
        Should be run periodically (e.g., weekly) after cleanup operations.
        
        Example:
            manager.cleanup_old_snapshots(7)
            manager.vacuum_database()  # Reclaim space
        """
        try:
            logger.info("Starting database VACUUM operation")
            self.connection.execute("VACUUM")
            logger.info("Database VACUUM completed successfully")
        except sqlite3.Error as e:
            logger.error(f"Failed to vacuum database: {e}")
            raise
    
    def get_table_sizes(self) -> Dict[str, int]:
        """
        Get row counts for all retention-managed tables.
        
        Returns:
            Dict mapping table names to row counts
            
        Example:
            sizes = manager.get_table_sizes()
            print(f"device_snapshots: {sizes['device_snapshots']} rows")
        """
        tables = ['device_snapshots', 'device_alerts', 'syslog_recent']
        sizes = {}
        
        try:
            cursor = self.connection.cursor()
            
            for table in tables:
                try:
                    cursor.execute(f"SELECT COUNT(*) FROM {table}")
                    count = cursor.fetchone()[0]
                    sizes[table] = count
                except sqlite3.Error:
                    # Table might not exist
                    sizes[table] = 0
            
            return sizes
            
        except sqlite3.Error as e:
            logger.error(f"Failed to get table sizes: {e}")
            return {}
    
    def run_full_cleanup(
        self,
        snapshot_retention_days: int = 7,
        alert_retention_days: int = 30,
        syslog_retention_days: int = 14,
        vacuum: bool = False
    ) -> Dict[str, Any]:
        """
        Run full data retention cleanup across all tables.
        
        Args:
            snapshot_retention_days: Days to retain device snapshots
            alert_retention_days: Days to retain resolved alerts
            syslog_retention_days: Days to retain syslog entries
            vacuum: Whether to vacuum database after cleanup
            
        Returns:
            Dict with cleanup results
            
        Example:
            results = manager.run_full_cleanup(
                snapshot_retention_days=7,
                alert_retention_days=30,
                syslog_retention_days=14,
                vacuum=True
            )
            print(f"Total deleted: {sum(results['deleted'].values())}")
        """
        results = {
            'deleted': {},
            'errors': [],
            'vacuum_performed': False
        }
        
        # Cleanup snapshots
        try:
            deleted = self.cleanup_old_snapshots(snapshot_retention_days)
            results['deleted']['device_snapshots'] = deleted
        except Exception as e:
            results['errors'].append(f"device_snapshots: {str(e)}")
        
        # Cleanup alerts
        try:
            deleted = self.cleanup_old_alerts(alert_retention_days)
            results['deleted']['device_alerts'] = deleted
        except Exception as e:
            results['errors'].append(f"device_alerts: {str(e)}")
        
        # Cleanup syslog
        try:
            deleted = self.cleanup_old_syslog(syslog_retention_days)
            results['deleted']['syslog_recent'] = deleted
        except Exception as e:
            results['errors'].append(f"syslog_recent: {str(e)}")
        
        # Vacuum if requested and any deletions occurred
        if vacuum and sum(results['deleted'].values()) > 0:
            try:
                self.vacuum_database()
                results['vacuum_performed'] = True
            except Exception as e:
                results['errors'].append(f"vacuum: {str(e)}")
        
        return results


@contextmanager
def get_retention_manager(connection: sqlite3.Connection):
    """
    Context manager to get a data retention manager.
    
    Args:
        connection: SQLite database connection
        
    Yields:
        DataRetentionManager instance
        
    Example:
        with get_retention_manager(conn) as manager:
            manager.cleanup_old_snapshots(7)
    """
    manager = DataRetentionManager(connection)
    try:
        yield manager
    finally:
        pass  # No cleanup needed, connection is managed by caller

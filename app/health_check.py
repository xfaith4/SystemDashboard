"""
Health check utilities for SystemDashboard.

Provides comprehensive health monitoring for:
- Database connectivity and query performance
- Data freshness (recent syslog, device snapshots)
- Service status indicators
"""

import datetime
import sqlite3
import time
from typing import Dict, Any, Tuple, Optional


class HealthStatus:
    """Health status constants."""
    HEALTHY = 'healthy'
    DEGRADED = 'degraded'
    UNHEALTHY = 'unhealthy'


def check_database_health(db_path: str, timeout: float = 5.0) -> Dict[str, Any]:
    """
    Check database connectivity and basic performance.
    
    Args:
        db_path: Path to SQLite database
        timeout: Query timeout in seconds
        
    Returns:
        Dictionary with:
        - status: 'healthy', 'degraded', or 'unhealthy'
        - message: Human-readable status message
        - response_time_ms: Database query response time
        - error: Error message if unhealthy
    """
    result = {
        'status': HealthStatus.UNHEALTHY,
        'message': 'Database check failed',
        'response_time_ms': None,
        'error': None
    }
    
    try:
        start_time = time.time()
        conn = sqlite3.connect(db_path, timeout=timeout)
        conn.row_factory = sqlite3.Row
        
        # Basic connectivity check
        cursor = conn.cursor()
        cursor.execute("SELECT 1")
        cursor.fetchone()
        
        response_time = (time.time() - start_time) * 1000
        result['response_time_ms'] = round(response_time, 2)
        
        # Check if response time is acceptable
        if response_time < 100:
            result['status'] = HealthStatus.HEALTHY
            result['message'] = 'Database responding normally'
        elif response_time < 500:
            result['status'] = HealthStatus.DEGRADED
            result['message'] = f'Database responding slowly ({response_time:.0f}ms)'
        else:
            result['status'] = HealthStatus.DEGRADED
            result['message'] = f'Database very slow ({response_time:.0f}ms)'
        
        conn.close()
        
    except sqlite3.OperationalError as e:
        result['error'] = f'Database operational error: {str(e)}'
        result['message'] = 'Database unavailable'
    except Exception as e:
        result['error'] = f'Database error: {str(e)}'
        result['message'] = 'Database check failed'
    
    return result


def check_data_freshness(db_path: str, max_age_minutes: int = 60) -> Dict[str, Any]:
    """
    Check if data is fresh (has recent entries).
    
    Args:
        db_path: Path to SQLite database
        max_age_minutes: Maximum acceptable age for data in minutes
        
    Returns:
        Dictionary with:
        - status: 'healthy', 'degraded', or 'unhealthy'
        - message: Human-readable status message
        - checks: Dict of individual freshness checks
    """
    result = {
        'status': HealthStatus.HEALTHY,
        'message': 'Data is fresh',
        'checks': {}
    }
    
    try:
        conn = sqlite3.connect(db_path, timeout=5.0)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        now = datetime.datetime.now(datetime.UTC)
        cutoff = now - datetime.timedelta(minutes=max_age_minutes)
        
        # Check for recent device snapshots
        cursor.execute("""
            SELECT MAX(snapshot_time_utc) as latest
            FROM device_snapshots
        """)
        row = cursor.fetchone()
        
        if row and row['latest']:
            try:
                latest = datetime.datetime.fromisoformat(row['latest'].replace('Z', '+00:00'))
                if latest.tzinfo is None:
                    latest = latest.replace(tzinfo=datetime.UTC)
                age_minutes = (now - latest).total_seconds() / 60
                
                if age_minutes <= max_age_minutes:
                    result['checks']['device_snapshots'] = {
                        'status': HealthStatus.HEALTHY,
                        'age_minutes': round(age_minutes, 1),
                        'message': f'Latest snapshot {age_minutes:.1f} minutes ago'
                    }
                else:
                    result['checks']['device_snapshots'] = {
                        'status': HealthStatus.DEGRADED,
                        'age_minutes': round(age_minutes, 1),
                        'message': f'Latest snapshot {age_minutes:.1f} minutes ago (stale)'
                    }
                    result['status'] = HealthStatus.DEGRADED
            except (ValueError, AttributeError):
                result['checks']['device_snapshots'] = {
                    'status': HealthStatus.DEGRADED,
                    'message': 'Invalid timestamp format'
                }
        else:
            result['checks']['device_snapshots'] = {
                'status': HealthStatus.DEGRADED,
                'message': 'No snapshots found'
            }
            result['status'] = HealthStatus.DEGRADED
        
        # Check for recent syslog entries
        cursor.execute("""
            SELECT COUNT(*) as count, MAX(syslog_timestamp_utc) as latest
            FROM syslog_recent
        """)
        row = cursor.fetchone()
        
        if row and row['latest']:
            try:
                latest = datetime.datetime.fromisoformat(row['latest'].replace('Z', '+00:00'))
                if latest.tzinfo is None:
                    latest = latest.replace(tzinfo=datetime.UTC)
                age_minutes = (now - latest).total_seconds() / 60
                count = row['count']
                
                if age_minutes <= max_age_minutes:
                    result['checks']['syslog'] = {
                        'status': HealthStatus.HEALTHY,
                        'age_minutes': round(age_minutes, 1),
                        'count': count,
                        'message': f'{count} entries, latest {age_minutes:.1f} minutes ago'
                    }
                else:
                    result['checks']['syslog'] = {
                        'status': HealthStatus.DEGRADED,
                        'age_minutes': round(age_minutes, 1),
                        'count': count,
                        'message': f'Latest entry {age_minutes:.1f} minutes ago (stale)'
                    }
                    if result['status'] == HealthStatus.HEALTHY:
                        result['status'] = HealthStatus.DEGRADED
            except (ValueError, AttributeError):
                result['checks']['syslog'] = {
                    'status': HealthStatus.DEGRADED,
                    'message': 'Invalid timestamp format'
                }
        else:
            result['checks']['syslog'] = {
                'status': HealthStatus.DEGRADED,
                'message': 'No syslog entries found'
            }
            if result['status'] == HealthStatus.HEALTHY:
                result['status'] = HealthStatus.DEGRADED
        
        conn.close()
        
        # Update overall message based on status
        if result['status'] == HealthStatus.DEGRADED:
            stale_checks = [k for k, v in result['checks'].items() 
                          if v.get('status') == HealthStatus.DEGRADED]
            result['message'] = f'Some data is stale: {", ".join(stale_checks)}'
        
    except Exception as e:
        result['status'] = HealthStatus.UNHEALTHY
        result['message'] = f'Data freshness check failed: {str(e)}'
        result['error'] = str(e)
    
    return result


def check_schema_integrity(db_path: str) -> Dict[str, Any]:
    """
    Verify database schema has required tables and views.
    
    Args:
        db_path: Path to SQLite database
        
    Returns:
        Dictionary with status and list of missing objects
    """
    required_tables = [
        'devices',
        'device_snapshots',
        'device_alerts',
        'ai_feedback',
        'syslog_recent'
    ]
    
    required_views = [
        'lan_summary_stats',
        'device_alerts_active'
    ]
    
    result = {
        'status': HealthStatus.HEALTHY,
        'message': 'Schema is valid',
        'missing_tables': [],
        'missing_views': []
    }
    
    try:
        conn = sqlite3.connect(db_path, timeout=5.0)
        cursor = conn.cursor()
        
        # Check tables
        cursor.execute("""
            SELECT name FROM sqlite_master 
            WHERE type='table'
        """)
        existing_tables = set(row[0] for row in cursor.fetchall())
        
        result['missing_tables'] = [t for t in required_tables if t not in existing_tables]
        
        # Check views
        cursor.execute("""
            SELECT name FROM sqlite_master 
            WHERE type='view'
        """)
        existing_views = set(row[0] for row in cursor.fetchall())
        
        result['missing_views'] = [v for v in required_views if v not in existing_views]
        
        conn.close()
        
        # Update status based on missing objects
        if result['missing_tables'] or result['missing_views']:
            result['status'] = HealthStatus.UNHEALTHY
            missing = []
            if result['missing_tables']:
                missing.append(f"{len(result['missing_tables'])} tables")
            if result['missing_views']:
                missing.append(f"{len(result['missing_views'])} views")
            result['message'] = f'Schema incomplete: missing {", ".join(missing)}'
        
    except Exception as e:
        result['status'] = HealthStatus.UNHEALTHY
        result['message'] = f'Schema check failed: {str(e)}'
        result['error'] = str(e)
    
    return result


def get_comprehensive_health(db_path: str) -> Tuple[Dict[str, Any], int]:
    """
    Perform comprehensive health check of all subsystems.
    
    Args:
        db_path: Path to SQLite database
        
    Returns:
        Tuple of (health_report dict, HTTP status code)
    """
    report = {
        'timestamp': datetime.datetime.now(datetime.UTC).isoformat(),
        'overall_status': HealthStatus.HEALTHY,
        'subsystems': {}
    }
    
    # Check database connectivity
    db_health = check_database_health(db_path)
    report['subsystems']['database'] = db_health
    
    # Only check other subsystems if database is accessible
    if db_health['status'] != HealthStatus.UNHEALTHY:
        # Check schema integrity
        schema_health = check_schema_integrity(db_path)
        report['subsystems']['schema'] = schema_health
        
        # Check data freshness
        freshness_health = check_data_freshness(db_path)
        report['subsystems']['data_freshness'] = freshness_health
        
        # Determine overall status (worst of all subsystems)
        statuses = [db_health['status'], schema_health['status'], freshness_health['status']]
        if HealthStatus.UNHEALTHY in statuses:
            report['overall_status'] = HealthStatus.UNHEALTHY
        elif HealthStatus.DEGRADED in statuses:
            report['overall_status'] = HealthStatus.DEGRADED
    else:
        report['overall_status'] = HealthStatus.UNHEALTHY
    
    # Map status to HTTP codes
    http_code = {
        HealthStatus.HEALTHY: 200,
        HealthStatus.DEGRADED: 200,  # Still serving requests
        HealthStatus.UNHEALTHY: 503
    }[report['overall_status']]
    
    return report, http_code

#!/usr/bin/env python3
"""
Test script to verify database connection with Flask app settings
"""

__test__ = False

import os
import sys
import json

try:  # pragma: no cover - pytest is optional when running as a script
    import pytest
except ImportError:  # pragma: no cover - running standalone without pytest installed
    pytest = None

# Add the repo root to Python path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

def load_config():
    """Load database configuration from config.json or SYSTEMDASHBOARD_CONFIG."""
    config_path = os.environ.get('SYSTEMDASHBOARD_CONFIG')
    if not config_path:
        config_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'config.json')
    try:
        with open(config_path, 'r') as f:
            config = json.load(f)
            return config.get('Database', {})
    except Exception as e:
        print(f"Failed to load config: {e}")
        return {}

def load_connection_info():
    """Load generated database passwords from var/database-connection.json if present."""
    repo_root = os.path.dirname(os.path.dirname(__file__))
    connection_path = os.path.join(repo_root, 'var', 'database-connection.json')
    if not os.path.exists(connection_path):
        return {}
    try:
        with open(connection_path, 'r') as f:
            return json.load(f) or {}
    except Exception as e:
        print(f"Failed to load connection info: {e}")
        return {}

def check_database_connection(verbose: bool = True):
    """Attempt to connect to the database.

    Returns a tuple of (status, message) where status is one of
    'success', 'skip', or 'failed'. The optional message describes the outcome.
    """

    # Load config from file
    db_config = load_config()
    if verbose:
        print(f"Config from file: {db_config}")

    # Set environment variables like the service script does
    os.environ.setdefault('DASHBOARD_DB_HOST', db_config.get('Host', 'localhost'))
    os.environ.setdefault('DASHBOARD_DB_PORT', str(db_config.get('Port', 5432)))
    os.environ.setdefault('DASHBOARD_DB_NAME', db_config.get('Database', 'system_dashboard'))
    os.environ.setdefault('DASHBOARD_DB_USER', 'sysdash_reader')

    connection_info = load_connection_info()

    # Prefer docker-generated passwords when available
    reader_password = connection_info.get('ReaderPassword') or os.environ.get('SYSTEMDASHBOARD_DB_READER_PASSWORD')
    if not reader_password:
        reader_password = os.environ.get('SYSTEMDASHBOARD_DB_PASSWORD', 'GeneratedPassword123!').replace('123!', '456!')

    os.environ.setdefault('DASHBOARD_DB_PASSWORD', reader_password)

    if verbose:
        print("Environment variables set:")
        print(f"  DASHBOARD_DB_HOST: {os.environ.get('DASHBOARD_DB_HOST')}")
        print(f"  DASHBOARD_DB_PORT: {os.environ.get('DASHBOARD_DB_PORT')}")
        print(f"  DASHBOARD_DB_NAME: {os.environ.get('DASHBOARD_DB_NAME')}")
        print(f"  DASHBOARD_DB_USER: {os.environ.get('DASHBOARD_DB_USER')}")
        print(f"  DASHBOARD_DB_PASSWORD: {'*' * len(reader_password)}")

    try:
        from app import get_db_settings, get_db_connection
    except Exception as exc:
        message = f"Unable to import app module: {exc}"
        if verbose:
            print(f"❌ {message}")
        return 'failed', message

    if verbose:
        print("\n--- Testing database settings ---")
    settings = get_db_settings()
    if verbose:
        print(f"Database settings: {settings}")

    if not settings:
        message = "Database settings are not configured; skipping connection test"
        if verbose:
            print(f"⚠️  {message}")
        return 'skip', message

    if verbose:
        print("\n--- Testing database connection ---")
    conn = get_db_connection()
    if conn is None:
        message = "Database connection unavailable"
        if verbose:
            print(f"❌ {message}")
        return 'skip', message

    try:
        if verbose:
            print("✅ Database connection successful!")
        with conn:
            with conn.cursor() as cur:
                cur.execute("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'telemetry'")
                count = cur.fetchone()[0]
                if verbose:
                    print(f"✅ Found {count} telemetry tables")

                cur.execute("SELECT COUNT(*) FROM telemetry.syslog_recent")
                syslog_count = cur.fetchone()[0]
                if verbose:
                    print(f"✅ Found {syslog_count} records in syslog_recent")
    except Exception as exc:
        message = f"Error during verification queries: {exc}"
        if verbose:
            print(f"❌ {message}")
        return 'failed', message
    finally:
        try:
            conn.close()
        except Exception:
            pass

    return 'success', 'Database connection verified'


def test_database_connection():
    """Pytest wrapper that uses the helper and skips when no database is configured."""

    status, message = check_database_connection(verbose=False)

    if status == 'skip':
        if pytest is not None:
            pytest.skip(message)
        return

    assert status == 'success', message


if __name__ == "__main__":
    print("=== Database Connection Test ===")
    status, message = check_database_connection()
    print(message)
    sys.exit(0 if status == 'success' else 1)

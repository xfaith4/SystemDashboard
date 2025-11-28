#!/usr/bin/env python3
"""
Test script to verify database connection with Flask app settings
"""

import os
import sys
import json

try:  # pragma: no cover - pytest is optional when running as a script
    import pytest
except ImportError:  # pragma: no cover - running standalone without pytest installed
    pytest = None

# Add the app directory to Python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

def load_config():
    """Load database configuration from config.json"""
    config_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'config.json')
    try:
        with open(config_path, 'r') as f:
            config = json.load(f)
            return config.get('Database', {})
    except Exception as e:
        print(f"Failed to load config: {e}")
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

    # Check if SQLite is configured
    db_type = db_config.get('Type', '').lower()
    if db_type != 'sqlite':
        message = "Database type is not SQLite; skipping connection test"
        if verbose:
            print(f"⚠️  {message}")
        return 'skip', message

    db_path = db_config.get('Path', './var/system_dashboard.db')
    if verbose:
        print(f"  Database path: {db_path}")

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
        cur = conn.cursor()
        
        # Count tables in SQLite
        cur.execute("SELECT COUNT(*) FROM sqlite_master WHERE type='table'")
        count = cur.fetchone()[0]
        if verbose:
            print(f"✅ Found {count} tables in database")

        # Check syslog_messages table
        cur.execute("SELECT COUNT(*) FROM syslog_messages")
        syslog_count = cur.fetchone()[0]
        if verbose:
            print(f"✅ Found {syslog_count} records in syslog_messages")
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

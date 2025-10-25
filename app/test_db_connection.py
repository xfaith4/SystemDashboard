#!/usr/bin/env python3
"""
Test script to verify database connection with Flask app settings
"""

import os
import sys
import json

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

def test_database_connection():
    """Test database connection using Flask app logic"""

    # Load config from file
    db_config = load_config()
    print(f"Config from file: {db_config}")

    # Set environment variables like the service script does
    os.environ['DASHBOARD_DB_HOST'] = db_config.get('Host', 'localhost')
    os.environ['DASHBOARD_DB_PORT'] = str(db_config.get('Port', 5432))
    os.environ['DASHBOARD_DB_NAME'] = db_config.get('Database', 'system_dashboard')
    os.environ['DASHBOARD_DB_USER'] = 'sysdash_reader'

    # Try to get the reader password
    reader_password = os.environ.get('SYSTEMDASHBOARD_DB_READER_PASSWORD')
    if not reader_password:
        reader_password = os.environ.get('SYSTEMDASHBOARD_DB_PASSWORD', 'GeneratedPassword123!').replace('123!', '456!')

    os.environ['DASHBOARD_DB_PASSWORD'] = reader_password

    print("Environment variables set:")
    print(f"  DASHBOARD_DB_HOST: {os.environ.get('DASHBOARD_DB_HOST')}")
    print(f"  DASHBOARD_DB_PORT: {os.environ.get('DASHBOARD_DB_PORT')}")
    print(f"  DASHBOARD_DB_NAME: {os.environ.get('DASHBOARD_DB_NAME')}")
    print(f"  DASHBOARD_DB_USER: {os.environ.get('DASHBOARD_DB_USER')}")
    print(f"  DASHBOARD_DB_PASSWORD: {'*' * len(reader_password)}")

    # Import Flask app modules
    try:
        from app import get_db_settings, get_db_connection

        print("\n--- Testing database settings ---")
        settings = get_db_settings()
        print(f"Database settings: {settings}")

        if not settings:
            print("❌ Database settings are None - check environment variables")
            return False

        print("\n--- Testing database connection ---")
        conn = get_db_connection()

        if conn:
            print("✅ Database connection successful!")

            # Test a simple query
            with conn.cursor() as cur:
                cur.execute("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'telemetry'")
                count = cur.fetchone()[0]
                print(f"✅ Found {count} telemetry tables")

                # Test telemetry tables
                cur.execute("SELECT COUNT(*) FROM telemetry.syslog_recent")
                syslog_count = cur.fetchone()[0]
                print(f"✅ Found {syslog_count} records in syslog_recent")

            conn.close()
            return True
        else:
            print("❌ Database connection failed")
            return False

    except Exception as e:
        print(f"❌ Error testing connection: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    print("=== Database Connection Test ===")
    success = test_database_connection()
    sys.exit(0 if success else 1)

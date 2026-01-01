#!/usr/bin/env python3
"""
Flask App Wrapper - Sets database environment variables explicitly
"""

import os
import sys
import json
from pathlib import Path


def load_config(repo_root: Path) -> dict:
    config_path = repo_root / 'config.json'
    if not config_path.exists():
        return {}
    try:
        with config_path.open('r', encoding='utf-8') as f:
            return json.load(f) or {}
    except Exception:
        return {}


def load_connection_info(repo_root: Path) -> dict:
    connection_path = repo_root / 'var' / 'database-connection.json'
    if not connection_path.exists():
        return {}
    try:
        with connection_path.open('r', encoding='utf-8') as f:
            return json.load(f) or {}
    except Exception:
        return {}


def ensure_postgres_env(repo_root: Path) -> None:
    cfg = load_config(repo_root)
    db = (cfg or {}).get('Database') or {}

    os.environ.setdefault('DASHBOARD_DB_HOST', str(db.get('Host') or 'localhost'))
    os.environ.setdefault('DASHBOARD_DB_PORT', str(db.get('Port') or 5432))
    os.environ.setdefault('DASHBOARD_DB_NAME', str(db.get('Database') or 'system_dashboard'))
    os.environ.setdefault('DASHBOARD_DB_USER', 'sysdash_reader')

    connection_info = load_connection_info(repo_root)
    password = (
        os.environ.get('SYSTEMDASHBOARD_DB_READER_PASSWORD')
        or connection_info.get('ReaderPassword')
        or os.environ.get('DASHBOARD_DB_PASSWORD')
    )
    if password:
        os.environ['DASHBOARD_DB_PASSWORD'] = password

    os.environ.setdefault('FLASK_ENV', 'production')

# Import and run the Flask app
if __name__ == '__main__':
    # Change to the app directory
    app_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(app_dir)
    repo_root = Path(app_dir).parent
    ensure_postgres_env(repo_root)

    # Import the Flask app
    from app import app

    # Test database connection before starting
    from app import get_db_connection

    try:
        print("Testing database connection...")
        conn = get_db_connection()
        if conn:
            print("Database connection successful")
            conn.close()
        else:
            print("Database connection failed")
    except Exception as e:
        print(f"Database test error: {e}")

    # Start the Flask app
    port = int(os.environ.get('DASHBOARD_PORT', '5000'))
    app.run(debug=True, host='0.0.0.0', port=port)

#!/usr/bin/env python3
"""
Flask App Wrapper - Sets database environment variables explicitly
"""

import os
import sys
import subprocess
from pathlib import Path

# Set database environment variables explicitly (SQLite uses file path)
os.environ.setdefault('FLASK_ENV', 'production')
os.environ.setdefault('DASHBOARD_LOG_LEVEL', 'INFO')

def _ensure_ssl_context():
    """Ensure an HTTPS context is available.

    Uses DASHBOARD_CERT_FILE/DASHBOARD_KEY_FILE if provided; otherwise defaults to var/ssl/self-signed.
    Attempts to generate a self-signed cert with openssl if missing; falls back to 'adhoc' if generation fails.
    """
    cert_path = Path(os.environ.get('DASHBOARD_CERT_FILE', '../var/ssl/dashboard.crt')).resolve()
    key_path = Path(os.environ.get('DASHBOARD_KEY_FILE', '../var/ssl/dashboard.key')).resolve()

    try:
        cert_path.parent.mkdir(parents=True, exist_ok=True)
        if cert_path.exists() and key_path.exists():
            return (str(cert_path), str(key_path))

        # Generate a self-signed cert (valid 365 days) if missing
        cmd = [
            os.environ.get('OPENSSL_PATH', 'openssl'),
            'req', '-x509', '-nodes', '-newkey', 'rsa:2048',
            '-days', '365',
            '-subj', '/CN=localhost',
            '-keyout', str(key_path),
            '-out', str(cert_path)
        ]
        subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return (str(cert_path), str(key_path))
    except Exception as exc:
        print(f"SSL cert generation failed; falling back to adhoc TLS. Error: {exc}")
        return 'adhoc'

# Import and run the Flask app
if __name__ == '__main__':
    # Change to the app directory
    app_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(app_dir)

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
    port = int(os.environ.get('DASHBOARD_PORT', '5443'))
    ssl_context = _ensure_ssl_context()
    app.run(debug=False, host='0.0.0.0', port=port, ssl_context=ssl_context)

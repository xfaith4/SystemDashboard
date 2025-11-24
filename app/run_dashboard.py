#!/usr/bin/env python3
"""
Flask App Wrapper - Sets database environment variables explicitly
"""

import os
import sys

# Set database environment variables explicitly
os.environ['DASHBOARD_DB_HOST'] = 'localhost'
os.environ['DASHBOARD_DB_PORT'] = '5432'
os.environ['DASHBOARD_DB_NAME'] = 'system_dashboard'
os.environ['DASHBOARD_DB_USER'] = 'sysdash_reader'
os.environ['DASHBOARD_DB_PASSWORD'] = 'ReaderPassword456!'
os.environ['FLASK_ENV'] = 'production'

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
    port = int(os.environ.get('DASHBOARD_PORT', '5001'))
    app.run(debug=True, host='0.0.0.0', port=port)

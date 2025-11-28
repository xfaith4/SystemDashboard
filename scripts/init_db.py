#!/usr/bin/env python3
"""
Initialize the SQLite database for System Dashboard.

This script creates the database file and schema if they don't exist.
Run this script to set up a fresh database or verify an existing one.
"""

import os
import sys
import sqlite3
import argparse

def get_script_dir():
    return os.path.dirname(os.path.abspath(__file__))

def get_project_root():
    return os.path.dirname(get_script_dir())

def get_default_db_path():
    return os.path.join(get_project_root(), 'var', 'system_dashboard.db')

def get_schema_path():
    return os.path.join(get_project_root(), 'tools', 'schema-sqlite.sql')

def init_database(db_path: str, force: bool = False):
    """Initialize the SQLite database with the schema."""
    
    # Ensure var directory exists
    db_dir = os.path.dirname(db_path)
    if db_dir and not os.path.exists(db_dir):
        os.makedirs(db_dir, exist_ok=True)
        print(f"Created directory: {db_dir}")
    
    # Check if database already exists
    db_exists = os.path.exists(db_path)
    if db_exists and not force:
        print(f"Database already exists at: {db_path}")
        print("Use --force to recreate the database (WARNING: this will delete all data)")
        return False
    
    if db_exists and force:
        os.remove(db_path)
        print(f"Removed existing database: {db_path}")
    
    # Read schema file
    schema_path = get_schema_path()
    if not os.path.exists(schema_path):
        print(f"Schema file not found: {schema_path}")
        return False
    
    with open(schema_path, 'r') as f:
        schema_sql = f.read()
    
    # Create database and apply schema
    try:
        conn = sqlite3.connect(db_path)
        conn.executescript(schema_sql)
        conn.commit()
        conn.close()
        print(f"Successfully created database: {db_path}")
        print("Schema applied successfully.")
        return True
    except Exception as e:
        print(f"Error creating database: {e}")
        return False

def verify_database(db_path: str):
    """Verify the database schema."""
    if not os.path.exists(db_path):
        print(f"Database not found: {db_path}")
        return False
    
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Check for expected tables
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
        tables = [row[0] for row in cursor.fetchall()]
        
        expected_tables = [
            'syslog_messages',
            'eventlog_windows',
            'iis_requests',
            'devices',
            'device_snapshots',
            'device_events',
            'device_alerts',
            'ai_feedback',
            'lan_settings',
            'syslog_device_links'
        ]
        
        print(f"Database: {db_path}")
        print(f"Tables found: {len(tables)}")
        
        missing = [t for t in expected_tables if t not in tables]
        if missing:
            print(f"Missing tables: {missing}")
            return False
        
        print("All expected tables present.")
        
        # Show row counts
        print("\nTable row counts:")
        for table in expected_tables:
            cursor.execute(f"SELECT COUNT(*) FROM {table}")
            count = cursor.fetchone()[0]
            print(f"  {table}: {count} rows")
        
        conn.close()
        return True
    except Exception as e:
        print(f"Error verifying database: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(description='Initialize or verify the System Dashboard SQLite database')
    parser.add_argument('--db-path', '-d', default=get_default_db_path(),
                       help='Path to the SQLite database file')
    parser.add_argument('--force', '-f', action='store_true',
                       help='Force recreation of the database (WARNING: deletes all data)')
    parser.add_argument('--verify', '-v', action='store_true',
                       help='Verify existing database instead of initializing')
    
    args = parser.parse_args()
    
    if args.verify:
        success = verify_database(args.db_path)
    else:
        success = init_database(args.db_path, args.force)
    
    sys.exit(0 if success else 1)

if __name__ == '__main__':
    main()

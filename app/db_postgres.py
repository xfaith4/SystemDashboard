"""
PostgreSQL connection helpers shared across Flask API and UI.
"""

import os
import logging

try:
    import psycopg2  # type: ignore
except Exception:  # pragma: no cover - optional dependency during local dev
    psycopg2 = None


def get_db_settings():
    if psycopg2 is None:
        return None
    dsn = os.environ.get('DASHBOARD_DB_DSN')
    if dsn:
        return {'dsn': dsn}
    host = os.environ.get('DASHBOARD_DB_HOST')
    user = os.environ.get('DASHBOARD_DB_USER')
    password = os.environ.get('DASHBOARD_DB_PASSWORD')
    dbname = os.environ.get('DASHBOARD_DB_NAME') or os.environ.get('DASHBOARD_DB_DATABASE')
    if not all([host, user, password, dbname]):
        return None
    settings = {
        'host': host,
        'port': int(os.environ.get('DASHBOARD_DB_PORT', '5432')),
        'dbname': dbname,
        'user': user,
        'password': password,
    }
    sslmode = os.environ.get('DASHBOARD_DB_SSLMODE')
    if sslmode:
        settings['sslmode'] = sslmode
    return settings


def get_db_connection():
    settings = get_db_settings()
    if not settings:
        return None
    try:
        if 'dsn' in settings:
            return psycopg2.connect(settings['dsn'])
        params = dict(settings)
        password = params.pop('password', None)
        if password is None:
            return None
        if 'connect_timeout' not in params:
            params['connect_timeout'] = 3
        return psycopg2.connect(password=password, **params)
    except Exception as exc:  # pragma: no cover - depends on runtime
        logger.warning('Failed to connect to PostgreSQL: %s', exc)
        return None
logger = logging.getLogger(__name__)

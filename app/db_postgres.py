"""
PostgreSQL connection helpers shared across Flask API and UI.
"""

import json
import logging
import os

try:
    import psycopg2  # type: ignore
except Exception:  # pragma: no cover - optional dependency during local dev
    psycopg2 = None


def _load_config():
    config_path = os.environ.get('SYSTEMDASHBOARD_CONFIG')
    if not config_path:
        config_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'config.json')
    if not os.path.exists(config_path):
        return {}
    try:
        with open(config_path, 'r', encoding='utf-8') as handle:
            return json.load(handle)
    except Exception:
        return {}


def _resolve_secret(value):
    if not value:
        return None
    if isinstance(value, str) and value.startswith('env:'):
        return os.environ.get(value[4:])
    return value


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
        config = _load_config()
        db_config = (config or {}).get('Database', {}) if isinstance(config, dict) else {}
        host = host or db_config.get('Host') or 'localhost'
        user = user or db_config.get('Username')
        dbname = dbname or db_config.get('Database') or db_config.get('Name')
        password = password or _resolve_secret(db_config.get('PasswordSecret')) or db_config.get('Password')
        port = db_config.get('Port')
        sslmode = db_config.get('SslMode') or db_config.get('SSLMode')
    else:
        port = None
        sslmode = None

    if not all([host, user, password, dbname]):
        return None

    settings = {
        'host': host,
        'port': int(os.environ.get('DASHBOARD_DB_PORT', port or 5432)),
        'dbname': dbname,
        'user': user,
        'password': password,
    }
    sslmode = os.environ.get('DASHBOARD_DB_SSLMODE') or sslmode
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

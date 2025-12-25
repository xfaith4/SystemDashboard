"""Versioned API routes for SystemDashboard."""

import json
from datetime import datetime, timezone

from flask import request

from ...api_utils import (
    error_response,
    handle_api_errors,
    require_json,
    success_response,
    validate_required_fields,
)
from ...action_engine import execute_action, get_action_definition
from ...db_postgres import get_db_connection


DEFAULT_LIMIT = 100
MAX_LIMIT = 1000


def _parse_limit(value):
    try:
        limit = int(value)
    except (TypeError, ValueError):
        return DEFAULT_LIMIT
    return max(1, min(limit, MAX_LIMIT))


def _fetch_rows(cursor):
    columns = [desc[0] for desc in cursor.description]
    return [dict(zip(columns, row)) for row in cursor.fetchall()]


def _utc_now():
    return datetime.now(timezone.utc).isoformat()


def register_routes(bp):
    @bp.route('/health', methods=['GET'])
    @handle_api_errors
    def health():
        conn = get_db_connection()
        ok = conn is not None
        if conn:
            conn.close()
        return success_response({'db_connected': ok, 'checked_at': _utc_now()})

    @bp.route('/incidents', methods=['GET'])
    @handle_api_errors
    def list_incidents():
        limit = _parse_limit(request.args.get('limit'))
        conn = get_db_connection()
        if conn is None:
            return error_response('Database not configured', 503)
        try:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT incident_id, title, status, severity, summary,
                           created_at, updated_at, closed_at
                      FROM telemetry.incidents
                     ORDER BY created_at DESC
                     LIMIT %s
                    """,
                    (limit,)
                )
                rows = _fetch_rows(cur)
            return success_response({'items': rows, 'count': len(rows)})
        finally:
            conn.close()

    @bp.route('/events', methods=['GET'])
    @handle_api_errors
    def list_events():
        limit = _parse_limit(request.args.get('limit'))
        conn = get_db_connection()
        if conn is None:
            return error_response('Database not configured', 503)
        try:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT event_id, event_type, source, severity, subject,
                           occurred_at, received_at, tags, correlation_id
                      FROM telemetry.events
                     ORDER BY occurred_at DESC
                     LIMIT %s
                    """,
                    (limit,)
                )
                rows = _fetch_rows(cur)
            return success_response({'items': rows, 'count': len(rows)})
        finally:
            conn.close()

    @bp.route('/actions', methods=['GET'])
    @handle_api_errors
    def list_actions():
        limit = _parse_limit(request.args.get('limit'))
        conn = get_db_connection()
        if conn is None:
            return error_response('Database not configured', 503)
        try:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT action_id, incident_id, action_type, status,
                           requested_by, requested_at, approved_by,
                           approved_at, executed_at, completed_at
                      FROM telemetry.actions
                     ORDER BY requested_at DESC
                     LIMIT %s
                    """,
                    (limit,)
                )
                rows = _fetch_rows(cur)
            return success_response({'items': rows, 'count': len(rows)})
        finally:
            conn.close()

    @bp.route('/actions', methods=['POST'])
    @require_json
    @validate_required_fields(['action_type'])
    @handle_api_errors
    def create_action():
        payload = request.get_json() or {}
        action_type = payload.get('action_type')
        incident_id = payload.get('incident_id')
        requested_by = payload.get('requested_by')
        action_payload = payload.get('payload')

        if not get_action_definition(action_type):
            return error_response(f"Unknown action type: {action_type}", 400)

        conn = get_db_connection()
        if conn is None:
            return error_response('Database not configured', 503)

        try:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO telemetry.actions (
                        incident_id, action_type, status,
                        requested_by, action_payload
                    ) VALUES (%s, %s, %s, %s, %s)
                    RETURNING action_id
                    """,
                    (
                        incident_id,
                        action_type,
                        'requested',
                        requested_by,
                        json.dumps(action_payload) if action_payload is not None else None,
                    )
                )
                action_id = cur.fetchone()[0]
                conn.commit()
            return success_response({'action_id': action_id}, message='Action queued')
        finally:
            conn.close()

    @bp.route('/actions/<int:action_id>/approve', methods=['POST'])
    @handle_api_errors
    def approve_action(action_id: int):
        payload = request.get_json(silent=True) or {}
        approved_by = payload.get('approved_by')

        conn = get_db_connection()
        if conn is None:
            return error_response('Database not configured', 503)

        try:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    UPDATE telemetry.actions
                       SET status = 'approved',
                           approved_by = %s,
                           approved_at = NOW()
                     WHERE action_id = %s
                    """,
                    (approved_by, action_id)
                )
                conn.commit()
            return success_response({'action_id': action_id}, message='Action approved')
        finally:
            conn.close()

    @bp.route('/actions/<int:action_id>/execute', methods=['POST'])
    @handle_api_errors
    def execute_action_endpoint(action_id: int):
        conn = get_db_connection()
        if conn is None:
            return error_response('Database not configured', 503)

        try:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT action_type, status, action_payload
                      FROM telemetry.actions
                     WHERE action_id = %s
                    """,
                    (action_id,)
                )
                row = cur.fetchone()
        finally:
            conn.close()

        if not row:
            return error_response('Action not found', 404)

        action_type, status, action_payload = row
        approved = status == 'approved'
        payload = None
        if action_payload:
            if isinstance(action_payload, (dict, list)):
                payload = action_payload
            else:
                try:
                    payload = json.loads(action_payload)
                except Exception:
                    payload = None

        ok, message = execute_action(action_id, action_type, payload=payload, approved=approved)
        if not ok:
            return error_response(message, 409)
        return success_response({'action_id': action_id}, message='Action executed')

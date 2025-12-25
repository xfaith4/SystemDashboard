"""Action engine for executing remediation steps with audit trail."""

import json
import os
import platform
import subprocess
from typing import Dict, Optional, Tuple

from .db_postgres import get_db_connection


ACTION_DEFINITIONS = {
    'dns_flush': {
        'script': os.path.join('scripting', 'actions', 'dns-flush.ps1'),
        'requires_admin': True,
        'timeout': 60,
        'description': 'Flush DNS cache on the host system.'
    },
    'noop': {
        'script': os.path.join('scripting', 'actions', 'noop.ps1'),
        'requires_admin': False,
        'timeout': 10,
        'description': 'No-op action for testing.'
    }
}


def _repo_root() -> str:
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _config_path() -> str:
    return os.environ.get('SYSTEMDASHBOARD_CONFIG') or os.path.join(_repo_root(), 'config.json')


def load_action_policy() -> Dict:
    policy = {
        'allow_auto_execute': False,
        'require_approval': True,
        'safe_actions': ['dns_flush', 'noop']
    }

    cfg_path = _config_path()
    if not os.path.exists(cfg_path):
        return policy

    try:
        with open(cfg_path, 'r') as f:
            cfg = json.load(f)
        actions_cfg = cfg.get('Actions', {})
        policy['allow_auto_execute'] = bool(actions_cfg.get('AllowAutoExecute', policy['allow_auto_execute']))
        policy['require_approval'] = bool(actions_cfg.get('RequireApproval', policy['require_approval']))
        policy['safe_actions'] = actions_cfg.get('SafeActions', policy['safe_actions'])
    except Exception:
        return policy

    return policy


def get_action_definition(action_type: str) -> Optional[Dict]:
    return ACTION_DEFINITIONS.get(action_type)


def _script_path(action_def: Dict) -> str:
    return os.path.join(_repo_root(), action_def['script'])


def _insert_audit(action_id: int, step: str, status: str, message: str = None, metadata: Dict = None) -> None:
    conn = get_db_connection()
    if conn is None:
        return
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO telemetry.action_audit (action_id, step, status, message, metadata)
                VALUES (%s, %s, %s, %s, %s)
                """,
                (action_id, step, status, message, json.dumps(metadata) if metadata else None)
            )
            conn.commit()
    finally:
        conn.close()


def _update_action_status(action_id: int, status: str, result_payload: Dict = None) -> None:
    conn = get_db_connection()
    if conn is None:
        return
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE telemetry.actions
                   SET status = %s,
                       executed_at = CASE WHEN %s IN ('executing', 'completed', 'failed') THEN NOW() ELSE executed_at END,
                       completed_at = CASE WHEN %s IN ('completed', 'failed') THEN NOW() ELSE completed_at END,
                       result_payload = COALESCE(result_payload, %s)
                 WHERE action_id = %s
                """,
                (status, status, status, json.dumps(result_payload) if result_payload else None, action_id)
            )
            conn.commit()
    finally:
        conn.close()


def can_execute(action_type: str, approved: bool) -> Tuple[bool, str]:
    policy = load_action_policy()
    if action_type not in ACTION_DEFINITIONS:
        return False, f"Unknown action type: {action_type}"

    if policy.get('require_approval', True) and not approved:
        return False, 'Action requires approval'

    if action_type not in policy.get('safe_actions', []) and not policy.get('allow_auto_execute', False):
        return False, 'Action not in safe allowlist'

    return True, 'ok'


def execute_action(action_id: int, action_type: str, payload: Dict = None, approved: bool = False) -> Tuple[bool, str]:
    action_def = get_action_definition(action_type)
    if not action_def:
        return False, f"Unknown action type: {action_type}"

    allowed, reason = can_execute(action_type, approved)
    if not allowed:
        _insert_audit(action_id, 'policy', 'blocked', reason)
        _update_action_status(action_id, 'blocked', {'reason': reason})
        return False, reason

    if platform.system().lower().startswith('win') is False:
        reason = 'Action execution is only supported on Windows'
        _insert_audit(action_id, 'platform', 'blocked', reason)
        _update_action_status(action_id, 'blocked', {'reason': reason})
        return False, reason

    script_path = _script_path(action_def)
    if not os.path.exists(script_path):
        reason = f"Action script not found: {script_path}"
        _insert_audit(action_id, 'script', 'failed', reason)
        _update_action_status(action_id, 'failed', {'reason': reason})
        return False, reason

    _insert_audit(action_id, 'execute', 'started', action_def.get('description'))
    _update_action_status(action_id, 'executing')

    timeout = action_def.get('timeout', 60)
    cmd = [
        'pwsh', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', script_path,
        '-Payload', json.dumps(payload or {})
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        metadata = {
            'exit_code': result.returncode,
            'stdout': result.stdout[-4000:] if result.stdout else '',
            'stderr': result.stderr[-4000:] if result.stderr else ''
        }
        if result.returncode == 0:
            _insert_audit(action_id, 'execute', 'completed', 'Action completed', metadata)
            _update_action_status(action_id, 'completed', {'result': 'success'})
            return True, 'completed'

        _insert_audit(action_id, 'execute', 'failed', 'Action failed', metadata)
        _update_action_status(action_id, 'failed', {'result': 'failed'})
        return False, 'failed'
    except subprocess.TimeoutExpired:
        reason = 'Action timed out'
        _insert_audit(action_id, 'execute', 'failed', reason)
        _update_action_status(action_id, 'failed', {'reason': reason})
        return False, reason


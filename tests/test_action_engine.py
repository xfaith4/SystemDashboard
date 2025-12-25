"""Tests for action engine policy evaluation."""

import json
import os
import tempfile

from app import action_engine


def write_config(data):
    fd, path = tempfile.mkstemp(suffix='.json')
    with os.fdopen(fd, 'w') as f:
        json.dump(data, f)
    return path


def test_can_execute_requires_approval(monkeypatch):
    config_path = write_config({"Actions": {"RequireApproval": True}})
    monkeypatch.setenv('SYSTEMDASHBOARD_CONFIG', config_path)

    allowed, reason = action_engine.can_execute('dns_flush', approved=False)
    assert allowed is False
    assert 'approval' in reason.lower()


def test_can_execute_safe_action_with_approval(monkeypatch):
    config_path = write_config({"Actions": {"RequireApproval": True, "SafeActions": ["dns_flush"]}})
    monkeypatch.setenv('SYSTEMDASHBOARD_CONFIG', config_path)

    allowed, reason = action_engine.can_execute('dns_flush', approved=True)
    assert allowed is True
    assert reason == 'ok'


def test_can_execute_blocks_unknown_action(monkeypatch):
    config_path = write_config({"Actions": {"RequireApproval": False}})
    monkeypatch.setenv('SYSTEMDASHBOARD_CONFIG', config_path)

    allowed, reason = action_engine.can_execute('nope', approved=True)
    assert allowed is False
    assert 'unknown action type' in reason.lower()

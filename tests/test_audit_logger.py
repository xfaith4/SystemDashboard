"""
Tests for audit_logger module.

Tests:
- Sensitive data masking
- Structured logging
- Audit trail
- Log rotation configuration
"""

import pytest
import os
import json
import tempfile
import sys

# Add app directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'app'))

from audit_logger import (
    SensitiveDataMasker, mask_sensitive_data,
    StructuredLogger, get_structured_logger,
    AuditTrail, get_audit_trail,
    get_log_rotation_config
)


# ============================================================================
# Sensitive Data Masking Tests
# ============================================================================

def test_mask_password_in_string():
    """Test masking passwords in strings."""
    masker = SensitiveDataMasker()
    
    text = 'password: secret123'
    result = masker.mask_string(text)
    assert 'secret123' not in result
    assert '********' in result


def test_mask_api_key_in_string():
    """Test masking API keys in strings."""
    masker = SensitiveDataMasker()
    
    text = 'api_key: abc123xyz'
    result = masker.mask_string(text)
    assert 'abc123xyz' not in result
    assert '********' in result


def test_mask_mac_address():
    """Test masking MAC addresses (keeps OUI)."""
    masker = SensitiveDataMasker()
    
    text = 'Device MAC: AA:BB:CC:DD:EE:FF'
    result = masker.mask_string(text)
    assert 'AA:BB' in result  # OUI preserved
    assert 'DD:EE:FF' not in result
    assert '**:**:**' in result


def test_mask_authorization_header():
    """Test masking authorization headers."""
    masker = SensitiveDataMasker()
    
    text = 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
    result = masker.mask_string(text)
    assert 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9' not in result
    assert '********' in result


def test_mask_dict_with_sensitive_keys():
    """Test masking dictionaries with sensitive keys."""
    masker = SensitiveDataMasker()
    
    data = {
        'username': 'admin',
        'password': 'secret123',
        'api_key': 'xyz789',
        'normal_field': 'visible'
    }
    
    result = masker.mask_dict(data)
    
    assert result['username'] == 'admin'
    assert result['password'] == '********'
    assert result['api_key'] == '********'
    assert result['normal_field'] == 'visible'


def test_mask_nested_dict():
    """Test masking nested dictionaries."""
    masker = SensitiveDataMasker()
    
    data = {
        'config': {
            'database': {
                'host': 'localhost',
                'password': 'dbpass123'
            }
        }
    }
    
    result = masker.mask_dict(data)
    
    assert result['config']['database']['host'] == 'localhost'
    assert result['config']['database']['password'] == '********'


def test_mask_list_in_dict():
    """Test masking lists within dictionaries."""
    masker = SensitiveDataMasker()
    
    data = {
        'users': [
            {'name': 'user1', 'password': 'pass1'},
            {'name': 'user2', 'password': 'pass2'}
        ]
    }
    
    result = masker.mask_dict(data)
    
    assert result['users'][0]['name'] == 'user1'
    assert result['users'][0]['password'] == '********'
    assert result['users'][1]['password'] == '********'


def test_mask_sensitive_data_function():
    """Test the convenience mask_sensitive_data function."""
    # String
    result = mask_sensitive_data('password: secret')
    assert 'secret' not in result
    
    # Dict
    result = mask_sensitive_data({'password': 'secret'})
    assert result['password'] == '********'
    
    # Other types pass through
    result = mask_sensitive_data(123)
    assert result == 123


def test_masker_handles_none():
    """Test that masker handles None values gracefully."""
    masker = SensitiveDataMasker()
    
    assert masker.mask_string(None) is None
    assert masker.mask_string('') == ''


# ============================================================================
# Structured Logger Tests
# ============================================================================

def test_structured_logger_formats_json():
    """Test that structured logger produces JSON output."""
    logger = get_structured_logger('test')
    
    # Capture log output
    import logging
    from io import StringIO
    import sys
    
    # Create string stream handler
    log_stream = StringIO()
    handler = logging.StreamHandler(log_stream)
    logger.logger.addHandler(handler)
    logger.logger.setLevel(logging.INFO)
    
    # Log a message
    logger.info('Test message', user='testuser', action='test')
    
    # Get output
    log_output = log_stream.getvalue()
    
    # Parse as JSON
    log_entry = json.loads(log_output.strip())
    
    assert log_entry['level'] == 'INFO'
    assert log_entry['message'] == 'Test message'
    assert log_entry['context']['user'] == 'testuser'
    assert log_entry['context']['action'] == 'test'
    assert 'timestamp' in log_entry


def test_structured_logger_masks_sensitive_data():
    """Test that structured logger masks sensitive data."""
    logger = get_structured_logger('test', mask_sensitive=True)
    
    import logging
    from io import StringIO
    
    log_stream = StringIO()
    handler = logging.StreamHandler(log_stream)
    logger.logger.addHandler(handler)
    logger.logger.setLevel(logging.INFO)
    
    # Log with sensitive data
    logger.info('User login', password='secret123', username='admin')
    
    log_output = log_stream.getvalue()
    log_entry = json.loads(log_output.strip())
    
    assert log_entry['context']['password'] == '********'
    assert log_entry['context']['username'] == 'admin'


def test_structured_logger_levels():
    """Test all log levels."""
    logger = get_structured_logger('test')
    
    import logging
    from io import StringIO
    
    log_stream = StringIO()
    handler = logging.StreamHandler(log_stream)
    logger.logger.addHandler(handler)
    logger.logger.setLevel(logging.DEBUG)
    
    # Test all levels
    logger.debug('Debug message')
    logger.info('Info message')
    logger.warning('Warning message')
    logger.error('Error message')
    logger.critical('Critical message')
    
    log_output = log_stream.getvalue()
    lines = [line for line in log_output.strip().split('\n') if line]
    
    assert len(lines) == 5
    
    # Check each level
    levels = [json.loads(line)['level'] for line in lines]
    assert levels == ['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL']


def test_structured_logger_with_exception():
    """Test logging with exception information."""
    logger = get_structured_logger('test')
    
    import logging
    from io import StringIO
    
    log_stream = StringIO()
    handler = logging.StreamHandler(log_stream)
    logger.logger.addHandler(handler)
    logger.logger.setLevel(logging.ERROR)
    
    # Create exception
    try:
        raise ValueError('Test error')
    except ValueError as e:
        logger.error('An error occurred', exc_info=e)
    
    log_output = log_stream.getvalue()
    log_entry = json.loads(log_output.strip())
    
    assert 'exception' in log_entry
    assert log_entry['exception']['type'] == 'ValueError'
    assert 'Test error' in log_entry['exception']['message']
    assert 'traceback' in log_entry['exception']


# ============================================================================
# Audit Trail Tests
# ============================================================================

def test_audit_trail_device_update():
    """Test logging device updates."""
    with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.log') as f:
        log_file = f.name
    
    try:
        audit = AuditTrail(log_file)
        
        audit.log_device_update(
            device_id='AA:BB:CC:DD:EE:FF',
            changes={'nickname': 'My Device', 'location': 'Office'},
            user='admin',
            ip_address='192.168.1.100'
        )
        
        # Read log file
        with open(log_file, 'r') as f:
            log_content = f.read()
        
        log_entry = json.loads(log_content.strip())
        
        assert log_entry['level'] == 'INFO'
        assert log_entry['context']['action'] == 'device_update'
        assert log_entry['context']['device_id'] == 'AA:BB:CC:DD:EE:FF'
        assert log_entry['context']['changes'] == {'nickname': 'My Device', 'location': 'Office'}
        assert log_entry['context']['user'] == 'admin'
    
    finally:
        if os.path.exists(log_file):
            os.unlink(log_file)


def test_audit_trail_device_delete():
    """Test logging device deletions."""
    with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.log') as f:
        log_file = f.name
    
    try:
        audit = AuditTrail(log_file)
        
        audit.log_device_delete(
            device_id='AA:BB:CC:DD:EE:FF',
            user='admin',
            ip_address='192.168.1.100'
        )
        
        with open(log_file, 'r') as f:
            log_content = f.read()
        
        log_entry = json.loads(log_content.strip())
        
        assert log_entry['context']['action'] == 'device_delete'
        assert log_entry['context']['device_id'] == 'AA:BB:CC:DD:EE:FF'
    
    finally:
        if os.path.exists(log_file):
            os.unlink(log_file)


def test_audit_trail_config_change():
    """Test logging configuration changes."""
    with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.log') as f:
        log_file = f.name
    
    try:
        audit = AuditTrail(log_file)
        
        audit.log_config_change(
            setting='refresh_interval',
            old_value=30,
            new_value=60,
            user='admin'
        )
        
        with open(log_file, 'r') as f:
            log_content = f.read()
        
        log_entry = json.loads(log_content.strip())
        
        assert log_entry['context']['action'] == 'config_change'
        assert log_entry['context']['setting'] == 'refresh_interval'
        assert log_entry['context']['old_value'] == 30
        assert log_entry['context']['new_value'] == 60
    
    finally:
        if os.path.exists(log_file):
            os.unlink(log_file)


def test_audit_trail_login_attempts():
    """Test logging login attempts."""
    with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.log') as f:
        log_file = f.name
    
    try:
        audit = AuditTrail(log_file)
        
        # Successful login
        audit.log_login_attempt(
            success=True,
            user='admin',
            ip_address='192.168.1.100'
        )
        
        # Failed login
        audit.log_login_attempt(
            success=False,
            user='hacker',
            ip_address='1.2.3.4',
            reason='Invalid password'
        )
        
        with open(log_file, 'r') as f:
            log_content = f.read()
        
        lines = [line for line in log_content.strip().split('\n') if line]
        assert len(lines) == 2
        
        # Check successful login
        success_entry = json.loads(lines[0])
        assert success_entry['level'] == 'INFO'
        assert success_entry['context']['success'] is True
        
        # Check failed login
        fail_entry = json.loads(lines[1])
        assert fail_entry['level'] == 'WARNING'
        assert fail_entry['context']['success'] is False
        assert fail_entry['context']['reason'] == 'Invalid password'
    
    finally:
        if os.path.exists(log_file):
            os.unlink(log_file)


def test_audit_trail_api_access():
    """Test logging API access."""
    with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.log') as f:
        log_file = f.name
    
    try:
        audit = AuditTrail(log_file)
        
        # Successful API call
        audit.log_api_access(
            endpoint='/api/devices',
            method='GET',
            status_code=200,
            duration_ms=45.2
        )
        
        # Failed API call
        audit.log_api_access(
            endpoint='/api/protected',
            method='POST',
            status_code=403,
            user='guest',
            ip_address='1.2.3.4'
        )
        
        with open(log_file, 'r') as f:
            log_content = f.read()
        
        lines = [line for line in log_content.strip().split('\n') if line]
        assert len(lines) == 2
        
        # Check successful call
        success_entry = json.loads(lines[0])
        assert success_entry['level'] == 'INFO'
        assert success_entry['context']['status_code'] == 200
        assert success_entry['context']['duration_ms'] == 45.2
        
        # Check failed call (should be WARNING)
        fail_entry = json.loads(lines[1])
        assert fail_entry['level'] == 'WARNING'
        assert fail_entry['context']['status_code'] == 403
    
    finally:
        if os.path.exists(log_file):
            os.unlink(log_file)


def test_get_audit_trail_singleton():
    """Test that get_audit_trail returns singleton instance."""
    audit1 = get_audit_trail()
    audit2 = get_audit_trail()
    
    assert audit1 is audit2


# ============================================================================
# Log Rotation Tests
# ============================================================================

def test_get_log_rotation_config():
    """Test log rotation configuration."""
    config = get_log_rotation_config()
    
    assert 'maxBytes' in config
    assert 'backupCount' in config
    assert config['maxBytes'] > 0
    assert config['backupCount'] > 0


if __name__ == '__main__':
    pytest.main([__file__, '-v'])

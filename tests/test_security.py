"""
Tests for security module (security.py).

Tests:
- Security headers
- API key authentication
- CSRF protection
- Input sanitization
"""

import pytest
import os
import tempfile
from flask import Flask, jsonify, request, make_response
import sys

# Add app directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from app.security import (
    add_security_headers, configure_security_headers,
    APIKeyAuth, get_api_key_auth, require_api_key,
    CSRFProtection, get_csrf_protection, csrf_protect,
    sanitize_path, validate_sql_identifier
)


# ============================================================================
# Security Headers Tests
# ============================================================================

def test_add_security_headers():
    """Test that security headers are added correctly."""
    app = Flask(__name__)
    
    with app.test_request_context():
        response = make_response('test')
        response = add_security_headers(response)
        
        # Check all security headers are present
        assert response.headers.get('X-Content-Type-Options') == 'nosniff'
        assert response.headers.get('X-Frame-Options') == 'DENY'
        assert response.headers.get('X-XSS-Protection') == '1; mode=block'
        assert 'Content-Security-Policy' in response.headers
        assert 'default-src' in response.headers.get('Content-Security-Policy')
        assert response.headers.get('Referrer-Policy') == 'strict-origin-when-cross-origin'


def test_add_security_headers_https():
    """Test that HSTS header is added for HTTPS requests."""
    app = Flask(__name__)
    
    with app.test_request_context('/', base_url='https://example.com'):
        response = make_response('test')
        response = add_security_headers(response)
        
        assert 'Strict-Transport-Security' in response.headers


def test_configure_security_headers():
    """Test that security headers are configured on app."""
    app = Flask(__name__)
    configure_security_headers(app)
    
    @app.route('/test')
    def test_route():
        return 'ok'
    
    with app.test_client() as client:
        response = client.get('/test')
        assert response.headers.get('X-Content-Type-Options') == 'nosniff'


# ============================================================================
# API Key Authentication Tests
# ============================================================================

def test_api_key_auth_disabled_by_default():
    """Test that API key auth is disabled when no key is set."""
    auth = APIKeyAuth()
    assert not auth.is_enabled()
    assert auth.verify_key('any-key')  # Should allow access when disabled


def test_api_key_auth_from_environment(monkeypatch):
    """Test loading API key from environment variable."""
    monkeypatch.setenv('DASHBOARD_API_KEY', 'test-key-123')
    auth = APIKeyAuth()
    
    assert auth.is_enabled()
    assert auth.verify_key('test-key-123')
    assert not auth.verify_key('wrong-key')


def test_api_key_auth_add_remove():
    """Test adding and removing API keys."""
    auth = APIKeyAuth()
    
    # Add key
    auth.add_key('test-key', 'test')
    assert auth.is_enabled()
    assert auth.verify_key('test-key')
    
    # Remove key
    assert auth.remove_key('test')
    assert not auth.is_enabled()
    
    # Remove non-existent key
    assert not auth.remove_key('nonexistent')


def test_api_key_auth_multiple_keys():
    """Test that multiple API keys can be added."""
    auth = APIKeyAuth()
    
    auth.add_key('key1', 'first')
    auth.add_key('key2', 'second')
    
    assert auth.verify_key('key1')
    assert auth.verify_key('key2')
    assert not auth.verify_key('key3')


def test_require_api_key_decorator():
    """Test @require_api_key decorator."""
    app = Flask(__name__)
    
    # Enable API key auth
    auth = get_api_key_auth()
    auth.add_key('valid-key')
    
    @app.route('/protected')
    @require_api_key
    def protected():
        return jsonify({'status': 'ok'})
    
    with app.test_client() as client:
        # Without key - should fail
        response = client.get('/protected')
        assert response.status_code == 401
        
        # With key in header - should succeed
        response = client.get('/protected', headers={'X-API-Key': 'valid-key'})
        assert response.status_code == 200
        
        # With key in query param - should succeed
        response = client.get('/protected?api_key=valid-key')
        assert response.status_code == 200
        
        # With wrong key - should fail
        response = client.get('/protected', headers={'X-API-Key': 'wrong-key'})
        assert response.status_code == 401
    
    # Clean up
    auth.remove_key('default')


def test_require_api_key_when_disabled():
    """Test that @require_api_key allows access when auth is disabled."""
    app = Flask(__name__)
    
    auth = get_api_key_auth()
    auth.set_enabled(False)
    
    @app.route('/protected')
    @require_api_key
    def protected():
        return jsonify({'status': 'ok'})
    
    with app.test_client() as client:
        # Should succeed without key when disabled
        response = client.get('/protected')
        assert response.status_code == 200


# ============================================================================
# CSRF Protection Tests
# ============================================================================

def test_csrf_token_generation():
    """Test CSRF token generation."""
    csrf = CSRFProtection()
    token1 = csrf.generate_token()
    token2 = csrf.generate_token()
    
    assert len(token1) > 20  # Should be reasonably long
    assert token1 != token2  # Should be unique


def test_csrf_token_validation():
    """Test CSRF token validation."""
    csrf = CSRFProtection()
    token = csrf.generate_token()
    
    # Valid token
    assert csrf.validate_token(token, token)
    
    # Invalid token
    assert not csrf.validate_token('wrong', token)
    assert not csrf.validate_token(token, 'wrong')
    assert not csrf.validate_token('', token)
    assert not csrf.validate_token(token, '')


def test_csrf_protect_decorator_get_request():
    """Test that CSRF protection doesn't apply to GET requests."""
    app = Flask(__name__)
    
    csrf = get_csrf_protection()
    csrf.set_enabled(True)
    
    @app.route('/api/data', methods=['GET', 'POST'])
    @csrf_protect
    def api_data():
        return jsonify({'status': 'ok'})
    
    with app.test_client() as client:
        # GET should work without CSRF token
        response = client.get('/api/data')
        assert response.status_code == 200


def test_csrf_protect_decorator_post_request():
    """Test that CSRF protection applies to POST requests."""
    app = Flask(__name__)
    
    csrf = get_csrf_protection()
    csrf.set_enabled(True)
    
    @app.route('/api/update', methods=['POST'])
    @csrf_protect
    def api_update():
        return jsonify({'status': 'updated'})
    
    with app.test_client() as client:
        # POST without token should fail
        response = client.post('/api/update')
        assert response.status_code == 403
        
        # POST with valid token should succeed
        token = csrf.generate_token()
        client.set_cookie('csrf_token', token)
        response = client.post('/api/update', headers={'X-CSRF-Token': token})
        assert response.status_code == 200


def test_csrf_protect_when_disabled():
    """Test that CSRF protection allows access when disabled."""
    app = Flask(__name__)
    
    csrf = get_csrf_protection()
    csrf.set_enabled(False)
    
    @app.route('/api/update', methods=['POST'])
    @csrf_protect
    def api_update():
        return jsonify({'status': 'updated'})
    
    with app.test_client() as client:
        # Should succeed without token when disabled
        response = client.post('/api/update')
        assert response.status_code == 200


def test_csrf_token_from_form_field():
    """Test CSRF token validation from form field."""
    app = Flask(__name__)
    
    csrf = get_csrf_protection()
    csrf.set_enabled(True)
    
    @app.route('/form', methods=['POST'])
    @csrf_protect
    def form_submit():
        return jsonify({'status': 'ok'})
    
    with app.test_client() as client:
        token = csrf.generate_token()
        client.set_cookie('csrf_token', token)
        
        # Token in form field should work
        response = client.post('/form', data={'_csrf': token, 'field': 'value'})
        assert response.status_code == 200


# ============================================================================
# Input Sanitization Tests
# ============================================================================

def test_sanitize_path_basic():
    """Test basic path sanitization."""
    result = sanitize_path('/var/log/test.log')
    assert result is not None
    assert os.path.isabs(result)


def test_sanitize_path_with_base_dir():
    """Test path sanitization with base directory restriction."""
    base = '/var/log'
    
    # Valid path within base
    result = sanitize_path('/var/log/test.log', base)
    assert result is not None
    
    # Invalid path outside base
    result = sanitize_path('/etc/passwd', base)
    assert result is None


def test_sanitize_path_traversal_attempts():
    """Test that path traversal attempts are blocked."""
    # Directory traversal with ..
    result = sanitize_path('/var/log/../../etc/passwd')
    assert result is None
    
    # Tilde expansion
    result = sanitize_path('~/secrets')
    assert result is None
    
    # Environment variable
    result = sanitize_path('$HOME/file')
    assert result is None


def test_sanitize_path_empty():
    """Test sanitizing empty path."""
    result = sanitize_path('')
    assert result is None
    
    result = sanitize_path(None)
    assert result is None


def test_validate_sql_identifier_valid():
    """Test validation of valid SQL identifiers."""
    assert validate_sql_identifier('table_name')
    assert validate_sql_identifier('column123')
    assert validate_sql_identifier('_private')
    assert validate_sql_identifier('mixedCase')


def test_validate_sql_identifier_invalid():
    """Test validation of invalid SQL identifiers."""
    # Empty
    assert not validate_sql_identifier('')
    assert not validate_sql_identifier(None)
    
    # Starts with number
    assert not validate_sql_identifier('123table')
    
    # Contains special characters
    assert not validate_sql_identifier('table-name')
    assert not validate_sql_identifier('table.name')
    assert not validate_sql_identifier('table name')
    
    # SQL keywords
    assert not validate_sql_identifier('select')
    assert not validate_sql_identifier('DROP')
    assert not validate_sql_identifier('insert')


# ============================================================================
# Integration Tests
# ============================================================================

def test_full_security_stack():
    """Test that all security features work together."""
    app = Flask(__name__)
    
    # Configure all security features
    configure_security_headers(app)
    
    auth = get_api_key_auth()
    auth.add_key('test-key')
    
    csrf = get_csrf_protection()
    csrf.set_enabled(True)
    
    @app.route('/api/secure', methods=['GET', 'POST'])
    @require_api_key
    @csrf_protect
    def secure_endpoint():
        return jsonify({'status': 'ok'})
    
    with app.test_client() as client:
        # GET with API key should work (no CSRF needed for GET)
        response = client.get('/api/secure', headers={'X-API-Key': 'test-key'})
        assert response.status_code == 200
        assert 'X-Content-Type-Options' in response.headers
        
        # POST with API key but no CSRF should fail
        response = client.post('/api/secure', headers={'X-API-Key': 'test-key'})
        assert response.status_code == 403
        
        # POST with both API key and CSRF should work
        token = csrf.generate_token()
        client.set_cookie('csrf_token', token)
        response = client.post('/api/secure', 
                             headers={'X-API-Key': 'test-key', 'X-CSRF-Token': token})
        assert response.status_code == 200
    
    # Clean up
    auth.remove_key('default')


if __name__ == '__main__':
    pytest.main([__file__, '-v'])

"""
Security utilities for SystemDashboard Flask application.

This module provides security features including:
- Secure HTTP headers
- API key authentication
- CSRF protection
- Input sanitization helpers
"""

import os
import secrets
import hashlib
import hmac
import time
from functools import wraps
from typing import Optional, Dict, Any, Callable
from flask import request, jsonify, Response, make_response
import logging

logger = logging.getLogger(__name__)


# ============================================================================
# Security Headers
# ============================================================================

def add_security_headers(response: Response) -> Response:
    """
    Add security headers to Flask response.
    
    Headers added:
    - X-Content-Type-Options: nosniff
    - X-Frame-Options: DENY
    - X-XSS-Protection: 1; mode=block
    - Content-Security-Policy: Restrictive CSP
    - Strict-Transport-Security: HSTS (if HTTPS)
    - Referrer-Policy: strict-origin-when-cross-origin
    
    Args:
        response: Flask response object
        
    Returns:
        Response with security headers added
    """
    # Prevent MIME type sniffing
    response.headers['X-Content-Type-Options'] = 'nosniff'
    
    # Prevent clickjacking
    response.headers['X-Frame-Options'] = 'DENY'
    
    # Enable XSS filter (legacy browsers)
    response.headers['X-XSS-Protection'] = '1; mode=block'
    
    # Content Security Policy
    # Allow self, inline styles (for existing app), and CDN resources
    csp = (
        "default-src 'self'; "
        "script-src 'self' https://cdn.jsdelivr.net 'unsafe-inline'; "
        "style-src 'self' 'unsafe-inline'; "
        "img-src 'self' data:; "
        "font-src 'self'; "
        "connect-src 'self'; "
        "frame-ancestors 'none'; "
        "base-uri 'self'; "
        "form-action 'self'"
    )
    response.headers['Content-Security-Policy'] = csp
    
    # HSTS - only if HTTPS is being used
    if request.is_secure:
        response.headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
    
    # Referrer policy
    response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
    
    return response


def configure_security_headers(app) -> None:
    """
    Configure Flask app to add security headers to all responses.
    
    Args:
        app: Flask application instance
    """
    @app.after_request
    def apply_security_headers(response):
        return add_security_headers(response)
    
    logger.info("Security headers configured")


# ============================================================================
# API Key Authentication
# ============================================================================

class APIKeyAuth:
    """
    Simple API key authentication system.
    
    API keys can be set via:
    1. Environment variable: DASHBOARD_API_KEY
    2. Configuration at runtime
    
    Keys are hashed for storage security.
    """
    
    def __init__(self):
        self._api_keys: Dict[str, str] = {}  # {key_name: hashed_key}
        self._enabled = False
        self._load_from_environment()
    
    def _load_from_environment(self) -> None:
        """Load API key from environment variable."""
        api_key = os.environ.get('DASHBOARD_API_KEY')
        if api_key:
            # Hash the key for secure storage
            hashed = self._hash_key(api_key)
            self._api_keys['default'] = hashed
            self._enabled = True
            logger.info("API key authentication enabled (loaded from environment)")
    
    def _hash_key(self, key: str) -> str:
        """Hash an API key using SHA-256."""
        return hashlib.sha256(key.encode('utf-8')).hexdigest()
    
    def add_key(self, key: str, name: str = 'default') -> None:
        """
        Add an API key.
        
        Args:
            key: The API key to add
            name: Optional name for the key
        """
        hashed = self._hash_key(key)
        self._api_keys[name] = hashed
        self._enabled = True
        logger.info(f"API key '{name}' added")
    
    def remove_key(self, name: str = 'default') -> bool:
        """
        Remove an API key.
        
        Args:
            name: Name of the key to remove
            
        Returns:
            True if key was removed, False if not found
        """
        if name in self._api_keys:
            del self._api_keys[name]
            if not self._api_keys:
                self._enabled = False
            logger.info(f"API key '{name}' removed")
            return True
        return False
    
    def verify_key(self, key: str) -> bool:
        """
        Verify an API key.
        
        Args:
            key: The key to verify
            
        Returns:
            True if key is valid, False otherwise
        """
        if not self._enabled or not key:
            return not self._enabled  # If auth disabled, allow access
        
        hashed = self._hash_key(key)
        return hashed in self._api_keys.values()
    
    def is_enabled(self) -> bool:
        """Check if API key authentication is enabled."""
        return self._enabled
    
    def set_enabled(self, enabled: bool) -> None:
        """Enable or disable API key authentication."""
        self._enabled = enabled
        logger.info(f"API key authentication {'enabled' if enabled else 'disabled'}")


# Global API key auth instance
_api_key_auth = APIKeyAuth()


def get_api_key_auth() -> APIKeyAuth:
    """Get the global API key authentication instance."""
    return _api_key_auth


def require_api_key(f: Callable) -> Callable:
    """
    Decorator to require API key authentication for a route.
    
    API key can be provided in:
    - X-API-Key header
    - api_key query parameter
    
    Returns 401 Unauthorized if authentication fails.
    
    Example:
        @app.route('/api/sensitive')
        @require_api_key
        def sensitive_endpoint():
            return jsonify({'data': 'secret'})
    """
    @wraps(f)
    def decorated_function(*args, **kwargs):
        auth = get_api_key_auth()
        
        # If auth is disabled, allow access
        if not auth.is_enabled():
            return f(*args, **kwargs)
        
        # Check for API key in header or query parameter
        api_key = request.headers.get('X-API-Key') or request.args.get('api_key')
        
        if not api_key or not auth.verify_key(api_key):
            logger.warning(f"Unauthorized API access attempt from {request.remote_addr}")
            return jsonify({
                'error': 'Unauthorized',
                'message': 'Valid API key required'
            }), 401
        
        return f(*args, **kwargs)
    
    return decorated_function


# ============================================================================
# CSRF Protection
# ============================================================================

class CSRFProtection:
    """
    Simple CSRF protection using double-submit cookie pattern.
    
    For state-changing operations, clients must include:
    1. CSRF token in cookie (set automatically)
    2. Same token in X-CSRF-Token header or _csrf form field
    """
    
    def __init__(self):
        self._enabled = os.environ.get('DASHBOARD_CSRF_ENABLED', 'true').lower() == 'true'
        self._token_name = 'csrf_token'
        self._header_name = 'X-CSRF-Token'
        self._field_name = '_csrf'
    
    def generate_token(self) -> str:
        """Generate a new CSRF token."""
        return secrets.token_urlsafe(32)
    
    def validate_token(self, token: str, cookie_token: str) -> bool:
        """
        Validate a CSRF token against the cookie value.
        
        Args:
            token: Token from header or form field
            cookie_token: Token from cookie
            
        Returns:
            True if tokens match, False otherwise
        """
        if not token or not cookie_token:
            return False
        
        # Use constant-time comparison to prevent timing attacks
        return hmac.compare_digest(token, cookie_token)
    
    def is_enabled(self) -> bool:
        """Check if CSRF protection is enabled."""
        return self._enabled
    
    def set_enabled(self, enabled: bool) -> None:
        """Enable or disable CSRF protection."""
        self._enabled = enabled
        logger.info(f"CSRF protection {'enabled' if enabled else 'disabled'}")


# Global CSRF protection instance
_csrf_protection = CSRFProtection()


def get_csrf_protection() -> CSRFProtection:
    """Get the global CSRF protection instance."""
    return _csrf_protection


def csrf_protect(f: Callable) -> Callable:
    """
    Decorator to require CSRF token for state-changing operations.
    
    Token must be provided in:
    - X-CSRF-Token header, or
    - _csrf form field
    
    And must match the csrf_token cookie.
    
    Returns 403 Forbidden if validation fails.
    
    Example:
        @app.route('/api/update', methods=['POST'])
        @csrf_protect
        def update_data():
            return jsonify({'status': 'updated'})
    """
    @wraps(f)
    def decorated_function(*args, **kwargs):
        csrf = get_csrf_protection()
        
        # Only protect state-changing methods
        if request.method in ('GET', 'HEAD', 'OPTIONS'):
            return f(*args, **kwargs)
        
        # If CSRF protection is disabled, allow access
        if not csrf.is_enabled():
            return f(*args, **kwargs)
        
        # Get token from header or form field
        token = request.headers.get(csrf._header_name)
        if not token and request.form:
            token = request.form.get(csrf._field_name)
        if not token and request.is_json:
            token = request.json.get(csrf._field_name)
        
        # Get token from cookie
        cookie_token = request.cookies.get(csrf._token_name)
        
        # Validate
        if not csrf.validate_token(token, cookie_token):
            logger.warning(f"CSRF validation failed from {request.remote_addr}")
            return jsonify({
                'error': 'Forbidden',
                'message': 'CSRF token validation failed'
            }), 403
        
        return f(*args, **kwargs)
    
    return decorated_function


def set_csrf_token(response: Response) -> Response:
    """
    Set CSRF token in response cookie if not already present.
    
    Args:
        response: Flask response object
        
    Returns:
        Response with CSRF token cookie
    """
    csrf = get_csrf_protection()
    
    if not csrf.is_enabled():
        return response
    
    # Only set token if not already in cookies
    if csrf._token_name not in request.cookies:
        token = csrf.generate_token()
        response.set_cookie(
            csrf._token_name,
            token,
            httponly=False,  # JavaScript needs to read this
            secure=request.is_secure,
            samesite='Strict',
            max_age=3600  # 1 hour
        )
    
    return response


def configure_csrf_protection(app) -> None:
    """
    Configure Flask app with CSRF protection.
    
    Automatically sets CSRF token cookie on all responses.
    
    Args:
        app: Flask application instance
    """
    @app.after_request
    def apply_csrf_token(response):
        return set_csrf_token(response)
    
    logger.info("CSRF protection configured")


# ============================================================================
# Input Sanitization Helpers
# ============================================================================

def sanitize_path(path: str, base_dir: Optional[str] = None) -> Optional[str]:
    """
    Validate and sanitize a file path to prevent directory traversal.
    
    Args:
        path: The path to sanitize
        base_dir: Optional base directory to restrict access to
        
    Returns:
        Sanitized absolute path if valid, None if path is invalid
        
    Example:
        safe_path = sanitize_path(user_input, '/var/log')
        if safe_path:
            with open(safe_path, 'r') as f:
                data = f.read()
    """
    if not path:
        return None
    
    try:
        # Resolve to absolute path
        abs_path = os.path.abspath(path)
        
        # If base_dir specified, ensure path is within it
        if base_dir:
            base_abs = os.path.abspath(base_dir)
            # Check if path starts with base directory
            if not abs_path.startswith(base_abs + os.sep) and abs_path != base_abs:
                logger.warning(f"Path traversal attempt detected: {path}")
                return None
        
        # Check for dangerous patterns
        dangerous = ['..', '~', '$']
        for pattern in dangerous:
            if pattern in path:
                logger.warning(f"Dangerous pattern '{pattern}' in path: {path}")
                return None
        
        return abs_path
    
    except Exception as e:
        logger.error(f"Error sanitizing path '{path}': {e}")
        return None


def validate_sql_identifier(identifier: str) -> bool:
    """
    Validate that a string is a safe SQL identifier (table/column name).
    
    Args:
        identifier: The identifier to validate
        
    Returns:
        True if safe, False otherwise
    """
    if not identifier:
        return False
    
    # Must start with letter or underscore
    if not (identifier[0].isalpha() or identifier[0] == '_'):
        return False
    
    # Must contain only alphanumeric and underscore
    if not all(c.isalnum() or c == '_' for c in identifier):
        return False
    
    # Reject SQL keywords (basic list)
    sql_keywords = {
        'select', 'insert', 'update', 'delete', 'drop', 'create', 'alter',
        'table', 'from', 'where', 'join', 'union', 'exec', 'execute'
    }
    if identifier.lower() in sql_keywords:
        return False
    
    return True


# ============================================================================
# Rate Limit Error Handler
# ============================================================================

def create_rate_limit_handler(app) -> None:
    """
    Create error handler for rate limit (429) errors.
    
    Args:
        app: Flask application instance
    """
    @app.errorhandler(429)
    def rate_limit_exceeded(e):
        return jsonify({
            'error': 'Too Many Requests',
            'message': 'Rate limit exceeded. Please try again later.'
        }), 429

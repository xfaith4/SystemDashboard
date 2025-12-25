"""
API utilities for consistent error handling and response formatting.

This module provides utilities for:
- Consistent JSON error responses
- Request validation decorators
- Response caching
- CORS headers
"""

from flask import jsonify, request
from functools import wraps
from typing import Optional, Dict, Any, Callable
import time
import logging

from app.validators import ValidationError

logger = logging.getLogger(__name__)


class APIError(Exception):
    """Base exception for API errors."""
    
    def __init__(self, message: str, status_code: int = 400, payload: Optional[Dict] = None):
        """
        Initialize API error.
        
        Args:
            message: Error message
            status_code: HTTP status code
            payload: Additional error data
        """
        super().__init__()
        self.message = message
        self.status_code = status_code
        self.payload = payload or {}
        
    def to_dict(self) -> Dict[str, Any]:
        """Convert error to dictionary."""
        rv = {
            'error': self.message,
            'status': self.status_code,
            'timestamp': time.time()
        }
        rv.update(self.payload)
        return rv


def error_response(message: str, status_code: int = 400, **kwargs) -> tuple:
    """
    Create a consistent JSON error response.
    
    Args:
        message: Error message
        status_code: HTTP status code
        **kwargs: Additional fields to include in response
        
    Returns:
        Tuple of (jsonify response, status_code)
    """
    response = {
        'error': message,
        'status': status_code,
        'timestamp': time.time()
    }
    response.update(kwargs)
    
    return jsonify(response), status_code


def success_response(data: Any = None, message: Optional[str] = None, **kwargs) -> tuple:
    """
    Create a consistent JSON success response.
    
    Args:
        data: Response data
        message: Optional success message
        **kwargs: Additional fields to include in response
        
    Returns:
        Tuple of (jsonify response, status_code)
    """
    response = {
        'status': 'success',
        'timestamp': time.time()
    }
    
    if message:
        response['message'] = message
        
    if data is not None:
        response['data'] = data
        
    response.update(kwargs)
    
    return jsonify(response), 200


def handle_api_errors(f: Callable) -> Callable:
    """
    Decorator to handle API errors consistently.
    
    Catches ValidationError and APIError exceptions and returns
    appropriate JSON error responses.
    
    Example:
        @app.route('/api/endpoint')
        @handle_api_errors
        def my_endpoint():
            # If ValidationError or APIError is raised, 
            # it will be caught and formatted as JSON
            validate_something()
            return jsonify({'result': 'ok'})
    """
    @wraps(f)
    def decorated_function(*args, **kwargs):
        try:
            return f(*args, **kwargs)
        except ValidationError as e:
            logger.warning(f"Validation error in {f.__name__}: {e}")
            return error_response(str(e), 400)
        except APIError as e:
            logger.warning(f"API error in {f.__name__}: {e.message}")
            response = e.to_dict()
            return jsonify(response), e.status_code
        except Exception as e:
            logger.error(f"Unexpected error in {f.__name__}: {e}", exc_info=True)
            return error_response(
                'Internal server error',
                500,
                detail=str(e) if logger.level <= logging.DEBUG else None
            )
            
    return decorated_function


def require_json(f: Callable) -> Callable:
    """
    Decorator to require JSON content type for POST/PUT requests.
    
    Example:
        @app.route('/api/endpoint', methods=['POST'])
        @require_json
        @handle_api_errors
        def my_endpoint():
            data = request.get_json()
            # ...
    """
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if request.method in ['POST', 'PUT', 'PATCH']:
            if not request.is_json:
                return error_response(
                    'Content-Type must be application/json',
                    415  # Unsupported Media Type
                )
        return f(*args, **kwargs)
        
    return decorated_function


def validate_required_fields(required_fields: list) -> Callable:
    """
    Decorator to validate required fields in JSON payload.
    
    Args:
        required_fields: List of required field names
        
    Example:
        @app.route('/api/endpoint', methods=['POST'])
        @require_json
        @validate_required_fields(['name', 'email'])
        @handle_api_errors
        def my_endpoint():
            data = request.get_json()
            # name and email are guaranteed to exist
    """
    def decorator(f: Callable) -> Callable:
        @wraps(f)
        def decorated_function(*args, **kwargs):
            data = request.get_json()
            
            if not data:
                return error_response('Request body is required', 400)
                
            missing = [field for field in required_fields if field not in data]
            
            if missing:
                return error_response(
                    f"Missing required fields: {', '.join(missing)}",
                    400,
                    missing_fields=missing
                )
                
            return f(*args, **kwargs)
            
        return decorated_function
    return decorator


# Simple in-memory cache for API responses
_cache: Dict[str, tuple] = {}
_cache_timestamps: Dict[str, float] = {}


def cache_response(ttl_seconds: int = 300) -> Callable:
    """
    Decorator to cache API responses.
    
    Args:
        ttl_seconds: Time-to-live for cached responses in seconds
        
    Example:
        @app.route('/api/expensive-query')
        @cache_response(ttl_seconds=600)  # Cache for 10 minutes
        @handle_api_errors
        def expensive_query():
            # This function will only run if cache is empty or expired
            result = perform_expensive_operation()
            return jsonify(result)
    """
    def decorator(f: Callable) -> Callable:
        @wraps(f)
        def decorated_function(*args, **kwargs):
            # Create cache key from function name and request args
            cache_key = f"{f.__name__}:{request.full_path}"
            
            # Check cache
            now = time.time()
            if cache_key in _cache and cache_key in _cache_timestamps:
                cache_age = now - _cache_timestamps[cache_key]
                if cache_age < ttl_seconds:
                    logger.debug(f"Cache hit for {cache_key} (age: {cache_age:.1f}s)")
                    return _cache[cache_key]
                    
            # Cache miss or expired - execute function
            result = f(*args, **kwargs)
            
            # Store in cache
            _cache[cache_key] = result
            _cache_timestamps[cache_key] = now
            
            # Clean up old cache entries
            _cleanup_cache(ttl_seconds)
            
            return result
            
        return decorated_function
    return decorator


def _cleanup_cache(ttl_seconds: int):
    """Remove expired entries from cache."""
    now = time.time()
    expired_keys = [
        key for key, timestamp in _cache_timestamps.items()
        if now - timestamp > ttl_seconds
    ]
    
    for key in expired_keys:
        _cache.pop(key, None)
        _cache_timestamps.pop(key, None)
        
    if expired_keys:
        logger.debug(f"Cleaned up {len(expired_keys)} expired cache entries")


def clear_cache():
    """Clear all cached responses."""
    global _cache, _cache_timestamps
    count = len(_cache)
    _cache.clear()
    _cache_timestamps.clear()
    logger.info(f"Cleared {count} cached responses")


def add_cors_headers(response):
    """
    Add CORS headers to a response.
    
    Args:
        response: Flask response object
        
    Returns:
        Modified response with CORS headers
    """
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
    response.headers['Access-Control-Max-Age'] = '3600'
    return response


def with_cors(f: Callable) -> Callable:
    """
    Decorator to add CORS headers to response.
    
    Example:
        @app.route('/api/endpoint')
        @with_cors
        def my_endpoint():
            return jsonify({'result': 'ok'})
    """
    @wraps(f)
    def decorated_function(*args, **kwargs):
        # Handle preflight OPTIONS request
        if request.method == 'OPTIONS':
            response = jsonify({'status': 'ok'})
            return add_cors_headers(response)
            
        # Execute function and add CORS headers
        response = f(*args, **kwargs)
        
        # If response is a tuple (body, status), extract the response object
        if isinstance(response, tuple):
            return add_cors_headers(response[0]), *response[1:]
        else:
            return add_cors_headers(response)
            
    return decorated_function

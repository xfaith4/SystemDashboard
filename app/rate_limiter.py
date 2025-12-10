"""
Rate limiting for API endpoints.

Provides per-client rate limiting with sliding window algorithm
to prevent abuse and ensure fair resource usage.
"""

import time
from collections import defaultdict, deque
from functools import wraps
from typing import Callable, Optional
from flask import request, jsonify, make_response


class RateLimiter:
    """
    Simple in-memory rate limiter using sliding window algorithm.
    
    Tracks requests per client (identified by IP address) and enforces
    configurable limits on request frequency.
    """
    
    def __init__(self):
        # Store request timestamps per client
        # Format: {client_id: deque([timestamp1, timestamp2, ...])}
        self._requests = defaultdict(deque)
        self._window_size = 60  # Default: 60 seconds
        self._max_requests = 100  # Default: 100 requests per window
    
    def _get_client_id(self) -> str:
        """Get unique identifier for current client (IP address)."""
        # Try to get real IP from proxy headers
        if request.headers.get('X-Forwarded-For'):
            return request.headers.get('X-Forwarded-For').split(',')[0].strip()
        elif request.headers.get('X-Real-IP'):
            return request.headers.get('X-Real-IP')
        else:
            return request.remote_addr or 'unknown'
    
    def _cleanup_old_requests(self, client_id: str, current_time: float, window_size: Optional[float] = None):
        """Remove requests outside the current window."""
        if window_size is None:
            window_size = self._window_size
        cutoff_time = current_time - window_size
        
        # Remove old timestamps from the front of the deque
        while self._requests[client_id] and self._requests[client_id][0] < cutoff_time:
            self._requests[client_id].popleft()
    
    def is_allowed(self, client_id: Optional[str] = None, 
                   max_requests: Optional[int] = None,
                   window_seconds: Optional[int] = None) -> tuple[bool, dict]:
        """
        Check if a request from this client should be allowed.
        
        Args:
            client_id: Client identifier (uses current request IP if None)
            max_requests: Override default max requests limit
            window_seconds: Override default window size
            
        Returns:
            Tuple of (allowed: bool, info: dict with rate limit details)
        """
        if client_id is None:
            client_id = self._get_client_id()
        
        window_size = window_seconds if window_seconds is not None else self._window_size
        max_reqs = max_requests if max_requests is not None else self._max_requests
        
        current_time = time.time()
        
        # Clean up old requests
        self._cleanup_old_requests(client_id, current_time, window_size)
        
        # Count requests in current window
        request_count = len(self._requests[client_id])
        
        # Calculate time until window reset
        if self._requests[client_id]:
            oldest_request = self._requests[client_id][0]
            reset_time = int(oldest_request + window_size)
        else:
            reset_time = int(current_time + window_size)
        
        info = {
            'limit': max_reqs,
            'remaining': max(0, max_reqs - request_count),
            'reset': reset_time,
            'window_seconds': window_size
        }
        
        # Check if limit exceeded
        if request_count >= max_reqs:
            return False, info
        
        # Record this request
        self._requests[client_id].append(current_time)
        info['remaining'] = max(0, max_reqs - request_count - 1)
        
        return True, info
    
    def reset_client(self, client_id: Optional[str] = None):
        """Reset rate limit for a specific client."""
        if client_id is None:
            client_id = self._get_client_id()
        
        if client_id in self._requests:
            del self._requests[client_id]
    
    def reset_all(self):
        """Reset rate limits for all clients. Useful for testing."""
        self._requests.clear()
    
    def get_stats(self) -> dict:
        """Get statistics about current rate limiting state."""
        current_time = time.time()
        active_clients = 0
        total_requests = 0
        
        for client_id in list(self._requests.keys()):
            self._cleanup_old_requests(client_id, current_time)
            if self._requests[client_id]:
                active_clients += 1
                total_requests += len(self._requests[client_id])
        
        return {
            'active_clients': active_clients,
            'total_requests_in_window': total_requests,
            'window_seconds': self._window_size,
            'max_requests_per_window': self._max_requests
        }


# Global rate limiter instance
_rate_limiter = RateLimiter()


def get_rate_limiter() -> RateLimiter:
    """Get the global rate limiter instance."""
    return _rate_limiter


def rate_limit(max_requests: int = 100, window_seconds: int = 60):
    """
    Decorator to add rate limiting to Flask routes.
    
    Args:
        max_requests: Maximum number of requests allowed in the time window
        window_seconds: Time window in seconds
        
    Usage:
        @app.route('/api/endpoint')
        @rate_limit(max_requests=10, window_seconds=60)
        def my_endpoint():
            return {'result': 'ok'}
    
    The decorator adds the following response headers:
    - X-RateLimit-Limit: Maximum requests allowed
    - X-RateLimit-Remaining: Requests remaining in current window
    - X-RateLimit-Reset: Unix timestamp when the limit resets
    
    When rate limit is exceeded, returns 429 Too Many Requests with:
    - Retry-After header indicating seconds until reset
    - JSON body with error details
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(*args, **kwargs):
            limiter = get_rate_limiter()
            allowed, info = limiter.is_allowed(
                max_requests=max_requests,
                window_seconds=window_seconds
            )
            
            if not allowed:
                # Calculate retry-after in seconds
                retry_after = max(0, info['reset'] - int(time.time()))
                
                response = jsonify({
                    'error': 'Rate limit exceeded',
                    'message': f'Too many requests. Please try again in {retry_after} seconds.',
                    'limit': info['limit'],
                    'window_seconds': info['window_seconds'],
                    'reset_time': info['reset']
                })
                response.status_code = 429
                response.headers['Retry-After'] = str(retry_after)
                response.headers['X-RateLimit-Limit'] = str(info['limit'])
                response.headers['X-RateLimit-Remaining'] = '0'
                response.headers['X-RateLimit-Reset'] = str(info['reset'])
                
                return response
            
            # Call the actual endpoint
            result = func(*args, **kwargs)
            
            # Convert to Response object if needed
            if not hasattr(result, 'headers'):
                result = make_response(result)
            
            # Add rate limit headers to successful response
            result.headers['X-RateLimit-Limit'] = str(info['limit'])
            result.headers['X-RateLimit-Remaining'] = str(info['remaining'])
            result.headers['X-RateLimit-Reset'] = str(info['reset'])
            
            return result
        
        return wrapper
    return decorator


def check_rate_limit(max_requests: int = 100, window_seconds: int = 60) -> tuple[bool, dict]:
    """
    Check rate limit without recording a request.
    
    Useful for preflight checks or conditional rate limiting.
    
    Args:
        max_requests: Maximum requests allowed
        window_seconds: Time window in seconds
        
    Returns:
        Tuple of (allowed: bool, info: dict)
    """
    limiter = get_rate_limiter()
    client_id = limiter._get_client_id()
    current_time = time.time()
    
    # Clean up but don't record
    limiter._cleanup_old_requests(client_id, current_time, window_seconds)
    
    request_count = len(limiter._requests[client_id])
    
    if limiter._requests[client_id]:
        oldest_request = limiter._requests[client_id][0]
        reset_time = int(oldest_request + window_seconds)
    else:
        reset_time = int(current_time + window_seconds)
    
    info = {
        'limit': max_requests,
        'remaining': max(0, max_requests - request_count),
        'reset': reset_time,
        'window_seconds': window_seconds
    }
    
    return request_count < max_requests, info

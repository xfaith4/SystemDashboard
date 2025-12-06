"""Tests for rate limiter module."""

import pytest
import time
import os
import sys
from flask import Flask

# Add the app directory to the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'app'))

from rate_limiter import (
    RateLimiter,
    get_rate_limiter,
    rate_limit,
    check_rate_limit
)


@pytest.fixture
def app():
    """Create Flask app for testing."""
    app = Flask(__name__)
    app.config['TESTING'] = True
    return app


@pytest.fixture
def limiter():
    """Create a fresh rate limiter for each test."""
    limiter = RateLimiter()
    # Clear any previous state
    limiter._requests.clear()
    return limiter


class TestRateLimiter:
    """Test RateLimiter class."""
    
    def test_initialization(self, limiter):
        """Test rate limiter initializes correctly."""
        assert limiter._window_size == 60
        assert limiter._max_requests == 100
        assert len(limiter._requests) == 0
    
    def test_allows_requests_under_limit(self, limiter):
        """Test requests under limit are allowed."""
        client_id = '192.168.1.1'
        
        for i in range(10):
            allowed, info = limiter.is_allowed(
                client_id=client_id,
                max_requests=10,
                window_seconds=60
            )
            
            assert allowed is True
            assert info['remaining'] >= 0
    
    def test_blocks_requests_over_limit(self, limiter):
        """Test requests over limit are blocked."""
        client_id = '192.168.1.1'
        
        # Make 5 requests (limit is 5)
        for i in range(5):
            allowed, info = limiter.is_allowed(
                client_id=client_id,
                max_requests=5,
                window_seconds=60
            )
            assert allowed is True
        
        # 6th request should be blocked
        allowed, info = limiter.is_allowed(
            client_id=client_id,
            max_requests=5,
            window_seconds=60
        )
        assert allowed is False
        assert info['remaining'] == 0
    
    def test_window_sliding(self, limiter):
        """Test sliding window behavior."""
        client_id = '192.168.1.1'
        
        # Make first request
        allowed, info = limiter.is_allowed(
            client_id=client_id,
            max_requests=2,
            window_seconds=1
        )
        assert allowed is True
        assert info['remaining'] == 1
        
        # Make second request immediately
        allowed, info = limiter.is_allowed(
            client_id=client_id,
            max_requests=2,
            window_seconds=1
        )
        assert allowed is True
        assert info['remaining'] == 0
        
        # Third request should be blocked (limit reached)
        allowed, info = limiter.is_allowed(
            client_id=client_id,
            max_requests=2,
            window_seconds=1
        )
        assert allowed is False
        assert info['remaining'] == 0
        
        # Wait for entire window to expire
        time.sleep(1.05)
        
        # Should be allowed again (all requests have aged out)
        allowed, info = limiter.is_allowed(
            client_id=client_id,
            max_requests=2,
            window_seconds=1
        )
        assert allowed is True
        assert info['remaining'] == 1
    
    def test_separate_clients(self, limiter):
        """Test different clients have separate limits."""
        # Client 1 uses their limit
        for i in range(3):
            allowed, info = limiter.is_allowed(
                client_id='client1',
                max_requests=3,
                window_seconds=60
            )
            assert allowed is True
        
        # Client 1 is blocked
        allowed, info = limiter.is_allowed(
            client_id='client1',
            max_requests=3,
            window_seconds=60
        )
        assert allowed is False
        
        # Client 2 should still be allowed
        allowed, info = limiter.is_allowed(
            client_id='client2',
            max_requests=3,
            window_seconds=60
        )
        assert allowed is True
    
    def test_reset_client(self, limiter):
        """Test resetting a client's rate limit."""
        client_id = '192.168.1.1'
        
        # Use up the limit
        for i in range(3):
            limiter.is_allowed(
                client_id=client_id,
                max_requests=3,
                window_seconds=60
            )
        
        # Should be blocked
        allowed, info = limiter.is_allowed(
            client_id=client_id,
            max_requests=3,
            window_seconds=60
        )
        assert allowed is False
        
        # Reset the client
        limiter.reset_client(client_id)
        
        # Should be allowed again
        allowed, info = limiter.is_allowed(
            client_id=client_id,
            max_requests=3,
            window_seconds=60
        )
        assert allowed is True
    
    def test_get_stats(self, limiter):
        """Test getting rate limiter statistics."""
        # Make some requests from different clients
        limiter.is_allowed(client_id='client1', max_requests=10, window_seconds=60)
        limiter.is_allowed(client_id='client1', max_requests=10, window_seconds=60)
        limiter.is_allowed(client_id='client2', max_requests=10, window_seconds=60)
        
        stats = limiter.get_stats()
        
        assert stats['active_clients'] == 2
        assert stats['total_requests_in_window'] == 3


class TestRateLimitDecorator:
    """Test rate_limit decorator."""
    
    @pytest.fixture(autouse=True)
    def reset_global_limiter(self):
        """Reset the global rate limiter before each test."""
        limiter = get_rate_limiter()
        limiter._requests.clear()
        yield
        limiter._requests.clear()
    
    def test_decorator_allows_under_limit(self, app):
        """Test decorated endpoint allows requests under limit."""
        @app.route('/test')
        @rate_limit(max_requests=5, window_seconds=60)
        def test_endpoint():
            return {'status': 'ok'}
        
        with app.test_client() as client:
            # First 5 requests should succeed
            for i in range(5):
                response = client.get('/test')
                assert response.status_code == 200
                assert 'X-RateLimit-Limit' in response.headers
                assert response.headers['X-RateLimit-Limit'] == '5'
    
    def test_decorator_blocks_over_limit(self, app):
        """Test decorated endpoint blocks requests over limit."""
        @app.route('/test')
        @rate_limit(max_requests=3, window_seconds=60)
        def test_endpoint():
            return {'status': 'ok'}
        
        with app.test_client() as client:
            # First 3 requests succeed
            for i in range(3):
                response = client.get('/test')
                assert response.status_code == 200
            
            # 4th request should be blocked
            response = client.get('/test')
            assert response.status_code == 429
            assert 'Retry-After' in response.headers
            
            data = response.get_json()
            assert 'error' in data
            assert data['error'] == 'Rate limit exceeded'
    
    def test_decorator_includes_headers(self, app):
        """Test decorator includes rate limit headers."""
        @app.route('/test')
        @rate_limit(max_requests=10, window_seconds=60)
        def test_endpoint():
            return {'status': 'ok'}
        
        with app.test_client() as client:
            response = client.get('/test')
            
            assert 'X-RateLimit-Limit' in response.headers
            assert 'X-RateLimit-Remaining' in response.headers
            assert 'X-RateLimit-Reset' in response.headers
            
            assert int(response.headers['X-RateLimit-Limit']) == 10
            assert int(response.headers['X-RateLimit-Remaining']) >= 0
    
    def test_decorator_different_limits(self, app):
        """Test different endpoints can have different limits."""
        @app.route('/strict')
        @rate_limit(max_requests=2, window_seconds=60)
        def strict_endpoint():
            return {'status': 'ok'}
        
        @app.route('/lenient')
        @rate_limit(max_requests=10, window_seconds=60)
        def lenient_endpoint():
            return {'status': 'ok'}
        
        with app.test_client() as client:
            # Use up strict limit
            for i in range(2):
                response = client.get('/strict')
                assert response.status_code == 200
            
            # Strict should be blocked
            response = client.get('/strict')
            assert response.status_code == 429
            
            # Lenient should still work
            response = client.get('/lenient')
            assert response.status_code == 200


class TestCheckRateLimit:
    """Test check_rate_limit function."""
    
    def test_check_without_recording(self, app):
        """Test checking rate limit without recording request."""
        limiter = get_rate_limiter()
        
        with app.test_request_context(
            '/',
            environ_base={'REMOTE_ADDR': '192.168.1.1'}
        ):
            # Check 5 times without recording
            for i in range(5):
                allowed, info = check_rate_limit(max_requests=3, window_seconds=60)
                # Should always be allowed since we're not recording
                assert allowed is True
                assert info['remaining'] == 3

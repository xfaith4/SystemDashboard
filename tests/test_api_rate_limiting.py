"""Integration tests for API endpoint rate limiting."""

import pytest
import os
import sys
from flask import Flask

# Add the app directory to the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'app'))

# Import the Flask app
from app import app as flask_app
from rate_limiter import get_rate_limiter


@pytest.fixture
def app():
    """Create Flask app for testing."""
    flask_app.config['TESTING'] = True
    return flask_app


@pytest.fixture
def client(app):
    """Create test client."""
    return app.test_client()


@pytest.fixture(autouse=True)
def reset_rate_limiter():
    """Reset rate limiter before and after each test."""
    limiter = get_rate_limiter()
    limiter._requests.clear()
    yield
    limiter._requests.clear()


class TestAPIEndpointRateLimiting:
    """Test rate limiting is applied to API endpoints."""
    
    def test_dashboard_summary_rate_limiting(self, client):
        """Test /api/dashboard/summary has rate limiting."""
        # Make multiple requests
        for i in range(5):
            response = client.get('/api/dashboard/summary')
            assert response.status_code == 200
            # Verify rate limit headers are present
            assert 'X-RateLimit-Limit' in response.headers
            assert 'X-RateLimit-Remaining' in response.headers
            assert 'X-RateLimit-Reset' in response.headers
        
        # Verify the limit is set to 60
        response = client.get('/api/dashboard/summary')
        assert response.headers['X-RateLimit-Limit'] == '60'
    
    def test_router_logs_rate_limiting(self, client):
        """Test /api/router/logs has rate limiting."""
        response = client.get('/api/router/logs')
        assert response.status_code == 200
        assert 'X-RateLimit-Limit' in response.headers
        assert response.headers['X-RateLimit-Limit'] == '60'
    
    def test_router_summary_rate_limiting(self, client):
        """Test /api/router/summary has rate limiting."""
        response = client.get('/api/router/summary')
        assert response.status_code == 200
        assert 'X-RateLimit-Limit' in response.headers
        assert response.headers['X-RateLimit-Limit'] == '30'
    
    def test_events_rate_limiting(self, client):
        """Test /api/events has rate limiting."""
        response = client.get('/api/events')
        assert response.status_code == 200
        assert 'X-RateLimit-Limit' in response.headers
        assert response.headers['X-RateLimit-Limit'] == '60'
    
    def test_events_summary_rate_limiting(self, client):
        """Test /api/events/summary has rate limiting."""
        response = client.get('/api/events/summary')
        assert response.status_code == 200
        assert 'X-RateLimit-Limit' in response.headers
        assert response.headers['X-RateLimit-Limit'] == '30'
    
    def test_trends_rate_limiting(self, client):
        """Test /api/trends has rate limiting."""
        response = client.get('/api/trends')
        assert response.status_code == 200
        assert 'X-RateLimit-Limit' in response.headers
        assert response.headers['X-RateLimit-Limit'] == '30'
    
    def test_ai_endpoints_strict_rate_limiting(self, client):
        """Test AI endpoints have strict rate limiting (10 req/min)."""
        # Test /api/ai/suggest
        response = client.post('/api/ai/suggest', json={'message': 'test', 'source': 'test'})
        # May return 400 or 502 if missing required fields/API key, but should still have rate limit headers
        assert 'X-RateLimit-Limit' in response.headers
        assert response.headers['X-RateLimit-Limit'] == '10'
        
        # Test /api/ai/explain
        response = client.post('/api/ai/explain', json={'type': 'router_log', 'context': {'test': 'data'}})
        assert 'X-RateLimit-Limit' in response.headers
        assert response.headers['X-RateLimit-Limit'] == '10'
    
    def test_lan_stats_rate_limiting(self, client):
        """Test /api/lan/stats has rate limiting."""
        response = client.get('/api/lan/stats')
        assert response.status_code == 200
        assert 'X-RateLimit-Limit' in response.headers
        assert response.headers['X-RateLimit-Limit'] == '60'
    
    def test_lan_devices_rate_limiting(self, client):
        """Test /api/lan/devices has rate limiting."""
        response = client.get('/api/lan/devices')
        assert response.status_code == 200
        assert 'X-RateLimit-Limit' in response.headers
        assert response.headers['X-RateLimit-Limit'] == '60'
    
    def test_lan_device_update_stricter_rate_limiting(self, client):
        """Test write endpoints have stricter rate limiting (30 req/min)."""
        # Test device update endpoint
        response = client.post('/api/lan/device/1/update', json={'nickname': 'test'})
        # May return 403 or 503 depending on CSRF and DB availability
        assert 'X-RateLimit-Limit' in response.headers
        assert response.headers['X-RateLimit-Limit'] == '30'
    
    def test_expensive_operations_very_strict_rate_limiting(self, client):
        """Test expensive operations have very strict rate limiting (5-10 req/min)."""
        # Test vendor enrichment (5 req/min)
        response = client.post('/api/lan/devices/enrich-vendors')
        assert 'X-RateLimit-Limit' in response.headers
        assert response.headers['X-RateLimit-Limit'] == '5'
        
        # Test vendor lookup (10 req/min)
        response = client.post('/api/lan/device/1/lookup-vendor')
        assert 'X-RateLimit-Limit' in response.headers
        assert response.headers['X-RateLimit-Limit'] == '10'
    
    def test_rate_limit_blocks_excessive_requests(self, client):
        """Test that rate limiting actually blocks excessive requests."""
        # Use a low-limit endpoint for testing
        endpoint = '/api/router/summary'  # 30 req/min limit
        
        # Make 30 successful requests
        for i in range(30):
            response = client.get(endpoint)
            assert response.status_code == 200, f"Request {i+1} should succeed"
            remaining = int(response.headers['X-RateLimit-Remaining'])
            assert remaining == 29 - i, f"Remaining should be {29 - i} but got {remaining}"
        
        # 31st request should be blocked
        response = client.get(endpoint)
        assert response.status_code == 429, "Request 31 should be rate limited"
        assert 'Retry-After' in response.headers
        
        data = response.get_json()
        assert 'error' in data
        assert data['error'] == 'Rate limit exceeded'
    
    def test_rate_limit_headers_decreasing(self, client):
        """Test that remaining counter decreases with each request."""
        endpoint = '/api/dashboard/summary'
        
        # First request
        response = client.get(endpoint)
        assert response.status_code == 200
        first_remaining = int(response.headers['X-RateLimit-Remaining'])
        
        # Second request
        response = client.get(endpoint)
        assert response.status_code == 200
        second_remaining = int(response.headers['X-RateLimit-Remaining'])
        
        # Remaining should decrease
        assert second_remaining == first_remaining - 1
    
    def test_different_endpoints_have_different_limits(self, client):
        """Test that different endpoints have appropriate limits."""
        # High-frequency endpoints (60 req/min)
        high_freq = ['/api/dashboard/summary', '/api/lan/stats', '/api/lan/devices']
        for endpoint in high_freq:
            response = client.get(endpoint)
            assert int(response.headers['X-RateLimit-Limit']) == 60
        
        # Medium-frequency endpoints (30 req/min)
        medium_freq = ['/api/router/summary', '/api/events/summary', '/api/trends']
        for endpoint in medium_freq:
            response = client.get(endpoint)
            assert int(response.headers['X-RateLimit-Limit']) == 30
        
        # Expensive operations (5-10 req/min)
        response = client.post('/api/lan/devices/enrich-vendors')
        assert int(response.headers['X-RateLimit-Limit']) == 5

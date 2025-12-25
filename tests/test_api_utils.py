"""
Test suite for API utilities.
"""
import os
import sys
import pytest
import time
from flask import Flask, jsonify, request

# Add the app directory to the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from app.api_utils import (
    APIError, error_response, success_response,
    handle_api_errors, require_json, validate_required_fields,
    cache_response, clear_cache, with_cors
)
from app.validators import ValidationError


@pytest.fixture
def app():
    """Create a test Flask app."""
    app = Flask(__name__)
    app.config['TESTING'] = True
    return app


@pytest.fixture
def client(app):
    """Create a test client."""
    return app.test_client()


class TestAPIError:
    """Test APIError exception class."""
    
    def test_api_error_creation(self):
        """Test creating an API error."""
        error = APIError("Test error", 404)
        assert error.message == "Test error"
        assert error.status_code == 404
        
    def test_api_error_to_dict(self):
        """Test converting error to dictionary."""
        error = APIError("Test error", 400, payload={'detail': 'More info'})
        result = error.to_dict()
        
        assert result['error'] == "Test error"
        assert result['status'] == 400
        assert result['detail'] == 'More info'
        assert 'timestamp' in result


class TestErrorResponse:
    """Test error response formatting."""
    
    def test_basic_error_response(self, app):
        """Test basic error response."""
        with app.app_context():
            response, status = error_response("Something went wrong", 400)
            data = response.get_json()
            
            assert status == 400
            assert data['error'] == "Something went wrong"
            assert data['status'] == 400
            assert 'timestamp' in data
        
    def test_error_response_with_extras(self, app):
        """Test error response with additional fields."""
        with app.app_context():
            response, status = error_response(
                "Validation failed",
                422,
                field='email',
                reason='Invalid format'
            )
            data = response.get_json()
            
            assert data['field'] == 'email'
            assert data['reason'] == 'Invalid format'


class TestSuccessResponse:
    """Test success response formatting."""
    
    def test_basic_success_response(self, app):
        """Test basic success response."""
        with app.app_context():
            response, status = success_response()
            data = response.get_json()
            
            assert status == 200
            assert data['status'] == 'success'
            assert 'timestamp' in data
        
    def test_success_response_with_data(self, app):
        """Test success response with data."""
        with app.app_context():
            response, status = success_response(data={'id': 123, 'name': 'Test'})
            data = response.get_json()
            
            assert data['data']['id'] == 123
            assert data['data']['name'] == 'Test'
        
    def test_success_response_with_message(self, app):
        """Test success response with message."""
        with app.app_context():
            response, status = success_response(message="Operation completed")
            data = response.get_json()
            
            assert data['message'] == "Operation completed"


class TestHandleApiErrors:
    """Test error handling decorator."""
    
    def test_validation_error_handling(self, app, client):
        """Test handling of ValidationError."""
        @app.route('/test')
        @handle_api_errors
        def test_route():
            raise ValidationError("Invalid input")
            
        response = client.get('/test')
        assert response.status_code == 400
        data = response.get_json()
        assert 'Invalid input' in data['error']
        
    def test_api_error_handling(self, app, client):
        """Test handling of APIError."""
        @app.route('/test')
        @handle_api_errors
        def test_route():
            raise APIError("Not found", 404)
            
        response = client.get('/test')
        assert response.status_code == 404
        data = response.get_json()
        assert 'Not found' in data['error']
        
    def test_generic_exception_handling(self, app, client):
        """Test handling of generic exceptions."""
        @app.route('/test')
        @handle_api_errors
        def test_route():
            raise ValueError("Something broke")
            
        response = client.get('/test')
        assert response.status_code == 500
        data = response.get_json()
        assert 'Internal server error' in data['error']
        
    def test_successful_execution(self, app, client):
        """Test that decorator doesn't interfere with successful execution."""
        @app.route('/test')
        @handle_api_errors
        def test_route():
            return jsonify({'result': 'ok'})
            
        response = client.get('/test')
        assert response.status_code == 200
        data = response.get_json()
        assert data['result'] == 'ok'


class TestRequireJson:
    """Test require_json decorator."""
    
    def test_post_with_json(self, app, client):
        """Test POST request with JSON content type."""
        @app.route('/test', methods=['POST'])
        @require_json
        def test_route():
            return jsonify({'result': 'ok'})
            
        response = client.post('/test', 
                             json={'data': 'test'},
                             content_type='application/json')
        assert response.status_code == 200
        
    def test_post_without_json(self, app, client):
        """Test POST request without JSON content type."""
        @app.route('/test', methods=['POST'])
        @require_json
        def test_route():
            return jsonify({'result': 'ok'})
            
        response = client.post('/test', data='plain text')
        assert response.status_code == 415
        data = response.get_json()
        assert 'Content-Type' in data['error']
        
    def test_get_without_json(self, app, client):
        """Test GET request doesn't require JSON."""
        @app.route('/test')
        @require_json
        def test_route():
            return jsonify({'result': 'ok'})
            
        response = client.get('/test')
        assert response.status_code == 200


class TestValidateRequiredFields:
    """Test validate_required_fields decorator."""
    
    def test_all_fields_present(self, app, client):
        """Test validation passes when all fields present."""
        @app.route('/test', methods=['POST'])
        @validate_required_fields(['name', 'email'])
        def test_route():
            return jsonify({'result': 'ok'})
            
        response = client.post('/test',
                             json={'name': 'Test', 'email': 'test@example.com'})
        assert response.status_code == 200
        
    def test_missing_field(self, app, client):
        """Test validation fails when field missing."""
        @app.route('/test', methods=['POST'])
        @validate_required_fields(['name', 'email'])
        def test_route():
            return jsonify({'result': 'ok'})
            
        response = client.post('/test', json={'name': 'Test'})
        assert response.status_code == 400
        data = response.get_json()
        assert 'email' in data['error']
        assert 'missing_fields' in data
        
    def test_empty_body(self, app, client):
        """Test validation fails with empty body."""
        @app.route('/test', methods=['POST'])
        @validate_required_fields(['name'])
        def test_route():
            return jsonify({'result': 'ok'})
            
        response = client.post('/test',
                             data='',
                             content_type='application/json')
        assert response.status_code == 400


class TestCacheResponse:
    """Test response caching decorator."""
    
    def test_cache_hit(self, app, client):
        """Test that cached response is returned."""
        call_count = [0]
        
        @app.route('/test')
        @cache_response(ttl_seconds=60)
        def test_route():
            call_count[0] += 1
            return jsonify({'count': call_count[0]})
            
        # First call
        response1 = client.get('/test')
        data1 = response1.get_json()
        assert data1['count'] == 1
        
        # Second call should be cached
        response2 = client.get('/test')
        data2 = response2.get_json()
        assert data2['count'] == 1  # Same as first call
        assert call_count[0] == 1  # Function only called once
        
    def test_cache_miss_after_expiry(self, app, client):
        """Test that cache expires after TTL."""
        # Clear any existing cache first
        clear_cache()
        
        call_count = [0]
        
        @app.route('/test_expiry')
        @cache_response(ttl_seconds=1)  # Very short TTL
        def test_route():
            call_count[0] += 1
            return jsonify({'count': call_count[0]})
            
        # First call
        response1 = client.get('/test_expiry')
        data1 = response1.get_json()
        assert data1['count'] == 1
        assert call_count[0] == 1
        
        # Wait for cache to expire
        time.sleep(1.1)
        
        # Second call should execute function again
        response2 = client.get('/test_expiry')
        data2 = response2.get_json()
        assert data2['count'] == 2
        assert call_count[0] == 2
        
    def test_cache_different_endpoints(self, app, client):
        """Test that different endpoints have separate caches."""
        # Clear any existing cache first
        clear_cache()
        
        @app.route('/test1_unique')
        @cache_response(ttl_seconds=60)
        def test1():
            return jsonify({'endpoint': 'test1'})
            
        @app.route('/test2_unique')
        @cache_response(ttl_seconds=60)
        def test2():
            return jsonify({'endpoint': 'test2'})
            
        response1 = client.get('/test1_unique')
        response2 = client.get('/test2_unique')
        
        assert response1.get_json()['endpoint'] == 'test1'
        assert response2.get_json()['endpoint'] == 'test2'
        
    def test_clear_cache(self, app, client):
        """Test clearing the cache."""
        # Clear any existing cache first
        clear_cache()
        
        call_count = [0]
        
        @app.route('/test_clear')
        @cache_response(ttl_seconds=60)
        def test_route():
            call_count[0] += 1
            return jsonify({'count': call_count[0]})
            
        # First call
        response1 = client.get('/test_clear')
        assert call_count[0] == 1
        assert response1.get_json()['count'] == 1
        
        # Clear cache
        clear_cache()
        
        # Should execute function again
        response2 = client.get('/test_clear')
        assert call_count[0] == 2
        assert response2.get_json()['count'] == 2


class TestCORSHeaders:
    """Test CORS header functionality."""
    
    def test_with_cors_decorator(self, app, client):
        """Test with_cors decorator adds headers."""
        @app.route('/test')
        @with_cors
        def test_route():
            return jsonify({'result': 'ok'})
            
        response = client.get('/test')
        assert response.status_code == 200
        assert 'Access-Control-Allow-Origin' in response.headers
        assert response.headers['Access-Control-Allow-Origin'] == '*'
        
    def test_cors_preflight_request(self, app, client):
        """Test CORS preflight OPTIONS request."""
        @app.route('/test', methods=['GET', 'POST', 'OPTIONS'])
        @with_cors
        def test_route():
            return jsonify({'result': 'ok'})
            
        response = client.options('/test')
        assert response.status_code == 200
        assert 'Access-Control-Allow-Methods' in response.headers
        assert 'Access-Control-Allow-Headers' in response.headers


if __name__ == '__main__':
    pytest.main([__file__, '-v'])

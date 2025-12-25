"""
Shared test fixtures and utilities for pytest.
"""
import os
import sys

# Add the app directory to the path so tests can import app modules
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))


def reset_rate_limiter():
    """
    Reset the rate limiter to ensure clean test state.
    
    This helper function resets all rate limiting state between tests
    to prevent test pollution and ensure tests are isolated.
    """
    try:
        import app as flask_app
        if flask_app.PHASE1_FEATURES_AVAILABLE:
            from app.rate_limiter import get_rate_limiter
            rate_limiter = get_rate_limiter()
            rate_limiter.reset_all()
    except (ImportError, AttributeError):
        # If Phase 1 features aren't available, silently continue
        pass


def pytest_ignore_collect(collection_path, config):
    if collection_path.name == "test_db_connection.py" and "app" in str(collection_path):
        return True

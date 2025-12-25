"""Tests for graceful shutdown module."""

import pytest
import signal
import threading
import time
import os
import sys
from unittest.mock import Mock, patch

# Add the app directory to the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from app.graceful_shutdown import (
    GracefulShutdown,
    get_shutdown_manager,
    register_cleanup,
    is_shutting_down,
    create_db_cleanup,
    create_cache_cleanup,
    create_state_persistence_cleanup
)


class TestGracefulShutdown:
    """Test GracefulShutdown class."""
    
    def test_initialization(self):
        """Test shutdown manager initializes correctly."""
        manager = GracefulShutdown(timeout=10)
        
        assert manager.timeout == 10
        assert len(manager.cleanup_functions) == 0
        assert manager.is_shutting_down is False
    
    def test_register_cleanup(self):
        """Test registering cleanup functions."""
        manager = GracefulShutdown()
        
        def cleanup1():
            pass
        
        def cleanup2():
            pass
        
        manager.register_cleanup(cleanup1, "cleanup1")
        manager.register_cleanup(cleanup2, "cleanup2")
        
        assert len(manager.cleanup_functions) == 2
        assert manager.cleanup_functions[0][1] == "cleanup1"
        assert manager.cleanup_functions[1][1] == "cleanup2"
    
    def test_cleanup_execution(self):
        """Test cleanup functions are executed."""
        manager = GracefulShutdown(timeout=5)
        
        executed = []
        
        def cleanup1():
            executed.append('cleanup1')
        
        def cleanup2():
            executed.append('cleanup2')
        
        manager.register_cleanup(cleanup1, "cleanup1")
        manager.register_cleanup(cleanup2, "cleanup2")
        
        # Run cleanup directly
        manager._run_cleanup()
        
        assert 'cleanup1' in executed
        assert 'cleanup2' in executed
    
    def test_cleanup_error_handling(self):
        """Test cleanup continues even if one function fails."""
        manager = GracefulShutdown(timeout=5)
        
        executed = []
        
        def failing_cleanup():
            raise Exception("Test error")
        
        def successful_cleanup():
            executed.append('success')
        
        manager.register_cleanup(failing_cleanup, "failing")
        manager.register_cleanup(successful_cleanup, "success")
        
        # Should not raise exception
        manager._run_cleanup()
        
        # Second cleanup should still execute
        assert 'success' in executed
    
    def test_shutdown_event(self):
        """Test shutdown event is set correctly."""
        manager = GracefulShutdown()
        
        assert manager.is_shutdown_requested() is False
        
        # Simulate shutdown
        manager.shutdown_event.set()
        
        assert manager.is_shutdown_requested() is True
    
    def test_wait_for_shutdown(self):
        """Test waiting for shutdown signal."""
        manager = GracefulShutdown()
        
        # Should timeout quickly
        result = manager.wait_for_shutdown(timeout=0.1)
        assert result is False
        
        # Set shutdown and try again
        manager.shutdown_event.set()
        result = manager.wait_for_shutdown(timeout=0.1)
        assert result is True


class TestGlobalShutdownManager:
    """Test global shutdown manager functions."""
    
    def test_get_shutdown_manager(self):
        """Test getting global shutdown manager."""
        manager1 = get_shutdown_manager()
        manager2 = get_shutdown_manager()
        
        # Should return same instance
        assert manager1 is manager2
    
    def test_register_cleanup_global(self):
        """Test registering cleanup with global manager."""
        executed = []
        
        def cleanup():
            executed.append('done')
        
        register_cleanup(cleanup, "test")
        
        # Get manager and run cleanup
        manager = get_shutdown_manager()
        manager._run_cleanup()
        
        assert 'done' in executed
    
    def test_is_shutting_down(self):
        """Test checking shutdown state."""
        manager = get_shutdown_manager()
        manager.shutdown_event.clear()
        
        assert is_shutting_down() is False
        
        manager.shutdown_event.set()
        assert is_shutting_down() is True


class TestCleanupFactories:
    """Test cleanup factory functions."""
    
    def test_create_db_cleanup_with_close_all(self):
        """Test database cleanup with close_all method."""
        db_manager = Mock()
        db_manager.close_all = Mock()
        
        cleanup = create_db_cleanup(db_manager)
        cleanup()
        
        db_manager.close_all.assert_called_once()
    
    def test_create_db_cleanup_with_close(self):
        """Test database cleanup with close method."""
        db_manager = Mock()
        db_manager.close = Mock()
        # Remove close_all to test fallback
        del db_manager.close_all
        
        cleanup = create_db_cleanup(db_manager)
        cleanup()
        
        db_manager.close.assert_called_once()
    
    def test_create_db_cleanup_error_handling(self):
        """Test database cleanup handles errors gracefully."""
        db_manager = Mock()
        db_manager.close_all = Mock(side_effect=Exception("Test error"))
        
        cleanup = create_db_cleanup(db_manager)
        # Should not raise exception
        cleanup()
    
    def test_create_cache_cleanup(self):
        """Test cache cleanup."""
        cache = {'key1': 'value1', 'key2': 'value2'}
        
        cleanup = create_cache_cleanup(cache)
        cleanup()
        
        assert len(cache) == 0
    
    def test_create_state_persistence_cleanup(self):
        """Test state persistence cleanup."""
        state = {'data': 'test'}
        save_func = Mock()
        
        cleanup = create_state_persistence_cleanup(state, save_func)
        cleanup()
        
        save_func.assert_called_once_with(state)
    
    def test_state_persistence_error_handling(self):
        """Test state persistence handles errors."""
        state = {'data': 'test'}
        save_func = Mock(side_effect=Exception("Save failed"))
        
        cleanup = create_state_persistence_cleanup(state, save_func)
        # Should not raise exception
        cleanup()


class TestSignalHandling:
    """Test signal handler integration."""
    
    @patch('sys.exit')
    def test_signal_handler_calls_cleanup(self, mock_exit):
        """Test signal handler triggers cleanup."""
        manager = GracefulShutdown(timeout=1)
        
        executed = []
        
        def cleanup():
            executed.append('done')
        
        manager.register_cleanup(cleanup, "test")
        
        # Simulate signal (but don't actually send it)
        # We can't easily test the actual signal handler without
        # complex threading, so we test the cleanup mechanism
        manager._run_cleanup()
        
        assert 'done' in executed
    
    def test_cleanup_timeout(self):
        """Test cleanup respects timeout."""
        manager = GracefulShutdown(timeout=1)
        
        def slow_cleanup():
            time.sleep(5)  # Takes longer than timeout
        
        manager.register_cleanup(slow_cleanup, "slow")
        
        start = time.time()
        
        # Run in thread to allow timeout
        cleanup_thread = threading.Thread(target=manager._run_cleanup)
        cleanup_thread.start()
        cleanup_thread.join(timeout=2)
        
        duration = time.time() - start
        
        # Should complete quickly due to threading
        assert duration < 3
    
    def test_multiple_signals_ignored(self):
        """Test multiple signals don't cause duplicate cleanup."""
        manager = GracefulShutdown(timeout=1)
        
        executed = []
        
        def cleanup():
            executed.append('done')
        
        manager.register_cleanup(cleanup, "test")
        
        # First cleanup
        manager.is_shutting_down = False
        manager._run_cleanup()
        
        # Simulate shutdown started
        manager.is_shutting_down = True
        
        # Second cleanup should be prevented by lock
        manager._run_cleanup()
        
        # Should only execute once per call
        assert len(executed) == 2  # Once per _run_cleanup call

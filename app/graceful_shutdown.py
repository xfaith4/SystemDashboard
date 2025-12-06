"""
Graceful shutdown handling for Flask application.

Provides signal handlers and cleanup routines to ensure:
- Database connections are properly closed
- In-flight requests are completed
- State is persisted before exit
"""

import signal
import sys
import logging
import threading
import time
from typing import Callable, List, Optional


logger = logging.getLogger(__name__)


class GracefulShutdown:
    """
    Manages graceful shutdown of the application.
    
    Handles SIGTERM and SIGINT signals, allowing registered cleanup
    functions to execute before the application exits.
    """
    
    def __init__(self, timeout: int = 30):
        """
        Initialize graceful shutdown handler.
        
        Args:
            timeout: Maximum seconds to wait for cleanup (default 30)
        """
        self.timeout = timeout
        self.cleanup_functions: List[Callable] = []
        self.shutdown_event = threading.Event()
        self.is_shutting_down = False
        self._lock = threading.Lock()
    
    def register_cleanup(self, func: Callable, name: Optional[str] = None):
        """
        Register a cleanup function to run on shutdown.
        
        Args:
            func: Callable to execute during shutdown
            name: Optional name for logging purposes
        """
        func_name = name or func.__name__
        logger.debug(f"Registered cleanup function: {func_name}")
        self.cleanup_functions.append((func, func_name))
    
    def _signal_handler(self, signum, frame):
        """Handle shutdown signals (SIGTERM, SIGINT)."""
        signal_name = signal.Signals(signum).name
        logger.info(f"Received {signal_name} signal, initiating graceful shutdown...")
        
        with self._lock:
            if self.is_shutting_down:
                logger.warning("Shutdown already in progress, ignoring signal")
                return
            
            self.is_shutting_down = True
            self.shutdown_event.set()
        
        # Run cleanup in a separate thread to avoid blocking signal handler
        cleanup_thread = threading.Thread(target=self._run_cleanup, name="shutdown-cleanup")
        cleanup_thread.daemon = False
        cleanup_thread.start()
        
        # Wait for cleanup with timeout
        cleanup_thread.join(timeout=self.timeout)
        
        if cleanup_thread.is_alive():
            logger.error(f"Cleanup did not complete within {self.timeout}s timeout")
        else:
            logger.info("Graceful shutdown completed successfully")
        
        # Exit the application
        sys.exit(0)
    
    def _run_cleanup(self):
        """Execute all registered cleanup functions."""
        logger.info(f"Running {len(self.cleanup_functions)} cleanup functions...")
        
        for func, name in self.cleanup_functions:
            try:
                logger.debug(f"Running cleanup: {name}")
                start_time = time.time()
                func()
                duration = time.time() - start_time
                logger.debug(f"Cleanup {name} completed in {duration:.2f}s")
            except Exception as e:
                logger.error(f"Error in cleanup function {name}: {e}", exc_info=True)
        
        logger.info("All cleanup functions completed")
    
    def install_signal_handlers(self):
        """Install signal handlers for SIGTERM and SIGINT."""
        signal.signal(signal.SIGTERM, self._signal_handler)
        signal.signal(signal.SIGINT, self._signal_handler)
        logger.info("Graceful shutdown handlers installed (SIGTERM, SIGINT)")
    
    def is_shutdown_requested(self) -> bool:
        """Check if shutdown has been requested."""
        return self.shutdown_event.is_set()
    
    def wait_for_shutdown(self, timeout: Optional[float] = None):
        """
        Block until shutdown is requested.
        
        Args:
            timeout: Optional timeout in seconds
            
        Returns:
            True if shutdown was requested, False if timeout occurred
        """
        return self.shutdown_event.wait(timeout=timeout)


# Global shutdown manager instance
_shutdown_manager: Optional[GracefulShutdown] = None


def get_shutdown_manager(timeout: int = 30) -> GracefulShutdown:
    """
    Get or create the global shutdown manager.
    
    Args:
        timeout: Shutdown timeout in seconds (only used on first call)
        
    Returns:
        GracefulShutdown instance
    """
    global _shutdown_manager
    if _shutdown_manager is None:
        _shutdown_manager = GracefulShutdown(timeout=timeout)
    return _shutdown_manager


def register_cleanup(func: Callable, name: Optional[str] = None):
    """
    Register a cleanup function for graceful shutdown.
    
    Convenience function that registers with the global shutdown manager.
    
    Args:
        func: Cleanup function to execute on shutdown
        name: Optional name for logging
    """
    manager = get_shutdown_manager()
    manager.register_cleanup(func, name)


def install_handlers(timeout: int = 30):
    """
    Install signal handlers for graceful shutdown.
    
    This should be called early in application startup, typically
    in the main module after imports.
    
    Args:
        timeout: Maximum seconds to wait for cleanup
    """
    manager = get_shutdown_manager(timeout=timeout)
    manager.install_signal_handlers()


def is_shutting_down() -> bool:
    """
    Check if application is shutting down.
    
    Useful for long-running tasks to check if they should abort early.
    
    Returns:
        True if shutdown has been initiated
    """
    manager = get_shutdown_manager()
    return manager.is_shutdown_requested()


# Common cleanup functions for Flask applications

def create_db_cleanup(db_manager) -> Callable:
    """
    Create a cleanup function for database manager.
    
    Args:
        db_manager: DatabaseManager instance to clean up
        
    Returns:
        Cleanup function that closes all database connections
    """
    def cleanup():
        logger.info("Closing database connections...")
        try:
            if hasattr(db_manager, 'close_all'):
                db_manager.close_all()
            elif hasattr(db_manager, 'close'):
                db_manager.close()
            logger.info("Database connections closed")
        except Exception as e:
            logger.error(f"Error closing database connections: {e}")
    
    return cleanup


def create_cache_cleanup(cache_dict: dict) -> Callable:
    """
    Create a cleanup function that clears a cache dictionary.
    
    Args:
        cache_dict: Dictionary to clear
        
    Returns:
        Cleanup function
    """
    def cleanup():
        logger.info(f"Clearing cache ({len(cache_dict)} entries)...")
        cache_dict.clear()
        logger.info("Cache cleared")
    
    return cleanup


def create_state_persistence_cleanup(state_obj, save_func: Callable) -> Callable:
    """
    Create a cleanup function that persists application state.
    
    Args:
        state_obj: State object to persist
        save_func: Function that saves the state
        
    Returns:
        Cleanup function
    """
    def cleanup():
        logger.info("Persisting application state...")
        try:
            save_func(state_obj)
            logger.info("Application state persisted")
        except Exception as e:
            logger.error(f"Error persisting state: {e}")
    
    return cleanup

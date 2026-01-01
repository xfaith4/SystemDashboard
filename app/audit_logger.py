"""
Audit logging and structured logging for SystemDashboard.

This module provides:
- Structured JSON logging
- Sensitive data masking
- Audit trail for configuration changes
- Log rotation configuration helpers
"""

import os
import json
import logging
import re
from typing import Any, Dict, Optional, List
from datetime import datetime
import traceback


# ============================================================================
# Sensitive Data Masking
# ============================================================================

class SensitiveDataMasker:
    """
    Mask sensitive data in logs to prevent credential leakage.
    
    Masks:
    - Passwords
    - API keys and tokens
    - Full MAC addresses (keeps first 6 chars)
    - IP addresses (optional, configurable)
    - Email addresses (optional, configurable)
    """
    
    def __init__(self):
        # Patterns for sensitive data
        self._patterns = {
            'password': re.compile(r'(password["\']?\s*[:=]\s*["\']?)([^"\'}\s]+)', re.IGNORECASE),
            'api_key': re.compile(r'((?:api[_-]?key|token|secret)["\']?\s*[:=]\s*["\']?)([^"\'}\s]+)', re.IGNORECASE),
            'mac_address': re.compile(r'(([0-9A-Fa-f]{2})[:-]([0-9A-Fa-f]{2})[:-])([0-9A-Fa-f]{2}[:-]){3}([0-9A-Fa-f]{2})'),
            'authorization': re.compile(r'(Authorization["\']?\s*:\s*["\']?(?:Bearer|Basic)\s+)([^\s"\']+)', re.IGNORECASE),
        }
        
        # Optional patterns (disabled by default)
        self._optional_patterns = {
            'ip_address': re.compile(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'),
            'email': re.compile(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'),
        }
        
        self._mask_ips = os.environ.get('DASHBOARD_MASK_IPS', 'false').lower() == 'true'
        self._mask_emails = os.environ.get('DASHBOARD_MASK_EMAILS', 'false').lower() == 'true'
    
    def mask_string(self, text: str) -> str:
        """
        Mask sensitive data in a string.
        
        Args:
            text: Text to mask
            
        Returns:
            Text with sensitive data masked
        """
        if not text:
            return text
        
        result = text
        
        # Apply standard patterns
        for pattern_name, pattern in self._patterns.items():
            if pattern_name == 'mac_address':
                # Keep first 6 characters (OUI - first two octets), mask the rest
                result = pattern.sub(r'\2:\3:**:**:**', result)
            else:
                # Replace value with asterisks
                result = pattern.sub(r'\1********', result)
        
        # Apply optional patterns
        if self._mask_ips:
            pattern = self._optional_patterns['ip_address']
            result = pattern.sub('***.***.***.***', result)
        
        if self._mask_emails:
            pattern = self._optional_patterns['email']
            result = pattern.sub('***@***.***', result)
        
        return result
    
    def mask_dict(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Recursively mask sensitive data in a dictionary.
        
        Args:
            data: Dictionary to mask
            
        Returns:
            Dictionary with sensitive data masked
        """
        if not isinstance(data, dict):
            return data
        
        result = {}
        sensitive_keys = {
            'password', 'passwd', 'pwd', 'secret', 'token', 'api_key', 
            'apikey', 'auth', 'authorization', 'credential', 'key'
        }
        
        for key, value in data.items():
            # Check if key name indicates sensitive data
            if any(sensitive in key.lower() for sensitive in sensitive_keys):
                result[key] = '********'
            elif isinstance(value, dict):
                result[key] = self.mask_dict(value)
            elif isinstance(value, list):
                result[key] = [self.mask_dict(item) if isinstance(item, dict) else item for item in value]
            elif isinstance(value, str):
                result[key] = self.mask_string(value)
            else:
                result[key] = value
        
        return result


# Global masker instance
_masker = SensitiveDataMasker()


def mask_sensitive_data(data: Any) -> Any:
    """
    Mask sensitive data in any type of data.
    
    Args:
        data: Data to mask (string, dict, or other)
        
    Returns:
        Masked data
    """
    if isinstance(data, str):
        return _masker.mask_string(data)
    elif isinstance(data, dict):
        return _masker.mask_dict(data)
    else:
        return data


# ============================================================================
# Structured JSON Logger
# ============================================================================

class StructuredLogger:
    """
    Structured JSON logger for consistent, parseable logs.
    
    Each log entry includes:
    - timestamp (ISO 8601)
    - level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
    - message
    - context (optional extra fields)
    - exception info (if applicable)
    """
    
    def __init__(self, name: str, mask_sensitive: bool = True):
        self.logger = logging.getLogger(name)
        self.mask_sensitive = mask_sensitive
    
    def _format_log(self, level: str, message: str, context: Optional[Dict[str, Any]] = None,
                    exc_info: Optional[Exception] = None) -> str:
        """Format a log entry as JSON."""
        # Use timezone-aware UTC datetime
        from datetime import timezone
        timestamp = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
        
        entry = {
            'timestamp': timestamp,
            'level': level,
            'message': message,
            'logger': self.logger.name
        }
        
        # Add context if provided
        if context:
            if self.mask_sensitive:
                context = mask_sensitive_data(context)
            entry['context'] = context
        
        # Add exception info if provided
        if exc_info:
            entry['exception'] = {
                'type': type(exc_info).__name__,
                'message': str(exc_info),
                'traceback': traceback.format_exc()
            }
        
        return json.dumps(entry)
    
    def debug(self, message: str, **context):
        """Log debug message."""
        self.logger.debug(self._format_log('DEBUG', message, context))
    
    def info(self, message: str, **context):
        """Log info message."""
        self.logger.info(self._format_log('INFO', message, context))
    
    def warning(self, message: str, **context):
        """Log warning message."""
        self.logger.warning(self._format_log('WARNING', message, context))
    
    def error(self, message: str, exc_info: Optional[Exception] = None, **context):
        """Log error message."""
        self.logger.error(self._format_log('ERROR', message, context, exc_info))
    
    def critical(self, message: str, exc_info: Optional[Exception] = None, **context):
        """Log critical message."""
        self.logger.critical(self._format_log('CRITICAL', message, context, exc_info))


def get_structured_logger(name: str, mask_sensitive: bool = True) -> StructuredLogger:
    """
    Get a structured logger instance.
    
    Args:
        name: Logger name
        mask_sensitive: Whether to mask sensitive data
        
    Returns:
        StructuredLogger instance
    """
    return StructuredLogger(name, mask_sensitive)


# ============================================================================
# Audit Trail
# ============================================================================

class _AutoCloseFileHandler(logging.Handler):
    """Write each log record with a short-lived file handle to avoid Windows locks."""

    def __init__(self, log_file: str, mode: str = 'a', encoding: str = 'utf-8', max_bytes: int = 50 * 1024 * 1024, backup_count: int = 5):
        super().__init__()
        self._log_file = log_file
        self._mode = mode
        self._encoding = encoding
        self._max_bytes = max_bytes
        self._backup_count = backup_count

    def _rotate_if_needed(self) -> None:
        if not self._log_file:
            return
        try:
            if not os.path.exists(self._log_file):
                return
            size = os.path.getsize(self._log_file)
            if size < self._max_bytes:
                return

            log_dir = os.path.dirname(self._log_file) or '.'
            base, ext = os.path.splitext(os.path.basename(self._log_file))
            ext = ext or '.log'
            timestamp = datetime.utcnow().strftime('%Y%m%d-%H%M%S')
            rotated = os.path.join(log_dir, f"{base}.{timestamp}{ext}")
            try:
                os.replace(self._log_file, rotated)
            except OSError:
                rotated = os.path.join(log_dir, f"{base}.{timestamp}.{os.getpid()}{ext}")
                os.replace(self._log_file, rotated)

            pattern = re.compile(rf"^{re.escape(base)}\\.\\d{{8}}-\\d{{6}}.*{re.escape(ext)}$")
            candidates = []
            for name in os.listdir(log_dir):
                if pattern.match(name):
                    candidates.append(os.path.join(log_dir, name))
            candidates.sort(key=lambda p: os.path.getmtime(p), reverse=True)
            for old_path in candidates[self._backup_count:]:
                try:
                    os.remove(old_path)
                except OSError:
                    pass
        except Exception:
            return

    def emit(self, record: logging.LogRecord) -> None:
        try:
            self._rotate_if_needed()
            message = self.format(record)
            with open(self._log_file, self._mode, encoding=self._encoding) as handle:
                handle.write(message + '\n')
        except Exception:
            self.handleError(record)


class AuditTrail:
    """
    Audit trail for tracking configuration changes and important actions.
    
    Logs all modifications to:
    - Device configurations (nicknames, locations, tags)
    - System settings
    - User actions (if authentication is implemented)
    """
    
    def __init__(self, log_file: Optional[str] = None):
        self.logger = get_structured_logger('audit', mask_sensitive=False)
        
        # Set up file handler for audit log if path provided
        if log_file:
            self._setup_file_handler(log_file)
    
    def _setup_file_handler(self, log_file: str) -> None:
        """Set up dedicated file handler for audit logs."""
        try:
            # Create directory if needed
            log_dir = os.path.dirname(log_file)
            if log_dir and not os.path.exists(log_dir):
                os.makedirs(log_dir, exist_ok=True)
            
            # Clear any existing handlers to avoid duplicates
            self.logger.logger.handlers = []
            
            rotation = get_log_rotation_config()
            handler = _AutoCloseFileHandler(
                log_file,
                max_bytes=int(rotation.get('maxBytes', 50 * 1024 * 1024)),
                backup_count=int(rotation.get('backupCount', 5)),
            )
            handler.setLevel(logging.INFO)
            handler.setFormatter(logging.Formatter('%(message)s'))  # JSON already formatted
            self.logger.logger.addHandler(handler)
            self.logger.logger.setLevel(logging.INFO)
        except Exception as e:
            logging.error(f"Failed to set up audit log file handler: {e}")
    
    def log_device_update(self, device_id: str, changes: Dict[str, Any],
                         user: Optional[str] = None, ip_address: Optional[str] = None):
        """
        Log a device configuration update.
        
        Args:
            device_id: Device identifier (MAC address or ID)
            changes: Dictionary of changed fields and their new values
            user: Optional user who made the change
            ip_address: Optional IP address of requester
        """
        context = {
            'action': 'device_update',
            'device_id': device_id,
            'changes': changes
        }
        
        if user:
            context['user'] = user
        if ip_address:
            context['ip_address'] = ip_address
        
        self.logger.info(f"Device {device_id} updated", **context)
    
    def log_device_delete(self, device_id: str, user: Optional[str] = None,
                         ip_address: Optional[str] = None):
        """
        Log a device deletion.
        
        Args:
            device_id: Device identifier
            user: Optional user who made the change
            ip_address: Optional IP address of requester
        """
        context = {
            'action': 'device_delete',
            'device_id': device_id
        }
        
        if user:
            context['user'] = user
        if ip_address:
            context['ip_address'] = ip_address
        
        self.logger.info(f"Device {device_id} deleted", **context)
    
    def log_config_change(self, setting: str, old_value: Any, new_value: Any,
                         user: Optional[str] = None, ip_address: Optional[str] = None):
        """
        Log a configuration change.
        
        Args:
            setting: Setting name
            old_value: Previous value
            new_value: New value
            user: Optional user who made the change
            ip_address: Optional IP address of requester
        """
        context = {
            'action': 'config_change',
            'setting': setting,
            'old_value': old_value,
            'new_value': new_value
        }
        
        if user:
            context['user'] = user
        if ip_address:
            context['ip_address'] = ip_address
        
        self.logger.info(f"Configuration changed: {setting}", **context)
    
    def log_login_attempt(self, success: bool, user: Optional[str] = None,
                         ip_address: Optional[str] = None, reason: Optional[str] = None):
        """
        Log a login attempt.
        
        Args:
            success: Whether login succeeded
            user: Optional username
            ip_address: Optional IP address
            reason: Optional reason for failure
        """
        context = {
            'action': 'login_attempt',
            'success': success
        }
        
        if user:
            context['user'] = user
        if ip_address:
            context['ip_address'] = ip_address
        if reason:
            context['reason'] = reason
        
        level = 'info' if success else 'warning'
        message = f"Login {'succeeded' if success else 'failed'}"
        
        if success:
            self.logger.info(message, **context)
        else:
            self.logger.warning(message, **context)
    
    def log_api_access(self, endpoint: str, method: str, status_code: int,
                      user: Optional[str] = None, ip_address: Optional[str] = None,
                      duration_ms: Optional[float] = None):
        """
        Log an API access.
        
        Args:
            endpoint: API endpoint accessed
            method: HTTP method
            status_code: Response status code
            user: Optional user who made the request
            ip_address: Optional IP address
            duration_ms: Optional request duration in milliseconds
        """
        context = {
            'action': 'api_access',
            'endpoint': endpoint,
            'method': method,
            'status_code': status_code
        }
        
        if user:
            context['user'] = user
        if ip_address:
            context['ip_address'] = ip_address
        if duration_ms is not None:
            context['duration_ms'] = duration_ms
        
        # Log as warning if status indicates error
        if status_code >= 400:
            self.logger.warning(f"API access: {method} {endpoint} - {status_code}", **context)
        else:
            self.logger.info(f"API access: {method} {endpoint} - {status_code}", **context)


# Global audit trail instance
_audit_trail = None


def get_audit_trail() -> AuditTrail:
    """
    Get the global audit trail instance.
    
    Returns:
        AuditTrail instance
    """
    global _audit_trail
    if _audit_trail is None:
        # Get log file path from environment or use default
        log_file = os.environ.get('DASHBOARD_AUDIT_LOG')
        if not log_file:
            # Default to var/log/audit.log relative to project root
            base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            log_file = os.path.join(base_dir, 'var', 'log', 'audit.log')
        
        _audit_trail = AuditTrail(log_file)
    
    return _audit_trail


# ============================================================================
# Log Rotation Configuration
# ============================================================================

def get_log_rotation_config() -> Dict[str, Any]:
    """
    Get recommended log rotation configuration.
    
    Returns:
        Dictionary with log rotation settings
    """
    return {
        'maxBytes': 50 * 1024 * 1024,  # 50 MB
        'backupCount': 5,  # Keep 5 backup files
        'encoding': 'utf-8',
        'delay': False
    }


def configure_log_rotation(logger: logging.Logger, log_file: str) -> None:
    """
    Configure log rotation for a logger.
    
    Args:
        logger: Logger instance to configure
        log_file: Path to log file
    """
    from logging.handlers import RotatingFileHandler
    
    config = get_log_rotation_config()
    
    # Create directory if needed
    log_dir = os.path.dirname(log_file)
    if log_dir and not os.path.exists(log_dir):
        os.makedirs(log_dir, exist_ok=True)
    
    handler = RotatingFileHandler(
        log_file,
        maxBytes=config['maxBytes'],
        backupCount=config['backupCount'],
        encoding=config['encoding']
    )
    
    # Set formatter
    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    handler.setFormatter(formatter)
    
    logger.addHandler(handler)
    logger.info(f"Log rotation configured for {log_file}")

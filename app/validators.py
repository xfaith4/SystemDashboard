"""
Input validation utilities for API endpoints.

This module provides validation functions for common input types:
- Date/time parameters
- MAC addresses
- IP addresses
- Pagination parameters
- Severity levels
"""

import re
from datetime import datetime, timedelta
from typing import Optional, Tuple


class ValidationError(Exception):
    """Exception raised for validation errors."""
    pass


def validate_mac_address(mac: str) -> str:
    """
    Validate and normalize a MAC address.
    
    Args:
        mac: MAC address string in various formats
        
    Returns:
        Normalized MAC address in XX:XX:XX:XX:XX:XX format
        
    Raises:
        ValidationError: If MAC address is invalid
    """
    if not mac:
        raise ValidationError("MAC address is required")
        
    # Remove common separators and convert to uppercase
    mac_clean = mac.upper().replace(':', '').replace('-', '').replace('.', '')
    
    # Validate length
    if len(mac_clean) != 12:
        raise ValidationError(f"Invalid MAC address length: {mac}")
        
    # Validate hex characters
    if not all(c in '0123456789ABCDEF' for c in mac_clean):
        raise ValidationError(f"Invalid MAC address format: {mac}")
        
    # Format as XX:XX:XX:XX:XX:XX
    return ':'.join(mac_clean[i:i+2] for i in range(0, 12, 2))


def validate_ip_address(ip: str, allow_private: bool = True) -> str:
    """
    Validate an IPv4 address.
    
    Args:
        ip: IP address string
        allow_private: Whether to allow private IP ranges
        
    Returns:
        Validated IP address
        
    Raises:
        ValidationError: If IP address is invalid
    """
    if not ip:
        raise ValidationError("IP address is required")
        
    # Split into octets
    parts = ip.split('.')
    if len(parts) != 4:
        raise ValidationError(f"Invalid IP address format: {ip}")
        
    # Validate each octet
    try:
        octets = [int(p) for p in parts]
    except ValueError:
        raise ValidationError(f"Invalid IP address format: {ip}")
        
    for octet in octets:
        if octet < 0 or octet > 255:
            raise ValidationError(f"Invalid IP address range: {ip}")
            
    # Check for private IP ranges if not allowed
    if not allow_private:
        first = octets[0]
        second = octets[1]
        
        # 10.0.0.0/8
        if first == 10:
            raise ValidationError(f"Private IP address not allowed: {ip}")
            
        # 172.16.0.0/12
        if first == 172 and 16 <= second <= 31:
            raise ValidationError(f"Private IP address not allowed: {ip}")
            
        # 192.168.0.0/16
        if first == 192 and second == 168:
            raise ValidationError(f"Private IP address not allowed: {ip}")
            
    return ip


def validate_pagination(page: Optional[str], limit: Optional[str], 
                       max_limit: int = 500) -> Tuple[int, int]:
    """
    Validate and normalize pagination parameters.
    
    Args:
        page: Page number (1-based)
        limit: Items per page
        max_limit: Maximum allowed limit
        
    Returns:
        Tuple of (page, limit) as integers
        
    Raises:
        ValidationError: If parameters are invalid
    """
    # Default values
    page_int = 1
    limit_int = 50
    
    # Validate page
    if page is not None:
        try:
            page_int = int(page)
            if page_int < 1:
                raise ValidationError("Page must be >= 1")
        except ValueError:
            raise ValidationError(f"Invalid page number: {page}")
            
    # Validate limit
    if limit is not None:
        try:
            limit_int = int(limit)
            if limit_int < 1:
                raise ValidationError("Limit must be >= 1")
            if limit_int > max_limit:
                limit_int = max_limit  # Cap at max, don't error
        except ValueError:
            raise ValidationError(f"Invalid limit: {limit}")
            
    return page_int, limit_int


def validate_date_range(start_date: Optional[str], end_date: Optional[str],
                       max_range_days: int = 90) -> Tuple[Optional[datetime], Optional[datetime]]:
    """
    Validate date range parameters.
    
    Args:
        start_date: Start date in ISO format (YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS)
        end_date: End date in ISO format
        max_range_days: Maximum allowed range in days
        
    Returns:
        Tuple of (start_datetime, end_datetime)
        
    Raises:
        ValidationError: If dates are invalid
    """
    start_dt = None
    end_dt = None
    
    if start_date:
        try:
            # Try parsing as ISO datetime
            if 'T' in start_date:
                start_dt = datetime.fromisoformat(start_date.replace('Z', '+00:00'))
            else:
                start_dt = datetime.strptime(start_date, '%Y-%m-%d')
        except ValueError:
            raise ValidationError(f"Invalid start date format: {start_date}")
            
    if end_date:
        try:
            if 'T' in end_date:
                end_dt = datetime.fromisoformat(end_date.replace('Z', '+00:00'))
            else:
                end_dt = datetime.strptime(end_date, '%Y-%m-%d')
        except ValueError:
            raise ValidationError(f"Invalid end date format: {end_date}")
            
    # Validate range
    if start_dt and end_dt:
        if start_dt > end_dt:
            raise ValidationError("Start date must be before end date")
            
        range_days = (end_dt - start_dt).days
        if range_days > max_range_days:
            raise ValidationError(f"Date range too large (max {max_range_days} days)")
            
    return start_dt, end_dt


def validate_severity(severity: str, allowed_levels: Optional[list] = None) -> str:
    """
    Validate severity level.
    
    Args:
        severity: Severity level string
        allowed_levels: List of allowed severity levels (default: common levels)
        
    Returns:
        Normalized severity level (lowercase)
        
    Raises:
        ValidationError: If severity is invalid
    """
    if allowed_levels is None:
        allowed_levels = [
            'emergency', 'alert', 'critical', 'error', 'warning',
            'notice', 'informational', 'info', 'debug'
        ]
        
    severity_lower = severity.lower()
    if severity_lower not in allowed_levels:
        raise ValidationError(
            f"Invalid severity level: {severity}. "
            f"Allowed: {', '.join(allowed_levels)}"
        )
        
    return severity_lower


def validate_sort_field(field: str, allowed_fields: list) -> str:
    """
    Validate sort field name.
    
    Args:
        field: Field name to sort by
        allowed_fields: List of allowed field names
        
    Returns:
        Validated field name
        
    Raises:
        ValidationError: If field is not allowed
    """
    if field not in allowed_fields:
        raise ValidationError(
            f"Invalid sort field: {field}. "
            f"Allowed: {', '.join(allowed_fields)}"
        )
        
    return field


def validate_sort_order(order: str) -> str:
    """
    Validate sort order.
    
    Args:
        order: Sort order ('asc' or 'desc')
        
    Returns:
        Normalized sort order (lowercase)
        
    Raises:
        ValidationError: If order is invalid
    """
    order_lower = order.lower()
    if order_lower not in ['asc', 'desc']:
        raise ValidationError(f"Invalid sort order: {order}. Use 'asc' or 'desc'")
        
    return order_lower


def validate_tags(tags: str, max_tags: int = 10) -> list:
    """
    Validate and parse comma-separated tags.
    
    Args:
        tags: Comma-separated tag string
        max_tags: Maximum number of tags allowed
        
    Returns:
        List of validated tag strings
        
    Raises:
        ValidationError: If tags are invalid
    """
    if not tags:
        return []
        
    # Split and clean tags
    tag_list = [t.strip() for t in tags.split(',') if t.strip()]
    
    if len(tag_list) > max_tags:
        raise ValidationError(f"Too many tags (max {max_tags})")
        
    # Validate each tag
    for tag in tag_list:
        if len(tag) > 50:
            raise ValidationError(f"Tag too long: {tag}")
            
        # Allow alphanumeric, dash, underscore
        if not re.match(r'^[a-zA-Z0-9_-]+$', tag):
            raise ValidationError(f"Invalid tag format: {tag}")
            
    return tag_list


def sanitize_sql_like_pattern(pattern: str) -> str:
    """
    Sanitize a string for use in SQL LIKE patterns.
    
    Args:
        pattern: Input pattern
        
    Returns:
        Sanitized pattern with SQL wildcards escaped
    """
    # Escape SQL special characters
    pattern = pattern.replace('%', '\\%')
    pattern = pattern.replace('_', '\\_')
    pattern = pattern.replace('[', '\\[')
    pattern = pattern.replace(']', '\\]')
    
    return pattern

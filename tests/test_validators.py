"""
Test suite for input validation utilities.
"""
import os
import sys
import pytest
from datetime import datetime, timedelta

# Add the app directory to the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from app.validators import (
    ValidationError, validate_mac_address, validate_ip_address,
    validate_pagination, validate_date_range, validate_severity,
    validate_sort_field, validate_sort_order, validate_tags,
    sanitize_sql_like_pattern
)


class TestMACAddressValidation:
    """Test MAC address validation."""
    
    def test_valid_mac_colon_format(self):
        """Test validation of MAC in XX:XX:XX:XX:XX:XX format."""
        result = validate_mac_address('AA:BB:CC:DD:EE:FF')
        assert result == 'AA:BB:CC:DD:EE:FF'
        
    def test_valid_mac_dash_format(self):
        """Test validation of MAC in XX-XX-XX-XX-XX-XX format."""
        result = validate_mac_address('AA-BB-CC-DD-EE-FF')
        assert result == 'AA:BB:CC:DD:EE:FF'
        
    def test_valid_mac_no_separator(self):
        """Test validation of MAC without separators."""
        result = validate_mac_address('AABBCCDDEEFF')
        assert result == 'AA:BB:CC:DD:EE:FF'
        
    def test_valid_mac_lowercase(self):
        """Test validation normalizes to uppercase."""
        result = validate_mac_address('aa:bb:cc:dd:ee:ff')
        assert result == 'AA:BB:CC:DD:EE:FF'
        
    def test_invalid_mac_length(self):
        """Test validation rejects incorrect length."""
        with pytest.raises(ValidationError, match="Invalid MAC address length"):
            validate_mac_address('AA:BB:CC')
            
    def test_invalid_mac_characters(self):
        """Test validation rejects non-hex characters."""
        with pytest.raises(ValidationError, match="Invalid MAC address format"):
            validate_mac_address('GG:HH:II:JJ:KK:LL')
            
    def test_empty_mac(self):
        """Test validation rejects empty MAC."""
        with pytest.raises(ValidationError, match="MAC address is required"):
            validate_mac_address('')


class TestIPAddressValidation:
    """Test IP address validation."""
    
    def test_valid_public_ip(self):
        """Test validation of public IP."""
        result = validate_ip_address('8.8.8.8')
        assert result == '8.8.8.8'
        
    def test_valid_private_ip(self):
        """Test validation of private IP when allowed."""
        result = validate_ip_address('192.168.1.1', allow_private=True)
        assert result == '192.168.1.1'
        
    def test_private_ip_rejected(self):
        """Test validation rejects private IP when not allowed."""
        with pytest.raises(ValidationError, match="Private IP address not allowed"):
            validate_ip_address('192.168.1.1', allow_private=False)
            
    def test_private_ip_10_network(self):
        """Test validation detects 10.0.0.0/8 network."""
        with pytest.raises(ValidationError, match="Private IP address not allowed"):
            validate_ip_address('10.0.0.1', allow_private=False)
            
    def test_private_ip_172_network(self):
        """Test validation detects 172.16.0.0/12 network."""
        with pytest.raises(ValidationError, match="Private IP address not allowed"):
            validate_ip_address('172.16.0.1', allow_private=False)
            
    def test_invalid_ip_format(self):
        """Test validation rejects invalid format."""
        with pytest.raises(ValidationError, match="Invalid IP address range"):
            validate_ip_address('256.1.1.1')
            
    def test_invalid_ip_octet_count(self):
        """Test validation rejects wrong number of octets."""
        with pytest.raises(ValidationError, match="Invalid IP address format"):
            validate_ip_address('192.168.1')
            
    def test_empty_ip(self):
        """Test validation rejects empty IP."""
        with pytest.raises(ValidationError, match="IP address is required"):
            validate_ip_address('')


class TestPaginationValidation:
    """Test pagination parameter validation."""
    
    def test_default_values(self):
        """Test default pagination values."""
        page, limit = validate_pagination(None, None)
        assert page == 1
        assert limit == 50
        
    def test_valid_pagination(self):
        """Test validation with valid parameters."""
        page, limit = validate_pagination('2', '100')
        assert page == 2
        assert limit == 100
        
    def test_limit_capped_at_max(self):
        """Test limit is capped at maximum."""
        page, limit = validate_pagination('1', '1000', max_limit=500)
        assert limit == 500
        
    def test_invalid_page_string(self):
        """Test validation rejects non-numeric page."""
        with pytest.raises(ValidationError, match="Invalid page number"):
            validate_pagination('abc', '50')
            
    def test_invalid_limit_string(self):
        """Test validation rejects non-numeric limit."""
        with pytest.raises(ValidationError, match="Invalid limit"):
            validate_pagination('1', 'xyz')
            
    def test_page_less_than_one(self):
        """Test validation rejects page < 1."""
        with pytest.raises(ValidationError, match="Page must be >= 1"):
            validate_pagination('0', '50')
            
    def test_limit_less_than_one(self):
        """Test validation rejects limit < 1."""
        with pytest.raises(ValidationError, match="Limit must be >= 1"):
            validate_pagination('1', '0')


class TestDateRangeValidation:
    """Test date range validation."""
    
    def test_valid_date_range(self):
        """Test validation with valid date range."""
        start, end = validate_date_range('2024-01-01', '2024-01-31')
        assert start.year == 2024
        assert start.month == 1
        assert start.day == 1
        assert end.year == 2024
        assert end.month == 1
        assert end.day == 31
        
    def test_valid_datetime_range(self):
        """Test validation with datetime strings."""
        start, end = validate_date_range('2024-01-01T00:00:00', '2024-01-01T23:59:59')
        assert start.hour == 0
        assert end.hour == 23
        
    def test_none_dates(self):
        """Test validation with None dates."""
        start, end = validate_date_range(None, None)
        assert start is None
        assert end is None
        
    def test_invalid_start_date_format(self):
        """Test validation rejects invalid start date."""
        with pytest.raises(ValidationError, match="Invalid start date format"):
            validate_date_range('not-a-date', '2024-01-31')
            
    def test_invalid_end_date_format(self):
        """Test validation rejects invalid end date."""
        with pytest.raises(ValidationError, match="Invalid end date format"):
            validate_date_range('2024-01-01', 'invalid')
            
    def test_start_after_end(self):
        """Test validation rejects start after end."""
        with pytest.raises(ValidationError, match="Start date must be before end date"):
            validate_date_range('2024-02-01', '2024-01-01')
            
    def test_range_too_large(self):
        """Test validation rejects range larger than max."""
        start = '2024-01-01'
        end = '2024-06-01'  # 5 months = ~150 days
        with pytest.raises(ValidationError, match="Date range too large"):
            validate_date_range(start, end, max_range_days=90)


class TestSeverityValidation:
    """Test severity level validation."""
    
    def test_valid_severity_levels(self):
        """Test validation of standard severity levels."""
        for level in ['emergency', 'alert', 'critical', 'error', 'warning']:
            result = validate_severity(level)
            assert result == level
            
    def test_severity_normalized_to_lowercase(self):
        """Test severity is normalized to lowercase."""
        result = validate_severity('ERROR')
        assert result == 'error'
        
    def test_info_shorthand(self):
        """Test 'info' is accepted as informational."""
        result = validate_severity('info')
        assert result == 'info'
        
    def test_invalid_severity(self):
        """Test validation rejects invalid severity."""
        with pytest.raises(ValidationError, match="Invalid severity level"):
            validate_severity('invalid_level')
            
    def test_custom_allowed_levels(self):
        """Test validation with custom allowed levels."""
        result = validate_severity('high', allowed_levels=['low', 'medium', 'high'])
        assert result == 'high'


class TestSortValidation:
    """Test sort field and order validation."""
    
    def test_valid_sort_field(self):
        """Test validation of allowed sort field."""
        result = validate_sort_field('created_at', ['created_at', 'updated_at', 'name'])
        assert result == 'created_at'
        
    def test_invalid_sort_field(self):
        """Test validation rejects invalid field."""
        with pytest.raises(ValidationError, match="Invalid sort field"):
            validate_sort_field('invalid_field', ['name', 'date'])
            
    def test_valid_sort_order_asc(self):
        """Test validation of ascending order."""
        result = validate_sort_order('asc')
        assert result == 'asc'
        
    def test_valid_sort_order_desc(self):
        """Test validation of descending order."""
        result = validate_sort_order('DESC')
        assert result == 'desc'
        
    def test_invalid_sort_order(self):
        """Test validation rejects invalid order."""
        with pytest.raises(ValidationError, match="Invalid sort order"):
            validate_sort_order('random')


class TestTagsValidation:
    """Test tags validation."""
    
    def test_valid_tags(self):
        """Test validation of comma-separated tags."""
        result = validate_tags('iot,critical,network')
        assert result == ['iot', 'critical', 'network']
        
    def test_tags_trimmed(self):
        """Test tags are trimmed of whitespace."""
        result = validate_tags('  iot  , critical , network  ')
        assert result == ['iot', 'critical', 'network']
        
    def test_empty_tags(self):
        """Test empty tags returns empty list."""
        result = validate_tags('')
        assert result == []
        
    def test_too_many_tags(self):
        """Test validation rejects too many tags."""
        tags = ','.join(f'tag{i}' for i in range(20))
        with pytest.raises(ValidationError, match="Too many tags"):
            validate_tags(tags, max_tags=10)
            
    def test_tag_too_long(self):
        """Test validation rejects overly long tags."""
        long_tag = 'a' * 100
        with pytest.raises(ValidationError, match="Tag too long"):
            validate_tags(long_tag)
            
    def test_invalid_tag_characters(self):
        """Test validation rejects invalid characters."""
        with pytest.raises(ValidationError, match="Invalid tag format"):
            validate_tags('tag with spaces')


class TestSQLSanitization:
    """Test SQL LIKE pattern sanitization."""
    
    def test_sanitize_percent(self):
        """Test percent sign is escaped."""
        result = sanitize_sql_like_pattern('100%')
        assert result == '100\\%'
        
    def test_sanitize_underscore(self):
        """Test underscore is escaped."""
        result = sanitize_sql_like_pattern('my_table')
        assert result == 'my\\_table'
        
    def test_sanitize_brackets(self):
        """Test brackets are escaped."""
        result = sanitize_sql_like_pattern('[test]')
        assert result == '\\[test\\]'
        
    def test_sanitize_combined(self):
        """Test multiple special characters are escaped."""
        result = sanitize_sql_like_pattern('test_%[name]')
        assert result == 'test\\_\\%\\[name\\]'


if __name__ == '__main__':
    pytest.main([__file__, '-v'])

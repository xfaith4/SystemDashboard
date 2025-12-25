"""
Router log testing functionality - Creates test logs and validates parsing.
"""
import os
import tempfile
import subprocess
import sys
from pathlib import Path

# Add app directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from app import get_router_logs


def create_test_router_logs():
    """Create realistic router log file for testing."""
    log_content = """
2024-01-15 08:30:15 INFO DHCP assigned IP 192.168.1.100 to MAC 00:11:22:33:44:55
2024-01-15 08:30:45 WARN Failed login attempt from 192.168.1.50
2024-01-15 08:31:00 INFO Firewall blocked connection to port 22 from 10.0.0.5
2024-01-15 08:31:30 ERROR WAN connection lost - attempting reconnection
2024-01-15 08:31:45 INFO WAN connection restored
2024-01-15 08:32:00 INFO Wireless client connected: 192.168.1.101 (aa:bb:cc:dd:ee:ff)
2024-01-15 08:32:15 WARN High bandwidth usage detected from 192.168.1.100
2024-01-15 08:32:30 INFO Automatic firmware update available
2024-01-15 08:32:45 ERROR DNS resolution failed for external.domain.com
2024-01-15 08:33:00 INFO Port forwarding rule activated for 192.168.1.105:8080
""".strip()
    
    with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.log') as f:
        f.write(log_content)
        return f.name


def test_router_log_parsing():
    """Test router log parsing with realistic data."""
    log_file = create_test_router_logs()
    
    try:
        # Set environment variable
        os.environ['ROUTER_LOG_PATH'] = log_file
        
        # Test log retrieval
        logs = get_router_logs(max_lines=20)
        
        print(f"Retrieved {len(logs)} log entries")
        
        # Validate log structure
        assert len(logs) > 0, "Should retrieve log entries"
        
        # Check first log entry
        first_log = logs[0]
        assert 'time' in first_log, "Log should have time field"
        assert 'level' in first_log, "Log should have level field"  
        assert 'message' in first_log, "Log should have message field"
        
        print("First log entry:")
        print(f"  Time: {first_log['time']}")
        print(f"  Level: {first_log['level']}")
        print(f"  Message: {first_log['message']}")
        
        # Validate specific entries
        dhcp_logs = [log for log in logs if 'DHCP' in log['message']]
        assert len(dhcp_logs) > 0, "Should find DHCP logs"
        
        error_logs = [log for log in logs if log['level'] == 'ERROR']
        assert len(error_logs) > 0, "Should find ERROR logs"
        
        # Test filtering by number of lines
        limited_logs = get_router_logs(max_lines=5)
        assert len(limited_logs) <= 5, "Should respect max_lines parameter"
        
        print("✓ Router log parsing test passed")
        
    finally:
        # Cleanup
        os.unlink(log_file)
        if 'ROUTER_LOG_PATH' in os.environ:
            del os.environ['ROUTER_LOG_PATH']


def test_router_log_edge_cases():
    """Test router log parsing with edge cases."""
    edge_case_content = """
2024-01-15 08:30:15 INFO Normal log entry
Incomplete line without timestamp
2024-01-15 08:31:00
2024-01-15 08:32:00 WARN Message with multiple spaces    here
2024-01-15 08:33:00 ERROR Message with "quotes" and special chars !@#$%
""".strip()
    
    with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.log') as f:
        f.write(edge_case_content)
        log_file = f.name
    
    try:
        os.environ['ROUTER_LOG_PATH'] = log_file
        
        logs = get_router_logs()
        print(f"Edge case test: Retrieved {len(logs)} log entries")
        
        # Find the incomplete line
        incomplete_lines = [log for log in logs if log['time'] == '' and log['level'] == '']
        assert len(incomplete_lines) > 0, "Should handle incomplete lines"
        
        print("✓ Router log edge cases test passed")
        
    finally:
        os.unlink(log_file)
        if 'ROUTER_LOG_PATH' in os.environ:
            del os.environ['ROUTER_LOG_PATH']


def test_missing_router_log_file():
    """Test behavior when router log file doesn't exist."""
    os.environ['ROUTER_LOG_PATH'] = '/nonexistent/path/router.log'
    
    try:
        logs = get_router_logs()
        assert logs == [], "Should return empty list for missing file"
        print("✓ Missing router log file test passed")
        
    finally:
        if 'ROUTER_LOG_PATH' in os.environ:
            del os.environ['ROUTER_LOG_PATH']


if __name__ == '__main__':
    print("Running router log functionality tests...")
    test_router_log_parsing()
    test_router_log_edge_cases()
    test_missing_router_log_file()
    print("All router log tests passed! ✓")
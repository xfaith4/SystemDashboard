# Phase 1: Core Stability & Error Handling - Implementation Guide

This document describes the Phase 1 improvements implemented for the SystemDashboard project, focusing on core stability, error handling, and API robustness.

## Overview

Phase 1 delivers significant improvements to:
- Database connection management and performance
- Input validation and error handling
- API consistency and reliability
- Response caching and CORS support

## Database Improvements

### Connection Pooling (`app/db_manager.py`)

The new `DatabaseManager` class provides robust SQLite connection management:

```python
from app.db_manager import get_db_manager

# Get the database manager
db_manager = get_db_manager('/path/to/database.db')

# Use connection pooling
with db_manager.get_connection() as conn:
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM devices")
    results = cursor.fetchall()
```

**Features:**
- Thread-safe connection pooling (max 5 connections by default)
- WAL mode enabled for better concurrent access
- Automatic connection reuse and cleanup
- Foreign key constraints enabled
- Configurable timeouts (10 seconds default)

### Retry Logic

Database operations automatically retry on transient failures:

```python
# Automatically retries on "database is locked" errors
cursor = db_manager.execute_with_retry(
    "INSERT INTO devices (mac_address) VALUES (?)",
    ('AA:BB:CC:DD:EE:FF',)
)
```

**Features:**
- Exponential backoff (0.1s, 0.2s, 0.4s, etc.)
- Configurable max retries (3 by default)
- Automatic rollback on errors

### Schema Validation

Ensure database schema is valid at startup:

```python
is_valid, missing = db_manager.validate_schema()
if not is_valid:
    print(f"Missing database objects: {', '.join(missing)}")
```

**Checks:**
- Required tables: devices, device_snapshots, device_alerts, ai_feedback, syslog_recent
- Required views: lan_summary_stats, device_alerts_active

### Performance Indexes

Performance indexes are applied via migrations:

```python
# Apply migrations from directory
applied, errors = db_manager.apply_migrations('./migrations')
print(f"Applied {applied} migrations")
```

**Indexes added:**
- `idx_devices_mac` - Fast MAC address lookups
- `idx_devices_active` - Active device queries
- `idx_devices_last_seen` - Recent device queries
- `idx_device_snapshots_device_time` - Device timeline queries
- `idx_device_alerts_severity` - Alert severity filtering
- And more...

## Input Validation (`app/validators.py`)

Comprehensive validation functions for API inputs:

### MAC Address Validation

```python
from app.validators import validate_mac_address, ValidationError

try:
    # Accepts various formats: XX:XX:XX:XX:XX:XX, XX-XX-XX-XX-XX-XX, XXXXXXXXXXXX
    normalized = validate_mac_address('aa:bb:cc:dd:ee:ff')
    # Returns: 'AA:BB:CC:DD:EE:FF'
except ValidationError as e:
    print(f"Invalid MAC: {e}")
```

### IP Address Validation

```python
from app.validators import validate_ip_address

# Validate with private IP detection
ip = validate_ip_address('192.168.1.1', allow_private=True)

# Reject private IPs
try:
    validate_ip_address('192.168.1.1', allow_private=False)
except ValidationError:
    print("Private IP not allowed")
```

### Pagination Validation

```python
from app.validators import validate_pagination

# Validate and cap pagination parameters
page, limit = validate_pagination(
    page='2',
    limit='1000',  # Will be capped at max_limit
    max_limit=500
)
# Returns: (2, 500)
```

### Date Range Validation

```python
from app.validators import validate_date_range

start, end = validate_date_range(
    '2024-01-01',
    '2024-01-31',
    max_range_days=90
)
```

### Other Validators

- `validate_severity()` - Syslog severity levels
- `validate_sort_field()` - Safe sort field names
- `validate_sort_order()` - ASC/DESC validation
- `validate_tags()` - Comma-separated tags
- `sanitize_sql_like_pattern()` - Escape SQL wildcards

## API Utilities (`app/api_utils.py`)

Consistent API responses and error handling:

### Error Responses

```python
from app.api_utils import error_response, APIError

# Simple error response
return error_response("Invalid input", 400)

# Error with additional context
return error_response(
    "Validation failed",
    422,
    field='email',
    reason='Invalid format'
)

# Raise API errors
raise APIError("Resource not found", 404)
```

### Success Responses

```python
from app.api_utils import success_response

# Simple success
return success_response()

# With data
return success_response(data={'id': 123, 'name': 'Test'})

# With message
return success_response(message="Operation completed successfully")
```

### Error Handling Decorator

```python
from app.api_utils import handle_api_errors
from app.validators import ValidationError

@app.route('/api/endpoint')
@handle_api_errors
def my_endpoint():
    # ValidationError and APIError are automatically caught
    # and formatted as JSON error responses
    validate_something()
    return jsonify({'result': 'ok'})
```

### JSON Validation Decorators

```python
from app.api_utils import require_json, validate_required_fields

@app.route('/api/endpoint', methods=['POST'])
@require_json  # Enforces Content-Type: application/json
@validate_required_fields(['name', 'email'])  # Validates required fields
@handle_api_errors
def create_user():
    data = request.get_json()
    # name and email are guaranteed to exist
    return success_response(data={'id': create_user(data)})
```

### Response Caching

```python
from app.api_utils import cache_response

@app.route('/api/expensive-query')
@cache_response(ttl_seconds=600)  # Cache for 10 minutes
@handle_api_errors
def expensive_query():
    # This function only runs if cache is empty or expired
    result = perform_expensive_operation()
    return jsonify(result)
```

**Features:**
- In-memory cache with TTL
- Automatic cache cleanup
- Per-endpoint caching
- `clear_cache()` function for manual clearing

### CORS Support

```python
from app.api_utils import with_cors

@app.route('/api/endpoint')
@with_cors
def my_endpoint():
    return jsonify({'result': 'ok'})
```

**Features:**
- Adds CORS headers to responses
- Handles preflight OPTIONS requests
- Configurable for cross-origin requests

## Usage Examples

### Complete API Endpoint

```python
from flask import request, jsonify
from app.api_utils import (
    handle_api_errors, require_json, validate_required_fields,
    success_response, with_cors, cache_response
)
from app.validators import validate_mac_address, validate_tags

@app.route('/api/devices', methods=['POST'])
@with_cors
@require_json
@validate_required_fields(['mac_address'])
@handle_api_errors
def create_device():
    data = request.get_json()
    
    # Validate inputs
    mac = validate_mac_address(data['mac_address'])
    tags = validate_tags(data.get('tags', ''))
    
    # Create device
    device_id = insert_device(mac, tags)
    
    return success_response(
        data={'id': device_id, 'mac': mac},
        message="Device created successfully"
    )

@app.route('/api/devices')
@with_cors
@cache_response(ttl_seconds=300)
@handle_api_errors
def list_devices():
    from app.validators import validate_pagination
    
    # Validate pagination
    page, limit = validate_pagination(
        request.args.get('page'),
        request.args.get('limit')
    )
    
    # Query with pagination
    devices = query_devices(page, limit)
    
    return jsonify({
        'devices': devices,
        'page': page,
        'limit': limit
    })
```

### Database Operations

```python
from app.db_manager import get_db_manager

db_manager = get_db_manager('./var/system_dashboard.db')

# Validate schema on startup
is_valid, missing = db_manager.validate_schema()
if not is_valid:
    logger.error(f"Database schema invalid. Missing: {', '.join(missing)}")
    sys.exit(1)

# Apply migrations
applied, errors = db_manager.apply_migrations('./migrations')
logger.info(f"Applied {applied} migrations")

# Use connection pooling
with db_manager.get_connection() as conn:
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM devices WHERE is_active = 1")
    active_devices = cursor.fetchall()

# Retry on database lock
cursor = db_manager.execute_with_retry(
    "UPDATE devices SET last_seen_utc = ? WHERE device_id = ?",
    (datetime.now(), device_id)
)
```

## Testing

All new features have comprehensive test coverage:

```bash
# Run all tests
pytest tests/

# Run specific test suites
pytest tests/test_db_manager.py      # 23 tests
pytest tests/test_validators.py       # 49 tests
pytest tests/test_api_utils.py        # 23 tests
```

**Total test coverage:** 233 tests passing

## Migration Guide

### Updating Existing Endpoints

To add validation and error handling to existing endpoints:

1. Add the `@handle_api_errors` decorator
2. Add validation for inputs using `validators.py` functions
3. Replace manual error responses with `error_response()`
4. Use `success_response()` for consistent success responses

**Before:**
```python
@app.route('/api/device/<device_id>')
def get_device(device_id):
    try:
        device = query_device(device_id)
        if not device:
            return jsonify({'error': 'Not found'}), 404
        return jsonify(device)
    except Exception as e:
        return jsonify({'error': str(e)}), 500
```

**After:**
```python
from app.api_utils import handle_api_errors, error_response
from app.validators import ValidationError

@app.route('/api/device/<device_id>')
@handle_api_errors
def get_device(device_id):
    device = query_device(device_id)
    if not device:
        raise APIError('Device not found', 404)
    return jsonify(device)
```

### Using Database Manager

Replace direct SQLite connections with the database manager:

**Before:**
```python
conn = sqlite3.connect('./var/system_dashboard.db')
cursor = conn.cursor()
cursor.execute("SELECT * FROM devices")
results = cursor.fetchall()
conn.close()
```

**After:**
```python
from app.db_manager import get_db_manager

db_manager = get_db_manager('./var/system_dashboard.db')
with db_manager.get_connection() as conn:
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM devices")
    results = cursor.fetchall()
```

## Performance Considerations

### Connection Pooling

- Default pool size: 5 connections
- Adjust based on concurrent request load
- Monitor for "All connections in use" log messages

### Caching

- Cache expensive queries (>100ms)
- Set appropriate TTL based on data freshness requirements
- Monitor cache hit rate in logs
- Clear cache after data modifications if needed

### Indexes

- Migrations automatically add performance indexes
- Monitor slow query log (if enabled)
- Add custom indexes for application-specific queries

## Security

### Input Validation

All user inputs are validated before database queries:
- MAC addresses are normalized and validated
- IP addresses are checked for valid format
- SQL LIKE patterns are sanitized to prevent injection
- Date ranges are validated to prevent excessive queries

### SQL Injection Prevention

- All queries use parameterized statements
- `sanitize_sql_like_pattern()` for LIKE queries
- No string concatenation in SQL queries

### CORS Configuration

Configure CORS based on deployment:
- Development: Allow all origins (`*`)
- Production: Restrict to specific domains
- Use `@with_cors` decorator or configure app-wide

## Troubleshooting

### Database Locked Errors

If you still see "database is locked" errors:
1. Increase connection timeout
2. Reduce concurrent operations
3. Check for long-running transactions
4. Verify WAL mode is enabled

### Cache Issues

If cached data is stale:
1. Reduce TTL for that endpoint
2. Call `clear_cache()` after data updates
3. Use cache key that includes timestamp parameter

### Validation Errors

If validation is too strict:
1. Check validation parameters (e.g., `allow_private` for IPs)
2. Adjust max limits (pagination, date ranges)
3. Add custom validation functions if needed

## Next Steps

Phase 1 completion enables:
- Phase 2: UI Polish & Professionalism
- Phase 3: Security & Hardening
- Phase 4: Performance & Scalability

See ROADMAP.md for details on upcoming phases.

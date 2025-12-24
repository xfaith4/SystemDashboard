# SystemDashboard - API Reference

This document provides a comprehensive reference for all REST API endpoints exposed by SystemDashboard.

## Table of Contents

- [Base URL](#base-url)
- [Authentication](#authentication)
- [Common Headers](#common-headers)
- [Error Responses](#error-responses)
- [Rate Limiting](#rate-limiting)
- [Dashboard APIs](#dashboard-apis)
- [Events APIs](#events-apis)
- [Router APIs](#router-apis)
- [LAN Observability APIs](#lan-observability-apis)
- [AI-Powered APIs](#ai-powered-apis)
- [Health & Monitoring APIs](#health--monitoring-apis)
- [Performance APIs](#performance-apis)

## Base URL

**Development**: `http://localhost:5000`  
**Production**: `https://your-server:5443`

All API endpoints are relative to this base URL.

## Authentication

### API Key Authentication

Protected endpoints require an API key in the request header:

```http
X-API-Key: your_api_key_here
```

To enable authentication, set the environment variable:

```powershell
$env:DASHBOARD_API_KEY = "your_secure_api_key"
```

**Protected Endpoints** (require API key):
- `/api/lan/device/<device_id>/update` (POST/PATCH)
- `/api/ai/feedback` (POST)
- `/api/ai/feedback/<id>/status` (PATCH)
- `/api/performance/*` (all endpoints)

**Public Endpoints** (no authentication required):
- `/health`, `/health/detailed`
- `/api/dashboard/summary`
- `/api/events`, `/api/events/logs`
- `/api/router/logs`, `/api/router/summary`
- `/api/lan/*` (read-only endpoints)

## Common Headers

### Request Headers

```http
Content-Type: application/json
X-API-Key: your_api_key_here
X-CSRF-Token: csrf_token_value
```

### Response Headers

```http
Content-Type: application/json
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1702288800
```

## Error Responses

All errors follow a consistent JSON format:

```json
{
  "error": "Error message",
  "status": 400,
  "timestamp": "2025-12-10T09:00:00Z"
}
```

### HTTP Status Codes

| Code | Meaning | Description |
|------|---------|-------------|
| 200 | OK | Request succeeded |
| 201 | Created | Resource created successfully |
| 400 | Bad Request | Invalid input or parameters |
| 401 | Unauthorized | Missing or invalid API key |
| 403 | Forbidden | CSRF token missing or invalid |
| 404 | Not Found | Resource not found |
| 429 | Too Many Requests | Rate limit exceeded |
| 500 | Internal Server Error | Server-side error |
| 503 | Service Unavailable | Database unavailable |

## Rate Limiting

Default rate limit: **100 requests per minute per client IP**.

When rate limited, you'll receive:

```json
{
  "error": "Rate limit exceeded. Try again in 42 seconds.",
  "status": 429,
  "timestamp": "2025-12-10T09:00:00Z"
}
```

Response headers indicate rate limit status:

```http
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1702288842
Retry-After: 42
```

---

## Dashboard APIs

### Get Dashboard Summary

**Endpoint**: `GET /api/dashboard/summary`

**Description**: Retrieve summary statistics for the main dashboard.

**Authentication**: None

**Parameters**: None

**Response**:

```json
{
  "total_devices": 45,
  "online_devices": 32,
  "offline_devices": 13,
  "total_events": 1250,
  "recent_alerts": [
    {
      "id": 123,
      "severity": "high",
      "message": "High CPU usage detected",
      "timestamp": 1702288800
    }
  ],
  "event_trends": {
    "last_hour": 150,
    "last_24h": 2400
  }
}
```

**Example**:

```bash
curl http://localhost:5000/api/dashboard/summary
```

---

## Events APIs

### Query Events

**Endpoint**: `GET /api/events` or `GET /api/events/logs`

**Description**: Query Windows Event Log entries with filtering.

**Authentication**: None

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `source` | string | No | Filter by event source |
| `level` | string | No | Filter by level (Critical, Error, Warning, Information) |
| `start_time` | integer | No | Start timestamp (Unix epoch) |
| `end_time` | integer | No | End timestamp (Unix epoch) |
| `search` | string | No | Search in message text |
| `limit` | integer | No | Max results (default: 100, max: 1000) |
| `offset` | integer | No | Pagination offset |

**Response**:

```json
{
  "events": [
    {
      "id": 456,
      "timestamp": 1702288800,
      "source": "Microsoft-Windows-Security-Auditing",
      "event_id": 4625,
      "level": "Warning",
      "message": "An account failed to log on.",
      "computer": "WIN-SERVER01"
    }
  ],
  "total": 1523,
  "limit": 100,
  "offset": 0
}
```

**Example**:

```bash
# Get critical events from last 24 hours
curl "http://localhost:5000/api/events?level=Critical&start_time=1702202400&limit=50"
```

### Get Events Summary

**Endpoint**: `GET /api/events/summary`

**Description**: Get aggregated event statistics.

**Authentication**: None

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `hours` | integer | No | Time window in hours (default: 24) |

**Response**:

```json
{
  "total_events": 2450,
  "by_level": {
    "Critical": 5,
    "Error": 123,
    "Warning": 456,
    "Information": 1866
  },
  "by_source": {
    "Microsoft-Windows-Security-Auditing": 850,
    "Application": 600,
    "System": 1000
  },
  "top_event_ids": [
    {"event_id": 4625, "count": 45, "description": "Failed login"},
    {"event_id": 4624, "count": 120, "description": "Successful login"}
  ]
}
```

---

## Router APIs

### Get Router Logs

**Endpoint**: `GET /api/router/logs`

**Description**: Query syslog messages from router.

**Authentication**: None

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `severity` | string | No | Filter by severity (emergency, alert, critical, error, warning, notice, info, debug) |
| `facility` | string | No | Filter by facility code |
| `hostname` | string | No | Filter by source hostname |
| `message` | string | No | Search in message text |
| `start_time` | integer | No | Start timestamp |
| `end_time` | integer | No | End timestamp |
| `limit` | integer | No | Max results (default: 100) |
| `offset` | integer | No | Pagination offset |

**Response**:

```json
{
  "logs": [
    {
      "id": 789,
      "timestamp": 1702288800,
      "facility": 23,
      "severity": 6,
      "hostname": "RT-AX88U",
      "message": "DHCP assigned 192.168.1.105 to AA:BB:CC:DD:EE:FF",
      "source_ip": "192.168.1.1"
    }
  ],
  "total": 3456,
  "limit": 100,
  "offset": 0
}
```

**Example**:

```bash
# Get error-level router logs
curl "http://localhost:5000/api/router/logs?severity=error&limit=50"
```

### Get Router Summary

**Endpoint**: `GET /api/router/summary`

**Description**: Get router log statistics.

**Authentication**: None

**Response**:

```json
{
  "total_messages": 15234,
  "by_severity": {
    "emergency": 0,
    "alert": 2,
    "critical": 5,
    "error": 45,
    "warning": 234,
    "notice": 1200,
    "info": 10500,
    "debug": 3248
  },
  "recent_errors": [
    {
      "timestamp": 1702288800,
      "message": "WAN connection dropped"
    }
  ]
}
```

---

## LAN Observability APIs

### Get LAN Statistics

**Endpoint**: `GET /api/lan/stats`

**Description**: Get overall LAN statistics.

**Authentication**: None

**Response**:

```json
{
  "total_devices": 45,
  "online_devices": 32,
  "offline_devices": 13,
  "new_devices_24h": 2,
  "interfaces": {
    "wired": 12,
    "wireless_2.4ghz": 15,
    "wireless_5ghz": 18
  },
  "signal_strength_avg": -62
}
```

**Example**:

```bash
curl http://localhost:5000/api/lan/stats
```

### List All Devices

**Endpoint**: `GET /api/lan/devices`

**Description**: Get list of all known devices.

**Authentication**: None

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `status` | string | No | Filter by status (online, offline, all) - default: all |
| `interface` | string | No | Filter by interface (wired, wireless_2.4ghz, wireless_5ghz) |
| `sort` | string | No | Sort field (last_seen, first_seen, nickname) |
| `order` | string | No | Sort order (asc, desc) - default: desc |
| `limit` | integer | No | Max results (default: 100) |
| `offset` | integer | No | Pagination offset |

**Response**:

```json
{
  "devices": [
    {
      "mac_address": "AA:BB:CC:DD:EE:FF",
      "first_seen": 1702202400,
      "last_seen": 1702288800,
      "nickname": "Living Room TV",
      "location": "Living Room",
      "manufacturer": "Samsung",
      "is_online": true,
      "interface": "wireless_5ghz",
      "ip_address": "192.168.1.105",
      "rssi": -58,
      "tx_rate": 866.0,
      "rx_rate": 866.0
    }
  ],
  "total": 45,
  "limit": 100,
  "offset": 0
}
```

**Example**:

```bash
# Get online devices only
curl "http://localhost:5000/api/lan/devices?status=online"

# Get wireless devices sorted by signal strength
curl "http://localhost:5000/api/lan/devices?interface=wireless_5ghz&sort=rssi&order=desc"
```

### Get Online Devices

**Endpoint**: `GET /api/lan/devices/online`

**Description**: Get only currently online devices (shortcut for `status=online`).

**Authentication**: None

**Response**: Same as `/api/lan/devices` but filtered to online only.

### Get Device Details

**Endpoint**: `GET /api/lan/device/<device_id>`

**Description**: Get detailed information about a specific device.

**Authentication**: None

**Path Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `device_id` | string | Yes | MAC address (URL-encoded) |

**Response**:

```json
{
  "mac_address": "AA:BB:CC:DD:EE:FF",
  "first_seen": 1702202400,
  "last_seen": 1702288800,
  "nickname": "Living Room TV",
  "location": "Living Room",
  "manufacturer": "Samsung",
  "is_online": true,
  "current_state": {
    "interface": "wireless_5ghz",
    "ip_address": "192.168.1.105",
    "rssi": -58,
    "tx_rate": 866.0,
    "rx_rate": 866.0,
    "timestamp": 1702288800
  },
  "statistics": {
    "total_snapshots": 1250,
    "avg_rssi": -60,
    "uptime_percentage": 98.5,
    "total_online_hours": 720
  }
}
```

**Example**:

```bash
curl "http://localhost:5000/api/lan/device/AA:BB:CC:DD:EE:FF"
```

### Update Device Information

**Endpoint**: `POST /api/lan/device/<device_id>/update` or `PATCH /api/lan/device/<device_id>/update`

**Description**: Update device nickname and location.

**Authentication**: API key required

**Path Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `device_id` | string | Yes | MAC address (URL-encoded) |

**Request Body**:

```json
{
  "nickname": "Living Room TV",
  "location": "Living Room"
}
```

**Response**:

```json
{
  "success": true,
  "message": "Device updated successfully",
  "device": {
    "mac_address": "AA:BB:CC:DD:EE:FF",
    "nickname": "Living Room TV",
    "location": "Living Room"
  }
}
```

**Example**:

```bash
curl -X POST http://localhost:5000/api/lan/device/AA:BB:CC:DD:EE:FF/update \
  -H "X-API-Key: your_api_key" \
  -H "Content-Type: application/json" \
  -d '{"nickname": "Living Room TV", "location": "Living Room"}'
```

### Get Device Timeline

**Endpoint**: `GET /api/lan/device/<device_id>/timeline`

**Description**: Get time-series data for a device (RSSI, transfer rates, online/offline).

**Authentication**: None

**Path Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `device_id` | string | Yes | MAC address |

**Query Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `start_time` | integer | No | Start timestamp (default: 24h ago) |
| `end_time` | integer | No | End timestamp (default: now) |
| `interval` | integer | No | Data point interval in seconds (default: 300) |

**Response**:

```json
{
  "mac_address": "AA:BB:CC:DD:EE:FF",
  "timeline": [
    {
      "timestamp": 1702288800,
      "is_online": true,
      "rssi": -58,
      "tx_rate": 866.0,
      "rx_rate": 866.0,
      "interface": "wireless_5ghz"
    }
  ],
  "start_time": 1702202400,
  "end_time": 1702288800,
  "data_points": 288
}
```

**Example**:

```bash
# Get last 24 hours of timeline data
curl "http://localhost:5000/api/lan/device/AA:BB:CC:DD:EE:FF/timeline"

# Get last week with hourly data points
curl "http://localhost:5000/api/lan/device/AA:BB:CC:DD:EE:FF/timeline?start_time=1701684000&interval=3600"
```

### Get Device Events

**Endpoint**: `GET /api/lan/device/<device_id>/events`

**Description**: Get router syslog events correlated to this device.

**Authentication**: None

**Path Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `device_id` | string | Yes | MAC address |

**Query Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `start_time` | integer | No | Start timestamp |
| `end_time` | integer | No | End timestamp |
| `limit` | integer | No | Max results (default: 100) |

**Response**:

```json
{
  "mac_address": "AA:BB:CC:DD:EE:FF",
  "events": [
    {
      "id": 123,
      "timestamp": 1702288800,
      "severity": "info",
      "message": "DHCP assigned 192.168.1.105 to AA:BB:CC:DD:EE:FF",
      "confidence": 1.0
    }
  ],
  "total": 45
}
```

### Get Device Connection Events

**Endpoint**: `GET /api/lan/device/<device_id>/connection-events`

**Description**: Get connect/disconnect events for a device.

**Authentication**: None

**Response**:

```json
{
  "mac_address": "AA:BB:CC:DD:EE:FF",
  "connection_events": [
    {
      "timestamp": 1702288800,
      "event_type": "connected",
      "interface": "wireless_5ghz",
      "ip_address": "192.168.1.105"
    },
    {
      "timestamp": 1702202400,
      "event_type": "disconnected",
      "duration_seconds": 86400
    }
  ]
}
```

---

## AI-Powered APIs

### Get AI Suggestions

**Endpoint**: `POST /api/ai/suggest`

**Description**: Get AI-powered suggestions for improving system health.

**Authentication**: None (but requires OpenAI API key configured)

**Request Body**:

```json
{
  "context": {
    "event_id": 4625,
    "count": 45,
    "time_window": "1 hour"
  }
}
```

**Response**:

```json
{
  "suggestions": [
    "Consider enabling account lockout policy after 5 failed attempts",
    "Review firewall rules to block suspicious IP addresses",
    "Enable detailed audit logging for security events"
  ],
  "confidence": 0.85,
  "timestamp": 1702288800
}
```

### Get AI Explanation

**Endpoint**: `POST /api/ai/explain`

**Description**: Get AI-powered explanation of an event or issue.

**Authentication**: None (but requires OpenAI API key configured)

**Request Body**:

```json
{
  "issue_type": "authentication_failure",
  "details": {
    "event_id": 4625,
    "count": 45,
    "source_ips": ["192.168.1.50", "192.168.1.75"]
  }
}
```

**Response**:

```json
{
  "explanation": "You are experiencing a potential brute-force authentication attack. Multiple failed login attempts from different IP addresses within a short time window suggest automated credential guessing.",
  "severity": "high",
  "recommendations": [
    "Enable account lockout policy",
    "Review and block suspicious IPs",
    "Enable MFA if not already enabled"
  ],
  "timestamp": 1702288800
}
```

### Submit AI Feedback

**Endpoint**: `POST /api/ai/feedback`

**Description**: Submit feedback about AI-generated suggestions.

**Authentication**: API key required

**Request Body**:

```json
{
  "issue_type": "authentication_failure",
  "explanation": "Potential brute-force attack detected",
  "recommendations": ["Enable lockout policy", "Block IPs"],
  "user_rating": 5,
  "user_comment": "Very helpful suggestion"
}
```

**Response**:

```json
{
  "success": true,
  "feedback_id": 123,
  "message": "Feedback submitted successfully"
}
```

### Get AI Feedback History

**Endpoint**: `GET /api/ai/feedback`

**Description**: Retrieve historical AI feedback entries.

**Authentication**: None

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `issue_type` | string | No | Filter by issue type |
| `status` | string | No | Filter by status (pending, resolved) |
| `limit` | integer | No | Max results (default: 100) |

**Response**:

```json
{
  "feedback": [
    {
      "id": 123,
      "issue_type": "authentication_failure",
      "explanation": "...",
      "recommendations": ["..."],
      "user_rating": 5,
      "status": "resolved",
      "timestamp": 1702288800
    }
  ],
  "total": 45
}
```

### Update Feedback Status

**Endpoint**: `PATCH /api/ai/feedback/<feedback_id>/status`

**Description**: Update the status of AI feedback.

**Authentication**: API key required

**Path Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `feedback_id` | integer | Yes | Feedback ID |

**Request Body**:

```json
{
  "status": "resolved",
  "resolution_notes": "Applied recommended lockout policy"
}
```

**Response**:

```json
{
  "success": true,
  "message": "Feedback status updated",
  "feedback": {
    "id": 123,
    "status": "resolved",
    "resolution_notes": "..."
  }
}
```

---

## Health & Monitoring APIs

### Simple Health Check

**Endpoint**: `GET /health`

**Description**: Quick health check (fast, minimal data).

**Authentication**: None

**Response**:

```json
{
  "status": "healthy",
  "timestamp": 1702288800
}
```

**Possible Status Values**:
- `healthy` - All systems operational
- `degraded` - Some issues detected but operational
- `unhealthy` - Critical issues, service impaired

**Example**:

```bash
curl http://localhost:5000/health
```

### Detailed Health Check

**Endpoint**: `GET /health/detailed`

**Description**: Comprehensive health check with component status.

**Authentication**: None

**Response**:

```json
{
  "status": "healthy",
  "timestamp": 1702288800,
  "checks": {
    "database": {
      "status": "healthy",
      "response_time_ms": 5,
      "details": "Connection successful"
    },
    "schema": {
      "status": "healthy",
      "tables_found": 12,
      "missing_tables": []
    },
    "data_freshness": {
      "status": "healthy",
      "last_snapshot_age_seconds": 120,
      "last_event_age_seconds": 45
    },
    "disk_space": {
      "status": "healthy",
      "database_size_mb": 456,
      "usage_percent": 45
    },
    "memory": {
      "status": "healthy",
      "rss_mb": 150,
      "vms_mb": 200
    }
  },
  "issues": []
}
```

**Degraded Example**:

```json
{
  "status": "degraded",
  "timestamp": 1702288800,
  "checks": {
    "data_freshness": {
      "status": "degraded",
      "last_snapshot_age_seconds": 720,
      "threshold_seconds": 600
    }
  },
  "issues": [
    "Last device snapshot is 12 minutes old (threshold: 10 minutes)"
  ]
}
```

---

## Performance APIs

### Get Query Performance Stats

**Endpoint**: `GET /api/performance/queries`

**Description**: Get query performance statistics.

**Authentication**: API key required

**Response**:

```json
{
  "slow_queries": [
    {
      "query": "SELECT * FROM device_snapshots WHERE timestamp > ?",
      "avg_duration_ms": 250,
      "max_duration_ms": 450,
      "count": 125,
      "last_execution": 1702288800
    }
  ],
  "statistics": {
    "total_queries": 5432,
    "avg_duration_ms": 45,
    "max_duration_ms": 450,
    "slow_query_threshold_ms": 100,
    "slow_query_count": 12
  }
}
```

**Example**:

```bash
curl -H "X-API-Key: your_api_key" http://localhost:5000/api/performance/queries
```

### Get Resource Usage

**Endpoint**: `GET /api/performance/resources`

**Description**: Get current resource utilization.

**Authentication**: API key required

**Response**:

```json
{
  "memory": {
    "rss_mb": 150,
    "vms_mb": 200,
    "percent": 3.5
  },
  "disk": {
    "database_size_mb": 456,
    "log_directory_size_mb": 45,
    "database_usage_percent": 45,
    "log_usage_percent": 5
  },
  "database": {
    "total_tables": 12,
    "total_rows": 125000,
    "largest_table": "device_snapshots",
    "largest_table_rows": 85000
  },
  "timestamp": 1702288800
}
```

### Analyze Query Plan

**Endpoint**: `POST /api/performance/query-plan`

**Description**: Get query execution plan and optimization suggestions.

**Authentication**: API key required

**Request Body**:

```json
{
  "query": "SELECT * FROM devices WHERE last_seen > ? ORDER BY last_seen DESC"
}
```

**Response**:

```json
{
  "query": "SELECT * FROM devices...",
  "plan": [
    {
      "id": 0,
      "parent": 0,
      "detail": "SCAN TABLE devices USING INDEX idx_devices_last_seen"
    }
  ],
  "issues": [],
  "suggestions": [
    "Query uses index efficiently",
    "Consider adding LIMIT clause if not all rows needed"
  ],
  "estimated_cost": 25
}
```

**Issues Detection**:

```json
{
  "issues": [
    "Full table scan detected - consider adding index",
    "TEMP B-TREE created - complex query may be slow"
  ],
  "suggestions": [
    "Add index on 'timestamp' column",
    "Simplify WHERE clause or split into multiple queries"
  ]
}
```

---

## OpenAPI Specification

For machine-readable API documentation, see the OpenAPI 3.0 specification:

```bash
# Generate OpenAPI spec (if implemented)
curl http://localhost:5000/api/openapi.json
```

---

## Code Examples

### Python

```python
import requests

# Get dashboard summary
response = requests.get('http://localhost:5000/api/dashboard/summary')
data = response.json()
print(f"Total devices: {data['total_devices']}")

# Update device with API key
headers = {'X-API-Key': 'your_api_key'}
payload = {'nickname': 'Living Room TV', 'location': 'Living Room'}
response = requests.post(
    'http://localhost:5000/api/lan/device/AA:BB:CC:DD:EE:FF/update',
    json=payload,
    headers=headers
)
print(response.json())
```

### PowerShell

```powershell
# Get dashboard summary
$response = Invoke-RestMethod -Uri "http://localhost:5000/api/dashboard/summary"
Write-Output "Total devices: $($response.total_devices)"

# Update device with API key
$headers = @{ "X-API-Key" = "your_api_key" }
$body = @{
    nickname = "Living Room TV"
    location = "Living Room"
} | ConvertTo-Json

$response = Invoke-RestMethod `
    -Uri "http://localhost:5000/api/lan/device/AA:BB:CC:DD:EE:FF/update" `
    -Method POST `
    -Headers $headers `
    -Body $body `
    -ContentType "application/json"

Write-Output $response.message
```

### JavaScript/Fetch

```javascript
// Get dashboard summary
fetch('http://localhost:5000/api/dashboard/summary')
  .then(response => response.json())
  .then(data => {
    console.log(`Total devices: ${data.total_devices}`);
  });

// Update device with API key
fetch('http://localhost:5000/api/lan/device/AA:BB:CC:DD:EE:FF/update', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'X-API-Key': 'your_api_key'
  },
  body: JSON.stringify({
    nickname: 'Living Room TV',
    location: 'Living Room'
  })
})
.then(response => response.json())
.then(data => console.log(data.message));
```

### cURL

```bash
# Get dashboard summary
curl http://localhost:5000/api/dashboard/summary | jq

# Get online devices
curl "http://localhost:5000/api/lan/devices?status=online" | jq '.devices[] | {nickname, ip_address}'

# Update device
curl -X POST http://localhost:5000/api/lan/device/AA:BB:CC:DD:EE:FF/update \
  -H "X-API-Key: your_api_key" \
  -H "Content-Type: application/json" \
  -d '{"nickname": "Living Room TV", "location": "Living Room"}' | jq

# Health check
curl http://localhost:5000/health/detailed | jq '.status'
```

---

## Webhooks (Future)

*Note: Webhook support is planned for Phase 7.*

### Alert Webhooks

Send POST requests to external URLs when alerts occur:

```json
{
  "event": "alert.created",
  "timestamp": 1702288800,
  "data": {
    "alert_id": 123,
    "severity": "high",
    "message": "High CPU usage detected",
    "details": {...}
  }
}
```

---

## Best Practices

### 1. Use Pagination

Always use `limit` and `offset` parameters for large datasets:

```bash
# Good
curl "http://localhost:5000/api/lan/devices?limit=100&offset=0"

# Bad (may return thousands of rows)
curl "http://localhost:5000/api/lan/devices"
```

### 2. Cache Responses

Many endpoints are cached server-side with 5-minute TTL. Avoid polling more frequently than necessary.

### 3. Handle Errors Gracefully

Always check HTTP status codes and handle errors:

```python
response = requests.get('http://localhost:5000/api/devices')
if response.status_code == 200:
    data = response.json()
elif response.status_code == 429:
    retry_after = int(response.headers.get('Retry-After', 60))
    print(f"Rate limited. Retry after {retry_after} seconds")
else:
    print(f"Error: {response.json()['error']}")
```

### 4. Use Appropriate HTTP Methods

- `GET` for reading data
- `POST` for creating resources
- `PATCH` for updating resources (partial)
- `DELETE` for removing resources (if supported)

### 5. Secure API Keys

Never commit API keys to version control:

```powershell
# Good
$apiKey = $env:DASHBOARD_API_KEY

# Bad
$apiKey = "hardcoded_api_key_12345"
```

---

## Rate Limit Guidelines

**Recommended polling intervals**:

| Endpoint | Recommended Interval |
|----------|---------------------|
| `/health` | 1 minute |
| `/api/dashboard/summary` | 5 minutes |
| `/api/lan/devices` | 2 minutes |
| `/api/lan/device/<id>/timeline` | 5 minutes |
| `/api/events` | 1 minute |
| `/api/router/logs` | 1 minute |

---

## Changelog

**2025-12-10**: Initial API reference documentation

For the latest API changes, see the [CHANGELOG](CHANGELOG.md).

---

## Support

For API questions or issues:

- Check [FAQ](FAQ.md) for common questions
- Review [TROUBLESHOOTING](TROUBLESHOOTING.md) for debugging
- Open an issue on GitHub

---

**API Version**: 1.0 (no versioning currently, breaking changes will be avoided)

# Implementation Guide for Roadmap Items

This guide provides concrete implementation details for the items outlined in [ROADMAP.md](../ROADMAP.md).

---

## Phase 1: Core Stability & Error Handling

### Connection Pooling (SQLite)

**Problem**: SQLite can encounter "database is locked" errors under concurrent access.

**Solution**:
```python
# In app.py, add connection pooling with WAL mode
import sqlite3
from contextlib import contextmanager

def init_db_pool():
    """Initialize SQLite with WAL mode for better concurrency."""
    db_path = _get_db_path()
    if db_path and os.path.exists(db_path):
        conn = sqlite3.connect(db_path)
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA synchronous=NORMAL")
        conn.execute("PRAGMA busy_timeout=5000")  # 5 second timeout
        conn.close()

@contextmanager
def get_db_cursor():
    """Context manager for database operations."""
    conn = get_db_connection()
    if not conn:
        yield None
        return
    try:
        cursor = conn.cursor()
        yield cursor
        conn.commit()
    except Exception as e:
        conn.rollback()
        app.logger.error('Database error: %s', e)
        raise
    finally:
        conn.close()
```

### Query Optimization

**Action Items**:
1. Add indexes for common queries:
```sql
-- In tools/schema-sqlite.sql or as a migration
CREATE INDEX IF NOT EXISTS idx_syslog_timestamp ON syslog_generic_events(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_syslog_severity ON syslog_generic_events(severity);
CREATE INDEX IF NOT EXISTS idx_devices_mac ON devices(mac_address);
CREATE INDEX IF NOT EXISTS idx_snapshots_mac_time ON device_snapshots(mac_address, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_iis_timestamp ON iis_logs(timestamp DESC) WHERE status_code >= 500;
```

2. Analyze query plans:
```python
# Add this helper function for development
def explain_query(query, params=None):
    """Log query execution plan for optimization."""
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute(f"EXPLAIN QUERY PLAN {query}", params or [])
    plan = cursor.fetchall()
    app.logger.debug('Query plan: %s', plan)
    conn.close()
```

### Service Heartbeat

**Implementation**:
```python
# Add to app.py
@app.route('/api/health/detailed')
def health_detailed():
    """Detailed health check for monitoring."""
    checks = {
        'database': check_database_health(),
        'services': check_services_health(),
        'disk_space': check_disk_space()
    }
    
    all_healthy = all(c['status'] == 'ok' for c in checks.values())
    status_code = 200 if all_healthy else 503
    
    return jsonify({
        'status': 'healthy' if all_healthy else 'degraded',
        'timestamp': datetime.datetime.now(datetime.UTC).isoformat(),
        'checks': checks
    }), status_code

def check_database_health():
    """Check if database is accessible and has recent data."""
    try:
        conn = get_db_connection()
        if not conn:
            return {'status': 'error', 'message': 'Cannot connect to database'}
        
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM syslog_generic_events WHERE timestamp > datetime('now', '-5 minutes')")
        recent_count = cursor.fetchone()[0]
        conn.close()
        
        if recent_count == 0:
            return {'status': 'warning', 'message': 'No recent data (last 5 min)'}
        
        return {'status': 'ok', 'recent_events': recent_count}
    except Exception as e:
        return {'status': 'error', 'message': str(e)}

def check_services_health():
    """Check if Windows services are running (Windows only)."""
    if not _is_windows():
        return {'status': 'ok', 'message': 'Not applicable (non-Windows)'}
    
    try:
        import subprocess
        # Check specific service names from the project
        service_names = ['SystemDashboardTelemetry']  # Add actual service names here
        services_status = []
        
        for service_name in service_names:
            result = subprocess.run(
                ['powershell', '-Command', 
                 f'Get-Service -Name {service_name} -ErrorAction SilentlyContinue | Select-Object Name, Status | ConvertTo-Json'],
                capture_output=True, text=True, timeout=5
            )
            if result.stdout:
                service = json.loads(result.stdout)
                services_status.append(service)
        
        stopped = [s['Name'] for s in services_status if s.get('Status') != 'Running']
        if stopped:
            return {'status': 'warning', 'message': f'Services stopped: {", ".join(stopped)}'}
        
        return {'status': 'ok', 'running_services': len(services_status)}
    except Exception as e:
        return {'status': 'error', 'message': str(e)}

def check_disk_space():
    """Check available disk space for database."""
    try:
        db_path = _get_db_path()
        if not db_path or not os.path.exists(db_path):
            return {'status': 'warning', 'message': 'Database file not found'}
        
        import shutil
        stat = shutil.disk_usage(os.path.dirname(db_path))
        percent_used = (stat.used / stat.total) * 100
        
        if percent_used > 90:
            return {'status': 'warning', 'message': f'Disk {percent_used:.1f}% full'}
        
        return {'status': 'ok', 'disk_usage_percent': round(percent_used, 1)}
    except Exception as e:
        return {'status': 'error', 'message': str(e)}
```

---

## Phase 2: UI Polish & Professionalism

### Loading States

**Skeleton Screens**:
```css
/* Add to styles.css */
.skeleton {
    background: linear-gradient(90deg, 
        var(--bg-card) 0%, 
        var(--bg-card-hover) 50%, 
        var(--bg-card) 100%);
    background-size: 200% 100%;
    animation: skeleton-loading 1.5s ease-in-out infinite;
    border-radius: var(--radius-md);
}

@keyframes skeleton-loading {
    0% { background-position: 200% 0; }
    100% { background-position: -200% 0; }
}

.skeleton-text {
    height: 1rem;
    margin-bottom: 0.5rem;
}

.skeleton-heading {
    height: 2rem;
    margin-bottom: 1rem;
    width: 60%;
}
```

```html
<!-- Add to dashboard.html while data loads -->
<div id="loading-skeleton" class="kpi-grid">
    <div class="kpi-card">
        <div class="skeleton skeleton-heading"></div>
        <div class="skeleton skeleton-text"></div>
        <div class="skeleton skeleton-text"></div>
    </div>
    <!-- Repeat for each card -->
</div>
```

### Toast Notifications

**Implementation**:
```javascript
// Add to app.js
const Toast = {
    container: null,
    
    init() {
        if (!this.container) {
            this.container = document.createElement('div');
            this.container.className = 'toast-container';
            document.body.appendChild(this.container);
        }
    },
    
    show(message, type = 'info', duration = 3000) {
        this.init();
        
        const toast = document.createElement('div');
        toast.className = `toast toast-${type}`;
        toast.innerHTML = `
            <span class="toast-icon">${this._getIcon(type)}</span>
            <span class="toast-message">${message}</span>
            <button class="toast-close">&times;</button>
        `;
        
        this.container.appendChild(toast);
        
        // Animate in
        setTimeout(() => toast.classList.add('toast-show'), 10);
        
        // Auto-dismiss
        const dismissTimer = setTimeout(() => this.dismiss(toast), duration);
        
        // Manual dismiss
        toast.querySelector('.toast-close').onclick = () => {
            clearTimeout(dismissTimer);
            this.dismiss(toast);
        };
    },
    
    dismiss(toast) {
        toast.classList.remove('toast-show');
        setTimeout(() => toast.remove(), 300);
    },
    
    _getIcon(type) {
        const icons = {
            success: '✓',
            error: '✕',
            warning: '⚠',
            info: 'ℹ'
        };
        return icons[type] || icons.info;
    }
};

// Usage:
// Toast.show('Device updated successfully', 'success');
// Toast.show('Failed to connect to database', 'error');
```

```css
/* Add to styles.css */
.toast-container {
    position: fixed;
    top: var(--space-lg);
    right: var(--space-lg);
    z-index: 10000;
    display: flex;
    flex-direction: column;
    gap: var(--space-sm);
    pointer-events: none;
}

.toast {
    display: flex;
    align-items: center;
    gap: var(--space-sm);
    padding: var(--space-md) var(--space-lg);
    background: var(--bg-card);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-md);
    box-shadow: var(--shadow-lg);
    min-width: 300px;
    max-width: 500px;
    opacity: 0;
    transform: translateX(100%);
    transition: all 0.3s ease;
    pointer-events: auto;
}

.toast-show {
    opacity: 1;
    transform: translateX(0);
}

.toast-success { border-left: 4px solid var(--status-healthy); }
.toast-error { border-left: 4px solid var(--status-critical); }
.toast-warning { border-left: 4px solid var(--status-warning); }
.toast-info { border-left: 4px solid var(--status-info); }

.toast-icon {
    font-size: 1.25rem;
    font-weight: bold;
}

.toast-success .toast-icon { color: var(--status-healthy); }
.toast-error .toast-icon { color: var(--status-critical); }
.toast-warning .toast-icon { color: var(--status-warning); }
.toast-info .toast-icon { color: var(--status-info); }

.toast-message {
    flex: 1;
    color: var(--text-primary);
}

.toast-close {
    background: none;
    border: none;
    color: var(--text-secondary);
    font-size: 1.5rem;
    cursor: pointer;
    padding: 0;
    width: 1.5rem;
    height: 1.5rem;
    display: flex;
    align-items: center;
    justify-content: center;
}

.toast-close:hover {
    color: var(--text-primary);
}
```

### Empty States

**Implementation**:
```html
<!-- Add to templates where tables/lists appear -->
<div id="empty-state" class="empty-state" style="display: none;">
    <svg class="empty-state-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <circle cx="12" cy="12" r="10"/>
        <line x1="12" y1="8" x2="12" y2="12"/>
        <line x1="12" y1="16" x2="12.01" y2="16"/>
    </svg>
    <h3 class="empty-state-title">No devices found</h3>
    <p class="empty-state-message">
        Start the LAN collector service to begin discovering devices on your network.
    </p>
    <button class="btn btn-primary" onclick="window.location.reload()">Refresh</button>
</div>
```

```css
/* Add to styles.css */
.empty-state {
    text-align: center;
    padding: var(--space-2xl) var(--space-xl);
    background: var(--bg-card);
    border: 1px solid var(--border-subtle);
    border-radius: var(--radius-lg);
    margin: var(--space-xl) 0;
}

.empty-state-icon {
    width: 64px;
    height: 64px;
    color: var(--text-muted);
    margin: 0 auto var(--space-lg);
    opacity: 0.5;
}

.empty-state-title {
    margin: 0 0 var(--space-sm);
    color: var(--text-primary);
    font-size: 1.25rem;
}

.empty-state-message {
    margin: 0 0 var(--space-lg);
    color: var(--text-secondary);
    max-width: 400px;
    margin-left: auto;
    margin-right: auto;
}
```

---

## Phase 3: Security & Hardening

### HTTPS Configuration

**Generate Self-Signed Certificate** (for development/internal use):

```powershell
# Create certificate generation script: scripts/generate-cert.ps1
param(
    [string]$CertPassword
)

# Prompt for password if not provided
if (-not $CertPassword) {
    $securePassword = Read-Host "Enter password for certificate" -AsSecureString
} else {
    $securePassword = ConvertTo-SecureString -String $CertPassword -Force -AsPlainText
}

$certParams = @{
    DnsName = "localhost", "systemdashboard.local"
    CertStoreLocation = "Cert:\LocalMachine\My"
    KeyExportPolicy = "Exportable"
    KeySpec = "Signature"
    KeyLength = 2048
    KeyAlgorithm = "RSA"
    HashAlgorithm = "SHA256"
    NotAfter = (Get-Date).AddYears(2)
}

$cert = New-SelfSignedCertificate @certParams

# Export certificate
$certPath = ".\certs\systemdashboard.pfx"
New-Item -ItemType Directory -Force -Path ".\certs"
Export-PfxCertificate -Cert $cert -FilePath $certPath -Password $securePassword

Write-Host "Certificate created and exported to $certPath"
Write-Host "Thumbprint: $($cert.Thumbprint)"
Write-Host "IMPORTANT: Save the certificate password securely!"
```

**Configure Flask for HTTPS**:

```python
# Update run_dashboard.py
import ssl

if __name__ == '__main__':
    # Check if cert files exist
    cert_file = os.path.join(os.path.dirname(__file__), '..', 'certs', 'cert.pem')
    key_file = os.path.join(os.path.dirname(__file__), '..', 'certs', 'key.pem')
    
    if os.path.exists(cert_file) and os.path.exists(key_file):
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert_file, key_file)
        app.run(host='0.0.0.0', port=5443, debug=False, ssl_context=context)
    else:
        print("Warning: Running without HTTPS. Generate certificates with scripts/generate-cert.ps1")
        app.run(host='0.0.0.0', port=5000, debug=False)
```

### Input Validation

**Comprehensive Validation Helper**:

```python
# Add to app.py
import re
from functools import wraps

class ValidationError(Exception):
    """Raised when input validation fails."""
    pass

def validate_mac_address(mac):
    """Validate MAC address format."""
    if not mac:
        raise ValidationError("MAC address is required")
    
    # Remove common separators
    cleaned = re.sub(r'[:\-\.]', '', mac.upper())
    
    if not re.match(r'^[0-9A-F]{12}$', cleaned):
        raise ValidationError(f"Invalid MAC address format: {mac}")
    
    return cleaned

def validate_ip_address(ip):
    """Validate IPv4 address format."""
    if not ip:
        raise ValidationError("IP address is required")
    
    parts = ip.split('.')
    if len(parts) != 4:
        raise ValidationError(f"Invalid IP address: {ip}")
    
    try:
        if not all(0 <= int(part) <= 255 for part in parts):
            raise ValidationError(f"Invalid IP address: {ip}")
    except ValueError:
        raise ValidationError(f"Invalid IP address: {ip}")
    
    return ip

def validate_pagination(page=1, per_page=50, max_per_page=100):
    """Validate pagination parameters."""
    try:
        page = max(1, int(page))
        per_page = max(1, min(int(per_page), max_per_page))
        return page, per_page
    except (TypeError, ValueError):
        raise ValidationError("Invalid pagination parameters")

def validate_date_range(start_date, end_date=None):
    """Validate date range parameters."""
    try:
        start = datetime.datetime.fromisoformat(start_date)
        end = datetime.datetime.fromisoformat(end_date) if end_date else datetime.datetime.now(datetime.UTC)
        
        if start > end:
            raise ValidationError("Start date must be before end date")
        
        # Limit range to 90 days
        if (end - start).days > 90:
            raise ValidationError("Date range cannot exceed 90 days")
        
        return start, end
    except (TypeError, ValueError) as e:
        raise ValidationError(f"Invalid date format: {e}")

def validate_request(validators):
    """Decorator for endpoint input validation.
    
    Note: This validates but doesn't mutate request.args/request.json
    since they're immutable. Instead, validated values are passed to
    the view function via kwargs or must be re-validated inside.
    """
    def decorator(f):
        @wraps(f)
        def wrapper(*args, **kwargs):
            try:
                # Validate request parameters
                validated_params = {}
                for param_name, validator_func in validators.items():
                    value = None
                    if param_name in request.args:
                        value = request.args.get(param_name)
                    elif request.is_json and param_name in request.json:
                        value = request.json.get(param_name)
                    
                    if value is not None:
                        validated_params[param_name] = validator_func(value)
                
                # Pass validated params to view function
                kwargs.update(validated_params)
                return f(*args, **kwargs)
            except ValidationError as e:
                return jsonify({'error': str(e)}), 400
        return wrapper
    return decorator

# Usage example:
@app.route('/api/lan/device/<mac>')
def api_lan_device_detail(mac):
    # Validate mac in the function
    try:
        mac = validate_mac_address(mac)
    except ValidationError as e:
        return jsonify({'error': str(e)}), 400
    # mac is now validated
    pass
```

---

## Phase 4: Performance & Scalability

### Query Caching

**Simple Cache Implementation**:

```python
# Add to app.py
from functools import lru_cache, wraps
import hashlib
import time

class Cache:
    """Simple TTL cache for expensive queries."""
    
    def __init__(self):
        self._cache = {}
    
    def get(self, key):
        if key in self._cache:
            value, expiry = self._cache[key]
            if time.time() < expiry:
                return value
            else:
                del self._cache[key]
        return None
    
    def set(self, key, value, ttl=60):
        """Set cache entry with TTL in seconds."""
        self._cache[key] = (value, time.time() + ttl)
    
    def clear(self):
        self._cache.clear()

# Global cache instance
query_cache = Cache()

def cached_query(ttl=60):
    """Decorator to cache query results."""
    def decorator(f):
        @wraps(f)
        def wrapper(*args, **kwargs):
            # Generate cache key from function name and arguments
            key_data = f"{f.__name__}:{args}:{sorted(kwargs.items())}"
            cache_key = hashlib.md5(key_data.encode()).hexdigest()
            
            # Check cache
            cached = query_cache.get(cache_key)
            if cached is not None:
                app.logger.debug('Cache hit for %s', f.__name__)
                return cached
            
            # Execute query and cache result
            result = f(*args, **kwargs)
            query_cache.set(cache_key, result, ttl=ttl)
            return result
        return wrapper
    return decorator

# Usage example:
@cached_query(ttl=300)  # Cache for 5 minutes
def get_24h_summary():
    """Get summary for last 24 hours (expensive query)."""
    conn = get_db_connection()
    if not conn:
        return None
    
    cursor = conn.cursor()
    cursor.execute("""
        SELECT 
            COUNT(*) as total_events,
            COUNT(CASE WHEN severity <= 3 THEN 1 END) as critical_count,
            COUNT(DISTINCT hostname) as unique_hosts
        FROM syslog_generic_events
        WHERE timestamp > datetime('now', '-24 hours')
    """)
    result = dict_from_row(cursor.fetchone())
    conn.close()
    return result
```

### Lazy Loading Images/Charts

```javascript
// Add to app.js
const LazyLoader = {
    observer: null,
    
    init() {
        if ('IntersectionObserver' in window) {
            this.observer = new IntersectionObserver(
                (entries) => {
                    entries.forEach(entry => {
                        if (entry.isIntersecting) {
                            this.loadElement(entry.target);
                            this.observer.unobserve(entry.target);
                        }
                    });
                },
                { rootMargin: '50px' }  // Load 50px before visible
            );
            
            // Observe all lazy elements
            document.querySelectorAll('[data-lazy-load]').forEach(el => {
                this.observer.observe(el);
            });
        } else {
            // Fallback: load everything immediately
            document.querySelectorAll('[data-lazy-load]').forEach(el => {
                this.loadElement(el);
            });
        }
    },
    
    loadElement(element) {
        const loadType = element.dataset.lazyLoad;
        
        if (loadType === 'chart') {
            // Load chart data and render
            const chartId = element.id;
            loadChartData(chartId);
        } else if (loadType === 'image') {
            // Load image
            const src = element.dataset.src;
            element.src = src;
        }
        
        element.removeAttribute('data-lazy-load');
    }
};

// Initialize on page load
document.addEventListener('DOMContentLoaded', () => LazyLoader.init());
```

---

## Testing Guidelines

### Writing Good Tests

**Structure**: Follow Arrange-Act-Assert pattern

```python
def test_device_update_validates_mac_address():
    """Test that device update rejects invalid MAC addresses."""
    # Arrange
    client = app.test_client()
    invalid_mac = "not-a-mac"
    
    # Act
    response = client.post(
        f'/api/lan/device/{invalid_mac}',
        json={'nickname': 'Test Device'}
    )
    
    # Assert
    assert response.status_code == 400
    assert 'Invalid MAC address' in response.json['error']
```

**Coverage Goals**:
- Critical paths: 100% coverage (auth, data ingestion, core queries)
- Business logic: >90% coverage
- UI routes: >70% coverage
- Utilities: >80% coverage

---

## Monitoring & Alerting

### Key Metrics to Track

1. **Database**:
   - Query response times (p50, p95, p99)
   - Database size and growth rate
   - Lock wait times
   - Vacuum/analyze last run

2. **Services**:
   - Service uptime
   - Collection success rate
   - Events ingested per minute
   - Error rate

3. **API**:
   - Requests per minute
   - Response times by endpoint
   - Error rate (4xx, 5xx)
   - Cache hit rate

4. **System**:
   - CPU usage
   - Memory usage
   - Disk space
   - Network I/O

---

## Conclusion

This implementation guide provides concrete code examples for the roadmap items. Use these as starting points, adapting them to fit the specific needs of your environment.

For questions or clarifications, consult the main [ROADMAP.md](../ROADMAP.md) or open a discussion.

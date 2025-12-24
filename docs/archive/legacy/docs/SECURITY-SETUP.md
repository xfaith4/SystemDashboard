# Security Setup Guide

This guide covers security configuration for the SystemDashboard including HTTPS, authentication, and credential management.

## Table of Contents

1. [HTTPS Setup](#https-setup)
2. [API Key Authentication](#api-key-authentication)
3. [CSRF Protection](#csrf-protection)
4. [Credential Rotation](#credential-rotation)
5. [Security Best Practices](#security-best-practices)

---

## HTTPS Setup

### Self-Signed Certificate for Development

For development and testing, you can generate a self-signed certificate:

#### Using OpenSSL (Windows/Linux)

```powershell
# Generate private key and certificate
openssl req -x509 -newkey rsa:4096 -nodes -out cert.pem -keyout key.pem -days 365

# You'll be prompted for certificate details:
# - Country Name: US
# - State: Your State
# - Locality: Your City
# - Organization: Your Organization
# - Organizational Unit: IT
# - Common Name: localhost (or your server's hostname/IP)
# - Email Address: admin@example.com
```

This creates two files:
- `cert.pem` - The certificate
- `key.pem` - The private key

#### Using PowerShell (Windows Only)

```powershell
# Create self-signed certificate for development
$cert = New-SelfSignedCertificate `
    -DnsName "localhost", "127.0.0.1" `
    -CertStoreLocation "cert:\LocalMachine\My" `
    -NotAfter (Get-Date).AddYears(1) `
    -KeySpec KeyExchange `
    -KeyExportPolicy Exportable

# Export certificate with private key
$password = ConvertTo-SecureString -String "YourPassword123!" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath ".\dashboard.pfx" -Password $password

# Export certificate without private key (for clients)
Export-Certificate -Cert $cert -FilePath ".\dashboard.cer"
```

### Running Flask with HTTPS

#### Option 1: Using Flask Built-in SSL

```python
# In app.py or a separate startup script
if __name__ == '__main__':
    import ssl
    
    context = ssl.SSLContext(ssl.PROTOCOL_TLSv1_2)
    context.load_cert_chain('cert.pem', 'key.pem')
    
    port = int(os.environ.get('DASHBOARD_PORT', '5000'))
    app.run(debug=False, host='0.0.0.0', port=port, ssl_context=context)
```

#### Option 2: Using Gunicorn (Production)

```bash
# Install gunicorn
pip install gunicorn

# Run with SSL
gunicorn --certfile cert.pem --keyfile key.pem \
         --bind 0.0.0.0:5000 app:app
```

#### Option 3: Using IIS as Reverse Proxy (Windows Production)

1. Install IIS with URL Rewrite and Application Request Routing (ARR)
2. Import your certificate into IIS
3. Configure SSL binding for your site
4. Set up reverse proxy to Flask app:

```xml
<!-- web.config -->
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <system.webServer>
        <rewrite>
            <rules>
                <rule name="ReverseProxyInboundRule1" stopProcessing="true">
                    <match url="(.*)" />
                    <action type="Rewrite" url="http://localhost:<port>/{R:1}" />
                </rule>
                <!-- Replace `<port>` with the value stored in `var/webui-port.txt`. -->
            </rules>
        </rewrite>
    </system.webServer>
</configuration>
```

### Production Certificate (Let's Encrypt)

For production deployments accessible from the internet, use Let's Encrypt for free, trusted certificates.

#### Using Certbot (Linux)

```bash
# Install certbot
sudo apt-get update
sudo apt-get install certbot

# Get certificate
sudo certbot certonly --standalone -d your-domain.com

# Certificates will be in:
# /etc/letsencrypt/live/your-domain.com/fullchain.pem
# /etc/letsencrypt/live/your-domain.com/privkey.pem
```

#### Using win-acme (Windows)

```powershell
# Download win-acme from https://www.win-acme.com/
# Run the executable and follow prompts
.\wacs.exe

# Select option for new certificate
# Choose IIS binding
# Certificates will be imported into Windows Certificate Store
```

---

## API Key Authentication

### Enabling API Key Authentication

API key authentication is **optional** and disabled by default. Enable it to protect sensitive endpoints.

#### Set API Key via Environment Variable

```powershell
# Windows
$env:DASHBOARD_API_KEY = "your-secure-random-key-here"

# Linux
export DASHBOARD_API_KEY="your-secure-random-key-here"
```

#### Generate a Secure API Key

```powershell
# PowerShell
-join ((65..90) + (97..122) + (48..57) | Get-Random -Count 32 | ForEach-Object {[char]$_})

# Python
python -c "import secrets; print(secrets.token_urlsafe(32))"

# OpenSSL
openssl rand -base64 32
```

#### Using API Keys in Requests

**Option 1: HTTP Header (Recommended)**

```bash
curl -H "X-API-Key: your-api-key" https://localhost:<port>/api/devices
```

```javascript
// JavaScript
fetch('/api/devices', {
    headers: {
        'X-API-Key': 'your-api-key'
    }
})
```

**Option 2: Query Parameter**

```bash
curl https://localhost:<port>/api/devices?api_key=your-api-key
```

### Protecting Endpoints

Add `@require_api_key` decorator to protect specific endpoints:

```python
from security import require_api_key

@app.route('/api/sensitive-data')
@require_api_key
def sensitive_endpoint():
    return jsonify({'data': 'protected'})
```

---

## CSRF Protection

Cross-Site Request Forgery (CSRF) protection is **enabled by default** for state-changing operations (POST, PUT, PATCH, DELETE).

### How CSRF Protection Works

1. Server sets a `csrf_token` cookie on all responses
2. Client includes token in requests:
   - As `X-CSRF-Token` header, OR
   - As `_csrf` field in JSON body or form data

### Client-Side Implementation

#### JavaScript/Fetch Example

```javascript
// Get CSRF token from cookie
function getCsrfToken() {
    const name = 'csrf_token=';
    const cookies = document.cookie.split(';');
    for (let cookie of cookies) {
        cookie = cookie.trim();
        if (cookie.startsWith(name)) {
            return cookie.substring(name.length);
        }
    }
    return null;
}

// Include in POST request
fetch('/api/lan/device/AA:BB:CC:DD:EE:FF/update', {
    method: 'POST',
    headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': getCsrfToken()
    },
    body: JSON.stringify({
        nickname: 'My Device'
    })
});
```

#### Form Submission Example

```html
<form method="POST" action="/api/update">
    <input type="hidden" name="_csrf" id="csrf_token">
    <input type="text" name="nickname">
    <button type="submit">Update</button>
</form>

<script>
    // Set CSRF token on page load
    document.getElementById('csrf_token').value = getCsrfToken();
</script>
```

### Disabling CSRF Protection

For development or if not needed:

```powershell
# Windows
$env:DASHBOARD_CSRF_ENABLED = "false"

# Linux
export DASHBOARD_CSRF_ENABLED="false"
```

---

## Credential Rotation

Regular credential rotation is a security best practice.

### Router Credentials

If your router password changes, update the environment variable:

```powershell
# Windows
$env:ASUS_ROUTER_PASSWORD = "new-password"

# Linux
export ASUS_ROUTER_PASSWORD="new-password"
```

Then restart the telemetry service:

```powershell
Restart-Service SystemDashboardTelemetry
```

### API Keys

To rotate API keys without downtime:

1. Generate a new API key
2. Update client applications to use new key
3. After transition period, update server environment variable
4. Restart the dashboard application

### Database Credentials

For SQLite, there are no database credentials. For future PostgreSQL support:

1. Change password in database: `ALTER USER sysdash_reader PASSWORD 'newpass';`
2. Update `config.json` or environment variable
3. Restart services

---

## Security Best Practices

### General

1. **Always use HTTPS in production** - Protects credentials and data in transit
2. **Use strong passwords** - At least 16 characters, mix of upper/lower/numbers/symbols
3. **Limit network exposure** - Only expose dashboard on trusted networks
4. **Keep software updated** - Regularly update Python, Flask, and dependencies
5. **Enable firewall** - Only allow necessary ports (443 for HTTPS, 514 for syslog)

### API Keys

1. **Generate cryptographically random keys** - Use `secrets` module or OpenSSL
2. **Store securely** - Use environment variables, not config files
3. **Rotate regularly** - Change keys every 90 days or after incidents
4. **Use separate keys per client** - Allows selective revocation
5. **Never log keys** - Audit logging automatically masks sensitive data

### CSRF Tokens

1. **Keep CSRF protection enabled** - Default is enabled
2. **Use HTTPS** - CSRF tokens in cookies need Secure flag
3. **Validate on server** - Never rely on client-side validation alone
4. **Short token lifetime** - Tokens expire after 1 hour by default

### Audit Trail

1. **Enable audit logging** - Track all configuration changes
2. **Review logs regularly** - Check for suspicious activity
3. **Secure log files** - Restrict access to audit logs
4. **Retain logs** - Keep at least 90 days for compliance
5. **Monitor failed attempts** - Alert on repeated authentication failures

### Network Security

1. **Use private network** - Keep dashboard on internal network
2. **VPN for remote access** - Don't expose directly to internet
3. **Segment networks** - Separate management network from monitored devices
4. **Monitor firewall logs** - Watch for unauthorized access attempts

### Database Security

1. **Regular backups** - Backup SQLite database daily
2. **Restrict file permissions** - Only dashboard process can read database
3. **Encrypt backups** - If storing offsite
4. **Test restore process** - Verify backups work

---

## Troubleshooting

### HTTPS Certificate Errors

**Problem:** "Certificate not trusted" warnings in browser

**Solution:** For self-signed certificates, this is expected. Either:
- Add certificate to trusted store
- Accept the warning (development only)
- Use proper CA-signed certificate (production)

### CSRF Token Missing

**Problem:** "CSRF token validation failed" errors

**Solution:**
1. Ensure cookies are enabled
2. Check that `csrf_token` cookie is being set
3. Verify client is sending `X-CSRF-Token` header
4. For cross-origin requests, check CORS configuration

### API Key Not Working

**Problem:** "Unauthorized" responses despite providing key

**Solution:**
1. Verify environment variable is set: `$env:DASHBOARD_API_KEY`
2. Restart the application after setting variable
3. Check key format - should be base64-safe string
4. Ensure key is passed in `X-API-Key` header or `api_key` parameter

### Audit Log Not Writing

**Problem:** Audit trail events not appearing in log file

**Solution:**
1. Check `DASHBOARD_AUDIT_LOG` environment variable
2. Verify write permissions on log directory
3. Check disk space
4. Review application logs for errors

---

## Environment Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `DASHBOARD_API_KEY` | (none) | API key for authentication; if set, enables auth |
| `DASHBOARD_CSRF_ENABLED` | `true` | Enable CSRF protection |
| `DASHBOARD_AUDIT_LOG` | `var/log/audit.log` | Path to audit log file |
| `DASHBOARD_MASK_IPS` | `false` | Mask IP addresses in logs |
| `DASHBOARD_MASK_EMAILS` | `false` | Mask email addresses in logs |
| `DASHBOARD_PORT` | `5000` | HTTP/HTTPS port to listen on |
| `ASUS_ROUTER_PASSWORD` | (none) | Router password for log collection |

---

## Additional Resources

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [Flask Security Best Practices](https://flask.palletsprojects.com/en/latest/security/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [CSP Reference](https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP)

---

**Last Updated:** December 7, 2025  
**Version:** 1.0

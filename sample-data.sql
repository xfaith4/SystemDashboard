-- Insert sample data for testing System Dashboard
-- This creates realistic test data in all telemetry tables

-- Sample Windows Event Log entries
INSERT INTO telemetry.eventlog_windows_template (
    received_utc, event_utc, source_host, provider_name, event_id, level, level_text,
    message, source
) VALUES
(NOW() - INTERVAL '5 minutes', NOW() - INTERVAL '5 minutes', 'APP01', 'Application Error', 1000, 2, 'Error',
 'Application MyApp.exe crashed due to memory access violation at address 0x12345678', 'windows_eventlog'),
(NOW() - INTERVAL '3 minutes', NOW() - INTERVAL '3 minutes', 'APP01', 'System', 7031, 1, 'Critical',
 'Service Control Manager terminated unexpectedly', 'windows_eventlog'),
(NOW() - INTERVAL '8 minutes', NOW() - INTERVAL '8 minutes', 'DB01', 'Application Error', 1001, 3, 'Warning',
 'Database connection timeout after 30 seconds', 'windows_eventlog'),
(NOW() - INTERVAL '12 minutes', NOW() - INTERVAL '12 minutes', 'WEB01', 'System', 6008, 3, 'Warning',
 'System uptime is 15 days - scheduled restart recommended', 'windows_eventlog'),
(NOW() - INTERVAL '1 minute', NOW() - INTERVAL '1 minute', 'DC01', 'Microsoft-Windows-Security-Auditing', 4625, 2, 'Error',
 'An account failed to log on. Account Name: admin Source Network Address: 192.168.1.100', 'windows_eventlog');

-- Sample IIS Request Log entries
INSERT INTO telemetry.iis_requests_template (
    received_utc, request_time, source_host, client_ip, method, uri_stem, status,
    bytes_sent, time_taken, user_agent, source
) VALUES
(NOW() - INTERVAL '2 minutes', NOW() - INTERVAL '2 minutes', 'WEB01', '192.168.1.50', 'GET', '/api/data', 500,
 1024, 5000, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)', 'iis'),
(NOW() - INTERVAL '1 minute', NOW() - INTERVAL '1 minute', 'WEB01', '192.168.1.50', 'POST', '/api/auth', 401,
 512, 1500, 'curl/7.68.0', 'iis'),
(NOW() - INTERVAL '3 minutes', NOW() - INTERVAL '3 minutes', 'WEB01', '192.168.1.75', 'GET', '/admin/login', 401,
 2048, 800, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)', 'iis'),
(NOW() - INTERVAL '4 minutes', NOW() - INTERVAL '4 minutes', 'WEB01', '192.168.1.50', 'POST', '/api/auth', 401,
 512, 1200, 'PostmanRuntime/7.28.4', 'iis'),
(NOW() - INTERVAL '6 minutes', NOW() - INTERVAL '6 minutes', 'WEB01', '203.0.113.44', 'GET', '/admin/dashboard', 403,
 1536, 2000, 'BadBot/1.0', 'iis'),
(NOW() - INTERVAL '7 minutes', NOW() - INTERVAL '7 minutes', 'WEB01', '192.168.1.25', 'GET', '/api/status', 200,
 4096, 150, 'HealthCheck/1.0', 'iis'),
(NOW() - INTERVAL '5 minutes', NOW() - INTERVAL '5 minutes', 'WEB01', '192.168.1.50', 'POST', '/api/data', 500,
 1024, 8000, 'axios/0.21.1', 'iis'),
(NOW() - INTERVAL '1 minute', NOW() - INTERVAL '1 minute', 'WEB01', '192.168.1.50', 'GET', '/login', 401,
 768, 500, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)', 'iis'),
(NOW() - INTERVAL '2 minutes', NOW() - INTERVAL '2 minutes', 'WEB01', '192.168.1.50', 'POST', '/login', 401,
 512, 750, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)', 'iis'),
(NOW() - INTERVAL '8 minutes', NOW() - INTERVAL '8 minutes', 'WEB01', '192.168.1.50', 'GET', '/api/auth', 401,
 256, 300, 'curl/7.68.0', 'iis');

-- Sample additional IIS entries to test thresholds
INSERT INTO telemetry.iis_requests_template (
    received_utc, request_time, source_host, client_ip, method, uri_stem, status,
    bytes_sent, time_taken, user_agent, source
) VALUES
(NOW() - INTERVAL '4 minutes', NOW() - INTERVAL '4 minutes', 'WEB01', '192.168.1.50', 'POST', '/login', 401,
 512, 600, 'Mozilla/5.0', 'iis'),
(NOW() - INTERVAL '3 minutes', NOW() - INTERVAL '3 minutes', 'WEB01', '192.168.1.50', 'GET', '/admin', 401,
 384, 400, 'Mozilla/5.0', 'iis'),
(NOW() - INTERVAL '5 minutes', NOW() - INTERVAL '5 minutes', 'WEB01', '192.168.1.50', 'POST', '/api/login', 403,
 256, 350, 'PostmanRuntime/7.28.4', 'iis'),
(NOW() - INTERVAL '6 minutes', NOW() - INTERVAL '6 minutes', 'WEB01', '192.168.1.50', 'GET', '/secure', 401,
 128, 200, 'curl/7.68.0', 'iis'),
(NOW() - INTERVAL '7 minutes', NOW() - INTERVAL '7 minutes', 'WEB01', '192.168.1.50', 'POST', '/dashboard', 403,
 512, 550, 'BadBot/1.0', 'iis');

-- Sample Syslog entries
INSERT INTO telemetry.syslog_generic_template (
    received_utc, event_utc, source_host, facility, severity, message, source
) VALUES
(NOW() - INTERVAL '3 minutes', NOW() - INTERVAL '3 minutes', 'asus-router', 16, 3,
 'WAN connection lost - attempting reconnection', 'asus'),
(NOW() - INTERVAL '6 minutes', NOW() - INTERVAL '6 minutes', 'asus-router', 16, 4,
 'DHCP lease expired for client 192.168.1.105', 'asus'),
(NOW() - INTERVAL '9 minutes', NOW() - INTERVAL '9 minutes', 'asus-router', 4, 6,
 'Admin login successful from 192.168.1.10', 'asus'),
(NOW() - INTERVAL '2 minutes', NOW() - INTERVAL '2 minutes', 'firewall01', 16, 4,
 'Connection blocked from 203.0.113.50 to port 22', 'syslog'),
(NOW() - INTERVAL '4 minutes', NOW() - INTERVAL '4 minutes', 'asus-router', 4, 4,
 'Multiple failed admin login attempts from 203.0.113.10', 'asus'),
(NOW() - INTERVAL '1 minute', NOW() - INTERVAL '1 minute', 'monitoring', 16, 6,
 'System health check completed - all services operational', 'syslog');

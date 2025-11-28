-- System Dashboard SQLite Schema
-- This schema provides a clean, professional database structure for the system dashboard
-- using SQLite for simple, file-based database management.

-- Enable foreign keys
PRAGMA foreign_keys = ON;

-- ============================================================================
-- Core Telemetry Tables
-- ============================================================================

-- Syslog messages table (replaces PostgreSQL partitioned table)
CREATE TABLE IF NOT EXISTS syslog_messages (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    received_utc    TEXT NOT NULL,
    event_utc       TEXT,
    source_host     TEXT,
    app_name        TEXT,
    facility        INTEGER,
    severity        INTEGER,
    message         TEXT,
    raw_message     TEXT,
    remote_endpoint TEXT,
    source          TEXT NOT NULL DEFAULT 'syslog',
    created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Indexes for syslog_messages
CREATE INDEX IF NOT EXISTS idx_syslog_received_utc ON syslog_messages(received_utc DESC);
CREATE INDEX IF NOT EXISTS idx_syslog_source ON syslog_messages(source, received_utc DESC);
CREATE INDEX IF NOT EXISTS idx_syslog_severity ON syslog_messages(severity, received_utc DESC);

-- Windows Event Log table
CREATE TABLE IF NOT EXISTS eventlog_windows (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    received_utc    TEXT NOT NULL DEFAULT (datetime('now')),
    event_utc       TEXT,
    source_host     TEXT,
    provider_name   TEXT,
    event_id        INTEGER,
    level           INTEGER,
    level_text      TEXT,
    task_category   TEXT,
    keywords        TEXT,
    message         TEXT,
    raw_xml         TEXT,
    source          TEXT NOT NULL DEFAULT 'windows_eventlog',
    created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Indexes for eventlog_windows
CREATE INDEX IF NOT EXISTS idx_eventlog_received_utc ON eventlog_windows(received_utc DESC);
CREATE INDEX IF NOT EXISTS idx_eventlog_level ON eventlog_windows(level, received_utc DESC);
CREATE INDEX IF NOT EXISTS idx_eventlog_provider ON eventlog_windows(provider_name, received_utc DESC);

-- IIS Request Log table
CREATE TABLE IF NOT EXISTS iis_requests (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    received_utc    TEXT NOT NULL DEFAULT (datetime('now')),
    request_time    TEXT,
    source_host     TEXT,
    client_ip       TEXT,
    client_user     TEXT,
    method          TEXT,
    uri_stem        TEXT,
    uri_query       TEXT,
    status          INTEGER,
    substatus       INTEGER,
    win32_status    INTEGER,
    bytes_sent      INTEGER,
    bytes_received  INTEGER,
    time_taken      INTEGER,
    user_agent      TEXT,
    referer         TEXT,
    site_name       TEXT,
    raw_log_line    TEXT,
    source          TEXT NOT NULL DEFAULT 'iis',
    created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Indexes for iis_requests
CREATE INDEX IF NOT EXISTS idx_iis_received_utc ON iis_requests(received_utc DESC);
CREATE INDEX IF NOT EXISTS idx_iis_status ON iis_requests(status, received_utc DESC);
CREATE INDEX IF NOT EXISTS idx_iis_client ON iis_requests(client_ip, received_utc DESC);
CREATE INDEX IF NOT EXISTS idx_iis_request_time ON iis_requests(request_time DESC);

-- ============================================================================
-- LAN Observability Tables
-- ============================================================================

-- Device inventory table
CREATE TABLE IF NOT EXISTS devices (
    device_id           INTEGER PRIMARY KEY AUTOINCREMENT,
    mac_address         TEXT NOT NULL UNIQUE,
    primary_ip_address  TEXT,
    hostname            TEXT,
    nickname            TEXT,
    location            TEXT,
    manufacturer        TEXT,
    vendor              TEXT,
    first_seen_utc      TEXT NOT NULL DEFAULT (datetime('now')),
    last_seen_utc       TEXT NOT NULL DEFAULT (datetime('now')),
    is_active           INTEGER DEFAULT 0,
    tags                TEXT,
    network_type        TEXT DEFAULT 'main',
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Indexes for devices
CREATE INDEX IF NOT EXISTS idx_devices_mac ON devices(mac_address);
CREATE INDEX IF NOT EXISTS idx_devices_active ON devices(is_active, last_seen_utc DESC);
CREATE INDEX IF NOT EXISTS idx_devices_last_seen ON devices(last_seen_utc DESC);

-- Device snapshots table (time-series data)
CREATE TABLE IF NOT EXISTS device_snapshots (
    snapshot_id         INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id           INTEGER NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
    sample_time_utc     TEXT NOT NULL DEFAULT (datetime('now')),
    ip_address          TEXT,
    interface           TEXT,
    rssi                INTEGER,
    tx_rate_mbps        REAL,
    rx_rate_mbps        REAL,
    is_online           INTEGER DEFAULT 1,
    raw_json            TEXT,
    source_payload      TEXT,
    created_at          TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Indexes for device_snapshots
CREATE INDEX IF NOT EXISTS idx_snapshots_device_time ON device_snapshots(device_id, sample_time_utc DESC);
CREATE INDEX IF NOT EXISTS idx_snapshots_time ON device_snapshots(sample_time_utc DESC);
CREATE INDEX IF NOT EXISTS idx_snapshots_online ON device_snapshots(is_online, sample_time_utc DESC);

-- Syslog-to-device link table
CREATE TABLE IF NOT EXISTS syslog_device_links (
    link_id             INTEGER PRIMARY KEY AUTOINCREMENT,
    syslog_id           INTEGER NOT NULL,
    device_id           INTEGER NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
    match_type          TEXT,
    confidence          REAL DEFAULT 1.0,
    created_at          TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Indexes for syslog_device_links
CREATE INDEX IF NOT EXISTS idx_syslog_links_syslog ON syslog_device_links(syslog_id);
CREATE INDEX IF NOT EXISTS idx_syslog_links_device ON syslog_device_links(device_id, created_at DESC);

-- Device events table
CREATE TABLE IF NOT EXISTS device_events (
    event_id            INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id           INTEGER NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
    event_type          TEXT NOT NULL,
    event_time          TEXT NOT NULL DEFAULT (datetime('now')),
    previous_state      TEXT,
    new_state           TEXT,
    details             TEXT,
    created_at          TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Indexes for device_events
CREATE INDEX IF NOT EXISTS idx_device_events_device ON device_events(device_id, event_time DESC);
CREATE INDEX IF NOT EXISTS idx_device_events_type ON device_events(event_type, event_time DESC);
CREATE INDEX IF NOT EXISTS idx_device_events_time ON device_events(event_time DESC);

-- Device alerts table
CREATE TABLE IF NOT EXISTS device_alerts (
    alert_id            INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id           INTEGER REFERENCES devices(device_id) ON DELETE CASCADE,
    alert_type          TEXT NOT NULL,
    severity            TEXT NOT NULL DEFAULT 'info',
    title               TEXT NOT NULL,
    message             TEXT,
    metadata            TEXT,
    is_acknowledged     INTEGER DEFAULT 0,
    acknowledged_at     TEXT,
    acknowledged_by     TEXT,
    is_resolved         INTEGER DEFAULT 0,
    resolved_at         TEXT,
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Indexes for device_alerts
CREATE INDEX IF NOT EXISTS idx_alerts_device ON device_alerts(device_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_alerts_type ON device_alerts(alert_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_alerts_severity ON device_alerts(severity, is_resolved, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_alerts_unresolved ON device_alerts(is_resolved, created_at DESC);

-- ============================================================================
-- AI Feedback Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS ai_feedback (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id            INTEGER,
    event_source        TEXT,
    event_message       TEXT NOT NULL,
    event_log_type      TEXT,
    event_level         TEXT,
    event_time          TEXT,
    ai_response         TEXT NOT NULL,
    review_status       TEXT NOT NULL DEFAULT 'Viewed'
                        CHECK (review_status IN ('Pending', 'Viewed', 'Resolved')),
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Indexes for ai_feedback
CREATE INDEX IF NOT EXISTS idx_ai_feedback_status ON ai_feedback(review_status);
CREATE INDEX IF NOT EXISTS idx_ai_feedback_event_id ON ai_feedback(event_id);
CREATE INDEX IF NOT EXISTS idx_ai_feedback_created ON ai_feedback(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_feedback_status_created ON ai_feedback(review_status, created_at DESC);

-- ============================================================================
-- Settings Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS lan_settings (
    setting_key         TEXT PRIMARY KEY,
    setting_value       TEXT,
    description         TEXT,
    updated_at          TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Insert default settings
INSERT OR IGNORE INTO lan_settings (setting_key, setting_value, description) VALUES
    ('snapshot_retention_days', '7', 'Number of days to retain device snapshot data'),
    ('inactive_threshold_minutes', '10', 'Minutes without snapshot before marking device inactive'),
    ('poll_interval_seconds', '300', 'Seconds between router polling attempts'),
    ('syslog_correlation_enabled', 'true', 'Whether to correlate syslog events with devices'),
    ('track_device_events', 'true', 'Track device connect/disconnect events'),
    ('event_retention_days', '90', 'Days to keep device event history'),
    ('alert_new_device_enabled', 'true', 'Alert on new devices joining the network'),
    ('alert_offline_enabled', 'true', 'Alert on devices going offline'),
    ('alert_weak_signal_enabled', 'true', 'Alert on weak signal strength'),
    ('alert_weak_signal_threshold', '-75', 'RSSI threshold for weak signal alerts (dBm)'),
    ('alert_retention_days', '30', 'Days to keep resolved alerts');

-- ============================================================================
-- Views for convenience (matching PostgreSQL views)
-- ============================================================================

-- Recent syslog messages (last 24 hours)
CREATE VIEW IF NOT EXISTS syslog_recent AS
SELECT * FROM syslog_messages
WHERE datetime(received_utc) >= datetime('now', '-24 hours');

-- Recent Windows events (last 24 hours)
CREATE VIEW IF NOT EXISTS eventlog_windows_recent AS
SELECT * FROM eventlog_windows
WHERE datetime(received_utc) >= datetime('now', '-24 hours');

-- Recent IIS requests (last 24 hours)
CREATE VIEW IF NOT EXISTS iis_requests_recent AS
SELECT * FROM iis_requests
WHERE datetime(received_utc) >= datetime('now', '-24 hours');

-- Recent device snapshots (last 7 days)
CREATE VIEW IF NOT EXISTS device_snapshots_recent AS
SELECT * FROM device_snapshots
WHERE datetime(sample_time_utc) >= datetime('now', '-7 days');

-- Online devices view
CREATE VIEW IF NOT EXISTS devices_online AS
SELECT 
    d.*,
    ds.sample_time_utc AS last_snapshot_time,
    ds.ip_address AS current_ip,
    ds.interface AS current_interface,
    ds.rssi AS current_rssi
FROM devices d
INNER JOIN device_snapshots ds ON ds.device_id = d.device_id
    AND datetime(ds.sample_time_utc) >= datetime('now', '-10 minutes')
    AND ds.is_online = 1
WHERE d.is_active = 1
GROUP BY d.device_id
HAVING ds.sample_time_utc = MAX(ds.sample_time_utc);

-- Active alerts view
CREATE VIEW IF NOT EXISTS device_alerts_active AS
SELECT 
    a.*,
    d.mac_address,
    d.hostname,
    d.nickname,
    d.primary_ip_address,
    d.tags,
    d.is_active AS device_is_active
FROM device_alerts a
INNER JOIN devices d ON a.device_id = d.device_id
WHERE a.is_resolved = 0
ORDER BY a.created_at DESC;

-- LAN summary stats view
CREATE VIEW IF NOT EXISTS lan_summary_stats AS
SELECT
    COUNT(*) AS total_devices,
    SUM(CASE WHEN is_active = 1 THEN 1 ELSE 0 END) AS active_devices,
    SUM(CASE WHEN is_active = 0 THEN 1 ELSE 0 END) AS inactive_devices,
    0 AS wired_devices_24h,
    0 AS wifi_24ghz_devices_24h,
    0 AS wifi_5ghz_devices_24h
FROM devices;

-- AI Feedback views
CREATE VIEW IF NOT EXISTS ai_feedback_recent AS
SELECT 
    id, event_id, event_source, event_message, event_log_type,
    event_level, event_time, ai_response, review_status,
    created_at, updated_at
FROM ai_feedback
WHERE datetime(created_at) >= datetime('now', '-30 days')
ORDER BY created_at DESC;

CREATE VIEW IF NOT EXISTS ai_feedback_unresolved AS
SELECT 
    id, event_id, event_source, event_message, event_log_type,
    event_level, event_time, ai_response, review_status,
    created_at, updated_at
FROM ai_feedback
WHERE review_status IN ('Pending', 'Viewed')
ORDER BY created_at DESC;

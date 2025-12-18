-- Performance optimization indexes for System Dashboard SQLite database
-- These indexes improve query performance for frequently-accessed columns

-- Devices table indexes
CREATE INDEX IF NOT EXISTS idx_devices_mac ON devices (mac_address);
CREATE INDEX IF NOT EXISTS idx_devices_active ON devices (is_active, last_seen_utc DESC);
CREATE INDEX IF NOT EXISTS idx_devices_last_seen ON devices (last_seen_utc DESC);
CREATE INDEX IF NOT EXISTS idx_devices_tags ON devices (tags) WHERE tags IS NOT NULL;

-- Device snapshots indexes
CREATE INDEX IF NOT EXISTS idx_device_snapshots_device_time ON device_snapshots (device_id, sample_time_utc DESC);
CREATE INDEX IF NOT EXISTS idx_device_snapshots_time ON device_snapshots (sample_time_utc DESC);
CREATE INDEX IF NOT EXISTS idx_device_snapshots_online ON device_snapshots (is_online, sample_time_utc DESC);

-- Device alerts indexes
CREATE INDEX IF NOT EXISTS idx_device_alerts_device ON device_alerts (device_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_device_alerts_status ON device_alerts (status, severity, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_device_alerts_severity ON device_alerts (severity, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_device_alerts_active ON device_alerts (status) WHERE status = 'active';

-- Syslog recent indexes (if table exists)
CREATE INDEX IF NOT EXISTS idx_syslog_recent_received ON syslog_recent (received_utc DESC);
CREATE INDEX IF NOT EXISTS idx_syslog_recent_severity ON syslog_recent (severity, received_utc DESC);
CREATE INDEX IF NOT EXISTS idx_syslog_recent_host ON syslog_recent (host, received_utc DESC);

-- AI feedback indexes (if table exists)
CREATE INDEX IF NOT EXISTS idx_ai_feedback_created ON ai_feedback (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_feedback_status ON ai_feedback (review_status, created_at DESC);

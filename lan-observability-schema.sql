-- LAN Observability Schema for System Dashboard
-- This schema supports device inventory and time-series monitoring

-- Create devices table (stable inventory)
CREATE TABLE IF NOT EXISTS telemetry.devices (
    device_id           SERIAL PRIMARY KEY,
    mac_address         TEXT NOT NULL UNIQUE,
    primary_ip_address  TEXT,
    hostname            TEXT,
    nickname            TEXT,
    location            TEXT,
    manufacturer        TEXT,
    vendor              TEXT,
    first_seen_utc      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_utc       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_active           BOOLEAN DEFAULT false,
    tags                TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for fast MAC lookups
CREATE INDEX IF NOT EXISTS idx_devices_mac ON telemetry.devices (mac_address);
CREATE INDEX IF NOT EXISTS idx_devices_active ON telemetry.devices (is_active, last_seen_utc DESC);
CREATE INDEX IF NOT EXISTS idx_devices_last_seen ON telemetry.devices (last_seen_utc DESC);

-- Device snapshots table (time-series data) - partitioned by time
CREATE TABLE IF NOT EXISTS telemetry.device_snapshots_template (
    snapshot_id         BIGSERIAL,
    device_id           INTEGER NOT NULL REFERENCES telemetry.devices(device_id) ON DELETE CASCADE,
    sample_time_utc     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ip_address          TEXT,
    interface           TEXT,
    rssi                INTEGER,
    tx_rate_mbps        REAL,
    rx_rate_mbps        REAL,
    is_online           BOOLEAN DEFAULT true,
    raw_json            TEXT,
    source_payload      TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (snapshot_id, sample_time_utc)
) PARTITION BY RANGE (sample_time_utc);

-- Helper function to create monthly partitions for device snapshots
CREATE OR REPLACE FUNCTION telemetry.ensure_device_snapshot_partition(target_month DATE)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    partition_name TEXT;
    start_ts       DATE;
    end_ts         DATE;
    stmt           TEXT;
BEGIN
    start_ts := date_trunc('month', target_month);
    end_ts := (start_ts + INTERVAL '1 month');
    partition_name := format('device_snapshots_%s', to_char(start_ts, 'YYMM'));

    IF NOT EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = partition_name
          AND n.nspname = 'telemetry'
    ) THEN
        stmt := format(
            'CREATE TABLE telemetry.%I PARTITION OF telemetry.device_snapshots_template
             FOR VALUES FROM (%L) TO (%L);',
            partition_name,
            start_ts,
            end_ts
        );
        EXECUTE stmt;
        
        -- Create indexes on the partition
        EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_device_time ON telemetry.%I (device_id, sample_time_utc DESC)', 
                      partition_name, partition_name);
        EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_time ON telemetry.%I (sample_time_utc DESC)', 
                      partition_name, partition_name);
    END IF;
END;
$$;

-- Create indexes on template (will be inherited by partitions)
CREATE INDEX IF NOT EXISTS idx_device_snapshots_device_time ON telemetry.device_snapshots_template (device_id, sample_time_utc DESC);
CREATE INDEX IF NOT EXISTS idx_device_snapshots_time ON telemetry.device_snapshots_template (sample_time_utc DESC);
CREATE INDEX IF NOT EXISTS idx_device_snapshots_online ON telemetry.device_snapshots_template (is_online, sample_time_utc DESC);

-- Recent device snapshots view (last 7 days for fast queries)
CREATE OR REPLACE VIEW telemetry.device_snapshots_recent AS
SELECT *
FROM telemetry.device_snapshots_template
WHERE sample_time_utc >= NOW() - INTERVAL '7 days';

-- Link table for syslog events to devices
CREATE TABLE IF NOT EXISTS telemetry.syslog_device_links (
    link_id             BIGSERIAL PRIMARY KEY,
    syslog_id           BIGINT NOT NULL,
    device_id           INTEGER NOT NULL REFERENCES telemetry.devices(device_id) ON DELETE CASCADE,
    match_type          TEXT,
    confidence          REAL DEFAULT 1.0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_syslog_device_links_syslog ON telemetry.syslog_device_links (syslog_id);
CREATE INDEX IF NOT EXISTS idx_syslog_device_links_device ON telemetry.syslog_device_links (device_id, created_at DESC);

-- Retention cleanup function for device snapshots
CREATE OR REPLACE FUNCTION telemetry.cleanup_old_device_snapshots(retention_days INTEGER DEFAULT 7)
RETURNS TABLE(deleted_count BIGINT)
LANGUAGE plpgsql
AS $$
DECLARE
    cutoff_date TIMESTAMPTZ;
    rows_deleted BIGINT;
BEGIN
    cutoff_date := NOW() - (retention_days || ' days')::INTERVAL;
    
    DELETE FROM telemetry.device_snapshots_template
    WHERE sample_time_utc < cutoff_date;
    
    GET DIAGNOSTICS rows_deleted = ROW_COUNT;
    
    RETURN QUERY SELECT rows_deleted;
END;
$$;

-- Helper view for currently online devices
CREATE OR REPLACE VIEW telemetry.devices_online AS
SELECT d.*,
       ds.sample_time_utc AS last_snapshot_time,
       ds.ip_address AS current_ip,
       ds.interface AS current_interface,
       ds.rssi AS current_rssi
FROM telemetry.devices d
INNER JOIN LATERAL (
    SELECT *
    FROM telemetry.device_snapshots_template
    WHERE device_id = d.device_id
      AND sample_time_utc >= NOW() - INTERVAL '10 minutes'
      AND is_online = true
    ORDER BY sample_time_utc DESC
    LIMIT 1
) ds ON true
WHERE d.is_active = true;

-- Helper function to update device activity status
CREATE OR REPLACE FUNCTION telemetry.update_device_activity_status(inactive_threshold_minutes INTEGER DEFAULT 10)
RETURNS TABLE(updated_count INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    cutoff_time TIMESTAMPTZ;
    rows_updated INTEGER;
BEGIN
    cutoff_time := NOW() - (inactive_threshold_minutes || ' minutes')::INTERVAL;
    
    -- Mark devices as inactive if no recent snapshots
    UPDATE telemetry.devices
    SET is_active = false,
        updated_at = NOW()
    WHERE is_active = true
      AND last_seen_utc < cutoff_time;
    
    GET DIAGNOSTICS rows_updated = ROW_COUNT;
    
    RETURN QUERY SELECT rows_updated;
END;
$$;

-- Create initial partition for current month
SELECT telemetry.ensure_device_snapshot_partition(CURRENT_DATE);

-- Grant permissions to existing users
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA telemetry TO sysdash_ingest;
GRANT SELECT ON ALL TABLES IN SCHEMA telemetry TO sysdash_reader;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA telemetry TO sysdash_ingest;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA telemetry TO sysdash_ingest;

-- Update default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA telemetry GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO sysdash_ingest;
ALTER DEFAULT PRIVILEGES IN SCHEMA telemetry GRANT SELECT ON TABLES TO sysdash_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA telemetry GRANT USAGE, SELECT ON SEQUENCES TO sysdash_ingest;
ALTER DEFAULT PRIVILEGES IN SCHEMA telemetry GRANT EXECUTE ON FUNCTIONS TO sysdash_ingest;

-- Create a settings table for LAN observability configuration
CREATE TABLE IF NOT EXISTS telemetry.lan_settings (
    setting_key         TEXT PRIMARY KEY,
    setting_value       TEXT,
    description         TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Insert default settings
INSERT INTO telemetry.lan_settings (setting_key, setting_value, description)
VALUES 
    ('snapshot_retention_days', '7', 'Number of days to retain device snapshot data'),
    ('inactive_threshold_minutes', '10', 'Minutes without snapshot before marking device inactive'),
    ('poll_interval_seconds', '300', 'Seconds between router polling attempts'),
    ('syslog_correlation_enabled', 'true', 'Whether to correlate syslog events with devices')
ON CONFLICT (setting_key) DO NOTHING;

GRANT SELECT, INSERT, UPDATE ON telemetry.lan_settings TO sysdash_ingest;
GRANT SELECT ON telemetry.lan_settings TO sysdash_reader;

-- Summary view for dashboard statistics
CREATE OR REPLACE VIEW telemetry.lan_summary_stats AS
WITH device_totals AS (
    SELECT
        COUNT(*) AS total_devices,
        COUNT(*) FILTER (WHERE is_active = true) AS active_devices,
        COUNT(*) FILTER (WHERE is_active = false) AS inactive_devices
    FROM telemetry.devices
),
recent_snapshots AS (
    SELECT 
        device_id, 
        COALESCE(NULLIF(interface, ''), 'unknown') AS interface,
        sample_time_utc
    FROM telemetry.device_snapshots_template
    WHERE sample_time_utc >= NOW() - INTERVAL '24 hours'
),
latest_interfaces AS (
    SELECT DISTINCT ON (device_id)
        device_id,
        interface
    FROM recent_snapshots
    ORDER BY device_id, sample_time_utc DESC
)
SELECT
    dt.total_devices,
    dt.active_devices,
    dt.inactive_devices,
    COUNT(li.device_id) FILTER (WHERE li.interface ILIKE '%wired%') AS wired_devices_24h,
    COUNT(li.device_id) FILTER (WHERE li.interface ILIKE ANY (ARRAY['%2.4%','%24%','%2g%','%wireless%','%wl0%'])) AS wifi_24ghz_devices_24h,
    COUNT(li.device_id) FILTER (WHERE li.interface ILIKE ANY (ARRAY['%5%','%5g%','%5ghz%','%wl1%'])) AS wifi_5ghz_devices_24h
FROM device_totals dt
LEFT JOIN latest_interfaces li ON true
GROUP BY dt.total_devices, dt.active_devices, dt.inactive_devices;

GRANT SELECT ON telemetry.lan_summary_stats TO sysdash_reader;

-- Add comment for documentation
COMMENT ON TABLE telemetry.devices IS 'Stable inventory of all LAN devices identified by MAC address';
COMMENT ON TABLE telemetry.device_snapshots_template IS 'Time-series snapshots of device network statistics (RSSI, rates, online status)';
COMMENT ON TABLE telemetry.syslog_device_links IS 'Links syslog events to specific devices for correlation';
COMMENT ON TABLE telemetry.lan_settings IS 'Configuration settings for LAN observability features';

-- Ensure new columns exist when updating existing deployments
ALTER TABLE telemetry.devices
    ADD COLUMN IF NOT EXISTS location TEXT;

ALTER TABLE telemetry.devices
    ADD COLUMN IF NOT EXISTS network_type TEXT DEFAULT 'main'; -- 'main', 'guest', 'iot', 'unknown'

-- Device events table for tracking connect/disconnect and other events
CREATE TABLE IF NOT EXISTS telemetry.device_events (
    event_id            BIGSERIAL PRIMARY KEY,
    device_id           INTEGER NOT NULL REFERENCES telemetry.devices(device_id) ON DELETE CASCADE,
    event_type          TEXT NOT NULL, -- 'connected', 'disconnected', 'reconnected', 'ip_change', 'interface_change'
    event_time          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    previous_state      JSONB,
    new_state           JSONB,
    details             TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_device_events_device ON telemetry.device_events (device_id, event_time DESC);
CREATE INDEX IF NOT EXISTS idx_device_events_type ON telemetry.device_events (event_type, event_time DESC);
CREATE INDEX IF NOT EXISTS idx_device_events_time ON telemetry.device_events (event_time DESC);

-- Event settings
INSERT INTO telemetry.lan_settings (setting_key, setting_value, description)
VALUES 
    ('track_device_events', 'true', 'Track device connect/disconnect events'),
    ('event_retention_days', '90', 'Days to keep device event history')
ON CONFLICT (setting_key) DO NOTHING;

GRANT SELECT, INSERT ON telemetry.device_events TO sysdash_ingest;
GRANT SELECT ON telemetry.device_events TO sysdash_reader;

COMMENT ON TABLE telemetry.device_events IS 'Timeline of device connection events (connect/disconnect/changes)';

-- Device alerts table for tracking network issues and events
CREATE TABLE IF NOT EXISTS telemetry.device_alerts (
    alert_id            BIGSERIAL PRIMARY KEY,
    device_id           INTEGER REFERENCES telemetry.devices(device_id) ON DELETE CASCADE,
    alert_type          TEXT NOT NULL, -- 'new_device', 'offline', 'weak_signal', 'reconnected', 'bandwidth_spike'
    severity            TEXT NOT NULL DEFAULT 'info', -- 'critical', 'warning', 'info'
    title               TEXT NOT NULL,
    message             TEXT,
    metadata            JSONB,
    is_acknowledged     BOOLEAN DEFAULT false,
    acknowledged_at     TIMESTAMPTZ,
    acknowledged_by     TEXT,
    is_resolved         BOOLEAN DEFAULT false,
    resolved_at         TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_device_alerts_device ON telemetry.device_alerts (device_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_device_alerts_type ON telemetry.device_alerts (alert_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_device_alerts_severity ON telemetry.device_alerts (severity, is_resolved, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_device_alerts_unresolved ON telemetry.device_alerts (is_resolved, created_at DESC) WHERE is_resolved = false;

-- Alert settings
INSERT INTO telemetry.lan_settings (setting_key, setting_value, description)
VALUES 
    ('alert_new_device_enabled', 'true', 'Alert on new devices joining the network'),
    ('alert_offline_enabled', 'true', 'Alert on devices going offline'),
    ('alert_weak_signal_enabled', 'true', 'Alert on weak signal strength'),
    ('alert_weak_signal_threshold', '-75', 'RSSI threshold for weak signal alerts (dBm)'),
    ('alert_retention_days', '30', 'Days to keep resolved alerts')
ON CONFLICT (setting_key) DO NOTHING;

GRANT SELECT, INSERT, UPDATE ON telemetry.device_alerts TO sysdash_ingest;
GRANT SELECT ON telemetry.device_alerts TO sysdash_reader;

-- View for recent unresolved alerts
CREATE OR REPLACE VIEW telemetry.device_alerts_active AS
SELECT 
    a.*,
    d.mac_address,
    d.hostname,
    d.nickname,
    d.primary_ip_address,
    d.tags,
    d.is_active AS device_is_active
FROM telemetry.device_alerts a
INNER JOIN telemetry.devices d ON a.device_id = d.device_id
WHERE a.is_resolved = false
ORDER BY a.created_at DESC;

GRANT SELECT ON telemetry.device_alerts_active TO sysdash_reader;

COMMENT ON TABLE telemetry.device_alerts IS 'Alerts for network device events and issues';
COMMENT ON VIEW telemetry.device_alerts_active IS 'Active (unresolved) alerts with device information';

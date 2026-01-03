-- System Dashboard unified PostgreSQL schema
-- Includes telemetry, Windows Event Log, IIS, LAN observability, AI feedback, and actions.

CREATE SCHEMA IF NOT EXISTS telemetry;

-- ============================================================================
-- Syslog telemetry base
-- ============================================================================

CREATE TABLE IF NOT EXISTS telemetry.syslog_generic_template (
    id              BIGSERIAL,
    received_utc    TIMESTAMPTZ NOT NULL,
    event_utc       TIMESTAMPTZ,
    source_host     TEXT,
    app_name        TEXT,
    facility        SMALLINT,
    severity        SMALLINT,
    message         TEXT,
    raw_message     TEXT,
    remote_endpoint TEXT,
    source          TEXT NOT NULL DEFAULT 'syslog',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (received_utc, id)
) PARTITION BY RANGE (received_utc);

CREATE OR REPLACE FUNCTION telemetry.ensure_syslog_partition(target_month DATE)
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
    partition_name := format('syslog_generic_%s', to_char(start_ts, 'YYMM'));

    IF NOT EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = partition_name
          AND n.nspname = 'telemetry'
    ) THEN
        stmt := format(
            'CREATE TABLE telemetry.%I PARTITION OF telemetry.syslog_generic_template
             FOR VALUES FROM (%L) TO (%L);',
            partition_name,
            start_ts,
            end_ts
        );
        EXECUTE stmt;
    END IF;
END;
$$;

CREATE OR REPLACE VIEW telemetry.syslog_recent AS
SELECT *
FROM telemetry.syslog_generic_template
WHERE received_utc >= NOW() - INTERVAL '24 hours';

CREATE INDEX IF NOT EXISTS idx_syslog_recent_time ON telemetry.syslog_generic_template (received_utc DESC);
CREATE INDEX IF NOT EXISTS idx_syslog_source ON telemetry.syslog_generic_template (source, received_utc DESC);
CREATE INDEX IF NOT EXISTS idx_syslog_severity ON telemetry.syslog_generic_template (severity, received_utc DESC);

-- ============================================================================
-- Device profile + observation telemetry
-- ============================================================================

CREATE TABLE IF NOT EXISTS telemetry.device_profiles (
    mac_address      TEXT PRIMARY KEY,
    first_seen       TIMESTAMPTZ NOT NULL,
    last_seen        TIMESTAMPTZ NOT NULL,
    last_event_type  TEXT,
    last_category    TEXT,
    last_source_host TEXT,
    last_app_name    TEXT,
    last_rssi        INTEGER,
    vendor_oui       TEXT,
    last_ip          INET,
    total_events     BIGINT NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS telemetry.device_observations (
    observation_id BIGSERIAL PRIMARY KEY,
    occurred_at    TIMESTAMPTZ NOT NULL,
    received_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    mac_address    TEXT NOT NULL,
    event_type     TEXT,
    category       TEXT,
    source_host    TEXT,
    app_name       TEXT,
    rssi           INTEGER,
    ip_address     INET,
    message        TEXT,
    raw_message    TEXT
);

CREATE INDEX IF NOT EXISTS idx_device_obs_mac_time ON telemetry.device_observations (mac_address, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_device_obs_category ON telemetry.device_observations (category, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_device_obs_event_type ON telemetry.device_observations (event_type, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_device_obs_time ON telemetry.device_observations (occurred_at DESC);

CREATE OR REPLACE VIEW telemetry.device_observations_recent AS
SELECT *
FROM telemetry.device_observations
WHERE occurred_at >= NOW() - INTERVAL '24 hours';

-- ============================================================================
-- Windows Event Log telemetry
-- ============================================================================

CREATE TABLE IF NOT EXISTS telemetry.eventlog_windows_template (
    id              BIGSERIAL,
    received_utc    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_utc       TIMESTAMPTZ,
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
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (id, received_utc)
) PARTITION BY RANGE (received_utc);

CREATE OR REPLACE FUNCTION telemetry.ensure_eventlog_partition(target_month DATE)
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
    partition_name := format('eventlog_windows_%s', to_char(start_ts, 'YYMM'));

    IF NOT EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = partition_name
          AND n.nspname = 'telemetry'
    ) THEN
        stmt := format(
            'CREATE TABLE telemetry.%I PARTITION OF telemetry.eventlog_windows_template
             FOR VALUES FROM (%L) TO (%L);',
            partition_name,
            start_ts,
            end_ts
        );
        EXECUTE stmt;
    END IF;
END;
$$;

CREATE OR REPLACE VIEW telemetry.eventlog_windows_recent AS
SELECT *
FROM telemetry.eventlog_windows_template
WHERE received_utc >= NOW() - INTERVAL '24 hours';

CREATE INDEX IF NOT EXISTS idx_eventlog_windows_recent_time ON telemetry.eventlog_windows_template (received_utc DESC);
CREATE INDEX IF NOT EXISTS idx_eventlog_windows_level ON telemetry.eventlog_windows_template (level, received_utc DESC);
CREATE INDEX IF NOT EXISTS idx_eventlog_windows_provider ON telemetry.eventlog_windows_template (provider_name, received_utc DESC);

-- ============================================================================
-- IIS request telemetry
-- ============================================================================

CREATE TABLE IF NOT EXISTS telemetry.iis_requests_template (
    id              BIGSERIAL,
    received_utc    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    request_time    TIMESTAMPTZ,
    source_host     TEXT,
    client_ip       TEXT,
    client_user     TEXT,
    method          TEXT,
    uri_stem        TEXT,
    uri_query       TEXT,
    status          INTEGER,
    substatus       INTEGER,
    win32_status    INTEGER,
    bytes_sent      BIGINT,
    bytes_received  BIGINT,
    time_taken      INTEGER,
    user_agent      TEXT,
    referer         TEXT,
    site_name       TEXT,
    raw_log_line    TEXT,
    source          TEXT NOT NULL DEFAULT 'iis',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (id, received_utc)
) PARTITION BY RANGE (received_utc);

CREATE OR REPLACE FUNCTION telemetry.ensure_iis_partition(target_month DATE)
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
    partition_name := format('iis_requests_%s', to_char(start_ts, 'YYMM'));

    IF NOT EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = partition_name
          AND n.nspname = 'telemetry'
    ) THEN
        stmt := format(
            'CREATE TABLE telemetry.%I PARTITION OF telemetry.iis_requests_template
             FOR VALUES FROM (%L) TO (%L);',
            partition_name,
            start_ts,
            end_ts
        );
        EXECUTE stmt;
    END IF;
END;
$$;

CREATE OR REPLACE VIEW telemetry.iis_requests_recent AS
SELECT *
FROM telemetry.iis_requests_template
WHERE received_utc >= NOW() - INTERVAL '24 hours';

CREATE INDEX IF NOT EXISTS idx_iis_requests_time ON telemetry.iis_requests_template (received_utc DESC);
CREATE INDEX IF NOT EXISTS idx_iis_requests_status ON telemetry.iis_requests_template (status, received_utc DESC);
CREATE INDEX IF NOT EXISTS idx_iis_requests_client ON telemetry.iis_requests_template (client_ip, received_utc DESC);

-- ============================================================================
-- Unified events + metrics + incidents/actions
-- ============================================================================

CREATE TABLE IF NOT EXISTS telemetry.events (
    event_id       BIGSERIAL PRIMARY KEY,
    event_type     TEXT,
    source         TEXT,
    severity       TEXT,
    subject        TEXT,
    occurred_at    TIMESTAMPTZ,
    received_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    tags           JSONB,
    correlation_id TEXT,
    payload        JSONB,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE telemetry.events
    ADD COLUMN IF NOT EXISTS tags JSONB;

ALTER TABLE telemetry.events
    ALTER COLUMN received_at SET DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_events_occurred_at ON telemetry.events (occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_events_type ON telemetry.events (event_type, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_events_severity ON telemetry.events (severity, occurred_at DESC);

CREATE TABLE IF NOT EXISTS telemetry.metrics (
    metric_id    BIGSERIAL PRIMARY KEY,
    metric_name  TEXT NOT NULL,
    metric_value DOUBLE PRECISION NOT NULL,
    metric_unit  TEXT,
    source       TEXT,
    captured_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    tags         JSONB
);

CREATE INDEX IF NOT EXISTS idx_metrics_captured_at ON telemetry.metrics (captured_at DESC);
CREATE INDEX IF NOT EXISTS idx_metrics_name ON telemetry.metrics (metric_name, captured_at DESC);

CREATE TABLE IF NOT EXISTS telemetry.incidents (
    incident_id BIGSERIAL PRIMARY KEY,
    title       TEXT NOT NULL,
    status      TEXT NOT NULL DEFAULT 'open',
    severity    TEXT NOT NULL DEFAULT 'info',
    summary     TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_incidents_status ON telemetry.incidents (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_incidents_severity ON telemetry.incidents (severity, created_at DESC);

CREATE TABLE IF NOT EXISTS telemetry.incident_links (
    incident_id BIGINT NOT NULL REFERENCES telemetry.incidents(incident_id) ON DELETE CASCADE,
    event_id    BIGINT NOT NULL REFERENCES telemetry.events(event_id) ON DELETE CASCADE,
    confidence  DOUBLE PRECISION NOT NULL DEFAULT 1.0,
    reason      TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (incident_id, event_id)
);

CREATE TABLE IF NOT EXISTS telemetry.actions (
    action_id      BIGSERIAL PRIMARY KEY,
    incident_id    BIGINT REFERENCES telemetry.incidents(incident_id) ON DELETE SET NULL,
    action_type    TEXT NOT NULL,
    status         TEXT NOT NULL DEFAULT 'requested',
    requested_by   TEXT,
    requested_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    approved_by    TEXT,
    approved_at    TIMESTAMPTZ,
    executed_at    TIMESTAMPTZ,
    completed_at   TIMESTAMPTZ,
    action_payload JSONB,
    result_payload JSONB
);

CREATE INDEX IF NOT EXISTS idx_actions_status ON telemetry.actions (status, requested_at DESC);
CREATE INDEX IF NOT EXISTS idx_actions_incident ON telemetry.actions (incident_id, requested_at DESC);

CREATE TABLE IF NOT EXISTS telemetry.action_audit (
    audit_id   BIGSERIAL PRIMARY KEY,
    action_id  BIGINT NOT NULL REFERENCES telemetry.actions(action_id) ON DELETE CASCADE,
    step       TEXT NOT NULL,
    status     TEXT NOT NULL,
    message    TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata   JSONB
);

CREATE INDEX IF NOT EXISTS idx_action_audit_action ON telemetry.action_audit (action_id, created_at DESC);

CREATE TABLE IF NOT EXISTS telemetry.config_snapshots (
    snapshot_id    BIGSERIAL PRIMARY KEY,
    source         TEXT NOT NULL,
    captured_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    config_payload JSONB NOT NULL
);

-- ============================================================================
-- AI feedback
-- ============================================================================

CREATE TABLE IF NOT EXISTS telemetry.ai_feedback (
    id                  BIGSERIAL PRIMARY KEY,
    event_id            INTEGER,
    event_source        TEXT,
    event_message       TEXT NOT NULL,
    event_log_type      TEXT,
    event_level         TEXT,
    event_time          TIMESTAMPTZ,
    ai_response         TEXT NOT NULL,
    review_status       TEXT NOT NULL
                        CHECK (review_status IN ('Pending', 'Viewed', 'Resolved'))
                        DEFAULT 'Viewed',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_feedback_review_status ON telemetry.ai_feedback(review_status);
CREATE INDEX IF NOT EXISTS idx_ai_feedback_event_id ON telemetry.ai_feedback(event_id);
CREATE INDEX IF NOT EXISTS idx_ai_feedback_created_at ON telemetry.ai_feedback(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_feedback_status_created ON telemetry.ai_feedback(review_status, created_at DESC);

CREATE OR REPLACE FUNCTION telemetry.update_ai_feedback_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_ai_feedback_updated_at ON telemetry.ai_feedback;
CREATE TRIGGER trg_ai_feedback_updated_at
    BEFORE UPDATE ON telemetry.ai_feedback
    FOR EACH ROW
    EXECUTE FUNCTION telemetry.update_ai_feedback_updated_at();

CREATE OR REPLACE VIEW telemetry.ai_feedback_recent AS
SELECT
    id,
    event_id,
    event_source,
    event_message,
    event_log_type,
    event_level,
    event_time,
    ai_response,
    review_status,
    created_at,
    updated_at
FROM telemetry.ai_feedback
WHERE created_at >= NOW() - INTERVAL '30 days'
ORDER BY created_at DESC;

CREATE OR REPLACE VIEW telemetry.ai_feedback_unresolved AS
SELECT
    id,
    event_id,
    event_source,
    event_message,
    event_log_type,
    event_level,
    event_time,
    ai_response,
    review_status,
    created_at,
    updated_at
FROM telemetry.ai_feedback
WHERE review_status IN ('Pending', 'Viewed')
ORDER BY created_at DESC;

COMMENT ON TABLE telemetry.ai_feedback IS
'AI-generated explanations for Windows Event Log entries with review workflow';

COMMENT ON COLUMN telemetry.ai_feedback.review_status IS
'Review status workflow: Pending (not yet reviewed), Viewed (acknowledged), Resolved (action taken)';

-- ============================================================================
-- LAN observability
-- ============================================================================

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
    network_type        TEXT DEFAULT 'main',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_devices_mac ON telemetry.devices (mac_address);
CREATE INDEX IF NOT EXISTS idx_devices_active ON telemetry.devices (is_active, last_seen_utc DESC);
CREATE INDEX IF NOT EXISTS idx_devices_last_seen ON telemetry.devices (last_seen_utc DESC);

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

        EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_device_time ON telemetry.%I (device_id, sample_time_utc DESC)',
                      partition_name, partition_name);
        EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_time ON telemetry.%I (sample_time_utc DESC)',
                      partition_name, partition_name);
    END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_device_snapshots_device_time ON telemetry.device_snapshots_template (device_id, sample_time_utc DESC);
CREATE INDEX IF NOT EXISTS idx_device_snapshots_time ON telemetry.device_snapshots_template (sample_time_utc DESC);
CREATE INDEX IF NOT EXISTS idx_device_snapshots_online ON telemetry.device_snapshots_template (is_online, sample_time_utc DESC);

CREATE OR REPLACE VIEW telemetry.device_snapshots_recent AS
SELECT *
FROM telemetry.device_snapshots_template
WHERE sample_time_utc >= NOW() - INTERVAL '7 days';

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

CREATE OR REPLACE FUNCTION telemetry.update_device_activity_status(inactive_threshold_minutes INTEGER DEFAULT 10)
RETURNS TABLE(updated_count INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    cutoff_time TIMESTAMPTZ;
    rows_updated INTEGER;
BEGIN
    cutoff_time := NOW() - (inactive_threshold_minutes || ' minutes')::INTERVAL;

    UPDATE telemetry.devices
    SET is_active = false,
        updated_at = NOW()
    WHERE is_active = true
      AND last_seen_utc < cutoff_time;

    GET DIAGNOSTICS rows_updated = ROW_COUNT;

    RETURN QUERY SELECT rows_updated;
END;
$$;

CREATE TABLE IF NOT EXISTS telemetry.lan_settings (
    setting_key         TEXT PRIMARY KEY,
    setting_value       TEXT,
    description         TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO telemetry.lan_settings (setting_key, setting_value, description)
VALUES
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
    ('alert_retention_days', '30', 'Days to keep resolved alerts')
ON CONFLICT (setting_key) DO NOTHING;

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

COMMENT ON TABLE telemetry.devices IS 'Stable inventory of all LAN devices identified by MAC address';
COMMENT ON TABLE telemetry.device_snapshots_template IS 'Time-series snapshots of device network statistics (RSSI, rates, online status)';
COMMENT ON TABLE telemetry.syslog_device_links IS 'Links syslog events to specific devices for correlation';
COMMENT ON TABLE telemetry.lan_settings IS 'Configuration settings for LAN observability features';

ALTER TABLE telemetry.devices
    ADD COLUMN IF NOT EXISTS location TEXT;

ALTER TABLE telemetry.devices
    ADD COLUMN IF NOT EXISTS network_type TEXT DEFAULT 'main';

CREATE TABLE IF NOT EXISTS telemetry.device_events (
    event_id            BIGSERIAL PRIMARY KEY,
    device_id           INTEGER NOT NULL REFERENCES telemetry.devices(device_id) ON DELETE CASCADE,
    event_type          TEXT NOT NULL,
    event_time          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    previous_state      JSONB,
    new_state           JSONB,
    details             TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_device_events_device ON telemetry.device_events (device_id, event_time DESC);
CREATE INDEX IF NOT EXISTS idx_device_events_type ON telemetry.device_events (event_type, event_time DESC);
CREATE INDEX IF NOT EXISTS idx_device_events_time ON telemetry.device_events (event_time DESC);

CREATE TABLE IF NOT EXISTS telemetry.device_alerts (
    alert_id            BIGSERIAL PRIMARY KEY,
    device_id           INTEGER REFERENCES telemetry.devices(device_id) ON DELETE CASCADE,
    alert_type          TEXT NOT NULL,
    severity            TEXT NOT NULL DEFAULT 'info',
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

COMMENT ON TABLE telemetry.device_events IS 'Timeline of device connection events (connect/disconnect/changes)';
COMMENT ON TABLE telemetry.device_alerts IS 'Alerts for network device events and issues';
COMMENT ON VIEW telemetry.device_alerts_active IS 'Active (unresolved) alerts with device information';

-- ============================================================================
-- Initialization + permissions
-- ============================================================================

SELECT telemetry.ensure_syslog_partition(CURRENT_DATE);
SELECT telemetry.ensure_eventlog_partition(CURRENT_DATE);
SELECT telemetry.ensure_iis_partition(CURRENT_DATE);
SELECT telemetry.ensure_device_snapshot_partition(CURRENT_DATE);

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sysdash_ingest') THEN
        GRANT USAGE ON SCHEMA telemetry TO sysdash_ingest;
        GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA telemetry TO sysdash_ingest;
        GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA telemetry TO sysdash_ingest;
        GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA telemetry TO sysdash_ingest;
        ALTER DEFAULT PRIVILEGES IN SCHEMA telemetry GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO sysdash_ingest;
        ALTER DEFAULT PRIVILEGES IN SCHEMA telemetry GRANT USAGE, SELECT ON SEQUENCES TO sysdash_ingest;
        ALTER DEFAULT PRIVILEGES IN SCHEMA telemetry GRANT EXECUTE ON FUNCTIONS TO sysdash_ingest;
    END IF;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sysdash_reader') THEN
        GRANT USAGE ON SCHEMA telemetry TO sysdash_reader;
        GRANT SELECT ON ALL TABLES IN SCHEMA telemetry TO sysdash_reader;
        ALTER DEFAULT PRIVILEGES IN SCHEMA telemetry GRANT SELECT ON TABLES TO sysdash_reader;
    END IF;
END;
$$;

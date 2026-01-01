-- System Dashboard telemetry schema
CREATE SCHEMA IF NOT EXISTS telemetry;

-- Base template table for syslog style data
CREATE TABLE IF NOT EXISTS telemetry.syslog_generic_template (
    id              BIGSERIAL NOT NULL,
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
    PRIMARY KEY (id, received_utc)
) PARTITION BY RANGE (received_utc);

-- Helper function to create monthly partitions on demand
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

-- View that surfaces the last 24 hours of syslog data for dashboards
CREATE OR REPLACE VIEW telemetry.syslog_recent AS
SELECT *
FROM telemetry.syslog_generic_template
WHERE received_utc >= NOW() - INTERVAL '24 hours';

-- Device profiles inferred from syslog (MAC-level activity)
CREATE TABLE IF NOT EXISTS telemetry.device_profiles (
    mac_address    TEXT PRIMARY KEY,
    first_seen     TIMESTAMPTZ NOT NULL,
    last_seen      TIMESTAMPTZ NOT NULL,
    last_event_type TEXT,
    last_category  TEXT,
    last_source_host TEXT,
    last_app_name  TEXT,
    last_rssi      INTEGER,
    vendor_oui     TEXT,
    last_ip        INET,
    total_events   BIGINT NOT NULL DEFAULT 0
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

-- Unified event stream
CREATE TABLE IF NOT EXISTS telemetry.events (
    event_id       BIGSERIAL PRIMARY KEY,
    event_type     TEXT NOT NULL,
    source         TEXT NOT NULL,
    severity       TEXT,
    subject        TEXT,
    occurred_at    TIMESTAMPTZ NOT NULL,
    received_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    tags           TEXT[],
    correlation_id TEXT,
    payload        JSONB
);

CREATE INDEX IF NOT EXISTS idx_events_occurred_at ON telemetry.events (occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_events_type ON telemetry.events (event_type, occurred_at DESC);

-- Metrics time-series
CREATE TABLE IF NOT EXISTS telemetry.metrics (
    metric_id    BIGSERIAL PRIMARY KEY,
    metric_name  TEXT NOT NULL,
    metric_value DOUBLE PRECISION NOT NULL,
    metric_unit  TEXT,
    source       TEXT,
    captured_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    tags         TEXT[]
);

CREATE INDEX IF NOT EXISTS idx_metrics_captured_at ON telemetry.metrics (captured_at DESC);
CREATE INDEX IF NOT EXISTS idx_metrics_name ON telemetry.metrics (metric_name, captured_at DESC);

-- Incidents
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

-- Actions + audit trail
CREATE TABLE IF NOT EXISTS telemetry.actions (
    action_id     BIGSERIAL PRIMARY KEY,
    incident_id   BIGINT REFERENCES telemetry.incidents(incident_id) ON DELETE SET NULL,
    action_type   TEXT NOT NULL,
    status        TEXT NOT NULL DEFAULT 'requested',
    requested_by  TEXT,
    requested_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    approved_by   TEXT,
    approved_at   TIMESTAMPTZ,
    executed_at   TIMESTAMPTZ,
    completed_at  TIMESTAMPTZ,
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

-- Config snapshots
CREATE TABLE IF NOT EXISTS telemetry.config_snapshots (
    snapshot_id    BIGSERIAL PRIMARY KEY,
    source         TEXT NOT NULL,
    captured_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    config_payload JSONB NOT NULL
);

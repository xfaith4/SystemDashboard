-- System Dashboard telemetry schema
CREATE SCHEMA IF NOT EXISTS telemetry;

-- Base template table for syslog style data
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

-- Generic events table (Windows event ingestion target)
CREATE TABLE IF NOT EXISTS telemetry.events (
    event_id       BIGSERIAL PRIMARY KEY,
    event_type     TEXT,
    source         TEXT,
    severity       TEXT,
    subject        TEXT,
    occurred_at    TIMESTAMPTZ,
    received_at    TIMESTAMPTZ,
    correlation_id TEXT,
    payload        JSONB,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_events_occurred_at ON telemetry.events (occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_events_type ON telemetry.events (event_type, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_events_severity ON telemetry.events (severity, occurred_at DESC);

-- Apply grants when standard roles exist (safe no-ops if roles are absent).
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sysdash_ingest') THEN
        GRANT USAGE ON SCHEMA telemetry TO sysdash_ingest;
        GRANT INSERT, SELECT ON ALL TABLES IN SCHEMA telemetry TO sysdash_ingest;
        GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA telemetry TO sysdash_ingest;
        GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA telemetry TO sysdash_ingest;
        ALTER DEFAULT PRIVILEGES IN SCHEMA telemetry GRANT INSERT, SELECT ON TABLES TO sysdash_ingest;
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

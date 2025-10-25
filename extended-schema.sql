-- Extended schema for System Dashboard telemetry
-- This adds missing tables for Windows Events and IIS logs

-- Windows Event Log table
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

-- Helper function for Windows Event Log partitions
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

-- Recent Windows events view (last 24 hours)
CREATE OR REPLACE VIEW telemetry.eventlog_windows_recent AS
SELECT *
FROM telemetry.eventlog_windows_template
WHERE received_utc >= NOW() - INTERVAL '24 hours';

-- IIS Request Log table
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

-- Helper function for IIS log partitions
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

-- Recent IIS requests view (last 24 hours)
CREATE OR REPLACE VIEW telemetry.iis_requests_recent AS
SELECT *
FROM telemetry.iis_requests_template
WHERE received_utc >= NOW() - INTERVAL '24 hours';

-- Create initial partitions for current month
SELECT telemetry.ensure_syslog_partition(CURRENT_DATE);
SELECT telemetry.ensure_eventlog_partition(CURRENT_DATE);
SELECT telemetry.ensure_iis_partition(CURRENT_DATE);

-- Grant permissions to existing users
GRANT INSERT, SELECT ON ALL TABLES IN SCHEMA telemetry TO sysdash_ingest;
GRANT SELECT ON ALL TABLES IN SCHEMA telemetry TO sysdash_reader;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA telemetry TO sysdash_ingest;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA telemetry TO sysdash_ingest;

-- Update default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA telemetry GRANT INSERT, SELECT ON TABLES TO sysdash_ingest;
ALTER DEFAULT PRIVILEGES IN SCHEMA telemetry GRANT SELECT ON TABLES TO sysdash_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA telemetry GRANT USAGE, SELECT ON SEQUENCES TO sysdash_ingest;

-- Add indexes for common queries
CREATE INDEX IF NOT EXISTS idx_eventlog_windows_recent_time ON telemetry.eventlog_windows_template (received_utc DESC);
CREATE INDEX IF NOT EXISTS idx_eventlog_windows_level ON telemetry.eventlog_windows_template (level, received_utc DESC);
CREATE INDEX IF NOT EXISTS idx_eventlog_windows_provider ON telemetry.eventlog_windows_template (provider_name, received_utc DESC);

CREATE INDEX IF NOT EXISTS idx_iis_requests_time ON telemetry.iis_requests_template (received_utc DESC);
CREATE INDEX IF NOT EXISTS idx_iis_requests_status ON telemetry.iis_requests_template (status, received_utc DESC);
CREATE INDEX IF NOT EXISTS idx_iis_requests_client ON telemetry.iis_requests_template (client_ip, received_utc DESC);

CREATE INDEX IF NOT EXISTS idx_syslog_recent_time ON telemetry.syslog_generic_template (received_utc DESC);
CREATE INDEX IF NOT EXISTS idx_syslog_source ON telemetry.syslog_generic_template (source, received_utc DESC);
CREATE INDEX IF NOT EXISTS idx_syslog_severity ON telemetry.syslog_generic_template (severity, received_utc DESC);

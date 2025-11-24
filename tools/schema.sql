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

-- System Dashboard telemetry schema (SQL Server / T-SQL)
-- Notes:
-- - This script targets SQL Server syntax (no IF NOT EXISTS on CREATE TABLE/INDEX, no TIMESTAMPTZ/JSONB).
-- - UTC timestamps are stored as DATETIME2(7) and defaulted via SYSUTCDATETIME().

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'telemetry')
BEGIN
    EXEC(N'CREATE SCHEMA telemetry');
END;

-- Base template table for syslog style data
IF OBJECT_ID(N'telemetry.syslog_generic_template', N'U') IS NULL
BEGIN
    CREATE TABLE telemetry.syslog_generic_template (
        id              BIGINT IDENTITY(1,1) NOT NULL,
        received_utc    DATETIME2(7) NOT NULL,
        event_utc       DATETIME2(7) NULL,
        source_host     NVARCHAR(255) NULL,
        app_name        NVARCHAR(255) NULL,
        facility        SMALLINT NULL,
        severity        SMALLINT NULL,
        message         NVARCHAR(MAX) NULL,
        raw_message     NVARCHAR(MAX) NULL,
        remote_endpoint NVARCHAR(255) NULL,
        source          NVARCHAR(64) NOT NULL CONSTRAINT DF_syslog_generic_template_source DEFAULT (N'syslog'),
        created_at      DATETIME2(7) NOT NULL CONSTRAINT DF_syslog_generic_template_created_at DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_syslog_generic_template PRIMARY KEY (id, received_utc)
    );
END;

-- Partitioning helper removed (PostgreSQL-only).

-- View that surfaces the last 24 hours of syslog data for dashboards
EXEC(N'
CREATE OR ALTER VIEW telemetry.syslog_recent AS
SELECT *
FROM telemetry.syslog_generic_template
WHERE received_utc >= DATEADD(HOUR, -24, SYSUTCDATETIME());
');

-- Device profiles inferred from syslog (MAC-level activity)
IF OBJECT_ID(N'telemetry.device_profiles', N'U') IS NULL
BEGIN
    CREATE TABLE telemetry.device_profiles (
        mac_address     NVARCHAR(64) NOT NULL,
        first_seen      DATETIME2(7) NOT NULL,
        last_seen       DATETIME2(7) NOT NULL,
        last_event_type NVARCHAR(255) NULL,
        last_category   NVARCHAR(255) NULL,
        last_source_host NVARCHAR(255) NULL,
        last_app_name   NVARCHAR(255) NULL,
        last_rssi       INT NULL,
        vendor_oui      NVARCHAR(32) NULL,
        last_ip         VARCHAR(45) NULL,
        total_events    BIGINT NOT NULL CONSTRAINT DF_device_profiles_total_events DEFAULT (0),
        CONSTRAINT PK_device_profiles PRIMARY KEY (mac_address)
    );
END;

IF OBJECT_ID(N'telemetry.device_observations', N'U') IS NULL
BEGIN
    CREATE TABLE telemetry.device_observations (
        observation_id BIGINT IDENTITY(1,1) NOT NULL,
        occurred_at    DATETIME2(7) NOT NULL,
        received_at    DATETIME2(7) NOT NULL CONSTRAINT DF_device_observations_received_at DEFAULT (SYSUTCDATETIME()),
        mac_address    NVARCHAR(64) NOT NULL,
        event_type     NVARCHAR(255) NULL,
        category       NVARCHAR(255) NULL,
        source_host    NVARCHAR(255) NULL,
        app_name       NVARCHAR(255) NULL,
        rssi           INT NULL,
        ip_address     VARCHAR(45) NULL,
        message        NVARCHAR(MAX) NULL,
        raw_message    NVARCHAR(MAX) NULL,
        CONSTRAINT PK_device_observations PRIMARY KEY (observation_id)
    );
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_device_obs_mac_time' AND object_id = OBJECT_ID(N'telemetry.device_observations'))
    CREATE INDEX idx_device_obs_mac_time ON telemetry.device_observations (mac_address, occurred_at DESC);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_device_obs_category' AND object_id = OBJECT_ID(N'telemetry.device_observations'))
    CREATE INDEX idx_device_obs_category ON telemetry.device_observations (category, occurred_at DESC);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_device_obs_event_type' AND object_id = OBJECT_ID(N'telemetry.device_observations'))
    CREATE INDEX idx_device_obs_event_type ON telemetry.device_observations (event_type, occurred_at DESC);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_device_obs_time' AND object_id = OBJECT_ID(N'telemetry.device_observations'))
    CREATE INDEX idx_device_obs_time ON telemetry.device_observations (occurred_at DESC);

EXEC(N'
CREATE OR ALTER VIEW telemetry.device_observations_recent AS
SELECT *
FROM telemetry.device_observations
WHERE occurred_at >= DATEADD(HOUR, -24, SYSUTCDATETIME());
');

-- Unified event stream
IF OBJECT_ID(N'telemetry.events', N'U') IS NULL
BEGIN
    CREATE TABLE telemetry.events (
        event_id       BIGINT IDENTITY(1,1) NOT NULL,
        event_type     NVARCHAR(255) NOT NULL,
        source         NVARCHAR(255) NOT NULL,
        severity       NVARCHAR(64) NULL,
        subject        NVARCHAR(512) NULL,
        occurred_at    DATETIME2(7) NOT NULL,
        received_at    DATETIME2(7) NOT NULL CONSTRAINT DF_events_received_at DEFAULT (SYSUTCDATETIME()),
        tags           NVARCHAR(MAX) NULL,
        correlation_id NVARCHAR(255) NULL,
        payload        NVARCHAR(MAX) NULL,
        CONSTRAINT PK_events PRIMARY KEY (event_id),
        CONSTRAINT CK_events_payload_isjson CHECK (payload IS NULL OR ISJSON(payload) = 1),
        CONSTRAINT CK_events_tags_isjson CHECK (tags IS NULL OR ISJSON(tags) = 1)
    );
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_events_occurred_at' AND object_id = OBJECT_ID(N'telemetry.events'))
    CREATE INDEX idx_events_occurred_at ON telemetry.events (occurred_at DESC);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_events_type' AND object_id = OBJECT_ID(N'telemetry.events'))
    CREATE INDEX idx_events_type ON telemetry.events (event_type, occurred_at DESC);

-- Metrics time-series
IF OBJECT_ID(N'telemetry.metrics', N'U') IS NULL
BEGIN
    CREATE TABLE telemetry.metrics (
        metric_id    BIGINT IDENTITY(1,1) NOT NULL,
        metric_name  NVARCHAR(255) NOT NULL,
        metric_value FLOAT NOT NULL,
        metric_unit  NVARCHAR(64) NULL,
        source       NVARCHAR(255) NULL,
        captured_at  DATETIME2(7) NOT NULL CONSTRAINT DF_metrics_captured_at DEFAULT (SYSUTCDATETIME()),
        tags         NVARCHAR(MAX) NULL,
        CONSTRAINT PK_metrics PRIMARY KEY (metric_id),
        CONSTRAINT CK_metrics_tags_isjson CHECK (tags IS NULL OR ISJSON(tags) = 1)
    );
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_metrics_captured_at' AND object_id = OBJECT_ID(N'telemetry.metrics'))
    CREATE INDEX idx_metrics_captured_at ON telemetry.metrics (captured_at DESC);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_metrics_name' AND object_id = OBJECT_ID(N'telemetry.metrics'))
    CREATE INDEX idx_metrics_name ON telemetry.metrics (metric_name, captured_at DESC);

-- Incidents
IF OBJECT_ID(N'telemetry.incidents', N'U') IS NULL
BEGIN
    CREATE TABLE telemetry.incidents (
        incident_id BIGINT IDENTITY(1,1) NOT NULL,
        title       NVARCHAR(512) NOT NULL,
        status      NVARCHAR(64) NOT NULL CONSTRAINT DF_incidents_status DEFAULT (N'open'),
        severity    NVARCHAR(64) NOT NULL CONSTRAINT DF_incidents_severity DEFAULT (N'info'),
        summary     NVARCHAR(MAX) NULL,
        created_at  DATETIME2(7) NOT NULL CONSTRAINT DF_incidents_created_at DEFAULT (SYSUTCDATETIME()),
        updated_at  DATETIME2(7) NOT NULL CONSTRAINT DF_incidents_updated_at DEFAULT (SYSUTCDATETIME()),
        closed_at   DATETIME2(7) NULL,
        CONSTRAINT PK_incidents PRIMARY KEY (incident_id)
    );
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_incidents_status' AND object_id = OBJECT_ID(N'telemetry.incidents'))
    CREATE INDEX idx_incidents_status ON telemetry.incidents (status, created_at DESC);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_incidents_severity' AND object_id = OBJECT_ID(N'telemetry.incidents'))
    CREATE INDEX idx_incidents_severity ON telemetry.incidents (severity, created_at DESC);

IF OBJECT_ID(N'telemetry.incident_links', N'U') IS NULL
BEGIN
    CREATE TABLE telemetry.incident_links (
        incident_id BIGINT NOT NULL,
        event_id    BIGINT NOT NULL,
        confidence  FLOAT NOT NULL CONSTRAINT DF_incident_links_confidence DEFAULT (1.0),
        reason      NVARCHAR(MAX) NULL,
        created_at  DATETIME2(7) NOT NULL CONSTRAINT DF_incident_links_created_at DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_incident_links PRIMARY KEY (incident_id, event_id),
        CONSTRAINT FK_incident_links_incident FOREIGN KEY (incident_id) REFERENCES telemetry.incidents(incident_id) ON DELETE CASCADE,
        CONSTRAINT FK_incident_links_event FOREIGN KEY (event_id) REFERENCES telemetry.events(event_id) ON DELETE CASCADE
    );
END;

-- Actions + audit trail
IF OBJECT_ID(N'telemetry.actions', N'U') IS NULL
BEGIN
    CREATE TABLE telemetry.actions (
        action_id      BIGINT IDENTITY(1,1) NOT NULL,
        incident_id    BIGINT NULL,
        action_type    NVARCHAR(255) NOT NULL,
        status         NVARCHAR(64) NOT NULL CONSTRAINT DF_actions_status DEFAULT (N'requested'),
        requested_by   NVARCHAR(255) NULL,
        requested_at   DATETIME2(7) NOT NULL CONSTRAINT DF_actions_requested_at DEFAULT (SYSUTCDATETIME()),
        approved_by    NVARCHAR(255) NULL,
        approved_at    DATETIME2(7) NULL,
        executed_at    DATETIME2(7) NULL,
        completed_at   DATETIME2(7) NULL,
        action_payload NVARCHAR(MAX) NULL,
        result_payload NVARCHAR(MAX) NULL,
        CONSTRAINT PK_actions PRIMARY KEY (action_id),
        CONSTRAINT FK_actions_incident FOREIGN KEY (incident_id) REFERENCES telemetry.incidents(incident_id) ON DELETE SET NULL,
        CONSTRAINT CK_actions_action_payload_isjson CHECK (action_payload IS NULL OR ISJSON(action_payload) = 1),
        CONSTRAINT CK_actions_result_payload_isjson CHECK (result_payload IS NULL OR ISJSON(result_payload) = 1)
    );
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_actions_status' AND object_id = OBJECT_ID(N'telemetry.actions'))
    CREATE INDEX idx_actions_status ON telemetry.actions (status, requested_at DESC);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_actions_incident' AND object_id = OBJECT_ID(N'telemetry.actions'))
    CREATE INDEX idx_actions_incident ON telemetry.actions (incident_id, requested_at DESC);

IF OBJECT_ID(N'telemetry.action_audit', N'U') IS NULL
BEGIN
    CREATE TABLE telemetry.action_audit (
        audit_id   BIGINT IDENTITY(1,1) NOT NULL,
        action_id  BIGINT NOT NULL,
        step       NVARCHAR(255) NOT NULL,
        status     NVARCHAR(64) NOT NULL,
        message    NVARCHAR(MAX) NULL,
        created_at DATETIME2(7) NOT NULL CONSTRAINT DF_action_audit_created_at DEFAULT (SYSUTCDATETIME()),
        metadata   NVARCHAR(MAX) NULL,
        CONSTRAINT PK_action_audit PRIMARY KEY (audit_id),
        CONSTRAINT FK_action_audit_action FOREIGN KEY (action_id) REFERENCES telemetry.actions(action_id) ON DELETE CASCADE,
        CONSTRAINT CK_action_audit_metadata_isjson CHECK (metadata IS NULL OR ISJSON(metadata) = 1)
    );
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_action_audit_action' AND object_id = OBJECT_ID(N'telemetry.action_audit'))
    CREATE INDEX idx_action_audit_action ON telemetry.action_audit (action_id, created_at DESC);

-- Config snapshots
IF OBJECT_ID(N'telemetry.config_snapshots', N'U') IS NULL
BEGIN
    CREATE TABLE telemetry.config_snapshots (
        snapshot_id    BIGINT IDENTITY(1,1) NOT NULL,
        source         NVARCHAR(255) NOT NULL,
        captured_at    DATETIME2(7) NOT NULL CONSTRAINT DF_config_snapshots_captured_at DEFAULT (SYSUTCDATETIME()),
        config_payload NVARCHAR(MAX) NOT NULL,
        CONSTRAINT PK_config_snapshots PRIMARY KEY (snapshot_id),
        CONSTRAINT CK_config_snapshots_payload_isjson CHECK (ISJSON(config_payload) = 1)
    );
END;

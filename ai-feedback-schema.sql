-- AI Feedback storage schema for System Dashboard
-- Stores AI-generated explanations for Windows Event Log entries
-- with review status workflow (Pending, Viewed, Resolved)

CREATE TABLE IF NOT EXISTS telemetry.ai_feedback (
    id                  BIGSERIAL PRIMARY KEY,
    event_id            INTEGER,                -- Windows Event ID
    event_source        TEXT,                   -- Event provider/source name
    event_message       TEXT NOT NULL,          -- Original event message
    event_log_type      TEXT,                   -- Application, System, Security
    event_level         TEXT,                   -- Error, Warning, Information
    event_time          TIMESTAMPTZ,            -- When the event occurred
    ai_response         TEXT NOT NULL,          -- AI-generated explanation
    review_status       TEXT NOT NULL           -- Pending, Viewed, Resolved
                        CHECK (review_status IN ('Pending', 'Viewed', 'Resolved'))
                        DEFAULT 'Viewed',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for efficient querying by review status
CREATE INDEX IF NOT EXISTS idx_ai_feedback_review_status 
ON telemetry.ai_feedback(review_status);

-- Index for querying by event details
CREATE INDEX IF NOT EXISTS idx_ai_feedback_event_id 
ON telemetry.ai_feedback(event_id);

-- Index for time-based queries
CREATE INDEX IF NOT EXISTS idx_ai_feedback_created_at 
ON telemetry.ai_feedback(created_at DESC);

-- Composite index for common filter patterns
CREATE INDEX IF NOT EXISTS idx_ai_feedback_status_created 
ON telemetry.ai_feedback(review_status, created_at DESC);

-- Function to automatically update the updated_at timestamp
CREATE OR REPLACE FUNCTION telemetry.update_ai_feedback_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to call the update function
DROP TRIGGER IF EXISTS trg_ai_feedback_updated_at ON telemetry.ai_feedback;
CREATE TRIGGER trg_ai_feedback_updated_at
    BEFORE UPDATE ON telemetry.ai_feedback
    FOR EACH ROW
    EXECUTE FUNCTION telemetry.update_ai_feedback_updated_at();

-- View for recent AI feedback (last 30 days)
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

-- View for unresolved AI feedback (Pending or Viewed status)
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
'Stores AI-generated explanations for Windows Event Log entries with review workflow';

COMMENT ON COLUMN telemetry.ai_feedback.review_status IS 
'Review status workflow: Pending (not yet reviewed), Viewed (acknowledged), Resolved (action taken)';

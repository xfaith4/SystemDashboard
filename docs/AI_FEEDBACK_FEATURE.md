# AI Feedback Persistence and Review Workflow

## Overview

The AI Feedback feature provides persistent storage and a review workflow for AI-generated explanations of Windows Event Log entries. When users click "Ask AI" to get explanations for events, those explanations are automatically saved to the database and can be reviewed later with status tracking.

## Features

### 1. Automatic Persistence

- All AI-generated event explanations are automatically saved to the database
- No additional user action required - happens transparently when AI generates a response
- Initial status is set to "Viewed" (indicating the user has seen the explanation)

### 2. Review Status Workflow

Three status levels for tracking feedback lifecycle:

- **Pending**: Marked for later review or action
- **Viewed**: Default status when AI generates explanation (user has seen it)
- **Resolved**: User has taken action based on the feedback

### 3. Historical Review

- View all previously analyzed events with their AI explanations
- Filter by review status (All, Pending, Viewed, Resolved)
- Display event details including source, log type, level, and timestamp
- Shows both original event message and AI analysis

### 4. Interactive Status Management

- Update review status via dropdown for each feedback entry
- Changes are immediately persisted to the database
- Visual indicators (color coding) for each status

## Database Schema

### Table: `telemetry.ai_feedback`

| Column | Type | Description |
|--------|------|-------------|
| id | BIGSERIAL | Primary key |
| event_id | INTEGER | Windows Event ID |
| event_source | TEXT | Event provider/source name |
| event_message | TEXT | Original event message (required) |
| event_log_type | TEXT | Application, System, or Security |
| event_level | TEXT | Error, Warning, Information |
| event_time | TIMESTAMPTZ | When the event occurred |
| ai_response | TEXT | AI-generated explanation (required) |
| review_status | TEXT | Pending, Viewed, or Resolved |
| created_at | TIMESTAMPTZ | When feedback was created |
| updated_at | TIMESTAMPTZ | Last update timestamp |

### Indexes

- `idx_ai_feedback_review_status` - Fast filtering by status
- `idx_ai_feedback_event_id` - Quick lookup by event ID
- `idx_ai_feedback_created_at` - Time-based queries
- `idx_ai_feedback_status_created` - Composite for status + time filtering

### Views

- `telemetry.ai_feedback_recent` - Last 30 days of feedback
- `telemetry.ai_feedback_unresolved` - Only Pending and Viewed entries

## API Endpoints

### POST `/api/ai/feedback`

Creates a new AI feedback entry.

**Request Body:**

```json
{
  "event_id": 1001,
  "event_source": "Application Error",
  "event_message": "Application has stopped working",
  "event_log_type": "Application",
  "event_level": "Error",
  "event_time": "2024-01-01T12:00:00Z",
  "ai_response": "This error indicates...",
  "review_status": "Viewed"
}
```

**Response (201 Created):**

```json
{
  "status": "ok",
  "id": 1,
  "created_at": "2024-01-01T12:00:00Z",
  "updated_at": "2024-01-01T12:00:00Z"
}
```

**Validation:**

- `event_message` is required
- `ai_response` is required
- `review_status` must be one of: Pending, Viewed, Resolved

### GET `/api/ai/feedback`

Retrieves AI feedback entries with optional filtering.

**Query Parameters:**

- `limit` (default: 50, max: 200) - Number of entries per page
- `offset` (default: 0) - Pagination offset
- `status` - Filter by review status
- `log_type` - Filter by event log type
- `since_days` (default: 30, max: 365) - Time range in days

**Response (200 OK):**

```json
{
  "feedback": [
    {
      "id": 1,
      "event_id": 1001,
      "event_source": "Application Error",
      "event_message": "Application has stopped working",
      "event_log_type": "Application",
      "event_level": "Error",
      "event_time": "2024-01-01T10:00:00Z",
      "ai_response": "This error indicates...",
      "review_status": "Viewed",
      "created_at": "2024-01-01T12:00:00Z",
      "updated_at": "2024-01-01T12:00:00Z"
    }
  ],
  "total": 42,
  "limit": 50,
  "offset": 0,
  "source": "database"
}
```

### PATCH `/api/ai/feedback/<id>/status`

Updates the review status of a feedback entry.

**Request Body:**

```json
{
  "status": "Resolved"
}
```

**Response (200 OK):**

```json
{
  "status": "ok",
  "id": 1,
  "review_status": "Resolved",
  "updated_at": "2024-01-01T15:00:00Z"
}
```

**Validation:**

- `status` must be one of: Pending, Viewed, Resolved

## Frontend Integration

### Location

The AI Feedback History section appears on the System Events page (`/events`) below the events table.

### Components

1. **Header Section**
   - Title: "AI Feedback History"
   - Subtitle: "Previously analyzed events with AI-generated explanations"
   - Status filter dropdown
   - Refresh button

2. **Feedback List**
   - Each entry shows:
     - Event source and ID
     - Event log type and level (badges)
     - Timestamp
     - Original event message (truncated)
     - AI analysis
     - Status dropdown (interactive)

3. **Empty State**
   - Displayed when no feedback exists
   - Prompts users to use "Ask AI" to create entries

### User Flow

1. User views System Events page
2. User clicks "Ask AI" on any event
3. AI modal displays explanation
4. Explanation is automatically saved with status="Viewed"
5. AI Feedback History section refreshes to show new entry
6. User can change status via dropdown
7. Status change persists immediately to database

## Installation

### 1. Apply Database Schema

```bash
psql -h <host> -U <user> -d <database> -f ai-feedback-schema.sql
```

Or if using the setup script:

```bash
./scripts/setup-database.ps1
# Schema is automatically applied
```

### 2. No Application Changes Required

The feature is automatically available once the schema is applied. No configuration needed.

## Usage Examples

### Example 1: Viewing All Feedback

1. Navigate to System Events page (`/events`)
2. Scroll to "AI Feedback History" section
3. Set status filter to "All"
4. Click "Refresh" to reload

### Example 2: Managing Review Workflow

1. Use "Ask AI" on several events to generate feedback
2. View entries with status="Viewed" (default)
3. For items requiring action, change status to "Pending"
4. After taking action, update status to "Resolved"
5. Filter by status to focus on specific items

### Example 3: Tracking Recurring Issues

1. Use "Ask AI" on similar errors over time
2. Filter feedback by event source or log type
3. Review AI explanations to identify patterns
4. Mark resolved once root cause is addressed

## Security Considerations

### Input Validation

- All text fields are truncated to reasonable limits
- Review status values are validated against allowed list
- Numeric parameters (IDs, limits) are properly typed and bounded

### SQL Injection Prevention

- All database queries use parameterized statements
- No string concatenation in SQL queries
- Validated and sanitized user inputs

### Access Control

- Database credentials required (via environment variables)
- No authentication bypass - relies on existing dashboard auth
- Database connection failures gracefully handled

## Performance

### Optimizations

- Indexed columns for fast filtering and sorting
- Pagination prevents loading large result sets
- Views pre-filter common queries (recent, unresolved)
- Automatic updated_at timestamp via trigger (minimal overhead)

### Scalability

- Partitioning can be added if table grows very large
- Old feedback can be archived/purged after retention period
- Limit queries to last 30 days by default

## Monitoring and Observability

### Logging

All API operations are logged with:

- Request parameters
- Success/failure status
- Error details (if any)

### Metrics to Monitor

- Number of feedback entries created per day
- Distribution of review statuses
- Average time in each status
- Failed API requests

## Troubleshooting

### Feedback Not Saving

1. Check database connection: `DASHBOARD_DB_*` environment variables
2. Verify schema is applied: `SELECT * FROM telemetry.ai_feedback LIMIT 1;`
3. Check browser console for API errors
4. Review Flask application logs

### Empty History Section

1. Verify database contains data: `SELECT COUNT(*) FROM telemetry.ai_feedback;`
2. Check status filter - may be filtering out all entries
3. Try clicking "Refresh" button
4. Check browser console for fetch errors

### Status Updates Not Persisting

1. Verify PATCH endpoint is working: Check network tab in browser
2. Confirm database user has UPDATE permissions
3. Check for constraint violations in logs
4. Verify updated_at trigger is installed

## Future Enhancements

Potential improvements for consideration:

- Export feedback to CSV/JSON for reporting
- Bulk status updates (select multiple, update all)
- Search within AI responses
- Tagging/categorization of feedback
- Email notifications for critical feedback
- Integration with ticketing systems
- AI trend analysis across multiple feedback entries
- Similarity detection for related events

## Support

For issues or questions:

1. Check application logs for errors
2. Verify database schema is up to date
3. Review browser console for frontend errors
4. Ensure all tests pass: `pytest tests/test_ai_feedback.py -v`

# SystemDashboard Roadmap

## Executive Summary

- Reframe the product around two user questions: **"What changed?"** and **"What should I do now?"**
- Unify telemetry + configuration + action history in one schema with provenance and confidence.
- Build a safe remediation engine with approvals, rollback, and audit.
- Converge on one runtime (Pode) and keep Flask as legacy until parity is reached.
- Deliver a minimal autonomous fix MVP (router DNS failure remediation) early.

## Phase Plan

### 0–3 months: Foundation

- Consolidate data sources into a single normalized schema.
- Implement provenance + confidence scoring for every insight.
- Standardize config + secrets handling (local-only, least privilege).
- Create "Incident" model and timeline UI: what changed → why → action options.

### 3–6 months: Action Plane

- Introduce a remediation policy engine (read-only → safe → elevated).
- Add scripted fix library with dry-run + rollback for each action.
- Implement approval gates and audit logging.
- Start "Action Suggestions" UX with confidence and risk annotations.

### 6–12 months: Autonomy & Optimization

- Add autonomy modes (Recommend / Auto-fix / Observe only).
- Expand closed-loop fixes (network, storage, service restarts, router config).
- Add proactive config drift detection and optimization suggestions.
- Refine intelligence with local model + optional cloud advisory.

## Target Architecture

### Data Plane

- **Collectors:** Syslog, Windows Event Log, Performance Metrics, Router Poll, Service Health.
- **Normalizer:** Canonical event schema, tags, correlation IDs, timestamps.
- **Storage:** PostgreSQL with partitioned event tables + compact summaries.

### Reasoning Plane

- **Correlation engine:** rules + learned patterns + feature stores.
- **Confidence model:** data freshness, source reliability, and contradiction checks.
- **Hypothesis registry:** track cause, impact, and next best action.

### Action Plane

- **Policy engine:** "read-only", "safe", "elevated" action classes.
- **Executor:** PowerShell scripts with dry-run and rollback.
- **Audit + approval:** signed actions, approvals, and reason codes.

### UI Plane

- **Primary:** "What changed?" timeline (incidents).
- **Secondary:** "Fix it" action center with risk & rollback info.
- **Debug:** full telemetry explorer for power users.

### Schema Draft (PostgreSQL)

```sql
CREATE TABLE telemetry.events (
  event_id UUID PRIMARY KEY,
  event_type VARCHAR NOT NULL,
  source VARCHAR NOT NULL,
  timestamp TIMESTAMPTZ NOT NULL,
  payload_json JSONB,
  tags TEXT[] DEFAULT '{}'
);

CREATE TABLE telemetry.metrics (
  metric_id UUID PRIMARY KEY,
  metric_name VARCHAR NOT NULL,
  value NUMERIC NOT NULL,
  unit VARCHAR,
  timestamp TIMESTAMPTZ NOT NULL,
  source VARCHAR NOT NULL
);

CREATE TABLE telemetry.incidents (
  incident_id UUID PRIMARY KEY,
  title VARCHAR NOT NULL,
  status VARCHAR NOT NULL,
  severity VARCHAR NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  closed_at TIMESTAMPTZ
);

CREATE TABLE telemetry.incident_links (
  incident_id UUID REFERENCES telemetry.incidents(incident_id),
  event_id UUID REFERENCES telemetry.events(event_id),
  confidence NUMERIC CHECK (confidence >= 0 AND confidence <= 1),
  reason TEXT,
  PRIMARY KEY (incident_id, event_id)
);

CREATE TABLE telemetry.actions (
  action_id UUID PRIMARY KEY,
  incident_id UUID REFERENCES telemetry.incidents(incident_id),
  action_type VARCHAR NOT NULL,
  status VARCHAR NOT NULL,
  requested_by VARCHAR NOT NULL,
  executed_at TIMESTAMPTZ
);

CREATE TABLE telemetry.action_audit (
  audit_id UUID PRIMARY KEY,
  action_id UUID REFERENCES telemetry.actions(action_id),
  step INT NOT NULL,
  stdout TEXT,
  stderr TEXT,
  exit_code INT,
  rollback_id UUID REFERENCES telemetry.actions(action_id)
);

CREATE TABLE telemetry.config_snapshots (
  snapshot_id UUID PRIMARY KEY,
  source VARCHAR NOT NULL,
  captured_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  config_json JSONB
);
```

### Remediation Policy Framework

**Levels:** ReadOnly, Safe, Elevated

**Rules:**

- Auto-fix only if confidence ≥ 0.85 and action is reversible
- Require user approval for Elevated
- Every action stores pre-state and rollback command

**Examples:**

- **Safe:** restart a telemetry service, flush DNS cache, renew DHCP
- **Elevated:** change router firewall/QoS settings (requires explicit approval)

### Testing Strategy

- **Synthetic incidents:** Router down, DNS poisoning, disk full, stalled service, event log flood.
- **Metrics:** Time-to-detect, time-to-resolve, false positive rate, rollback success rate.
- **E2E:** "Home outage" replay harness that validates UI + action plan.

### Refactor Steps (Repo-Specific)

- Consolidate to one primary runtime: 2025-09-11 Pode module becomes canonical.
- Standardize scripts under `scripting/` (done), and update tools to read from `config.json`.
- Add `scripting/actions/` and `scripting/policies/` for remediation plans.
- Create `app/ai/` for local inference + prompt templates + safety layer.
- Add telemetry/action modules in `SystemDashboard.Telemetry.psm1`.

### Minimal Autonomous Fix MVP (DNS Failure)

**Detection:**

- Correlate router DNS errors + client resolution timeouts + event log warnings.

**Recommendation:**

- Suggest switching to fallback DNS (1.1.1.1/8.8.8.8) or restart DNS service.

**Action:**

- Provide safe auto-fix: local DNS flush + DHCP renew.
- Provide elevated action: update router DNS settings (requires approval).

**Rollback:**

- Save previous DNS config; revert on failure.

## Future Considerations

- **Integrate with CI/CD:** Explore automated testing and deployment of dashboard components.
- **Cloud Integration:** Investigate options for cloud-based data storage, processing, and AI models for enhanced scalability and intelligence.
- **Community Contributions:** Establish guidelines and processes for accepting external contributions to the project.
- **Security Hardening:** Conduct regular security audits and penetration testing to ensure the robustness of the system.
- **Performance Optimization:** Continuously monitor and optimize the performance of data collection, processing, and UI rendering.

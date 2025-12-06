# SystemDashboard Roadmap

## Overview

This roadmap focuses on **hardening existing features** and delivering a **professional, production-ready UI**. No new features are planned—the goal is to make what we have more robust, reliable, and user-friendly.

---

## 🎯 Guiding Principles

1. **Stability First**: All existing features should work reliably under various conditions
2. **Error Resilience**: Graceful degradation when services are unavailable
3. **Professional Polish**: UI should feel complete, consistent, and intuitive
4. **Performance**: Fast page loads, efficient database queries, responsive interactions
5. **Observability**: Better logging, monitoring, and diagnostics for troubleshooting

---

## 📋 Phase 1: Core Stability & Error Handling

### Database & Data Layer
- [x] **Connection pooling**: Implement proper SQLite connection management to prevent "database is locked" errors
  - ✅ Implemented ConnectionPool class with WAL mode and thread-safe access
  - ✅ Configurable max connections and automatic connection reuse
- [x] **Query optimization**: Add indexes for frequently-queried columns (timestamps, MAC addresses, severity levels)
  - ✅ Created migration system with 001_add_performance_indexes.sql
  - ✅ Added indexes on timestamps, MAC addresses, severity, device_id, status
- [x] **Transaction safety**: Wrap multi-statement operations in transactions
  - ✅ Automatic rollback on errors in DatabaseManager
  - ✅ Context manager pattern ensures proper cleanup
- [x] **Connection retry logic**: Exponential backoff for transient database failures
  - ✅ execute_with_retry() method with configurable retries
  - ✅ Exponential backoff for "database is locked" errors
- [x] **Query timeouts**: Set appropriate timeouts to prevent hanging queries
  - ✅ 10-second default timeout on all connections
  - ✅ Configurable busy_timeout pragma
- [x] **Schema validation**: Add startup check to ensure all required tables and views exist
  - ✅ validate_schema() method checks required tables and views
  - ✅ Returns detailed list of missing objects

### Service Reliability
- [ ] **Service heartbeat**: Add health check endpoints that verify database connectivity and data freshness
- [ ] **Graceful shutdown**: Ensure services close connections and flush buffers on stop
- [ ] **Error recovery**: Automatic restart logic for critical background tasks
- [ ] **Rate limiting**: Prevent collection services from overwhelming the router or database
- [ ] **Backpressure handling**: Queue management when ingestion can't keep up with collection
- [ ] **State persistence**: Ensure state files (like `asus/state.json`) are atomic writes

### API Endpoints
- [x] **Input validation**: Strict validation for all query parameters (dates, MAC addresses, IP addresses)
  - ✅ Created validators.py with comprehensive validation functions
  - ✅ MAC address validation and normalization
  - ✅ IP address validation with private IP detection
  - ✅ Date range validation, pagination, severity, tags, and more
- [x] **Pagination limits**: Enforce maximum page sizes to prevent memory exhaustion
  - ✅ validate_pagination() enforces configurable max limits
  - ✅ Automatically caps excessive limit values
- [x] **Response caching**: Cache expensive queries (e.g., 24-hour summaries) with appropriate TTLs
  - ✅ @cache_response decorator with configurable TTL
  - ✅ Automatic cache cleanup of expired entries
- [x] **Error responses**: Consistent JSON error format across all endpoints
  - ✅ Created api_utils.py with error_response() and success_response()
  - ✅ Standardized format with timestamp and status code
  - ✅ @handle_api_errors decorator for consistent exception handling
- [ ] **Rate limiting**: Per-client API rate limits for public-facing endpoints
- [x] **CORS headers**: Proper CORS configuration if serving UI from different origin
  - ✅ @with_cors decorator for adding CORS headers
  - ✅ Handles preflight OPTIONS requests

---

## 🎨 Phase 2: UI Polish & Professionalism

### Visual Consistency
- [ ] **Design system audit**: Document all color variables, spacing, typography in use
- [ ] **Component library**: Extract reusable card, button, table, badge components
- [ ] **Icon consistency**: Use a single icon set (current SVGs are good, just ensure completeness)
- [ ] **Loading states**: Skeleton screens or spinners for all async data loads
- [ ] **Empty states**: Friendly messages when no data exists (better than showing zeros)
- [ ] **Error states**: Clear, actionable error messages with recovery suggestions

### Navigation & UX
- [ ] **Breadcrumbs**: Add breadcrumb navigation for device detail pages
- [ ] **Back buttons**: Consistent "back to list" navigation on detail pages
- [ ] **Search persistence**: Remember search/filter state when navigating back
- [ ] **Keyboard shortcuts**: Add hotkeys for common actions (refresh, navigate pages)
- [ ] **Responsive design**: Ensure all pages work on tablets (1024px and down)
- [ ] **Mobile optimization**: Test on 768px and 375px viewports, make critical views usable

### Data Presentation
- [ ] **Chart improvements**:
  - [ ] Add zoom/pan to charts with lots of data
  - [ ] Responsive chart sizing (adapt to viewport)
  - [ ] Export chart data to CSV
  - [ ] Tooltips with full context (timestamp, value, device name)
- [ ] **Table enhancements**:
  - [ ] Column sorting on all tables
  - [ ] Column visibility toggles (show/hide columns)
  - [ ] Bulk actions (e.g., tag multiple devices at once)
  - [ ] Row selection with checkboxes
  - [ ] Export to CSV
- [ ] **Timestamp formatting**: Consistent relative times ("5 minutes ago") with absolute on hover
- [ ] **Data refresh indicators**: Visual cue when data is stale or refreshing

### Forms & Inputs
- [ ] **Form validation**: Real-time validation with clear error messages
- [ ] **Input helpers**: Placeholder examples, format hints (e.g., "MAC: AA:BB:CC:DD:EE:FF")
- [ ] **Autosave**: Device nickname/location changes save automatically with "Saved" indicator
- [ ] **Undo functionality**: Allow reverting recent changes (especially for bulk edits)
- [ ] **Confirmation dialogs**: For destructive actions (clear alerts, delete devices)

### Notifications & Feedback
- [ ] **Toast notifications**: Unobtrusive success/error messages in corner (instead of alerts)
- [ ] **Progress indicators**: For long-running operations (data collection, exports)
- [ ] **System status banner**: Persistent banner when services are degraded
- [ ] **Alert badge**: Show count of unacknowledged alerts in navigation

---

## 🔒 Phase 3: Security & Hardening

### Authentication & Authorization
- [ ] **Session management**: Add basic auth or API key authentication for production
- [ ] **CSRF protection**: Enable Flask CSRF for state-changing operations
- [ ] **Secure headers**: Set CSP, X-Frame-Options, X-Content-Type-Options
- [ ] **HTTPS enforcement**: Document TLS setup, provide script for self-signed cert generation
- [ ] **Credential rotation**: Document best practices for rotating router passwords

### Input Sanitization
- [ ] **SQL injection prevention**: Audit all queries for parameterization (already good, verify 100%)
- [ ] **XSS prevention**: Ensure all user-provided content is escaped in templates
- [ ] **Path traversal**: Validate file paths in log export features
- [ ] **Command injection**: Audit PowerShell execution for user input (should be none)

### Logging & Audit
- [ ] **Structured logging**: Consistent log format (JSON?) for easy parsing
- [ ] **Log levels**: Proper use of DEBUG, INFO, WARNING, ERROR, CRITICAL
- [ ] **Sensitive data**: Never log passwords, tokens, or full MAC addresses in production logs
- [ ] **Audit trail**: Log configuration changes (device nicknames, tag updates, alert resolutions)
- [ ] **Log rotation**: Ensure service logs rotate and don't fill disk

---

## 📊 Phase 4: Performance & Scalability

### Query Performance
- [ ] **Slow query logging**: Identify queries > 100ms, optimize or add indexes
- [ ] **Materialized view refresh**: Ensure views refresh efficiently (incremental if possible)
- [ ] **Pagination strategy**: Use keyset pagination instead of OFFSET for large tables
- [ ] **Query plan analysis**: Use `EXPLAIN QUERY PLAN` to optimize hot paths
- [ ] **Data retention enforcement**: Automatic cleanup of old snapshots (already exists, verify it runs)

### Frontend Performance
- [ ] **Asset optimization**: Minify CSS/JS, optimize images if any
- [ ] **CDN integrity**: Ensure Chart.js and other CDN assets have SRI hashes (already done, verify)
- [ ] **Lazy loading**: Load charts only when scrolled into view
- [ ] **Debounce/throttle**: Search inputs and filter changes should debounce API calls
- [ ] **Service worker**: Consider offline support for static assets

### Resource Management
- [ ] **Memory profiling**: Ensure services don't leak memory over days of runtime
- [ ] **Connection limits**: Limit concurrent database connections
- [ ] **Disk space monitoring**: Alert when database or log directories approach capacity
- [ ] **CPU throttling**: Ensure collection loops don't peg CPU during idle periods

---

## 📖 Phase 5: Documentation & Onboarding

### User Documentation
- [ ] **Getting Started guide**: Streamline installation for new users
- [ ] **Dashboard tour**: Annotated screenshots explaining each page
- [ ] **FAQ section**: Common questions (where is data stored, how to reset DB, etc.)
- [ ] **Troubleshooting playbook**: Step-by-step for common issues
- [ ] **Video walkthrough**: 5-minute intro video (optional but nice)

### Developer Documentation
- [ ] **Architecture diagram**: Update with current service layout
- [ ] **API reference**: Swagger/OpenAPI spec for all endpoints
- [ ] **Database schema docs**: ER diagram, table descriptions, view purposes
- [ ] **Code contribution guide**: How to add tests, run locally, submit PRs
- [ ] **Release process**: How to tag versions, generate changelogs

### Operations Documentation
- [ ] **Deployment guide**: Production setup (Windows Server, IIS, SSL, firewall)
- [ ] **Backup & restore**: How to backup database, restore from backup
- [ ] **Monitoring setup**: Recommended alerts and health checks
- [ ] **Performance tuning**: Configuration options for high-volume environments
- [ ] **Upgrade path**: How to migrate from older versions

---

## 🧪 Phase 6: Testing & Quality Assurance

### Test Coverage
- [ ] **Unit tests**: Maintain >80% coverage for app.py and service modules
- [ ] **Integration tests**: End-to-end tests for critical workflows (device discovery, alert lifecycle)
- [ ] **Performance tests**: Benchmark query response times under load
- [ ] **Browser testing**: Verify in Chrome, Firefox, Edge, Safari
- [ ] **Accessibility testing**: Run axe-core or similar tool, fix critical issues

### Quality Checks
- [ ] **Linting**: Add flake8/black for Python, ESLint for JavaScript
- [ ] **Type checking**: Add mypy annotations to critical functions
- [ ] **Dependency updates**: Audit requirements.txt for CVEs, update safely
- [ ] **Code review checklist**: Document what to look for in PRs
- [ ] **CI/CD pipeline**: Automate tests, linting, security scans on every commit

---

## 🚀 Phase 7: Production Readiness

### Deployment Automation
- [ ] **Installation script improvements**: Idempotent install (can run multiple times safely)
- [ ] **Configuration validation**: Script that checks config.json for common mistakes
- [ ] **Environment detection**: Auto-detect Windows version, PowerShell version, Python version
- [ ] **Dependency checker**: Verify all prerequisites before install
- [ ] **Uninstall script**: Clean removal of services, scheduled tasks, modules

### Monitoring & Alerting
- [ ] **Service health dashboard**: Dedicated page showing service status, last run times, error counts
- [ ] **Alert rules**: Define thresholds for critical issues (DB size, service down, error rate spike)
- [ ] **Email notifications**: Send alerts via SMTP when issues detected
- [ ] **Integration hooks**: Webhooks for external monitoring (PagerDuty, Slack, etc.)

### Operations Tooling
- [ ] **Backup script**: Automated SQLite backup with configurable retention
- [ ] **Database vacuum**: Scheduled job to reclaim space from deleted rows
- [ ] **Log archival**: Compress and archive old service logs
- [ ] **Health check endpoint**: `/api/health` with detailed subsystem status
- [ ] **Metrics export**: Prometheus-compatible metrics endpoint (optional)

---

## 🎨 UI/UX Quick Wins (High Impact, Low Effort)

These are small improvements that can be done quickly but have outsized impact on perceived quality:

1. **Add favicons**: Professional branding in browser tabs
2. **Loading placeholders**: Skeleton UI instead of "Loading..." text
3. **Hover states**: All interactive elements should respond to hover
4. **Focus indicators**: Visible focus rings for keyboard navigation
5. **Consistent spacing**: Use CSS variables for all spacing (already started, finish it)
6. **Button hierarchy**: Primary, secondary, tertiary styles clearly distinguished
7. **Status badges**: Color-coded, rounded badges for device states (online/offline/new)
8. **Tooltips**: Add helpful tooltips to all icons and abbreviations
9. **Footer**: Add version number, docs link, GitHub link to footer
10. **Page titles**: Ensure `<title>` tags reflect current page content

---

## 📅 Suggested Timeline

This roadmap is **aggressive but achievable** over 8-12 weeks with focused effort:

- **Weeks 1-2**: Phase 1 (Core Stability)
- **Weeks 3-4**: Phase 2 (UI Polish) + Phase 7 quick wins
- **Weeks 5-6**: Phase 3 (Security) + Phase 4 (Performance)
- **Weeks 7-8**: Phase 5 (Documentation) + Phase 6 (Testing)
- **Weeks 9-10**: Phase 7 (Production Readiness) + Bug fixes
- **Weeks 11-12**: User feedback, final polish, production deployment

---

## ✅ Definition of Done

Each phase is complete when:

1. All checklist items are implemented
2. New code has test coverage ≥80%
3. Documentation is updated
4. Manual QA completed (smoke tests)
5. Code review approved
6. Deployed to staging environment (if applicable)

The **entire roadmap** is complete when:

- The dashboard can run 24/7 without intervention
- UI feels polished and professional (no rough edges)
- Documentation enables new users to self-serve
- All tests pass in CI
- Security scan (CodeQL) reports zero critical/high issues
- Performance benchmarks meet targets (pages load <500ms, APIs <100ms)

---

## 🤝 Contributing

This roadmap is a living document. If you:

- Find a critical issue not covered here → file an issue and we'll add it
- Complete a task → submit a PR updating this doc (move to "Done" section)
- Disagree with prioritization → open a discussion, let's talk!

The goal is to make SystemDashboard **production-ready and delightful to use**. Let's do this! 🚀

---

## 📜 Version History

- **2025-12-05**: Initial roadmap created
  - Focus: Hardening existing features and professional UI polish
  - No new features planned
  - Target: Production-ready in 8-12 weeks

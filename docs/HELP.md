# System Dashboard Help Guide

Welcome to the System Dashboard Help Guide! This page explains what each section, panel, and graph shows, and teaches you how to interpret the data to make informed decisions about your home infrastructure.

## Dashboard Overview

The System Dashboard is a comprehensive network operations center (NOC) dashboard for monitoring your home lab or network infrastructure. It collects logs from Windows systems, ASUS routers, and network devices to provide real-time visibility into your environment's health and performance.

**What you'll monitor:**
- **IIS Server Health**: Web server errors and performance issues
- **Authentication Activity**: Failed login attempts and potential security threats
- **Windows System Events**: Critical errors, warnings, and system health
- **Router Activity**: Network device logs, WAN issues, and connectivity problems
- **LAN Devices**: Real-time tracking of devices on your network, signal strength, and connectivity

---

## 1. Operations Overview (Dashboard)

**Path:** `/` (Home page)

The Operations Overview is your main dashboard, providing a bird's-eye view of your infrastructure's health. This is where you should start each day to identify any issues that need attention.

### Primary KPI Cards

These four cards at the top show critical metrics that require immediate attention when they spike:

#### IIS Server Errors
**What it shows:** The number of HTTP 5xx errors from IIS in the last 5 minutes, compared to a baseline.

**Tooltip:** "Tracks IIS 5xx server errors in real-time. Normal: 0-2 errors. Concerning: Spike above baseline with red alert indicator. Investigate immediately if the card turns red."

**Normal vs Concerning:**
- ✅ **Normal**: 0-2 errors over 5 minutes, no red alert
- ⚠️ **Concerning**: Red "Spike detected" alert appears, errors exceed baseline by significant margin
- **What to do**: Click through to check IIS logs, review recent deployments, check server resource usage

#### Auth Failures
**What it shows:** Number of unique client IPs with repeated authentication failures in the last 15 minutes.

**Tooltip:** "Displays authentication burst events from unique IPs. Normal: 0-1 clients. Concerning: 3+ clients with repeated failures. May indicate brute force attacks or misconfigured services."

**Normal vs Concerning:**
- ✅ **Normal**: 0-1 clients, card is neutral colored
- ⚠️ **Concerning**: 3+ clients shown with warning badge, card turns yellow/orange
- **What to do**: Review the Authentication Bursts panel below, check if IPs are internal or external, investigate affected accounts

#### Windows Events
**What it shows:** Count of Windows Critical and Error level events in the last 10 minutes.

**Tooltip:** "Shows critical and error-level Windows events. Normal: 0-3 events. Concerning: 5+ events or recurring pattern. Check the Windows Critical Events panel for details."

**Normal vs Concerning:**
- ✅ **Normal**: 0-3 events, mostly routine warnings
- ⚠️ **Concerning**: 5+ events, card turns yellow, recurring errors from same source
- **What to do**: Navigate to System Events page, filter by Error/Critical, identify problem sources

#### Router Alerts
**What it shows:** Recent anomalous router events (WAN drops, DHCP issues, authentication problems).

**Tooltip:** "Router syslog anomalies including WAN issues, DHCP errors, and auth failures. Normal: 0-2 events. Concerning: 5+ events or repeated WAN drops. May indicate ISP issues or router problems."

**Normal vs Concerning:**
- ✅ **Normal**: 0-2 informational events
- ⚠️ **Concerning**: 5+ events, repeated WAN drops, DHCP exhaustion warnings
- **What to do**: Check Router Logs page, look for patterns, verify WAN connectivity

### 7-Day Trend Charts

These bar charts show the last 7 days of activity for each metric category:

**Tooltip:** "Historical view of the last 7 days. Look for: (1) increasing trends that suggest growing problems, (2) sudden spikes on specific days, (3) cyclic patterns that indicate scheduled events or recurring issues."

- **How to use**: Compare today's activity to the recent past. A spike today that's out of pattern needs investigation. Gradual increases suggest underlying issues building up.
- **What's normal**: Relatively flat lines with occasional small spikes
- **What's concerning**: Steadily increasing trend lines, massive single-day spikes, or weekend vs weekday patterns (if not expected)

### Detail Panels

#### Authentication Bursts Panel
**Tooltip:** "Lists client IPs exceeding the failure threshold within 15 minutes. Each row shows the IP, failure count, and last occurrence. Investigate unfamiliar IPs immediately."

**What it shows:** A table of IP addresses that have triggered multiple authentication failures.

**How to interpret:**
- Internal IPs (192.168.x.x, 10.x.x.x): Likely a misconfigured service or forgotten password
- External IPs: Potential brute force attack or scanning activity
- High count (20+): Active attack or severely misconfigured client

#### Windows Critical Events Panel
**Tooltip:** "Recent critical and error events from Windows. Focus on: repeating source names (indicates persistent issue), disk/IO errors (potential hardware failure), and service crashes."

**What it shows:** Most recent critical/error Windows events with timestamp, source, level, and message.

**How to interpret:**
- One-off events: Usually safe to ignore unless severe
- Repeated source: Indicates persistent problem needing investigation
- Disk-related errors: Check drive health immediately
- Application crashes: Review application logs for root cause

#### Router Alerts Panel
**Tooltip:** "Router syslog entries flagged as anomalies. Pay attention to: IGMP drops (usually harmless multicast), WAN connection drops (ISP issues), and authentication failures (security concern)."

**What it shows:** Recent router syslog entries marked as anomalous by the collector.

**Common patterns:**
- **IGMP drops on 224.0.0.1**: Usually harmless multicast traffic, safe to ignore if consistent
- **WAN connection drops**: ISP issues or line problems, contact ISP if frequent
- **DHCP issues**: Address pool exhaustion or misconfiguration
- **Wi-Fi authentication failures**: Client device issues or incorrect passwords

#### Latest Syslog Activity Panel
**Tooltip:** "Raw syslog feed from all sources. Use this to correlate events across different systems and get context around alerts shown in other panels."

**What it shows:** Most recent syslog messages from all sources (router, systems, applications).

**How to use:** This is your "raw feed" for correlating events. If you see an alert in another panel, check this view for related events around the same time.

---

## 2. System Events

**Path:** `/events`

The System Events page provides deep visibility into Windows Event Logs from Application, Security, and System logs.

### Log Type Filters

**Tooltip:** "Toggle log types to focus your analysis. Check all three for cross-referencing related issues (e.g., application crash alongside system error). Select one to deep-dive into specific log type."

**Use cases:**
- All three checked: Find correlated issues across log types
- Application only: Debug application-specific problems
- Security only: Audit authentication, access, and security events
- System only: Investigate hardware, driver, and OS-level issues

### Summary Cards

#### Total Events
**Tooltip:** "Total events loaded from selected log types. Higher counts during incidents or changes are normal. Use time filters to narrow the window."

#### Auth / Login
**Tooltip:** "Events containing authentication keywords. Normal: steady low rate. Concerning: sudden spike may indicate brute force or account issues."

#### Disk / IO
**Tooltip:** "Storage-related events. Normal: minimal activity. Concerning: repeated errors may indicate failing disk or misconfiguration."

#### Network
**Tooltip:** "Network-related events. Normal: occasional DHCP renewals. Concerning: repeated connection failures or adapter errors."

### Charts

#### Severity Distribution
**Tooltip:** "Breakdown by Error, Warning, and Information levels. Healthy systems show mostly Information events. Large Error counts need investigation."

**What's normal:** 80%+ Information, <10% Error

#### Top Sources
**Tooltip:** "Most active event sources. Identify chatty applications or services generating excessive logs. Repeated errors from one source indicate focused problem."

**How to use:** If one source dominates, filter the table below to that source and investigate why it's so active.

#### Keyword Analysis
**Tooltip:** "Events categorized by keywords (auth, disk, network). Quick way to spot patterns in event types. Spikes in specific categories guide investigation."

#### Severity Over Time
**Tooltip:** "Timeline showing error, warning, and info events over selected time range. Look for: error spikes correlating with outages, gradual increase in warnings suggesting degrading health."

**How to interpret:**
- Isolated error spike: One-time incident, check what happened at that time
- Increasing error trend: Growing problem, investigate before it becomes critical
- Warning pattern before errors: System was warning before failure

### Recent Events Table

**Tooltip:** "Detailed event log with filtering and sorting. Use search to find specific messages. Sort by Time to see chronological sequence. Filter by Level to focus on errors."

**Best practices:**
- Search for error codes, application names, or keywords
- Sort by Source to group related events
- Use time filters (1h, 6h, 24h) to narrow scope during incident investigation
- Cross-reference Log Type badge to understand event context

### AI Trend Analysis

**Button:** "Analyze Trends"

**Tooltip:** "AI-powered analysis of recent events to identify patterns, correlations, and actionable insights. Use when you see increased activity but aren't sure of the root cause."

**When to use:**
- You notice elevated error counts but can't identify the pattern
- You want to cross-reference Application, Security, and System logs for related issues
- You need a quick summary of what's happening in your environment

---

## 3. Router Logs

**Path:** `/router`

Router Logs provides visibility into your ASUS router's syslog messages, helping you monitor network health and connectivity.

### Summary Cards

#### Total Events
**Tooltip:** "All syslog entries captured from router. Steady rate indicates healthy logging. Sudden drop means collection stopped."

#### IGMP Drops
**Tooltip:** "Multicast group management packets dropped at WAN. Usually benign unless causing application issues. Normal: consistent low rate."

**What it means:** Your ISP is dropping multicast packets (often for IPTV or streaming). Unless you use multicast services, this is harmless.

#### rstats Issues
**Tooltip:** "Router traffic history database errors. Normal: 0. Concerning: repeated errors may prevent bandwidth monitoring. Usually cosmetic."

#### UPnP Events
**Tooltip:** "Universal Plug and Play activity from miniupnpd. Shows devices requesting port forwards. Normal: occasional. Spikes when new devices connect."

### Charts

#### Severity Distribution
**Tooltip:** "Router log severity levels. Mostly Notice and Info is healthy. High Error or Critical counts need investigation."

#### Top WAN Drop Ports
**Tooltip:** "Ports blocked at WAN interface. IGMP drops (224.0.0.1 proto 2) are common. Unexpected ports may indicate blocked services or scanning attempts."

**How to interpret:**
- Port 224.0.0.1: IGMP multicast, usually harmless
- Common ports (80, 443, 22): Potential scanning or blocked legitimate traffic
- Unusual ports: May need investigation or firewall rule adjustment

#### Wi-Fi Events by MAC
**Tooltip:** "Wireless client activity from router logs. Shows which devices are connecting, disconnecting, or having issues. High counts may indicate flapping clients or poor signal."

**What's normal:** Occasional connect/disconnect events
**What's concerning:** Repeated connect/disconnect cycles (flapping), authentication failures

### Recent Router Logs Table

**Tooltip:** "Detailed router syslog with filtering and search. Use Level filter for errors only. Search for specific IPs, MACs, or keywords. Sort by Time to see event sequence."

**Features:**
- **Search**: Find specific messages, IPs, MAC addresses
- **Level filter**: Focus on Error, Warning, or other severity levels
- **Host filter**: Show only events from specific source hosts
- **Sorting**: Click column headers to sort (Time, Level, Message, Host)
- **Pagination**: Navigate through logs with per-page size controls

**Common searches:**
- "WAN" - Find WAN-related events
- "DHCP" - Look for DHCP pool issues
- "auth" or "authentication" - Find Wi-Fi connection issues
- MAC address - Track specific device activity

### AI Features

#### Ask AI (Per Log Entry)
**Tooltip:** "Get AI explanation of individual log entry. Useful for cryptic router messages or understanding security implications."

**When to use:** You see a concerning message but don't understand what it means or if you should take action.

#### Analyze Trends
**Tooltip:** "AI analysis of last 100 logs to identify patterns, recurring issues, or anomalies. Great for spotting problems you might miss manually."

**When to use:**
- Router seems unstable but you can't pinpoint why
- You want to understand if current activity is normal
- You need a quick assessment of router health

---

## 4. Wi-Fi Clients

**Path:** `/wifi`

*(This page exists in navigation but details depend on implementation. General guidance:)*

**Purpose:** Monitor wireless clients connected to your network, including signal strength, connection quality, and client-specific issues.

**Tooltip for typical metrics:**
- **Signal Strength (RSSI)**: "Measured in dBm. Excellent: -50 or better. Good: -50 to -60. Fair: -60 to -70. Poor: -70 or worse. Move closer to AP or add mesh node."
- **Connection Speed**: "Current negotiated rate. Lower than expected may indicate interference, distance, or client limitations."
- **Connected Clients**: "Devices currently on Wi-Fi. Unexpected devices warrant investigation."

---

## 5. LAN / Network

**Path:** `/lan`

LAN Observability provides real-time tracking of all network devices, signal strength, and connectivity issues.

### Summary Cards

#### Total Devices
**Tooltip:** "All devices ever seen on network, tracked by MAC address. This count only increases as new devices join."

#### Active Now
**Tooltip:** "Currently online devices. Compare to expected count. Lower than usual may indicate connectivity issues or offline equipment."

#### Wired / 2.4 GHz / 5 GHz
**Tooltip:** "Device counts by connection type in last 24 hours. Helps identify if devices are using optimal bands. More 5 GHz is generally better for speed."

#### Inactive
**Tooltip:** "Devices not seen recently. High count is normal for guest devices. Sudden increase may indicate network problems preventing check-ins."

### Currently Online Devices Table

**Tooltip:** "Real-time view of active devices with interface, signal, and activity details. Auto-refreshes every 30 seconds. Use to spot connection issues or unexpected devices."

**Columns explained:**
- **Hostname**: Device name (or MAC if unknown). Click for detailed history.
- **IP Address**: Current IP assignment
- **Interface**: wired, wireless 2.4GHz, or wireless 5GHz
- **Signal (RSSI)**: 
  - Excellent (≥-50 dBm): Strong signal, full speed potential
  - Good (-50 to -60 dBm): Solid connection, good speed
  - Fair (-60 to -70 dBm): Acceptable but may see occasional slowness
  - Poor (<-70 dBm): Weak signal, slow speeds, intermittent issues - consider moving device or adding access point
- **Last Seen**: How recently the device was detected

### Active Alerts

**Tooltip:** "Network issues and device notifications. Critical alerts (red) need immediate action. Warnings (yellow) should be investigated soon. Acknowledge alerts to track what you've reviewed."

**Alert types:**
- **Weak Signal**: Device has RSSI < -70 dBm
- **Connection Flapping**: Device connecting and disconnecting repeatedly
- **Offline**: Previously active device hasn't been seen in expected window
- **New Device**: Unknown device joined network (security consideration)

**Actions:**
- **Acknowledge**: Mark that you've seen the alert
- **Resolve**: Close the alert (it won't appear again)
- **View Device**: Go to device detail page for full history

### Potential Issues

**Tooltip:** "Automatic detection of devices with connectivity problems. Use to proactively identify and fix issues before users complain."

**Green status**: "All devices operating normally" - No action needed

**Issues shown:**
- Weak signal strength with specific RSSI value
- Suggestions for improvement (move device, add access point, check interference)

---

## How to Use This Dashboard Day-to-Day

### Morning Check-In (2-3 minutes)

1. **Start at Operations Overview**: Quick scan of the four KPI cards
   - All green? You're good to go
   - Red/yellow alerts? Click into that section
2. **Check 7-day trends**: Look for unusual patterns or trends
3. **Scan detail panels**: Review any authentication bursts or router alerts
4. **Check LAN Overview**: Verify expected devices are online

### Investigating an Alert

1. **Start at the alert source** (Operations Overview panel or specific page)
2. **Note the timestamp** - when did it start?
3. **Check related pages** for correlated events:
   - Windows error? Check System Events for details
   - Network issue? Check Router Logs and LAN Overview
   - Auth failure? Check System Events Security logs
4. **Use AI Trend Analysis** if pattern isn't obvious
5. **Filter and search** to narrow down to relevant events
6. **Document** your findings for future reference

### Weekly Health Check (10-15 minutes)

1. **Review 7-day trends** on Operations Overview - Are errors increasing?
2. **System Events page**: Run Analyze Trends to spot growing issues
3. **Router Logs page**: Run Analyze Trends to identify network patterns
4. **LAN Overview**: Check inactive devices - Should any be retired?
5. **Review alerts**: Any recurring alerts that need permanent fixes?

### Performance Optimization

1. **LAN page**: Check Wi-Fi devices on 2.4 GHz - Can they use 5 GHz?
2. **LAN page**: Identify devices with poor RSSI - Move or add access point?
3. **Router Logs**: Look for WAN drops - Time to call ISP?
4. **System Events**: High Disk/IO counts - Time for cleanup or upgrade?

---

## Troubleshooting / FAQ

### Q: The dashboard shows "Sample data displayed — database connection unavailable"

**A:** The Flask app can't reach PostgreSQL. 
- Check that PostgreSQL service is running
- Verify database credentials in environment variables
- Check network connectivity to database host
- Review `TROUBLESHOOTING.md` for detailed steps

### Q: No data is appearing in charts or tables

**A:** Possible causes:
1. **Collection services not running**: Start `SystemDashboardTelemetry` service
2. **No partition for current month**: Run `SELECT telemetry.ensure_syslog_partition(CURRENT_DATE);` in PostgreSQL
3. **No data sources configured**: Check `config.json` for router endpoint and verify Windows Event Log access

### Q: I see lots of IGMP drops in Router Logs - is this bad?

**A:** Usually no. IGMP drops (224.0.0.1, proto 2) are multicast packets being filtered by your ISP. Unless you use IPTV or specific multicast applications, these are harmless and expected.

### Q: What's a normal number of Windows Events per hour?

**A:** Varies by system, but typically:
- Information: 10-100/hour is normal
- Warning: 0-10/hour is normal
- Error: 0-5/hour is normal
- Critical: 0-1/hour (ideally 0)

More than this may indicate issues, or you may have verbose logging enabled.

### Q: Should I worry about authentication failures?

**A:** Depends on the source:
- **1-2 failures from internal IP**: Likely typo or cached credentials - monitor but not urgent
- **Multiple failures from external IP**: Potential attack - review and consider blocking
- **10+ failures in burst**: Active attack or seriously misconfigured client - investigate immediately

### Q: What does "Spike detected" mean for IIS Server Errors?

**A:** The current 5-minute window has significantly more 5xx errors than the baseline average. This indicates a server problem:
- Check recent deployments or changes
- Review IIS application logs
- Verify server resources (CPU, memory, disk)
- Check database connectivity if applicable

### Q: A device shows "Poor" signal strength but seems to work fine

**A:** Poor signal (<-70 dBm) means:
- Lower speeds than capable of
- More prone to interference and dropouts
- May work fine for light usage but struggle with streaming or large transfers
- **Recommendation**: Move device closer to AP, switch to 5 GHz if possible, or add a mesh node/AP

### Q: How do I know if a Windows Event is important?

**A:** Priority indicators:
1. **Critical**: Always investigate - system stability at risk
2. **Error + repeating source**: Important - indicates ongoing problem
3. **Error, one-off**: Lower priority - may be transient
4. **Warning + disk/hardware related**: Important - may predict failure
5. **Information**: Usually safe to ignore unless investigating specific issue

### Q: The LAN page shows a device I don't recognize

**A:** Steps to investigate:
1. Click "Details" to see device history and activity
2. Check the IP address - is it in your DHCP range?
3. Look at the MAC address first 6 digits (OUI) - Google it to identify manufacturer
4. Check connection history - When did it first appear?
5. If unauthorized: Block via router, change Wi-Fi password, investigate security

### Q: Can I export or save chart data?

**A:** Currently, the dashboard is view-only. To save data:
- Take screenshots of relevant charts and tables
- Query PostgreSQL directly for raw data export
- Use browser print-to-PDF for entire pages

### Q: How far back does historical data go?

**A:** Depends on your retention policy:
- Default: Data retained indefinitely
- Partitioned by month for performance
- Older partitions can be archived or dropped as needed
- Configure retention in PostgreSQL or via scheduled tasks

### Q: AI Trend Analysis isn't working

**A:** Check:
- AI service must be configured in the backend
- Requires sufficient event data (min 50-100 events)
- Review browser console for error messages
- Contact administrator if persistent

---

## Getting Help

- **Detailed Setup**: See `docs/SETUP.md`
- **Troubleshooting Guide**: See `docs/TROUBLESHOOTING.md`
- **LAN Monitoring**: See `docs/LAN-OBSERVABILITY-README.md`
- **Advanced Features**: See `docs/ADVANCED-FEATURES.md`

**Remember:** This dashboard is your window into infrastructure health. Regular check-ins and proactive monitoring will help you catch issues before they impact users!

'use strict';

(() => {
  const REFRESH_INTERVAL = 5000;
  const METRICS_ENDPOINT = 'metrics';
  const SYSLOG_SUMMARY_ENDPOINT = '/api/syslog/summary';
  const SYSLOG_RECENT_ENDPOINT = '/api/syslog/recent';
  const EVENTS_SUMMARY_ENDPOINT = '/api/events/summary';
  const EVENTS_RECENT_ENDPOINT = '/api/events/recent';
  const SYSLOG_TIMELINE_ENDPOINT = '/api/syslog/timeline';
  const EVENTS_TIMELINE_ENDPOINT = '/api/events/timeline';
  const TIMELINE_ENDPOINT = '/api/timeline';
  const DEVICES_SUMMARY_ENDPOINT = '/api/devices/summary';
  const ROUTER_KPI_ENDPOINT = '/api/router/kpis';
  const WIFI_CLIENTS_ENDPOINT = '/api/lan/clients';
  const LAYOUTS_ENDPOINT = '/api/layouts';
  const HEALTH_ENDPOINT = '/api/health';
  const STATUS_ENDPOINT = '/api/status';
  const TELEMETRY_REFRESH_INTERVAL = 15000;
  const SYSLOG_PAGE_SIZE = 12;
  const EVENTS_PAGE_SIZE = 12;
  const OVERVIEW_REFRESH_INTERVAL = 60000;
  const DISK_PRESSURE_THRESHOLD = 0.9;
  const DEFAULT_LAYOUT_NAME = 'Default';
  const LAYOUT_STORAGE_KEY = 'system-dashboard-layouts';

  const statusEl = document.getElementById('connection-status');
  const statusDetailEl = document.getElementById('status-detail');
  const hostNameEl = document.getElementById('host-name');
  const uptimeEl = document.getElementById('uptime-value');
  const cpuValueEl = document.getElementById('cpu-value');
  const memoryValueEl = document.getElementById('memory-value');
  const memoryDetailEl = document.getElementById('memory-detail');
  const latencyEl = document.getElementById('latency-value');
  const latencyTargetEl = document.getElementById('latency-target');
  const overviewRangeEl = document.getElementById('overview-range');
  const overviewErrorsEl = document.getElementById('overview-errors');
  const overviewWarningsEl = document.getElementById('overview-warnings');
  const overviewNoisyHostsEl = document.getElementById('overview-noisy-hosts');
  const overviewTopHostEl = document.getElementById('overview-top-host');
  const overviewTopAppEl = document.getElementById('overview-top-app');
  const overviewRouterDropsEl = document.getElementById('overview-router-drops');
  const overviewDiskPressureEl = document.getElementById('overview-disk-pressure');
  const overviewDiskDetailEl = document.getElementById('overview-disk-detail');
  const overviewFocusListEl = document.getElementById('overview-focus-list');
  const overviewFocusUpdatedEl = document.getElementById('overview-focus-updated');
  const layoutSelectEl = document.getElementById('layout-select');
  const layoutNameInput = document.getElementById('layout-name');
  const layoutSaveBtn = document.getElementById('layout-save');
  const layoutDeleteBtn = document.getElementById('layout-delete');
  const layoutResetBtn = document.getElementById('layout-reset');
  const layoutLockToggle = document.getElementById('layout-lock');
  const dashboardGridEl = document.getElementById('dashboard-grid');
  const diskTableBody = document.querySelector('#disk-table tbody');
  const networkTableBody = document.querySelector('#network-table tbody');
  const processTableBody = document.querySelector('#process-table tbody');
  const warningListEl = document.getElementById('warning-list');
  const warningTotalEl = document.getElementById('warning-total');
  const errorListEl = document.getElementById('error-list');
  const errorTotalEl = document.getElementById('error-total');
  const networkCountEl = document.getElementById('network-count');
  const refreshIntervalEl = document.getElementById('refresh-interval');
  const syslogTableBody = document.querySelector('#syslog-table tbody');
  const syslogTotal1hEl = document.getElementById('syslog-total-1h');
  const syslogTotal24hEl = document.getElementById('syslog-total-24h');
  const syslogTopAppEl = document.getElementById('syslog-top-app');
  const syslogInfoEl = document.getElementById('syslog-sev-info');
  const syslogWarnEl = document.getElementById('syslog-sev-warn');
  const syslogErrorEl = document.getElementById('syslog-sev-error');
  const syslogHostInput = document.getElementById('syslog-host');
  const syslogCategorySelect = document.getElementById('syslog-category');
  const syslogSeveritySelect = document.getElementById('syslog-severity');
  const syslogStartInput = document.getElementById('syslog-start');
  const syslogEndInput = document.getElementById('syslog-end');
  const syslogBucketSelect = document.getElementById('syslog-bucket');
  const syslogRefreshBtn = document.getElementById('syslog-refresh');
  const syslogPrevBtn = document.getElementById('syslog-prev');
  const syslogNextBtn = document.getElementById('syslog-next');
  const syslogPageEl = document.getElementById('syslog-page');
  const syslogRangeEl = document.getElementById('syslog-range');
  const syslogTimelineChartEl = document.getElementById('syslog-timeline-chart');
  const syslogTimelineLegendEl = document.getElementById('syslog-timeline-legend');
  const eventTableBody = document.querySelector('#event-table tbody');
  const eventsTotal1hEl = document.getElementById('events-total-1h');
  const eventsTotal24hEl = document.getElementById('events-total-24h');
  const eventsTopSourceEl = document.getElementById('events-top-source');
  const eventsWarnEl = document.getElementById('events-sev-warn');
  const eventsErrorEl = document.getElementById('events-sev-error');
  const eventsInfoEl = document.getElementById('events-sev-info');
  const eventSourceInput = document.getElementById('event-source');
  const eventCategorySelect = document.getElementById('event-category');
  const eventSeveritySelect = document.getElementById('event-severity');
  const eventStartInput = document.getElementById('event-start');
  const eventEndInput = document.getElementById('event-end');
  const eventBucketSelect = document.getElementById('event-bucket');
  const eventRefreshBtn = document.getElementById('event-refresh');
  const eventPrevBtn = document.getElementById('event-prev');
  const eventNextBtn = document.getElementById('event-next');
  const eventPageEl = document.getElementById('event-page');
  const eventRangeEl = document.getElementById('event-range');
  const eventTimelineChartEl = document.getElementById('event-timeline-chart');
  const eventTimelineLegendEl = document.getElementById('event-timeline-legend');
  const timelineChartEl = document.getElementById('timeline-chart');
  const timelineLegendEl = document.getElementById('timeline-legend');
  const timelineMacInput = document.getElementById('timeline-mac');
  const timelineCategorySelect = document.getElementById('timeline-category');
  const timelineEventTypeSelect = document.getElementById('timeline-event-type');
  const timelineRefreshBtn = document.getElementById('timeline-refresh');
  const devicesRefreshBtn = document.getElementById('devices-refresh');
  const deviceTableBody = document.querySelector('#device-table tbody');
  const deviceCountEl = document.getElementById('device-count');
  const wifiRefreshBtn = document.getElementById('wifi-refresh');
  const wifiTableBody = document.querySelector('#wifi-table tbody');
  const wifiClientCountEl = document.getElementById('wifi-client-count');
  const refreshStatusEl = document.getElementById('refresh-status');
  const refreshResumeBtn = document.getElementById('refresh-resume');
  const healthBannerEl = document.getElementById('health-banner');
  const healthBannerTextEl = document.getElementById('health-banner-text');
  const serviceBannerEl = document.getElementById('service-banner');
  const serviceBannerTextEl = document.getElementById('service-banner-text');
  const routerKpiUpdatedEl = document.getElementById('router-kpi-updated');
  const routerKpiTotalDropEl = document.getElementById('kpi-total-drop');
  const routerKpiIgmpDropEl = document.getElementById('kpi-igmp-drop');
  const routerKpiRoamKicksEl = document.getElementById('kpi-roam-kicks');
  const routerKpiRstatsErrorsEl = document.getElementById('kpi-rstats-errors');
  const routerKpiDnsmasqSigtermEl = document.getElementById('kpi-dnsmasq-sigterm');
  const routerKpiAvahiSigtermEl = document.getElementById('kpi-avahi-sigterm');
  const routerKpiUpnpShutdownsEl = document.getElementById('kpi-upnp-shutdowns');

  if (refreshIntervalEl) {
    refreshIntervalEl.textContent = (REFRESH_INTERVAL / 1000).toString();
  }

  let refreshTimer;
  let telemetryTimer;
  let autoRefreshPaused = false;
  let syslogPage = 1;
  let eventPage = 1;
  let lastOverviewRefresh = 0;
  let layoutLocked = false;
  let layoutStore = { active: DEFAULT_LAYOUT_NAME, layouts: {} };
  let layoutSaveTimer;

  const overviewState = {
    errorsToday: null,
    warningsToday: null,
    noisyHosts: null,
    topHost: null,
    topApp: null,
    routerDrops: null,
    diskPressureCount: null,
    diskMax: null,
    latencyMs: null,
    latencyTarget: null
  };

  const DEFAULT_LAYOUT = {
    'recent-warnings': { w: 4, h: 6, order: 1 },
    'recent-errors': { w: 4, h: 6, order: 2 },
    'disk-utilisation': { w: 8, h: 8, order: 3 },
    'network-throughput': { w: 6, h: 7, order: 4 },
    'top-processes': { w: 6, h: 7, order: 5 },
    'device-timeline': { w: 8, h: 10, order: 6 },
    'wifi-clients': { w: 6, h: 9, order: 7 },
    'noisy-devices': { w: 6, h: 9, order: 8 },
    'syslog-intake': { w: 12, h: 14, order: 9 },
    'event-logs': { w: 12, h: 14, order: 10 },
    'router-kpis': { w: 4, h: 8, order: 11 }
  };

  function scheduleNext(delay = REFRESH_INTERVAL) {
    clearTimeout(refreshTimer);
    if (autoRefreshPaused) {
      return;
    }
    refreshTimer = setTimeout(loadMetrics, delay);
  }

  function setStatus(state, detail) {
    if (!statusEl) {
      return;
    }
    statusEl.className = `status status--${state}`;
    switch (state) {
      case 'online':
        statusEl.textContent = 'Online';
        break;
      case 'offline':
        statusEl.textContent = 'Offline';
        break;
      default:
        statusEl.textContent = 'Connecting…';
        break;
    }
    if (statusDetailEl) {
      statusDetailEl.textContent = detail || '';
    }
  }

  function formatPercent(value, options) {
    const settings = Object.assign({ scaleTo100: true, digits: 1 }, options);
    if (typeof value !== 'number' || !isFinite(value) || value < 0) {
      return '--';
    }
    const percent = (value <= 1 && settings.scaleTo100) ? value * 100 : value;
    const clamped = Math.min(Math.max(percent, 0), 100);
    return `${clamped.toFixed(settings.digits)}%`;
  }

  function formatNumber(value, digits = 1) {
    if (typeof value !== 'number' || !isFinite(value)) {
      return '--';
    }
    return value.toFixed(digits);
  }

  function formatBytesPerSec(value) {
    if (typeof value !== 'number' || !isFinite(value)) {
      return '--';
    }
    const units = ['B/s', 'KB/s', 'MB/s', 'GB/s', 'TB/s'];
    let idx = 0;
    let current = value;
    while (current >= 1024 && idx < units.length - 1) {
      current /= 1024;
      idx += 1;
    }
    const digits = current >= 100 ? 0 : current >= 10 ? 1 : 2;
    return `${current.toFixed(digits)} ${units[idx]}`;
  }

  function formatLatency(value) {
    if (typeof value !== 'number' || !isFinite(value) || value < 0) {
      return 'No response';
    }
    return `${value.toFixed(0)} ms`;
  }

  function formatUptime(uptime) {
    if (!uptime || typeof uptime !== 'object') {
      return '--';
    }
    const parts = [];
    const days = Number(uptime.Days);
    const hours = Number(uptime.Hours);
    const minutes = Number(uptime.Minutes);
    if (!Number.isNaN(days) && days > 0) {
      parts.push(`${days}d`);
    }
    if (!Number.isNaN(hours) && (hours > 0 || parts.length)) {
      parts.push(`${hours}h`);
    }
    if (!Number.isNaN(minutes)) {
      parts.push(`${minutes}m`);
    }
    return parts.length ? parts.join(' ') : '0m';
  }

  function formatDurationSeconds(totalSeconds) {
    if (typeof totalSeconds !== 'number' || !isFinite(totalSeconds) || totalSeconds < 0) {
      return '--';
    }
    const total = Math.floor(totalSeconds);
    const days = Math.floor(total / 86400);
    const hours = Math.floor((total % 86400) / 3600);
    const minutes = Math.floor((total % 3600) / 60);
    const parts = [];
    if (days > 0) {
      parts.push(`${days}d`);
    }
    if (hours > 0 || parts.length) {
      parts.push(`${hours}h`);
    }
    parts.push(`${minutes}m`);
    return parts.join(' ');
  }

  function formatTimestamp(value) {
    const date = value ? new Date(value) : new Date();
    if (Number.isNaN(date.getTime())) {
      return new Date().toLocaleString();
    }
    return date.toLocaleString();
  }

  function formatMemoryDetail(memory) {
    if (!memory || typeof memory !== 'object') {
      return '--';
    }
    const used = formatNumber(memory.UsedGB, 1);
    const total = formatNumber(memory.TotalGB, 1);
    if (used === '--' || total === '--') {
      return '--';
    }
    return `${used} GB used of ${total} GB`;
  }

  function truncateText(value, max = 160) {
    if (!value) {
      return '';
    }
    const text = value.toString();
    if (text.length <= max) {
      return text;
    }
    return `${text.slice(0, max - 3)}...`;
  }

  function formatShortTime(value) {
    if (!value) {
      return '--';
    }
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      return value;
    }
    return date.toLocaleString();
  }

  function formatLocalIso(value) {
    if (!(value instanceof Date) || Number.isNaN(value.getTime())) {
      return null;
    }
    const pad = (num) => num.toString().padStart(2, '0');
    return `${value.getFullYear()}-${pad(value.getMonth() + 1)}-${pad(value.getDate())}T${pad(value.getHours())}:${pad(value.getMinutes())}:${pad(value.getSeconds())}`;
  }

  function formatCount(value) {
    if (typeof value !== 'number' || !isFinite(value)) {
      return '--';
    }
    return value.toString();
  }

  function getTodayRange() {
    const end = new Date();
    const start = new Date(end.getFullYear(), end.getMonth(), end.getDate());
    return { start, end };
  }

  function formatTodayLabel() {
    const today = new Date();
    return `Today • ${today.toLocaleDateString()}`;
  }

  function computeSyslogSeverityTotals(summary) {
    const totals = { error: 0, warn: 0, info: 0 };
    if (!summary || !Array.isArray(summary.bySeverity)) {
      return totals;
    }
    summary.bySeverity.forEach((entry) => {
      const count = Number(entry.total) || 0;
      const sev = Number(entry.severity);
      if (!Number.isNaN(sev)) {
        if (sev <= 3) {
          totals.error += count;
        } else if (sev === 4) {
          totals.warn += count;
        } else {
          totals.info += count;
        }
        return;
      }
      const label = (entry.severity || '').toString().toLowerCase();
      if (['emerg', 'alert', 'critical', 'crit', 'error'].includes(label)) {
        totals.error += count;
      } else if (label === 'warning' || label === 'warn') {
        totals.warn += count;
      } else if (label) {
        totals.info += count;
      }
    });
    return totals;
  }

  function computeEventSeverityTotals(summary) {
    const totals = { error: 0, warn: 0, info: 0 };
    if (!summary || !Array.isArray(summary.bySeverity)) {
      return totals;
    }
    summary.bySeverity.forEach((entry) => {
      const count = Number(entry.total) || 0;
      const label = (entry.severity || '').toString().toLowerCase();
      if (label === 'critical' || label === 'error') {
        totals.error += count;
      } else if (label === 'warning' || label === 'warn') {
        totals.warn += count;
      } else if (label) {
        totals.info += count;
      }
    });
    return totals;
  }

  function renderOverview() {
    if (overviewRangeEl) {
      overviewRangeEl.textContent = formatTodayLabel();
    }
    if (overviewErrorsEl) {
      overviewErrorsEl.textContent = formatCount(overviewState.errorsToday);
    }
    if (overviewWarningsEl) {
      overviewWarningsEl.textContent = formatCount(overviewState.warningsToday);
    }
    if (overviewNoisyHostsEl) {
      overviewNoisyHostsEl.textContent = formatCount(overviewState.noisyHosts);
    }
    if (overviewTopHostEl) {
      overviewTopHostEl.textContent = overviewState.topHost || '--';
    }
    if (overviewTopAppEl) {
      overviewTopAppEl.textContent = overviewState.topApp || '--';
    }
    if (overviewRouterDropsEl) {
      overviewRouterDropsEl.textContent = formatCount(overviewState.routerDrops);
    }
    if (overviewDiskPressureEl) {
      overviewDiskPressureEl.textContent = formatCount(overviewState.diskPressureCount);
    }
    if (overviewDiskDetailEl) {
      if (overviewState.diskMax) {
        overviewDiskDetailEl.textContent = `${overviewState.diskMax.drive}: ${overviewState.diskMax.pct}%`;
      } else {
        overviewDiskDetailEl.textContent = '--';
      }
    }
    renderOverviewFocus();
  }

  function renderOverviewFocus() {
    if (!overviewFocusListEl) {
      return;
    }
    clearElement(overviewFocusListEl);
    const hasData = [
      overviewState.errorsToday,
      overviewState.warningsToday,
      overviewState.noisyHosts,
      overviewState.routerDrops,
      overviewState.diskPressureCount,
      overviewState.latencyMs
    ].some((value) => typeof value === 'number');
    const items = [];
    if (typeof overviewState.errorsToday === 'number' && overviewState.errorsToday > 0) {
      items.push({ text: `Errors today: ${overviewState.errorsToday}`, tone: 'urgent' });
    }
    if (typeof overviewState.warningsToday === 'number' && overviewState.warningsToday > 0) {
      items.push({ text: `Warnings today: ${overviewState.warningsToday}`, tone: 'warn' });
    }
    if (typeof overviewState.noisyHosts === 'number' && overviewState.noisyHosts > 0) {
      const detail = overviewState.topHost ? ` (top: ${overviewState.topHost})` : '';
      items.push({ text: `Noisy hosts: ${overviewState.noisyHosts}${detail}`, tone: 'warn' });
    }
    if (typeof overviewState.routerDrops === 'number' && overviewState.routerDrops > 0) {
      items.push({ text: `Router drops (24h): ${overviewState.routerDrops}`, tone: 'warn' });
    }
    if (typeof overviewState.diskPressureCount === 'number' && overviewState.diskPressureCount > 0) {
      const detail = overviewState.diskMax ? ` (max ${overviewState.diskMax.drive} ${overviewState.diskMax.pct}%)` : '';
      items.push({ text: `Disk pressure on ${overviewState.diskPressureCount} drive(s)${detail}`, tone: 'urgent' });
    }
    if (typeof overviewState.latencyMs === 'number' && overviewState.latencyMs < 0) {
      const target = overviewState.latencyTarget ? ` (${overviewState.latencyTarget})` : '';
      items.push({ text: `Latency target not responding${target}`, tone: 'warn' });
    }

    if (!items.length) {
      const empty = document.createElement('li');
      empty.className = 'empty';
      empty.textContent = hasData ? 'All quiet. No priority issues detected.' : 'Loading focus items…';
      overviewFocusListEl.appendChild(empty);
    } else {
      items.slice(0, 5).forEach((item) => {
        const li = document.createElement('li');
        if (item.tone === 'urgent') {
          li.classList.add('is-urgent');
        } else if (item.tone === 'warn') {
          li.classList.add('is-warn');
        }
        li.textContent = item.text;
        overviewFocusListEl.appendChild(li);
      });
    }

    if (overviewFocusUpdatedEl) {
      overviewFocusUpdatedEl.textContent = hasData ? `Updated ${formatShortTime(Date.now())}` : '--';
    }
  }

  function parseDateInput(value) {
    if (!value) {
      return null;
    }
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      return null;
    }
    return date;
  }

  function appendDateRangeParams(params, startInput, endInput) {
    const startValue = startInput ? parseDateInput(startInput.value) : null;
    const endValue = endInput ? parseDateInput(endInput.value) : null;
    if (startValue) {
      params.set('start', startValue.toISOString());
    }
    if (endValue) {
      params.set('end', endValue.toISOString());
    }
  }

  function buildSyslogParams() {
    const params = new URLSearchParams();
    const host = syslogHostInput ? syslogHostInput.value.trim() : '';
    const category = syslogCategorySelect ? syslogCategorySelect.value : '';
    const severity = syslogSeveritySelect ? syslogSeveritySelect.value : '';
    if (host) {
      params.set('host', host);
    }
    if (category) {
      params.set('category', category);
    }
    if (severity) {
      params.set('severity', severity);
    }
    appendDateRangeParams(params, syslogStartInput, syslogEndInput);
    return params;
  }

  function buildEventParams() {
    const params = new URLSearchParams();
    const severity = eventSeveritySelect ? eventSeveritySelect.value : '';
    const source = eventSourceInput ? eventSourceInput.value.trim() : '';
    const category = eventCategorySelect ? eventCategorySelect.value : '';
    if (severity) {
      params.set('severity', severity);
    }
    if (source) {
      params.set('source', source);
    }
    if (category) {
      params.set('category', category);
    }
    appendDateRangeParams(params, eventStartInput, eventEndInput);
    return params;
  }

  async function fetchJson(url, options) {
    const res = await fetch(url, options);
    if (!res.ok) {
      const error = new Error(`HTTP ${res.status}`);
      error.status = res.status;
      throw error;
    }
    return res.json();
  }

  async function postJson(url, payload) {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    if (!res.ok) {
      const error = new Error(`HTTP ${res.status}`);
      error.status = res.status;
      throw error;
    }
    return res.json();
  }

  function parseIsoDurationToMinutes(value) {
    if (!value) {
      return 1440;
    }
    const match = /^PT(?:(\d+)H)?(?:(\d+)M)?$/i.exec(value);
    if (!match) {
      return 1440;
    }
    const hours = match[1] ? Number(match[1]) : 0;
    const minutes = match[2] ? Number(match[2]) : 0;
    const total = (hours * 60) + minutes;
    return total > 0 ? total : 1440;
  }

  function aggregateSnapshotsToTimeline(rows, bucketMinutes) {
    if (!Array.isArray(rows) || rows.length === 0) {
      return [];
    }
    const buckets = new Map();
    rows.forEach((row) => {
      const rawTime = row.sample_time_utc || row.sample_time || row.time;
      if (!rawTime) {
        return;
      }
      const date = new Date(rawTime);
      if (Number.isNaN(date.getTime())) {
        return;
      }
      date.setSeconds(0, 0);
      const mins = date.getMinutes();
      date.setMinutes(mins - (mins % bucketMinutes));
      const bucket = date.toISOString();
      const key = `${bucket}|network`;
      const entry = buckets.get(key) || { bucket_start: bucket, category: 'network', total: 0 };
      entry.total += 1;
      buckets.set(key, entry);
    });
    return Array.from(buckets.values()).sort((a, b) => new Date(a.bucket_start) - new Date(b.bucket_start));
  }

  function mapLanDevicesToSummary(data) {
    const rows = Array.isArray(data.devices) ? data.devices : (Array.isArray(data) ? data : []);
    const mapped = rows.map((row) => {
      return {
        mac_address: row.mac_address,
        last_seen: row.last_seen_utc || row.last_seen,
        events_1h: row.events_1h ?? null,
        last_rssi: row.last_rssi ?? row.current_rssi,
        last_event_type: row.last_event_type
      };
    });
    mapped.sort((a, b) => new Date(b.last_seen || 0) - new Date(a.last_seen || 0));
    return mapped.slice(0, 10);
  }

  function clearElement(element) {
    while (element && element.firstChild) {
      element.removeChild(element.firstChild);
    }
  }

  function setCardCollapsed(target, collapsed) {
    if (!target || !target.closest) {
      return;
    }
    const card = target.closest('.card');
    if (!card) {
      return;
    }
    card.classList.toggle('is-collapsed', collapsed);
    if (collapsed) {
      if (!card.dataset.prevSpanY) {
        const currentSpan = card.style.getPropertyValue('--span-y') || '6';
        card.dataset.prevSpanY = currentSpan;
      }
      card.style.setProperty('--span-y', '3');
    } else if (card.dataset.prevSpanY) {
      card.style.setProperty('--span-y', card.dataset.prevSpanY);
      delete card.dataset.prevSpanY;
    }
  }

  function setEmptyRow(tbody, columns, message) {
    if (!tbody) {
      return;
    }
    const row = document.createElement('tr');
    row.className = 'empty-row';
    const cell = document.createElement('td');
    cell.colSpan = columns;
    cell.textContent = message;
    row.appendChild(cell);
    tbody.appendChild(row);
  }

  function updatePaginationControls(pageEl, rangeEl, prevBtn, nextBtn, page, pageSize, itemCount) {
    if (pageEl) {
      pageEl.textContent = `Page ${page}`;
    }
    if (rangeEl) {
      if (!itemCount) {
        rangeEl.textContent = 'No results';
      } else {
        const start = (page - 1) * pageSize + 1;
        const end = start + itemCount - 1;
        rangeEl.textContent = `Showing ${start}-${end}`;
      }
    }
    if (prevBtn) {
      prevBtn.disabled = page <= 1;
    }
    if (nextBtn) {
      nextBtn.disabled = itemCount < pageSize;
    }
  }

  function getDashboardCards() {
    if (!dashboardGridEl) {
      return [];
    }
    return Array.from(dashboardGridEl.querySelectorAll('.dashboard-card'));
  }

  function setCardLayout(card, layout) {
    if (!card || !layout) {
      return;
    }
    const width = Math.max(1, Math.min(12, Number(layout.w) || 6));
    const height = Math.max(2, Number(layout.h) || 6);
    const order = Number(layout.order) || 0;
    card.style.setProperty('--span-x', width.toString());
    card.style.setProperty('--span-y', height.toString());
    card.style.order = order.toString();
    card.dataset.spanX = width.toString();
    card.dataset.spanY = height.toString();
    card.dataset.order = order.toString();
  }

  function getCardLayout(card, fallback) {
    if (!card) {
      return fallback || { w: 6, h: 6, order: 0 };
    }
    const width = Number(card.dataset.spanX || card.style.getPropertyValue('--span-x')) || (fallback ? fallback.w : 6);
    const heightValue = card.dataset.prevSpanY || card.dataset.spanY || card.style.getPropertyValue('--span-y');
    const height = Number(heightValue) || (fallback ? fallback.h : 6);
    const order = Number(card.dataset.order || card.style.order) || (fallback ? fallback.order : 0);
    return { w: width, h: height, order };
  }

  function buildLayoutFromDom() {
    const items = {};
    getDashboardCards().forEach((card, index) => {
      const id = card.dataset.layoutId;
      if (!id) {
        return;
      }
      if (!card.dataset.order) {
        card.dataset.order = (index + 1).toString();
        card.style.order = card.dataset.order;
      }
      items[id] = getCardLayout(card, DEFAULT_LAYOUT[id]);
    });
    return items;
  }

  function applyLayoutItems(items) {
    getDashboardCards().forEach((card) => {
      const id = card.dataset.layoutId;
      const fallback = DEFAULT_LAYOUT[id];
      const layout = items && items[id] ? items[id] : fallback;
      if (layout) {
        setCardLayout(card, layout);
      }
    });
  }

  function ensureDefaultLayout() {
    if (!layoutStore.layouts[DEFAULT_LAYOUT_NAME]) {
      layoutStore.layouts[DEFAULT_LAYOUT_NAME] = {
        items: DEFAULT_LAYOUT,
        updated_utc: new Date().toISOString()
      };
    }
  }

  function setActiveLayout(name) {
    if (!name || !layoutStore.layouts[name]) {
      name = DEFAULT_LAYOUT_NAME;
    }
    layoutStore.active = name;
    const layout = layoutStore.layouts[name];
    applyLayoutItems(layout ? layout.items : DEFAULT_LAYOUT);
    if (layoutSelectEl) {
      layoutSelectEl.value = name;
    }
    if (layoutNameInput) {
      layoutNameInput.value = '';
    }
  }

  function populateLayoutSelect() {
    if (!layoutSelectEl) {
      return;
    }
    const names = Object.keys(layoutStore.layouts || {});
    if (!names.length) {
      names.push(DEFAULT_LAYOUT_NAME);
    }
    layoutSelectEl.innerHTML = '';
    names.forEach((name) => {
      const option = document.createElement('option');
      option.value = name;
      option.textContent = name;
      layoutSelectEl.appendChild(option);
    });
    if (layoutStore.active) {
      layoutSelectEl.value = layoutStore.active;
    }
  }

  function saveLayoutStoreToLocal() {
    try {
      localStorage.setItem(LAYOUT_STORAGE_KEY, JSON.stringify(layoutStore));
    } catch {}
  }

  async function saveLayoutStoreToServer() {
    try {
      await postJson(LAYOUTS_ENDPOINT, layoutStore);
    } catch {}
  }

  function queueLayoutSave() {
    clearTimeout(layoutSaveTimer);
    layoutSaveTimer = setTimeout(() => {
      saveLayoutStoreToLocal();
      saveLayoutStoreToServer();
    }, 700);
  }

  function refreshActiveLayoutState() {
    const items = buildLayoutFromDom();
    const name = layoutStore.active || DEFAULT_LAYOUT_NAME;
    layoutStore.layouts[name] = {
      items,
      updated_utc: new Date().toISOString()
    };
    queueLayoutSave();
  }

  function setLayoutLockedState(locked) {
    layoutLocked = Boolean(locked);
    if (dashboardGridEl) {
      dashboardGridEl.classList.toggle('layout-locked', layoutLocked);
    }
    if (layoutLockToggle) {
      layoutLockToggle.checked = layoutLocked;
    }
  }

  function loadLayoutStoreFromLocal() {
    try {
      const raw = localStorage.getItem(LAYOUT_STORAGE_KEY);
      if (raw) {
        return JSON.parse(raw);
      }
    } catch {}
    return null;
  }

  async function loadLayoutStore() {
    let store = null;
    try {
      store = await fetchJson(`${LAYOUTS_ENDPOINT}?_=${Date.now()}`, { cache: 'no-store' });
    } catch {
      store = loadLayoutStoreFromLocal();
    }
    if (!store || typeof store !== 'object') {
      store = { active: DEFAULT_LAYOUT_NAME, layouts: {} };
    }
    layoutStore = store;
    if (!layoutStore.layouts || typeof layoutStore.layouts !== 'object') {
      layoutStore.layouts = {};
    }
    ensureDefaultLayout();
    populateLayoutSelect();
    setActiveLayout(layoutStore.active || DEFAULT_LAYOUT_NAME);
  }

  function initLayoutControls() {
    if (!layoutSelectEl) {
      return;
    }
    layoutSelectEl.addEventListener('change', () => {
      const name = layoutSelectEl.value;
      setActiveLayout(name);
      queueLayoutSave();
    });
    if (layoutSaveBtn) {
      layoutSaveBtn.addEventListener('click', () => {
        const name = layoutNameInput && layoutNameInput.value.trim()
          ? layoutNameInput.value.trim()
          : layoutSelectEl.value;
        if (!name) {
          return;
        }
        layoutStore.layouts[name] = {
          items: buildLayoutFromDom(),
          updated_utc: new Date().toISOString()
        };
        layoutStore.active = name;
        populateLayoutSelect();
        setActiveLayout(name);
        queueLayoutSave();
      });
    }
    if (layoutDeleteBtn) {
      layoutDeleteBtn.addEventListener('click', () => {
        const name = layoutSelectEl.value;
        if (!name || name === DEFAULT_LAYOUT_NAME) {
          return;
        }
        delete layoutStore.layouts[name];
        if (layoutStore.active === name) {
          layoutStore.active = DEFAULT_LAYOUT_NAME;
        }
        populateLayoutSelect();
        setActiveLayout(layoutStore.active);
        queueLayoutSave();
      });
    }
    if (layoutResetBtn) {
      layoutResetBtn.addEventListener('click', () => {
        layoutStore.layouts[DEFAULT_LAYOUT_NAME] = {
          items: DEFAULT_LAYOUT,
          updated_utc: new Date().toISOString()
        };
        layoutStore.active = DEFAULT_LAYOUT_NAME;
        populateLayoutSelect();
        setActiveLayout(DEFAULT_LAYOUT_NAME);
        queueLayoutSave();
      });
    }
    if (layoutLockToggle) {
      layoutLockToggle.addEventListener('change', () => {
        setLayoutLockedState(layoutLockToggle.checked);
      });
    }
  }

  function initCardHandles() {
    getDashboardCards().forEach((card) => {
      if (!card.dataset.layoutId) {
        return;
      }
      const header = card.querySelector('.card__header');
      if (header && !header.querySelector('.drag-handle')) {
        const handle = document.createElement('span');
        handle.className = 'drag-handle';
        handle.title = 'Drag to move';
        handle.setAttribute('aria-hidden', 'true');
        const actions = header.querySelector('.card__actions');
        if (actions) {
          actions.appendChild(handle);
        } else {
          header.appendChild(handle);
        }
      }
      if (!card.querySelector('.resize-handle')) {
        const handle = document.createElement('span');
        handle.className = 'resize-handle';
        handle.setAttribute('aria-hidden', 'true');
        card.appendChild(handle);
      }
      card.setAttribute('draggable', 'true');
    });
  }

  function initDragAndResize() {
    if (!dashboardGridEl) {
      return;
    }
    let dragCard = null;
    let resizeState = null;

    dashboardGridEl.addEventListener('dragstart', (event) => {
      const handle = event.target;
      if (layoutLocked || !handle || !handle.classList.contains('drag-handle')) {
        event.preventDefault();
        return;
      }
      const card = handle.closest('.dashboard-card');
      if (!card) {
        event.preventDefault();
        return;
      }
      dragCard = card;
      card.classList.add('is-dragging');
      if (event.dataTransfer) {
        event.dataTransfer.effectAllowed = 'move';
        event.dataTransfer.setData('text/plain', card.dataset.layoutId || '');
      }
    });

    dashboardGridEl.addEventListener('dragover', (event) => {
      if (!dragCard) {
        return;
      }
      event.preventDefault();
    });

    dashboardGridEl.addEventListener('drop', (event) => {
      if (!dragCard) {
        return;
      }
      event.preventDefault();
      const target = event.target.closest('.dashboard-card');
      if (!target || target === dragCard) {
        return;
      }
      const rect = target.getBoundingClientRect();
      const isAfter = event.clientY > rect.top + rect.height / 2;
      if (isAfter) {
        dashboardGridEl.insertBefore(dragCard, target.nextSibling);
      } else {
        dashboardGridEl.insertBefore(dragCard, target);
      }
      getDashboardCards().forEach((card, index) => {
        card.style.order = (index + 1).toString();
        card.dataset.order = (index + 1).toString();
      });
      refreshActiveLayoutState();
    });

    dashboardGridEl.addEventListener('dragend', () => {
      if (dragCard) {
        dragCard.classList.remove('is-dragging');
      }
      dragCard = null;
    });

    dashboardGridEl.addEventListener('pointerdown', (event) => {
      const handle = event.target;
      if (layoutLocked || !handle || !handle.classList.contains('resize-handle')) {
        return;
      }
      const card = handle.closest('.dashboard-card');
      if (!card) {
        return;
      }
      const styles = window.getComputedStyle(dashboardGridEl);
      const gapValue = parseFloat(styles.columnGap || styles.gap || '0');
      const rowHeight = parseFloat(styles.gridAutoRows || '32');
      const columns = parseInt(styles.getPropertyValue('--grid-columns') || '12', 10);
      const gridRect = dashboardGridEl.getBoundingClientRect();
      const colWidth = (gridRect.width - gapValue * (columns - 1)) / columns;
      resizeState = {
        card,
        startX: event.clientX,
        startY: event.clientY,
        startW: Number(card.dataset.spanX || card.style.getPropertyValue('--span-x') || 6),
        startH: Number(card.dataset.spanY || card.style.getPropertyValue('--span-y') || 6),
        colWidth,
        rowHeight,
        gap: gapValue,
        columns
      };
      card.classList.add('is-resizing');
      event.preventDefault();
      card.setPointerCapture(event.pointerId);
    });

    dashboardGridEl.addEventListener('pointermove', (event) => {
      if (!resizeState) {
        return;
      }
      const dx = event.clientX - resizeState.startX;
      const dy = event.clientY - resizeState.startY;
      const colUnit = resizeState.colWidth + resizeState.gap;
      const rowUnit = resizeState.rowHeight + resizeState.gap;
      const deltaCols = Math.round(dx / colUnit);
      const deltaRows = Math.round(dy / rowUnit);
      const minWidth = 3;
      const minHeight = 3;
      const maxWidth = resizeState.columns;
      const maxHeight = 20;
      const nextW = Math.min(maxWidth, Math.max(minWidth, resizeState.startW + deltaCols));
      const nextH = Math.min(maxHeight, Math.max(minHeight, resizeState.startH + deltaRows));
      resizeState.card.style.setProperty('--span-x', nextW.toString());
      resizeState.card.style.setProperty('--span-y', nextH.toString());
      resizeState.card.dataset.spanX = nextW.toString();
      resizeState.card.dataset.spanY = nextH.toString();
    });

    dashboardGridEl.addEventListener('pointerup', (event) => {
      if (!resizeState) {
        return;
      }
      const card = resizeState.card;
      card.classList.remove('is-resizing');
      try {
        card.releasePointerCapture(event.pointerId);
      } catch {}
      resizeState = null;
      refreshActiveLayoutState();
    });
  }

  function updateSyslogPagination(itemCount) {
    updatePaginationControls(
      syslogPageEl,
      syslogRangeEl,
      syslogPrevBtn,
      syslogNextBtn,
      syslogPage,
      SYSLOG_PAGE_SIZE,
      itemCount
    );
  }

  function updateEventPagination(itemCount) {
    updatePaginationControls(
      eventPageEl,
      eventRangeEl,
      eventPrevBtn,
      eventNextBtn,
      eventPage,
      EVENTS_PAGE_SIZE,
      itemCount
    );
  }

  function renderHealthBanner(message) {
    if (!healthBannerEl || !healthBannerTextEl) {
      return;
    }
    if (!message) {
      healthBannerEl.classList.remove('is-visible');
      healthBannerTextEl.textContent = '';
      return;
    }
    healthBannerTextEl.textContent = message;
    healthBannerEl.classList.add('is-visible');
  }

  function renderServiceBanner(message, isWarning = false) {
    if (!serviceBannerEl || !serviceBannerTextEl) {
      return;
    }
    if (!message) {
      serviceBannerEl.classList.remove('is-visible', 'service-banner--warn');
      serviceBannerTextEl.textContent = '';
      return;
    }
    serviceBannerTextEl.textContent = message;
    serviceBannerEl.classList.add('is-visible');
    serviceBannerEl.classList.toggle('service-banner--warn', Boolean(isWarning));
  }

  function setKpiValue(element, value) {
    if (!element) {
      return;
    }
    if (value == null || Number.isNaN(value)) {
      element.textContent = '--';
      return;
    }
    element.textContent = value.toString();
  }

  function renderDiskTable(disks) {
    if (!diskTableBody) {
      return;
    }
    clearElement(diskTableBody);
    if (!Array.isArray(disks) || disks.length === 0) {
      setEmptyRow(diskTableBody, 4, 'No disk metrics reported.');
      return;
    }
    const fragment = document.createDocumentFragment();
    disks.forEach((disk) => {
      const row = document.createElement('tr');
      const drive = document.createElement('td');
      drive.textContent = disk.Drive || '—';
      const used = document.createElement('td');
      used.textContent = `${formatNumber(disk.UsedGB, 1)} GB`;
      const total = document.createElement('td');
      total.textContent = `${formatNumber(disk.TotalGB, 1)} GB`;
      const pct = document.createElement('td');
      pct.textContent = formatPercent(disk.UsedPct);
      row.append(drive, used, total, pct);
      fragment.appendChild(row);
    });
    diskTableBody.appendChild(fragment);
  }

  function renderEventList(items, listEl, totalEl, emptyMessage) {
    if (!listEl || !totalEl) {
      return;
    }
    clearElement(listEl);
    let total = 0;
    if (!Array.isArray(items) || items.length === 0) {
      const li = document.createElement('li');
      li.className = 'empty';
      li.textContent = emptyMessage;
      listEl.appendChild(li);
      totalEl.textContent = '0';
      setCardCollapsed(listEl, true);
      return;
    }
    const fragment = document.createDocumentFragment();
    items
      .slice()
      .sort((a, b) => (Number(b.Count) || 0) - (Number(a.Count) || 0))
      .forEach((item) => {
        const li = document.createElement('li');
        const source = document.createElement('span');
        source.className = 'list__source';
        source.textContent = item.Source || 'Unknown source';
        const count = Number(item.Count) || 0;
        const countEl = document.createElement('span');
        countEl.className = 'list__count';
        countEl.textContent = count.toString();
        total += count;
        li.append(source, countEl);
        fragment.appendChild(li);
      });
    listEl.appendChild(fragment);
    totalEl.textContent = total.toString();
    setCardCollapsed(listEl, total === 0);
  }

  function renderNetworkTable(entries) {
    if (!networkTableBody) {
      return;
    }
    clearElement(networkTableBody);
    if (!Array.isArray(entries) || entries.length === 0) {
      setEmptyRow(networkTableBody, 3, 'No active adapters detected.');
      if (networkCountEl) {
        networkCountEl.textContent = '0';
      }
      setCardCollapsed(networkTableBody, true);
      return;
    }
    const fragment = document.createDocumentFragment();
    entries.forEach((entry) => {
      const row = document.createElement('tr');
      const name = document.createElement('td');
      name.textContent = entry.Adapter || '—';
      const sent = document.createElement('td');
      sent.textContent = formatBytesPerSec(entry.BytesSentPerSec);
      const recv = document.createElement('td');
      recv.textContent = formatBytesPerSec(entry.BytesRecvPerSec);
      row.append(name, sent, recv);
      fragment.appendChild(row);
    });
    networkTableBody.appendChild(fragment);
    if (networkCountEl) {
      networkCountEl.textContent = entries.length.toString();
    }
    setCardCollapsed(networkTableBody, false);
  }

  function renderProcessTable(processes) {
    if (!processTableBody) {
      return;
    }
    clearElement(processTableBody);
    if (!Array.isArray(processes) || processes.length === 0) {
      setEmptyRow(processTableBody, 3, 'No process data returned.');
      return;
    }
    const fragment = document.createDocumentFragment();
    processes.forEach((proc) => {
      const row = document.createElement('tr');
      const name = document.createElement('td');
      name.textContent = proc.Name || '—';
      const cpu = document.createElement('td');
      cpu.textContent = formatNumber(proc.CPU, 1);
      const pid = document.createElement('td');
      pid.textContent = proc.Id != null ? proc.Id.toString() : '—';
      row.append(name, cpu, pid);
      fragment.appendChild(row);
    });
    processTableBody.appendChild(fragment);
  }

  function severityChipClass(label) {
    const value = (label || '').toString().toLowerCase();
    if (['emerg', 'alert', 'crit', 'critical', 'error'].includes(value)) {
      return 'chip--sev-error';
    }
    if (['warn', 'warning'].includes(value)) {
      return 'chip--sev-warn';
    }
    if (['info', 'information', 'notice'].includes(value)) {
      return 'chip--sev-info';
    }
    if (value === 'debug' || value === 'verbose') {
      return 'chip--sev-debug';
    }
    return '';
  }

  function categoryChipClass(category) {
    if (!category) {
      return 'chip--system';
    }
    const value = category.toString().toLowerCase();
    switch (value) {
      case 'wifi':
      case 'dhcp':
      case 'firewall':
      case 'auth':
      case 'update':
      case 'service':
      case 'security':
      case 'application':
      case 'dns':
      case 'network':
      case 'system':
        return `chip--${value}`;
      default:
        return 'chip--system';
    }
  }

  function renderSyslogSummary(summary) {
    if (!summary) {
      return;
    }
    if (syslogTotal1hEl) {
      syslogTotal1hEl.textContent = summary.total1h != null ? summary.total1h : '--';
    }
    if (syslogTotal24hEl) {
      syslogTotal24hEl.textContent = summary.total24h != null ? summary.total24h : '--';
    }
    if (syslogTopAppEl) {
      const top = Array.isArray(summary.topApps) && summary.topApps.length ? summary.topApps[0].app : '--';
      syslogTopAppEl.textContent = top || '--';
    }

    let infoTotal = 0;
    let warnTotal = 0;
    let errorTotal = 0;
    if (Array.isArray(summary.bySeverity)) {
      summary.bySeverity.forEach((entry) => {
        const count = Number(entry.total) || 0;
        const sev = Number(entry.severity);
        if (!Number.isNaN(sev)) {
          if (sev <= 3) {
            errorTotal += count;
          } else if (sev === 4) {
            warnTotal += count;
          } else {
            infoTotal += count;
          }
          return;
        }
        const label = (entry.severity || '').toString().toLowerCase();
        if (['emerg', 'alert', 'critical', 'crit', 'error'].includes(label)) {
          errorTotal += count;
        } else if (label === 'warning' || label === 'warn') {
          warnTotal += count;
        } else if (label) {
          infoTotal += count;
        }
      });
    }
    if (syslogInfoEl) {
      syslogInfoEl.textContent = infoTotal.toString();
    }
    if (syslogWarnEl) {
      syslogWarnEl.textContent = warnTotal.toString();
    }
    if (syslogErrorEl) {
      syslogErrorEl.textContent = errorTotal.toString();
    }
  }

  function renderSyslogRows(rows) {
    if (!syslogTableBody) {
      return;
    }
    clearElement(syslogTableBody);
    if (!Array.isArray(rows) || rows.length === 0) {
      setEmptyRow(syslogTableBody, 6, 'No syslog rows yet.');
      return;
    }
    const fragment = document.createDocumentFragment();
    rows.forEach((row) => {
      const tr = document.createElement('tr');
      const time = document.createElement('td');
      time.textContent = formatShortTime(row.received_utc);
      const host = document.createElement('td');
      host.textContent = row.source_host || '—';
      const app = document.createElement('td');
      app.textContent = row.app_name || '—';
      const severity = document.createElement('td');
      const sevLabel = row.severity_label || row.severity;
      const sevChip = document.createElement('span');
      sevChip.className = `chip ${severityChipClass(sevLabel)}`;
      sevChip.textContent = sevLabel || 'unknown';
      severity.appendChild(sevChip);
      const category = document.createElement('td');
      const catValue = row.category || 'system';
      const catChip = document.createElement('span');
      catChip.className = `chip ${categoryChipClass(catValue)}`;
      catChip.textContent = catValue;
      category.appendChild(catChip);
      const message = document.createElement('td');
      message.textContent = truncateText(row.message || '', 180);
      tr.append(time, host, app, severity, category, message);
      fragment.appendChild(tr);
    });
    syslogTableBody.appendChild(fragment);
  }

  async function loadSyslogSummary() {
    if (!syslogTotal24hEl && !syslogTotal1hEl) {
      return;
    }
    try {
      const params = buildSyslogParams();
      params.set('_', Date.now().toString());
      const res = await fetch(`${SYSLOG_SUMMARY_ENDPOINT}?${params.toString()}`, { cache: 'no-store' });
      if (!res.ok) {
        throw new Error(`HTTP ${res.status}`);
      }
      const data = await res.json();
      renderSyslogSummary(data);
    } catch (err) {
      if (syslogTotal24hEl) {
        syslogTotal24hEl.textContent = '--';
      }
      if (syslogTotal1hEl) {
        syslogTotal1hEl.textContent = '--';
      }
    }
  }

  async function loadSyslogRows() {
    if (!syslogTableBody) {
      return;
    }
    clearElement(syslogTableBody);
    setEmptyRow(syslogTableBody, 6, 'Loading syslog…');
    const params = buildSyslogParams();
    params.set('limit', SYSLOG_PAGE_SIZE.toString());
    params.set('offset', Math.max(0, (syslogPage - 1) * SYSLOG_PAGE_SIZE).toString());
    try {
      const res = await fetch(`${SYSLOG_RECENT_ENDPOINT}?${params.toString()}`, { cache: 'no-store' });
      if (!res.ok) {
        throw new Error(`HTTP ${res.status}`);
      }
      const data = await res.json();
      const rows = Array.isArray(data) ? data : [];
      if (rows.length === 0 && syslogPage > 1) {
        syslogPage -= 1;
        return loadSyslogRows();
      }
      renderSyslogRows(rows);
      updateSyslogPagination(rows.length);
    } catch (err) {
      clearElement(syslogTableBody);
      setEmptyRow(syslogTableBody, 6, 'Failed to load syslog.');
      updateSyslogPagination(0);
    }
  }

  function renderEventSummary(summary) {
    if (!summary) {
      return;
    }
    if (eventsTotal1hEl) {
      eventsTotal1hEl.textContent = summary.total1h != null ? summary.total1h : '--';
    }
    if (eventsTotal24hEl) {
      eventsTotal24hEl.textContent = summary.total24h != null ? summary.total24h : '--';
    }
    if (eventsTopSourceEl) {
      const top = Array.isArray(summary.topSources) && summary.topSources.length ? summary.topSources[0].source : '--';
      eventsTopSourceEl.textContent = top || '--';
    }

    let infoTotal = 0;
    let warnTotal = 0;
    let errorTotal = 0;
    if (Array.isArray(summary.bySeverity)) {
      summary.bySeverity.forEach((entry) => {
        const label = (entry.severity || '').toString().toLowerCase();
        const count = Number(entry.total) || 0;
        if (label === 'warning' || label === 'warn') {
          warnTotal += count;
        } else if (label === 'information' || label === 'info') {
          infoTotal += count;
        } else if (label) {
          errorTotal += count;
        }
      });
    }
    if (eventsWarnEl) {
      eventsWarnEl.textContent = warnTotal.toString();
    }
    if (eventsErrorEl) {
      eventsErrorEl.textContent = errorTotal.toString();
    }
    if (eventsInfoEl) {
      eventsInfoEl.textContent = infoTotal.toString();
    }
  }

  function renderEventRows(rows) {
    if (!eventTableBody) {
      return;
    }
    clearElement(eventTableBody);
    if (!Array.isArray(rows) || rows.length === 0) {
      setEmptyRow(eventTableBody, 6, 'No events yet.');
      return;
    }
    const fragment = document.createDocumentFragment();
    rows.forEach((row) => {
      const tr = document.createElement('tr');
      const time = document.createElement('td');
      time.textContent = formatShortTime(row.occurred_at);
      const source = document.createElement('td');
      source.textContent = row.source || '—';
      const severity = document.createElement('td');
      const sevLabel = row.severity || 'unknown';
      const sevChip = document.createElement('span');
      sevChip.className = `chip ${severityChipClass(sevLabel)}`;
      sevChip.textContent = sevLabel;
      severity.appendChild(sevChip);
      const category = document.createElement('td');
      const catValue = row.category || 'application';
      const catChip = document.createElement('span');
      catChip.className = `chip ${categoryChipClass(catValue)}`;
      catChip.textContent = catValue;
      category.appendChild(catChip);
      const provider = document.createElement('td');
      provider.textContent = row.subject || '—';
      const message = document.createElement('td');
      message.textContent = truncateText(row.message || '', 180);
      tr.append(time, source, severity, category, provider, message);
      fragment.appendChild(tr);
    });
    eventTableBody.appendChild(fragment);
  }

  const TIMELINE_CATEGORIES = ['wifi', 'dhcp', 'firewall', 'auth', 'dns', 'network', 'system', 'unknown'];
  const SYSLOG_TIMELINE_CATEGORIES = ['error', 'warning', 'info', 'debug'];
  const EVENT_TIMELINE_CATEGORIES = ['error', 'warning', 'info'];
  const SYSLOG_TIMELINE_LABELS = {
    error: 'Error',
    warning: 'Warning',
    info: 'Info',
    debug: 'Debug'
  };
  const EVENT_TIMELINE_LABELS = {
    error: 'Error',
    warning: 'Warning',
    info: 'Info'
  };

  function renderLegend(legendEl, categories, labels) {
    if (!legendEl) {
      return;
    }
    legendEl.innerHTML = categories.map((cat) => {
      const label = labels && labels[cat] ? labels[cat] : cat;
      return `<span class="legend-item"><span class="legend-dot ${cat}"></span>${label}</span>`;
    }).join('');
  }

  function renderBucketTimeline(chartEl, data, categories, emptyMessage) {
    if (!chartEl) {
      return;
    }
    clearElement(chartEl);
    if (!Array.isArray(data) || data.length === 0) {
      const empty = document.createElement('div');
      empty.className = 'timeline-empty';
      empty.textContent = emptyMessage;
      chartEl.appendChild(empty);
      return;
    }

    const buckets = new Map();
    data.forEach((row) => {
      const bucket = row.bucket_start;
      if (!buckets.has(bucket)) {
        buckets.set(bucket, { total: 0, categories: {} });
      }
      const entry = buckets.get(bucket);
      const count = Number(row.total) || 0;
      entry.total += count;
      const category = (row.category || 'unknown').toString().toLowerCase();
      entry.categories[category] = (entry.categories[category] || 0) + count;
    });

    const bucketEntries = Array.from(buckets.entries());
    const maxTotal = bucketEntries.reduce((max, [, value]) => Math.max(max, value.total), 1);
    const fragment = document.createDocumentFragment();
    bucketEntries.forEach(([bucket, value]) => {
      const bar = document.createElement('div');
      bar.className = 'timeline-bar';
      bar.title = `${formatShortTime(bucket)} • ${value.total} events`;
      categories.forEach((cat) => {
        const count = value.categories[cat] || 0;
        if (!count) {
          return;
        }
        const seg = document.createElement('div');
        seg.className = `timeline-seg category-${cat}`;
        seg.style.height = `${(count / maxTotal) * 100}%`;
        bar.appendChild(seg);
      });
      fragment.appendChild(bar);
    });
    chartEl.appendChild(fragment);
  }

  function renderTimelineLegend() {
    renderLegend(timelineLegendEl, TIMELINE_CATEGORIES);
  }

  function renderSyslogTimelineLegend() {
    renderLegend(syslogTimelineLegendEl, SYSLOG_TIMELINE_CATEGORIES, SYSLOG_TIMELINE_LABELS);
  }

  function renderEventTimelineLegend() {
    renderLegend(eventTimelineLegendEl, EVENT_TIMELINE_CATEGORIES, EVENT_TIMELINE_LABELS);
  }

  function renderTimeline(data) {
    renderBucketTimeline(timelineChartEl, data, TIMELINE_CATEGORIES, 'No activity in this window.');
  }

  function renderDeviceSummary(rows) {
    if (!deviceTableBody) {
      return;
    }
    clearElement(deviceTableBody);
    if (!Array.isArray(rows) || rows.length === 0) {
      setEmptyRow(deviceTableBody, 5, 'No device activity yet.');
      if (deviceCountEl) {
        deviceCountEl.textContent = '0';
      }
      setCardCollapsed(deviceTableBody, true);
      return;
    }
    const fragment = document.createDocumentFragment();
    rows.forEach((row) => {
      const tr = document.createElement('tr');
      const mac = document.createElement('td');
      mac.textContent = row.mac_address || '—';
      const lastSeen = document.createElement('td');
      lastSeen.textContent = formatShortTime(row.last_seen);
      const events = document.createElement('td');
      events.textContent = row.events_1h != null ? row.events_1h : '--';
      const rssi = document.createElement('td');
      rssi.textContent = row.last_rssi != null ? row.last_rssi : '--';
      const lastEvent = document.createElement('td');
      lastEvent.textContent = row.last_event_type || '—';
      tr.append(mac, lastSeen, events, rssi, lastEvent);
      fragment.appendChild(tr);
    });
    deviceTableBody.appendChild(fragment);
    if (deviceCountEl) {
      deviceCountEl.textContent = rows.length.toString();
    }
    setCardCollapsed(deviceTableBody, false);
  }

  function formatRssiValue(rssi) {
    if (typeof rssi !== 'number' || !isFinite(rssi)) {
      return '--';
    }
    return `${rssi} dBm`;
  }

  function formatBandLabel(value) {
    if (!value) {
      return '--';
    }
    const lower = value.toString().toLowerCase();
    if (lower.includes('2.4') || lower.includes('2g') || lower.includes('wl0')) {
      return '2.4 GHz';
    }
    if (lower.includes('5') || lower.includes('5g') || lower.includes('wl1')) {
      return '5 GHz';
    }
    if (lower.includes('6') || lower.includes('6g') || lower.includes('wl2')) {
      return '6 GHz';
    }
    return value;
  }

  function renderWifiClients(rows) {
    if (!wifiTableBody) {
      return;
    }
    clearElement(wifiTableBody);
    if (!Array.isArray(rows) || rows.length === 0) {
      setEmptyRow(wifiTableBody, 6, 'No Wi-Fi clients detected.');
      if (wifiClientCountEl) {
        wifiClientCountEl.textContent = '0';
      }
      setCardCollapsed(wifiTableBody, true);
      return;
    }
    const fragment = document.createDocumentFragment();
    rows.forEach((row) => {
      const tr = document.createElement('tr');
      const client = document.createElement('td');
      client.textContent = row.nickname || row.hostname || row.mac_address || '—';
      const ip = document.createElement('td');
      ip.textContent = row.current_ip || row.ip_address || '—';
      const band = document.createElement('td');
      band.textContent = formatBandLabel(row.current_interface || row.interface);
      const rssi = document.createElement('td');
      rssi.textContent = formatRssiValue(row.current_rssi);
      const rates = document.createElement('td');
      const tx = formatNumber(row.tx_rate_mbps, 1);
      const rx = formatNumber(row.rx_rate_mbps, 1);
      rates.textContent = (tx !== '--' || rx !== '--') ? `${tx}/${rx} Mbps` : '--';
      const lastSeen = document.createElement('td');
      lastSeen.textContent = formatShortTime(row.last_seen_utc || row.last_snapshot_time || row.sample_time_utc);
      tr.append(client, ip, band, rssi, rates, lastSeen);
      fragment.appendChild(tr);
    });
    wifiTableBody.appendChild(fragment);
    if (wifiClientCountEl) {
      wifiClientCountEl.textContent = rows.length.toString();
    }
    setCardCollapsed(wifiTableBody, false);
  }

  async function loadTimeline() {
    if (!timelineChartEl) {
      return;
    }
    const params = new URLSearchParams();
    const mac = timelineMacInput ? timelineMacInput.value.trim() : '';
    const category = timelineCategorySelect ? timelineCategorySelect.value : '';
    const eventType = timelineEventTypeSelect ? timelineEventTypeSelect.value : '';
    if (mac) {
      params.set('mac', mac);
    }
    if (category) {
      params.set('category', category);
    }
    if (eventType) {
      params.set('eventType', eventType);
    }
    params.set('bucketMinutes', '5');
    params.set('since', 'PT24H');
    const sinceMinutes = parseIsoDurationToMinutes(params.get('since'));
    try {
      const data = await fetchJson(`${TIMELINE_ENDPOINT}?${params.toString()}`, { cache: 'no-store' });
      renderTimeline(data);
    } catch (err) {
      console.error('Failed to load timeline', err);
      if (err && err.status === 404 && mac) {
        try {
          const devicesData = await fetchJson(`/api/lan/devices?_=${Date.now()}`, { cache: 'no-store' });
          const devices = Array.isArray(devicesData.devices) ? devicesData.devices : [];
          const match = devices.find((row) => {
            return (row.mac_address || '').toLowerCase() === mac.toLowerCase();
          });
          if (match && match.device_id != null) {
            const hours = Math.max(1, Math.ceil(sinceMinutes / 60));
            const timelineData = await fetchJson(`/api/lan/device/${match.device_id}/timeline?hours=${hours}`, { cache: 'no-store' });
            const bucketValue = Number(params.get('bucketMinutes') || 5);
            const bucketMinutes = Number.isFinite(bucketValue) && bucketValue > 0 ? bucketValue : 5;
            const fallbackRows = aggregateSnapshotsToTimeline(timelineData.timeline || [], bucketMinutes);
            renderTimeline(fallbackRows);
            return;
          }
        } catch (fallbackErr) {
          console.error('Fallback timeline load failed', fallbackErr);
        }
      }
      clearElement(timelineChartEl);
      const empty = document.createElement('div');
      empty.className = 'timeline-empty';
      empty.textContent = 'Failed to load timeline.';
      timelineChartEl.appendChild(empty);
    }
  }

  async function loadSyslogTimeline() {
    if (!syslogTimelineChartEl) {
      return;
    }
    const params = buildSyslogParams();
    const bucketValue = syslogBucketSelect ? Number(syslogBucketSelect.value) : NaN;
    const bucketMinutes = Number.isFinite(bucketValue) && bucketValue > 0 ? bucketValue : 15;
    params.set('bucketMinutes', bucketMinutes.toString());
    params.set('_', Date.now().toString());
    try {
      const data = await fetchJson(`${SYSLOG_TIMELINE_ENDPOINT}?${params.toString()}`, { cache: 'no-store' });
      renderBucketTimeline(syslogTimelineChartEl, data, SYSLOG_TIMELINE_CATEGORIES, 'No syslog activity in this window.');
    } catch (err) {
      console.error('Failed to load syslog timeline', err);
      renderBucketTimeline(syslogTimelineChartEl, [], SYSLOG_TIMELINE_CATEGORIES, 'Failed to load syslog timeline.');
    }
  }

  async function loadEventTimeline() {
    if (!eventTimelineChartEl) {
      return;
    }
    const params = buildEventParams();
    const bucketValue = eventBucketSelect ? Number(eventBucketSelect.value) : NaN;
    const bucketMinutes = Number.isFinite(bucketValue) && bucketValue > 0 ? bucketValue : 15;
    params.set('bucketMinutes', bucketMinutes.toString());
    params.set('_', Date.now().toString());
    try {
      const data = await fetchJson(`${EVENTS_TIMELINE_ENDPOINT}?${params.toString()}`, { cache: 'no-store' });
      renderBucketTimeline(eventTimelineChartEl, data, EVENT_TIMELINE_CATEGORIES, 'No event activity in this window.');
    } catch (err) {
      console.error('Failed to load event timeline', err);
      renderBucketTimeline(eventTimelineChartEl, [], EVENT_TIMELINE_CATEGORIES, 'Failed to load event timeline.');
    }
  }

  async function loadDeviceSummary() {
    if (!deviceTableBody) {
      return;
    }
    clearElement(deviceTableBody);
    setEmptyRow(deviceTableBody, 5, 'Loading devices…');
    try {
      const data = await fetchJson(`${DEVICES_SUMMARY_ENDPOINT}?limit=10&_=${Date.now()}`, { cache: 'no-store' });
      const rows = Array.isArray(data) ? data : (Array.isArray(data.devices) ? data.devices : data);
      renderDeviceSummary(rows);
    } catch (err) {
      console.error('Failed to load devices summary', err);
      if (err && err.status === 404) {
        try {
          const fallbackData = await fetchJson(`/api/lan/devices?_=${Date.now()}`, { cache: 'no-store' });
          const mapped = mapLanDevicesToSummary(fallbackData);
          renderDeviceSummary(mapped);
          return;
        } catch (fallbackErr) {
          console.error('Fallback device summary load failed', fallbackErr);
        }
      }
      clearElement(deviceTableBody);
      setEmptyRow(deviceTableBody, 5, 'Failed to load devices.');
    }
  }

  async function loadWifiClients() {
    if (!wifiTableBody) {
      return;
    }
    clearElement(wifiTableBody);
    setEmptyRow(wifiTableBody, 6, 'Loading Wi-Fi clients…');
    try {
      const data = await fetchJson(`${WIFI_CLIENTS_ENDPOINT}?limit=50&_=${Date.now()}`, { cache: 'no-store' });
      const rows = Array.isArray(data) ? data : (Array.isArray(data.clients) ? data.clients : data);
      renderWifiClients(rows);
    } catch (err) {
      console.error('Failed to load Wi-Fi clients', err);
      clearElement(wifiTableBody);
      setEmptyRow(wifiTableBody, 6, 'Failed to load Wi-Fi clients.');
      if (wifiClientCountEl) {
        wifiClientCountEl.textContent = '--';
      }
      setCardCollapsed(wifiTableBody, false);
    }
  }

  async function loadEventSummary() {
    if (!eventsTotal24hEl && !eventsTotal1hEl) {
      return;
    }
    try {
      const params = buildEventParams();
      params.set('_', Date.now().toString());
      const res = await fetch(`${EVENTS_SUMMARY_ENDPOINT}?${params.toString()}`, { cache: 'no-store' });
      if (!res.ok) {
        throw new Error(`HTTP ${res.status}`);
      }
      const data = await res.json();
      renderEventSummary(data);
    } catch (err) {
      if (eventsTotal24hEl) {
        eventsTotal24hEl.textContent = '--';
      }
      if (eventsTotal1hEl) {
        eventsTotal1hEl.textContent = '--';
      }
    }
  }

  async function loadEventRows() {
    if (!eventTableBody) {
      return;
    }
    clearElement(eventTableBody);
    setEmptyRow(eventTableBody, 6, 'Loading events…');
    const params = buildEventParams();
    params.set('limit', EVENTS_PAGE_SIZE.toString());
    params.set('offset', Math.max(0, (eventPage - 1) * EVENTS_PAGE_SIZE).toString());
    try {
      const res = await fetch(`${EVENTS_RECENT_ENDPOINT}?${params.toString()}`, { cache: 'no-store' });
      if (!res.ok) {
        throw new Error(`HTTP ${res.status}`);
      }
      const data = await res.json();
      const rows = Array.isArray(data) ? data : [];
      if (rows.length === 0 && eventPage > 1) {
        eventPage -= 1;
        return loadEventRows();
      }
      renderEventRows(rows);
      updateEventPagination(rows.length);
    } catch (err) {
      clearElement(eventTableBody);
      setEmptyRow(eventTableBody, 6, 'Failed to load events.');
      updateEventPagination(0);
    }
  }

  async function loadOverviewSummary(force = false) {
    const now = Date.now();
    if (!force && now - lastOverviewRefresh < OVERVIEW_REFRESH_INTERVAL) {
      return;
    }
    lastOverviewRefresh = now;
    overviewState.errorsToday = null;
    overviewState.warningsToday = null;
    overviewState.noisyHosts = null;
    overviewState.topHost = null;
    overviewState.topApp = null;
    overviewState.routerDrops = null;
    const range = getTodayRange();
    const syslogParams = new URLSearchParams();
    const startLocal = formatLocalIso(range.start);
    const endLocal = formatLocalIso(range.end);
    if (startLocal) {
      syslogParams.set('start', startLocal);
    }
    if (endLocal) {
      syslogParams.set('end', endLocal);
    }
    syslogParams.set('_', now.toString());
    const eventParams = new URLSearchParams();
    if (startLocal) {
      eventParams.set('start', startLocal);
    }
    if (endLocal) {
      eventParams.set('end', endLocal);
    }
    eventParams.set('_', now.toString());

    const [syslogResult, eventResult, routerResult] = await Promise.allSettled([
      fetchJson(`${SYSLOG_SUMMARY_ENDPOINT}?${syslogParams.toString()}`, { cache: 'no-store' }),
      fetchJson(`${EVENTS_SUMMARY_ENDPOINT}?${eventParams.toString()}`, { cache: 'no-store' }),
      fetchJson(`${ROUTER_KPI_ENDPOINT}?_=${now}`, { cache: 'no-store' })
    ]);

    if (syslogResult.status === 'fulfilled') {
      const syslog = syslogResult.value;
      const syslogTotals = computeSyslogSeverityTotals(syslog);
      const eventTotals = eventResult.status === 'fulfilled'
        ? computeEventSeverityTotals(eventResult.value)
        : { error: 0, warn: 0 };
      overviewState.errorsToday = syslogTotals.error + eventTotals.error;
      overviewState.warningsToday = syslogTotals.warn + eventTotals.warn;
      overviewState.noisyHosts = typeof syslog.noisyHosts === 'number' ? syslog.noisyHosts : null;
      overviewState.topHost = Array.isArray(syslog.topHosts) && syslog.topHosts.length ? syslog.topHosts[0].host : null;
      overviewState.topApp = Array.isArray(syslog.topApps) && syslog.topApps.length ? syslog.topApps[0].app : null;
    } else if (eventResult.status === 'fulfilled') {
      const eventTotals = computeEventSeverityTotals(eventResult.value);
      overviewState.errorsToday = eventTotals.error;
      overviewState.warningsToday = eventTotals.warn;
    }

    if (routerResult.status === 'fulfilled') {
      const router = routerResult.value;
      overviewState.routerDrops = typeof router?.kpis?.total_drop === 'number' ? router.kpis.total_drop : null;
    }

    renderOverview();
  }

  async function loadHealthStatus() {
    if (!healthBannerEl || !healthBannerTextEl) {
      return;
    }
    try {
      const res = await fetch(`${HEALTH_ENDPOINT}?_=${Date.now()}`, { cache: 'no-store' });
      const payload = await res.text();
      const data = payload ? JSON.parse(payload) : null;
      if (!data || data.ok) {
        renderHealthBanner('');
        return;
      }
      const failures = [];
      const errorDetails = [];
      if (data.checks && typeof data.checks === 'object') {
        Object.entries(data.checks).forEach(([key, value]) => {
          if (!value || value.ok) {
            return;
          }
          failures.push(key.replace(/_/g, ' '));
          if (value.error) {
            errorDetails.push(`${key}: ${value.error}`);
          }
        });
      }
      let message = failures.length
        ? `Checks failing: ${failures.join(', ')}.`
        : 'Health checks are reporting issues.';
      if (errorDetails.length) {
        message = `${message} ${errorDetails[0]}`;
      }
      renderHealthBanner(message);
    } catch (err) {
      if (err && err.status === 404) {
        renderHealthBanner('');
        return;
      }
      console.error('Failed to load health status', err);
      renderHealthBanner('Health checks unavailable.');
    }
  }

  async function loadServiceStatus() {
    if (!serviceBannerEl || !serviceBannerTextEl) {
      return;
    }
    try {
      const res = await fetch(`${STATUS_ENDPOINT}?_=${Date.now()}`, { cache: 'no-store' });
      if (!res.ok) {
        throw new Error(`HTTP ${res.status}`);
      }
      const data = await res.json();
      const parts = [];
      const prefix = data?.listener?.prefix || `${window.location.origin}/`;
      const uptime = data?.listener?.uptime_seconds;
      if (prefix) {
        parts.push(`Listener ${prefix}`);
      }
      if (typeof uptime === 'number') {
        parts.push(`Uptime ${formatDurationSeconds(uptime)}`);
      }
      if (Array.isArray(data?.startup_issues) && data.startup_issues.length) {
        parts.push(`Startup: ${truncateText(data.startup_issues[0], 120)}`);
      }
      if (data?.db?.circuit_open) {
        parts.push('DB circuit open');
      }
      if (data?.last_error?.message) {
        parts.push(`Last error: ${truncateText(data.last_error.message, 140)}`);
      }
      const isWarning = Boolean(
        (data?.startup_issues && data.startup_issues.length) ||
        data?.db?.circuit_open ||
        data?.last_error?.message
      );
      renderServiceBanner(parts.join(' • '), isWarning);
    } catch (err) {
      console.error('Failed to load service status', err);
      renderServiceBanner('Listener status unavailable.', true);
    }
  }

  async function loadRouterKpis() {
    if (!routerKpiTotalDropEl && !routerKpiIgmpDropEl) {
      return;
    }
    try {
      const data = await fetchJson(`${ROUTER_KPI_ENDPOINT}?_=${Date.now()}`, { cache: 'no-store' });
      const kpis = data && data.kpis ? data.kpis : {};
      setKpiValue(routerKpiTotalDropEl, kpis.total_drop);
      setKpiValue(routerKpiIgmpDropEl, kpis.igmp_drops);
      setKpiValue(routerKpiRoamKicksEl, kpis.roam_kicks);
      setKpiValue(routerKpiRstatsErrorsEl, kpis.rstats_errors);
      setKpiValue(routerKpiDnsmasqSigtermEl, kpis.dnsmasq_sigterm);
      setKpiValue(routerKpiAvahiSigtermEl, kpis.avahi_sigterm);
      setKpiValue(routerKpiUpnpShutdownsEl, kpis.upnp_shutdowns);
      if (routerKpiUpdatedEl) {
        routerKpiUpdatedEl.textContent = data.updated_utc ? `Updated ${formatShortTime(data.updated_utc)}` : '--';
      }
    } catch (err) {
      console.error('Failed to load router KPIs', err);
      setKpiValue(routerKpiTotalDropEl, null);
      setKpiValue(routerKpiIgmpDropEl, null);
      setKpiValue(routerKpiRoamKicksEl, null);
      setKpiValue(routerKpiRstatsErrorsEl, null);
      setKpiValue(routerKpiDnsmasqSigtermEl, null);
      setKpiValue(routerKpiAvahiSigtermEl, null);
      setKpiValue(routerKpiUpnpShutdownsEl, null);
      if (routerKpiUpdatedEl) {
        routerKpiUpdatedEl.textContent = '--';
      }
    }
  }

  function scheduleTelemetryNext(delay = TELEMETRY_REFRESH_INTERVAL) {
    clearTimeout(telemetryTimer);
    if (autoRefreshPaused) {
      return;
    }
    telemetryTimer = setTimeout(loadTelemetry, delay);
  }

  function setAutoRefreshPaused(paused) {
    autoRefreshPaused = paused;
    if (refreshStatusEl) {
      refreshStatusEl.textContent = paused ? 'Auto-refresh: paused' : 'Auto-refresh: on';
    }
    if (refreshResumeBtn) {
      refreshResumeBtn.classList.toggle('is-visible', paused);
    }
    if (paused) {
      clearTimeout(refreshTimer);
      clearTimeout(telemetryTimer);
      return;
    }
    scheduleNext(200);
    scheduleTelemetryNext(200);
  }

  async function loadTelemetry(force = false) {
    if (autoRefreshPaused && !force) {
      return;
    }
    await Promise.all([
      loadOverviewSummary(force),
      loadRouterKpis(),
      loadHealthStatus(),
      loadServiceStatus(),
      loadSyslogSummary(),
      loadSyslogRows(),
      loadSyslogTimeline(),
      loadEventSummary(),
      loadEventRows(),
      loadEventTimeline(),
      loadTimeline(),
      loadDeviceSummary(),
      loadWifiClients()
    ]);
    scheduleTelemetryNext();
  }

  function updateUI(data) {
    if (hostNameEl) {
      hostNameEl.textContent = data.ComputerName || data.Host || 'Unknown host';
    }
    if (uptimeEl) {
      uptimeEl.textContent = formatUptime(data.Uptime);
    }
    if (cpuValueEl) {
      cpuValueEl.textContent = formatPercent(data?.CPU?.Pct, { scaleTo100: false, digits: 1 });
    }
    if (memoryValueEl) {
      memoryValueEl.textContent = formatPercent(data?.Memory?.Pct, { digits: 1 });
    }
    if (memoryDetailEl) {
      memoryDetailEl.textContent = formatMemoryDetail(data.Memory);
    }
    if (latencyEl) {
      latencyEl.textContent = formatLatency(data?.Network?.LatencyMs);
    }
    if (latencyTargetEl) {
      const target = data?.Network?.LatencyTarget;
      latencyTargetEl.textContent = target ? target : 'configured target';
    }
    overviewState.latencyMs = typeof data?.Network?.LatencyMs === 'number' ? data.Network.LatencyMs : null;
    overviewState.latencyTarget = data?.Network?.LatencyTarget || null;
    renderDiskTable(Array.isArray(data.Disk) ? data.Disk : []);
    const disks = Array.isArray(data.Disk) ? data.Disk : [];
    let diskMax = null;
    let pressureCount = 0;
    disks.forEach((disk) => {
      const pct = typeof disk.UsedPct === 'number' ? disk.UsedPct : Number(disk.UsedPct);
      if (!Number.isFinite(pct)) {
        return;
      }
      const pct100 = Math.round(pct * 1000) / 10;
      if (!diskMax || pct100 > diskMax.pct) {
        diskMax = { drive: disk.Drive || '--', pct: pct100 };
      }
      if (pct >= DISK_PRESSURE_THRESHOLD) {
        pressureCount += 1;
      }
    });
    overviewState.diskPressureCount = pressureCount;
    overviewState.diskMax = diskMax;
    renderOverview();
    renderEventList(data?.Events?.Warnings, warningListEl, warningTotalEl, 'No warnings reported.');
    renderEventList(data?.Events?.Errors, errorListEl, errorTotalEl, 'No errors reported.');
    renderNetworkTable(data?.Network?.Usage);
    renderProcessTable(data?.Processes);
    const timestamp = data.Time ? formatTimestamp(data.Time) : formatTimestamp(Date.now());
    return `Last updated ${timestamp}`;
  }

  async function loadMetrics(force = false) {
    if (autoRefreshPaused && !force) {
      return;
    }
    try {
      const response = await fetch(`${METRICS_ENDPOINT}?_=${Date.now()}`, {
        cache: 'no-store'
      });
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }
      const data = await response.json();
      const detail = updateUI(data);
      setStatus('online', detail);
      scheduleNext();
    } catch (error) {
      console.error('Failed to load metrics', error);
      setStatus('offline', `Unable to reach listener (${error.message})`);
      scheduleNext(10000);
    }
  }

  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      scheduleNext(REFRESH_INTERVAL * 2);
      scheduleTelemetryNext(TELEMETRY_REFRESH_INTERVAL * 2);
    } else {
      scheduleNext(200);
      scheduleTelemetryNext(200);
    }
  });

  window.addEventListener('scroll', () => {
    const y = window.scrollY || document.documentElement.scrollTop || 0;
    if (y > 200 && !autoRefreshPaused) {
      setAutoRefreshPaused(true);
    } else if (y < 80 && autoRefreshPaused) {
      setAutoRefreshPaused(false);
    }
  }, { passive: true });

  setStatus('connecting', 'Waiting for first response…');
  scheduleNext(50);
  loadMetrics();
  loadTelemetry();

  if (syslogRefreshBtn) {
    syslogRefreshBtn.addEventListener('click', () => {
      syslogPage = 1;
      loadSyslogSummary();
      loadSyslogRows();
      loadSyslogTimeline();
      loadOverviewSummary(true);
    });
  }
  if (eventRefreshBtn) {
    eventRefreshBtn.addEventListener('click', () => {
      eventPage = 1;
      loadEventSummary();
      loadEventRows();
      loadEventTimeline();
      loadOverviewSummary(true);
    });
  }
  if (syslogPrevBtn) {
    syslogPrevBtn.addEventListener('click', () => {
      if (syslogPage > 1) {
        syslogPage -= 1;
        loadSyslogRows();
      }
    });
  }
  if (syslogNextBtn) {
    syslogNextBtn.addEventListener('click', () => {
      syslogPage += 1;
      loadSyslogRows();
    });
  }
  if (eventPrevBtn) {
    eventPrevBtn.addEventListener('click', () => {
      if (eventPage > 1) {
        eventPage -= 1;
        loadEventRows();
      }
    });
  }
  if (eventNextBtn) {
    eventNextBtn.addEventListener('click', () => {
      eventPage += 1;
      loadEventRows();
    });
  }
  if (timelineRefreshBtn) {
    timelineRefreshBtn.addEventListener('click', () => {
      loadTimeline();
    });
  }
  if (syslogBucketSelect) {
    syslogBucketSelect.addEventListener('change', () => {
      loadSyslogTimeline();
    });
  }
  if (eventBucketSelect) {
    eventBucketSelect.addEventListener('change', () => {
      loadEventTimeline();
    });
  }
  if (devicesRefreshBtn) {
    devicesRefreshBtn.addEventListener('click', () => {
      loadDeviceSummary();
    });
  }
  if (wifiRefreshBtn) {
    wifiRefreshBtn.addEventListener('click', () => {
      loadWifiClients();
    });
  }
  if (refreshResumeBtn) {
    refreshResumeBtn.addEventListener('click', () => {
      setAutoRefreshPaused(false);
      loadMetrics(true);
      loadTelemetry(true);
    });
  }

  initCardHandles();
  initDragAndResize();
  initLayoutControls();
  loadLayoutStore();

  renderTimelineLegend();
  renderSyslogTimelineLegend();
  renderEventTimelineLegend();
})();

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
  const HISTORY_WINDOW_MINUTES = 60;
  const DISK_WARN_THRESHOLD = 0.85;
  const DISK_CRITICAL_THRESHOLD = 0.92;
  const PROCESS_MAX_ROWS = 10;
  const DEFAULT_LAYOUT_NAME = 'Default';
  const LAYOUT_STORAGE_KEY = 'system-dashboard-layouts';
  const EMPTY_TOGGLE_KEY = 'system-dashboard-show-empty';

  const statusEl = document.getElementById('connection-status');
  const statusDetailEl = document.getElementById('status-detail');
  const hostNameEl = document.getElementById('host-name');
  const uptimeEl = document.getElementById('uptime-value');
  const latencyEl = document.getElementById('latency-value');
  const latencyTargetEl = document.getElementById('latency-target');
  const refreshToggleBtn = document.getElementById('refresh-toggle');
  const refreshTimestampEl = document.getElementById('refresh-timestamp');
  const healthWindowLabelEl = document.getElementById('health-window-label');
  const healthUpdatedEl = document.getElementById('health-updated');
  const kpiCpuValueEl = document.getElementById('kpi-cpu-value');
  const kpiCpuDeltaEl = document.getElementById('kpi-cpu-delta');
  const kpiCpuSparkEl = document.getElementById('kpi-cpu-spark');
  const kpiRamValueEl = document.getElementById('kpi-ram-value');
  const kpiRamDeltaEl = document.getElementById('kpi-ram-delta');
  const kpiRamSparkEl = document.getElementById('kpi-ram-spark');
  const kpiDiskWorstValueEl = document.getElementById('kpi-disk-worst');
  const kpiDiskWorstDeltaEl = document.getElementById('kpi-disk-worst-delta');
  const kpiDiskWorstSparkEl = document.getElementById('kpi-disk-worst-spark');
  const kpiDiskFreeValueEl = document.getElementById('kpi-disk-free');
  const kpiDiskFreeDeltaEl = document.getElementById('kpi-disk-free-delta');
  const kpiDiskFreeSparkEl = document.getElementById('kpi-disk-free-spark');
  const kpiNetInValueEl = document.getElementById('kpi-net-in');
  const kpiNetInDeltaEl = document.getElementById('kpi-net-in-delta');
  const kpiNetInSparkEl = document.getElementById('kpi-net-in-spark');
  const kpiNetOutValueEl = document.getElementById('kpi-net-out');
  const kpiNetOutDeltaEl = document.getElementById('kpi-net-out-delta');
  const kpiNetOutSparkEl = document.getElementById('kpi-net-out-spark');
  const kpiNet95pValueEl = document.getElementById('kpi-net-95p');
  const kpiNet95pDeltaEl = document.getElementById('kpi-net-95p-delta');
  const kpiNet95pSparkEl = document.getElementById('kpi-net-95p-spark');
  const kpiErrorsValueEl = document.getElementById('kpi-errors');
  const kpiErrorsDeltaEl = document.getElementById('kpi-errors-delta');
  const kpiErrorsSparkEl = document.getElementById('kpi-errors-spark');
  const kpiWarningsValueEl = document.getElementById('kpi-warnings');
  const kpiWarningsDeltaEl = document.getElementById('kpi-warnings-delta');
  const kpiWarningsSparkEl = document.getElementById('kpi-warnings-spark');
  const alertsErrorsEl = document.getElementById('alerts-errors');
  const alertsWarningsEl = document.getElementById('alerts-warnings');
  const alertsErrorsDeltaEl = document.getElementById('alerts-errors-delta');
  const alertsWarningsDeltaEl = document.getElementById('alerts-warnings-delta');
  const alertsUpdatedEl = document.getElementById('alerts-updated');
  const alertsListEl = document.getElementById('alerts-list');
  const alertsViewAllBtn = document.getElementById('alerts-view-all');
  const layoutSelectEl = document.getElementById('layout-select');
  const layoutNameInput = document.getElementById('layout-name');
  const layoutSaveBtn = document.getElementById('layout-save');
  const layoutDeleteBtn = document.getElementById('layout-delete');
  const layoutResetBtn = document.getElementById('layout-reset');
  const layoutLockToggle = document.getElementById('layout-lock');
  const emptyToggleEl = document.getElementById('empty-toggle');
  const dashboardGridEl = document.getElementById('dashboard-grid');
  const diskTableBody = document.querySelector('#disk-table tbody');
  const processTableBody = document.querySelector('#process-table tbody');
  const processFilterInput = document.getElementById('process-filter');
  const processWindowSelect = document.getElementById('process-window');
  const processUpdatedEl = document.getElementById('process-updated');
  const processTabButtons = Array.from(document.querySelectorAll('[data-process-mode]'));
  const networkAdapterSelect = document.getElementById('network-adapter');
  const networkInCurrentEl = document.getElementById('network-in-current');
  const networkOutCurrentEl = document.getElementById('network-out-current');
  const networkInDeltaEl = document.getElementById('network-in-delta');
  const networkOutDeltaEl = document.getElementById('network-out-delta');
  const network95pEl = document.getElementById('network-95p');
  const network95pDeltaEl = document.getElementById('network-95p-delta');
  const networkPeakEl = document.getElementById('network-peak');
  const networkUpdatedEl = document.getElementById('network-updated');
  const networkSparkEl = document.getElementById('network-spark');
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
  const healthBannerEl = document.getElementById('health-banner');
  const healthBannerTextEl = document.getElementById('health-banner-text');
  const serviceBannerEl = document.getElementById('service-banner');
  const serviceBannerTextEl = document.getElementById('service-banner-text');
  const detailDrawerEl = document.getElementById('detail-drawer');
  const detailCloseBtn = document.getElementById('detail-close');
  const detailTitleEl = document.getElementById('detail-title');
  const detailBodyEl = document.getElementById('detail-body');
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

  const kpiHistory = {
    cpu: [],
    ram: [],
    diskWorst: [],
    diskFree: [],
    netIn: [],
    netOut: [],
    net95p: [],
    errors: [],
    warnings: []
  };
  const networkHistory = new Map();
  const processHistory = new Map();
  const tableSortState = {};
  const alertState = {
    errors24h: null,
    warnings24h: null
  };
  const processState = {
    mode: 'cpu',
    windowSeconds: 300,
    filter: ''
  };
  let lastMetricsAt = null;
  const lastTableRows = {};
  let lastNetworkEntries = [];

  const DEFAULT_LAYOUT = {
    'device-timeline': { w: 8, h: 8, order: 1 },
    'wifi-clients': { w: 6, h: 8, order: 2 },
    'noisy-devices': { w: 6, h: 8, order: 3 },
    'syslog-intake': { w: 12, h: 12, order: 4 },
    'event-logs': { w: 12, h: 12, order: 5 },
    'router-kpis': { w: 4, h: 6, order: 6 }
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

  function formatBytesDelta(value) {
    if (typeof value !== 'number' || !isFinite(value)) {
      return '--';
    }
    const sign = value > 0 ? '+' : value < 0 ? '-' : '';
    return `${sign}${formatBytesPerSec(Math.abs(value))}`;
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

  function getLastHoursRange(hours = 24) {
    const end = new Date();
    const start = new Date(end.getTime() - hours * 60 * 60 * 1000);
    return { start, end };
  }

  function trimHistory(series, windowMinutes = HISTORY_WINDOW_MINUTES) {
    if (!Array.isArray(series)) {
      return [];
    }
    const cutoff = Date.now() - windowMinutes * 60 * 1000;
    return series.filter((entry) => entry && entry.t >= cutoff);
  }

  function pushHistory(series, value, timestamp = Date.now()) {
    if (!Array.isArray(series)) {
      return;
    }
    if (typeof value !== 'number' || !isFinite(value)) {
      return;
    }
    series.push({ t: timestamp, v: value });
    const trimmed = trimHistory(series);
    series.length = 0;
    series.push(...trimmed);
  }

  function getHistoryDelta(series) {
    if (!Array.isArray(series) || series.length < 2) {
      return null;
    }
    const last = series[series.length - 1];
    const prev = series[series.length - 2];
    return last && prev ? last.v - prev.v : null;
  }

  function formatSigned(value, digits = 1, suffix = '') {
    if (typeof value !== 'number' || !isFinite(value)) {
      return '--';
    }
    const sign = value > 0 ? '+' : value < 0 ? '-' : '';
    const display = Math.abs(value).toFixed(digits);
    return `${sign}${display}${suffix}`;
  }

  function setDeltaText(element, value, digits = 1, suffix = '') {
    if (!element) {
      return;
    }
    element.classList.remove('is-up', 'is-down');
    if (typeof value !== 'number' || !isFinite(value)) {
      element.textContent = '--';
      return;
    }
    element.textContent = formatSigned(value, digits, suffix);
    if (value > 0) {
      element.classList.add('is-up');
    } else if (value < 0) {
      element.classList.add('is-down');
    }
  }

  function renderSparkline(container, series) {
    if (!container) {
      return;
    }
    const values = Array.isArray(series) ? series.map((entry) => entry.v).filter((val) => typeof val === 'number' && isFinite(val)) : [];
    if (values.length < 2) {
      container.innerHTML = '<div class=\"sparkline-empty\">--</div>';
      return;
    }
    const width = 120;
    const height = 26;
    const min = Math.min(...values);
    const max = Math.max(...values);
    const range = max - min || 1;
    const points = values.map((val, idx) => {
      const x = (idx / (values.length - 1)) * width;
      const y = height - ((val - min) / range) * height;
      return `${x.toFixed(2)},${y.toFixed(2)}`;
    }).join(' ');
    container.innerHTML = `<svg viewBox=\"0 0 ${width} ${height}\" preserveAspectRatio=\"none\" aria-hidden=\"true\"><polyline fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.5\" points=\"${points}\"></polyline></svg>`;
  }

  function updateKpiTile({
    valueEl,
    deltaEl,
    sparkEl,
    series,
    value,
    formatter,
    deltaDigits = 1,
    deltaSuffix = '',
    deltaMultiplier = 1,
    deltaFormatter = null
  }) {
    if (typeof value === 'number' && isFinite(value)) {
      pushHistory(series, value);
    }
    if (valueEl) {
      valueEl.textContent = formatter ? formatter(value) : formatNumber(value, 1);
    }
    const delta = getHistoryDelta(series);
    if (deltaEl) {
      deltaEl.classList.remove('is-up', 'is-down');
    }
    if (typeof delta === 'number' && isFinite(delta)) {
      const scaled = delta * deltaMultiplier;
      if (deltaFormatter) {
        if (deltaEl) {
          deltaEl.textContent = deltaFormatter(scaled);
        }
      } else {
        setDeltaText(deltaEl, scaled, deltaDigits, deltaSuffix);
      }
      if (deltaEl) {
        if (scaled > 0) {
          deltaEl.classList.add('is-up');
        } else if (scaled < 0) {
          deltaEl.classList.add('is-down');
        }
      }
    } else if (deltaEl) {
      deltaEl.textContent = '--';
    }
    renderSparkline(sparkEl, series);
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

  function renderAlertSummary() {
    const errors = alertState.errors24h;
    const warnings = alertState.warnings24h;
    if (alertsErrorsEl) {
      alertsErrorsEl.textContent = formatCount(errors);
    }
    if (alertsWarningsEl) {
      alertsWarningsEl.textContent = formatCount(warnings);
    }
    updateKpiTile({
      valueEl: kpiErrorsValueEl,
      deltaEl: kpiErrorsDeltaEl,
      sparkEl: kpiErrorsSparkEl,
      series: kpiHistory.errors,
      value: typeof errors === 'number' ? errors : null,
      formatter: (val) => formatCount(val),
      deltaDigits: 0,
      deltaSuffix: ''
    });
    updateKpiTile({
      valueEl: kpiWarningsValueEl,
      deltaEl: kpiWarningsDeltaEl,
      sparkEl: kpiWarningsSparkEl,
      series: kpiHistory.warnings,
      value: typeof warnings === 'number' ? warnings : null,
      formatter: (val) => formatCount(val),
      deltaDigits: 0,
      deltaSuffix: ''
    });
    setDeltaText(alertsErrorsDeltaEl, getHistoryDelta(kpiHistory.errors), 0, '');
    setDeltaText(alertsWarningsDeltaEl, getHistoryDelta(kpiHistory.warnings), 0, '');
  }

  function renderAlertItems(items) {
    if (!alertsListEl) {
      return;
    }
    clearElement(alertsListEl);
    if (!Array.isArray(items) || items.length === 0) {
      const empty = document.createElement('li');
      empty.className = 'empty';
      empty.textContent = 'No alerts in the last window.';
      alertsListEl.appendChild(empty);
      setPanelEmptyState(alertsListEl, true, 'No alerts');
      if (alertsUpdatedEl) {
        alertsUpdatedEl.textContent = '--';
      }
      return;
    }
    setPanelEmptyState(alertsListEl, false);
    if (alertsUpdatedEl) {
      alertsUpdatedEl.textContent = formatShortTime(items[0].time);
    }
    const fragment = document.createDocumentFragment();
    items.forEach((item) => {
      const li = document.createElement('li');
      li.dataset.drilldown = item.type === 'syslog' ? '#syslog-intake' : '#event-logs';
      li.dataset.alertType = item.type;
      li.dataset.severity = item.severity || '';
      const header = document.createElement('div');
      header.className = 'alert-line';
      const time = document.createElement('span');
      time.className = 'alert-time';
      time.textContent = formatShortTime(item.time);
      const sev = document.createElement('span');
      sev.className = `chip ${severityChipClass(item.severity)}`;
      sev.textContent = item.severity;
      const source = document.createElement('span');
      source.className = 'alert-source';
      source.textContent = item.source;
      header.append(time, sev, source);
      const message = document.createElement('div');
      message.className = 'alert-message';
      message.textContent = truncateText(item.message || '', 160);
      li.append(header, message);
      fragment.appendChild(li);
    });
    alertsListEl.appendChild(fragment);
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

  function setPanelEmptyState(target, isEmpty, message) {
    const card = target && target.closest ? target.closest('.card') : target;
    if (!card) {
      return;
    }
    card.classList.toggle('is-empty', isEmpty);
    card.dataset.empty = isEmpty ? 'true' : 'false';
    const emptyEl = card.querySelector('.card__empty');
    if (emptyEl) {
      emptyEl.textContent = message || 'No data';
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

  function renderTableRows(tbody, rows, columns, renderRow) {
    if (!tbody) {
      return;
    }
    const maxRows = 200;
    let rendered = 0;
    const renderChunk = () => {
      const slice = rows.slice(rendered, rendered + maxRows);
      const fragment = document.createDocumentFragment();
      slice.forEach((row) => {
        fragment.appendChild(renderRow(row));
      });
      tbody.appendChild(fragment);
      rendered += slice.length;
      if (rendered < rows.length) {
        const tr = document.createElement('tr');
        tr.className = 'virtual-row';
        const td = document.createElement('td');
        td.colSpan = columns;
        const button = document.createElement('button');
        button.className = 'btn btn--outline btn--sm';
        button.type = 'button';
        const remaining = Math.min(maxRows, rows.length - rendered);
        button.textContent = `Load ${remaining} more (showing ${rendered} of ${rows.length})`;
        button.addEventListener('click', () => {
          tr.remove();
          renderChunk();
        });
        td.appendChild(button);
        tr.appendChild(td);
        tbody.appendChild(tr);
      }
    };
    renderChunk();
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

  function getSortType(tableId, key) {
    const table = document.getElementById(tableId);
    const header = table ? table.querySelector(`th[data-sort-key=\"${key}\"]`) : null;
    return header && header.dataset.sortType ? header.dataset.sortType : 'text';
  }

  function compareSortValues(a, b, type) {
    if (type === 'number') {
      const numA = Number(a);
      const numB = Number(b);
      if (Number.isNaN(numA) && Number.isNaN(numB)) {
        return 0;
      }
      if (Number.isNaN(numA)) {
        return 1;
      }
      if (Number.isNaN(numB)) {
        return -1;
      }
      return numA - numB;
    }
    const textA = (a ?? '').toString().toLowerCase();
    const textB = (b ?? '').toString().toLowerCase();
    if (textA < textB) {
      return -1;
    }
    if (textA > textB) {
      return 1;
    }
    return 0;
  }

  function getSortedRows(tableId, rows, defaultSort, valueGetter) {
    if (!Array.isArray(rows)) {
      return [];
    }
    const state = tableSortState[tableId] || {};
    const sortKey = state.key || (defaultSort ? defaultSort.key : null);
    const sortDir = state.dir || (defaultSort ? defaultSort.dir : 'asc');
    if (!sortKey) {
      return rows;
    }
    const sortType = getSortType(tableId, sortKey);
    const sorted = rows.slice().sort((a, b) => {
      const delta = compareSortValues(valueGetter(a, sortKey), valueGetter(b, sortKey), sortType);
      return sortDir === 'desc' ? -delta : delta;
    });
    updateSortIndicators(tableId, sortKey, sortDir);
    return sorted;
  }

  function updateSortIndicators(tableId, sortKey, sortDir) {
    const table = document.getElementById(tableId);
    if (!table) {
      return;
    }
    table.querySelectorAll('th[data-sort-key]').forEach((th) => {
      const key = th.dataset.sortKey;
      th.classList.toggle('is-sorted', key === sortKey);
      if (key === sortKey) {
        th.dataset.sortDir = sortDir;
      } else {
        delete th.dataset.sortDir;
      }
    });
  }

  function toggleSort(tableId, key) {
    const state = tableSortState[tableId] || {};
    const nextDir = state.key === key && state.dir === 'asc' ? 'desc' : 'asc';
    tableSortState[tableId] = { key, dir: nextDir };
    rerenderTable(tableId);
  }

  function rerenderTable(tableId) {
    const rows = lastTableRows[tableId] || [];
    switch (tableId) {
      case 'disk-table':
        renderDiskTable(rows);
        break;
      case 'process-table':
        renderProcessTable(rows);
        break;
      case 'wifi-table':
        renderWifiClients(rows);
        break;
      case 'device-table':
        renderDeviceSummary(rows);
        break;
      case 'syslog-table':
        renderSyslogRows(rows);
        break;
      case 'event-table':
        renderEventRows(rows);
        break;
      default:
        break;
    }
  }

  function initTableSorting() {
    document.querySelectorAll('table').forEach((table) => {
      const tableId = table.id;
      if (!tableId) {
        return;
      }
      table.querySelectorAll('th[data-sort-key]').forEach((th) => {
        th.addEventListener('click', () => {
          const key = th.dataset.sortKey;
          if (!key) {
            return;
          }
          toggleSort(tableId, key);
        });
      });
    });
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

  function setShowEmptyPanels(show) {
    document.body.dataset.showEmpty = show ? 'true' : 'false';
    if (emptyToggleEl) {
      emptyToggleEl.checked = show;
    }
    try {
      localStorage.setItem(EMPTY_TOGGLE_KEY, show ? 'true' : 'false');
    } catch {}
  }

  function initEmptyToggle() {
    if (!emptyToggleEl) {
      return;
    }
    let show = true;
    try {
      const stored = localStorage.getItem(EMPTY_TOGGLE_KEY);
      if (stored !== null) {
        show = stored === 'true';
      }
    } catch {}
    setShowEmptyPanels(show);
    emptyToggleEl.addEventListener('change', () => {
      setShowEmptyPanels(emptyToggleEl.checked);
    });
  }

  function initProcessControls() {
    if (processWindowSelect) {
      const initial = Number(processWindowSelect.value);
      if (Number.isFinite(initial) && initial > 0) {
        processState.windowSeconds = initial;
      }
      processWindowSelect.addEventListener('change', () => {
        const value = Number(processWindowSelect.value);
        if (Number.isFinite(value) && value > 0) {
          processState.windowSeconds = value;
        }
        renderProcessTable(lastTableRows['process-table'] || []);
      });
    }
    if (processFilterInput) {
      processFilterInput.addEventListener('input', () => {
        processState.filter = processFilterInput.value.trim();
        renderProcessTable(lastTableRows['process-table'] || []);
      });
    }
    if (processTabButtons.length) {
      processTabButtons.forEach((btn) => {
        btn.addEventListener('click', () => {
          const mode = btn.dataset.processMode;
          if (!mode) {
            return;
          }
          processState.mode = mode;
          processTabButtons.forEach((tab) => {
            tab.classList.toggle('is-active', tab === btn);
            tab.setAttribute('aria-selected', tab === btn ? 'true' : 'false');
          });
          delete tableSortState['process-table'];
          renderProcessTable(lastTableRows['process-table'] || []);
        });
      });
    }
  }

  function scrollToTarget(selector) {
    if (!selector) {
      return;
    }
    const target = document.querySelector(selector);
    if (!target) {
      return;
    }
    target.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  function initDrilldowns() {
    document.querySelectorAll('[data-drilldown]').forEach((el) => {
      el.addEventListener('click', (event) => {
        const target = el.dataset.drilldown;
        if (!target) {
          return;
        }
        event.preventDefault();
        scrollToTarget(target);
      });
    });
    if (alertsListEl) {
      alertsListEl.addEventListener('click', (event) => {
        const item = event.target.closest('li[data-drilldown]');
        if (!item) {
          return;
        }
        const target = item.dataset.drilldown;
        if (target) {
          scrollToTarget(target);
        }
        const severity = (item.dataset.severity || '').toLowerCase();
        if (item.dataset.alertType === 'syslog' && syslogSeveritySelect) {
          const sevValue = mapSyslogSeverity(severity);
          if (sevValue !== null) {
            syslogSeveritySelect.value = sevValue;
          }
          loadSyslogSummary();
          loadSyslogRows();
          loadSyslogTimeline();
        }
        if (item.dataset.alertType === 'event' && eventSeveritySelect) {
          const eventValue = mapEventSeverity(severity);
          if (eventValue) {
            eventSeveritySelect.value = eventValue;
          }
          loadEventSummary();
          loadEventRows();
          loadEventTimeline();
        }
      });
    }
    if (alertsViewAllBtn) {
      alertsViewAllBtn.addEventListener('click', () => {
        scrollToTarget('#event-logs');
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

  function showDetailDrawer(title, entries) {
    if (!detailDrawerEl || !detailBodyEl || !detailTitleEl) {
      return;
    }
    detailTitleEl.textContent = title || 'Details';
    detailBodyEl.innerHTML = '';
    const list = document.createElement('dl');
    list.className = 'detail-list';
    (entries || []).forEach(([label, value]) => {
      const dt = document.createElement('dt');
      dt.textContent = label;
      const dd = document.createElement('dd');
      dd.textContent = value != null ? value.toString() : '--';
      list.append(dt, dd);
    });
    detailBodyEl.appendChild(list);
    detailDrawerEl.classList.add('is-visible');
    detailDrawerEl.setAttribute('aria-hidden', 'false');
  }

  function hideDetailDrawer() {
    if (!detailDrawerEl) {
      return;
    }
    detailDrawerEl.classList.remove('is-visible');
    detailDrawerEl.setAttribute('aria-hidden', 'true');
  }

  function attachRowDetail(row, title, entries) {
    if (!row) {
      return;
    }
    row.classList.add('is-clickable');
    row.addEventListener('click', () => {
      showDetailDrawer(title, entries);
    });
  }

  function renderDiskTable(disks) {
    if (!diskTableBody) {
      return;
    }
    clearElement(diskTableBody);
    if (!Array.isArray(disks) || disks.length === 0) {
      setEmptyRow(diskTableBody, 7, 'No disk metrics reported.');
      setPanelEmptyState(diskTableBody, true, 'No disk metrics');
      return;
    }
    setPanelEmptyState(diskTableBody, false);
    const rows = disks.map((disk) => {
      const total = Number(disk.TotalGB) || 0;
      const used = Number(disk.UsedGB) || 0;
      const free = Math.max(0, total - used);
      const freePct = total > 0 ? free / total : 0;
      const usedPct = typeof disk.UsedPct === 'number' ? disk.UsedPct : Number(disk.UsedPct);
      const risk = usedPct >= DISK_CRITICAL_THRESHOLD
        ? 'critical'
        : usedPct >= DISK_WARN_THRESHOLD
          ? 'warn'
          : 'ok';
      return {
        drive: disk.Drive || '—',
        used,
        free,
        freePct,
        total,
        usedPct: Number.isFinite(usedPct) ? usedPct : 0,
        risk
      };
    });
    lastTableRows['disk-table'] = rows;
    const sorted = getSortedRows('disk-table', rows, { key: 'usedPct', dir: 'desc' }, (row, key) => row[key]);
    const fragment = document.createDocumentFragment();
    sorted.forEach((row) => {
      const tr = document.createElement('tr');
      const drive = document.createElement('td');
      drive.textContent = row.drive;
      const used = document.createElement('td');
      used.textContent = `${formatNumber(row.used, 1)} GB`;
      const free = document.createElement('td');
      free.textContent = `${formatNumber(row.free, 1)} GB`;
      const freePct = document.createElement('td');
      freePct.textContent = `${(row.freePct * 100).toFixed(1)}%`;
      const total = document.createElement('td');
      total.textContent = `${formatNumber(row.total, 1)} GB`;
      const pct = document.createElement('td');
      const pctValue = Math.min(100, Math.max(0, row.usedPct * 100));
      const pctLabel = document.createElement('div');
      pctLabel.textContent = `${pctValue.toFixed(1)}%`;
      const bar = document.createElement('div');
      bar.className = 'usage-bar';
      const fill = document.createElement('div');
      fill.className = 'usage-bar__fill';
      fill.style.width = `${pctValue.toFixed(1)}%`;
      bar.appendChild(fill);
      pct.append(pctLabel, bar);
      const risk = document.createElement('td');
      const riskPill = document.createElement('span');
      riskPill.className = `risk-pill risk-pill--${row.risk}`;
      riskPill.textContent = row.risk === 'critical' ? 'Critical' : row.risk === 'warn' ? 'Warn' : 'OK';
      risk.appendChild(riskPill);
      tr.append(drive, used, free, freePct, total, pct, risk);
      attachRowDetail(tr, `Disk ${row.drive}`, [
        ['Used', `${formatNumber(row.used, 1)} GB`],
        ['Free', `${formatNumber(row.free, 1)} GB`],
        ['Free %', `${(row.freePct * 100).toFixed(1)}%`],
        ['Total', `${formatNumber(row.total, 1)} GB`],
        ['Usage', `${pctValue.toFixed(1)}%`],
        ['Risk', riskPill.textContent]
      ]);
      fragment.appendChild(tr);
    });
    diskTableBody.appendChild(fragment);
  }

  function updateNetworkSummary(entries) {
    const now = Date.now();
    if (!Array.isArray(entries) || entries.length === 0) {
      if (networkAdapterSelect) {
        networkAdapterSelect.innerHTML = '';
      }
      if (networkInCurrentEl) {
        networkInCurrentEl.textContent = '--';
      }
      if (networkOutCurrentEl) {
        networkOutCurrentEl.textContent = '--';
      }
      if (networkInDeltaEl) {
        networkInDeltaEl.textContent = '--';
        networkInDeltaEl.classList.remove('is-up', 'is-down');
      }
      if (networkOutDeltaEl) {
        networkOutDeltaEl.textContent = '--';
        networkOutDeltaEl.classList.remove('is-up', 'is-down');
      }
      if (network95pDeltaEl) {
        network95pDeltaEl.textContent = '--';
        network95pDeltaEl.classList.remove('is-up', 'is-down');
      }
      if (network95pEl) {
        network95pEl.textContent = '--';
      }
      if (networkPeakEl) {
        networkPeakEl.textContent = '--';
      }
      if (kpiNetInValueEl) {
        kpiNetInValueEl.textContent = '--';
      }
      if (kpiNetOutValueEl) {
        kpiNetOutValueEl.textContent = '--';
      }
      if (kpiNet95pValueEl) {
        kpiNet95pValueEl.textContent = '--';
      }
      if (kpiNetInDeltaEl) {
        kpiNetInDeltaEl.textContent = '--';
        kpiNetInDeltaEl.classList.remove('is-up', 'is-down');
      }
      if (kpiNetOutDeltaEl) {
        kpiNetOutDeltaEl.textContent = '--';
        kpiNetOutDeltaEl.classList.remove('is-up', 'is-down');
      }
      if (kpiNet95pDeltaEl) {
        kpiNet95pDeltaEl.textContent = '--';
        kpiNet95pDeltaEl.classList.remove('is-up', 'is-down');
      }
      renderSparkline(kpiNetInSparkEl, []);
      renderSparkline(kpiNetOutSparkEl, []);
      renderSparkline(kpiNet95pSparkEl, []);
      setPanelEmptyState(networkSparkEl || networkAdapterSelect, true, 'No active adapters');
      return;
    }
    const total = entries.reduce((acc, entry) => {
      acc.in += Number(entry.BytesRecvPerSec) || 0;
      acc.out += Number(entry.BytesSentPerSec) || 0;
      return acc;
    }, { in: 0, out: 0 });
    const adapters = entries.map((entry) => entry.Adapter).filter(Boolean);
    const options = adapters.length > 1 ? ['All adapters', ...adapters] : adapters;
    if (networkAdapterSelect) {
      const current = networkAdapterSelect.value;
      networkAdapterSelect.innerHTML = '';
      options.forEach((name, idx) => {
        const option = document.createElement('option');
        option.value = idx === 0 && adapters.length > 1 ? '__all__' : name;
        option.textContent = name;
        networkAdapterSelect.appendChild(option);
      });
      if (current && Array.from(networkAdapterSelect.options).some((opt) => opt.value === current)) {
        networkAdapterSelect.value = current;
      }
    }

    const selected = networkAdapterSelect ? networkAdapterSelect.value : '__all__';
    entries.forEach((entry) => {
      const name = entry.Adapter || 'unknown';
      pushNetworkHistory(name, Number(entry.BytesRecvPerSec) || 0, Number(entry.BytesSentPerSec) || 0, now);
    });
    pushNetworkHistory('__all__', total.in, total.out, now);

    const history = networkHistory.get(selected || '__all__') || [];
    const latest = history.length ? history[history.length - 1] : { in: 0, out: 0 };
    const prev = history.length > 1 ? history[history.length - 2] : null;
    const deltaIn = prev ? latest.in - prev.in : null;
    const deltaOut = prev ? latest.out - prev.out : null;

    const valuesIn = history.map((entry) => entry.in).filter((val) => typeof val === 'number');
    const valuesOut = history.map((entry) => entry.out).filter((val) => typeof val === 'number');
    const in95 = percentile(valuesIn, 0.95);
    const out95 = percentile(valuesOut, 0.95);
    const peak = Math.max(...valuesIn, ...valuesOut, 0);

    if (networkInCurrentEl) {
      networkInCurrentEl.textContent = formatBytesPerSec(latest.in);
    }
    if (networkOutCurrentEl) {
      networkOutCurrentEl.textContent = formatBytesPerSec(latest.out);
    }
    if (networkInDeltaEl) {
      networkInDeltaEl.textContent = formatBytesDelta(deltaIn);
      networkInDeltaEl.classList.toggle('is-up', deltaIn > 0);
      networkInDeltaEl.classList.toggle('is-down', deltaIn < 0);
    }
    if (networkOutDeltaEl) {
      networkOutDeltaEl.textContent = formatBytesDelta(deltaOut);
      networkOutDeltaEl.classList.toggle('is-up', deltaOut > 0);
      networkOutDeltaEl.classList.toggle('is-down', deltaOut < 0);
    }
    if (network95pEl) {
      network95pEl.textContent = `${formatBytesPerSec(in95)} / ${formatBytesPerSec(out95)}`;
    }
    const net95Total = (Number.isFinite(in95) ? in95 : 0) + (Number.isFinite(out95) ? out95 : 0);
    updateKpiTile({
      valueEl: kpiNet95pValueEl,
      deltaEl: kpiNet95pDeltaEl,
      sparkEl: kpiNet95pSparkEl,
      series: kpiHistory.net95p,
      value: net95Total,
      formatter: () => `${formatBytesPerSec(in95)} / ${formatBytesPerSec(out95)}`,
      deltaFormatter: formatBytesDelta
    });
    const net95Delta = getHistoryDelta(kpiHistory.net95p);
    if (network95pDeltaEl) {
      network95pDeltaEl.textContent = formatBytesDelta(net95Delta);
      network95pDeltaEl.classList.toggle('is-up', net95Delta > 0);
      network95pDeltaEl.classList.toggle('is-down', net95Delta < 0);
    }
    if (networkPeakEl) {
      networkPeakEl.textContent = formatBytesPerSec(peak);
    }
    if (networkUpdatedEl) {
      networkUpdatedEl.textContent = `Updated ${formatShortTime(now)}`;
    }
    const netSeries = history.map((entry) => ({ t: entry.t, v: entry.in + entry.out }));
    renderSparkline(networkSparkEl, netSeries);
    updateKpiTile({
      valueEl: kpiNetInValueEl,
      deltaEl: kpiNetInDeltaEl,
      sparkEl: kpiNetInSparkEl,
      series: kpiHistory.netIn,
      value: latest.in,
      formatter: formatBytesPerSec,
      deltaFormatter: formatBytesDelta
    });
    updateKpiTile({
      valueEl: kpiNetOutValueEl,
      deltaEl: kpiNetOutDeltaEl,
      sparkEl: kpiNetOutSparkEl,
      series: kpiHistory.netOut,
      value: latest.out,
      formatter: formatBytesPerSec,
      deltaFormatter: formatBytesDelta
    });
    setPanelEmptyState(networkSparkEl || networkAdapterSelect, false);
  }

  function pushNetworkHistory(key, inValue, outValue, timestamp) {
    const series = networkHistory.get(key) || [];
    series.push({ t: timestamp, in: inValue, out: outValue });
    const trimmed = series.filter((entry) => entry.t >= Date.now() - HISTORY_WINDOW_MINUTES * 60 * 1000);
    networkHistory.set(key, trimmed);
  }

  function percentile(values, pct) {
    if (!Array.isArray(values) || values.length === 0) {
      return 0;
    }
    const sorted = values.slice().sort((a, b) => a - b);
    const index = Math.max(0, Math.min(sorted.length - 1, Math.floor(sorted.length * pct) - 1));
    return sorted[index] || 0;
  }

  function renderProcessTable(processes) {
    if (!processTableBody) {
      return;
    }
    clearElement(processTableBody);
    if (!Array.isArray(processes) || processes.length === 0) {
      setEmptyRow(processTableBody, 7, 'No process data returned.');
      setPanelEmptyState(processTableBody, true, 'No process data');
      return;
    }
    setPanelEmptyState(processTableBody, false);
    lastTableRows['process-table'] = processes;
    const rows = buildProcessRows(processes);
    const sorted = getSortedRows(
      'process-table',
      rows,
      { key: processState.mode === 'ram' ? 'workingSet' : processState.mode === 'io' ? 'io' : 'cpu', dir: 'desc' },
      (row, key) => row[key]
    );
    const fragment = document.createDocumentFragment();
    sorted.slice(0, PROCESS_MAX_ROWS).forEach((row) => {
      const tr = document.createElement('tr');
      const name = document.createElement('td');
      name.textContent = row.name || '—';
      const cpu = document.createElement('td');
      cpu.innerHTML = `${formatNumber(row.cpu, 2)}<div class=\"usage-bar\"><div class=\"usage-bar__fill\" style=\"width:${row.heat.toFixed(1)}%\"></div></div>`;
      const cpuPct = document.createElement('td');
      cpuPct.textContent = row.cpuPct != null ? `${row.cpuPct.toFixed(1)}%` : '--';
      const workingSet = document.createElement('td');
      workingSet.textContent = row.workingSet != null ? `${row.workingSet.toFixed(1)} MB` : '--';
      const privateBytes = document.createElement('td');
      privateBytes.textContent = row.privateBytes != null ? `${row.privateBytes.toFixed(1)} MB` : '--';
      const io = document.createElement('td');
      io.textContent = row.io != null ? `${row.io.toFixed(1)} MB` : '--';
      const pid = document.createElement('td');
      pid.textContent = row.pid != null ? row.pid.toString() : '—';
      tr.append(name, cpu, cpuPct, workingSet, privateBytes, io, pid);
      attachRowDetail(tr, `Process ${row.name || row.pid}`, [
        ['CPU (s)', row.cpu != null ? row.cpu.toFixed(2) : '--'],
        ['CPU %', row.cpuPct != null ? `${row.cpuPct.toFixed(1)}%` : '--'],
        ['Working Set', row.workingSet != null ? `${row.workingSet.toFixed(1)} MB` : '--'],
        ['Private MB', row.privateBytes != null ? `${row.privateBytes.toFixed(1)} MB` : '--'],
        ['IO MB', row.io != null ? `${row.io.toFixed(1)} MB` : '--'],
        ['PID', row.pid != null ? row.pid.toString() : '--']
      ]);
      fragment.appendChild(tr);
    });
    processTableBody.appendChild(fragment);
    if (processUpdatedEl && lastMetricsAt) {
      processUpdatedEl.textContent = `Updated ${formatShortTime(lastMetricsAt)}`;
    }
  }

  function buildProcessRows(processes) {
    const now = Date.now();
    const windowSeconds = processState.windowSeconds;
    const cores = navigator.hardwareConcurrency || 1;
    const filter = processState.filter ? processState.filter.toLowerCase() : '';
    const rows = [];
    processes.forEach((proc) => {
      const id = proc.Id ?? proc.id;
      const name = proc.Name || proc.name;
      if (filter && name && !name.toLowerCase().includes(filter)) {
        return;
      }
      const history = processHistory.get(id);
      const latest = history && history.samples.length ? history.samples[history.samples.length - 1] : null;
      const baseline = history ? findBaselineSample(history.samples, now - windowSeconds * 1000) : null;
      const cpuNow = latest?.cpu ?? Number(proc.CPU) ?? null;
      const cpuBase = baseline?.cpu ?? cpuNow ?? 0;
      const cpuDelta = cpuNow != null ? Math.max(0, cpuNow - cpuBase) : null;
      const cpuPct = cpuDelta != null && windowSeconds > 0 ? (cpuDelta / windowSeconds) * (100 / cores) : null;
      const workingSet = toMb(latest?.workingSet ?? proc.WorkingSet64 ?? proc.WorkingSet);
      const privateBytes = toMb(latest?.privateBytes ?? proc.PrivateMemorySize64 ?? proc.PrivateMemory);
      const ioNow = latest?.ioRead != null || latest?.ioWrite != null
        ? (Number(latest?.ioRead) || 0) + (Number(latest?.ioWrite) || 0)
        : (Number(proc.IOReadBytes) || 0) + (Number(proc.IOWriteBytes) || 0);
      const ioBase = baseline ? (Number(baseline.ioRead) || 0) + (Number(baseline.ioWrite) || 0) : ioNow;
      const ioDelta = ioNow != null ? Math.max(0, ioNow - ioBase) / 1024 / 1024 : null;
      rows.push({
        name,
        pid: id,
        cpu: cpuDelta,
        cpuPct,
        workingSet,
        privateBytes,
        io: ioDelta,
        heat: 0
      });
    });
    const maxCpu = rows.reduce((max, row) => Math.max(max, row.cpu || 0), 1);
    rows.forEach((row) => {
      row.heat = row.cpu != null ? Math.min(100, (row.cpu / maxCpu) * 100) : 0;
    });
    return rows;
  }

  function updateProcessHistory(processes, timestamp) {
    if (!Array.isArray(processes)) {
      return;
    }
    const now = timestamp || Date.now();
    processes.forEach((proc) => {
      const id = proc.Id ?? proc.id;
      if (id == null) {
        return;
      }
      const entry = processHistory.get(id) || { name: proc.Name || proc.name, samples: [] };
      entry.name = proc.Name || proc.name || entry.name;
      entry.samples.push({
        t: now,
        cpu: Number(proc.CPU) || 0,
        workingSet: Number(proc.WorkingSet64 ?? proc.WorkingSet) || null,
        privateBytes: Number(proc.PrivateMemorySize64 ?? proc.PrivateMemory) || null,
        ioRead: Number(proc.IOReadBytes) || 0,
        ioWrite: Number(proc.IOWriteBytes) || 0
      });
      entry.samples = entry.samples.filter((sample) => sample.t >= now - Math.max(processState.windowSeconds, 900) * 1000);
      processHistory.set(id, entry);
    });
  }

  function findBaselineSample(samples, cutoff) {
    if (!Array.isArray(samples) || samples.length === 0) {
      return null;
    }
    for (let i = samples.length - 1; i >= 0; i -= 1) {
      if (samples[i].t <= cutoff) {
        return samples[i];
      }
    }
    return samples[0];
  }

  function toMb(value) {
    const numeric = Number(value);
    if (!Number.isFinite(numeric)) {
      return null;
    }
    return numeric / 1024 / 1024;
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

  function mapSyslogSeverity(label) {
    if (label == null) {
      return null;
    }
    const value = label.toString().toLowerCase();
    if (/^\\d+$/.test(value)) {
      return value;
    }
    if (value.includes('emerg')) {
      return '0';
    }
    if (value.includes('alert')) {
      return '1';
    }
    if (value.includes('crit')) {
      return '2';
    }
    if (value.includes('error')) {
      return '3';
    }
    if (value.includes('warn')) {
      return '4';
    }
    if (value.includes('notice')) {
      return '5';
    }
    if (value.includes('info')) {
      return '6';
    }
    if (value.includes('debug')) {
      return '7';
    }
    return null;
  }

  function mapEventSeverity(label) {
    if (!label) {
      return null;
    }
    const value = label.toString().toLowerCase();
    if (value.includes('critical')) {
      return 'critical';
    }
    if (value.includes('error')) {
      return 'error';
    }
    if (value.includes('warn')) {
      return 'warning';
    }
    if (value.includes('info')) {
      return 'information';
    }
    return null;
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
    const totalCount = (Number(summary.total1h) || 0) + (Number(summary.total24h) || 0);
    if (syslogTableBody) {
      setPanelEmptyState(syslogTableBody, totalCount === 0, 'No syslog activity');
    }
  }

  function renderSyslogRows(rows) {
    if (!syslogTableBody) {
      return;
    }
    clearElement(syslogTableBody);
    if (!Array.isArray(rows) || rows.length === 0) {
      setEmptyRow(syslogTableBody, 6, 'No syslog rows yet.');
      setPanelEmptyState(syslogTableBody, true, 'No syslog rows');
      return;
    }
    setPanelEmptyState(syslogTableBody, false);
    lastTableRows['syslog-table'] = rows;
    const sorted = getSortedRows('syslog-table', rows, { key: 'time', dir: 'desc' }, (row, key) => {
      switch (key) {
        case 'time':
          return row.received_utc;
        case 'host':
          return row.source_host;
        case 'app':
          return row.app_name;
        case 'severity':
          return row.severity_label || row.severity;
        case 'category':
          return row.category;
        case 'message':
          return row.message;
        default:
          return row[key];
      }
    });
    const renderRow = (row) => {
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
      attachRowDetail(tr, `Syslog ${row.source_host || row.app_name || ''}`.trim(), [
        ['Time', time.textContent],
        ['Host', row.source_host || '--'],
        ['App', row.app_name || '--'],
        ['Severity', sevLabel || '--'],
        ['Category', catValue || '--'],
        ['Message', row.message || '--']
      ]);
      return tr;
    };
    if (sorted.length > 200) {
      renderTableRows(syslogTableBody, sorted, 6, renderRow);
    } else {
      const fragment = document.createDocumentFragment();
      sorted.forEach((row) => {
        fragment.appendChild(renderRow(row));
      });
      syslogTableBody.appendChild(fragment);
    }
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
      if (syslogTableBody) {
        setPanelEmptyState(syslogTableBody, true, 'Syslog unavailable');
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
      setPanelEmptyState(syslogTableBody, true, 'Failed to load syslog');
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
    const totalCount = (Number(summary.total1h) || 0) + (Number(summary.total24h) || 0);
    if (eventTableBody) {
      setPanelEmptyState(eventTableBody, totalCount === 0, 'No event activity');
    }
  }

  function renderEventRows(rows) {
    if (!eventTableBody) {
      return;
    }
    clearElement(eventTableBody);
    if (!Array.isArray(rows) || rows.length === 0) {
      setEmptyRow(eventTableBody, 6, 'No events yet.');
      setPanelEmptyState(eventTableBody, true, 'No event rows');
      return;
    }
    setPanelEmptyState(eventTableBody, false);
    lastTableRows['event-table'] = rows;
    const sorted = getSortedRows('event-table', rows, { key: 'time', dir: 'desc' }, (row, key) => {
      switch (key) {
        case 'time':
          return row.occurred_at;
        case 'source':
          return row.source;
        case 'severity':
          return row.severity;
        case 'category':
          return row.category;
        case 'provider':
          return row.subject;
        case 'message':
          return row.message;
        default:
          return row[key];
      }
    });
    const renderRow = (row) => {
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
      attachRowDetail(tr, `Event ${row.source || row.subject || ''}`.trim(), [
        ['Time', time.textContent],
        ['Source', row.source || '--'],
        ['Severity', sevLabel || '--'],
        ['Category', catValue || '--'],
        ['Provider', row.subject || '--'],
        ['Message', row.message || '--']
      ]);
      return tr;
    };
    if (sorted.length > 200) {
      renderTableRows(eventTableBody, sorted, 6, renderRow);
    } else {
      const fragment = document.createDocumentFragment();
      sorted.forEach((row) => {
        fragment.appendChild(renderRow(row));
      });
      eventTableBody.appendChild(fragment);
    }
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
    if (timelineChartEl) {
      const isEmpty = !Array.isArray(data) || data.length === 0;
      setPanelEmptyState(timelineChartEl, isEmpty, 'No timeline activity');
    }
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
      setPanelEmptyState(deviceTableBody, true, 'No device activity');
      return;
    }
    setPanelEmptyState(deviceTableBody, false);
    lastTableRows['device-table'] = rows;
    const sorted = getSortedRows('device-table', rows, { key: 'events_1h', dir: 'desc' }, (row, key) => {
      switch (key) {
        case 'mac':
          return row.mac_address;
        case 'lastSeen':
          return row.last_seen;
        case 'events':
          return row.events_1h;
        case 'rssi':
          return row.last_rssi;
        case 'event':
          return row.last_event_type;
        default:
          return row[key];
      }
    });
    const fragment = document.createDocumentFragment();
    sorted.forEach((row) => {
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
      attachRowDetail(tr, `Device ${row.mac_address || 'unknown'}`, [
        ['Last seen', formatShortTime(row.last_seen)],
        ['Events (1h)', row.events_1h != null ? row.events_1h.toString() : '--'],
        ['RSSI', row.last_rssi != null ? row.last_rssi.toString() : '--'],
        ['Last event', row.last_event_type || '--']
      ]);
      fragment.appendChild(tr);
    });
    deviceTableBody.appendChild(fragment);
    if (deviceCountEl) {
      deviceCountEl.textContent = rows.length.toString();
    }
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
      setPanelEmptyState(wifiTableBody, true, 'No Wi-Fi clients');
      return;
    }
    setPanelEmptyState(wifiTableBody, false);
    lastTableRows['wifi-table'] = rows;
    const sorted = getSortedRows('wifi-table', rows, { key: 'rssi', dir: 'desc' }, (row, key) => {
      switch (key) {
        case 'client':
          return row.nickname || row.hostname || row.mac_address;
        case 'ip':
          return row.current_ip || row.ip_address;
        case 'band':
          return row.current_interface || row.interface;
        case 'rssi':
          return row.current_rssi;
        case 'rates':
          return (Number(row.tx_rate_mbps) || 0) + (Number(row.rx_rate_mbps) || 0);
        case 'lastSeen':
          return row.last_seen_utc || row.last_snapshot_time || row.sample_time_utc;
        default:
          return row[key];
      }
    });
    const fragment = document.createDocumentFragment();
    sorted.forEach((row) => {
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
      attachRowDetail(tr, `Wi-Fi client ${row.nickname || row.hostname || row.mac_address || 'unknown'}`, [
        ['IP', row.current_ip || row.ip_address || '--'],
        ['Band', formatBandLabel(row.current_interface || row.interface)],
        ['RSSI', formatRssiValue(row.current_rssi)],
        ['Tx/Rx', rates.textContent],
        ['Last seen', lastSeen.textContent]
      ]);
      fragment.appendChild(tr);
    });
    wifiTableBody.appendChild(fragment);
    if (wifiClientCountEl) {
      wifiClientCountEl.textContent = rows.length.toString();
    }
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
      setPanelEmptyState(timelineChartEl, true, 'Timeline unavailable');
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
      setPanelEmptyState(deviceTableBody, true, 'Failed to load devices');
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
      setPanelEmptyState(wifiTableBody, true, 'Failed to load Wi-Fi clients');
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
      if (eventTableBody) {
        setPanelEmptyState(eventTableBody, true, 'Events unavailable');
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
      setPanelEmptyState(eventTableBody, true, 'Failed to load events');
    }
  }

  async function loadAlertSummary(force = false) {
    const now = Date.now();
    if (!force && now - lastOverviewRefresh < OVERVIEW_REFRESH_INTERVAL) {
      return;
    }
    lastOverviewRefresh = now;
    const range = getLastHoursRange(24);
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

    const [syslogResult, eventResult] = await Promise.allSettled([
      fetchJson(`${SYSLOG_SUMMARY_ENDPOINT}?${syslogParams.toString()}`, { cache: 'no-store' }),
      fetchJson(`${EVENTS_SUMMARY_ENDPOINT}?${eventParams.toString()}`, { cache: 'no-store' })
    ]);

    let errors = null;
    let warnings = null;
    if (syslogResult.status === 'fulfilled') {
      const syslog = syslogResult.value;
      const syslogTotals = computeSyslogSeverityTotals(syslog);
      const eventTotals = eventResult.status === 'fulfilled'
        ? computeEventSeverityTotals(eventResult.value)
        : { error: 0, warn: 0 };
      errors = syslogTotals.error + eventTotals.error;
      warnings = syslogTotals.warn + eventTotals.warn;
    } else if (eventResult.status === 'fulfilled') {
      const eventTotals = computeEventSeverityTotals(eventResult.value);
      errors = eventTotals.error;
      warnings = eventTotals.warn;
    }

    alertState.errors24h = errors;
    alertState.warnings24h = warnings;
    renderAlertSummary();
  }

  async function loadAlertItems() {
    if (!alertsListEl) {
      return;
    }
    clearElement(alertsListEl);
    const loading = document.createElement('li');
    loading.className = 'empty';
    loading.textContent = 'Loading alerts…';
    alertsListEl.appendChild(loading);
    const params = new URLSearchParams();
    params.set('limit', '3');
    params.set('offset', '0');
    try {
      const [syslogRows, eventRows] = await Promise.all([
        fetchJson(`${SYSLOG_RECENT_ENDPOINT}?${params.toString()}`, { cache: 'no-store' }),
        fetchJson(`${EVENTS_RECENT_ENDPOINT}?${params.toString()}`, { cache: 'no-store' })
      ]);
      const items = [];
      (Array.isArray(syslogRows) ? syslogRows : []).forEach((row) => {
        items.push({
          type: 'syslog',
          time: row.received_utc,
          severity: row.severity_label || row.severity || 'unknown',
          source: row.source_host || row.app_name || 'syslog',
          message: row.message || ''
        });
      });
      (Array.isArray(eventRows) ? eventRows : []).forEach((row) => {
        items.push({
          type: 'event',
          time: row.occurred_at,
          severity: row.severity || 'unknown',
          source: row.source || row.subject || 'event',
          message: row.message || ''
        });
      });
      items.sort((a, b) => new Date(b.time || 0) - new Date(a.time || 0));
      renderAlertItems(items.slice(0, 3));
    } catch (err) {
      clearElement(alertsListEl);
      const empty = document.createElement('li');
      empty.className = 'empty';
      empty.textContent = 'Failed to load alerts.';
      alertsListEl.appendChild(empty);
      setPanelEmptyState(alertsListEl, true, 'No alerts available');
    }
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
      const hasData = Object.values(kpis || {}).some((value) => typeof value === 'number');
      setPanelEmptyState(routerKpiUpdatedEl || routerKpiTotalDropEl, !hasData, 'No router KPIs');
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
      setPanelEmptyState(routerKpiUpdatedEl || routerKpiTotalDropEl, true, 'Router KPIs unavailable');
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
    if (refreshToggleBtn) {
      refreshToggleBtn.textContent = paused ? 'Resume' : 'Pause';
      refreshToggleBtn.title = paused ? 'Resume auto-refresh' : 'Pause auto-refresh';
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
      loadAlertSummary(force),
      loadAlertItems(),
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
    const now = Date.now();
    if (hostNameEl) {
      hostNameEl.textContent = data.ComputerName || data.Host || 'Unknown host';
    }
    if (uptimeEl) {
      uptimeEl.textContent = formatUptime(data.Uptime);
    }
    if (latencyEl) {
      latencyEl.textContent = formatLatency(data?.Network?.LatencyMs);
    }
    if (latencyTargetEl) {
      const target = data?.Network?.LatencyTarget;
      latencyTargetEl.textContent = target ? target : 'configured target';
    }
    const cpuPct = typeof data?.CPU?.Pct === 'number' ? data.CPU.Pct : null;
    updateKpiTile({
      valueEl: kpiCpuValueEl,
      deltaEl: kpiCpuDeltaEl,
      sparkEl: kpiCpuSparkEl,
      series: kpiHistory.cpu,
      value: cpuPct,
      formatter: (val) => formatPercent(val, { scaleTo100: false, digits: 1 }),
      deltaDigits: 1,
      deltaSuffix: '%'
    });
    const memPct = typeof data?.Memory?.Pct === 'number' ? data.Memory.Pct : null;
    updateKpiTile({
      valueEl: kpiRamValueEl,
      deltaEl: kpiRamDeltaEl,
      sparkEl: kpiRamSparkEl,
      series: kpiHistory.ram,
      value: memPct,
      formatter: (val) => formatPercent(val, { digits: 1 }),
      deltaDigits: 1,
      deltaSuffix: '%',
      deltaMultiplier: 100
    });
    const disks = Array.isArray(data.Disk) ? data.Disk : [];
    renderDiskTable(disks);
    let diskWorstPct = null;
    let diskFreeC = null;
    disks.forEach((disk) => {
      const pct = typeof disk.UsedPct === 'number' ? disk.UsedPct : Number(disk.UsedPct);
      if (Number.isFinite(pct)) {
        if (diskWorstPct == null || pct > diskWorstPct) {
          diskWorstPct = pct;
        }
      }
      const drive = (disk.Drive || '').toString().toUpperCase();
      if (drive === 'C') {
        const total = Number(disk.TotalGB) || 0;
        const used = Number(disk.UsedGB) || 0;
        diskFreeC = Math.max(0, total - used);
      }
    });
    updateKpiTile({
      valueEl: kpiDiskWorstValueEl,
      deltaEl: kpiDiskWorstDeltaEl,
      sparkEl: kpiDiskWorstSparkEl,
      series: kpiHistory.diskWorst,
      value: diskWorstPct,
      formatter: (val) => formatPercent(val, { digits: 1 }),
      deltaDigits: 1,
      deltaSuffix: '%',
      deltaMultiplier: 100
    });
    updateKpiTile({
      valueEl: kpiDiskFreeValueEl,
      deltaEl: kpiDiskFreeDeltaEl,
      sparkEl: kpiDiskFreeSparkEl,
      series: kpiHistory.diskFree,
      value: diskFreeC,
      formatter: (val) => (typeof val === 'number' && isFinite(val) ? `${val.toFixed(1)} GB` : '--'),
      deltaDigits: 1,
      deltaSuffix: ' GB'
    });
    const networkEntries = Array.isArray(data?.Network?.Usage) ? data.Network.Usage : [];
    lastNetworkEntries = networkEntries;
    updateNetworkSummary(networkEntries);
    updateProcessHistory(Array.isArray(data?.Processes) ? data.Processes : [], now);
    renderProcessTable(Array.isArray(data?.Processes) ? data.Processes : []);
    if (healthUpdatedEl) {
      healthUpdatedEl.textContent = `Updated ${formatShortTime(now)}`;
    }
    if (refreshTimestampEl) {
      refreshTimestampEl.textContent = `Last refresh ${formatShortTime(now)}`;
    }
    lastMetricsAt = now;
    const timestamp = data.Time ? formatTimestamp(data.Time) : formatTimestamp(now);
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
      loadAlertSummary(true);
      loadAlertItems();
    });
  }
  if (eventRefreshBtn) {
    eventRefreshBtn.addEventListener('click', () => {
      eventPage = 1;
      loadEventSummary();
      loadEventRows();
      loadEventTimeline();
      loadAlertSummary(true);
      loadAlertItems();
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
  if (refreshToggleBtn) {
    refreshToggleBtn.addEventListener('click', () => {
      setAutoRefreshPaused(!autoRefreshPaused);
      if (!autoRefreshPaused) {
        loadMetrics(true);
        loadTelemetry(true);
      }
    });
  }
  if (networkAdapterSelect) {
    networkAdapterSelect.addEventListener('change', () => {
      updateNetworkSummary(lastNetworkEntries);
    });
  }
  if (detailCloseBtn) {
    detailCloseBtn.addEventListener('click', () => {
      hideDetailDrawer();
    });
  }
  if (detailDrawerEl) {
    detailDrawerEl.addEventListener('click', (event) => {
      if (event.target === detailDrawerEl) {
        hideDetailDrawer();
      }
    });
  }

  initCardHandles();
  initDragAndResize();
  initLayoutControls();
  initEmptyToggle();
  initProcessControls();
  initDrilldowns();
  initTableSorting();
  loadLayoutStore();

  renderTimelineLegend();
  renderSyslogTimelineLegend();
  renderEventTimelineLegend();
  if (healthWindowLabelEl) {
    healthWindowLabelEl.textContent = 'Window: 60m';
  }
})();

'use strict';

(() => {
  const REFRESH_INTERVAL = 5000;
  const METRICS_ENDPOINT = 'metrics';
  const SYSLOG_SUMMARY_ENDPOINT = '/api/syslog/summary';
  const SYSLOG_RECENT_ENDPOINT = '/api/syslog/recent';
  const EVENTS_SUMMARY_ENDPOINT = '/api/events/summary';
  const EVENTS_RECENT_ENDPOINT = '/api/events/recent';
  const TIMELINE_ENDPOINT = '/api/timeline';
  const DEVICES_SUMMARY_ENDPOINT = '/api/devices/summary';
  const ROUTER_KPI_ENDPOINT = '/api/router/kpis';
  const HEALTH_ENDPOINT = '/api/health';
  const TELEMETRY_REFRESH_INTERVAL = 15000;

  const statusEl = document.getElementById('connection-status');
  const statusDetailEl = document.getElementById('status-detail');
  const hostNameEl = document.getElementById('host-name');
  const uptimeEl = document.getElementById('uptime-value');
  const cpuValueEl = document.getElementById('cpu-value');
  const memoryValueEl = document.getElementById('memory-value');
  const memoryDetailEl = document.getElementById('memory-detail');
  const latencyEl = document.getElementById('latency-value');
  const diskTableBody = document.querySelector('#disk-table tbody');
  const networkTableBody = document.querySelector('#network-table tbody');
  const processTableBody = document.querySelector('#process-table tbody');
  const warningListEl = document.getElementById('warning-list');
  const warningTotalEl = document.getElementById('warning-total');
  const errorListEl = document.getElementById('error-list');
  const errorTotalEl = document.getElementById('error-total');
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
  const syslogRefreshBtn = document.getElementById('syslog-refresh');
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
  const eventRefreshBtn = document.getElementById('event-refresh');
  const timelineChartEl = document.getElementById('timeline-chart');
  const timelineLegendEl = document.getElementById('timeline-legend');
  const timelineMacInput = document.getElementById('timeline-mac');
  const timelineCategorySelect = document.getElementById('timeline-category');
  const timelineEventTypeSelect = document.getElementById('timeline-event-type');
  const timelineRefreshBtn = document.getElementById('timeline-refresh');
  const devicesRefreshBtn = document.getElementById('devices-refresh');
  const deviceTableBody = document.querySelector('#device-table tbody');
  const refreshStatusEl = document.getElementById('refresh-status');
  const refreshResumeBtn = document.getElementById('refresh-resume');
  const healthBannerEl = document.getElementById('health-banner');
  const healthBannerTextEl = document.getElementById('health-banner-text');
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
    if (typeof value !== 'number' || !isFinite(value)) {
      return '--';
    }
    const percent = (value <= 1 && settings.scaleTo100) ? value * 100 : value;
    return `${percent.toFixed(settings.digits)}%`;
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

  async function fetchJson(url, options) {
    const res = await fetch(url, options);
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
  }

  function renderNetworkTable(entries) {
    if (!networkTableBody) {
      return;
    }
    clearElement(networkTableBody);
    if (!Array.isArray(entries) || entries.length === 0) {
      setEmptyRow(networkTableBody, 3, 'No active adapters detected.');
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
        const sev = Number(entry.severity);
        const count = Number(entry.total) || 0;
        if (!Number.isNaN(sev)) {
          if (sev <= 3) {
            errorTotal += count;
          } else if (sev === 4) {
            warnTotal += count;
          } else {
            infoTotal += count;
          }
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
      const res = await fetch(`${SYSLOG_SUMMARY_ENDPOINT}?_=${Date.now()}`, { cache: 'no-store' });
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
    params.set('limit', '50');
    try {
      const res = await fetch(`${SYSLOG_RECENT_ENDPOINT}?${params.toString()}`, { cache: 'no-store' });
      if (!res.ok) {
        throw new Error(`HTTP ${res.status}`);
      }
      const data = await res.json();
      renderSyslogRows(data);
    } catch (err) {
      clearElement(syslogTableBody);
      setEmptyRow(syslogTableBody, 6, 'Failed to load syslog.');
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

  function renderTimelineLegend() {
    if (!timelineLegendEl) {
      return;
    }
    timelineLegendEl.innerHTML = TIMELINE_CATEGORIES.map((cat) => {
      return `<span class="legend-item"><span class="legend-dot ${cat}"></span>${cat}</span>`;
    }).join('');
  }

  function renderTimeline(data) {
    if (!timelineChartEl) {
      return;
    }
    clearElement(timelineChartEl);
    if (!Array.isArray(data) || data.length === 0) {
      const empty = document.createElement('div');
      empty.className = 'timeline-empty';
      empty.textContent = 'No activity in this window.';
      timelineChartEl.appendChild(empty);
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
      TIMELINE_CATEGORIES.forEach((cat) => {
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
    timelineChartEl.appendChild(fragment);
  }

  function renderDeviceSummary(rows) {
    if (!deviceTableBody) {
      return;
    }
    clearElement(deviceTableBody);
    if (!Array.isArray(rows) || rows.length === 0) {
      setEmptyRow(deviceTableBody, 5, 'No device activity yet.');
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

  async function loadEventSummary() {
    if (!eventsTotal24hEl && !eventsTotal1hEl) {
      return;
    }
    try {
      const res = await fetch(`${EVENTS_SUMMARY_ENDPOINT}?_=${Date.now()}`, { cache: 'no-store' });
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
    setEmptyRow(eventTableBody, 5, 'Loading events…');
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
    params.set('limit', '50');
    try {
      const res = await fetch(`${EVENTS_RECENT_ENDPOINT}?${params.toString()}`, { cache: 'no-store' });
      if (!res.ok) {
        throw new Error(`HTTP ${res.status}`);
      }
      const data = await res.json();
      renderEventRows(data);
    } catch (err) {
      clearElement(eventTableBody);
      setEmptyRow(eventTableBody, 5, 'Failed to load events.');
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
      loadRouterKpis(),
      loadHealthStatus(),
      loadSyslogSummary(),
      loadSyslogRows(),
      loadEventSummary(),
      loadEventRows(),
      loadTimeline(),
      loadDeviceSummary()
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
    renderDiskTable(Array.isArray(data.Disk) ? data.Disk : []);
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
      loadSyslogSummary();
      loadSyslogRows();
    });
  }
  if (eventRefreshBtn) {
    eventRefreshBtn.addEventListener('click', () => {
      loadEventSummary();
      loadEventRows();
    });
  }
  if (timelineRefreshBtn) {
    timelineRefreshBtn.addEventListener('click', () => {
      loadTimeline();
    });
  }
  if (devicesRefreshBtn) {
    devicesRefreshBtn.addEventListener('click', () => {
      loadDeviceSummary();
    });
  }
  if (refreshResumeBtn) {
    refreshResumeBtn.addEventListener('click', () => {
      setAutoRefreshPaused(false);
      loadMetrics(true);
      loadTelemetry(true);
    });
  }

  renderTimelineLegend();
})();

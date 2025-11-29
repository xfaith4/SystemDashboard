'use strict';

(() => {
  const REFRESH_INTERVAL = 5000;
  const METRICS_ENDPOINT = 'metrics';

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

  if (refreshIntervalEl) {
    refreshIntervalEl.textContent = (REFRESH_INTERVAL / 1000).toString();
  }

  let refreshTimer;

  function scheduleNext(delay = REFRESH_INTERVAL) {
    clearTimeout(refreshTimer);
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

  async function loadMetrics() {
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
    } else {
      scheduleNext(200);
    }
  });

  setStatus('connecting', 'Waiting for first response…');
  scheduleNext(50);
  loadMetrics();
})();

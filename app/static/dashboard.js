(() => {
  const selectors = {
    charts: [
      { id: 'iisErrorsChart', key: 'iis_errors', color: '#e74c3c' },
      { id: 'authFailuresChart', key: 'auth_failures', color: '#f5a623' },
      { id: 'windowsErrorsChart', key: 'windows_errors', color: '#4e9af1' },
      { id: 'routerAlertsChart', key: 'router_alerts', color: '#9b59b6' }
    ],
    pulses: [
      { totalId: 'pulse-iis-total', deltaId: 'pulse-iis-delta', sparkId: 'spark-iis', key: 'iis_errors' },
      { totalId: 'pulse-auth-total', deltaId: 'pulse-auth-delta', sparkId: 'spark-auth', key: 'auth_failures' },
      { totalId: 'pulse-windows-total', deltaId: 'pulse-windows-delta', sparkId: 'spark-windows', key: 'windows_errors' },
      { totalId: 'pulse-router-total', deltaId: 'pulse-router-delta', sparkId: 'spark-router', key: 'router_alerts' }
    ]
  };

  const formatDelta = (current, median) => {
    if (!median) return '—';
    const change = ((current - median) / median) * 100;
    const arrow = change >= 0 ? '▲' : '▼';
    return `${arrow} ${Math.abs(change).toFixed(0)}% vs median`;
  };

  const median = (values) => {
    if (!values || !values.length) return 0;
    const sorted = [...values].sort((a, b) => a - b);
    const mid = Math.floor(sorted.length / 2);
    return sorted.length % 2 === 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid];
  };

  const renderBarChart = (containerId, dates, values, color) => {
    const container = document.getElementById(containerId);
    if (!container) return;
    const maxValue = Math.max(...values, 1);
    const html = `
      <div class="bar-chart">
        ${dates.map((date, i) => {
          const height = (values[i] / maxValue) * 100;
          const shortDate = date.substring(5);
          return `
            <div class="bar-wrapper">
              <div class="bar-container">
                <div class="bar" style="height: ${height}%; background: linear-gradient(180deg, ${color}, ${color}88);" title="${date}: ${values[i]}">
                  <span class="bar-value">${values[i]}</span>
                </div>
              </div>
              <div class="bar-label">${shortDate}</div>
            </div>
          `;
        }).join('')}
      </div>
    `;
    container.innerHTML = html;
  };

  const renderSparkline = (svgId, values, color) => {
    const svg = document.getElementById(svgId);
    if (!svg || !values.length) return;
    const width = 120;
    const height = 36;
    const max = Math.max(...values, 1);
    const min = Math.min(...values, 0);
    const span = max - min || 1;
    const step = values.length > 1 ? width / (values.length - 1) : width;

    const points = values.map((v, idx) => {
      const x = idx * step;
      const y = height - ((v - min) / span) * height;
      return `${x},${y}`;
    }).join(' ');

    const areaPoints = `0,${height} ${points} ${width},${height}`;

    svg.innerHTML = `
      <polyline points="${areaPoints}" fill="${color}22" stroke="none"></polyline>
      <polyline points="${points}" fill="none" stroke="${color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"></polyline>
    `;
  };

  const setText = (id, text) => {
    const el = document.getElementById(id);
    if (el) el.textContent = text;
  };

  const sum = (arr) => arr.reduce((acc, v) => acc + Number(v || 0), 0);

  async function bootstrap() {
    const hasCharts = selectors.charts.some(c => document.getElementById(c.id));
    const hasPulse = selectors.pulses.some(p => document.getElementById(p.sparkId));
    if (!hasCharts && !hasPulse) return;

    try {
      const res = await fetch('/api/trends');
      const data = await res.json();

      selectors.charts.forEach(({ id, key, color }) => {
        renderBarChart(id, data.dates || [], data[key] || [], color);
      });

      selectors.pulses.forEach(({ totalId, deltaId, sparkId, key }) => {
        const series = data[key] || [];
        const latest = series[series.length - 1] || 0;
        const med = median(series);
        setText(totalId, sum(series));
        setText(deltaId, formatDelta(latest, med));
        renderSparkline(sparkId, series, getComputedStyle(document.documentElement).getPropertyValue('--accent-color') || '#4e9af1');
      });
    } catch (err) {
      console.error('Failed to load trend data:', err);
    }
  }

  bootstrap();
})();

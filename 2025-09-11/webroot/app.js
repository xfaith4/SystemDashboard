(function(){
  const state = {
    apiBase: null
  };

  function initApiBase(){
    const body = document.body;
    state.apiBase = body.dataset.apiBase || 'http://localhost:5000/api/v1';
  }

  function switchPanel(view){
    document.querySelectorAll('.panel').forEach(panel => {
      panel.classList.toggle('active', panel.dataset.panel === view);
    });
    document.querySelectorAll('.nav-item').forEach(btn => {
      btn.classList.toggle('is-active', btn.dataset.view === view);
    });
    if (view === 'incidents') { loadIncidents(); }
    if (view === 'actions') { loadActions(); }
  }

  function connectSSE(){
    try {
      const es = new EventSource('/stream/metrics');
      es.addEventListener('metrics', (ev)=>{
        const data = JSON.parse(ev.data);
        setText('kpi-cpu', data.cpuPct.toFixed(1));
        setText('kpi-mem', data.memPct.toFixed(1));
        setText('kpi-tcp', data.tcpCount);
        setBar('bar-cpu', data.cpuPct);
        setBar('bar-mem', data.memPct);
      });
      es.onerror = ()=>{ es.close(); setTimeout(connectSSE, 3000); };
    } catch(e){ console.error(e); }
  }

  function setText(id,v){ const el=document.getElementById(id); if(el){ el.textContent=v; } }
  function setBar(id,pct){ const el=document.getElementById(id); if(el){ el.style.width = Math.max(0,Math.min(100,pct)) + '%'; } }

  window.checkHealth = async function(){
    const res = await fetch('/healthz');
    const j = await res.json();
    document.getElementById('health-out').textContent = JSON.stringify(j,null,2);
  };

  window.sendToAI = async function(){
    const lines = document.getElementById('ai-input').value.split(/\r?\n/).filter(Boolean).slice(0,50);
    const key = document.getElementById('ai-key').value.trim();
    const out = document.getElementById('ai-out');
    out.textContent = 'Analyzing...';
    const res = await fetch('/api/ai/assess', {
      method:'POST',
      headers: { 'Content-Type':'application/json', 'X-API-Key': key },
      body: JSON.stringify({ lines })
    });
    const j = await res.json();
    out.textContent = j.advice || JSON.stringify(j,null,2);
  };

  window.loadIncidents = async function(){
    const limit = document.getElementById('incidents-limit')?.value || 50;
    const list = document.getElementById('incident-list');
    if (!list) return;
    list.innerHTML = '<div class="muted">Loading incidents...</div>';
    try {
      const res = await fetch(`${state.apiBase}/incidents?limit=${limit}`);
      const data = await res.json();
      const items = data?.data?.items || [];
      if (!items.length) {
        list.innerHTML = '<div class="muted">No incidents found.</div>';
        return;
      }
      list.innerHTML = items.map(item => {
        const statusClass = item.status === 'closed' ? 'closed' : 'open';
        return `
          <div class="timeline-item">
            <div class="timeline-meta">
              <span class="badge ${statusClass}">${item.status}</span>
              <span>${item.severity || 'info'}</span>
              <span>${item.created_at || ''}</span>
            </div>
            <h4>${item.title || 'Untitled incident'}</h4>
            <p>${item.summary || 'No summary provided.'}</p>
          </div>
        `;
      }).join('');
    } catch (e) {
      list.innerHTML = `<div class="muted">Failed to load incidents: ${e}</div>`;
    }
  };

  window.loadActions = async function(){
    const limit = document.getElementById('actions-limit')?.value || 50;
    const list = document.getElementById('action-list');
    if (!list) return;
    list.innerHTML = '<div class="muted">Loading actions...</div>';
    try {
      const res = await fetch(`${state.apiBase}/actions?limit=${limit}`);
      const data = await res.json();
      const items = data?.data?.items || [];
      if (!items.length) {
        list.innerHTML = '<div class="muted">No actions queued.</div>';
        return;
      }
      list.innerHTML = items.map(item => {
        return `
          <div class="stack-item">
            <h4>${item.action_type}</h4>
            <div class="meta">status: ${item.status || 'unknown'} | incident: ${item.incident_id || 'n/a'}</div>
            <div class="meta">requested: ${item.requested_at || ''}</div>
            <div class="actions">
              <button class="btn outline" onclick="approveAction(${item.action_id})">Approve</button>
              <button class="btn" onclick="executeAction(${item.action_id})">Execute</button>
            </div>
          </div>
        `;
      }).join('');
    } catch (e) {
      list.innerHTML = `<div class="muted">Failed to load actions: ${e}</div>`;
    }
  };

  window.queueAction = async function(){
    const actionType = document.getElementById('action-type').value;
    const incidentId = document.getElementById('action-incident').value;
    const requestedBy = document.getElementById('action-requested').value || 'local-operator';
    const out = document.getElementById('action-create-out');
    out.textContent = 'Queueing...';
    const body = {
      action_type: actionType,
      requested_by: requestedBy,
      incident_id: incidentId ? Number(incidentId) : null
    };
    const res = await fetch(`${state.apiBase}/actions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });
    const data = await res.json();
    out.textContent = JSON.stringify(data, null, 2);
    loadActions();
  };

  window.approveAction = async function(actionId){
    const res = await fetch(`${state.apiBase}/actions/${actionId}/approve`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ approved_by: 'local-operator' })
    });
    await res.json();
    loadActions();
  };

  window.executeAction = async function(actionId){
    const res = await fetch(`${state.apiBase}/actions/${actionId}/execute`, {
      method: 'POST' }
    );
    await res.json();
    loadActions();
  };

  function wireTelemetryButtons(){
    const target = document.getElementById('telemetry-out');
    if (!target) return;
    document.querySelectorAll('[data-endpoint]').forEach(btn => {
      const url = btn.dataset.endpoint;
      if (!url) return;
      btn.addEventListener('click', async () => {
        target.textContent = 'Loading...';
        try {
          const res = await fetch(url);
          if (!res.ok) {
            target.textContent = `Failed to fetch feed (HTTP ${res.status})`;
            return;
          }
          const text = await res.text();
          const ctype = res.headers.get('content-type') || '';
          if (ctype.includes('json')) {
            try {
              target.textContent = JSON.stringify(JSON.parse(text), null, 2);
            } catch (_error) {
              target.textContent = text;
            }
          } else {
            target.textContent = text;
          }
        } catch (e) {
          target.textContent = 'Failed to fetch feed.';
        }
      });
    });
  }

  document.addEventListener('DOMContentLoaded', () => {
    initApiBase();
    connectSSE();
    switchPanel('overview');
    document.querySelectorAll('.nav-item').forEach(btn => {
      btn.addEventListener('click', () => switchPanel(btn.dataset.view));
    });
    wireTelemetryButtons();
  });
})();

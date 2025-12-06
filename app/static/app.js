// Toast Notification System
const Toast = {
  show(message, type = 'info', title = null, duration = 5000) {
    const container = document.getElementById('toast-container');
    if (!container) return;

    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    
    const icons = {
      success: '<path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/>',
      error: '<circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/>',
      warning: '<path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/>',
      info: '<circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/>'
    };

    toast.innerHTML = `
      <svg class="toast-icon ${type}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        ${icons[type] || icons.info}
      </svg>
      <div class="toast-content">
        ${title ? `<div class="toast-title">${title}</div>` : ''}
        <div class="toast-message">${message}</div>
      </div>
      <button class="toast-close" aria-label="Close notification">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
        </svg>
      </button>
    `;

    const closeBtn = toast.querySelector('.toast-close');
    const remove = () => {
      toast.classList.add('toast-hiding');
      setTimeout(() => toast.remove(), 300);
    };
    
    closeBtn.onclick = remove;
    container.appendChild(toast);

    if (duration > 0) {
      setTimeout(remove, duration);
    }

    return toast;
  },

  success(message, title = 'Success') {
    return this.show(message, 'success', title);
  },

  error(message, title = 'Error') {
    return this.show(message, 'error', title);
  },

  warning(message, title = 'Warning') {
    return this.show(message, 'warning', title);
  },

  info(message, title = null) {
    return this.show(message, 'info', title);
  }
};

// Make Toast available globally
window.Toast = Toast;

(() => {
  function qs(sel, root=document){ return root.querySelector(sel); }
  function qsa(sel, root=document){ return Array.from(root.querySelectorAll(sel)); }

  const table = qs('#eventsTable');
  if (!table) return; // only on events page

  const searchInput = qs('#searchInput');
  const levelFilter = qs('#levelFilter');
  const refreshBtn = qs('#refreshBtn');
  const insights = qs('#insights');

  let events = Array.isArray(window.__INITIAL_EVENTS__) ? window.__INITIAL_EVENTS__ : [];

  function computeInsights(rows) {
    const total = rows.length;
    const byLevel = rows.reduce((acc, e) => { const k=(e.level||'').toLowerCase(); acc[k]=(acc[k]||0)+1; return acc; }, {});
    const bySource = rows.reduce((acc, e) => { const k=e.source||'Unknown'; acc[k]=(acc[k]||0)+1; return acc; }, {});
    const topSources = Object.entries(bySource).sort((a,b)=>b[1]-a[1]).slice(0,5).map(([s,c])=>`${s} (${c})`).join(', ');
    return `Total: ${total}. Errors: ${byLevel.error||0}. Warnings: ${byLevel.warning||0}. Top sources: ${topSources}`;
  }

  function renderRows(rows){
    const tbody = table.tBodies[0];
    tbody.innerHTML = rows.map(e => `
      <tr>
        <td>${e.time||''}</td>
        <td>${e.level||''}</td>
        <td>${e.source||''}</td>
        <td class="wrap">${escapeHtml(e.message||'')}</td>
        <td><button class="aiSuggestBtn" data-source="${attr(e.source)}" data-id="${attr(e.id)}" data-message="${attr(e.message)}">Ask AI</button></td>
      </tr>`).join('');
    wireAiButtons();
    if (insights) {
      insights.textContent = computeInsights(rows);
    }
  }

  function escapeHtml(s){
    return s.replace(/[&<>]/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[ch]));
  }
  function attr(s){ return String(s||'').replace(/"/g,'&quot;'); }

  function filterRows(){
    const q = (searchInput.value||'').toLowerCase();
    const lvl = (levelFilter.value||'').toLowerCase();
    const rows = events.filter(e => {
      if (lvl && String(e.level||'').toLowerCase() !== lvl) return false;
      if (!q) return true;
      const hay = `${e.time||''} ${e.source||''} ${e.message||''}`.toLowerCase();
      return hay.includes(q);
    });
    renderRows(rows);
  }

  async function refresh(){
    const lvl = (levelFilter.value||'');
    const qsStr = lvl ? `?level=${encodeURIComponent(lvl)}` : '';
    const res = await fetch(`/api/events${qsStr}`);
    const data = await res.json();
    events = data.events || [];
    filterRows();
  }

  function wireAiButtons(){
    qsa('.aiSuggestBtn').forEach(btn => {
      btn.onclick = async () => {
        const payload = {
          source: btn.dataset.source,
          id: btn.dataset.id || null,
          message: btn.dataset.message || ''
        };
        const modal = qs('#aiResult');
        const pre = qs('#aiText');
        pre.textContent = 'Asking OpenAI for suggestions...';
        modal.hidden = false;
        try {
          const res = await fetch('/api/ai/suggest', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(payload) });
          const data = await res.json();
          if (data.suggestion) pre.textContent = data.suggestion;
          else pre.textContent = data.error || 'No suggestion available.';
        } catch (e) {
          pre.textContent = 'Failed to contact suggestion service.';
        }
      }
    });
  }

  const closeBtn = qs('#closeModal');
  if (closeBtn) closeBtn.onclick = () => { qs('#aiResult').hidden = true; };
  if (searchInput) searchInput.oninput = filterRows;
  if (levelFilter) levelFilter.onchange = filterRows;
  if (refreshBtn) refreshBtn.onclick = refresh;

  // initial insights render
  renderRows(events);
})();


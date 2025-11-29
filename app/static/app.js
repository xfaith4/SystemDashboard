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
    insights.textContent = computeInsights(rows);
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


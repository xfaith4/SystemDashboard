(function(){
  // Live metrics via SSE
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

  // Health check
  window.checkHealth = async function(){
    const res = await fetch('/healthz'); const j = await res.json();
    document.getElementById('health-out').textContent = JSON.stringify(j,null,2);
  };

  // Ask AI
  window.showAskAI = function(){
    document.getElementById('askai').classList.remove('hidden');
    document.getElementById('content').innerHTML = '';
  };
  window.sendToAI = async function(){
    const lines = document.getElementById('ai-input').value.split(/\r?\n/).filter(Boolean).slice(0,50);
    const key = document.getElementById('ai-key').value.trim();
    const out = document.getElementById('ai-out'); out.textContent = 'Analyzing...';
    const res = await fetch('/api/ai/assess', {
      method:'POST',
      headers: { 'Content-Type':'application/json', 'X-API-Key': key },
      body: JSON.stringify({ lines })
    });
    const j = await res.json();
    out.textContent = j.advice || JSON.stringify(j,null,2);
  };

  document.addEventListener('DOMContentLoaded', connectSSE);
})();

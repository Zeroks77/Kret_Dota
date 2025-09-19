(function(){
  function esc(s){ return String(s||'').replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[c])); }
  function h(html){ const t=document.createElement('template'); t.innerHTML=html.trim(); return t.content.firstElementChild; }
  function injectStyles(){ if(document.getElementById('ps-base-styles')) return; const css=`
  .ps-wrapper{display:flex;flex-direction:column;gap:10px}
  .ps-toolbar{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:-2px 0 2px}
  .ps-toolbar .seg{padding:6px 10px;border:1px solid var(--border,rgba(255,255,255,.12));background:linear-gradient(180deg,rgba(255,255,255,.07),rgba(255,255,255,.03));border-radius:10px;cursor:pointer;font-size:12px;color:var(--text,#eef3fb)}
  .ps-toolbar .seg.active{outline:2px solid rgba(109,166,255,.5);background:linear-gradient(180deg,rgba(109,166,255,.2),rgba(109,166,255,.08));border-color:rgba(109,166,255,.45)}
  table.ps-table{width:100%;border-collapse:collapse}
  table.ps-table th,table.ps-table td{padding:6px 8px;border-bottom:1px solid rgba(255,255,255,.06);font-size:13px;text-align:left}
  table.ps-table th{color:var(--muted,#9aa3b2);font-weight:600;font-size:11px;text-transform:uppercase;letter-spacing:1px}
  .ps-badge{display:inline-block;background:rgba(255,255,255,.08);padding:3px 6px;border-radius:8px;font-size:11px}
  .ps-hero-break{display:flex;flex-wrap:wrap;gap:6px;margin-top:4px}
  .ps-chip{padding:4px 6px;border:1px solid rgba(255,255,255,.1);border-radius:6px;font-size:11px;background:rgba(255,255,255,.05)}
  .ps-empty{color:var(--muted,#9aa3b2);font-size:12px}
  `; const st=document.createElement('style'); st.id='ps-base-styles'; st.textContent=css; document.head.appendChild(st); }
  function mount(host, cfg){ injectStyles(); if(!host) return; const data = cfg&&cfg.data || {}; const players = Array.isArray(data.players)? data.players: []; const heroMap=(cfg&&cfg.heroes)||{}; let state={ sort:'games', filter:'' };
    function computeRows(){ const list = players.slice(); // list items: {id,name, games,wins, heroes:{hid:count}, heroWins:{hid:wins}}
      return list.map(p=>{ const games=Number(p.games||0); const wins=Number(p.wins||0); const wr= games? wins/games : 0; const pool=Object.keys(p.heroes||{}).length; const topHeroes = Object.entries(p.heroes||{}).map(([hid,cnt])=>{ const hw = Number(p.heroWins && p.heroWins[hid] || 0); const hwr = cnt? hw/cnt : 0; return {hid:Number(hid), cnt:Number(cnt), wr:hwr}; }).sort((a,b)=> b.cnt-a.cnt || b.wr-a.wr).slice(0,5); return { id:p.account_id||p.id, name:p.name||('Player '+p.id), games, wins, wr, pool, topHeroes}; }); }
    function sortRows(rows){ const k=state.sort; return rows.slice().sort((a,b)=>{ if(k==='wr') return (b.wr-a.wr)|| (b.games-a.games); if(k==='pool') return (b.pool-a.pool)|| (b.wr-a.wr); return (b.games-a.games)|| (b.wr-a.wr); }); }
    const root = h(`<div class='ps-wrapper'>
      <div class='ps-toolbar'>
        <button class='seg' data-sort='games'>Sort Games</button>
        <button class='seg' data-sort='wr'>Sort WR</button>
        <button class='seg' data-sort='pool'>Sort Hero Pool</button>
        <input type='text' placeholder='Filter player…' id='psFilter' style='padding:6px 8px;border-radius:8px;border:1px solid var(--border,rgba(255,255,255,.12));background:rgba(255,255,255,.06);color:var(--text,#eef3fb);font-size:12px'>
      </div>
      <div style='overflow:auto'>
        <table class='ps-table'>
          <thead><tr><th>Player</th><th>Games</th><th>W-L</th><th>WR</th><th>Hero Pool</th><th>Top Heroes</th></tr></thead>
          <tbody id='psBody'></tbody>
        </table>
      </div>
    </div>`);
    host.innerHTML=''; host.appendChild(root);
    function setActive(){ root.querySelectorAll('.ps-toolbar [data-sort]').forEach(b=> b.classList.toggle('active',(b.getAttribute('data-sort')||'')===state.sort)); }
    function fmtPct(x){ return (x*100).toFixed(1)+'%'; }
    function render(){ setActive(); const tbody=root.querySelector('#psBody'); if(!tbody) return; const rows = sortRows(computeRows()).filter(r=> !state.filter || r.name.toLowerCase().includes(state.filter) || String(r.id).includes(state.filter)); tbody.innerHTML = rows.length? rows.map(r=>{ const heroes = r.topHeroes.map(th=>{ const meta=heroMap[String(th.hid)]||{}; const nm=esc(meta.name||('#'+th.hid)); return `<span class='ps-chip' title='${nm} WR ${fmtPct(th.wr)}'>${nm} (${th.cnt})</span>`; }).join(''); return `<tr><td>${esc(r.name)}</td><td>${r.games}</td><td><span class='win'>${r.wins}</span>-<span class='loss'>${r.games-r.wins}</span></td><td>${fmtPct(r.wr)}</td><td>${r.pool}</td><td>${heroes||'<span class=ps-empty>none</span>'}</td></tr>`; }).join('') : `<tr><td colspan='6' class='ps-empty'>Keine Spieler</td></tr>`; }
    root.querySelector('.ps-toolbar').addEventListener('click', e=>{ const btn=e.target.closest('button.seg'); if(!btn) return; state.sort=btn.getAttribute('data-sort'); render(); });
    const filterInput=root.querySelector('#psFilter'); if(filterInput){ filterInput.addEventListener('input',()=>{ state.filter=String(filterInput.value||'').trim().toLowerCase(); render(); }); }
    render();
  }
  window.PlayerStatsViewer = { mount };
})();

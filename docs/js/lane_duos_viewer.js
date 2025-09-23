(function(){
  function esc(s){ return String(s||'').replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[c])); }
  function h(html){ const t=document.createElement('template'); t.innerHTML=html.trim(); return t.content.firstElementChild; }
  function injectStyles(){ if(document.getElementById('ld-base-styles')) return; const css=`
  .ld-wrapper{display:flex;flex-direction:column;gap:10px}
  .ld-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:14px}
  .ld-card{background:linear-gradient(180deg,rgba(255,255,255,.05),rgba(255,255,255,.025));border:1px solid var(--border,rgba(255,255,255,.08));border-radius:12px;padding:10px}
  .ld-title{margin:0 0 6px;font-size:15px;font-weight:600;color:var(--muted,#9aa3b2)}
  ul.ld-list{list-style:none;margin:0;padding:0}
  ul.ld-list li{display:grid;grid-template-columns:1fr auto auto;gap:8px;align-items:center;padding:6px 0;border-bottom:1px solid rgba(255,255,255,.06);font-size:13px}
  ul.ld-list li:last-child{border-bottom:0}
  .ld-badges{display:flex;gap:6px;align-items:center}
  .ld-badge{display:inline-block;padding:4px 8px;border-radius:999px;background:rgba(255,255,255,.08);font-size:11px;color:var(--text,#eef3fb)}
  .ld-empty{font-size:12px;color:var(--muted,#9aa3b2)}
  .ld-toolbar{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:-2px 0 4px}
  .ld-toolbar .seg{padding:6px 10px;border:1px solid var(--border,rgba(255,255,255,.12));background:linear-gradient(180deg,rgba(255,255,255,.07),rgba(255,255,255,.03));border-radius:10px;cursor:pointer;font-size:12px;color:var(--text,#eef3fb)}
  .ld-toolbar .seg.active{outline:2px solid rgba(109,166,255,.5);background:linear-gradient(180deg,rgba(109,166,255,.2),rgba(109,166,255,.08));border-color:rgba(109,166,255,.45)}
  .ld-toolbar .field{display:inline-flex;gap:6px;align-items:center;padding:4px 8px;border:1px solid var(--border,rgba(255,255,255,.12));border-radius:10px}
  .ld-toolbar input[type="number"]{width:70px;background:transparent;color:var(--text);border:1px solid var(--border,rgba(255,255,255,.12));border-radius:8px;padding:4px 6px}
  `; const st=document.createElement('style'); st.id='ld-base-styles'; st.textContent=css; document.head.appendChild(st); }
  function mount(host, cfg){ injectStyles(); if(!host) return; const data = cfg&&cfg.data || {}; const safe=Array.isArray(data.safe)? data.safe: []; const off=Array.isArray(data.off)? data.off: []; const heroMap = (cfg&&cfg.heroes)||{}; const persistKey = cfg&&cfg.persistKey || null; let state={ lane:'both', sort:'wr', minGames:0, minWR:0 };
    // restore persisted state
    if(persistKey){ try{ const saved = JSON.parse(localStorage.getItem(persistKey) || 'null'); if(saved && typeof saved==='object'){ if(['both','safe','off'].includes(saved.lane)) state.lane=saved.lane; if(['wr','games'].includes(saved.sort)) state.sort=saved.sort; if(Number.isFinite(saved.minGames)) state.minGames = Math.max(0, Math.floor(saved.minGames)); if(Number.isFinite(saved.minWR)) state.minWR = Math.max(0, Math.min(100, saved.minWR)); } }catch(_e){} }
    function duoRow(d){ const a=heroMap[String(d.a)]||{}; const b=heroMap[String(d.b)]||{}; const aN=esc(a.name||('#'+d.a)); const bN=esc(b.name||('#'+d.b)); const wr = d.games? (d.wins/d.games):0; return `<li><span>${aN} + ${bN}</span><span class='ld-badge'>G ${d.games}</span><span class='ld-badge'>WR ${(wr*100).toFixed(1)}%</span></li>`; }
    function sortArr(arr){ const filtered = arr.filter(x=> x.games >= state.minGames && (x.games? (x.wins/x.games) : 0) >= (state.minWR/100)); if(state.sort==='games') return filtered.slice().sort((a,b)=> b.games-a.games || (b.wins/b.games)-(a.wins/a.games)); return filtered.slice().sort((a,b)=> (b.wins/b.games)-(a.wins/a.games) || b.games-a.games); }
    const root = h(`<div class='ld-wrapper'>
      <div class='ld-toolbar'>
        <button class='seg' data-lane='both'>Beide</button>
        <button class='seg' data-lane='safe'>Safe</button>
        <button class='seg' data-lane='off'>Off</button>
        <button class='seg' data-sort='wr'>Sort WR</button>
        <button class='seg' data-sort='games'>Sort Games</button>
        <span class='field'><label class='sub'>Min Games</label><input type='number' id='ldMinGames' value='0' min='0' step='1'></span>
        <span class='field'><label class='sub'>Min WR %</label><input type='number' id='ldMinWR' value='0' min='0' max='100' step='1'></span>
      </div>
      <div class='ld-grid'>
        <div class='ld-card' data-pane='safe'><h3 class='ld-title'>Safe Lane Duos</h3><ul class='ld-list' id='ldSafe'></ul></div>
        <div class='ld-card' data-pane='off'><h3 class='ld-title'>Off Lane Duos</h3><ul class='ld-list' id='ldOff'></ul></div>
      </div>
    </div>`);
    host.innerHTML=''; host.appendChild(root);
    function setActive(){ root.querySelectorAll('.ld-toolbar [data-lane]').forEach(b=> b.classList.toggle('active', (b.getAttribute('data-lane')||'')===state.lane)); root.querySelectorAll('.ld-toolbar [data-sort]').forEach(b=> b.classList.toggle('active',(b.getAttribute('data-sort')||'')===state.sort)); const mg=root.querySelector('#ldMinGames'); const mw=root.querySelector('#ldMinWR'); if(mg) mg.value=String(state.minGames); if(mw) mw.value=String(state.minWR); }
    function toCSV(){
      const escv = (v)=>{ const s=String(v).replace(/\u00A0/g,' ').trim(); return /[",\n]/.test(s)? '"'+s.replace(/"/g,'""')+'"' : s; };
      const rows = [];
      const headers = ['Lane','Hero A','Hero B','Games','Wins','WR']; rows.push(headers.join(','));
      const add = (laneName, arr)=>{
        arr.forEach(d=>{
          const a=heroMap[String(d.a)]||{}; const b=heroMap[String(d.b)]||{}; const wr = d.games? (d.wins/d.games):0;
          rows.push([laneName, a.name||('#'+d.a), b.name||('#'+d.b), d.games, d.wins, (wr*100).toFixed(1)+'%'].map(escv).join(','));
        });
      };
      const sSafe = sortArr(safe), sOff = sortArr(off);
      if(state.lane==='safe') add('Safe', sSafe);
      else if(state.lane==='off') add('Off', sOff);
      else { add('Safe', sSafe); add('Off', sOff); }
      return rows.join('\n');
    }
  function persist(){ if(!persistKey) return; try{ localStorage.setItem(persistKey, JSON.stringify(state)); }catch(_e){} }
  function render(){ setActive(); const safeEl=root.querySelector('#ldSafe'); const offEl=root.querySelector('#ldOff'); const sSafe = sortArr(safe); const sOff=sortArr(off); if(safeEl){ safeEl.innerHTML = sSafe.length? sSafe.map(duoRow).join('') : `<li class='ld-empty'>Keine Safe Duos</li>`; } if(offEl){ offEl.innerHTML = sOff.length? sOff.map(duoRow).join('') : `<li class='ld-empty'>Keine Off Duos</li>`; } root.querySelectorAll('[data-pane="safe"]').forEach(p=> p.style.display = (state.lane==='both'||state.lane==='safe')?'':'none'); root.querySelectorAll('[data-pane="off"]').forEach(p=> p.style.display = (state.lane==='both'||state.lane==='off')?'':'none'); try{ host.__getLaneDuosCSV = toCSV; }catch(_e){} }
  const toolbar = root.querySelector('.ld-toolbar');
  toolbar.addEventListener('click', e=>{ const btn=e.target.closest('button.seg'); if(!btn) return; if(btn.hasAttribute('data-lane')) state.lane=btn.getAttribute('data-lane'); if(btn.hasAttribute('data-sort')) state.sort=btn.getAttribute('data-sort'); persist(); render(); });
  toolbar.addEventListener('keydown', e=>{ const btn=e.target.closest('button.seg'); if(!btn) return; if(e.key==='Enter' || e.key===' '){ e.preventDefault(); if(btn.hasAttribute('data-lane')) state.lane=btn.getAttribute('data-lane'); if(btn.hasAttribute('data-sort')) state.sort=btn.getAttribute('data-sort'); persist(); render(); } });
  root.querySelector('#ldMinGames').addEventListener('change', e=>{ const v = Number(e.target.value||0); state.minGames = isFinite(v)? Math.max(0, Math.floor(v)) : 0; persist(); render(); });
  root.querySelector('#ldMinWR').addEventListener('change', e=>{ const v = Number(e.target.value||0); state.minWR = isFinite(v)? Math.max(0, Math.min(100, v)) : 0; persist(); render(); });
    render();
  }
  window.LaneDuosViewer = { mount };
})();

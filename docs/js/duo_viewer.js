(function(){
  function esc(s){ return String(s||'').replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[c])); }
  function h(html){ const t=document.createElement('template'); t.innerHTML=html.trim(); return t.content.firstElementChild; }
  function inject(){ if(document.getElementById('duo-viewer-styles')) return; const css=`
  .dvduo-wrapper{display:flex;flex-direction:column;gap:10px}
  .dvduo-toolbar{display:flex;flex-wrap:wrap;gap:8px;align-items:center}
  .dvduo-toolbar .seg{padding:6px 10px;border:1px solid var(--border,rgba(255,255,255,.12));background:linear-gradient(180deg,rgba(255,255,255,.07),rgba(255,255,255,.03));border-radius:10px;color:var(--text,#eef3fb);font-size:12px;cursor:pointer}
  .dvduo-toolbar .seg.active{outline:2px solid rgba(109,166,255,.5);background:linear-gradient(180deg,rgba(109,166,255,.2),rgba(109,166,255,.08));border-color:rgba(109,166,255,.45)}
  .dvduo-list{list-style:none;margin:0;padding:0}
  .dvduo-list li{display:grid;grid-template-columns:1fr auto auto;align-items:center;gap:8px;padding:6px 0;border-bottom:1px solid rgba(255,255,255,.06);font-size:13px}
  .dvduo-list li:last-child{border-bottom:0}
  .badge{display:inline-block;padding:4px 8px;border-radius:999px;background:var(--chip,#1a2142);font-size:11px}
  .has-fly{position:relative}
  .fly{display:none;position:absolute;left:0;top:100%;margin-top:6px;background:rgba(10,16,34,.96);border:1px solid var(--border,rgba(255,255,255,.12));border-radius:10px;padding:10px;min-width:280px;z-index:10000;box-shadow:0 8px 20px rgba(0,0,0,.4)}
  .has-fly.open .fly{display:block}
  .hero-row{display:flex;align-items:center;justify-content:space-between;gap:8px;padding:4px 0;border-bottom:1px solid rgba(255,255,255,.06)}
  .hero-row:last-child{border-bottom:0}
  .hpair{display:flex;align-items:center;gap:8px}
  .hpair img{width:28px;height:28px;border-radius:6px;border:1px solid rgba(255,255,255,.1);object-fit:cover}
  `; const st=document.createElement('style'); st.id='duo-viewer-styles'; st.textContent=css; document.head.appendChild(st); }
  function pct(x){ return (x*100).toFixed(1)+'%'; }
  function mount(host, cfg){ inject(); if(!host) return; const heroes = (cfg&&cfg.heroes)||{}; const arr = Array.isArray(cfg&&cfg.data)? cfg.data: []; let state={ sort:'wr', minGames:0, minWr:0 };
    const root = h(`<div class='dvduo-wrapper'>
      <div class='dvduo-toolbar'>
        <button class='seg' data-sort='wr'>Sort WR</button>
        <button class='seg' data-sort='games'>Sort Games</button>
        <label class='sub' style='display:flex;gap:6px;align-items:center'>Min Games <input type='number' id='dvduoMinG' value='0' min='0' step='1' style='width:80px;background:transparent;color:var(--text);border:1px solid var(--border,rgba(255,255,255,.12));border-radius:8px;padding:4px 6px'></label>
        <label class='sub' style='display:flex;gap:6px;align-items:center'>Min WR % <input type='number' id='dvduoMinWR' value='0' min='0' max='100' step='1' style='width:80px;background:transparent;color:var(--text);border:1px solid var(--border,rgba(255,255,255,.12));border-radius:8px;padding:4px 6px'></label>
      </div>
      <ul class='dvduo-list' id='dvduoList'></ul>
    </div>`);
    host.innerHTML=''; host.appendChild(root);
    function sortFiltered(){ const filtered = arr.filter(d=> d.games>=state.minGames && ((d.wins/(d.games||1))>=(state.minWr/100))); if(state.sort==='games'){ return filtered.slice().sort((a,b)=> b.games-a.games || (b.wins/b.games)-(a.wins/a.games)); } return filtered.slice().sort((a,b)=> (b.wins/b.games)-(a.wins/a.games) || b.games-a.games); }
    function setActive(){ root.querySelectorAll('.dvduo-toolbar .seg').forEach(b=> b.classList.toggle('active',(b.getAttribute('data-sort')||'')===state.sort)); const mg=root.querySelector('#dvduoMinG'); const mw=root.querySelector('#dvduoMinWR'); if(mg) mg.value=String(state.minGames); if(mw) mw.value=String(state.minWr); }
    function heroImg(hid){ const meta = heroes[String(hid)]||{}; const url = meta.icon || meta.img || ''; return `<img src='${esc(url)}' alt='${esc(meta.name||('#'+hid))}'>`; }
    function heroName(hid){ const meta = heroes[String(hid)]||{}; return esc(meta.name||('#'+hid)); }
    function render(){ setActive(); const list=root.querySelector('#dvduoList'); if(!list) return; const data = sortFiltered(); if(!data.length){ list.innerHTML = `<li class='sub'>Keine Duos</li>`; return; }
      list.innerHTML = data.map((d,i)=>{
        const a = d.pair && d.pair[0] || {}; const b = d.pair && d.pair[1] || {};
        const wr = d.games? (d.wins/d.games):0; const id = `fly-${i}-${(Math.random().toString(36).slice(2))}`;
        const btn = `<button class='badge' data-fly='${id}'>Heroes</button>`;
        const fly = `<div class='fly' id='${id}'>` + (Array.isArray(d.heroes)&&d.heroes.length? d.heroes.map(h=>{
            const metaA = heroes[String(h.a)]||{}; const metaB = heroes[String(h.b)]||{}; const wrh = h.games? (h.wins/h.games):0;
            return `<div class='hero-row'><span class='hpair'>${heroImg(h.a)}${heroImg(h.b)}<span>${esc(metaA.name||('#'+h.a))} + ${esc(metaB.name||('#'+h.b))}</span></span><span><span class='badge'>x${h.games}</span> <span class='badge'>WR ${pct(wrh)}</span></span></div>`;
          }).join('') : `<div class='sub'>no hero data</div>`) + `</div>`;
        const left = `<span class='has-fly'><a href='${esc(a.profile||'#')}' target='_blank'>${esc(a.name||'Player')}</a> + <a href='${esc(b.profile||'#')}' target='_blank'>${esc(b.name||'Player')}</a> ${btn} ${fly}</span>`;
        const badges = `<span class='badge'>x${d.games}</span><span class='badge'>WR ${pct(wr)}</span>`;
        return `<li>${left}<span></span><span style='display:flex;gap:6px;align-items:center'>${badges}</span></li>`;
      }).join('');
      // wire flyouts
      list.querySelectorAll('button[data-fly]').forEach(btn=>{
        btn.addEventListener('click', (e)=>{
          e.preventDefault(); e.stopPropagation();
          const id = btn.getAttribute('data-fly');
          const wrap = btn.closest('.has-fly');
          if(!id||!wrap) return;
          document.querySelectorAll('.has-fly.open').forEach(n=>{ if(n!==wrap) n.classList.remove('open'); });
          wrap.classList.toggle('open');
        });
      });
      document.addEventListener('click', (e)=>{
        document.querySelectorAll('.has-fly.open').forEach(n=>{ if(!n.contains(e.target)) n.classList.remove('open'); });
      });
    }
    root.querySelector('.dvduo-toolbar').addEventListener('click', (e)=>{ const b=e.target.closest('button.seg'); if(!b) return; state.sort=b.getAttribute('data-sort')||'wr'; render(); });
    root.querySelector('#dvduoMinG').addEventListener('input', (e)=>{ const v=parseInt(e.target.value||'0',10); state.minGames=isNaN(v)?0:Math.max(0,v); render(); });
    root.querySelector('#dvduoMinWR').addEventListener('input', (e)=>{ const v=parseFloat(e.target.value||'0'); state.minWr=isNaN(v)?0:Math.max(0, Math.min(100,v)); render(); });
    render();
  }
  window.DuosViewer = { mount };
})();

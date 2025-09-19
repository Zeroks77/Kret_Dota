(function(){
  function esc(s){ return String(s||'').replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[c])); }
  function hero(meta, size){ if(!meta) return `<span class="badge">#?</span>`; const w=size||28; return `<span style="display:inline-flex;align-items:center;gap:6px"><img src='${esc(meta.img||meta.icon||'')}' alt='${esc(meta.name||'Hero')}' loading='lazy' decoding='async' style='width:${w}px;height:${w}px;border-radius:6px;border:1px solid rgba(255,255,255,.1)'><span>${esc(meta.name||'Hero')}</span></span>`; }
  function fmtPct(x){ return (x*100).toFixed(1)+'%'; }
  function ensureStyle(){
    if(document.getElementById('dv-draft-style')) return;
    const css = `
      .dv-draft .summary-grid{ grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 12px }
      .dv-draft table{ width:100%; border-collapse: separate; border-spacing:0 }
      .dv-draft thead th{ text-align:left; color: var(--muted); font-weight:600; background: rgba(255,255,255,.03) }
      .dv-draft th, .dv-draft td{ padding:10px 10px; border-bottom:1px solid rgba(255,255,255,.06); font-size:14px }
      .dv-draft tbody tr:nth-child(odd){ background: rgba(255,255,255,.02) }
      .dv-draft td.num, .dv-draft th.num{ text-align:right; font-variant-numeric: tabular-nums }
      .dv-draft td.col-hero{ min-width:220px }
      .dv-draft td.col-pair{ min-width:260px }
      .dv-draft .toolbar{ display:flex; flex-wrap:wrap; gap:6px; align-items:center; margin-bottom:8px }
      .dv-draft .seg{ padding:6px 10px; border:1px solid var(--border); background:linear-gradient(180deg, rgba(255,255,255,.07), rgba(255,255,255,.03)); color:var(--text); border-radius:10px; cursor:pointer; font-size:12px }
      .dv-draft .seg.active{ outline:2px solid rgba(109,166,255,.5); background:linear-gradient(180deg, rgba(109,166,255,.2), rgba(109,166,255,.08)); border-color:rgba(109,166,255,.45) }
      .dv-draft .switch{ display:inline-flex; align-items:center; gap:6px; margin-left:8px }
      
      .dv-draft .hname{ white-space:nowrap; overflow:hidden; text-overflow:ellipsis; display:inline-block; max-width:200px }
    `;
    const el = document.createElement('style'); el.id='dv-draft-style'; el.textContent = css; document.head.appendChild(el);
  }

  function compute(details){
    const picks = new Map(); // hid -> {picks,wins}
    const bans = new Map();  // hid -> count
    const firstPick = new Map(); // hid -> {count,wins}
    const openingPairs = new Map(); // "a-b" -> {games,wins}

    for(const md of details||[]){ if(!md) continue; const radWin = !!md.radiant_win; const pbs = Array.isArray(md.picks_bans)? md.picks_bans: []; if(!pbs.length) continue;
      // Collect pick events per side in draft order
      const pickEvents = { Radiant: [], Dire: [] };
      for(const pb of pbs){
        const hid = Number(pb.hero_id||0); if(!(hid>0)) continue;
        const isPick = !!pb.is_pick;
        const tRaw = pb.team; let side = null;
        if(tRaw===0) side='Radiant'; else if(tRaw===1) side='Dire';
        // Fallback: try is_radiant flag sometimes present
        if(!side && pb.hasOwnProperty('is_radiant')) side = pb.is_radiant ? 'Radiant' : 'Dire';
        const order = Number(pb.order||pb.pick_order||pb.draft_order||0);
        if(isPick){
          const rec = picks.get(hid) || { picks:0, wins:0 }; rec.picks++; picks.set(hid, rec);
          if(side){ pickEvents[side].push({ hid, order }); }
        } else {
          bans.set(hid, (bans.get(hid)||0) + 1);
        }
      }
      function teamWon(side){ return side==='Radiant' ? radWin : !radWin; }
      // First pick per side
      for(const side of ['Radiant','Dire']){
        const list = pickEvents[side].slice().sort((a,b)=> a.order - b.order);
        if(list.length){ const fp = list[0]; const r = firstPick.get(fp.hid) || { count:0, wins:0 }; r.count++; if(teamWon(side)) r.wins++; firstPick.set(fp.hid, r); }
        // Opening pair: first two picks if present
        if(list.length>=2){ const a=list[0].hid, b=list[1].hid; const lo=Math.min(a,b), hi=Math.max(a,b); const key=`${lo}-${hi}`; const rec = openingPairs.get(key) || { a:lo, b:hi, games:0, wins:0 }; rec.games++; if(teamWon(side)) rec.wins++; openingPairs.set(key, rec); }
      }
      // Attribute pick wins to heroes (rough proxy)
      for(const side of ['Radiant','Dire']){
        const list = pickEvents[side]; const won = teamWon(side);
        if(won){ for(const ev of list){ const pr = picks.get(ev.hid); if(pr){ pr.wins++; picks.set(ev.hid, pr); } } }
      }
    }
    const contest = new Map();
    const allHids = new Set([...picks.keys(), ...bans.keys()]);
    for(const hid of allHids){ const pk = picks.get(hid) || {picks:0,wins:0}; const bn = bans.get(hid)||0; contest.set(hid, { hid, picks: pk.picks, pickWins: pk.wins, bans: bn, contest: pk.picks + bn, wrPick: pk.picks? (pk.wins/pk.picks):0 }); }
    const first = Array.from(firstPick.entries()).map(([hid, v])=>({ hid:Number(hid), count:v.count, wins:v.wins, wr: v.count? (v.wins/v.count):0 })).sort((a,b)=> b.count - a.count || b.wr - a.wr).slice(0,20);
    const pairs = Array.from(openingPairs.values()).map(v=>({ ...v, wr: v.games? (v.wins/v.games):0 })).sort((a,b)=> b.wr - a.wr || b.games - a.games).slice(0,20);
    const cont = Array.from(contest.values()).sort((a,b)=> b.contest - a.contest || b.picks - a.picks || b.bans - a.bans).slice(0,20);
    return { contest: cont, firstPicks: first, openingPairs: pairs };
  }

  function mount(root, opts){
    if(!root) return; ensureStyle(); const heroes = (opts&&opts.heroes)||{}; const data = (opts&&opts.data)||{};
    const persistKey = (opts && opts.persistKey) || null;
    function hmeta(id){ return heroes[String(id)] || { name: `#${id}`, img: '' }; }
    function listContest(arr){ if(!arr||!arr.length) return '<div class="sub">no data</div>'; return `<table class='table'>
      <thead><tr><th>Hero</th><th class='num'>Picks</th><th class='num'>Bans</th><th class='num'>Contest</th><th class='num'>Pick WR</th></tr></thead>
      <tbody>${arr.map(x=>`<tr><td class='col-hero'>${hero(hmeta(x.hid),22)} <span class='hname'></span></td><td class='num'>${x.picks}</td><td class='num'>${x.bans}</td><td class='num'>${x.contest}</td><td class='num'>${fmtPct(x.wrPick)}</td></tr>`).join('')}</tbody>
    </table>`; }
    function listFirst(arr){ if(!arr||!arr.length) return '<div class="sub">no data</div>'; return `<table class='table'>
      <thead><tr><th>Hero</th><th class='num'>First picks</th><th class='num'>WR</th></tr></thead>
      <tbody>${arr.map(x=>`<tr><td class='col-hero'>${hero(hmeta(x.hid),22)} <span class='hname'></span></td><td class='num'>${x.count}</td><td class='num'>${fmtPct(x.wr)}</td></tr>`).join('')}</tbody>
    </table>`; }
    function listPairs(arr){ if(!arr||!arr.length) return '<div class="sub">no data</div>'; return `<table class='table'>
      <thead><tr><th>Opening pair</th><th class='num'>Games</th><th class='num'>WR</th></tr></thead>
      <tbody>${arr.map(x=>`<tr><td class='col-pair'>${hero(hmeta(x.a),22)} + ${hero(hmeta(x.b),22)}</td><td class='num'>${x.games}</td><td class='num'>${fmtPct(x.wr)}</td></tr>`).join('')}</tbody>
    </table>`; }
  // Toolbar with view switch + filters
  const mode = (opts && opts.mode) || 'contest';
  let curMode = ['contest','first','pairs'].includes(mode)? mode : 'contest';
  // persisted state
  let minGames = 0, minWR = 0; // used for 'pairs' only, but visible for others too
  if(persistKey){
    try{
      const saved = JSON.parse(localStorage.getItem(persistKey) || 'null');
      if(saved && typeof saved === 'object'){
        if(['contest','first','pairs'].includes(saved.curMode)) curMode = saved.curMode;
        if(Number.isFinite(saved.minGames)) minGames = Math.max(0, Math.floor(saved.minGames));
        if(Number.isFinite(saved.minWR)) minWR = Math.max(0, Math.min(100, saved.minWR));
      }
    }catch(_e){}
  }
  function seg(label, value){ return `<button class='seg' data-mode='${value}'>${label}</button>`; }
  function persist(){ if(!persistKey) return; try{ localStorage.setItem(persistKey, JSON.stringify({ curMode, minGames, minWR })); }catch(_e){} }
    root.innerHTML = `
      <div class='dv-draft'>
        <div class='toolbar'>
          ${seg('Contested','contest')}
          ${seg('First picks','first')}
          ${seg('Opening pairs','pairs')}
          <span class='switch'><label class='sub'>Min Games</label> <input type='number' id='dv-min-games' value='0' min='0' step='1' style='width:70px;background:transparent;color:var(--text);border:1px solid var(--border);border-radius:8px;padding:4px 6px'></span>
          <span class='switch'><label class='sub'>Min WR %</label> <input type='number' id='dv-min-wr' value='0' min='0' max='100' step='1' style='width:70px;background:transparent;color:var(--text);border:1px solid var(--border);border-radius:8px;padding:4px 6px'></span>
        </div>
        <div id='dv-draft-body'></div>
      </div>`;
    const body = root.querySelector('#dv-draft-body');
    function toCSV(){
      const tbl = root.querySelector('table'); if(!tbl) return '';
      const esc = (v)=>{ const s=String(v).replace(/\u00A0/g,' ').trim(); return /[",\n]/.test(s)? '"'+s.replace(/"/g,'""')+'"' : s; };
      const header = Array.from(tbl.tHead ? tbl.tHead.rows[0].cells : []).map(th=>th.textContent.trim());
      const rows = [];
      if(header.length) rows.push(header.map(esc).join(','));
      Array.from(tbl.tBodies[0].rows).forEach(tr=>{ const cols = Array.from(tr.cells).map(td=>td.textContent.replace(/\s+/g,' ').trim()); rows.push(cols.map(esc).join(',')); });
      return rows.join('\n');
    }
    function render(){
      if(!body) return;
      const tabs = root.querySelectorAll('.seg'); tabs.forEach(b=> b.classList.toggle('active', b.getAttribute('data-mode')===curMode));
      if(curMode==='contest') body.innerHTML = listContest(data.contest);
      else if(curMode==='first') body.innerHTML = listFirst(data.firstPicks);
      else {
        let arr = Array.isArray(data.openingPairs)? data.openingPairs.slice(): [];
        if(minGames>0) arr = arr.filter(x=> (x.games||0) >= minGames);
        if(minWR>0) arr = arr.filter(x=> ((x.wr||0)*100) >= minWR);
        body.innerHTML = listPairs(arr);
      }
      // enable simple sorting if host page sorter exists
      try{
        const table = root.querySelector('table'); if(!table) return;
        const thead = table.tHead; if(!thead) return;
        Array.from(thead.rows[0].cells).forEach((th, idx)=>{
          th.style.cursor='pointer';
          th.addEventListener('click', ()=>{
            if(window.sortTable){ const type = idx===0? 'text' : 'num'; window.sortTable(table, idx, type, !th.classList.contains('sorted-asc')); }
          });
        });
      }catch(_e){}
      // expose CSV getter on mount element so host page can export
      try { if(root){ root.__getDraftCSV = toCSV; } } catch(_e){}
    }
    render();
    // Wire handlers
    root.querySelectorAll('.seg').forEach(btn=> btn.addEventListener('click', ()=>{ curMode = btn.getAttribute('data-mode'); persist(); render(); }));
    const mg = root.querySelector('#dv-min-games'); const mw = root.querySelector('#dv-min-wr');
    // reflect persisted values in inputs
    try{ if(mg) mg.value = String(minGames); if(mw) mw.value = String(minWR); }catch(_e){}
    if(mg) mg.addEventListener('change', ()=>{ const v = Number(mg.value||0); minGames = isFinite(v)? Math.max(0, Math.floor(v)) : 0; persist(); render(); });
    if(mw) mw.addEventListener('change', ()=>{ const v = Number(mw.value||0); minWR = isFinite(v)? Math.max(0, Math.min(100, v)) : 0; persist(); render(); });
  }

  window.DraftViewer = { mount, compute };
})();

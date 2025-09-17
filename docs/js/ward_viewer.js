(function(){
  function esc(s){ return String(s||'').replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[c])); }
  function h(html){ const t=document.createElement('template'); t.innerHTML=html.trim(); return t.content.firstElementChild; }
  function injectBaseStyles(){
    if(document.getElementById('wv-base-styles')) return;
    const css = `
    .wv-wardgrid{display:grid;grid-template-columns:1.2fr .8fr;gap:14px;align-items:start}
    @media (max-width: 980px){.wv-wardgrid{grid-template-columns:1fr}}
    .wv-wardmap{margin:8px 0 0;position:relative;width:100%;aspect-ratio:1/1;min-height:300px;background:url('https://www.opendota.com/assets/images/dota2map/dota2map_full.jpg') center/cover no-repeat;border:1px solid var(--border,rgba(255,255,255,.08));border-radius:12px}
    .wv-wardmap svg{position:absolute;inset:0;width:100%;height:100%}
    .wv-wardmap .spot{fill:rgba(255,255,255,.18);stroke:rgba(255,255,255,.5);stroke-width:1;transition:all .15s}
    .wv-wardmap .spot.best{fill:rgba(52,211,153,.25);stroke:#34d399;stroke-width:1.5}
    .wv-wardmap .spot.worst{fill:rgba(255,107,107,.25);stroke:#ff6b6b;stroke-width:1.5}
    .wv-wardmap .spot.neutral{fill:rgba(255,255,255,.18);stroke:rgba(255,255,255,.45);stroke-width:1}
    .wv-wardmap.enhanced svg .spot.best.hl{filter:drop-shadow(0 0 8px rgba(52,211,153,.6));stroke-width:2 !important}
    .wv-wardmap.enhanced svg .spot.worst.hl{filter:drop-shadow(0 0 8px rgba(255,107,107,.6));stroke-width:2 !important}
    .wv-wardmap.enhanced.highlighting svg .spot:not(.hl){opacity:.28}
  .wv-wardmap svg .spot.pinned{stroke:#fbbf24 !important; fill:rgba(251,191,36,.18) !important; stroke-width:2 !important}
  .wv-wardmap svg .pindot{fill:#fbbf24; opacity:.95}
  /* tooltip */
  .wv-tooltip{position:absolute;pointer-events:none;z-index:5;min-width:160px;max-width:260px;background:rgba(15,23,42,.95);color:#e5ecf8;border:1px solid rgba(255,255,255,.12);border-radius:8px;padding:8px 10px;box-shadow:0 6px 18px rgba(0,0,0,.35);transform:translate(-50%, -110%);opacity:0;transition:opacity .12s}
  .wv-tooltip.show{opacity:1}
  .wv-tooltip .tt-title{font-weight:600;font-size:12px;margin:0 0 4px;opacity:.95}
  .wv-tooltip .tt-row{display:flex;gap:8px;align-items:center;font-size:12px;color:#c7d2e5}
  .wv-tooltip .tt-badge{display:inline-block;background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.12);border-radius:999px;padding:2px 8px;font-size:11px;color:#e5ecf8}
  .wv-tooltip .tt-meta{font-size:11px;color:#9aa7bd;margin-top:4px}
  /* controls */
  .wv-controls{display:grid;gap:8px 14px;align-items:start;background:rgba(255,255,255,.03);border:1px solid rgba(255,255,255,.08);border-radius:12px;padding:10px}
  @media (min-width: 900px){.wv-controls.wv-controls--top{grid-template-columns:auto auto 1fr}.wv-controls.wv-controls--tune{grid-template-columns:auto auto auto auto 1fr}.wv-controls.wv-controls--lists{grid-template-columns:1fr 1fr}}
  @media (max-width: 899px){.wv-controls{grid-template-columns:1fr}}
  .wv-label{font-size:11px;text-transform:uppercase;letter-spacing:.6px;color:var(--muted,#93a0b4);margin:0 0 4px}
    .wv-segmented{display:flex;flex-wrap:wrap;gap:6px;align-items:center}
    .wv-segmented .seg{padding:6px 10px;border:1px solid var(--border,rgba(255,255,255,.12));background:linear-gradient(180deg,rgba(255,255,255,.08),rgba(255,255,255,.03));color:var(--text,#eef3fb);border-radius:999px;font-size:12px;cursor:pointer}
    .wv-segmented .seg.active{background:linear-gradient(160deg,rgba(110,180,255,.35),rgba(110,175,255,.08));border-color:rgba(110,180,255,.55)}
  .wv-chiprow{display:flex;flex-wrap:wrap;gap:6px}
  .wv-chip{padding:5px 10px;border:1px solid var(--border,rgba(255,255,255,.12));background:rgba(255,255,255,.06);color:var(--text,#eef3fb);border-radius:999px;font-size:12px;cursor:pointer;white-space:nowrap}
  .wv-chip.active{background:linear-gradient(160deg,rgba(110,180,255,.35),rgba(110,175,255,.08));border-color:rgba(110,180,255,.55)}
  /* selectable lists */
  .wv-list{max-height:220px;overflow:auto;border:1px solid rgba(255,255,255,.08);border-radius:10px;background:linear-gradient(180deg,rgba(255,255,255,.03),rgba(255,255,255,.02));padding:6px}
  .wv-list .item{display:flex;align-items:center;justify-content:space-between;gap:8px;padding:6px 8px;border-radius:8px;cursor:pointer;color:var(--text);font-size:12px}
  .wv-list .item:hover{background:rgba(255,255,255,.06)}
  .wv-list .item.active{outline:2px solid rgba(109,166,255,.5);background:linear-gradient(180deg,rgba(109,166,255,.2),rgba(109,166,255,.08))}
  .wv-list .search{display:flex;gap:6px;margin:0 0 6px}
  .wv-list .search input{width:100%;padding:6px 8px;border-radius:8px;border:1px solid rgba(255,255,255,.12);background:rgba(255,255,255,.06);color:var(--text)}
    .wv-title{font-weight:600;margin:0 0 6px;font-size:15px;letter-spacing:.2px}
    .wv-sub{color:var(--muted,#93a0b4);font-size:12px}
    ul.wv-simple{list-style:none;margin:0;padding:0}
    ul.wv-simple li{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:8px 0;border-bottom:1px solid rgba(255,255,255,.06)}
    .wv-badge{display:inline-block;padding:4px 8px;border-radius:999px;background:rgba(255,255,255,.08);color:var(--text,#eef3fb);font-size:12px}
  .wv-chips{display:flex;flex-wrap:wrap;gap:6px}
  .wv-chipbtn{cursor:pointer}
    `;
    const style = document.createElement('style'); style.id='wv-base-styles'; style.textContent=css; document.head.appendChild(style);
  }
  function boundsFor(mc){ const asset = (mc && mc.major && mc.current && mc.major[mc.current]) ? mc.major[mc.current] : null; return {asset}; }
  function mount(host, cfg){
    injectBaseStyles();
    if(!host) return;
  const data = cfg && cfg.data || {}; const spots = Array.isArray(data.spots)? data.spots: [];
  const teams = Array.isArray(data.teams)? data.teams: [];
  const players = Array.isArray(data.players)? data.players: [];
    const mc = cfg && cfg.mapConf || {};
    const extras = (cfg && cfg.options && cfg.options.extras) || {};
    const showExtras = !!(cfg && cfg.options && cfg.options.showExtras);
    const IGNORE_PLAYER_PERSIST = !!(cfg && cfg.options && cfg.options.ignorePersistedPlayer);
  let state = { mode: (cfg && cfg.options && cfg.options.modeDefault) || 'best', team:'', player:'', time:'', overlay:true, grid:false, minCount:1, topN:'all', metric:'avg', includeZeroWorst:false, pins:[], pquery:'' };
    // URL/Storage helpers
    function getSP(){ try{ return new URLSearchParams(location.search); }catch(_e){ return new URLSearchParams(); } }
    function replaceUrl(sp){ try{ const url = location.pathname + (sp.toString()? ('?'+sp.toString()):'') + location.hash; history.replaceState(null, '', url); }catch(_e){} }
    const LS_KEY = {
  mode:'wv_mode', time:'wv_time', team:'wv_team', player:'wv_player', ov:'wv_ov', grid:'wv_grid', min:'wv_min', top:'wv_top', metric:'wv_metric', zworst:'wv_zworst', pins:'wv_pins', pquery:'wv_pq'
    };
    function readStorage(k, def){ try{ const v = localStorage.getItem(k); if(v===null || v===undefined) return def; return v; }catch(_e){ return def; } }
    function writeStorage(k, v){ try{ if(v===undefined || v===null || v===''){ localStorage.removeItem(k); } else { localStorage.setItem(k, String(v)); } }catch(_e){} }
    const ALLOWED_MODE = new Set(['best','worst']);
    const ALLOWED_TIME = new Set(['','early','mid','earlylate','late','superlate']);
    const ALLOWED_METRIC = new Set(['avg','median']);
    function hydrateState(){
      const sp = getSP();
      const urlMode = String(sp.get('wmode')||'');
      const urlTime = String(sp.get('wtime')||'');
      const urlTeam = String(sp.get('wteam')||'');
  const urlOv   = String(sp.get('wov')||'');
      const urlGrid = String(sp.get('wgrid')||'');
      const urlMin  = String(sp.get('wmin')||'');
      const urlTop  = String(sp.get('wtop')||'');
      const urlMet  = String(sp.get('wmetric')||'');
  const urlZw   = String(sp.get('wzw')||'');
  const urlPins = String(sp.get('wpins')||'');
  const urlPq   = String(sp.get('wpq')||'');
  const urlPl   = String(sp.get('wplayer')||'');
      const stMode = urlMode || readStorage(LS_KEY.mode, state.mode);
      const stTime = (urlTime!==''? urlTime : (sp.has('wtime')? '' : readStorage(LS_KEY.time, state.time)));
      const stTeam = (urlTeam!==''? urlTeam : (sp.has('wteam')? '' : readStorage(LS_KEY.team, state.team)));
  // Player: allow URL override, but optionally ignore persisted storage to default to "All"
  const stPl   = IGNORE_PLAYER_PERSIST
    ? (urlPl!=='' ? urlPl : '')
    : (urlPl!==''? urlPl : (sp.has('wplayer')? '' : readStorage(LS_KEY.player, state.player)));
      const stOv   = urlOv!==''? (urlOv==='1'?'1':(urlOv==='0'?'0':'')) : readStorage(LS_KEY.ov, state.overlay? '1':'0');
      const stGrid = urlGrid!==''? (urlGrid==='1'?'1':(urlGrid==='0'?'0':'')) : readStorage(LS_KEY.grid, state.grid? '1':'0');
      const stMin  = urlMin!==''? urlMin : readStorage(LS_KEY.min, String(state.minCount));
      const stTop  = urlTop!==''? urlTop : readStorage(LS_KEY.top, String(state.topN));
      const stMet  = urlMet!==''? urlMet : readStorage(LS_KEY.metric, state.metric);
  const stZw   = urlZw!==''? urlZw : readStorage(LS_KEY.zworst, state.includeZeroWorst? '1':'0');
  const stPins = (urlPins!==''? urlPins : readStorage(LS_KEY.pins, '')).trim();
  const stPq   = urlPq!==''? urlPq : readStorage(LS_KEY.pquery, '');
      if(ALLOWED_MODE.has(stMode)) state.mode = stMode;
      if(ALLOWED_TIME.has(stTime)) state.time = stTime;
      // team can be '', 'Radiant', 'Dire', or 'team:<id>'
      if(stTeam==='' || stTeam==='Radiant' || stTeam==='Dire' || /^team:\d+$/.test(stTeam)) state.team = stTeam;
  // player is numeric account id string or ''
  if(stPl==='' || /^\d+$/.test(stPl)) state.player = stPl;
      state.overlay = (stOv==='1');
      state.grid = (stGrid==='1');
      const m = Math.max(1, parseInt(stMin,10)||1); state.minCount = m;
      const topVal = (String(stTop).toLowerCase()==='all')? 'all' : (parseInt(stTop,10)||15);
      state.topN = (topVal==='all'|| (typeof topVal==='string' && topVal.toLowerCase()==='all'))? 'all' : Math.max(1, Number(topVal));
      if(ALLOWED_METRIC.has(stMet)) state.metric = stMet;
  state.includeZeroWorst = (String(stZw)==='1');
  // pins as array of spot keys
  state.pins = stPins ? stPins.split(',').filter(Boolean) : [];
  state.pquery = String(stPq||'');
    }
    function persistState(){
      // Write to URL (only include when different from default)
      const sp = getSP();
  const def = { mode:(cfg && cfg.options && cfg.options.modeDefault) || 'best', time:'', team:'', player:'', ov:'1', grid:'0', min:String(1), top:'all', metric:'avg', zw:'0', pins:'', pq:'' };
      function setOrRemove(key, val, defVal){ if(val===defVal || val==='' || val===null || val===undefined){ sp.delete(key); } else { sp.set(key, String(val)); } }
      setOrRemove('wmode', state.mode, def.mode);
      setOrRemove('wtime', state.time, def.time);
      setOrRemove('wteam', state.team, def.team);
  setOrRemove('wov', state.overlay? '1':'0', def.ov);
      setOrRemove('wgrid', state.grid? '1':'0', def.grid);
      setOrRemove('wmin', String(state.minCount), def.min);
      setOrRemove('wtop', state.topN==='all'? 'all' : String(state.topN), def.top);
      setOrRemove('wmetric', state.metric, def.metric);
      setOrRemove('wzw', state.includeZeroWorst? '1':'0', def.zw);
  setOrRemove('wplayer', state.player, def.player);
  setOrRemove('wpins', (state.pins||[]).join(','), def.pins);
  setOrRemove('wpq', state.pquery||'', def.pq);
      replaceUrl(sp);
      // LocalStorage
    writeStorage(LS_KEY.mode, state.mode);
    writeStorage(LS_KEY.time, state.time);
    writeStorage(LS_KEY.team, state.team);
  // Optionally avoid writing persisted player to keep default "All" in views that opt-in
  if(!IGNORE_PLAYER_PERSIST){ writeStorage(LS_KEY.player, state.player); }
      writeStorage(LS_KEY.ov, state.overlay? '1':'0');
      writeStorage(LS_KEY.grid, state.grid? '1':'0');
      writeStorage(LS_KEY.min, String(state.minCount));
      writeStorage(LS_KEY.top, state.topN==='all'? 'all' : String(state.topN));
      writeStorage(LS_KEY.metric, state.metric);
      writeStorage(LS_KEY.zworst, state.includeZeroWorst? '1':'0');
  writeStorage(LS_KEY.pins, (state.pins||[]).join(','));
  writeStorage(LS_KEY.pquery, state.pquery||'');
    }
    // Build DOM
    const root = h(`
      <section class="card">
        <h2 style="margin:0 0 8px;font-size:18px">Ward Spots</h2>
        <div class="wv-sub" style="margin-bottom:8px">Best / Worst placements by average lifetime.</div>
        <div class="wv-wardgrid">
          <div>
            <div class="wv-controls wv-controls--top" style="margin:6px 0 8px">
              <div>
                <div class="wv-label">View</div>
                <div class="tabs" id="wvTabs" style="margin:0">
                  <button class="tab" data-wmode="best">Best</button>
                  <button class="tab" data-wmode="worst">Worst</button>
                </div>
              </div>
              <div>
                <div class="wv-label">Time Window</div>
                <div id="wvTime" class="wv-segmented" role="tablist" aria-label="Time window">
                  <button class="seg" data-time="">All</button>
                  <button class="seg" data-time="early">Early</button>
                  <button class="seg" data-time="mid">Mid</button>
                  <button class="seg" data-time="earlylate">Early Late</button>
                  <button class="seg" data-time="late">Late</button>
                  <button class="seg" data-time="superlate">Super Late</button>
                </div>
              </div>
            </div>
            <div class="wv-controls wv-controls--lists" style="margin:-4px 0 8px">
              <div>
                <div class="wv-label">Team</div>
                <div id="wvTeams" class="wv-list" role="listbox" aria-label="Teams"></div>
              </div>
              <div>
                <div class="wv-label">Player (observer placements)</div>
                <div id="wvPlayersPick" class="wv-list" role="listbox" aria-label="Players">
                  <div class="search"><input type="text" id="wvPq" placeholder="Search players…" value=""></div>
                  <div id="wvPlayersInner"></div>
                </div>
              </div>
            </div>
            <div class="wv-controls wv-controls--tune" style="margin:4px 0 8px">
              <div>
                <div class="wv-label">Min occ.</div>
                <div id="wvMin" class="wv-segmented">
                  <button class="seg" data-min="1">1</button>
                  <button class="seg" data-min="2">2</button>
                  <button class="seg" data-min="3">3</button>
                  <button class="seg" data-min="5">5</button>
                </div>
              </div>
              <div>
                <div class="wv-label">Top</div>
                <div id="wvTop" class="wv-segmented">
                  <button class="seg" data-top="10">10</button>
                  <button class="seg" data-top="15">15</button>
                  <button class="seg" data-top="25">25</button>
                  <button class="seg" data-top="50">50</button>
                  <button class="seg" data-top="all">All</button>
                </div>
              </div>
              <div>
                <div class="wv-label">Metric</div>
                <div id="wvMetric" class="wv-segmented">
                  <button class="seg" data-metric="avg">Avg</button>
                  <button class="seg" data-metric="median">Median</button>
                </div>
              </div>
              <div style="align-self:end;display:flex;gap:12px;justify-content:flex-end">
                <label class="wv-sub"><input type="checkbox" id="wvZeroWorst" style="vertical-align:middle;margin-right:6px">Include 0s worst</label>
              </div>
            </div>
            <div class="wv-wardmap enhanced" id="wvMap"><svg></svg><div class="wv-tooltip" id="wvTip" role="tooltip" aria-hidden="true"></div></div>
            <div class="wv-sub" id="wvPinsBar" style="margin-top:6px"></div>
            <div class="wv-sub" id="wvLegend" style="margin-top:6px">Green = Best avg lifetime, Red = Worst.</div>
            <div class="wv-sub" id="wvStatus" style="margin-top:4px;opacity:.85"></div>
            <div style="display:flex;gap:10px;align-items:center;margin-top:6px">
              <label style="font-size:12px;color:var(--muted)"><input type="checkbox" id="wvOv" checked style="vertical-align:middle;margin-right:6px">Overlay</label>
              <label style="font-size:12px;color:var(--muted)"><input type="checkbox" id="wvGrid" style="vertical-align:middle;margin-right:6px">Grid</label>
            </div>
            ${showExtras? `<div style="margin-top:10px">
              <div class="wv-title" style="margin:0 0 6px">Players</div>
              <div id="wvPlayers" class="wv-sub">(empty)</div>
            </div>`:''}
          </div>
          <div>
            <div style="display:flex;gap:12px;flex-direction:column;margin-top:6px">
              <div>
                <div class="wv-title" style="margin:0 0 6px">Best Spots</div>
                <div id="wvBest" class="wv-sub">(empty)</div>
              </div>
              <div>
                <div class="wv-title" style="margin:0 0 6px">Worst Spots</div>
                <div id="wvWorst" class="wv-sub">(empty)</div>
              </div>
              ${showExtras && (cfg && cfg.options && cfg.options.showLongest!==false)? `<div>
                <div class="wv-title" style="margin:0 0 6px">Longest-lived</div>
                <div id="wvLongest" class="wv-sub">(empty)</div>
              </div>`:''}
            </div>
          </div>
        </div>
      </section>`);
    host.innerHTML=''; host.appendChild(root);
    // Read initial state from URL/localStorage
    hydrateState();
    // Set default active tabs
    root.querySelectorAll('#wvTabs .tab').forEach(b=> b.classList.toggle('active',(b.dataset.wmode||'')===state.mode));
  function setActiveTime(){ const wrap=root.querySelector('#wvTime'); if(!wrap) return; wrap.querySelectorAll('.seg').forEach(b=> b.classList.toggle('active',(b.dataset.time||'')===state.time)); }
  function setActiveMin(){ const wrap=root.querySelector('#wvMin'); if(!wrap) return; wrap.querySelectorAll('.seg').forEach(b=> b.classList.toggle('active', Number(b.getAttribute('data-min')||'0')===Number(state.minCount))); }
  function setActiveTop(){ const wrap=root.querySelector('#wvTop'); if(!wrap) return; wrap.querySelectorAll('.seg').forEach(b=> b.classList.toggle('active', (b.getAttribute('data-top')||'')=== (state.topN==='all'?'all':String(state.topN)))); }
  function setActiveMetric(){ const wrap=root.querySelector('#wvMetric'); if(!wrap) return; wrap.querySelectorAll('.seg').forEach(b=> b.classList.toggle('active', (b.getAttribute('data-metric')||'')===state.metric)); }
    setActiveTime();
  setActiveMin();
  setActiveTop();
  setActiveMetric();
    // Build team and player picklists
    (function(){
      const tWrap=root.querySelector('#wvTeams'); const pWrap=root.querySelector('#wvPlayersPick'); if(!tWrap) return;
      const tItems=[{v:'',label:'All'},{v:'Radiant',label:'Radiant'},{v:'Dire',label:'Dire'}];
      teams.slice().sort((a,b)=> String(a.name||'').localeCompare(String(b.name||''))).forEach(t=> tItems.push({v:`team:${t.id}`,label:String(t.name||`Team ${t.id}`)}));
      function renderTeams(){ tWrap.innerHTML = tItems.map(c=>`<div class='item ${((c.v||'')===state.team?'active':'')}' role='option' data-team='${esc(c.v)}'><span>${esc(c.label)}</span>${((c.v||'')===state.team?"<span class='wv-badge'>selected</span>":'')}</div>`).join(''); }
      function normalizedPlayers(){
        // Build set of AIDs that actually placed observers (from samples)
        const placerSet = new Set();
        for(const s of spots){ const sm = Array.isArray(s.samples)? s.samples: []; for(const o of sm){ const aid = Number(o.aid||0); if(aid>0) placerSet.add(aid); } }
        // Prefer provided players, but filter by placerSet
        const base = Array.isArray(players)? players: [];
  let list = base.length>0 ? base.slice() : Array.from(placerSet.values()).map(aid=>({id:aid, name:`Player ${aid}`}));
        // Filter out players with zero placements
        list = list.filter(p=> placerSet.has(Number(p.id||p.account_id||0)));
        return list;
      }
      function renderPlayers(){ if(!pWrap) return; const pInner = pWrap.querySelector('#wvPlayersInner'); const pq = (state.pquery||'').toLowerCase(); const list=[{id:'',name:'All'}].concat(normalizedPlayers().slice().sort((a,b)=> String(a.name||'').localeCompare(String(b.name||''))).map(p=>({id:String(p.id||p.account_id||''), name:String(p.name||`Player ${p.id||p.account_id||''}`)})).filter(c=> !pq || String(c.name||'').toLowerCase().includes(pq) || String(c.id||'').includes(pq)));
        if(pInner){ pInner.innerHTML = list.map(c=>`<div class='item ${((String(c.id||'')===String(state.player))?'active':'')}' role='option' data-player='${esc(String(c.id||''))}'><span>${esc(c.name)}</span>${(String(c.id||'')===String(state.player)?"<span class='wv-badge'>selected</span>":'')}</div>`).join(''); }
        else { pWrap.innerHTML = list.map(c=>`<div class='item ${((String(c.id||'')===String(state.player))?'active':'')}' role='option' data-player='${esc(String(c.id||''))}'><span>${esc(c.name)}</span>${(String(c.id||'')===String(state.player)?"<span class='wv-badge'>selected</span>":'')}</div>`).join(''); }
      }
      renderTeams(); renderPlayers();
      tWrap.addEventListener('click', e=>{ const it=e.target.closest('.item'); if(!it) return; state.team = it.getAttribute('data-team')||''; renderTeams(); persistState(); render(); });
      if(pWrap){
        const pq = pWrap.querySelector('#wvPq'); if(pq){ pq.value = state.pquery||''; pq.addEventListener('input', ()=>{ state.pquery = String(pq.value||''); persistState(); renderPlayers(); }); }
        pWrap.addEventListener('click', e=>{ const it=e.target.closest('.item'); if(!it) return; state.player = it.getAttribute('data-player')||''; renderPlayers(); persistState(); render(); });
      }
    })();
    // Bind tabs/time
  root.querySelectorAll('#wvTabs .tab').forEach(b=> b.addEventListener('click',()=>{ state.mode = b.dataset.wmode||'best'; root.querySelectorAll('#wvTabs .tab').forEach(x=> x.classList.toggle('active', x===b)); persistState(); render(); }));
  root.querySelector('#wvTime').addEventListener('click',(e)=>{ const btn=e.target.closest('button.seg'); if(!btn) return; state.time = btn.getAttribute('data-time')||''; setActiveTime(); persistState(); render(); });
  root.querySelector('#wvMin').addEventListener('click',(e)=>{ const btn=e.target.closest('button.seg'); if(!btn) return; const v = Math.max(1, parseInt(btn.getAttribute('data-min')||'1',10)); state.minCount = v; setActiveMin(); persistState(); render(); });
  root.querySelector('#wvTop').addEventListener('click',(e)=>{ const btn=e.target.closest('button.seg'); if(!btn) return; const t = String(btn.getAttribute('data-top')||'15'); state.topN = (t.toLowerCase()==='all')? 'all' : Math.max(1, parseInt(t,10)||15); setActiveTop(); persistState(); render(); });
  root.querySelector('#wvMetric').addEventListener('click',(e)=>{ const btn=e.target.closest('button.seg'); if(!btn) return; const m = String(btn.getAttribute('data-metric')||'avg'); if(ALLOWED_METRIC.has(m)){ state.metric = m; setActiveMetric(); persistState(); render(); } });
    const svg = root.querySelector('#wvMap svg');
    function ensureBG(){ try{ const asset = (mc && mc.major && mc.current && mc.major[mc.current]) ? mc.major[mc.current] : null; let src = asset && asset.src ? asset.src : null; if(!src && mc && mc.default){ src = mc.default; } const el=root.querySelector('#wvMap'); if(src && el){ el.style.backgroundImage = `url('${src}')`; } }catch(_e){} }
    ensureBG();
    // Initialize overlay/grid from state
    try{ const ov=root.querySelector('#wvOv'); if(ov){ ov.checked = !!state.overlay; svg.style.display = ov.checked? '':'none'; } }catch(_e){}
  try{ const gr=root.querySelector('#wvGrid'); if(gr){ gr.checked = !!state.grid; } }catch(_e){}
  try{ const zw=root.querySelector('#wvZeroWorst'); if(zw){ zw.checked = !!state.includeZeroWorst; zw.addEventListener('change',()=>{ state.includeZeroWorst = !!zw.checked; persistState(); render(); }); } }catch(_e){}
    root.querySelector('#wvOv').addEventListener('change',()=>{ state.overlay = !!root.querySelector('#wvOv').checked; svg.style.display = state.overlay? '':'none'; persistState(); });
    root.querySelector('#wvGrid').addEventListener('change',()=>{ state.grid = !!root.querySelector('#wvGrid').checked; persistState(); render(); });
    function timeWindow(){ switch(state.time){ case 'early': return {min:0,max:600,label:'0-10m'}; case 'mid': return {min:600,max:2100,label:'10-35m'}; case 'earlylate': return {min:2100,max:3000,label:'35-50m'}; case 'late': return {min:3000,max:4500,label:'50-75m'}; case 'superlate': return {min:4500,max:Infinity,label:'75m+'}; default: return {min:-Infinity,max:Infinity,label:'all'}; } }
    function pickCounts(s){
      const val=state.team; const tw=timeWindow(); const pid = state.player ? Number(state.player) : 0;
      if(Array.isArray(s.samples) && s.samples.length){ let cnt=0,tot=0; const lifes=[]; for(const sm of s.samples){ const t=Number(sm.t||0); if(!(t>=tw.min && t<tw.max)) continue; if(pid>0 && Number(sm.aid||0)!==pid) continue; if(!val || val==='') { cnt++; const life=Number(sm.life||0); tot+=life; lifes.push(life); continue; } if(val==='Radiant' || val==='Dire'){ if(String(sm.side||'')===val){ cnt++; const life=Number(sm.life||0); tot+=life; lifes.push(life); } continue; } if(val.startsWith('team:')){ const id=Number(val.split(':')[1]||0); if(Number(sm.teamId||0)===id){ cnt++; const life=Number(sm.life||0); tot+=life; lifes.push(life); } }
        }
        return {count:cnt,total:tot,lifes};
      }
      // Without samples, only coarse aggregates are available; when filtering by player, return 0
      if(pid>0){ return {count:0,total:0,lifes:null}; }
      if(!val){ return {count:s.count||0,total:s.total||0,lifes:null}; }
      if(val==='Radiant' || val==='Dire'){ const side=s.bySide && s.bySide[val] || {count:0,total:0}; return {count:side.count||0, total:side.total||0, lifes:null}; }
      if(val.startsWith('team:')){ const id=Number(val.split(':')[1]||0); const t=s.byTeam && s.byTeam[id]; return {count:(t&&t.count)||0,total:(t&&t.total)||0,lifes:null}; }
      return {count:s.count||0,total:s.total||0,lifes:null};
    }
    function median(arr){ if(!Array.isArray(arr) || !arr.length) return 0; const a=arr.slice().sort((x,y)=>x-y); const n=a.length; const mid=n>>1; return n%2? a[mid] : Math.floor((a[mid-1]+a[mid])/2); }
    function setPinsBar(){
      const bar = root.querySelector('#wvPinsBar'); if(!bar) return;
      const pins = Array.isArray(state.pins)? state.pins: [];
      if(!pins.length){ bar.innerHTML = `<span>No pins</span>`; return; }
      const chips = pins.map(k=>`<span class='wv-badge wv-chipbtn' data-unpin='${esc(k)}'>${esc(k)} ✕</span>`).join(' ');
      bar.innerHTML = `<div class='wv-chips'>${chips}<span style='flex:1'></span><button class='tab' id='wvCopyPins'>Copy link</button><button class='tab' id='wvClearPins'>Clear</button></div>`;
      bar.querySelectorAll('[data-unpin]').forEach(btn=> btn.addEventListener('click', ()=>{ const k=btn.getAttribute('data-unpin'); state.pins = (state.pins||[]).filter(x=> x!==k); persistState(); render(); }));
      const copy = bar.querySelector('#wvCopyPins'); if(copy){ copy.addEventListener('click', ()=>{ try{ const sp=new URLSearchParams(location.search); sp.set('wpins', (state.pins||[]).join(',')); navigator.clipboard.writeText(location.pathname + '?' + sp.toString() + location.hash); copy.textContent='Copied'; setTimeout(()=> copy.textContent='Copy link', 1000); }catch(_e){} }); }
      const clr = bar.querySelector('#wvClearPins'); if(clr){ clr.addEventListener('click', ()=>{ state.pins=[]; persistState(); render(); }); }
    }
    function togglePin(spotKey){ spotKey=String(spotKey||''); if(!spotKey) return; const arr = state.pins||[]; const idx = arr.indexOf(spotKey); if(idx===-1){ arr.push(spotKey); } else { arr.splice(idx,1); } state.pins = arr; persistState(); render(); }
    function isPinned(spotKey){ return (state.pins||[]).includes(String(spotKey||'')); }
    function render(){
      // derive best/worst
      const derived = spots.map(s=>{ const v=pickCounts(s); const avg = v.count? Math.floor(v.total/v.count):0; const med = (v.lifes && v.lifes.length)? median(v.lifes) : 0; const chosen = (state.metric==='median')? med : avg; return {spot:s.spot,x:s.x,y:s.y,count:v.count,avgSeconds:chosen,avg:avg,median:med}; });
      const perf = derived.filter(s=> s.count>=Number(state.minCount||1));
      let best=[], worst=[], all=derived;
      const topN = (state.topN==='all')? Infinity : Number(state.topN||15);
      if(state.mode==='best'){
        best = perf.slice().sort((a,b)=> (b.avgSeconds-a.avgSeconds)||(b.count-a.count)).slice(0, topN);
      } else {
        const wsrc = perf.slice().filter(s=> state.includeZeroWorst ? true : (s.avgSeconds||0)>0);
        worst = wsrc.sort((a,b)=> (a.avgSeconds-b.avgSeconds)||(b.count-a.count)).slice(0, topN);
      }
      // map render
      svg.innerHTML='';
      const asset = (mc && mc.major && mc.current && mc.major[mc.current]) ? mc.major[mc.current] : null;
      const hasBounds = asset && asset.minX!=null && asset.maxX!=null && asset.minY!=null && asset.maxY!=null && asset.maxX>asset.minX && asset.maxY>asset.minY;
      const invertY = !!(asset && asset.invertY);
      const observedMax = (best.concat(worst).concat(all)).reduce((acc,s)=>({mx:Math.max(acc.mx, Number(s.x||0)), my:Math.max(acc.my, Number(s.y||0))}), {mx:0,my:0});
      const dynScale = Math.max(1, Number(asset && asset.scale || 0), observedMax.mx, observedMax.my, Number(mc && mc.defaultScale || 0));
      const cellUnits = Number((asset && asset.cellUnits) || (mc && mc.defaultCellUnits) || 128);
      const obsUnits  = Number((asset && asset.obsRadiusUnits) || (mc && mc.defaultObsRadiusUnits) || 1600);
      let obsPct = (asset && asset.obsRadiusPct!=null) ? Number(asset.obsRadiusPct)
             : (mc && mc.defaultObsRadiusPct!=null ? Number(mc.defaultObsRadiusPct) : NaN);
      if(!isFinite(obsPct)){
        const denom = hasBounds ? (cellUnits * (Number(asset && asset.maxX)||0 - Number(asset && asset.minX)||0)) : (cellUnits * dynScale);
        const calc = denom>0 ? (obsUnits/denom)*100 : NaN;
        obsPct = isFinite(calc) && calc>0 ? Math.round(calc*100)/100 : 10;
      }
  function norm(X,Y){ let cx0, cy0; if(hasBounds){ const minX=asset.minX, maxX=asset.maxX, minY=asset.minY, maxY=asset.maxY; const clX=Math.max(minX,Math.min(maxX,Number(X||0))); const clY=Math.max(minY,Math.min(maxY,Number(Y||0))); cx0=(clX-minX)/(maxX-minX); cy0=(clY-minY)/(maxY-minY); if(invertY) cy0=1-cy0; } else { cx0=Math.max(0,Math.min(dynScale,Number(X||0)))/dynScale; cy0=Math.max(0,Math.min(dynScale,Number(Y||0)))/dynScale; if(invertY) cy0=1-cy0; } return {cx: Math.round(cx0*10000)/100, cy: Math.round(cy0*10000)/100}; }
  function addSpot(list, cls){ list.forEach(s=>{ const {cx,cy}=norm(s.x,s.y); const key=String(s.spot||''); const big=document.createElementNS('http://www.w3.org/2000/svg','circle'); big.setAttribute('cx',cx+'%'); big.setAttribute('cy',cy+'%'); big.setAttribute('r',String(obsPct)); let klass='spot '+cls; if(isPinned(key)) klass+=' pinned'; big.setAttribute('class',klass); big.setAttribute('data-spot',key); big.setAttribute('data-avg',String(s.avg||0)); big.setAttribute('data-median',String(s.median||0)); big.setAttribute('data-count',String(s.count||0)); big.setAttribute('data-cx',String(cx)); big.setAttribute('data-cy',String(cy)); svg.appendChild(big); const dot=document.createElementNS('http://www.w3.org/2000/svg','circle'); dot.setAttribute('cx',cx+'%'); dot.setAttribute('cy',cy+'%'); dot.setAttribute('r', isPinned(key)? '1.6' : '1.0'); dot.setAttribute('class','pindot'); const stroke = isPinned(key)? '#fbbf24' : (cls==='best'? '#34d399' : (cls==='worst'? '#ff6b6b' : 'rgba(255,215,0,0.85)')); dot.setAttribute('fill',stroke); dot.setAttribute('opacity','0.95'); svg.appendChild(dot); big.addEventListener('click', ()=> togglePin(key)); dot.addEventListener('click', ()=> togglePin(key)); }); }
      if(state.mode==='best') addSpot(best,'best'); else addSpot(worst,'worst');
      if(root.querySelector('#wvGrid').checked){ const g=document.createElementNS('http://www.w3.org/2000/svg','g'); for(let i=0;i<=10;i++){ const p=i*10; const v1=document.createElementNS('http://www.w3.org/2000/svg','line'); v1.setAttribute('x1',p+'%'); v1.setAttribute('y1','0%'); v1.setAttribute('x2',p+'%'); v1.setAttribute('y2','100%'); v1.setAttribute('stroke','rgba(255,255,255,.08)'); v1.setAttribute('stroke-width','0.3'); g.appendChild(v1); const v2=document.createElementNS('http://www.w3.org/2000/svg','line'); v2.setAttribute('x1','0%'); v2.setAttribute('y1',p+'%'); v2.setAttribute('x2','100%'); v2.setAttribute('y2',p+'%'); v2.setAttribute('stroke','rgba(255,255,255,.08)'); v2.setAttribute('stroke-width','0.3'); g.appendChild(v2);} svg.insertBefore(g, svg.firstChild); }
  const st = root.querySelector('#wvStatus'); if(st){ const teamLbl = state.team||'All'; const playerLbl = state.player? ` · player:${state.player}` : ''; st.textContent = `spots:${spots.length} | r=${obsPct}% · bounds:${hasBounds?'yes':'no'} invY:${invertY?'yes':'no'} | time:${timeWindow().label} | team:${teamLbl}${playerLbl} | min>=${state.minCount} · top=${state.topN}`; }
      // lists
  function listify(arr){ if(!arr.length) return `<div class='wv-sub'>No data</div>`; return `<ul class='wv-simple'>`+arr.map((s,idx)=>{ const mm = s.avgSeconds? Math.floor((s.avgSeconds||0)/60):0; const ss = s.avgSeconds? (s.avgSeconds%60):0; const coords = (s.spot||'').replace(/\[|\]|\s/g,''); const pin = isPinned(s.spot) ? 'Unpin' : 'Pin'; return `<li data-spot='${s.spot||''}'><span style='display:flex;align-items:center;gap:8px'><span class='wv-badge' style='min-width:54px;text-align:center'>Ward ${idx+1}</span><span class='wv-sub' style='opacity:.8'>${coords}</span></span><span style='display:flex;gap:6px'>${s.avgSeconds!==undefined?`<span class='wv-badge'>avg ${mm}m ${ss}s</span>`:''}${s.count? `<span class='wv-badge'>x${s.count}</span>`:''}<button class='tab' data-pin='${esc(String(s.spot||''))}'>${pin}</button></span></li>`; }).join('')+`</ul>`; }
      const bestEl=root.querySelector('#wvBest'); if(bestEl) bestEl.innerHTML = listify(best);
      const worstEl=root.querySelector('#wvWorst'); if(worstEl) worstEl.innerHTML = listify(worst);
      // extras
      if(showExtras){ const pl=extras.wardPlayers||{}; const divP=root.querySelector('#wvPlayers'); if(divP){ divP.innerHTML = `<div class='wv-sub' style='opacity:.9'>Most Placed</div>` + (Array.isArray(pl.mostPlaced)? `<ul class='wv-simple'>${pl.mostPlaced.map(p=>`<li><span>${esc(p.name||'')}</span><span class='wv-badge'>x${p.count||0}</span></li>`).join('')}</ul>`:`<div class='wv-sub'>no data</div>`) + `<div class='wv-sub' style='opacity:.9;margin-top:6px'>Most Dewards</div>` + (Array.isArray(pl.mostDewards)? `<ul class='wv-simple'>${pl.mostDewards.map(p=>`<li><span>${esc(p.name||'')}</span><span class='wv-badge'>x${p.count||0}</span></li>`).join('')}</ul>`:`<div class='wv-sub'>no data</div>`) + `<div class='wv-sub' style='opacity:.9;margin-top:6px'>Longest Avg</div>` + (Array.isArray(pl.longestAvg)? `<ul class='wv-simple'>${pl.longestAvg.map(p=>{ const sec=Number(p.avgSeconds||0); const mm=Math.floor(sec/60), ss=sec%60; return `<li><span>${esc(p.name||'')}</span><span class='wv-badge'>${mm}m ${ss}s avg</span><span class='wv-badge'>n=${p.samples||0}</span></li>`; }).join('')}</ul>`:`<div class='wv-sub'>no data</div>`); }
        const lg=root.querySelector('#wvLongest'); if(lg){ const arr=extras.wardLongest||[]; lg.innerHTML = Array.isArray(arr)? `<ul class='wv-simple'>${arr.map(o=>{ const mx=Number(o.maxSeconds||0); const mm=Math.floor(mx/60), ss=mx%60; return `<li><span>${esc(o.spot||'')}</span><span class='wv-badge'>${mm}m ${ss}s</span><span class='wv-badge'>x${o.count||0}</span></li>`; }).join('')}</ul>` : `<div class='wv-sub'>no data</div>`; }
      }
      // hover
  const tip = root.querySelector('#wvTip');
      function fmtMMSS(secs){ const s=Math.max(0,Math.floor(Number(secs||0))); const m=Math.floor(s/60); const r=s%60; return `${m}m ${r}s`; }
  function showTipFromSpot(el){ if(!tip) return; const avg=Number(el.getAttribute('data-avg')||0); const med=Number(el.getAttribute('data-median')||0); const cnt=Number(el.getAttribute('data-count')||0); const label=String(el.getAttribute('data-spot')||''); const timeLbl = timeWindow().label; const teamLbl = state.team||'All'; tip.innerHTML = `<div class='tt-title'>${esc(label)}</div><div class='tt-row'><span class='tt-badge'>Avg ${fmtMMSS(avg)}</span><span class='tt-badge'>Median ${fmtMMSS(med)}</span><span class='tt-badge'>n=${cnt}</span></div><div class='tt-meta'>${esc(teamLbl)} · ${esc(timeLbl)}</div>`; tip.classList.add('show'); tip.setAttribute('aria-hidden','false'); }
      function moveTip(evt){ if(!tip) return; const box = root.querySelector('#wvMap').getBoundingClientRect(); let x = evt.clientX - box.left; let y = evt.clientY - box.top; x = Math.max(8, Math.min(box.width-8, x)); y = Math.max(8, Math.min(box.height-8, y)); tip.style.left = x+'px'; tip.style.top = y+'px'; }
      function hideTip(){ if(!tip) return; tip.classList.remove('show'); tip.setAttribute('aria-hidden','true'); }
      svg.querySelectorAll('.spot').forEach(n=>{
        n.addEventListener('mouseenter', (e)=>{ showTipFromSpot(n); });
        n.addEventListener('mousemove', moveTip);
        n.addEventListener('mouseleave', hideTip);
      });
      function bindList(id){ const c=root.querySelector(id); if(!c) return; c.querySelectorAll('li[data-spot]').forEach(li=>{ li.addEventListener('mouseenter',()=>{ const spot=li.getAttribute('data-spot'); svg.closest('.wv-wardmap').classList.add('highlighting'); svg.querySelectorAll('.spot').forEach(n=>{ if(n.getAttribute('data-spot')===spot) n.classList.add('hl'); }); }); li.addEventListener('mouseleave',()=>{ svg.closest('.wv-wardmap').classList.remove('highlighting'); svg.querySelectorAll('.spot.hl').forEach(n=> n.classList.remove('hl')); }); }); }
  bindList('#wvBest'); bindList('#wvWorst');
  // Pin buttons in lists
  root.querySelectorAll('[data-pin]').forEach(btn=>{ btn.addEventListener('click', (e)=>{ e.stopPropagation(); const key=btn.getAttribute('data-pin'); togglePin(key); }); });
  // Update pins bar
  setPinsBar();
    }
    // initial render
  // Persist initial state (to reflect defaults/params)
  persistState();
  render();
  }
  window.WardViewer = { mount };
})();

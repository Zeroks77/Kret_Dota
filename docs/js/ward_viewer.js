(function(){
  function esc(s){ return String(s||'').replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[c])); }
  function h(html){ const t=document.createElement('template'); t.innerHTML=html.trim(); return t.content.firstElementChild; }
  function injectBaseStyles(){
    if(document.getElementById('wv-base-styles')) return;
    const css = `
  .wv-wardgrid{display:grid;grid-template-columns:1.2fr .8fr;gap:10px;align-items:start}
    @media (max-width: 980px){.wv-wardgrid{grid-template-columns:1fr}}
  .wv-wardmap{margin:6px 0 0;position:relative;width:100%;aspect-ratio:1/1;min-height:260px;background:url('https://www.opendota.com/assets/images/dota2map/dota2map_full.jpg') center/cover no-repeat;border:1px solid var(--border,rgba(255,255,255,.08));border-radius:12px}
    .wv-wardmap svg{position:absolute;inset:0;width:100%;height:100%}
    .wv-wardmap .spot{fill:rgba(255,255,255,.18);stroke:rgba(255,255,255,.5);stroke-width:1;transition:all .15s}
    .wv-wardmap .spot.best{fill:rgba(52,211,153,.25);stroke:#34d399;stroke-width:1.5}
    .wv-wardmap .spot.worst{fill:rgba(255,107,107,.25);stroke:#ff6b6b;stroke-width:1.5}
  .wv-wardmap .spot.neutral{fill:rgba(255,255,255,.18);stroke:rgba(255,255,255,.45);stroke-width:1}
  /* danger emphasis */
  .wv-wardmap .spot.danger-high{fill:rgba(255,99,99,.35);stroke:#ff5c5c;stroke-width:2}
  .wv-wardmap .spot.danger-veryhigh{fill:rgba(255,45,45,.45);stroke:#ff2d2d;stroke-width:2.2;filter:drop-shadow(0 0 10px rgba(255,64,64,.65))}
    .wv-wardmap.enhanced svg .spot.best.hl{filter:drop-shadow(0 0 8px rgba(52,211,153,.6));stroke-width:2 !important}
    .wv-wardmap.enhanced svg .spot.worst.hl{filter:drop-shadow(0 0 8px rgba(255,107,107,.6));stroke-width:2 !important}
    .wv-wardmap.enhanced.highlighting svg .spot:not(.hl){opacity:.28}
  .wv-wardmap svg .spot.pinned{stroke:#fbbf24 !important; fill:rgba(251,191,36,.18) !important; stroke-width:2 !important}
  .wv-wardmap svg .pindot{fill:#fbbf24; opacity:.95}
  /* tooltip */
  .wv-tooltip{position:absolute;pointer-events:none;z-index:5;min-width:150px;max-width:240px;background:rgba(15,23,42,.95);color:#e5ecf8;border:1px solid rgba(255,255,255,.12);border-radius:8px;padding:6px 8px;box-shadow:0 6px 18px rgba(0,0,0,.35);transform:translate(-50%, -110%);opacity:0;transition:opacity .12s}
  .wv-tooltip.show{opacity:1}
  .wv-tooltip .tt-title{font-weight:600;font-size:12px;margin:0 0 4px;opacity:.95}
  .wv-tooltip .tt-row{display:flex;gap:8px;align-items:center;font-size:12px;color:#c7d2e5}
  .wv-tooltip .tt-badge{display:inline-block;background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.12);border-radius:999px;padding:2px 8px;font-size:11px;color:#e5ecf8}
  .wv-tooltip .tt-meta{font-size:11px;color:#9aa7bd;margin-top:4px}
  /* controls */
  .wv-controls{display:grid;gap:8px 12px;align-items:start;background:rgba(255,255,255,.03);border:1px solid rgba(255,255,255,.08);border-radius:10px;padding:10px}
  /* flyout */
  .wv-flyout{position:relative;display:inline-block}
  .wv-flyout .wv-flyout-menu{position:absolute;top:100%;right:0;background:rgba(17,25,40,.98);border:1px solid rgba(255,255,255,.12);border-radius:10px;padding:8px;box-shadow:0 8px 22px rgba(0,0,0,.45);min-width:180px;margin-top:6px;display:none;z-index:10}
  .wv-flyout.open .wv-flyout-menu{display:block}
  .wv-flyout .wv-flyout-menu .seg{display:block;width:100%;text-align:left;margin:0 0 6px}
  .wv-flyout .wv-flyout-menu .seg:last-child{margin-bottom:0}
  .wv-slider{position:relative;padding:6px 4px 0}
  .wv-slider-track{height:6px;background:linear-gradient(180deg,rgba(255,255,255,.18),rgba(255,255,255,.10));border:1px solid rgba(255,255,255,.14);border-radius:999px;position:relative;margin:12px 8px 0}
  .wv-slider-thumb{position:absolute;top:0;left:0;width:14px;height:14px;background:linear-gradient(180deg,rgba(110,180,255,.9),rgba(110,175,255,.6));border:1px solid rgba(110,180,255,.8);border-radius:50%;box-shadow:0 2px 6px rgba(0,0,0,.45),0 0 0 2px rgba(110,180,255,.25);transform:translate(-50%,-50%);cursor:pointer}
  .wv-slider-thumb:focus{outline:2px solid rgba(110,180,255,.6);outline-offset:2px}
  .wv-slider-labels{display:flex;justify-content:space-between;gap:6px;margin:8px 8px 0}
  .wv-slider-labels .seg{flex:1;text-align:center;padding:6px 10px;border:1px solid rgba(255,255,255,.14);border-radius:8px;background:linear-gradient(180deg,rgba(255,255,255,.08),rgba(255,255,255,.03));color:#eef3fb;cursor:pointer;font-size:11px;line-height:1}
  .wv-slider-labels .seg:hover{border-color:rgba(255,255,255,.22);background:linear-gradient(180deg,rgba(255,255,255,.12),rgba(255,255,255,.04))}
  .wv-slider-labels .seg:first-child{border-top-right-radius:6px;border-bottom-right-radius:6px;border-top-left-radius:10px;border-bottom-left-radius:10px}
  .wv-slider-labels .seg:last-child{border-top-left-radius:6px;border-bottom-left-radius:6px;border-top-right-radius:10px;border-bottom-right-radius:10px}
  .wv-slider-labels .seg.active{background:linear-gradient(160deg,rgba(110,180,255,.35),rgba(110,175,255,.08));border:1px solid rgba(110,180,255,.55);}
  @media (min-width: 900px){
    .wv-controls.wv-controls--top{grid-template-columns:auto auto 1fr}
    /* five groups + trailing filler column */
    .wv-controls.wv-controls--tune{grid-template-columns:auto auto auto auto auto 1fr}
    .wv-controls.wv-controls--lists{grid-template-columns:1fr 1fr}
  }
  @media (max-width: 899px){.wv-controls{grid-template-columns:1fr}}
  .wv-label{font-size:10px;text-transform:uppercase;letter-spacing:.6px;color:var(--muted,#93a0b4);margin:0 0 4px}
    .wv-segmented{display:flex;flex-wrap:wrap;gap:8px;align-items:center}
  .wv-segmented .seg{padding:6px 10px;border:1px solid var(--border,rgba(255,255,255,.14));background:linear-gradient(180deg,rgba(255,255,255,.08),rgba(255,255,255,.03));color:var(--text,#eef3fb);border-radius:999px;font-size:11px;cursor:pointer;line-height:1}
    .wv-segmented .seg:hover{border-color:rgba(255,255,255,.22);background:linear-gradient(180deg,rgba(255,255,255,.12),rgba(255,255,255,.04))}
    .wv-segmented .seg:focus{outline:2px solid rgba(110,180,255,.55);outline-offset:2px}
    .wv-segmented .seg.active{background:linear-gradient(160deg,rgba(110,180,255,.35),rgba(110,175,255,.08));border-color:rgba(110,180,255,.55);box-shadow:0 0 0 1px rgba(110,180,255,.2) inset}
  .wv-chiprow{display:flex;flex-wrap:wrap;gap:6px}
  .wv-chip{padding:4px 8px;border:1px solid var(--border,rgba(255,255,255,.12));background:rgba(255,255,255,.06);color:var(--text,#eef3fb);border-radius:999px;font-size:11px;cursor:pointer;white-space:nowrap}
  .wv-chip.active{background:linear-gradient(160deg,rgba(110,180,255,.35),rgba(110,175,255,.08));border-color:rgba(110,180,255,.55)}
  /* selectable lists */
  .wv-list{max-height:210px;overflow:auto;border:1px solid rgba(255,255,255,.08);border-radius:10px;background:linear-gradient(180deg,rgba(255,255,255,.03),rgba(255,255,255,.02));padding:6px}
  .wv-list .item{display:flex;align-items:center;justify-content:space-between;gap:8px;padding:5px 8px;border-radius:8px;cursor:pointer;color:var(--text);font-size:12px}
  .wv-list .item:hover{background:rgba(255,255,255,.06)}
  .wv-list .item.active{outline:2px solid rgba(109,166,255,.5);background:linear-gradient(180deg,rgba(109,166,255,.2),rgba(109,166,255,.08))}
  .wv-list .search{display:flex;gap:6px;margin:0 0 6px}
  .wv-list .search input{width:100%;padding:5px 8px;border-radius:8px;border:1px solid rgba(255,255,255,.12);background:rgba(255,255,255,.06);color:var(--text)}
  .wv-title{font-weight:600;margin:0 0 6px;font-size:14px;letter-spacing:.2px}
    .wv-sub{color:var(--muted,#93a0b4);font-size:12px}
    ul.wv-simple{list-style:none;margin:0;padding:0}
  ul.wv-simple li{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:7px 0;border-bottom:1px solid rgba(255,255,255,.06)}
    .wv-badge{display:inline-block;padding:4px 8px;border-radius:999px;background:rgba(255,255,255,.08);color:var(--text,#eef3fb);font-size:12px}
  .wv-chips{display:flex;flex-wrap:wrap;gap:6px}
  .wv-chipbtn{cursor:pointer}
  .wv-ico{display:inline-block;width:12px;height:12px;margin-right:6px;vertical-align:-2px;opacity:.9}
  /* Side settings flyout */
  .wv-settings { position: fixed; top:0; right:0; width: 300px; max-width:90vw; height: 100%; background:#161616; border-left:1px solid #2a2a2a; box-shadow: -8px 0 24px rgba(0,0,0,0.35); transform: translateX(100%); transition: transform .18s ease-out; z-index: 1000; }
  .wv-settings.open { transform: translateX(0); }
  .wv-settings-inner { padding:12px; height:100%; display:flex; flex-direction:column; gap:12px; }
  .wv-settings .wv-controls > div { margin-bottom:8px; }
  .wv-settings .wv-label { font-size:12px; color:#bdbdbd; margin-bottom:4px; }
  .wv-settings .wv-segmented { display:flex; gap:4px; flex-wrap:wrap; }
  .wv-settings .wv-segmented .seg { padding:4px 8px; font-size:12px; border:1px solid #333; background:#1b1b1b; color:#eee; border-radius:6px; cursor:pointer; }
  .wv-settings .wv-segmented .seg.active { background:#2a2a2a; border-color:#3a3a3a; }
  .wv-overlay { position:fixed; inset:0; background:rgba(0,0,0,0.35); display:none; z-index:999; }
  .wv-overlay.show { display:block; }
    `;
    const style = document.createElement('style'); style.id='wv-base-styles'; style.textContent=css; document.head.appendChild(style);
  }
  function boundsFor(mc){ const asset = (mc && mc.major && mc.current && mc.major[mc.current]) ? mc.major[mc.current] : null; return {asset}; }
  function mount(host, cfg){
    injectBaseStyles();
    if(!host) return;
  const data = cfg && cfg.data || {}; const spots = Array.isArray(data.spots)? data.spots: [];
  const sentries = Array.isArray(data.sentries)? data.sentries: [];
  const teams = Array.isArray(data.teams)? data.teams: [];
  const players = Array.isArray(data.players)? data.players: [];
    const mc = cfg && cfg.mapConf || {};
  const extras = (cfg && cfg.options && cfg.options.extras) || {};
  // Basis (lifetime|contest) replaces previous Metric control
  const BASIS_DEFAULT = (cfg && cfg.options && (cfg.options.basisDefault||cfg.options.metricDefault)) || 'lifetime';
  const showExtras = !!(cfg && cfg.options && cfg.options.showExtras);
  const IGNORE_PLAYER_PERSIST = !!(cfg && cfg.options && cfg.options.ignorePersistedPlayer);
  const IGNORE_CLUSTER_PERSIST = !!(cfg && cfg.options && cfg.options.ignorePersistedCluster);
  let state = { mode: (cfg && cfg.options && cfg.options.modeDefault) || 'best', team:'', player:'', time:'', overlay:true, grid:false, hotSentries:false, showSentries:false, minCount:1, topN:'all', basis: BASIS_DEFAULT, includeZeroWorst:false, pins:[], pquery:'', tquery:'', cluster:0 };
    // URL/Storage helpers
    function getSP(){ try{ return new URLSearchParams(location.search); }catch(_e){ return new URLSearchParams(); } }
    function replaceUrl(sp){ try{ const url = location.pathname + (sp.toString()? ('?'+sp.toString()):'') + location.hash; history.replaceState(null, '', url); }catch(_e){} }
    const LS_KEY = {
  mode:'wv_mode', time:'wv_time', team:'wv_team', player:'wv_player', ov:'wv_ov', grid:'wv_grid', hot:'wv_hot', sen:'wv_sen', min:'wv_min', top:'wv_top', basis:'wv_basis', zworst:'wv_zworst', pins:'wv_pins', pquery:'wv_pq', cluster:'wv_cluster'
    };
    function readStorage(k, def){ try{ const v = localStorage.getItem(k); if(v===null || v===undefined) return def; return v; }catch(_e){ return def; } }
    function writeStorage(k, v){ try{ if(v===undefined || v===null || v===''){ localStorage.removeItem(k); } else { localStorage.setItem(k, String(v)); } }catch(_e){} }
    const ALLOWED_MODE = new Set(['best','worst']);
    const ALLOWED_TIME = new Set(['','early','mid','earlylate','late','superlate']);
  const ALLOWED_BASIS = new Set(['lifetime','contest']);
    function hydrateState(){
      const sp = getSP();
      const urlMode = String(sp.get('wmode')||'');
      const urlTime = String(sp.get('wtime')||'');
      const urlTeam = String(sp.get('wteam')||'');
  const urlOv   = String(sp.get('wov')||'');
  const urlGrid = String(sp.get('wgrid')||'');
  const urlHot  = String(sp.get('whot')||'');
  const urlSen  = String(sp.get('wsen')||'');
      const urlMin  = String(sp.get('wmin')||'');
      const urlTop  = String(sp.get('wtop')||'');
    const urlBasis  = String(sp.get('wbasis')||'');
  
      // Back-compat: legacy metric (avg|median|danger)
      const urlMetLegacy = String(sp.get('wmetric')||'');
  const urlCr   = String(sp.get('wcr')||'');
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
  const stHot  = urlHot!==''? (urlHot==='1'?'1':(urlHot==='0'?'0':'')) : readStorage(LS_KEY.hot, state.hotSentries? '1':'0');
  const stSen  = urlSen!==''? (urlSen==='1'?'1':(urlSen==='0'?'0':'')) : readStorage(LS_KEY.sen, state.showSentries? '1':'0');
      const stMin  = urlMin!==''? urlMin : readStorage(LS_KEY.min, String(state.minCount));
    const stTop  = urlTop!==''? urlTop : readStorage(LS_KEY.top, String(state.topN));
      // Determine basis with back-compat mapping from legacy metric
      let stBasis;
      if(urlBasis!==''){
        stBasis = urlBasis;
      } else if(urlMetLegacy!==''){
        const m = String(urlMetLegacy||'').toLowerCase();
        stBasis = (m==='danger') ? 'contest' : 'lifetime';
      } else {
        const lsBasis = readStorage(LS_KEY.basis, '');
        if(lsBasis!==''){
          stBasis = lsBasis;
        } else {
          const lsMetLegacy = readStorage('wv_metric', '');
          if(lsMetLegacy!==''){
            const m = String(lsMetLegacy||'').toLowerCase();
            stBasis = (m==='danger') ? 'contest' : 'lifetime';
          } else {
            stBasis = state.basis;
          }
        }
      }
  // Cluster: optionally ignore persisted storage to default to Off unless URL overrides
  const stCr   = urlCr!==''? urlCr : (IGNORE_CLUSTER_PERSIST ? String(state.cluster) : readStorage(LS_KEY.cluster, String(state.cluster)));
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
  state.hotSentries = (stHot==='1');
  state.showSentries = (stSen==='1');
      const m = Math.max(1, parseInt(stMin,10)||1); state.minCount = m;
      const topVal = (String(stTop).toLowerCase()==='all')? 'all' : (parseInt(stTop,10)||15);
      state.topN = (topVal==='all'|| (typeof topVal==='string' && topVal.toLowerCase()==='all'))? 'all' : Math.max(1, Number(topVal));
  if(ALLOWED_BASIS.has(stBasis)) state.basis = stBasis;
  // cluster radius percentage (0 = off)
  {
    let cr = Number(stCr);
    if(!isFinite(cr) || cr<0) cr = 0;
    // snap to 0, 1, 1.5, 2, 3, 4
    const choices = [0,1,1.5,2,3,4];
    if(!choices.includes(cr)){
      cr = choices.reduce((best,v)=> Math.abs(v-cr) < Math.abs(best-cr) ? v : best, 0);
    }
    state.cluster = cr;
  }
  state.includeZeroWorst = (String(stZw)==='1');
  
  // (Intelligence removed)
  // pins as array of spot keys
  state.pins = stPins ? stPins.split(',').filter(Boolean) : [];
  state.pquery = String(stPq||'');
    }
    function persistState(){
      // Write to URL (only include when different from default)
    const sp = getSP();
  const def = { mode:(cfg && cfg.options && cfg.options.modeDefault) || 'best', time:'', team:'', player:'', ov:'1', grid:'0', hot:'0', sen:'0', min:String(1), top:'all', basis:'lifetime', zw:'0', pins:'', pq:'', cr:String(0) };
      function setOrRemove(key, val, defVal){ if(val===defVal || val==='' || val===null || val===undefined){ sp.delete(key); } else { sp.set(key, String(val)); } }
      setOrRemove('wmode', state.mode, def.mode);
      setOrRemove('wtime', state.time, def.time);
      setOrRemove('wteam', state.team, def.team);
  setOrRemove('wov', state.overlay? '1':'0', def.ov);
  setOrRemove('wgrid', state.grid? '1':'0', def.grid);
  setOrRemove('whot', state.hotSentries? '1':'0', def.hot);
  setOrRemove('wsen', state.showSentries? '1':'0', def.sen);
      setOrRemove('wmin', String(state.minCount), def.min);
  setOrRemove('wtop', state.topN==='all'? 'all' : String(state.topN), def.top);
  setOrRemove('wbasis', state.basis, def.basis);
  
      setOrRemove('wzw', state.includeZeroWorst? '1':'0', def.zw);
  setOrRemove('wplayer', state.player, def.player);
  setOrRemove('wpins', (state.pins||[]).join(','), def.pins);
  setOrRemove('wpq', state.pquery||'', def.pq);
    setOrRemove('wcr', String(state.cluster||0), def.cr);
  // no intelligence param
        // Remove legacy param if present
        try{ sp.delete('wmetric'); }catch(_e){}
      replaceUrl(sp);
      // LocalStorage
    writeStorage(LS_KEY.mode, state.mode);
    writeStorage(LS_KEY.time, state.time);
    writeStorage(LS_KEY.team, state.team);
  // Optionally avoid writing persisted player to keep default "All" in views that opt-in
  if(!IGNORE_PLAYER_PERSIST){ writeStorage(LS_KEY.player, state.player); }
      writeStorage(LS_KEY.ov, state.overlay? '1':'0');
  writeStorage(LS_KEY.grid, state.grid? '1':'0');
  writeStorage(LS_KEY.hot, state.hotSentries? '1':'0');
  writeStorage(LS_KEY.sen, state.showSentries? '1':'0');
      writeStorage(LS_KEY.min, String(state.minCount));
  writeStorage(LS_KEY.top, state.topN==='all'? 'all' : String(state.topN));
  writeStorage(LS_KEY.basis, state.basis);
      writeStorage(LS_KEY.zworst, state.includeZeroWorst? '1':'0');
  writeStorage(LS_KEY.pins, (state.pins||[]).join(','));
  writeStorage(LS_KEY.pquery, state.pquery||'');
  // Optionally avoid writing persisted cluster to keep default "Off" in views that opt-in
  if(!IGNORE_CLUSTER_PERSIST){ writeStorage(LS_KEY.cluster, String(state.cluster||0)); }
  
      // Clean up legacy storage key
      writeStorage('wv_metric', '');
    }
    // Build DOM
    const root = h(`
      <section class="card">
    <h2 style="margin:0 0 6px;font-size:18px">Ward Spots</h2>
  <div class="wv-sub" style="margin-bottom:6px">Best/Worst by time window and team filter. Switch Basis to Contest to see most contested spots.</div>
        <div class="wv-wardgrid">
          <div>
            <div class="wv-controls wv-controls--top" style="margin:6px 0 8px">
              <div>
                <div class="wv-label">View</div>
                <div class="tabs" id="wvTabs" style="margin:0">
                  <button class="tab" data-wmode="best" title="Show top spots by chosen basis (Lifetime/Contest)">Best</button>
                  <button class="tab" data-wmode="worst" title="Show bottom spots by chosen basis (Lifetime/Contest)">Worst</button>
                </div>
              </div>
              <div>
                <div class="wv-label">Basis</div>
                <div id="wvBasis" class="wv-segmented">
                  <button class="seg" data-basis="lifetime" title="Rank by average lifetime">Lifetime</button>
                  <button class="seg" data-basis="contest" title="Rank by contestedness (short lifetimes = higher contest)">Contest</button>
                </div>
              </div>
              <div>
                <div class="wv-label">Time Window</div>
                <div id="wvTime" class="wv-segmented" role="tablist" aria-label="Time window">
                  <button class="seg" data-time="" title="No time filter">All</button>
                  <button class="seg" data-time="early" title="0–10 minutes">Early</button>
                  <button class="seg" data-time="mid" title="10–35 minutes">Mid</button>
                  <button class="seg" data-time="earlylate" title="35–50 minutes">Early Late</button>
                  <button class="seg" data-time="late" title="50–75 minutes">Late</button>
                  <button class="seg" data-time="superlate" title=">75 minutes">Super Late</button>
                </div>
              </div>
            </div>
            <div style="display:flex;justify-content:flex-end;margin:-4px 0 6px">
              <button class="tab" id="wvOpenSettings" title="Open settings panel">Settings</button>
            </div>
            <div class="wv-controls wv-controls--lists" style="margin:-4px 0 8px">
              <div>
                <div class="wv-label">Team</div>
                <div id="wvTeams" class="wv-list" role="listbox" aria-label="Teams">
                  <div class="search"><input type="text" id="wvTq" placeholder="Search teams…" value=""></div>
                  <div id="wvTeamsInner"></div>
                </div>
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
              ${Array.isArray(sentries) && sentries.length ? `<div>
                <div class='wv-label'>Sentries</div>
                <div class='wv-slider' id='wvSenInline'>
                  <div class='wv-slider-track' id='wvSenInlineTrack'>
                    <div style="position:absolute;top:50%;left:0;transform:translate(-1px,-50%);width:2px;height:10px;background:rgba(255,255,255,.25);"></div>
                    <div style="position:absolute;top:50%;left:50%;transform:translate(-1px,-50%);width:2px;height:10px;background:rgba(255,255,255,.25);"></div>
                    <div style="position:absolute;top:50%;left:100%;transform:translate(-1px,-50%);width:2px;height:10px;background:rgba(255,255,255,.25);"></div>
                  </div>
                  <div class='wv-slider-thumb' id='wvSenInlineThumb' tabindex='0' role='slider' aria-valuemin='0' aria-valuemax='2' aria-valuenow='0' aria-label='Sentry mode'></div>
                  <div class='wv-slider-labels'>
                    <button class='seg' data-senmode='off' title='Disable sentry overlays'>
                      <svg class='wv-ico' viewBox='0 0 24 24' aria-hidden='true'><circle cx='12' cy='12' r='9' fill='none' stroke='currentColor' stroke-width='2'/><line x1='6' y1='6' x2='18' y2='18' stroke='currentColor' stroke-width='2'/></svg>
                      Off
                    </button>
                    <button class='seg' data-senmode='markers' title='Show individual sentry markers'>
                      <svg class='wv-ico' viewBox='0 0 24 24' aria-hidden='true'><circle cx='12' cy='12' r='9' fill='none' stroke='currentColor' stroke-width='2'/><circle cx='12' cy='12' r='2' fill='currentColor'/></svg>
                      Markers
                    </button>
                    <button class='seg' data-senmode='hot' title='Show sentry placement hotspots (clustered)'>
                      <svg class='wv-ico' viewBox='0 0 24 24' aria-hidden='true'><defs><radialGradient id='g1' cx='50%' cy='50%' r='50%'><stop offset='0%' stop-color='currentColor' stop-opacity='.9'/><stop offset='100%' stop-color='currentColor' stop-opacity='.2'/></radialGradient></defs><circle cx='12' cy='12' r='9' fill='url(#g1)' stroke='currentColor' stroke-opacity='.5' stroke-width='1.5'/></svg>
                      Hotspots
                    </button>
                  </div>
                </div>
              </div>` : ''}
            </div>
            <div class="wv-wardmap enhanced" id="wvMap"><svg></svg><div class="wv-tooltip" id="wvTip" role="tooltip" aria-hidden="true"></div></div>
            <div class="wv-settings" id="wvSettings" aria-hidden="true">
              <div class="wv-settings-inner">
                <div class="wv-title" style="margin:0 0 6px">Settings</div>
                <div class="wv-controls" style="margin:0 0 8px">
                  
                  <div>
                    <div class="wv-label">Min occ.</div>
                    <div id="wvMin" class="wv-segmented">
                      <button class="seg" data-min="1" title="Minimum occurrences per spot">1</button>
                      <button class="seg" data-min="2" title="Minimum occurrences per spot">2</button>
                      <button class="seg" data-min="3" title="Minimum occurrences per spot">3</button>
                      <button class="seg" data-min="5" title="Minimum occurrences per spot">5</button>
                    </div>
                  </div>
                  <div>
                    <div class="wv-label">Top</div>
                    <div id="wvTop" class="wv-segmented">
                      <button class="seg" data-top="10" title="Limit number of spots shown">10</button>
                      <button class="seg" data-top="15" title="Limit number of spots shown">15</button>
                      <button class="seg" data-top="25" title="Limit number of spots shown">25</button>
                      <button class="seg" data-top="50" title="Limit number of spots shown">50</button>
                      <button class="seg" data-top="all" title="Show all matching spots">All</button>
                    </div>
                  </div>
                  <div>
                    <div class="wv-label">Group</div>
                    <div id="wvCluster" class="wv-segmented">
                      <button class="seg" data-cluster="0" title="No grouping">Off</button>
                      <button class="seg" data-cluster="1" title="Group nearby spots within ≈1% of map size">1%</button>
                      <button class="seg" data-cluster="1.5" title="Group nearby spots within ≈1.5% of map size">1.5%</button>
                      <button class="seg" data-cluster="2" title="Group nearby spots within ≈2% of map size">2%</button>
                      <button class="seg" data-cluster="3" title="Group nearby spots within ≈3% of map size">3%</button>
                      <button class="seg" data-cluster="4" title="Group nearby spots within ≈4% of map size">4%</button>
                    </div>
                  </div>
                </div>
                <div style="display:flex;gap:12px;justify-content:space-between;align-items:center">
                  <label class="wv-sub" title="Include spots with 0s lifetime when showing worst list"><input type="checkbox" id="wvZeroWorst" style="vertical-align:middle;margin-right:6px">Include 0s worst</label>
                  <button class="tab" id="wvReset" title="Reset all filters to defaults">Reset</button>
                </div>
              </div>
            </div>
            <div class="wv-sub" id="wvPinsBar" style="margin-top:6px"></div>
            <div class="wv-sub" id="wvLegend" style="margin-top:6px">Green = Best avg lifetime, Red = Worst.</div>
            
            <div style="display:flex;gap:8px;align-items:center;margin-top:6px">
              <label style="font-size:12px;color:var(--muted)" title="Toggle spot circles overlay on the map"><input type="checkbox" id="wvOv" checked style="vertical-align:middle;margin-right:6px">Overlay</label>
              <label style="font-size:12px;color:var(--muted)" title="Show a 10x10 helper grid"><input type="checkbox" id="wvGrid" style="vertical-align:middle;margin-right:6px">Grid</label>
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
  // Add overlay element for settings
  const overlayEl = document.createElement('div');
  overlayEl.className = 'wv-overlay';
  host.appendChild(overlayEl);
    // Read initial state from URL/localStorage
    hydrateState();
    // Set default active tabs
    root.querySelectorAll('#wvTabs .tab').forEach(b=> b.classList.toggle('active',(b.dataset.wmode||'')===state.mode));
  function setActiveTime(){ const wrap=root.querySelector('#wvTime'); if(!wrap) return; wrap.querySelectorAll('.seg').forEach(b=> b.classList.toggle('active',(b.dataset.time||'')===state.time)); }
  function setActiveMin(){ const wrap=root.querySelector('#wvMin'); if(!wrap) return; wrap.querySelectorAll('.seg').forEach(b=> b.classList.toggle('active', Number(b.getAttribute('data-min')||'0')===Number(state.minCount))); }
  function setActiveTop(){ const wrap=root.querySelector('#wvTop'); if(!wrap) return; wrap.querySelectorAll('.seg').forEach(b=> b.classList.toggle('active', (b.getAttribute('data-top')||'')=== (state.topN==='all'?'all':String(state.topN)))); }
  function setActiveBasis(){ const wrap=root.querySelector('#wvBasis'); if(!wrap) return; wrap.querySelectorAll('.seg').forEach(b=> b.classList.toggle('active', (b.getAttribute('data-basis')||'')===state.basis)); }
  function setActiveCluster(){ const wrap=root.querySelector('#wvCluster'); if(!wrap) return; wrap.querySelectorAll('.seg').forEach(b=> b.classList.toggle('active', Number(b.getAttribute('data-cluster')||'0')===Number(state.cluster))); }
  
    setActiveTime();
  setActiveMin();
  setActiveTop();
  setActiveBasis();
  setActiveCluster();
  
  
    // Build team and player picklists
    (function(){
      const tWrap=root.querySelector('#wvTeams'); const pWrap=root.querySelector('#wvPlayersPick'); if(!tWrap) return;
      const tItemsBase=[{v:'',label:'All'},{v:'Radiant',label:'Radiant'},{v:'Dire',label:'Dire'}];
      teams.slice().sort((a,b)=> String(a.name||'').localeCompare(String(b.name||''))).forEach(t=> tItemsBase.push({v:`team:${t.id}`,label:String(t.name||`Team ${t.id}`)}));
      function renderTeams(){
        const wrapInner = tWrap.querySelector('#wvTeamsInner'); const tq = String(state.tquery||'').toLowerCase();
        const list = tItemsBase.filter(c=> !tq || String(c.label||'').toLowerCase().includes(tq) || String(c.v||'').toLowerCase().includes(tq));
        const html = list.map(c=>`<div class='item ${((c.v||'')===state.team?'active':'')}' role='option' data-team='${esc(c.v)}'><span>${esc(c.label)}</span>${((c.v||'')===state.team?"<span class='wv-badge'>selected</span>":'')}</div>`).join('');
        if(wrapInner){ wrapInner.innerHTML = html; }
        else { tWrap.innerHTML = html; }
      }
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
  const tq = tWrap.querySelector('#wvTq'); if(tq){ tq.value = state.tquery||''; tq.addEventListener('input', ()=>{ state.tquery = String(tq.value||''); renderTeams(); }); }
      tWrap.addEventListener('click', e=>{ const it=e.target.closest('.item'); if(!it) return; state.team = it.getAttribute('data-team')||''; renderTeams(); persistState(); render(); });
      if(pWrap){
        const pq = pWrap.querySelector('#wvPq'); if(pq){ pq.value = state.pquery||''; pq.addEventListener('input', ()=>{ state.pquery = String(pq.value||''); persistState(); renderPlayers(); }); }
        pWrap.addEventListener('click', e=>{ const it=e.target.closest('.item'); if(!it) return; state.player = it.getAttribute('data-player')||''; renderPlayers(); persistState(); render(); });
      }
    })();
    // Bind tabs/time
  root.querySelectorAll('#wvTabs .tab').forEach(b=> b.addEventListener('click',()=>{ state.mode = b.dataset.wmode||'best'; root.querySelectorAll('#wvTabs .tab').forEach(x=> x.classList.toggle('active', x===b)); try{ const zw=root.querySelector('#wvZeroWorst'); if(zw){ const lab=zw.closest('label'); if(lab){ lab.style.display = (state.mode==='worst')? '' : 'none'; } } }catch(_e){} persistState(); render(); }));
  root.querySelector('#wvTime').addEventListener('click',(e)=>{ const btn=e.target.closest('button.seg'); if(!btn) return; state.time = btn.getAttribute('data-time')||''; setActiveTime(); persistState(); render(); });
  root.querySelector('#wvMin').addEventListener('click',(e)=>{ const btn=e.target.closest('button.seg'); if(!btn) return; const v = Math.max(1, parseInt(btn.getAttribute('data-min')||'1',10)); state.minCount = v; setActiveMin(); persistState(); render(); });
  root.querySelector('#wvTop').addEventListener('click',(e)=>{ const btn=e.target.closest('button.seg'); if(!btn) return; const t = String(btn.getAttribute('data-top')||'15'); state.topN = (t.toLowerCase()==='all')? 'all' : Math.max(1, parseInt(t,10)||15); setActiveTop(); persistState(); render(); });
  root.querySelector('#wvBasis').addEventListener('click',(e)=>{ const btn=e.target.closest('button.seg'); if(!btn) return; const b = String(btn.getAttribute('data-basis')||'lifetime'); if(ALLOWED_BASIS.has(b)){ state.basis = b; setActiveBasis(); persistState(); render(); } });
  // Intelligence controls removed
  
  root.querySelector('#wvCluster').addEventListener('click',(e)=>{ const btn=e.target.closest('button.seg'); if(!btn) return; const cr = Number(btn.getAttribute('data-cluster')||'0'); state.cluster = (!isFinite(cr) || cr<0)? 0 : cr; setActiveCluster(); persistState(); render(); });
  
  const svg = root.querySelector('#wvMap svg');
    function ensureBG(){ try{ const asset = (mc && mc.major && mc.current && mc.major[mc.current]) ? mc.major[mc.current] : null; let src = asset && asset.src ? asset.src : null; if(!src && mc && mc.default){ src = mc.default; } const el=root.querySelector('#wvMap'); if(src && el){ el.style.backgroundImage = `url('${src}')`; } }catch(_e){} }
    ensureBG();
    // Initialize overlay/grid from state
    try{ const ov=root.querySelector('#wvOv'); if(ov){ ov.checked = !!state.overlay; svg.style.display = ov.checked? '':'none'; } }catch(_e){}
  try{ const gr=root.querySelector('#wvGrid'); if(gr){ gr.checked = !!state.grid; } }catch(_e){}
  // Flyout init: set current label
  function setSentryModeLabel(){ try{ const lbl=root.querySelector('#wvSentryModeLbl'); if(!lbl) return; let m='Off'; if(state.hotSentries) m='Hotspots'; else if(state.showSentries) m='Markers'; lbl.textContent = m; }catch(_e){} }
  setSentryModeLabel();
  try{ const zw=root.querySelector('#wvZeroWorst'); if(zw){ zw.checked = !!state.includeZeroWorst; const lab=zw.closest('label'); if(lab){ lab.style.display = (state.mode==='worst')? '' : 'none'; } zw.addEventListener('change',()=>{ state.includeZeroWorst = !!zw.checked; persistState(); render(); }); } }catch(_e){}
    root.querySelector('#wvOv').addEventListener('change',()=>{ state.overlay = !!root.querySelector('#wvOv').checked; svg.style.display = state.overlay? '':'none'; persistState(); });
  root.querySelector('#wvGrid').addEventListener('change',()=>{ state.grid = !!root.querySelector('#wvGrid').checked; persistState(); render(); });
  // Settings flyout open/close
  (function(){
    const panel = root.querySelector('#wvSettings');
    const openBtn = root.querySelector('#wvOpenSettings');
    const overlay = root.parentElement && root.parentElement.querySelector('.wv-overlay');
    if(!panel || !openBtn || !overlay) return;
  function open(){ panel.classList.add('open'); panel.setAttribute('aria-hidden','false'); overlay.classList.add('show'); setActiveMin(); setActiveTop(); setActiveCluster(); }
    function close(){ panel.classList.remove('open'); panel.setAttribute('aria-hidden','true'); overlay.classList.remove('show'); }
    openBtn.addEventListener('click',(e)=>{ e.preventDefault(); if(panel.classList.contains('open')) close(); else open(); });
    overlay.addEventListener('click', close);
    document.addEventListener('keydown', (e)=>{ if(e.key==='Escape') close(); });
  })();
  // Inline sentry slider wiring
  (function(){
    const thumb = root.querySelector('#wvSenInlineThumb');
    const track = root.querySelector('#wvSenInlineTrack');
    const labelsWrap = root.querySelector('#wvSenInline .wv-slider-labels');
    if(!thumb || !track || !labelsWrap) return;
    function modeIndex(){ if(state.hotSentries) return 2; if(state.showSentries) return 1; return 0; }
  function setFromIndex(idx){ idx=Math.max(0,Math.min(2,Number(idx||0))); if(idx===0){ state.showSentries=false; state.hotSentries=false; } else if(idx===1){ state.showSentries=true; state.hotSentries=false; } else { state.showSentries=false; state.hotSentries=true; } thumb.setAttribute('aria-valuenow', String(idx)); persistState(); setSentryModeLabel(); render(); setActiveLabels(); positionThumb(); }
  function positionThumb(){ try{ const r=track.getBoundingClientRect(); const xs=[0,0.5,1]; const x = r.left + r.width*xs[modeIndex()]; const left = (x - r.left); thumb.style.top = (r.top - track.parentElement.getBoundingClientRect().top) + 'px'; thumb.style.left = (8 + left) + 'px'; }catch(_e){} }
    function setActiveLabels(){ labelsWrap.querySelectorAll('[data-senmode]').forEach(b=>{ const m=String(b.getAttribute('data-senmode')||'off'); const idx=(m==='off')?0:(m==='markers'?1:2); b.classList.toggle('active', idx===modeIndex()); }); }
    // Init
    setActiveLabels();
    setTimeout(positionThumb,0);
    window.addEventListener('resize', positionThumb);
    // Drag
    function onDown(e){ e.preventDefault(); const move=(ev)=>{ const r=track.getBoundingClientRect(); const x = Math.max(r.left, Math.min(r.right, ev.clientX)); const p = (x - r.left)/Math.max(1,r.width); const idx = p<0.25? 0 : (p<0.75? 1 : 2); if(idx!==modeIndex()){ setFromIndex(idx); } positionThumb(); }; const up=()=>{ document.removeEventListener('mousemove', move); document.removeEventListener('mouseup', up); }; document.addEventListener('mousemove', move); document.addEventListener('mouseup', up); }
    thumb.addEventListener('mousedown', onDown);
    thumb.addEventListener('keydown', (e)=>{ if(e.key==='ArrowLeft'){ setFromIndex(modeIndex()-1); } else if(e.key==='ArrowRight'){ setFromIndex(modeIndex()+1); } });
    // Labels
    labelsWrap.addEventListener('click', (e)=>{ const it=e.target.closest('[data-senmode]'); if(!it) return; const m=String(it.getAttribute('data-senmode')||'off'); const idx=(m==='off')?0:(m==='markers'?1:2); setFromIndex(idx); });
  })();
  // Flyout open/close and selection handlers
  (function(){
    const fly = root.querySelector('#wvSentryFly'); if(!fly) return;
    const btn = root.querySelector('#wvSentryBtn'); const menu = root.querySelector('#wvSentryMenu');
    function close(){ fly.classList.remove('open'); if(btn) btn.setAttribute('aria-expanded','false'); }
    function open(){ fly.classList.add('open'); if(btn) btn.setAttribute('aria-expanded','true'); }
    if(btn){ btn.addEventListener('click', (e)=>{ e.stopPropagation(); if(fly.classList.contains('open')) close(); else open(); }); }
    // Outside click / Esc
    document.addEventListener('click', (e)=>{ if(!fly.contains(e.target)) close(); });
    document.addEventListener('keydown', (e)=>{ if(e.key==='Escape') close(); });
    // Slider + labels mapping
    const thumb = menu && menu.querySelector('#wvSenThumb');
    const track = menu && menu.querySelector('#wvSenTrack');
    function modeIndex(){ if(state.hotSentries) return 2; if(state.showSentries) return 1; return 0; }
    function setFromIndex(idx){ idx=Math.max(0,Math.min(2,Number(idx||0))); if(idx===0){ state.showSentries=false; state.hotSentries=false; } else if(idx===1){ state.showSentries=true; state.hotSentries=false; } else { state.showSentries=false; state.hotSentries=true; } persistState(); setSentryModeLabel(); render(); }
    function positionThumb(){ try{ if(!thumb || !track) return; const rect = track.getBoundingClientRect(); const xs = [0, 0.5, 1]; const x = rect.left + rect.width * xs[modeIndex()]; const left = 6 + (rect.width * xs[modeIndex()]); thumb.style.left = left + 'px'; thumb.setAttribute('aria-valuenow', String(modeIndex())); }catch(_e){} }
    // Initialize positions when opening
    if(btn){ btn.addEventListener('click', ()=>{ setTimeout(positionThumb, 0); }); }
    window.addEventListener('resize', positionThumb);
    // Drag support
    function onDown(e){ if(!thumb) return; e.preventDefault(); const move=(ev)=>{ const r=track.getBoundingClientRect(); const x = Math.max(r.left, Math.min(r.right, ev.clientX)); const p = (x - r.left)/Math.max(1,r.width); const idx = p<0.25? 0 : (p<0.75? 1 : 2); if(idx!==modeIndex()){ setFromIndex(idx); } positionThumb(); }; const up=()=>{ document.removeEventListener('mousemove', move); document.removeEventListener('mouseup', up); }; document.addEventListener('mousemove', move); document.addEventListener('mouseup', up); }
    if(thumb){ thumb.addEventListener('mousedown', onDown); thumb.addEventListener('keydown', (e)=>{ if(e.key==='ArrowLeft'){ setFromIndex(modeIndex()-1); positionThumb(); } else if(e.key==='ArrowRight'){ setFromIndex(modeIndex()+1); positionThumb(); } }); }
    // Label buttons
    if(menu){ menu.addEventListener('click', (e)=>{ const it=e.target.closest('[data-senmode]'); if(!it) return; const m=String(it.getAttribute('data-senmode')||'off'); const idx = (m==='off')?0:(m==='markers'?1:2); setFromIndex(idx); positionThumb(); close(); }); }
  })();
    function timeWindow(){ switch(state.time){ case 'early': return {min:0,max:600,label:'0-10m'}; case 'mid': return {min:600,max:2100,label:'10-35m'}; case 'earlylate': return {min:2100,max:3000,label:'35-50m'}; case 'late': return {min:3000,max:4500,label:'50-75m'}; case 'superlate': return {min:4500,max:Infinity,label:'75m+'}; default: return {min:-Infinity,max:Infinity,label:'all'}; } }
  function pickCounts(s){
      const val=state.team; const tw=timeWindow(); const pid = state.player ? Number(state.player) : 0;
      function dangerBucket(lifeSec){ const L=Math.max(0,Number(lifeSec||0)); if(L<=5) return 100; if(L<=30) return 75; if(L<=150) return 40; if(L<=360) return 15; return 10; }
  if(Array.isArray(s.samples) && s.samples.length){ let cnt=0,totW=0,wsum=0, totRaw=0; const lifes=[]; let cInst=0,cShort=0,cMed=0,cLong=0; let rSamp=0,dSamp=0; for(const sm of s.samples){ const t=Number(sm.t||0); if(!(t>=tw.min && t<tw.max)) continue; if(pid>0 && Number(sm.aid||0)!==pid) continue; let ok=false; if(!val || val==='') { ok=true; } else if(val==='Radiant' || val==='Dire'){ if(String(sm.side||'')===val) ok=true; } else if(val.startsWith('team:')){ const id=Number(val.split(':')[1]||0); if(Number(sm.teamId||0)===id) ok=true; }
    if(!ok) continue; cnt++; const life = Number((sm.life!=null? sm.life : sm.lifetime)||0); const L=Math.max(0,life); const w = 1.0; totW += (L * w); wsum += w; totRaw += L; lifes.push(Math.floor(L)); const sd=String(sm.side||''); if(sd==='Radiant') rSamp++; else if(sd==='Dire') dSamp++; if(L<=5) cInst++; else if(L<=30) cShort++; else if(L<=150) cMed++; else cLong++; }
    const n = Math.max(1, cInst+cShort+cMed+cLong);
    const danger = 100 * ((1.0*(cInst/n)) + (0.6*(cShort/n)) + (0.25*(cMed/n)));
    return {count:cnt,total:totW,wsum,rawTotal:totRaw,lifes, danger, inst:cInst, short:cShort, med:cMed, long:cLong, nSamples:(cInst+cShort+cMed+cLong), rSamples:rSamp, dSamples:dSamp};
      }
      // Without samples, only coarse aggregates are available; when filtering by player, return 0
  if(pid>0){ return {count:0,total:0,rawTotal:0,lifes:null, danger:0, inst:0, short:0, med:0, long:0, nSamples:0, rSamples:0, dSamples:0}; }
      function proxyDangerAggregated(spot, avg, filter){
        const base = (!isFinite(avg)||avg<=0) ? 0 : (dangerBucket(avg)/100);
        // If no filter (All), incorporate side-balance to reflect contestedness
        if(!filter){
          let r=0,d=0; try{ r = Number(spot.bySide && spot.bySide.Radiant && spot.bySide.Radiant.count || 0); d = Number(spot.bySide && spot.bySide.Dire && spot.bySide.Dire.count || 0); }catch(_e){}
          const tot = r + d;
          const balance = tot>0 ? (1 - Math.abs(r-d)/tot) : 0; // 0..1, higher means more even Radiant/Dire usage
          const score = Math.max(0, Math.min(1, 0.55*base + 0.45*balance));
          return 100*score;
        }
        // With side/team filters: fall back to base (coarse but consistent)
        return 100*base;
      }
      if(!val){ const avg=(Number(s.total||0)/Math.max(1,Number(s.count||0))); return {count:s.count||0,total:s.total||0,rawTotal:(s.total||0),lifes:null, danger: proxyDangerAggregated(s, avg, ''), inst:0, short:0, med:0, long:0, nSamples:0, rSamples:0, dSamples:0}; }
      if(val==='Radiant' || val==='Dire'){ const side=s.bySide && s.bySide[val] || {count:0,total:0}; const avg=(Number(side.total||0)/Math.max(1,Number(side.count||0))); return {count:side.count||0, total:side.total||0, rawTotal:(side.total||0), lifes:null, danger: proxyDangerAggregated(s, avg, val), inst:0, short:0, med:0, long:0, nSamples:0, rSamples:0, dSamples:0}; }
      if(val.startsWith('team:')){ const id=Number(val.split(':')[1]||0); const t=s.byTeam && s.byTeam[id]; const avg=(Number(t&&t.total||0)/Math.max(1,Number(t&&t.count||0))); return {count:(t&&t.count)||0,total:(t&&t.total)||0, rawTotal:(t&&t.total||0), lifes:null, danger: proxyDangerAggregated(s, avg, val), inst:0, short:0, med:0, long:0, nSamples:0, rSamples:0, dSamples:0}; }
      const avg=(Number(s.total||0)/Math.max(1,Number(s.count||0))); return {count:s.count||0,total:s.total||0,rawTotal:(s.total||0),lifes:null, danger: proxyDangerAggregated(s, avg, val), inst:0, short:0, med:0, long:0, nSamples:0, rSamples:0, dSamples:0};
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
    // (summary chips removed for a cleaner UI)
    // derive base metrics per raw spot
  // Helper: simple danger from avg lifetime (mirrors bucket logic)
  function simpleDangerFromAvg(L){ const v=Math.max(0,Number(L||0)); if(v<=5) return 100; if(v<=30) return 75; if(v<=150) return 40; if(v<=360) return 15; return 10; }
  const derived = spots.map(s=>{ const v=pickCounts(s); const cden = Number(v.count||0); const avgRaw = cden>0 ? (Number((v.rawTotal!=null?v.rawTotal:v.total)||0)/cden) : 0; const avg = Math.floor(Math.min(360, Math.max(0, avgRaw))); const med = (v.lifes && v.lifes.length)? median(v.lifes) : 0; // baseline shortness share under current filters
    const nS = Math.max(1, Number(v.nSamples||0)); const baseShort = (Number(v.inst||0) + 0.6*Number(v.short||0) + 0.25*Number(v.med||0)) / nS; // approximate league/filter baseline using total avg
    const baseDanger = Math.max(0, Math.min(1, (avg>0 ? (simpleDangerFromAvg(avg)/100) : 0))); // scale by side balance if available
    let sideBal = 0; try{ const r=Number(v.rSamples||0), d=Number(v.dSamples||0), tot=r+d; sideBal = tot>0 ? (1 - Math.abs(r-d)/tot) : 0; }catch(_e){}
    const mix = 0.55*baseDanger + 0.45*sideBal; // raw shortness mix from samples
    const rawShort = Math.max(0, Math.min(1, baseShort)); // residual above baseline; clamp to 0..1
    const excess = Math.max(0, rawShort - mix);
    const contResidual = Math.round(100 * (0.5*mix + 0.5*excess));
  // sentry pressure near spot (computed later in the function after we have norm and sentIdx)
  return {spot:s.spot,x:s.x,y:s.y,_v:v,count:v.count,avgSeconds:avg,avg:avg,median:med,_contResidual:contResidual}; });
  const clusterOn = Number(state.cluster||0) > 0;
  const preMin = clusterOn ? 1 : Number(state.minCount||1);
  const perf = derived.filter(s=> s.count>=preMin);
      let best=[], worst=[], all=derived;
      const topN = (state.topN==='all')? Infinity : Number(state.topN||15);
      // map render prep
      svg.innerHTML='';
      const asset = (mc && mc.major && mc.current && mc.major[mc.current]) ? mc.major[mc.current] : null;
      const hasBounds = asset && asset.minX!=null && asset.maxX!=null && asset.minY!=null && asset.maxY!=null && asset.maxX>asset.minX && asset.maxY>asset.minY;
      const invertY = !!(asset && asset.invertY);
      const observedMax = (perf.concat(all)).reduce((acc,s)=>({mx:Math.max(acc.mx, Number(s.x||0)), my:Math.max(acc.my, Number(s.y||0))}), {mx:0,my:0});
      const dynScale = Math.max(1, Number(asset && asset.scale || 0), observedMax.mx, observedMax.my, Number(mc && mc.defaultScale || 0));
      const cellUnits = Number((asset && asset.cellUnits) || (mc && mc.defaultCellUnits) || 128);
  const obsUnits  = Number((asset && asset.obsRadiusUnits) || (mc && mc.defaultObsRadiusUnits) || 1600);
  const senUnits  = Number((asset && asset.sentryRadiusUnits) || (mc && mc.defaultSentryRadiusUnits) || 900);
      let obsPct = (asset && asset.obsRadiusPct!=null) ? Number(asset.obsRadiusPct)
             : (mc && mc.defaultObsRadiusPct!=null ? Number(mc.defaultObsRadiusPct) : NaN);
      if(!isFinite(obsPct)){
        const denom = hasBounds ? (cellUnits * (Number(asset && asset.maxX)||0 - Number(asset && asset.minX)||0)) : (cellUnits * dynScale);
        const calc = denom>0 ? (obsUnits/denom)*100 : NaN;
        obsPct = isFinite(calc) && calc>0 ? Math.round(calc*100)/100 : 10;
      }
      let senPct = (asset && asset.sentryRadiusPct!=null) ? Number(asset.sentryRadiusPct)
             : (mc && mc.defaultSentryRadiusPct!=null ? Number(mc.defaultSentryRadiusPct) : NaN);
      if(!isFinite(senPct)){
        // Prefer ratio-based derivation from observer radius to ensure consistent visual scaling
        const ratio = (Number(obsUnits||0)>0) ? (Number(senUnits||0)/Number(obsUnits||1)) : NaN;
        if(isFinite(obsPct) && isFinite(ratio) && ratio>0){
          senPct = Math.round((obsPct * ratio) * 100) / 100;
        } else {
          // Fallback to unit->percent conversion if needed
          const denom = hasBounds ? (cellUnits * (Number(asset && asset.maxX)||0 - Number(asset && asset.minX)||0)) : (cellUnits * dynScale);
          const calc = denom>0 ? (senUnits/denom)*100 : NaN;
          senPct = isFinite(calc) && calc>0 ? Math.round(calc*100)/100 : 6; // conservative fallback
        }
      }
  function norm(X,Y){ let cx0, cy0; if(hasBounds){ const minX=asset.minX, maxX=asset.maxX, minY=asset.minY, maxY=asset.maxY; const clX=Math.max(minX,Math.min(maxX,Number(X||0))); const clY=Math.max(minY,Math.min(maxY,Number(Y||0))); cx0=(clX-minX)/(maxX-minX); cy0=(clY-minY)/(maxY-minY); if(invertY) cy0=1-cy0; } else { cx0=Math.max(0,Math.min(dynScale,Number(X||0)))/dynScale; cy0=Math.max(0,Math.min(dynScale,Number(Y||0)))/dynScale; if(invertY) cy0=1-cy0; } return {cx: Math.round(cx0*10000)/100, cy: Math.round(cy0*10000)/100}; }
      // Build sentry proximity index (time-window filtered)
      const twCur = timeWindow();
      const sentIdx = Array.isArray(sentries)? sentries.map(it=>{
        const n = norm(it.x, it.y);
        const samp = Array.isArray(it.samples)? it.samples: [];
        if(samp.length){
          let cnt=0, r=0, d=0;
          const teamSel = String(state.team||'');
          const playerSel = String(state.player||'');
          for(const s of samp){
            const t=Number(s.t||0); if(!(t>=twCur.min && t<twCur.max)) continue;
            // Apply team filter
            let ok=true;
            if(teamSel==='Radiant' || teamSel==='Dire'){
              ok = String(s.side||'')===teamSel;
            } else if(teamSel.startsWith('team:')){
              const id=Number(teamSel.split(':')[1]||0);
              const sid = Number(s.teamId||s.tid||it.teamId||0);
              ok = (id>0 && sid===id);
            }
            // Apply player filter if available (aid on sample)
            if(ok && playerSel && /^\d+$/.test(playerSel)){
              ok = Number(s.aid||s.account_id||0) === Number(playerSel);
            }
            if(!ok) continue;
            cnt++;
            const sd=String(s.side||''); if(sd==='Radiant') r++; else if(sd==='Dire') d++;
          }
          return {spot:String(it.spot||`${it.x},${it.y}`), x:Number(it.x||0), y:Number(it.y||0), nx:n.cx/100, ny:n.cy/100, cntTW:cnt, rTW:r, dTW:d};
        }
        return {spot:String(it.spot||`${it.x},${it.y}`), x:Number(it.x||0), y:Number(it.y||0), nx:n.cx/100, ny:n.cy/100, cntTW:Number(it.count||0), rTW:0, dTW:0};
      }) : [];
      const senMax = sentIdx.reduce((m,it)=> Math.max(m, Number(it.cntTW||0)), 0) || 1;
      function sentryPressureFor(cx, cy){
        // cx,cy in 0..1 space; use sentry detection radius as neighborhood
        const senR = Math.max(0.008, Number(senPct||0)/100);
        let acc = 0; const contrib=[]; let anyWithin=false;
        for(const it of sentIdx){ const dx = cx - Number(it.nx||0), dy = cy - Number(it.ny||0); const dist = Math.hypot(dx,dy); if(dist>senR) continue; anyWithin=true; const w = 1 - (dist/senR); const c = Number(it.cntTW||0)/senMax; const score = Math.max(0, w*c); if(score>0){ acc += score; contrib.push({spot:it.spot, x:it.x, y:it.y, score, count:it.cntTW, r:it.rTW, d:it.dTW}); } }
        contrib.sort((a,b)=> b.score-a.score);
        const top = contrib.slice(0,3);
        const pressure = Math.max(0, Math.min(100, Math.round(Math.min(1, acc)*100)));
        return { pressure, top, within:anyWithin };
      }
  // optional clustering before ranking
      function clusterize(list, radiusPct){
        const r = Number(radiusPct||0);
        if(!isFinite(r) || r<=0) return list.slice();
        const pts = list.map(s=>{ const n=norm(s.x,s.y); return {s, nx:Number(n.cx||0), ny:Number(n.cy||0)}; });
        // sort by count desc then avgSeconds desc for seed selection
        pts.sort((a,b)=> (Number(b.s.count||0)-Number(a.s.count||0)) || (Number(b.s.avgSeconds||0)-Number(a.s.avgSeconds||0)) );
        const used = new Array(pts.length).fill(false);
        const clusters = [];
        function wmedian(pairs){ const arr=pairs.filter(x=> isFinite(x.v) && isFinite(x.w) && x.w>0).sort((a,b)=> a.v-b.v); if(!arr.length) return 0; let total=0; for(const x of arr) total+=x.w; let acc=0; const half=total/2; for(const x of arr){ acc+=x.w; if(acc>=half) return Math.floor(x.v); } return Math.floor(arr[arr.length-1].v); }
        function wpercentile(pairs, pct){ const p=Math.max(0,Math.min(1,Number(pct||0.8))); const arr=pairs.filter(x=> isFinite(x.v) && isFinite(x.w) && x.w>0).sort((a,b)=> a.v-b.v); if(!arr.length) return 0; let total=0; for(const x of arr) total+=x.w; const target = total*p; let acc=0; for(const x of arr){ acc+=x.w; if(acc>=target) return Math.floor(x.v); } return Math.floor(arr[arr.length-1].v); }
        for(let i=0;i<pts.length;i++){
          if(used[i]) continue;
          const seed = pts[i];
          const groupIdx=[]; let sumW=0,sumNX=0,sumNY=0,sumX=0,sumY=0,sumTotSec=0; const meds=[];
          let sumContest=0, sumContestW=0; const contPairs=[];
          for(let j=i;j<pts.length;j++){
            if(used[j]) continue;
            const q=pts[j]; const dx = seed.nx - q.nx; const dy = seed.ny - q.ny; const dist = Math.hypot(dx,dy);
            if(dist<=r){
              groupIdx.push(j); used[j]=true; const w = Number(q.s.count||0);
              sumW+=w; sumNX += q.nx*w; sumNY += q.ny*w; sumX += Number(q.s.x||0)*w; sumY += Number(q.s.y||0)*w; sumTotSec += Number(q.s.avg||0)*w;
              meds.push({v:Number(q.s.median||0), w});
              if(q.s.contest!=null){ const cv=Number(q.s.contest||0); sumContest += cv*w; sumContestW += w; contPairs.push({v:cv, w}); }
            }
          }
          if(sumW<=0) continue;
          const cnx = sumNX/sumW, cny = sumNY/sumW;
          const cx = sumX/sumW, cy = sumY/sumW;
          const totalCount = sumW; const avgSeconds = Math.floor(sumTotSec/Math.max(1,totalCount)); const medSeconds = wmedian(meds);
          // Use a high-percentile of contest to avoid diluting strongly contested spots in large clusters
          const contestVal = sumContestW>0 ? wpercentile(contPairs, 0.8) : 0;
          const avgVal = avgSeconds;
          const chosen = (state.basis==='contest')? contestVal : avgVal;
          const spotKey = `cluster:[${cnx.toFixed(1)},${cny.toFixed(1)}]~r${r}`;
          clusters.push({ spot: spotKey, x: cx, y: cy, count: totalCount, avgSeconds: chosen, avg: avgVal, median: medSeconds, contest: contestVal });
        }
        return clusters;
      }
      // Draw individual sentry markers (underlay). Always independent of ward grouping.
      function renderSentryMarkers(){
        if(!state.showSentries) return;
        if(!Array.isArray(sentIdx) || !sentIdx.length) return;
        const g = document.createElementNS('http://www.w3.org/2000/svg','g');
        g.setAttribute('data-layer','sentry-markers');
        // Append to render above hotspots but below ward circles (which are added later)
        svg.appendChild(g);
        const senR = Math.max(0.008, Number(senPct||0)/100);
        // Optionally group sentry markers by current cluster radius
        const cr = Number(state.cluster||0);
        let markers;
        if(isFinite(cr) && cr>0){
          const src = sentIdx.map(it=>({ nx:Number(it.nx||0), ny:Number(it.ny||0), w:Math.max(0, Number(it.cntTW||0)) }));
          const used = new Array(src.length).fill(false);
          const clusters=[];
          for(let i=0;i<src.length;i++){
            if(used[i]) continue; const seed = src[i];
            let sumW=0,sumNX=0,sumNY=0;
            for(let j=i;j<src.length;j++){
              if(used[j]) continue; const q = src[j];
              const dx = seed.nx - q.nx; const dy = seed.ny - q.ny; const dist = Math.hypot(dx,dy);
              if(dist <= (cr/100)){
                used[j]=true; const w=q.w||0; sumW+=w; sumNX+=q.nx*w; sumNY+=q.ny*w;
              }
            }
            if(sumW>0){ clusters.push({ nx:sumNX/sumW, ny:sumNY/sumW, w:sumW }); }
          }
          markers = clusters;
        } else {
          markers = sentIdx.map(it=>({ nx:Number(it.nx||0), ny:Number(it.ny||0), w:Math.max(0, Number(it.cntTW||0)) }));
        }
  // Apply Min occ threshold to markers
  const minThrM = Math.max(1, Number(state.minCount||1));
  const markersF = markers.filter(it=> Number(it.w||0) >= minThrM);
  const maxW = markersF.reduce((m,c)=> Math.max(m, c.w||0), 0) || 1;
  for(const it of markersF){
          const cx = Math.round((Number(it.nx||0))*10000)/100;
          const cy = Math.round((Number(it.ny||0))*10000)/100;
          // Outer ring shows sentry range
          const ring = document.createElementNS('http://www.w3.org/2000/svg','circle');
          ring.setAttribute('cx', cx+'%'); ring.setAttribute('cy', cy+'%');
          ring.setAttribute('r', String(Number(senPct||0)));
          ring.setAttribute('fill', 'rgba(135,206,235,0.06)');
          ring.setAttribute('stroke', 'rgba(135,206,235,0.75)');
          ring.setAttribute('stroke-width', '1.2');
          ring.setAttribute('style','filter: drop-shadow(0 0 4px rgba(135,206,235,0.45))');
          g.appendChild(ring);
          // Center dot shows density
          const dot = document.createElementNS('http://www.w3.org/2000/svg','circle');
          dot.setAttribute('cx', cx+'%'); dot.setAttribute('cy', cy+'%');
          dot.setAttribute('r', '1.0');
          const alpha = 0.35 + 0.5 * Math.max(0, Math.min(1, Number(it.w||0) / (Number(maxW||1))));
          dot.setAttribute('fill', `rgba(135,206,235,${alpha.toFixed(3)})`);
          dot.setAttribute('stroke', 'rgba(255,255,255,0.65)');
          dot.setAttribute('stroke-width', '0.4');
          g.appendChild(dot);
        }
      }
      // Draw sentry hotspots overlay (4% grouping) under spots
      function renderSentryHotspots(){
        if(!state.hotSentries) return;
        if(!Array.isArray(sentIdx) || !sentIdx.length) return;
        const r = 6; // increased to 6% for more prominent hotspots
        // Build simple points from sentIdx, weighted by cntTW
        const pts = sentIdx.map(it=>({ nx:Number(it.nx||0), ny:Number(it.ny||0), w:Math.max(0, Number(it.cntTW||0)) }));
        if(!pts.length) return;
        // Greedy clustering by radius r%
        const used = new Array(pts.length).fill(false);
        const clusters=[];
        for(let i=0;i<pts.length;i++){
          if(used[i]) continue;
          const seed = pts[i];
          let sumW=0,sumNX=0,sumNY=0, count=0;
          for(let j=i;j<pts.length;j++){
            if(used[j]) continue; const q=pts[j];
            const dx = seed.nx - q.nx; const dy = seed.ny - q.ny; const dist = Math.hypot(dx,dy);
            if(dist <= (r/100)){
              used[j]=true; const w=q.w||0; sumW+=w; sumNX+=q.nx*w; sumNY+=q.ny*w; count++;
            }
          }
          if(sumW<=0) continue;
          clusters.push({ nx:sumNX/sumW, ny:sumNY/sumW, w:sumW });
        }
  if(!clusters.length) return;
  // Min occ threshold for hotspots
  const minThrH = Math.max(1, Number(state.minCount||1));
  const clustersF = clusters.filter(c=> Number(c.w||0) >= minThrH);
  if(!clustersF.length) return;
  // Normalize weights for opacity
  const maxW = clustersF.reduce((m,c)=> Math.max(m, c.w), 0) || 1;
        const g = document.createElementNS('http://www.w3.org/2000/svg','g');
        g.setAttribute('data-layer','sentry-hotspots');
        // Put as first child to render under spots
        svg.insertBefore(g, svg.firstChild);
  for(const c of clustersF){
          const cx = Math.round((c.nx||0)*10000)/100; const cy = Math.round((c.ny||0)*10000)/100;
          const circ = document.createElementNS('http://www.w3.org/2000/svg','circle');
          circ.setAttribute('cx', cx+'%'); circ.setAttribute('cy', cy+'%');
          circ.setAttribute('r', String(r));
          const opacity = 0.18 + 0.45 * (Math.max(0, Math.min(1, c.w/maxW)));
          circ.setAttribute('fill', `rgba(80,160,255,${opacity.toFixed(3)})`);
          circ.setAttribute('stroke', 'rgba(110,170,255,0.55)');
          circ.setAttribute('stroke-width', '0.9');
          g.appendChild(circ);
        }
      }
      // Blend sentry pressure into contest and finalize derived items
      const finalized = perf.map(s=>{
        const npt = norm(s.x, s.y); const sp = sentryPressureFor(Number(npt.cx||0)/100, Number(npt.cy||0)/100);
        const contest = Math.round(0.7*sp.pressure + 0.3*Number(s._contResidual||0));
        let rankVal = (state.basis==='contest')? contest : Number(s.avg||0);
        const topSentriesShort = (sp.top||[]).map(o=>`${Math.round(o.x)},${Math.round(o.y)}:${o.count}`).join('|');
        return { spot:s.spot, x:s.x, y:s.y, count:s.count, avgSeconds:rankVal, avg:Number(s.avg||0), median:Number(s.median||0), contest, sentryTop:(sp.top||[]), sentryTopStr:topSentriesShort, senPressure:sp.pressure, senWithin: !!sp.within };
      });
      // Replace perf with finalized values for ranking and rendering
      const perf2 = finalized;
    let perfForRanking = perf2;
  if(Number(state.cluster||0) > 0){ perfForRanking = clusterize(perf2, Number(state.cluster)); }
    let filteredForRanking = perfForRanking;
    if(clusterOn){ filteredForRanking = perfForRanking.filter(s=> Number(s.count||0) >= Number(state.minCount||1)); }
        if(state.mode==='best'){
          if(state.basis==='contest'){
          best = filteredForRanking.slice().sort((a,b)=> (Number(a.contest||0)-Number(b.contest||0))||(Number(b.count||0)-Number(a.count||0))).slice(0, topN);
        } else {
          best = filteredForRanking.slice().sort((a,b)=> (Number(b.avgSeconds||0)-Number(a.avgSeconds||0))||(Number(b.count||0)-Number(a.count||0))).slice(0, topN);
        }
      } else {
          if(state.basis==='contest'){
          const wsrc = filteredForRanking.slice();
          worst = wsrc.sort((a,b)=> (Number(b.contest||0)-Number(a.contest||0))||(Number(b.count||0)-Number(a.count||0))).slice(0, topN);
        } else {
          const wsrc = filteredForRanking.slice().filter(s=> state.includeZeroWorst ? true : (Number(s.avgSeconds||0))>0);
          worst = wsrc.sort((a,b)=> (Number(a.avgSeconds||0)-Number(b.avgSeconds||0))||(Number(b.count||0)-Number(a.count||0))).slice(0, topN);
        }
      }
  function addSpot(list, cls){
    function colorForContest(d){ const t = Math.max(0, Math.min(1, Number(d||0)/100)); const h = 120*(1-t); const stroke = `hsl(${h} 80% 55%)`; const fill = `hsla(${h} 80% 55% / 0.32)`; return {stroke, fill}; }
    list.forEach(s=>{
      const {cx,cy}=norm(s.x,s.y);
      const key=String(s.spot||'');
  const drawIcon = false;
      const ring = document.createElementNS('http://www.w3.org/2000/svg','circle');
      ring.setAttribute('cx',cx+'%'); ring.setAttribute('cy',cy+'%');
      if(drawIcon){
        // Small ring for minimap icon style
        const iconR = 1.2;
        ring.setAttribute('r', String(iconR));
      } else {
        // Classic coverage circle
        ring.setAttribute('r', String(obsPct));
      }
      let klass = 'spot ' + (state.basis==='contest' ? 'neutral' : cls);
      if(state.basis==='contest'){ const d = Number(s.contest||0); if(d>=80) klass+=' danger-veryhigh'; else if(d>=60) klass+=' danger-high'; }
      if(isPinned(key)) klass+=' pinned';
      ring.setAttribute('class',klass);
      ring.setAttribute('data-spot',key);
      ring.setAttribute('data-avg',String(s.avg||0));
      ring.setAttribute('data-count',String(s.count||0));
      if(s.contest!=null){ ring.setAttribute('data-contest', String(s.contest)); }
      ring.setAttribute('data-cx',String(cx)); ring.setAttribute('data-cy',String(cy));
      if(s.sentryTopStr){ ring.setAttribute('data-sentries', s.sentryTopStr); }
      if(s.senPressure!=null){ ring.setAttribute('data-senp', String(s.senPressure)); }
      if(s.senWithin!=null){ ring.setAttribute('data-senhit', s.senWithin? '1':'0'); }
      // Color the ring appropriately
      if(state.basis==='contest'){
        const {stroke, fill} = colorForContest(Number(s.contest||0));
        ring.style.stroke = stroke;
        ring.style.fill = fill;
        ring.setAttribute('stroke-width', '1');
      }
      svg.appendChild(ring);
      const dot=document.createElementNS('http://www.w3.org/2000/svg','circle');
      dot.setAttribute('cx',cx+'%'); dot.setAttribute('cy',cy+'%');
      dot.setAttribute('r', isPinned(key)? '1.6' : '1.0'); dot.setAttribute('class','pindot');
      let stroke = isPinned(key)? '#fbbf24' : (cls==='best'? '#34d399' : (cls==='worst'? '#ff6b6b' : 'rgba(255,215,0,0.85)'));
      if(state.basis==='contest' && !isPinned(key)){
        stroke = colorForContest(Number(s.contest||0)).stroke;
      }
      dot.style.fill = stroke; dot.setAttribute('opacity','0.95'); svg.appendChild(dot);
      ring.addEventListener('click', ()=> togglePin(key)); dot.addEventListener('click', ()=> togglePin(key));
    });
  }
  // hotspots and sentry markers first (underlay)
  renderSentryHotspots();
  renderSentryMarkers();
  if(state.mode==='best') addSpot(best,'best'); else addSpot(worst,'worst');
      if(root.querySelector('#wvGrid').checked){ const g=document.createElementNS('http://www.w3.org/2000/svg','g'); for(let i=0;i<=10;i++){ const p=i*10; const v1=document.createElementNS('http://www.w3.org/2000/svg','line'); v1.setAttribute('x1',p+'%'); v1.setAttribute('y1','0%'); v1.setAttribute('x2',p+'%'); v1.setAttribute('y2','100%'); v1.setAttribute('stroke','rgba(255,255,255,.08)'); v1.setAttribute('stroke-width','0.3'); g.appendChild(v1); const v2=document.createElementNS('http://www.w3.org/2000/svg','line'); v2.setAttribute('x1','0%'); v2.setAttribute('y1',p+'%'); v2.setAttribute('x2','100%'); v2.setAttribute('y2',p+'%'); v2.setAttribute('stroke','rgba(255,255,255,.08)'); v2.setAttribute('stroke-width','0.3'); g.appendChild(v2);} svg.insertBefore(g, svg.firstChild); }
  
  // status line removed
  // update legend message based on vision mode/basis
    const legend = root.querySelector('#wvLegend');
  if(legend){ if(state.basis==='contest'){ legend.textContent = 'Green = Safest (low contest), Red = Most contested (high contest). Contest couples local sentry pressure with short-lifetime residuals.'; } else { legend.textContent = 'Green = Best avg lifetime, Red = Worst.'; } }
      // lists
  function listify(arr){ if(!arr.length) return `<div class='wv-sub'>No data</div>`; return `<ul class='wv-simple'>`+arr.map((s,idx)=>{ const mmA = Math.floor((Number(s.avg||0))/60), ssA = (Number(s.avg||0))%60; const coords = (s.spot||'').replace(/\[|\]|\s/g,''); const pin = isPinned(s.spot) ? 'Unpin' : 'Pin'; const contestBadge = (state.basis==='contest')? `<span class='wv-badge'>contest ${Math.round(Number(s.contest||0))}</span>`:''; const timeBadge = `<span class='wv-badge'>avg ${mmA}m ${ssA}s</span>`; return `<li data-spot='${s.spot||''}'><span style='display:flex;align-items:center;gap:8px'><span class='wv-badge' style='min-width:54px;text-align:center'>Ward ${idx+1}</span><span class='wv-sub' style='opacity:.8'>${coords}</span></span><span style='display:flex;gap:6px'>${contestBadge}${timeBadge}${s.count? `<span class='wv-badge'>x${s.count}</span>`:''}<button class='tab' data-pin='${esc(String(s.spot||''))}'>${pin}</button></span></li>`; }).join('')+`</ul>`; }
      const bestEl=root.querySelector('#wvBest'); if(bestEl) bestEl.innerHTML = listify(best);
      const worstEl=root.querySelector('#wvWorst'); if(worstEl) worstEl.innerHTML = listify(worst);
      // extras
      if(showExtras){ const pl=extras.wardPlayers||{}; const divP=root.querySelector('#wvPlayers'); if(divP){ divP.innerHTML = `<div class='wv-sub' style='opacity:.9'>Most Placed</div>` + (Array.isArray(pl.mostPlaced)? `<ul class='wv-simple'>${pl.mostPlaced.map(p=>`<li><span>${esc(p.name||'')}</span><span class='wv-badge'>x${p.count||0}</span></li>`).join('')}</ul>`:`<div class='wv-sub'>no data</div>`) + `<div class='wv-sub' style='opacity:.9;margin-top:6px'>Most Dewards</div>` + (Array.isArray(pl.mostDewards)? `<ul class='wv-simple'>${pl.mostDewards.map(p=>`<li><span>${esc(p.name||'')}</span><span class='wv-badge'>x${p.count||0}</span></li>`).join('')}</ul>`:`<div class='wv-sub'>no data</div>`) + `<div class='wv-sub' style='opacity:.9;margin-top:6px'>Longest Avg</div>` + (Array.isArray(pl.longestAvg)? `<ul class='wv-simple'>${pl.longestAvg.map(p=>{ const sec=Number(p.avgSeconds||0); const mm=Math.floor(sec/60), ss=sec%60; return `<li><span>${esc(p.name||'')}</span><span class='wv-badge'>${mm}m ${ss}s avg</span><span class='wv-badge'>n=${p.samples||0}</span></li>`; }).join('')}</ul>`:`<div class='wv-sub'>no data</div>`); }
        const lg=root.querySelector('#wvLongest'); if(lg){ const arr=extras.wardLongest||[]; lg.innerHTML = Array.isArray(arr)? `<ul class='wv-simple'>${arr.map(o=>{ const mx=Number(o.maxSeconds||0); const mm=Math.floor(mx/60), ss=mx%60; return `<li><span>${esc(o.spot||'')}</span><span class='wv-badge'>${mm}m ${ss}s</span><span class='wv-badge'>x${o.count||0}</span></li>`; }).join('')}</ul>` : `<div class='wv-sub'>no data</div>`; }
      }
      // hover
  const tip = root.querySelector('#wvTip');
    function fmtMMSS(secs){ const s=Math.max(0,Math.floor(Number(secs||0))); const m=Math.floor(s/60); const r=s%60; return `${m}m ${r}s`; }
  function showTipFromSpot(el){ if(!tip) return; const avg=Number(el.getAttribute('data-avg')||0); const cnt=Number(el.getAttribute('data-count')||0); const label=String(el.getAttribute('data-spot')||''); const timeLbl = timeWindow().label; const teamLbl = state.team||'All'; const contest = Number(el.getAttribute('data-contest')||NaN); const tier = isFinite(contest)? (contest>=80?'Very High': contest>=60?'High': contest>=40?'Medium': contest>=20?'Low':'Very Low') : null; const basisLbl = state.basis==='contest' ? `Contest ${isFinite(contest)? Math.round(contest):'-'}` : `Avg ${fmtMMSS(avg)}`; let sentInfo=''; if(state.basis==='contest'){ const senp = Number(el.getAttribute('data-senp')||NaN); const str = String(el.getAttribute('data-sentries')||''); const inRange = String(el.getAttribute('data-senhit')||'')==='1'; const chips = str? str.split('|').slice(0,3).map(s=>{ const [pt,c]=s.split(':'); return `${esc(pt)} x${esc(c||'')}`; }).join(' · ') : ''; const parts = []; if(isFinite(senp)) parts.push(`pressure ${Math.round(senp)}`); parts.push(inRange? 'in-range' : 'no-sentry'); if(chips) parts.push(chips); sentInfo = parts.length? `<div class='tt-row'><span class='tt-badge'>${parts.join(' | ')}</span></div>` : ''; } const extraContest = (state.basis==='contest' && isFinite(contest))? `<span class='tt-badge'>${basisLbl}</span><span class='tt-badge'>${tier}</span>`:''; tip.innerHTML = `<div class='tt-title'>${esc(label)}</div><div class='tt-row'>${extraContest}<span class='tt-badge'>Avg ${fmtMMSS(avg)}</span><span class='tt-badge'>n=${cnt}</span></div>${sentInfo}<div class='tt-meta'>${esc(teamLbl)} · ${esc(timeLbl)}</div>`; tip.classList.add('show'); tip.setAttribute('aria-hidden','false'); }
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
  // Reset button binding
  try{ const rst=root.querySelector('#wvReset'); if(rst){ rst.addEventListener('click',()=>{
    state = { mode: (cfg && cfg.options && cfg.options.modeDefault) || 'best', team:'', player:'', time:'', overlay:true, grid:false, hotSentries:false, showSentries:false, minCount:1, topN:'all', basis: BASIS_DEFAULT, includeZeroWorst:false, pins:[], pquery:'', tquery:'', cluster:0 };
    // Clear URL params
    try{ const sp = new URLSearchParams(); replaceUrl(sp); }catch(_e){}
    // Clear storage
    try{ Object.keys(LS_KEY).forEach(k=> writeStorage(LS_KEY[k], '')); }catch(_e){}
    // Reset toggles
    try{ const ov=root.querySelector('#wvOv'); if(ov){ ov.checked = true; } }catch(_e){}
    try{ const gr=root.querySelector('#wvGrid'); if(gr){ gr.checked = false; } }catch(_e){}
    try{ const ht=root.querySelector('#wvHot'); if(ht){ ht.checked = false; } }catch(_e){}
    try{ const smk=root.querySelector('#wvSentries'); if(smk){ smk.checked = false; } }catch(_e){}
    try{ const zw=root.querySelector('#wvZeroWorst'); if(zw){ zw.checked = false; const lab=zw.closest('label'); if(lab){ lab.style.display = (state.mode==='worst')? '' : 'none'; } } }catch(_e){}
    // Reset active buttons
    root.querySelectorAll('#wvTabs .tab').forEach(b=> b.classList.toggle('active',(b.dataset.wmode||'')===state.mode));
    setActiveTime(); setActiveMin(); setActiveTop(); setActiveBasis(); setActiveCluster();
    persistState(); render();
  }); } }catch(_e){}
  }
  window.WardViewer = { mount };
})();

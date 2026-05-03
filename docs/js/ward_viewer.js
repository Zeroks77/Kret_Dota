(function(){
  function esc(s){ return String(s||'').replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[c])); }
  function h(html){ const t=document.createElement('template'); t.innerHTML=html.trim(); return t.content.firstElementChild; }
  function injectBaseStyles(){
    if(document.getElementById('wv-base-styles')) return;
  const css = `
  .wv-wardgrid{display:grid;grid-template-columns:1.2fr .8fr;gap:10px;align-items:start}
    @media (max-width: 980px){.wv-wardgrid{grid-template-columns:1fr}}
  .wv-wardmap{margin:6px 0 0;position:relative;width:100%;aspect-ratio:1/1;min-height:260px;background:#091022;border:1px solid var(--border,rgba(255,255,255,.08));border-radius:12px;overflow:hidden}
    .wv-wardmap .mapimg{position:absolute;inset:0;width:100%;height:100%;object-fit:fill;pointer-events:none;user-select:none}
    .wv-wardmap svg{position:absolute;inset:0;width:100%;height:100%}
    .wv-wardmap .spot{fill:rgba(255,255,255,.18);stroke:rgba(255,255,255,.5);stroke-width:1;transition:all .15s}
    .wv-wardmap .spot.best{fill:rgba(52,211,153,.25);stroke:#34d399;stroke-width:1.5}
    .wv-wardmap .spot.worst{fill:rgba(255,107,107,.25);stroke:#ff6b6b;stroke-width:1.5}
  .wv-wardmap .spot.elite{fill:rgba(189,255,164,.22);stroke:#d8f5a2;stroke-width:2.2;filter:drop-shadow(0 0 12px rgba(140,255,164,.5))}
  .wv-wardmap .spot.neutral{fill:rgba(255,255,255,.18);stroke:rgba(255,255,255,.45);stroke-width:1}
  /* danger emphasis */
  .wv-wardmap .spot.danger-high{fill:rgba(255,99,99,.35);stroke:#ff5c5c;stroke-width:2}
  .wv-wardmap .spot.danger-veryhigh{fill:rgba(255,45,45,.45);stroke:#ff2d2d;stroke-width:2.2;filter:drop-shadow(0 0 10px rgba(255,64,64,.65))}
    .wv-wardmap.enhanced svg .spot.best.hl{filter:drop-shadow(0 0 8px rgba(52,211,153,.6));stroke-width:2 !important}
    .wv-wardmap.enhanced svg .spot.worst.hl{filter:drop-shadow(0 0 8px rgba(255,107,107,.6));stroke-width:2 !important}
    .wv-wardmap.enhanced.highlighting svg .spot:not(.hl){opacity:.28}
  .wv-wardmap svg .spot.pinned{stroke:#fbbf24 !important; fill:rgba(251,191,36,.18) !important; stroke-width:2 !important}
  .wv-wardmap svg .pindot{fill:#fbbf24; opacity:.95}
  .wv-wardmap svg .pindot.elite{fill:#d8f5a2;filter:drop-shadow(0 0 8px rgba(216,245,162,.65))}
  .wv-wardmap svg .spot.selected{ stroke:#e8d5a3 !important; fill:rgba(200,170,110,.16) !important; stroke-width:2.2 !important; filter:drop-shadow(0 0 10px rgba(200,170,110,.55)) }
  /* focus visibility for keyboard users */
  .wv-wardmap svg .spot:focus{ outline:none; stroke:#e8d5a3 !important; stroke-width:2.4 !important; filter:drop-shadow(0 0 8px rgba(200,170,110,.6)); }
  /* tooltip */
  .wv-tooltip{position:absolute;pointer-events:none;z-index:5;min-width:150px;max-width:240px;background:rgba(15,23,42,.95);color:#e5ecf8;border:1px solid rgba(255,255,255,.12);border-radius:8px;padding:6px 8px;box-shadow:0 6px 18px rgba(0,0,0,.35);transform:translate(-50%, -110%);opacity:0;transition:opacity .12s}
  .wv-tooltip.show{opacity:1}
  .wv-tooltip .tt-title{font-weight:600;font-size:12px;margin:0 0 4px;opacity:.95}
  .wv-tooltip .tt-row{display:flex;gap:8px;align-items:center;font-size:12px;color:#c7d2e5}
  .wv-tooltip .tt-badge{display:inline-block;background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.12);border-radius:999px;padding:2px 8px;font-size:11px;color:#e5ecf8}
  .wv-tooltip .tt-meta{font-size:11px;color:#9aa7bd;margin-top:4px}
  /* controls */
  .wv-controls{display:grid;gap:8px 12px;align-items:start;background:rgba(255,255,255,.03);border:1px solid rgba(255,255,255,.08);border-radius:10px;padding:10px}
  #wvTabs{border-bottom:none;margin:0;gap:8px}
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
    .wv-controls.wv-controls--tune{grid-template-columns:auto auto auto 1fr}
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
  .wv-list .item.active{outline:2px solid rgba(200,170,110,.5);background:linear-gradient(180deg,rgba(200,170,110,.2),rgba(200,170,110,.08))}
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
  /* Details drawer */
  .wv-details { position: fixed; top:0; right:0; width: 360px; max-width:92vw; height: 100%; background:#0f152c; border-left:1px solid rgba(255,255,255,.08); box-shadow: -8px 0 24px rgba(0,0,0,0.45); transform: translateX(100%); transition: transform .18s ease-out; z-index: 1001; }
  .wv-details.open { transform: translateX(0); }
  .wv-details-inner { padding:12px; height:100%; display:flex; flex-direction:column; gap:10px; }
  .wv-details-header { display:flex; align-items:center; justify-content:space-between; gap:8px; }
  .wv-details-title { font-weight:600; font-size:15px; }
  .wv-detail-row { display:flex; flex-wrap:wrap; gap:6px; align-items:center; }
  .wv-detail-badge { display:inline-block; padding:4px 8px; border-radius:999px; background:rgba(255,255,255,.08); color:#eef3fb; font-size:12px; border:1px solid rgba(255,255,255,.12) }
  .wv-details .hint { color:#9aa7bd; font-size:12px }
  /* Spot flyout */
  .wv-spot-flyout { position:absolute; min-width:220px; max-width:320px; max-height:calc(100% - 16px); overflow:auto; overscroll-behavior:contain; background:rgba(15,23,42,.98); color:#e5ecf8; border:1px solid rgba(255,255,255,.12); border-radius:10px; padding:10px; box-shadow:0 10px 26px rgba(0,0,0,.5); z-index:6; display:none }
  .wv-spot-flyout.show { display:block }
  @media (prefers-reduced-motion: reduce){ .wv-spot-flyout{ transition:none } }
  .wv-spot-flyout.show { display:block }
  .wv-spot-flyout .hdr { display:flex; align-items:center; justify-content:space-between; gap:8px; margin-bottom:6px }
  .wv-spot-flyout .title { font-weight:600; font-size:14px }
  .wv-spot-flyout .row { display:flex; flex-wrap:wrap; gap:6px }
  .wv-spot-flyout .badge { display:inline-block; padding:4px 8px; border-radius:999px; background:rgba(255,255,255,.08); border:1px solid rgba(255,255,255,.12); font-size:12px }
  .wv-wardmap svg .spot-range{fill:rgba(109,177,255,.10);stroke:rgba(109,177,255,.62);stroke-width:.8;pointer-events:none}
  /* mini charts */
  .wv-prog { height:8px; background:rgba(255,255,255,.06); border:1px solid rgba(255,255,255,.12); border-radius:6px; overflow:hidden; }
  .wv-prog .fill { height:100%; background:linear-gradient(90deg, rgba(110,180,255,.9), rgba(110,175,255,.55)); box-shadow:0 0 8px rgba(110,180,255,.35) inset; }
  .wv-stack { display:flex; height:10px; border:1px solid rgba(255,255,255,.12); border-radius:6px; overflow:hidden; }
  .wv-stack .seg { height:100%; }
  .wv-seg-inst { background:rgba(255,64,64,.8); }
  .wv-seg-short { background:rgba(255,140,64,.75); }
  .wv-seg-med { background:rgba(255,210,64,.75); }
  .wv-seg-long { background:rgba(80,200,120,.8); }
  .wv-stack-legend { display:flex; gap:6px; flex-wrap:wrap; margin-top:4px; }
  .wv-stack-legend .key { display:inline-flex; align-items:center; gap:4px; font-size:11px; color:#c9d3ea }
  .wv-stack-legend .dot { width:10px; height:10px; border-radius:3px; display:inline-block; }
  .wv-friendly .line { margin:6px 0; }
  .wv-friendly .mono { font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace; }
  .wv-intro{margin:0 0 12px}
  .wv-introbar{display:flex;flex-wrap:wrap;align-items:flex-start;justify-content:space-between;gap:12px;padding:12px 14px;border:1px solid rgba(255,255,255,.09);border-radius:14px;background:linear-gradient(140deg,rgba(110,180,255,.10),rgba(200,170,110,.05) 55%,rgba(255,255,255,.03));box-shadow:0 10px 24px rgba(0,0,0,.18)}
  .wv-intro-main{display:flex;flex-direction:column;gap:4px;min-width:0;max-width:640px}
  .wv-intro-kicker{font-size:10px;text-transform:uppercase;letter-spacing:.7px;color:var(--muted,#93a0b4);margin:0 0 6px}
  .wv-intro-value{font-size:18px;font-weight:700;line-height:1.15;margin:0;color:#eef3fb}
  .wv-intro-text{font-size:12px;line-height:1.45;color:#c9d3ea}
  .wv-intro-meta{display:flex;flex-wrap:wrap;gap:6px;align-content:flex-start}
  .wv-intro-chip{display:inline-flex;align-items:center;padding:4px 8px;border-radius:999px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.12);font-size:11px;color:#d9e2f2}
  .wv-spotcards{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:10px}
  .wv-spotitem{padding:10px 11px;border:1px solid rgba(255,255,255,.08);border-radius:12px;background:linear-gradient(180deg,rgba(255,255,255,.045),rgba(255,255,255,.02));cursor:pointer;transition:border-color .15s ease, transform .15s ease, background .15s ease}
  .wv-spotitem:hover{border-color:rgba(255,255,255,.18);transform:translateY(-1px)}
  .wv-spotitem.bestcard{border-color:rgba(52,211,153,.22)}
  .wv-spotitem.worstcard{border-color:rgba(255,107,107,.22)}
  .wv-spotitem.elite{box-shadow:0 0 0 1px rgba(216,245,162,.18),0 10px 28px rgba(22,163,74,.10)}
  .wv-spothead{display:flex;align-items:flex-start;justify-content:space-between;gap:10px}
  .wv-spotmeta{display:flex;flex-direction:column;gap:3px;min-width:0}
  .wv-rank{display:inline-flex;align-items:center;justify-content:center;min-width:54px;padding:4px 10px;border-radius:999px;background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.12);font-size:11px;color:#eef3fb}
  .wv-spottitle{font-size:14px;font-weight:600;color:#eef3fb;line-height:1.25}
  .wv-spotcoords{font-size:11px;color:var(--muted,#93a0b4)}
  .wv-why{margin-top:6px;font-size:12px;line-height:1.45;color:#c9d3ea}
  .wv-chipline{display:flex;flex-wrap:wrap;gap:6px;margin-top:8px}
  .wv-playerline{margin-top:8px;font-size:12px;line-height:1.45;color:#c9d3ea}
  .wv-playerline b{color:#eef3fb}
  .wv-counterline{margin-top:8px;padding:8px 9px;border-radius:10px;background:rgba(200,170,110,.08);border:1px solid rgba(200,170,110,.16);font-size:12px;line-height:1.45;color:#e8dcc2}
  .wv-counterline b{display:block;color:#f3e6c5;margin-bottom:4px}
  .wv-counterlist{margin:0;padding-left:18px;display:flex;flex-direction:column;gap:4px}
  .wv-counterlist li{margin:0}
  .wv-counteritem{display:flex;align-items:flex-start;justify-content:space-between;gap:8px}
  .wv-countertext{flex:1;min-width:0}
  .wv-counteractions{display:inline-flex;flex-wrap:wrap;gap:4px;flex:0 0 auto;margin-left:6px}
  .wv-mini-action{padding:3px 7px;border:1px solid rgba(255,255,255,.14);background:rgba(255,255,255,.06);color:#eef3fb;border-radius:999px;font-size:10px;line-height:1;cursor:pointer}
  .wv-mini-action:hover{border-color:rgba(255,255,255,.24);background:rgba(255,255,255,.10)}
  .wv-mini-action:focus{outline:2px solid rgba(110,180,255,.55);outline-offset:2px}
  .wv-trendspots{margin:0;padding-left:18px;display:flex;flex-direction:column;gap:6px}
  .wv-trendspots li{margin:0}
  .wv-trendspotline{display:flex;align-items:flex-start;justify-content:space-between;gap:8px}
  .wv-trendspotmeta{flex:1;min-width:0;color:#eef3fb}
  .wv-trendspotmeta .count{color:var(--muted,#93a0b4);font-size:11px;margin-left:6px}
  .wv-sidecol{display:flex;flex-direction:column;gap:12px;min-height:0}
  .wv-panel{padding:10px 11px;border:1px solid rgba(255,255,255,.08);border-radius:14px;background:linear-gradient(180deg,rgba(255,255,255,.045),rgba(255,255,255,.02));display:flex;flex-direction:column;min-height:0}
  .wv-panel-head{display:flex;align-items:flex-end;justify-content:space-between;gap:10px;margin:0 0 8px}
  .wv-panel-note{font-size:11px;color:var(--muted,#93a0b4)}
  .wv-panel-scroll{max-height:310px;overflow:auto;padding-right:4px}
  .wv-actions{display:flex;flex-wrap:wrap;gap:6px;margin-top:8px}
  .wv-trendlist{display:flex;flex-direction:column;gap:10px}
  .wv-trendcard{padding:11px 12px;border:1px solid rgba(255,255,255,.08);border-radius:14px;background:linear-gradient(180deg,rgba(255,255,255,.05),rgba(255,255,255,.02))}
  .wv-trendtop{display:flex;align-items:flex-start;justify-content:space-between;gap:10px}
  .wv-trendsub{font-size:12px;line-height:1.45;color:#c9d3ea}
  @media (max-width: 640px){.wv-introbar{padding:10px 11px}}
  .wv-minibar { display:flex; gap:4px; align-items:flex-end; height:26px; margin-top:4px }
  .wv-minibar .b { flex:1; position:relative; height:100%; border:1px solid rgba(255,255,255,.12); background:rgba(255,255,255,.04); border-radius:3px; overflow:hidden }
  .wv-minibar .b .fill { position:absolute; left:0; right:0; bottom:0; height:0; background:linear-gradient(180deg, rgba(110,180,255,.9), rgba(110,175,255,.55)); box-shadow:0 0 8px rgba(110,180,255,.35) inset }
  .wv-minibar .cap { display:flex; justify-content:space-between; font-size:10px; color:#9aa7bd; margin-top:2px }
  /* Respect user motion preferences */
  @media (prefers-reduced-motion: reduce){
    .wv-wardmap .spot{ transition:none }
    .wv-tooltip{ transition:none }
    .wv-details, .wv-settings{ transition:none }
  }
  /* High-contrast/forced colors: ensure focus is visible */
  @media (forced-colors: active){
    .wv-wardmap .spot:focus{ outline:1px solid Highlight; outline-offset:2px; forced-color-adjust:auto }
  }
    `;
    const style = document.createElement('style'); style.id='wv-base-styles'; style.textContent=css; document.head.appendChild(style);
  }
  function boundsFor(mc){ const asset = (mc && mc.major && mc.current && mc.major[mc.current]) ? mc.major[mc.current] : null; return {asset}; }
  function mount(host, cfg){
    injectBaseStyles();
    if(!host) return;
    // Canonicalize URL params in-place if shared utility is present
    try{ if(window && window.UrlParams && typeof window.UrlParams.canonicalizeInPlace==='function'){ window.UrlParams.canonicalizeInPlace(); } }catch(_e){}
    const data = cfg && cfg.data || {}; const spots = Array.isArray(data.spots) ? data.spots : [];
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
  let state = { mode: (cfg && cfg.options && cfg.options.modeDefault) || 'best', team:'', player:'', time:'', overlay:true, grid:false, hotSentries:false, showSentries:false, minCount:1, topN:'all', basis: BASIS_DEFAULT, includeZeroWorst:false, pins:[], pquery:'', tquery:'', cluster:0, wspot:'' };
    // URL/Storage helpers
    function getSP(){ try{ return new URLSearchParams(location.search); }catch(_e){ return new URLSearchParams(); } }
    function replaceUrl(sp){ try{ const url = location.pathname + (sp.toString()? ('?'+sp.toString()):'') + location.hash; history.replaceState(null, '', url); }catch(_e){} }
    const LS_KEY = {
  mode:'wv_mode', time:'wv_time', team:'wv_team', player:'wv_player', ov:'wv_ov', grid:'wv_grid', hot:'wv_hot', sen:'wv_sen', min:'wv_min', top:'wv_top', basis:'wv_basis', zworst:'wv_zworst', pins:'wv_pins', pquery:'wv_pq', cluster:'wv_cluster', wspot:'wv_wspot'
    };
    function readStorage(k, def){ try{ const v = localStorage.getItem(k); if(v===null || v===undefined) return def; return v; }catch(_e){ return def; } }
    function writeStorage(k, v){ try{ if(v===undefined || v===null || v===''){ localStorage.removeItem(k); } else { localStorage.setItem(k, String(v)); } }catch(_e){} }
    function parsePlayerSelection(raw){ try{ const src = Array.isArray(raw) ? raw.join(',') : String(raw||''); const out=[]; const seen=new Set(); for(const partRaw of src.split(',')){ const part=String(partRaw||'').trim(); if(!/^\d+$/.test(part)) continue; const id=Number(part); if(!(id>0) || seen.has(id)) continue; seen.add(id); out.push(id); } return out; }catch(_e){ return []; } }
    function serializePlayerSelection(raw){ return parsePlayerSelection(raw).join(','); }
    let playerSelectionCacheKey = null;
    let playerSelectionCacheVal = null;
    function currentPlayerSelection(){ const key = serializePlayerSelection(state.player); if(key===playerSelectionCacheKey && playerSelectionCacheVal) return playerSelectionCacheVal; const ids = parsePlayerSelection(key); playerSelectionCacheKey = key; playerSelectionCacheVal = { ids, set:new Set(ids), hasAny:ids.length>0, single:ids.length===1 ? ids[0] : 0 }; return playerSelectionCacheVal; }
    function playerSelectionMatches(aid, sel){ const cur = sel || currentPlayerSelection(); return !cur.hasAny || cur.set.has(Number(aid||0)); }
    const ALLOWED_MODE = new Set(['best','worst']);
    const ALLOWED_TIME = new Set(['','early','mid','earlylate','late','superlate']);
  const ALLOWED_BASIS = new Set(['lifetime','contest']);
    function hydrateState(){
  const sp = getSP();
      const urlMode = String(sp.get('wmode')||'');
      const urlTime = String(sp.get('wtime')||'');
      // Prefer canonical 'side' when present; fallback to ward-specific 'wteam'
  const urlSide = String(sp.get('side')||'');
      const urlTeamRaw = String(sp.get('wteam')||'');
  const urlTeam = urlTeamRaw || ((urlSide==='Radiant'||urlSide==='Dire'||urlSide.startsWith('team:'))? urlSide : '');
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
  const urlSpot = String(sp.get('wspot')||'');
  // Multi-player selection is ward-specific (`wplayers`); fallback to legacy single-player params.
  const urlPlayers = String(sp.get('wplayers')||'').trim();
  const urlAid  = String(sp.get('aid')||'').trim();
  const urlPl   = urlPlayers || String(sp.get('wplayer')||'').trim() || urlAid;
      const stMode = urlMode || readStorage(LS_KEY.mode, state.mode);
  const stTime = (urlTime!==''? urlTime : (sp.has('wtime')? '' : readStorage(LS_KEY.time, state.time)));
  // Respect either 'side' or 'wteam' being explicitly present in URL to suppress LS fallback
  const hasTeamParam = sp.has('wteam') || sp.has('side');
  const stTeam = (urlTeam!==''? urlTeam : (hasTeamParam? '' : readStorage(LS_KEY.team, state.team)));
  // Player: allow URL override, but optionally ignore persisted storage to default to "All"
  const stPl   = IGNORE_PLAYER_PERSIST
    ? (urlPl!=='' ? urlPl : '')
    : (urlPl!==''? urlPl : ((sp.has('wplayers') || sp.has('wplayer') || sp.has('aid'))? '' : readStorage(LS_KEY.player, state.player)));
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
  const stWs   = urlSpot!==''? urlSpot : readStorage(LS_KEY.wspot, '');
      if(ALLOWED_MODE.has(stMode)) state.mode = stMode;
      if(ALLOWED_TIME.has(stTime)) state.time = stTime;
      // team can be '', 'Radiant', 'Dire', or 'team:<id>'
      if(stTeam==='' || stTeam==='Radiant' || stTeam==='Dire' || /^team:\d+$/.test(stTeam)) state.team = stTeam;
  // player selection is a comma-separated list of account ids or ''
  { const pl = serializePlayerSelection(stPl); if(stPl==='' || pl!=='') state.player = pl; }
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
    // snap to supported grouping presets
    const choices = [0,1,2,3];
    if(!choices.includes(cr)){
      cr = choices.reduce((best,v)=> Math.abs(v-cr) < Math.abs(best-cr) ? v : best, 0);
    }
    state.cluster = cr;
  }
  state.includeZeroWorst = (String(stZw)==='1');
  state.wspot = String(stWs||'');
  
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
      // Write standardized team/side: always prefer canonical 'side' (Radiant|Dire or team:<id>)
      if(state.team==='Radiant' || state.team==='Dire' || String(state.team||'').startsWith('team:')){
        setOrRemove('side', state.team, '');
        try{ sp.delete('wteam'); }catch(_e){}
      } else {
        // clear both when no team filter
        try{ sp.delete('wteam'); sp.delete('side'); }catch(_e){}
      }
  setOrRemove('wov', state.overlay? '1':'0', def.ov);
  setOrRemove('wgrid', state.grid? '1':'0', def.grid);
  setOrRemove('whot', state.hotSentries? '1':'0', def.hot);
  setOrRemove('wsen', state.showSentries? '1':'0', def.sen);
      setOrRemove('wmin', String(state.minCount), def.min);
  setOrRemove('wtop', state.topN==='all'? 'all' : String(state.topN), def.top);
  setOrRemove('wbasis', state.basis, def.basis);
  
      setOrRemove('wzw', state.includeZeroWorst? '1':'0', def.zw);
      // Ward viewer keeps its own player filter to avoid colliding with page-global single-player focus.
      setOrRemove('wplayers', serializePlayerSelection(state.player), '');
      try{ sp.delete('wplayer'); }catch(_e){}
  setOrRemove('wpins', (state.pins||[]).join(','), def.pins);
  setOrRemove('wpq', state.pquery||'', def.pq);
  setOrRemove('wspot', state.wspot||'', '');
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
  if(!IGNORE_PLAYER_PERSIST){ writeStorage(LS_KEY.player, serializePlayerSelection(state.player)); }
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
  writeStorage(LS_KEY.wspot, state.wspot||'');
  
      // Clean up legacy storage key
      writeStorage('wv_metric', '');
    }
    // Build DOM
    const root = h(`
      <section class="card">
    <h2 style="margin:0 0 6px;font-size:18px">Ward Spots</h2>
  <div class="wv-sub" style="margin-bottom:6px">Ward spots filtered by time window, team, and player.</div>
  <div id="wvIntro" class="wv-intro"></div>
        <div class="wv-wardgrid">
          <div>
            <div class="wv-controls wv-controls--top" style="margin:6px 0 8px">
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
                <div id="wvPlayersPick" class="wv-list" role="listbox" aria-label="Players" aria-multiselectable="true">
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
              <div>
                <div class="wv-label">Grouping</div>
                <div id="wvCluster" class="wv-segmented">
                  <button class="seg" data-cluster="0" title="No grouping">Off</button>
                  <button class="seg" data-cluster="1" title="Merge only very close spots">Tight</button>
                  <button class="seg" data-cluster="2" title="Balanced grouping for nearby spots">Standard</button>
                  <button class="seg" data-cluster="3" title="Broader grouping for overview mode">Wide</button>
                </div>
                <div class="wv-sub">Reduce duplicates without merging entire lanes together.</div>
              </div>
              <div>
                <div class="wv-label">Map</div>
                <div id="wvMapToggles" class="wv-segmented">
                  <button class="seg" data-toggle="overlay" title="Show or hide ward markers on the map">Overlay</button>
                  <button class="seg" data-toggle="grid" title="Show a 10x10 helper grid">Grid</button>
                </div>
              </div>
              <div style="display:flex;justify-content:flex-end;align-items:flex-end">
                <button class="tab" id="wvOpenSettings" title="Open additional filters">More filters</button>
              </div>
            </div>
            <div class="wv-wardmap enhanced" id="wvMap"><img class="mapimg" id="wvMapImg" alt="" aria-hidden="true"><svg aria-label="Ward spots map" role="group" viewBox="0 0 100 100" preserveAspectRatio="none"></svg><div class="wv-tooltip" id="wvTip" role="tooltip" aria-hidden="true"></div><div class="wv-spot-flyout" id="wvFly" role="dialog" aria-label="Ward spot details" tabindex="-1"><div class="hdr"><div class="title">Vision Details</div><div style="display:flex;gap:6px"><button class="tab" id="wvFlyCopy">Copy</button><button class="tab" id="wvFlyClose" title="Close">Close</button></div></div><div id="wvFlyBody" class="wv-sub" aria-live="polite" aria-atomic="true">Pick a ward spot.</div></div></div>
            <div id="wvLive" class="sr-only" role="status" aria-live="polite" aria-atomic="true"></div>
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
                </div>
                <div style="display:flex;gap:12px;justify-content:space-between;align-items:center">
                  <label class="wv-sub" title="Include spots with 0s lifetime when showing worst list"><input type="checkbox" id="wvZeroWorst" style="vertical-align:middle;margin-right:6px">Include 0s worst</label>
                  <button class="tab" id="wvReset" title="Reset all filters to defaults">Reset</button>
                </div>
              </div>
            </div>
            <div class="wv-sub" id="wvPinsBar" style="margin-top:6px"></div>
            <div class="wv-sub" id="wvLegend" style="margin-top:6px">Green = Best avg lifetime, Red = Worst.</div>
            
            ${showExtras? `<div style="margin-top:10px">
              <div class="wv-title" style="margin:0 0 6px">Players</div>
              <div id="wvPlayers" class="wv-sub">(empty)</div>
            </div>`:''}
          </div>
          <div>
            <div class="wv-sidecol" style="margin-top:6px">
              <section class="wv-panel">
                <div class="wv-panel-head">
                  <div class="wv-title" style="margin:0">Best Spots</div>
                  <div class="wv-panel-note">scannable shortlist</div>
                </div>
                <div id="wvBest" class="wv-sub wv-panel-scroll">(empty)</div>
              </section>
              <section class="wv-panel">
                <div class="wv-panel-head">
                  <div class="wv-title" style="margin:0">Worst Spots</div>
                  <div class="wv-panel-note">punished wards</div>
                </div>
                <div id="wvWorst" class="wv-sub wv-panel-scroll">(empty)</div>
              </section>
              <section class="wv-panel">
                <div class="wv-panel-head">
                  <div class="wv-title" style="margin:0">Player Trends & Counters</div>
                  <div class="wv-panel-note">jump straight to the map</div>
                </div>
                <div id="wvTrends" class="wv-sub wv-panel-scroll">(empty)</div>
              </section>
              ${showExtras && (cfg && cfg.options && cfg.options.showLongest!==false)? `<section class="wv-panel">
                <div class="wv-panel-head">
                  <div class="wv-title" style="margin:0">Longest-lived</div>
                </div>
                <div id="wvLongest" class="wv-sub wv-panel-scroll">(empty)</div>
              </section>`:''}
            </div>
          </div>
          <!-- Global details drawer (fixed) -->
          <aside class="wv-details" id="wvDetails" aria-hidden="true" role="dialog" aria-label="Vision details">
            <div class="wv-details-inner">
              <div class="wv-details-header">
                <div class="wv-details-title">Vision Details</div>
                <div style="display:flex; gap:6px">
                  <button class="tab" id="wvDetailsCopy">Copy link</button>
                  <button class="tab" id="wvDetailsClose" title="Close">Close</button>
                </div>
              </div>
              <div id="wvDetailsBody" class="wv-sub">Pick a ward spot on the map or from the list.</div>
            </div>
          </aside>
        </div>
      </section>`);
    host.innerHTML=''; host.appendChild(root);
  // Add overlay element for settings
  const overlayEl = document.createElement('div');
  overlayEl.className = 'wv-overlay';
  host.appendChild(overlayEl);
  // Reuse overlay for details as well
    // Read initial state from URL/localStorage
    hydrateState();
    // Set default active tabs
    root.querySelectorAll('#wvTabs .tab').forEach(b=> b.classList.toggle('active',(b.dataset.wmode||'')===state.mode));
  function setActiveTime(){ const wrap=root.querySelector('#wvTime'); if(!wrap) return; wrap.querySelectorAll('.seg').forEach(b=> b.classList.toggle('active',(b.dataset.time||'')===state.time)); }
  function setActiveMin(){ const wrap=root.querySelector('#wvMin'); if(!wrap) return; wrap.querySelectorAll('.seg').forEach(b=> b.classList.toggle('active', Number(b.getAttribute('data-min')||'0')===Number(state.minCount))); }
  function setActiveTop(){ const wrap=root.querySelector('#wvTop'); if(!wrap) return; wrap.querySelectorAll('.seg').forEach(b=> b.classList.toggle('active', (b.getAttribute('data-top')||'')=== (state.topN==='all'?'all':String(state.topN)))); }
  function setActiveBasis(){ const wrap=root.querySelector('#wvBasis'); if(!wrap) return; wrap.querySelectorAll('.seg').forEach(b=> b.classList.toggle('active', (b.getAttribute('data-basis')||'')===state.basis)); }
  function setActiveCluster(){ const wrap=root.querySelector('#wvCluster'); if(!wrap) return; wrap.querySelectorAll('.seg').forEach(b=> b.classList.toggle('active', Number(b.getAttribute('data-cluster')||'0')===Number(state.cluster))); }
  function updateViewAndListLabels(){
    const bestBtn = root.querySelector('#wvTabs .tab[data-wmode="best"]');
    const worstBtn = root.querySelector('#wvTabs .tab[data-wmode="worst"]');
    const bestTitle = (root.querySelector('#wvBest') && root.querySelector('#wvBest').previousElementSibling);
    const worstTitle = (root.querySelector('#wvWorst') && root.querySelector('#wvWorst').previousElementSibling);
    if(state.basis==='contest'){
      if(bestBtn) bestBtn.textContent = 'Safest';
      if(worstBtn) worstBtn.textContent = 'Most contested';
      if(bestTitle) bestTitle.textContent = 'Safest Spots';
      if(worstTitle) worstTitle.textContent = 'Most Contested Spots';
    } else {
      if(bestBtn) bestBtn.textContent = 'Best';
      if(worstBtn) worstBtn.textContent = 'Worst';
      if(bestTitle) bestTitle.textContent = 'Best Spots';
      if(worstTitle) worstTitle.textContent = 'Worst Spots';
    }
  }
  function normalizedPlayers(){
    const placerSet = new Set();
    for(const s of spots){
      const sm = Array.isArray(s.samples) ? s.samples : [];
      for(const o of sm){
        const aid = Number(o.aid||0);
        if(aid>0) placerSet.add(aid);
      }
    }
    const base = Array.isArray(players) ? players : [];
    let list = base.length>0 ? base.slice() : Array.from(placerSet.values()).map(aid=>({id:aid, name:`Player ${aid}`}));
    list = list.filter(p=> placerSet.has(Number(p.id||p.account_id||0)));
    return list;
  }
  
    setActiveTime();
  setActiveMin();
  setActiveTop();
  setActiveBasis();
  setActiveCluster();
    updateViewAndListLabels();
  
  
    // Build team and player picklists
    (function(){
      const tWrap=root.querySelector('#wvTeams'); const pWrap=root.querySelector('#wvPlayersPick'); if(!tWrap) return;
      const tItemsBase=[{v:'',label:'All'},{v:'Radiant',label:'Radiant'},{v:'Dire',label:'Dire'}];
      teams.slice().sort((a,b)=> String(a.name||'').localeCompare(String(b.name||''))).forEach(t=> tItemsBase.push({v:`team:${t.id}`,label:String(t.name||`Team ${t.id}`)}));
      function renderTeams(){
        const wrapInner = tWrap.querySelector('#wvTeamsInner'); const tq = String(state.tquery||'').toLowerCase();
        const list = tItemsBase.filter(c=> !tq || String(c.label||'').toLowerCase().includes(tq) || String(c.v||'').toLowerCase().includes(tq));
        const html = list.map(c=>{ const sel = ((c.v||'')===state.team); return `<div class='item ${sel?'active':''}' role='option' aria-selected='${sel?'true':'false'}' tabindex='0' data-team='${esc(c.v)}'><span>${esc(c.label)}</span>${sel?"<span class='wv-badge'>selected</span>":''}</div>`; }).join('');
        if(wrapInner){ wrapInner.innerHTML = html; }
        else { tWrap.innerHTML = html; }
      }
      function renderPlayers(){ if(!pWrap) return; const pInner = pWrap.querySelector('#wvPlayersInner'); const pq = (state.pquery||'').toLowerCase(); const sel = currentPlayerSelection(); const list=[{id:'',name:'All'}].concat(normalizedPlayers().slice().sort((a,b)=> String(a.name||'').localeCompare(String(b.name||''))).map(p=>({id:String(p.id||p.account_id||''), name:String(p.name||`Player ${p.id||p.account_id||''}`)})).filter(c=> !pq || String(c.name||'').toLowerCase().includes(pq) || String(c.id||'').includes(pq)));
        const html = list.map(c=>{ const id = String(c.id||''); const selCur = id==='' ? !sel.hasAny : sel.set.has(Number(id||0)); return `<div class='item ${selCur?'active':''}' role='option' aria-selected='${selCur?'true':'false'}' tabindex='0' data-player='${esc(id)}'><span>${esc(c.name)}</span>${selCur?"<span class='wv-badge'>selected</span>":''}</div>`; }).join('');
        if(pInner){ pInner.innerHTML = html; }
        else { pWrap.innerHTML = html; }
      }
  renderTeams(); renderPlayers();
  const tq = tWrap.querySelector('#wvTq'); if(tq){ tq.value = state.tquery||''; tq.addEventListener('input', ()=>{ state.tquery = String(tq.value||''); renderTeams(); }); }
  tWrap.addEventListener('click', e=>{ const it=e.target.closest('.item'); if(!it) return; state.team = it.getAttribute('data-team')||''; renderTeams(); persistState(); render(); });
  tWrap.addEventListener('keydown', e=>{ if((e.key==='Enter'||e.key===' ') && e.target && e.target.classList.contains('item')){ e.preventDefault(); const it=e.target; state.team = it.getAttribute('data-team')||''; renderTeams(); persistState(); render(); } });
      if(pWrap){
        function togglePlayerSelection(value){ const raw = String(value||''); if(!raw){ state.player = ''; return; } const id = Number(raw||0); if(!(id>0)) return; const ids = parsePlayerSelection(state.player); const idx = ids.indexOf(id); if(idx===-1) ids.push(id); else ids.splice(idx,1); state.player = serializePlayerSelection(ids); }
        const pq = pWrap.querySelector('#wvPq'); if(pq){ pq.value = state.pquery||''; pq.addEventListener('input', ()=>{ state.pquery = String(pq.value||''); persistState(); renderPlayers(); }); }
        pWrap.addEventListener('click', e=>{ const it=e.target.closest('.item'); if(!it) return; togglePlayerSelection(it.getAttribute('data-player')||''); renderPlayers(); persistState(); render(); });
        pWrap.addEventListener('keydown', e=>{ if((e.key==='Enter'||e.key===' ') && e.target && e.target.classList.contains('item')){ e.preventDefault(); const it=e.target; togglePlayerSelection(it.getAttribute('data-player')||''); renderPlayers(); persistState(); render(); } });
      }
    })();
    // Bind tabs/time
  root.querySelectorAll('#wvTabs .tab').forEach(b=> b.addEventListener('click',()=>{ state.mode = b.dataset.wmode||'best'; root.querySelectorAll('#wvTabs .tab').forEach(x=> x.classList.toggle('active', x===b)); try{ const zw=root.querySelector('#wvZeroWorst'); if(zw){ const lab=zw.closest('label'); if(lab){ lab.style.display = (state.mode==='worst')? '' : 'none'; } } }catch(_e){} persistState(); render(); }));
  root.querySelector('#wvTime').addEventListener('click',(e)=>{ const btn=e.target.closest('button.seg'); if(!btn) return; state.time = btn.getAttribute('data-time')||''; setActiveTime(); persistState(); render(); });
  root.querySelector('#wvMin').addEventListener('click',(e)=>{ const btn=e.target.closest('button.seg'); if(!btn) return; const v = Math.max(1, parseInt(btn.getAttribute('data-min')||'1',10)); state.minCount = v; setActiveMin(); persistState(); render(); });
  root.querySelector('#wvTop').addEventListener('click',(e)=>{ const btn=e.target.closest('button.seg'); if(!btn) return; const t = String(btn.getAttribute('data-top')||'15'); state.topN = (t.toLowerCase()==='all')? 'all' : Math.max(1, parseInt(t,10)||15); setActiveTop(); persistState(); render(); });
  { const basisWrap = root.querySelector('#wvBasis'); if(basisWrap){ basisWrap.addEventListener('click',(e)=>{ const btn=e.target.closest('button.seg'); if(!btn) return; const b = String(btn.getAttribute('data-basis')||'lifetime'); if(ALLOWED_BASIS.has(b)){ state.basis = b; setActiveBasis(); updateViewAndListLabels(); persistState(); render(); } }); } }
  // Intelligence controls removed
  
  root.querySelector('#wvCluster').addEventListener('click',(e)=>{ const btn=e.target.closest('button.seg'); if(!btn) return; const cr = Number(btn.getAttribute('data-cluster')||'0'); state.cluster = (!isFinite(cr) || cr<0)? 0 : cr; setActiveCluster(); persistState(); render(); });
  
  const svg = root.querySelector('#wvMap svg');
  function setActiveMapToggles(){ const wrap=root.querySelector('#wvMapToggles'); if(!wrap) return; wrap.querySelectorAll('.seg').forEach(btn=>{ const key = btn.getAttribute('data-toggle')||''; const on = key==='overlay' ? !!state.overlay : (key==='grid' ? !!state.grid : false); btn.classList.toggle('active', on); btn.setAttribute('aria-pressed', String(on)); }); }
    function ensureBG(){ try{ const asset = (mc && mc.major && mc.current && mc.major[mc.current]) ? mc.major[mc.current] : null; let src = asset && asset.src ? asset.src : null; if(!src && mc && mc.default){ src = mc.default; } const img=root.querySelector('#wvMapImg'); if(src && img){ img.src = src; } }catch(_e){} }
    ensureBG();
    // Initialize overlay/grid from state
    try{ svg.style.display = state.overlay? '':'none'; }catch(_e){}
  setActiveMapToggles();
  // Flyout init: set current label
  function setSentryModeLabel(){ try{ const lbl=root.querySelector('#wvSentryModeLbl'); if(!lbl) return; let m='Off'; if(state.hotSentries) m='Hotspots'; else if(state.showSentries) m='Markers'; lbl.textContent = m; }catch(_e){} }
  setSentryModeLabel();
  try{ const zw=root.querySelector('#wvZeroWorst'); if(zw){ zw.checked = !!state.includeZeroWorst; const lab=zw.closest('label'); if(lab){ lab.style.display = (state.mode==='worst')? '' : 'none'; } zw.addEventListener('change',()=>{ state.includeZeroWorst = !!zw.checked; persistState(); render(); }); } }catch(_e){}
  root.querySelector('#wvMapToggles').addEventListener('click',(e)=>{ const btn=e.target.closest('button.seg'); if(!btn) return; const key = btn.getAttribute('data-toggle')||''; if(key==='overlay'){ state.overlay = !state.overlay; svg.style.display = state.overlay? '':'none'; persistState(); setActiveMapToggles(); return; } if(key==='grid'){ state.grid = !state.grid; persistState(); setActiveMapToggles(); render(); } });
  // Compact vs details toggle for flyout (not persisted)
  let flyDetailOpen = false;

  // Shared render context and helpers accessible to flyout
  const lastCtx = { spotIndex:null, perfForRanking:null, perf2:null, best:null, worst:null, derived:null,
    asset:null, hasBounds:false, invertY:false, dynScale:1, obsPct:10, senPct:6, sentIdx:null, mapPoints:null };
  function equalSpotKey(a,b){ const ca=String(a||'').replace(/[\[\]\s]/g,''); const cb=String(b||'').replace(/[\[\]\s]/g,''); return ca===cb; }
  function parseXY(key){ try{ const c=String(key||'').replace(/[\[\]\s]/g,'').split(','); if(c.length!==2) return null; const x=parseFloat(c[0]), y=parseFloat(c[1]); if(!isFinite(x)||!isFinite(y)) return null; return {x,y}; }catch(_e){ return null; } }
  function normXY(X,Y){ try{
    const asset = lastCtx.asset; const hasBounds = !!(lastCtx && lastCtx.hasBounds);
    const invertY = !!(lastCtx && lastCtx.invertY); const dynScale = Number(lastCtx && lastCtx.dynScale || 1);
    let cx0, cy0;
    if(hasBounds && asset){ const minX=asset.minX, maxX=asset.maxX, minY=asset.minY, maxY=asset.maxY; const clX=Math.max(minX,Math.min(maxX,Number(X||0))); const clY=Math.max(minY,Math.min(maxY,Number(Y||0))); cx0=(clX-minX)/(maxX-minX); cy0=(clY-minY)/(maxY-minY); if(invertY) cy0=1-cy0; }
    else { cx0=Math.max(0,Math.min(dynScale,Number(X||0)))/dynScale; cy0=Math.max(0,Math.min(dynScale,Number(Y||0)))/dynScale; if(invertY) cy0=1-cy0; }
    return {cx: Math.round(cx0*10000)/100, cy: Math.round(cy0*10000)/100};
  }catch(_e){ return {cx:0,cy:0}; } }
  function inPolyShared(nx,ny,poly){ let inside=false; for(let i=0,j=poly.length-1;i<poly.length;j=i++){ const xi=poly[i][0], yi=poly[i][1]; const xj=poly[j][0], yj=poly[j][1]; const hit=((yi>ny)!==(yj>ny)) && (nx < (xj - xi) * (ny - yi) / ((yj - yi)||1e-9) + xi); if(hit) inside=!inside; } return inside; }
  function labelTargetsForItemShared(item){
    const targets = [];
    try{
      const members = Array.isArray(item && item.members) ? item.members : [];
      for(const member of members){
        const src = member && member.s ? member.s : member;
        const x = Number(src && src.x!=null ? src.x : member && member.x);
        const y = Number(src && src.y!=null ? src.y : member && member.y);
        let w = Number(member && member.w!=null ? member.w : (src && src.count!=null ? src.count : member && member.count));
        if(!(w>0)) w = 1;
        if(isFinite(x) && isFinite(y)) targets.push({ x, y, w });
      }
    }catch(_e){}
    if(targets.length) return targets;
    const x = Number(item && item.x || 0), y = Number(item && item.y || 0);
    let w = Number(item && item.count || 0);
    if(!(w>0)) w = 1;
    return [{ x, y, w }];
  }
  function addLabelWeightShared(mp, name, w){ if(!name) return; const key = String(name||''); mp.set(key, (mp.get(key)||0) + Math.max(1, Number(w||1))); }
  function rankLabelWeightsShared(mp){ return Array.from(mp.entries()).sort((a,b)=> b[1]-a[1]).map(([name])=> String(name||'')); }
  function regionNamesForPointShared(x,y){ try{ const regs = Array.isArray(lastCtx.regions)? lastCtx.regions : []; if(!regs.length) return []; const n=normXY(x,y); const nx=Number(n.cx||0)/100, ny=Number(n.cy||0)/100; return regs.filter(r=> Array.isArray(r.poly) && r.poly.length>=3 && inPolyShared(nx,ny,r.poly)).map(r=> String(r.name||r.id||'Region')); }catch(_e){ return []; } }
  function fallbackAreaNameShared(x,y){ try{ const n=normXY(x,y); const nx=Number(n.cx||0)/100, ny=Number(n.cy||0)/100; if(Math.abs(nx-0.5)<=0.11 && Math.abs(ny-0.5)<=0.11) return 'mid river area'; if(nx + ny < 0.86) return ny < 0.34 ? 'Dire top lane area' : 'Dire upper jungle edge'; if(nx + ny > 1.14) return ny > 0.66 ? 'Radiant bottom lane area' : 'Radiant lower jungle edge'; if(ny < 0.35) return 'top river / rune approach'; if(ny > 0.65) return 'bottom river / rune approach'; return 'central map transition'; }catch(_e){ return 'map area'; } }
  function nearestNamedPointForPointShared(x,y){ try{ const pts = Array.isArray(lastCtx.mapPoints)? lastCtx.mapPoints : []; if(!pts.length) return ''; const n=normXY(x,y); const nx=Number(n.cx||0)/100, ny=Number(n.cy||0)/100; let best = null; for(const pt of pts){ const dist = Math.hypot(nx-Number(pt.nx||0), ny-Number(pt.ny||0)); if(!best || dist < best.dist) best = { name:String(pt.name||''), dist }; } return best && best.dist <= 0.12 ? best.name : ''; }catch(_e){ return ''; } }
  function spotLabelShared(item){ const coords=String(item && item.spot || '').replace(/[\[\]\s]/g,''); const regionWeights=new Map(), namedWeights=new Map(), areaWeights=new Map(); for(const target of labelTargetsForItemShared(item)){ const regions=regionNamesForPointShared(target.x, target.y); for(const region of regions) addLabelWeightShared(regionWeights, region, target.w); addLabelWeightShared(namedWeights, nearestNamedPointForPointShared(target.x, target.y), target.w); addLabelWeightShared(areaWeights, fallbackAreaNameShared(target.x, target.y), target.w); } const regions=rankLabelWeightsShared(regionWeights); const namedPoints=rankLabelWeightsShared(namedWeights); const areas=rankLabelWeightsShared(areaWeights); const namedPoint = namedPoints[0] || ''; const area = areas[0] || ''; const title = regions[0] || namedPoint || area || coords || 'Spot'; const subtitle = regions[0] ? (namedPoint && namedPoint!==regions[0] ? namedPoint : area) : (namedPoint ? area : ''); return { title, subtitle, coords, regions, namedPoint, area }; }
  function sentryPressureFor(cx, cy){
    try{
      const sentIdx = Array.isArray(lastCtx.sentIdx)? lastCtx.sentIdx : [];
      if(!sentIdx.length) return {pressure:0, top:[], within:false, nearbyCount:0};
      const senPct = Number(lastCtx.senPct||0);
      const senR = Math.max(0.008, senPct/100);
      const senMax = sentIdx.reduce((m,it)=> Math.max(m, Number(it.cntTW||0)), 0) || 1;
      let acc = 0; const contrib=[]; let anyWithin=false;
      for(const it of sentIdx){ const dx = cx - Number(it.nx||0), dy = cy - Number(it.ny||0); const dist = Math.hypot(dx,dy); if(dist>senR) continue; anyWithin=true; const w = 1 - (dist/senR); const c = Number(it.cntTW||0)/senMax; const score = Math.max(0, w*c); if(score>0){ acc += score; contrib.push({spot:it.spot, x:it.x, y:it.y, score, count:it.cntTW, r:it.rTW, d:it.dTW}); } }
      contrib.sort((a,b)=> b.score-a.score);
      const top = contrib.slice(0,3);
      const pressure = Math.max(0, Math.min(100, Math.round(Math.min(1, acc)*100)));
      return { pressure, top, within:anyWithin, nearbyCount:contrib.length };
    }catch(_e){ return {pressure:0, top:[], within:false, nearbyCount:0}; }
  }
  function getItemForKey(key){
    const k = String(key || '');
    let it = null;
    try{
      const spotIndex = lastCtx.spotIndex instanceof Map ? lastCtx.spotIndex : null;
      if(spotIndex){ it = spotIndex.get(k) || null; if(!it){ for(const [sk,sv] of spotIndex.entries()){ if(equalSpotKey(sk,k)){ it = sv; break; } } }
      }
      function findIn(arr){ if(!Array.isArray(arr)) return null; const f = arr.find(s=> equalSpotKey(s.spot, k)); return f||null; }
      if(!it) it = findIn(lastCtx.perfForRanking);
      if(!it) it = findIn(lastCtx.perf2);
      if(!it) it = findIn(lastCtx.best);
      if(!it) it = findIn(lastCtx.worst);
      if(!it) it = findIn(lastCtx.derived);
      if(!it){ const xy = parseXY(k); if(xy){ const tol = 0.2; const cand = (Array.isArray(lastCtx.derived)? lastCtx.derived: []).find(s=>{ const p=parseXY(s.spot); return p && Math.abs(p.x-xy.x)<=tol && Math.abs(p.y-xy.y)<=tol; }); if(cand) it=cand; }
      }
    }catch(_e){}
    return it;
  }
  // Settings flyout open/close
  (function(){
    const panel = root.querySelector('#wvSettings');
    const openBtn = root.querySelector('#wvOpenSettings');
    const overlay = root.parentElement && root.parentElement.querySelector('.wv-overlay');
    if(!panel || !openBtn || !overlay) return;
  function open(){ panel.classList.add('open'); panel.setAttribute('aria-hidden','false'); overlay.classList.add('show'); setActiveMin(); setActiveTop(); setActiveCluster(); }
    function close(){ panel.classList.remove('open'); panel.setAttribute('aria-hidden','true'); // don't hide overlay here; may be used by details
      // hide overlay only if details is closed as well
      const det = root.querySelector('#wvDetails'); if(det && det.classList.contains('open')){ /* keep overlay */ } else { overlay.classList.remove('show'); } }
    openBtn.addEventListener('click',(e)=>{ e.preventDefault(); if(panel.classList.contains('open')) close(); else open(); });
    overlay.addEventListener('click', ()=>{ close(); /* overlay is dedicated to settings; flyout uses no overlay */ });
    document.addEventListener('keydown', (e)=>{ if(e.key==='Escape'){ close(); try{ const fly=root.querySelector('#wvFly'); if(fly && fly.classList.contains('show')){ fly.classList.remove('show'); state.wspot=''; persistState(); } }catch(_e){} } });
  })();
  // Close flyout on outside click
  (function(){
    function onDocClick(e){ const fly=root.querySelector('#wvFly'); const map=root.querySelector('#wvMap'); if(!fly || !map) return; if(fly.classList.contains('show')){ if(!fly.contains(e.target) && !map.contains(e.target.closest('circle.spot'))){ fly.classList.remove('show'); state.wspot=''; persistState(); } } }
    document.addEventListener('click', onDocClick);
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
      const val=state.team; const tw=timeWindow(); const playerSel = currentPlayerSelection();
      function dangerBucket(lifeSec){ const L=Math.max(0,Number(lifeSec||0)); if(L<=5) return 100; if(L<=30) return 75; if(L<=150) return 40; if(L<=360) return 15; return 10; }
  if(Array.isArray(s.samples) && s.samples.length){ let cnt=0,totW=0,wsum=0, totRaw=0; const lifes=[]; let cInst=0,cShort=0,cMed=0,cLong=0; let rSamp=0,dSamp=0; for(const sm of s.samples){ const t=Number(sm.t||0); if(!(t>=tw.min && t<tw.max)) continue; if(!playerSelectionMatches(sm.aid||sm.account_id, playerSel)) continue; let ok=false; if(!val || val==='') { ok=true; } else if(val==='Radiant' || val==='Dire'){ if(String(sm.side||'')===val) ok=true; } else if(val.startsWith('team:')){ const id=Number(val.split(':')[1]||0); if(Number(sm.teamId||0)===id) ok=true; }
    if(!ok) continue; cnt++; const life = Number((sm.life!=null? sm.life : sm.lifetime)||0); const L=Math.max(0,life); const w = 1.0; totW += (L * w); wsum += w; totRaw += L; lifes.push(Math.floor(L)); const sd=String(sm.side||''); if(sd==='Radiant') rSamp++; else if(sd==='Dire') dSamp++; if(L<=5) cInst++; else if(L<=30) cShort++; else if(L<=150) cMed++; else cLong++; }
    const n = Math.max(1, cInst+cShort+cMed+cLong);
    const danger = 100 * ((1.0*(cInst/n)) + (0.6*(cShort/n)) + (0.25*(cMed/n)));
    return {count:cnt,total:totW,wsum,rawTotal:totRaw,lifes, danger, inst:cInst, short:cShort, med:cMed, long:cLong, nSamples:(cInst+cShort+cMed+cLong), rSamples:rSamp, dSamples:dSamp};
      }
      // Without samples, only coarse aggregates are available; when filtering by player, return 0
  if(playerSel.hasAny){ return {count:0,total:0,rawTotal:0,lifes:null, danger:0, inst:0, short:0, med:0, long:0, nSamples:0, rSamples:0, dSamples:0}; }
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
  const chips = pins.map(k=>`<span class='wv-badge wv-chipbtn' role='button' tabindex='0' aria-label='Unpin ${esc(k)}' data-unpin='${esc(k)}'>${esc(k)} ✕</span>`).join(' ');
      bar.innerHTML = `<div class='wv-chips'>${chips}<span style='flex:1'></span><button class='tab' id='wvCopyPins'>Copy link</button><button class='tab' id='wvClearPins'>Clear</button></div>`;
      bar.querySelectorAll('[data-unpin]').forEach(btn=> btn.addEventListener('click', ()=>{ const k=btn.getAttribute('data-unpin'); state.pins = (state.pins||[]).filter(x=> x!==k); persistState(); render(); }));
  const copy = bar.querySelector('#wvCopyPins'); if(copy){ copy.addEventListener('click', ()=>{ try{ const sp=new URLSearchParams(location.search); sp.set('wpins', (state.pins||[]).join(',')); navigator.clipboard.writeText(location.pathname + '?' + sp.toString() + location.hash); copy.textContent='Copied'; const live=root.querySelector('#wvLive'); if(live){ live.textContent='Copied pins link to clipboard.'; } setTimeout(()=> copy.textContent='Copy link', 1000); }catch(_e){} }); copy.addEventListener('keydown',(e)=>{ if(e.key==='Enter'||e.key===' '){ e.preventDefault(); copy.click(); } }); }
  const clr = bar.querySelector('#wvClearPins'); if(clr){ clr.addEventListener('click', ()=>{ state.pins=[]; persistState(); const live=root.querySelector('#wvLive'); if(live){ live.textContent='Cleared all pins.'; } render(); }); clr.addEventListener('keydown',(e)=>{ if(e.key==='Enter'||e.key===' '){ e.preventDefault(); clr.click(); } }); }
    }
    function focusSpot(spotKey, pinAlso){
      const key = String(spotKey||'');
      if(!key) return;
      state.overlay = true;
      if(pinAlso && !isPinned(key)){
        const arr = Array.isArray(state.pins) ? state.pins.slice() : [];
        arr.push(key);
        state.pins = arr;
      }
      state.wspot = key;
      persistState();
      render();
    }
    function togglePin(spotKey){ spotKey=String(spotKey||''); if(!spotKey) return; const arr = state.pins||[]; const idx = arr.indexOf(spotKey); if(idx===-1){ arr.push(spotKey); } else { arr.splice(idx,1); } state.pins = arr; persistState(); render(); }
    function isPinned(spotKey){ return (state.pins||[]).includes(String(spotKey||'')); }
    // Spot flyout helpers
    function fmtMMSS(secs){ const s=Math.max(0,Math.floor(Number(secs||0))); const m=Math.floor(s/60); const r=s%60; return `${m}m ${r}s`; }
    let lastFlyoutOpener = null;
    function openFlyoutAt(clientX, clientY, opener){ try{ const fly = root.querySelector('#wvFly'); if(!fly) return; if(opener) lastFlyoutOpener = opener; const map = root.querySelector('#wvMap'); const box = map.getBoundingClientRect(); let x = clientX - box.left; let y = clientY - box.top; // clamp within map with margin
      fly.style.visibility = 'hidden'; fly.classList.add('show');
      const margin = 8; fly.style.maxHeight = Math.max(140, box.height - margin*2) + 'px'; const fw = fly.offsetWidth||260; const fh = Math.min(fly.offsetHeight||160, box.height - margin*2); x = Math.max(margin, Math.min(box.width - fw - margin, x)); y = Math.max(margin, Math.min(box.height - fh - margin, y)); fly.style.left = x + 'px'; fly.style.top = y + 'px'; fly.style.visibility=''; }catch(_e){} }
    function closeFlyout(){ try{ const fly=root.querySelector('#wvFly'); if(fly){ fly.classList.remove('show'); } const toFocus=lastFlyoutOpener; lastFlyoutOpener=null; state.wspot=''; persistState(); if(toFocus && typeof toFocus.focus==='function'){ setTimeout(()=>{ try{ toFocus.focus(); }catch(_e){} }, 0); } }catch(_e){} }
  function renderFlyFor(spotKey, fallback){
      const body = root.querySelector('#wvFlyBody'); const title = root.querySelector('#wvFly .title'); const copyBtn = root.querySelector('#wvFlyCopy'); const closeBtn = root.querySelector('#wvFlyClose');
      if(!body) return;
    const key = String(spotKey||'');
      let item = getItemForKey(key);
      if(!item && fallback && String(fallback.spot||'')===key){ item = fallback; }
      if(!item){
        // Try last-chance raw spot numeric tolerance and build minimal item
        let raw = null; try{ const xy=parseXY(key); if(xy){ raw = (spots||[]).find(ss=>{ const p=parseXY(ss.spot); return p && Math.abs(p.x-xy.x)<=0.2 && Math.abs(p.y-xy.y)<=0.2; }) || null; } }catch(_e){}
        if(raw){ const avg = Number(raw.count||0)>0 ? Math.floor(Number(raw.total||0)/Math.max(1,Number(raw.count||0))) : 0; item = { spot:String(raw.spot||key), x:Number(raw.x||xy&&xy.x||0), y:Number(raw.y||xy&&xy.y||0), count:Number(raw.count||0), avgSeconds:avg, avg:avg, median:0, contest:undefined }; }
      }
      if(!item){ body.innerHTML = `<div class='wv-sub'>No data for ${esc(key)}.</div>`; return; }
  // compute normalized coords using shared normXY
  const n = normXY(item.x, item.y); const cx = Number(n.cx||0)/100, cy=Number(n.cy||0)/100;
      // sentry context
      let sp = {pressure:0, top:[], within:false};
  try{ sp = sentryPressureFor(cx,cy) || sp; }catch(_e){}
      const avg = Number(item.avg||item.avgSeconds||0);
      const med = Number(item.median||0);
      const cnt = Number(item.count||0);
      // lifetime distribution (if we have samples or can approximate via _v)
      let lifeDist = null; let lifeFromAggregates=false; try{
        if(item._v){ lifeDist = { inst:Number(item._v.inst||0), short:Number(item._v.short||0), med:Number(item._v.med||0), long:Number(item._v.long||0) }; lifeFromAggregates = !(Array.isArray(item.samples) && item.samples.length); }
      }catch(_e){}
      const distTot = lifeDist? (lifeDist.inst + lifeDist.short + lifeDist.med + lifeDist.long) : 0;
      const distBlock = lifeDist && distTot>0 ? `
        <div class='wv-title' style='margin:8px 0 4px'>Lifetime distribution</div>
        <div class='wv-stack'>
          <div class='seg wv-seg-inst' style='width:${(100*lifeDist.inst/distTot).toFixed(1)}%'></div>
          <div class='seg wv-seg-short' style='width:${(100*lifeDist.short/distTot).toFixed(1)}%'></div>
          <div class='seg wv-seg-med' style='width:${(100*lifeDist.med/distTot).toFixed(1)}%'></div>
          <div class='seg wv-seg-long' style='width:${(100*lifeDist.long/distTot).toFixed(1)}%'></div>
        </div>
        <div class='wv-stack-legend'>
          <span class='key'><span class='dot wv-seg-inst'></span> ≤5s (${lifeDist.inst})</span>
          <span class='key'><span class='dot wv-seg-short'></span> ≤30s (${lifeDist.short})</span>
          <span class='key'><span class='dot wv-seg-med'></span> ≤150s (${lifeDist.med})</span>
          <span class='key'><span class='dot wv-seg-long'></span> >150s (${lifeDist.long})</span>
        </div>
        ${lifeFromAggregates ? `<div class='wv-sub hint' style='margin-top:4px'>approximate distribution (aggregates)</div>` : ''}
      ` : '';
      const sent = (sp && Array.isArray(sp.top))? sp.top.slice(0,3).map(o=>{
        const pt = `${Math.round(o.x)},${Math.round(o.y)}`; return `<li><span>${esc(pt)}</span><span class='wv-detail-badge'>x${o.count||0}</span></li>`;
      }).join('') : '';
      // Prefer map-relative, time-filtered sentry pressure used in ranking
      let __sentPressScaled = NaN;
      try{
        const __k = String(item.spot||key);
        if(lastCtx && lastCtx.pressMap instanceof Map){
          const pv = lastCtx.pressMap.get(__k);
          if(isFinite(pv)) __sentPressScaled = Math.round(Number(pv));
        }
        if(!isFinite(__sentPressScaled)){
          // Fallback: compute kernel density at this coordinate and normalize by recorded max
          const senPctLoc = Number(lastCtx && lastCtx.senPct || 0);
          const rPct = Math.min(isFinite(senPctLoc)? senPctLoc: 0, 4);
          const senR = Math.max(0.02, rPct/100);
          let acc=0;
          const arr = Array.isArray(lastCtx && lastCtx.sentIdx)? lastCtx.sentIdx : [];
          for(const it of arr){
            const dx = cx - Number(it.nx||0), dy = cy - Number(it.ny||0);
            const dist = Math.hypot(dx,dy);
            if(dist>senR) continue;
            const w = 1 - (dist/senR)**2;
            const c = Math.max(0, Number(it.cntTW||0));
            acc += w*c;
          }
          const maxA = Math.max(1, Number(lastCtx && lastCtx.pressMax || 1));
          __sentPressScaled = Math.round(100 * Math.max(0, Math.min(1, acc/maxA)));
        }
      }catch(_e){}
      const sentPress = isFinite(__sentPressScaled)? __sentPressScaled : (isFinite(sp && sp.pressure)? Math.round(sp.pressure) : 0);
      const contest = Number(item.contest!=null ? item.contest : Math.round(0.6*sentPress + 0.4*Number(item._contResidual||0)));
      const tier = isFinite(contest)? (contest>=80?'Very High': contest>=60?'High': contest>=40?'Medium': contest>=20?'Low':'Very Low') : '-';
      const chips = [
        `<span class='wv-detail-badge'>Avg ${fmtMMSS(avg)}</span>`,
        med? `<span class='wv-detail-badge'>Med ${fmtMMSS(med)}</span>`:'' ,
        `<span class='wv-detail-badge'>n=${cnt}</span>`,
        `<span class='wv-detail-badge'>Contest ${isFinite(contest)? Math.round(contest):'-'}</span>`,
        `<span class='wv-detail-badge'>${esc(tier)}</span>`
      ].filter(Boolean).join(' ');
      const sentBlock = `
        <div class='wv-title' style='margin:8px 0 4px'>Sentry pressure</div>
        <div class='wv-prog'><div class='fill' style='width:${sentPress}%;'></div></div>
        <div class='wv-sub' style='margin-top:4px'>${sentPress}% relative (current filters & time)</div>
        <div class='wv-title' style='margin:8px 0 4px'>Nearby sentries</div>
        ${sp && sp.top && sp.top.length? `<ul class='wv-simple'>${sent}</ul>`: `<div class='wv-sub'>none in range</div>`}`;
      const spotInfo = spotLabelShared(item);
      // Region names (defined early so title can use it)
      const __regionNames = Array.isArray(spotInfo && spotInfo.regions) && spotInfo.regions.length ? spotInfo.regions : regionNamesForItem();
      if(title){
        const ttl = spotInfo.title || ((__regionNames && __regionNames.length) ? __regionNames.join(', ') : key);
        title.textContent = `Vision Details — ${ttl}`;
      }
      // Region-level typical sentry timings (ignore time window; apply team/player filters)
      function computeRegionSentryTiming(){
        try{
          if(!Array.isArray(__regionNames) || !__regionNames.length) return null;
          const regs = Array.isArray(lastCtx && lastCtx.regions)? lastCtx.regions : [];
          if(!regs.length) return null;
          const chosen = regs.filter(r=> __regionNames.includes(r.name||r.id));
          if(!chosen.length) return null;
          function inPolyXY(nx,ny,poly){
            let inside=false; for(let i=0,j=poly.length-1;i<poly.length;j=i++){
              const xi=poly[i][0], yi=poly[i][1]; const xj=poly[j][0], yj=poly[j][1];
              const intersect = ((yi>ny)!==(yj>ny)) && (nx < (xj - xi) * (ny - yi) / ((yj - yi)||1e-9) + xi);
              if(intersect) inside=!inside;
            }
            return inside;
          }
          const teamSel = String(state.team||'');
          const playerSel = currentPlayerSelection();
          const phases = [
            {id:'early', label:'0–10', min:0, max:600},
            {id:'mid', label:'10–35', min:600, max:2100},
            {id:'earlylate', label:'35–50', min:2100, max:3000},
            {id:'late', label:'50–75', min:3000, max:4500},
            {id:'superlate', label:'75+', min:4500, max:Infinity}
          ];
          const counts = new Map(phases.map(p=> [p.id, 0]));
          const totalByPhase = ()=> phases.map(p=> ({ph:p, n: counts.get(p.id)||0}));
          const ps = Array.isArray(sentries)? sentries: [];
          for(const it of ps){
            // region membership by sentry location
            const n = normXY(it.x, it.y); const nx = Number(n.cx||0)/100, ny = Number(n.cy||0)/100;
            const inAny = chosen.some(r=> Array.isArray(r.poly) && r.poly.length>=3 && inPolyXY(nx,ny,r.poly));
            if(!inAny) continue;
            const samp = Array.isArray(it.samples)? it.samples: [];
            for(const s of samp){
              // team filter
              let ok=true;
              if(teamSel==='Radiant' || teamSel==='Dire'){
                ok = String(s.side||'')===teamSel;
              } else if(teamSel.startsWith('team:')){
                const id=Number(teamSel.split(':')[1]||0);
                const sid = Number(s.teamId||s.tid||it.teamId||0);
                ok = (id>0 && sid===id);
              }
              if(ok && playerSel.hasAny){ ok = playerSelectionMatches(s.aid||s.account_id, playerSel); }
              if(!ok) continue;
              const t = Number(s.t||0);
              const ph = phases.find(p=> t>=p.min && t<p.max);
              if(ph){ counts.set(ph.id, (counts.get(ph.id)||0) + 1); }
            }
          }
          const bars = totalByPhase();
          const maxCount = bars.reduce((m,b)=> Math.max(m, b.n||0), 0) || 0;
          const peak = bars.reduce((best,b)=> (b.n>(best&&best.n||0)? b: best), null);
          const total = bars.reduce((s,b)=> s + (b.n||0), 0);
          return { bars, maxCount, peak, total };
        }catch(_e){ return null; }
      }
      const rs = computeRegionSentryTiming();
      const regionSentryBlock = (rs && rs.total>0) ? `
        <div class='wv-title' style='margin:8px 0 4px'>Sentry placements in region</div>
        <div class='wv-minibar'>
          ${rs.bars.map(b=>{ const h = rs.maxCount>0? Math.round(100 * Math.min(1, Number(b.n||0)/rs.maxCount)) : 0; return `<div class='b' title='${b.ph.label}m: n=${b.n}'><div class='fill' style='height:${h}%'></div></div>`; }).join('')}
        </div>
        <div class='wv-minibar cap'><span>0–10</span><span>10–35</span><span>35–50</span><span>50–75</span><span>75+</span></div>
        <div class='wv-sub' style='margin-top:4px'>Peak: ${rs.peak && rs.peak.ph ? rs.peak.ph.label : '-'}m — n=${rs.peak? rs.peak.n: 0}</div>
      ` : '';
      // Side usage and best phase
  function computeSideStats(){
        // try to find matching raw spot by flexible key compare
  let raw = null; try{ raw = (spots||[]).find(ss=> equalSpotKey(ss.spot, key)) || null; }catch(_e){}
        if(!raw) return null;
        const playerSel = currentPlayerSelection();
        let rC=0, rTot=0, dC=0, dTot=0;
        if(Array.isArray(raw.samples) && raw.samples.length){
          for(const sm of raw.samples){
            if(!playerSelectionMatches(sm.aid||sm.account_id, playerSel)) continue;
            const L = Math.max(0, Number((sm.life!=null? sm.life : sm.lifetime)||0));
            const sd = String(sm.side||'');
            if(sd==='Radiant'){ rC++; rTot+=L; }
            else if(sd==='Dire'){ dC++; dTot+=L; }
          }
        } else {
          // fallback to aggregates
          const r = raw.bySide && raw.bySide.Radiant || {count:0,total:0};
          const d = raw.bySide && raw.bySide.Dire    || {count:0,total:0};
          rC = Number(r.count||0); rTot = Number(r.total||0);
          dC = Number(d.count||0); dTot = Number(d.total||0);
        }
        const rAvg = rC>0? Math.floor(rTot/Math.max(1,rC)) : 0;
        const dAvg = dC>0? Math.floor(dTot/Math.max(1,dC)) : 0;
        return { rC, rAvg, dC, dAvg };
      }
  function computeBestPhase(){
  let raw = null; try{ raw = (spots||[]).find(ss=> equalSpotKey(ss.spot, key)) || null; }catch(_e){}
        if(!raw || !Array.isArray(raw.samples) || !raw.samples.length) return null;
        const playerSel = currentPlayerSelection();
        const phases = [
          {id:'early', label:'Early (0–10m)', min:0, max:600},
          {id:'mid', label:'Mid (10–35m)', min:600, max:2100},
          {id:'earlylate', label:'Early Late (35–50m)', min:2100, max:3000},
          {id:'late', label:'Late (50–75m)', min:3000, max:4500},
          {id:'superlate', label:'Super Late (75m+)', min:4500, max:Infinity}
        ];
        let best = null;
        for(const ph of phases){
          let c=0, tot=0;
          for(const sm of raw.samples){
            const t = Number(sm.t||0); if(!(t>=ph.min && t<ph.max)) continue;
            if(!playerSelectionMatches(sm.aid||sm.account_id, playerSel)) continue;
            const L = Math.max(0, Number((sm.life!=null? sm.life : sm.lifetime)||0)); c++; tot+=L;
          }
          const avg = c>0? Math.floor(tot/Math.max(1,c)) : 0;
          if(c>0){ if(!best){ best = {phase:ph, avg, n:c}; } else { if(avg > best.avg) best = {phase:ph, avg, n:c}; } }
        }
        return best;
      }
      const side = computeSideStats();
      const phase = computeBestPhase();
      const sideBlock = side ? `
        <div class='wv-title' style='margin:8px 0 4px'>Usage by side</div>
        <ul class='wv-simple'>
          <li><span>Radiant placements</span><span><span class='wv-detail-badge'>x${side.rC}</span>${side.rC? `<span class='wv-detail-badge'>avg ${fmtMMSS(side.rAvg)}</span>`:''}</span></li>
          <li><span>Dire placements</span><span><span class='wv-detail-badge'>x${side.dC}</span>${side.dC? `<span class='wv-detail-badge'>avg ${fmtMMSS(side.dAvg)}</span>`:''}</span></li>
        </ul>` : '';
      // Per-phase mini bar (averages across phases)
      function computePhaseAverages(){
        let raw = null; try{ raw = (spots||[]).find(ss=> equalSpotKey(ss.spot, key)) || null; }catch(_e){}
        if(!raw || !Array.isArray(raw.samples) || !raw.samples.length) return null;
        const playerSel = currentPlayerSelection();
        const phases = [
          {id:'early', label:'0–10', min:0, max:600},
          {id:'mid', label:'10–35', min:600, max:2100},
          {id:'earlylate', label:'35–50', min:2100, max:3000},
          {id:'late', label:'50–75', min:3000, max:4500},
          {id:'superlate', label:'75+', min:4500, max:Infinity}
        ];
        const out=[]; let maxAvg=0;
        for(const ph of phases){
          let c=0, tot=0; for(const sm of raw.samples){ const t=Number(sm.t||0); if(!(t>=ph.min && t<ph.max)) continue; if(!playerSelectionMatches(sm.aid||sm.account_id, playerSel)) continue; const L=Math.max(0, Number((sm.life!=null? sm.life : sm.lifetime)||0)); c++; tot+=L; }
          const avg = c>0? Math.floor(tot/Math.max(1,c)) : 0; out.push({ph, avg, n:c}); if(avg>maxAvg) maxAvg=avg;
        }
        return { bars:out, maxAvg };
      }
      const phaseBars = computePhaseAverages();
      const phaseBarHtml = phaseBars && phaseBars.bars.some(b=>b.n>0) ? `
        <div class='wv-minibar'>
          ${phaseBars.bars.map(b=>{ const h = phaseBars.maxAvg>0? Math.round(100 * Math.min(1, b.avg/phaseBars.maxAvg)) : 0; return `<div class='b' title='${b.ph.label}m: avg ${fmtMMSS(b.avg)} (n=${b.n})'><div class='fill' style='height:${h}%'></div></div>`; }).join('')}
        </div>
        <div class='wv-minibar cap'><span>0–10</span><span>10–35</span><span>35–50</span><span>50–75</span><span>75+</span></div>
      ` : '';
      const phaseBlock = phase ? `
        <div class='wv-title' style='margin:8px 0 4px'>Best phase</div>
        <div class='wv-sub'>Most effective during <b>${phase.phase.label}</b> — <span class='wv-detail-badge'>avg ${fmtMMSS(phase.avg)}</span> <span class='wv-detail-badge'>n=${phase.n}</span></div>
        ${phaseBarHtml}
      ` : '';
  // Effectiveness score (0..100): 30% lifetime, 20% objectives proximity, 30% sentry pressure (inverse), 20% phase performance
      function effectivenessScore(){
        // 1) Lifetime (avg vs. a soft cap): scale 0..100 with diminishing returns; 360s ~ full credit
        const L = Math.max(0, Number(avg||0));
        const lifePct = Math.max(0, Math.min(100, Math.round(100 * (1 - Math.exp(-L/120))))); // ~63% at 120s, ~86% at 240s, ~95% at 360s
        // 2) Objectives proximity: higher if closer to objectives; take best (closest) objective within a reasonable radius
        let objPct = 0;
        try{
          // Nearby objectives (includes camps and towers parsed from shared map_locations.json)
          const objs = Array.isArray(lastCtx.objectivesNorm) ? lastCtx.objectivesNorm : [];
          if(objs.length){
            const n = normXY(item.x, item.y); const cx = Number(n.cx||0)/100, cy=Number(n.cy||0)/100;
            let best = Infinity; let type='';
            for(const o of objs){ const d = Math.hypot(cx - Number(o.nx||0), cy - Number(o.ny||0)); if(d < best){ best = d; type = o.type; } }
            // map distance to 0..100: <=3% => 100, 6% => 50, >=12% => ~0
            const dPct = best * 100; const a=3, b=12; const cl = Math.max(0, Math.min(1, (b - dPct) / (b - a)));
            objPct = Math.round(100 * cl);
          }
        }catch(_e){}
        // 3) Sentry pressure (lower is better for effectiveness): invert normalized pressure
        const pScaled = (lastCtx.pressMap && lastCtx.pressMap.get(String(item.spot||''))) || 0;
        const sentPct = Math.max(0, Math.min(100, 100 - Number(pScaled||0)));
        // 4) Phase performance: use best phase avg vs overall avg; reward improvement and sample support
        let phasePct = 0; try{
          if(phase && isFinite(phase.avg) && isFinite(avg)){
            const improvement = Math.max(0, Number(phase.avg||0) - Number(avg||0));
            // Cap benefit at +180s, scale to 0..100, slightly weight by n
            const base = Math.min(1, improvement/180);
            const w = Math.min(1, (Number(phase.n||0)/5));
            phasePct = Math.round(100 * (0.7*base + 0.3*w));
          }
        }catch(_e){}
        const score = Math.round(0.30*lifePct + 0.20*objPct + 0.30*sentPct + 0.20*phasePct);
        return { score, parts:{ lifePct, objPct, sentPct, phasePct } };
      }
      const eff = effectivenessScore();
      // Region inference (lazy): determine which user-defined regions (polygons) contain this spot
      function regionNamesForItem(){
        try{
          const regs = Array.isArray(lastCtx.regions)? lastCtx.regions : [];
          if(!regs.length) return [];
          const n = normXY(item.x, item.y); const x = Number(n.cx||0)/100, y = Number(n.cy||0)/100;
          function inPoly(x,y,poly){
            // ray-casting algorithm
            let inside=false; for(let i=0,j=poly.length-1;i<poly.length;j=i++){
              const xi=poly[i][0], yi=poly[i][1]; const xj=poly[j][0], yj=poly[j][1];
              const intersect = ((yi>y)!==(yj>y)) && (x < (xj - xi) * (y - yi) / ((yj - yi)||1e-9) + xi);
              if(intersect) inside=!inside;
            }
            return inside;
          }
          const names=[]; for(const r of regs){ if(Array.isArray(r.poly) && r.poly.length>=3 && inPoly(x,y,r.poly)) names.push(r.name||r.id||'Region'); }
          return names;
        }catch(_e){ return []; }
      }
      function tierFromScore(s){ if(s>=85) return 'Very High'; if(s>=70) return 'High'; if(s>=50) return 'Medium'; if(s>=30) return 'Low'; return 'Very Low'; }
      const effTier = tierFromScore(eff.score);
      const sideText = side ? `Radiant: ${side.rC}x${side.rC? ` (avg ${fmtMMSS(side.rAvg)})`:''} · Dire: ${side.dC}x${side.dC? ` (avg ${fmtMMSS(side.dAvg)})`:''}` : '';
      const phaseText = phase ? `${phase.phase.label} — avg ${fmtMMSS(phase.avg)} · n=${phase.n}` : '';
      const barBlocks = (p)=>{
        const pct = Math.max(0, Math.min(100, Number(p||0)));
        const filled = Math.round(pct/10);
        return '█'.repeat(filled) + '░'.repeat(10-filled);
      };
      const friendly = `
        <div class='wv-friendly'>
          <div class='line'>📍 <b>Ward Spot</b>: ${esc(spotInfo.title || 'Spot')}</div>
          ${spotInfo.subtitle ? `<div class='line'>🗺️ <b>Map area</b>: ${esc(spotInfo.subtitle)}</div>` : ''}
          ${__regionNames && __regionNames.length ? `<div class='line'>📦 <b>Region</b>: ${esc(__regionNames.join(', '))}</div>` : ''}
          <div class='line'>🕒 <b>Average duration</b>: ${fmtMMSS(avg)}</div>
          <div class='line'>📊 <b>Placements</b>: ${cnt}</div>
          <div class='line'>🔖 <b>Effectiveness</b>: ${esc(effTier)} (${eff.score})</div>
          <div class='line'>🛡️ <b>Sentry pressure</b>: ${sentPress}%<br><span class='mono'>[${barBlocks(sentPress)}]</span></div>
          <div class='line'>👀 <b>Nearby sentries</b>: ${(sp && Number(sp.nearbyCount||0)>0) ? `${Number(sp.nearbyCount||0)} nearby markers` : 'none in range'}</div>
          ${side? `<div class='line'>⚔️ <b>Usage</b>: ${esc(sideText)}</div>`:''}
          ${phase? `<div class='line'>📅 <b>Best phase</b>: ${esc(phase.phase.label)} (avg ${fmtMMSS(phase.avg)}, n=${phase.n})</div>`:''}
        </div>
      `;
      // Effectiveness breakdown badges
      const effParts = eff && eff.parts ? eff.parts : {lifePct:0,objPct:0,sentPct:0,phasePct:0};
      const effBreak = `
        <div class='wv-title' style='margin:8px 0 4px'>Effectiveness breakdown</div>
        <div class='wv-detail-row'>
          <span class='wv-detail-badge'>Lifetime ${effParts.lifePct}</span>
          <span class='wv-detail-badge'>Objectives ${effParts.objPct}</span>
          <span class='wv-detail-badge'>Sentries ${effParts.sentPct}</span>
          <span class='wv-detail-badge'>Phase ${effParts.phasePct}</span>
        </div>
      `;
  const detailsHtml = `${effBreak}${distBlock}${sentBlock}${regionSentryBlock}${sideBlock}${phaseBlock}`;
      body.innerHTML = `
        ${friendly}
        <div style='display:flex; gap:6px; margin-top:8px'>
          <button class='tab' id='wvFlyMore'>${flyDetailOpen? 'Hide details':'Show details'}</button>
          <button class='tab' id='wvDetPin' aria-pressed='${isPinned(key)?'true':'false'}'>${isPinned(key)?'Unpin':'Pin'}</button>
        </div>
        <div id='wvFlyDet' style='display:${flyDetailOpen? 'block':'none'}; margin-top:6px'>
          <div class='wv-detail-row' style='margin:4px 0'>${chips}</div>
          <div class='wv-sub hint'>Team: ${esc(state.team||'All')} · Time: ${esc(timeWindow().label)} · Basis: ${esc(state.basis)}</div>
          <div class='wv-sub hint'>Spot key: ${esc(key)}</div>
          ${detailsHtml}
        </div>
      `;
      // actions
  const pinBtn = body.querySelector('#wvDetPin'); if(pinBtn){ pinBtn.setAttribute('aria-pressed', String(isPinned(key))); pinBtn.addEventListener('click', ()=>{ togglePin(key); renderFlyFor(key); }); pinBtn.addEventListener('keydown', (e)=>{ if(e.key==='Enter'||e.key===' '){ e.preventDefault(); togglePin(key); renderFlyFor(key); } }); }
  const moreBtn = body.querySelector('#wvFlyMore'); if(moreBtn){ moreBtn.addEventListener('click', ()=>{ flyDetailOpen = !flyDetailOpen; const det = body.querySelector('#wvFlyDet'); if(det){ det.style.display = flyDetailOpen? 'block':'none'; } moreBtn.textContent = flyDetailOpen? 'Hide details' : 'Show details'; }); }
  if(copyBtn){ copyBtn.onclick = ()=>{ try{ const sp=new URLSearchParams(location.search); sp.set('wspot', key); navigator.clipboard.writeText(location.pathname + '?' + sp.toString() + location.hash); copyBtn.textContent='Copied'; const live=root.querySelector('#wvLive'); if(live){ live.textContent='Copied ward spot link to clipboard.'; } setTimeout(()=> copyBtn.textContent='Copy', 1000); }catch(_e){} }; }
  if(closeBtn){ closeBtn.onclick = ()=> closeFlyout(); closeBtn.addEventListener('keydown',(e)=>{ if(e.key==='Enter'||e.key===' '){ e.preventDefault(); closeFlyout(); } }); }
    }
    function render(){
    // (summary chips removed for a cleaner UI)
    // derive base metrics per raw spot
  // Helper: simple danger from avg lifetime (mirrors bucket logic)
  function simpleDangerFromAvg(L){ const v=Math.max(0,Number(L||0)); if(v<=5) return 100; if(v<=30) return 75; if(v<=150) return 40; if(v<=360) return 15; return 10; }
  function stabilizeContest(raw, count){ const prior = 50; const strength = 3; const c = Math.max(0, Number(count||0)); return Math.round(((Number(raw||0) * c) + (prior * strength)) / Math.max(1, c + strength)); }
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
      const pctDenom = hasBounds ? (cellUnits * (Number(asset && asset.maxX)||0 - Number(asset && asset.minX)||0)) : (cellUnits * dynScale);
      const obsPctCalc = pctDenom>0 ? Math.round(((obsUnits/pctDenom)*100) * 100) / 100 : NaN;
      const senPctCalc = pctDenom>0 ? Math.round(((senUnits/pctDenom)*100) * 100) / 100 : NaN;
      let obsPct = (asset && asset.obsRadiusPct!=null) ? Number(asset.obsRadiusPct)
             : (mc && mc.defaultObsRadiusPct!=null ? Number(mc.defaultObsRadiusPct) : NaN);
      if(!isFinite(obsPct)){
        obsPct = isFinite(obsPctCalc) && obsPctCalc>0 ? obsPctCalc : 10;
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
          senPct = isFinite(senPctCalc) && senPctCalc>0 ? senPctCalc : 6; // conservative fallback
        }
      }
      const selectionObsPct = Math.max(2, Math.round((Math.min(Number(obsPct||10), (isFinite(obsPctCalc) && obsPctCalc>0) ? obsPctCalc : Number(obsPct||10))) * 100) / 100);
  function norm(X,Y){ let cx0, cy0; if(hasBounds){ const minX=asset.minX, maxX=asset.maxX, minY=asset.minY, maxY=asset.maxY; const clX=Math.max(minX,Math.min(maxX,Number(X||0))); const clY=Math.max(minY,Math.min(maxY,Number(Y||0))); cx0=(clX-minX)/(maxX-minX); cy0=(clY-minY)/(maxY-minY); if(invertY) cy0=1-cy0; } else { cx0=Math.max(0,Math.min(dynScale,Number(X||0)))/dynScale; cy0=Math.max(0,Math.min(dynScale,Number(Y||0)))/dynScale; if(invertY) cy0=1-cy0; } return {cx: Math.round(cx0*10000)/100, cy: Math.round(cy0*10000)/100}; }
      // Build sentry proximity index (time-window filtered)
      const twCur = timeWindow();
      const sentIdx = Array.isArray(sentries)? sentries.map(it=>{
        const n = norm(it.x, it.y);
        const samp = Array.isArray(it.samples)? it.samples: [];
        if(samp.length){
          let cnt=0, r=0, d=0;
          const teamSel = String(state.team||'');
          const playerSel = currentPlayerSelection();
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
            if(ok && playerSel.hasAny){
              ok = playerSelectionMatches(s.aid||s.account_id, playerSel);
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
        const radius = r/100;
        const maxSpan = radius;
        const pts = list.map((s, idx)=>{ const n=norm(s.x,s.y); return { s, idx, w: Math.max(1, Number(s.count||0)), nx:Number(n.cx||0)/100, ny:Number(n.cy||0)/100 }; })
          .sort((a,b)=> (b.w-a.w) || (a.idx-b.idx));
        const clusters = [];
        function wmedian(pairs){ const arr=pairs.filter(x=> isFinite(x.v) && isFinite(x.w) && x.w>0).sort((a,b)=> a.v-b.v); if(!arr.length) return 0; let total=0; for(const x of arr) total+=x.w; let acc=0; const half=total/2; for(const x of arr){ acc+=x.w; if(acc>=half) return Math.floor(x.v); } return Math.floor(arr[arr.length-1].v); }
        function summarize(group){
          let sumW=0,sumNX=0,sumNY=0,sumX=0,sumY=0,sumTotSec=0; const meds=[];
          let sumContest=0, sumContestW=0;
          for(const cur of group){
            const w = Number(cur.w||0);
            sumW+=w; sumNX += cur.nx*w; sumNY += cur.ny*w; sumX += Number(cur.s.x||0)*w; sumY += Number(cur.s.y||0)*w; sumTotSec += Number(cur.s.avg||0)*w;
            meds.push({v:Number(cur.s.median||0), w});
            if(cur.s.contest!=null){ const cv=Number(cur.s.contest||0); sumContest += cv*w; sumContestW += w; }
          }
          if(sumW<=0) return null;
          const cnx = sumNX/sumW, cny = sumNY/sumW;
          const cx = sumX/sumW, cy = sumY/sumW;
          const totalCount = sumW;
          const avgSeconds = Math.floor(sumTotSec/Math.max(1,totalCount));
          const medSeconds = wmedian(meds);
          const contestMean = sumContestW>0 ? Math.round(sumContest/sumContestW) : 0;
          const contestVal = stabilizeContest(contestMean, totalCount);
          return { members:group, sumW, cnx, cny, cx, cy, totalCount, avgSeconds, medSeconds, contestVal };
        }
        function canJoin(cluster, pt){
          if(Math.hypot(cluster.cnx - pt.nx, cluster.cny - pt.ny) > radius) return false;
          for(const member of cluster.members){
            if(Math.hypot(member.nx - pt.nx, member.ny - pt.ny) > maxSpan) return false;
          }
          return true;
        }
        for(const pt of pts){
          let bestIdx = -1;
          let bestDist = Infinity;
          for(let i=0;i<clusters.length;i++){
            const cluster = clusters[i];
            const dist = Math.hypot(cluster.cnx - pt.nx, cluster.cny - pt.ny);
            if(dist > radius || dist >= bestDist) continue;
            if(!canJoin(cluster, pt)) continue;
            bestIdx = i;
            bestDist = dist;
          }
          if(bestIdx === -1){
            const single = summarize([pt]);
            if(single) clusters.push(single);
            continue;
          }
          const merged = summarize(clusters[bestIdx].members.concat(pt));
          if(merged) clusters[bestIdx] = merged;
        }
        return clusters.map(cluster=>{
          const spotKey = `cluster:[${(cluster.cnx*100).toFixed(1)},${(cluster.cny*100).toFixed(1)}]~r${r}`;
          return { spot: spotKey, x: cluster.cx, y: cluster.cy, count: cluster.totalCount, avgSeconds: cluster.avgSeconds, avg: cluster.avgSeconds, median: cluster.medSeconds, contest: cluster.contestVal, members: cluster.members.map(cur=> cur && cur.s ? cur.s : cur).filter(Boolean) };
        });
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
            if(used[i]) continue;
            const queue=[i]; used[i]=true;
            let sumW=0,sumNX=0,sumNY=0;
            while(queue.length){
              const idx = queue.pop();
              const cur = src[idx];
              const w=cur.w||0; sumW+=w; sumNX+=cur.nx*w; sumNY+=cur.ny*w;
              for(let j=0;j<src.length;j++){
                if(used[j]) continue;
                const q = src[j];
                const dist = Math.hypot(cur.nx - q.nx, cur.ny - q.ny);
                if(dist <= (cr/100)){
                  used[j]=true; queue.push(j);
                }
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
      // Compute kernel-based raw sentry density per spot, then normalize across all spots for better contrast
      function pressureAcc(cx, cy){
        // Use a compact radius to differentiate spots; cap to 4% of map if derived from settings
        const rPct = Math.min(Number(senPct||0), 4);
        const senR = Math.max(0.02, rPct/100);
        let acc = 0;
        for(const it of sentIdx){
          const dx = cx - Number(it.nx||0), dy = cy - Number(it.ny||0);
          const dist = Math.hypot(dx,dy);
          if(dist>senR) continue;
          // Quadratic kernel: stronger emphasis on closer sentries
          const w = 1 - (dist/senR)**2;
          const c = Math.max(0, Number(it.cntTW||0));
          acc += w * c;
        }
        return acc;
      }
      const pressRaw = perf.map(s=>{ const npt = norm(s.x,s.y); const cx = Number(npt.cx||0)/100, cy=Number(npt.cy||0)/100; return { key:String(s.spot||''), acc: pressureAcc(cx,cy) }; });
    const maxAcc = pressRaw.reduce((m,o)=> Math.max(m, Number(o.acc||0)), 0) || 1;
  const pressMap = new Map(pressRaw.map(o=> [o.key, Math.round(100 * (Math.max(0, Number(o.acc||0)) / Math.max(1, maxAcc)))]));
      // Blend normalized sentry pressure with shortness residual and finalize items
      const finalized = perf.map(s=>{
        const npt = norm(s.x, s.y);
        const cx = Number(npt.cx||0)/100, cy = Number(npt.cy||0)/100;
        const sp = sentryPressureFor(cx, cy); // reuse for top list + within flag
        const pScaled = pressMap.get(String(s.spot||'')) || 0;
        const contestRaw = Math.round(0.6*pScaled + 0.4*Number(s._contResidual||0));
        const contest = stabilizeContest(contestRaw, s.count);
        let rankVal = (state.basis==='contest')? contest : Number(s.avg||0);
        const topSentriesShort = (sp.top||[]).map(o=>`${Math.round(o.x)},${Math.round(o.y)}:${o.count}`).join('|');
        return { spot:s.spot, x:s.x, y:s.y, count:s.count, avgSeconds:rankVal, avg:Number(s.avg||0), median:Number(s.median||0), contest, contestRaw, sentryTop:(sp.top||[]), sentryTopStr:topSentriesShort, senPressure:pScaled, senWithin: !!sp.within };
      });
      // Replace perf with finalized values for ranking and rendering
      const perf2 = finalized;
    let perfForRanking = perf2;
  if(Number(state.cluster||0) > 0){ perfForRanking = clusterize(perf2, Number(state.cluster)); }
  let filteredForRanking = perfForRanking;
    if(clusterOn){ filteredForRanking = perfForRanking.filter(s=> Number(s.count||0) >= Number(state.minCount||1)); }
        if(state.basis==='contest'){
          best = filteredForRanking.slice().sort((a,b)=> (Number(a.contest||0)-Number(b.contest||0))||(Number(b.count||0)-Number(a.count||0))).slice(0, topN);
          worst = filteredForRanking.slice().sort((a,b)=> (Number(b.contest||0)-Number(a.contest||0))||(Number(b.count||0)-Number(a.count||0))).slice(0, topN);
        } else {
          best = filteredForRanking.slice().sort((a,b)=> (Number(b.avgSeconds||0)-Number(a.avgSeconds||0))||(Number(b.count||0)-Number(a.count||0))).slice(0, topN);
          worst = filteredForRanking.slice().filter(s=> state.includeZeroWorst ? true : (Number(s.avgSeconds||0))>0).sort((a,b)=> (Number(a.avgSeconds||0)-Number(b.avgSeconds||0))||(Number(b.count||0)-Number(a.count||0))).slice(0, topN);
        }
    const eliteKeys = (state.basis!=='contest')
      ? new Set(best.slice(0, Math.min(3, best.length)).map(s=> String(s.spot||'')))
    : new Set();
    const rawSpotIndex = new Map((spots||[]).map(s=> [String(s.spot||''), s]));
    const perfIndex = new Map((perf2||[]).map(s=> [String(s.spot||''), s]));
    const playerNameIndex = new Map(normalizedPlayers().map(p=>{ const id = Number(p.id||p.account_id||0); return [id, String(p.name||`Player ${id}`)]; }).filter(([id])=> id>0));
    const phaseDefs = [
      {id:'early', label:'0-10m', min:0, max:600},
      {id:'mid', label:'10-35m', min:600, max:2100},
      {id:'earlylate', label:'35-50m', min:2100, max:3000},
      {id:'late', label:'50-75m', min:3000, max:4500},
      {id:'superlate', label:'75m+', min:4500, max:Infinity}
    ];
    const twNow = timeWindow();
    function playerNameForAid(aid){ const id=Number(aid||0); return playerNameIndex.get(id) || `Player ${id}`; }
    function playerSelectionLabel(){ const sel = currentPlayerSelection(); if(!sel.hasAny) return 'All players'; const names = sel.ids.slice(0,2).map(id=> playerNameForAid(id)); if(sel.ids.length===1) return names[0]; if(sel.ids.length===2) return names.join(' + '); return `${names.join(' + ')} +${sel.ids.length-2}`; }
    function sampleMatches(sm, respectPlayer=true){
      const t = Number(sm && sm.t || 0);
      if(!(t>=twNow.min && t<twNow.max)) return false;
      const playerSel = currentPlayerSelection();
      if(respectPlayer && playerSel.hasAny && !playerSelectionMatches(sm && (sm.aid||sm.account_id), playerSel)) return false;
      const val = String(state.team||'');
      if(!val) return true;
      if(val==='Radiant' || val==='Dire') return String(sm && sm.side || '')===val;
      if(val.startsWith('team:')) return Number(sm && (sm.teamId||sm.tid)||0)===Number(val.split(':')[1]||0);
      return true;
    }
    function phaseForTime(t){ const sec=Number(t||0); return phaseDefs.find(ph=> sec>=ph.min && sec<ph.max) || phaseDefs[phaseDefs.length-1]; }
    function inPolyPoint(nx,ny,poly){ let inside=false; for(let i=0,j=poly.length-1;i<poly.length;j=i++){ const xi=poly[i][0], yi=poly[i][1]; const xj=poly[j][0], yj=poly[j][1]; const hit=((yi>ny)!==(yj>ny)) && (nx < (xj - xi) * (ny - yi) / ((yj - yi)||1e-9) + xi); if(hit) inside=!inside; } return inside; }
    function regionNamesForPoint(x,y){ try{ const regs = Array.isArray(lastCtx.regions)? lastCtx.regions : []; if(!regs.length) return []; const n=norm(x,y); const nx=Number(n.cx||0)/100, ny=Number(n.cy||0)/100; return regs.filter(r=> Array.isArray(r.poly) && r.poly.length>=3 && inPolyPoint(nx,ny,r.poly)).map(r=> String(r.name||r.id||'Region')); }catch(_e){ return []; } }
    function fallbackAreaName(x,y){
      try{
        const n = norm(x,y); const nx=Number(n.cx||0)/100, ny=Number(n.cy||0)/100;
        if(Math.abs(nx-0.5)<=0.11 && Math.abs(ny-0.5)<=0.11) return 'mid river area';
        if(nx + ny < 0.86) return ny < 0.34 ? 'Dire top lane area' : 'Dire upper jungle edge';
        if(nx + ny > 1.14) return ny > 0.66 ? 'Radiant bottom lane area' : 'Radiant lower jungle edge';
        if(ny < 0.35) return 'top river / rune approach';
        if(ny > 0.65) return 'bottom river / rune approach';
        return 'central map transition';
      }catch(_e){ return 'map area'; }
    }
    function nearestNamedPointForPoint(x,y){
      try{
        const pts = Array.isArray(lastCtx.mapPoints)? lastCtx.mapPoints : [];
        if(!pts.length) return '';
        const n=norm(x,y); const nx=Number(n.cx||0)/100, ny=Number(n.cy||0)/100;
        let best = null;
        for(const pt of pts){
          const dist = Math.hypot(nx-Number(pt.nx||0), ny-Number(pt.ny||0));
          if(!best || dist < best.dist) best = { name:String(pt.name||''), dist };
        }
        return best && best.dist <= 0.12 ? best.name : '';
      }catch(_e){ return ''; }
    }
    function spotLabel(item){ return spotLabelShared(item); }
    function samplesForItem(item, respectPlayer=true){
      const key = String(item && item.spot || '');
      const raw = rawSpotIndex.get(key);
      if(raw){ return (Array.isArray(raw.samples)? raw.samples : []).filter(sm=> sampleMatches(sm, respectPlayer)).map(sm=> ({ ...sm, __spot:key, __x:Number(raw.x||0), __y:Number(raw.y||0) })); }
      const members = Array.isArray(item && item.members) ? item.members : [];
      if(members.length){
        const out = [];
        for(const member of members){
          const memberKey = String(member && member.spot || member && member.s && member.s.spot || '');
          const rawMember = rawSpotIndex.get(memberKey);
          if(!rawMember) continue;
          for(const sm of (Array.isArray(rawMember.samples)? rawMember.samples : [])){
            if(sampleMatches(sm, respectPlayer)) out.push({ ...sm, __spot:memberKey, __x:Number(rawMember.x||0), __y:Number(rawMember.y||0) });
          }
        }
        if(out.length) return out;
      }
      if(!(Number(state.cluster||0)>0)) return [];
      const center = norm(item && item.x, item && item.y); const cx=Number(center.cx||0)/100, cy=Number(center.cy||0)/100;
      const radius = Math.max(0.005, Number(state.cluster||0)/100);
      const out = [];
      for(const rawSpot of (spots||[])){
        const n = norm(rawSpot.x, rawSpot.y); const nx=Number(n.cx||0)/100, ny=Number(n.cy||0)/100;
        if(Math.hypot(cx-nx, cy-ny) > (radius + 0.0005)) continue;
        for(const sm of (Array.isArray(rawSpot.samples)? rawSpot.samples : [])){
          if(sampleMatches(sm, respectPlayer)) out.push({ ...sm, __spot:String(rawSpot.spot||''), __x:Number(rawSpot.x||0), __y:Number(rawSpot.y||0) });
        }
      }
      return out;
    }
    function topPlayersForItem(item, limit=3){
      const mp = new Map();
      for(const sm of samplesForItem(item, true)){
        const aid = Number(sm.aid||sm.account_id||0); if(!(aid>0)) continue;
        const rec = mp.get(aid) || { aid, count:0, total:0 };
        rec.count++; rec.total += Math.max(0, Number((sm.life!=null? sm.life : sm.lifetime)||0)); mp.set(aid, rec);
      }
      return Array.from(mp.values()).map(rec=> ({ ...rec, avg: rec.count? Math.round(rec.total/rec.count) : 0, name: playerNameForAid(rec.aid) }))
        .sort((a,b)=> (b.count-a.count) || (b.avg-a.avg) || String(a.name).localeCompare(String(b.name)))
        .slice(0, limit);
    }
    function whyForSpot(item, kind){
      const info = spotLabel(item); const reasons = [];
      if(info.regions.length) reasons.push(info.regions[0]);
      const avg = Number(item && item.avg || item && item.avgSeconds || 0);
      const press = Number(item && item.senPressure || 0);
      const contest = Number(item && item.contest || 0);
      if(state.basis==='contest'){
        if(kind==='best' && contest<=25) reasons.push('low contest, rarely punished');
        if(kind==='worst' && contest>=60) reasons.push('predictable deward zone');
        if(press<=25) reasons.push('few nearby sentries');
        else if(press>=60) reasons.push('heavy sentry overlap');
      } else {
        if(avg>=240) reasons.push('survives a full vision cycle');
        else if(avg>=150) reasons.push('often survives first sweep');
        else if(avg<=45) reasons.push('dies almost immediately');
        else if(avg<=90) reasons.push('often removed on first pass');
        if(press<=25) reasons.push('off standard sentry paths');
        else if(press>=60) reasons.push('inside common sentry paths');
      }
      if(Number(item && item.count || 0) >= 10) reasons.push(`repeated ${Number(item.count||0)}x`);
      return reasons.slice(0,3).join(' · ');
    }
    function adviceItem(text, focus, topic, targetSpot, area){ return { text, focus:String(focus||''), topic:String(topic||''), targetSpot:String(targetSpot||''), area:String(area||'') }; }
    function collectAdvice(limit, candidates){
      const src = (Array.isArray(candidates) ? candidates : []).map(it=>{
        if(it && typeof it === 'object' && !Array.isArray(it)){
          return {
            text: String(it.text||'').trim(),
            focus: String(it.focus||'').trim().toLowerCase(),
            topic: String(it.topic||'').trim().toLowerCase(),
            targetSpot: String(it.targetSpot||'').trim(),
            area: String(it.area||'').trim().toLowerCase()
          };
        }
        return { text:String(it||'').trim(), focus:'', topic:'', targetSpot:'', area:'' };
      }).filter(it=> !!it.text);
      const out = [];
      const seenText = new Set();
      const seenFocus = new Set();
      const seenTopic = new Set();
      const seenArea = new Set();
      const seenTarget = new Set();
      function canTake(item, allowSeenFocus, allowSeenTopic, allowSeenArea, allowSeenTarget){
        const textKey = item.text.toLowerCase();
        if(seenText.has(textKey)) return false;
        if(item.focus && !allowSeenFocus && seenFocus.has(item.focus)) return false;
        if(item.topic && !allowSeenTopic && seenTopic.has(item.topic)) return false;
        if(item.area && !allowSeenArea && seenArea.has(item.area)) return false;
        if(item.targetSpot && !allowSeenTarget && seenTarget.has(item.targetSpot)) return false;
        return true;
      }
      function take(item){
        out.push({ text:item.text, targetSpot:item.targetSpot || '' });
        seenText.add(item.text.toLowerCase());
        if(item.focus) seenFocus.add(item.focus);
        if(item.topic) seenTopic.add(item.topic);
        if(item.area) seenArea.add(item.area);
        if(item.targetSpot) seenTarget.add(item.targetSpot);
      }
      const passes = [
        { allowSeenFocus:false, allowSeenTopic:false, allowSeenArea:false, allowSeenTarget:false },
        { allowSeenFocus:false, allowSeenTopic:true, allowSeenArea:false, allowSeenTarget:false },
        { allowSeenFocus:false, allowSeenTopic:true, allowSeenArea:true, allowSeenTarget:false },
        { allowSeenFocus:true, allowSeenTopic:true, allowSeenArea:true, allowSeenTarget:true }
      ];
      for(const pass of passes){
        for(const item of src){
          if(out.length >= limit) break;
          if(canTake(item, pass.allowSeenFocus, pass.allowSeenTopic, pass.allowSeenArea, pass.allowSeenTarget)) take(item);
        }
        if(out.length >= limit) break;
      }
      return out.slice(0, limit);
    }
    function buildPlayerTrends(){
      const agg = new Map();
      const focusSel = currentPlayerSelection();
      function ensure(aid){ if(!agg.has(aid)) agg.set(aid,{ aid, name:playerNameForAid(aid), count:0, totalLife:0, totalContest:0, totalPressure:0, totalQuality:0, elite:0, lowPressure:0, highContest:0, phaseCounts:new Map(), regionCounts:new Map(), spotCounts:new Map() }); return agg.get(aid); }
      for(const rawSpot of (spots||[])){
        const spotKey = String(rawSpot.spot||'');
        const perfItem = perfIndex.get(spotKey);
        if(!perfItem) continue;
        const regionNames = regionNamesForPoint(rawSpot.x, rawSpot.y);
        const region = regionNames[0] || '';
        const info = spotLabel({ spot:spotKey, x:rawSpot.x, y:rawSpot.y });
        for(const sm of (Array.isArray(rawSpot.samples)? rawSpot.samples : [])){
          if(!sampleMatches(sm, true)) continue;
          const aid = Number(sm.aid||sm.account_id||0); if(!(aid>0)) continue;
          const rec = ensure(aid);
          const life = Math.max(0, Number((sm.life!=null? sm.life : sm.lifetime)||0));
          const contest = Number(perfItem.contest||0);
          const pressure = Number(perfItem.senPressure||0);
          const lifeScore = Math.min(100, Math.round((life/240)*100));
          const placementScore = Math.round(0.55*lifeScore + 0.25*(100-pressure) + 0.20*(100-contest));
          rec.count++; rec.totalLife += life; rec.totalContest += contest; rec.totalPressure += pressure; rec.totalQuality += placementScore;
          if(eliteKeys.has(spotKey)) rec.elite++;
          if(pressure<=25) rec.lowPressure++;
          if(contest>=60) rec.highContest++;
          const phase = phaseForTime(sm.t);
          rec.phaseCounts.set(phase.id, (rec.phaseCounts.get(phase.id)||0)+1);
          if(region) rec.regionCounts.set(region, (rec.regionCounts.get(region)||0)+1);
          const spotRec = rec.spotCounts.get(spotKey) || { key:spotKey, label: info.title, coords: info.coords, count:0 };
          spotRec.count++;
          rec.spotCounts.set(spotKey, spotRec);
        }
      }
      const rows = Array.from(agg.values()).map(rec=>{
        const avgLife = rec.count? Math.round(rec.totalLife/rec.count) : 0;
        const avgContest = rec.count? Math.round(rec.totalContest/rec.count) : 0;
        const avgPressure = rec.count? Math.round(rec.totalPressure/rec.count) : 0;
        const avgQuality = rec.count? Math.round(rec.totalQuality/rec.count) : 0;
        const topRegions = Array.from(rec.regionCounts.entries()).sort((a,b)=> b[1]-a[1]).slice(0,3).map(([name,count])=> ({name,count}));
        const topSpots = Array.from(rec.spotCounts.values()).sort((a,b)=> b.count-a.count || String(a.label).localeCompare(String(b.label))).slice(0,5);
        const peakPhase = Array.from(rec.phaseCounts.entries()).sort((a,b)=> b[1]-a[1])[0];
        const phaseInfo = phaseDefs.find(ph=> ph.id === (peakPhase && peakPhase[0]));
        const zone = topRegions[0] ? topRegions[0].name : (topSpots[0] ? (topSpots[0].label || topSpots[0].coords) : 'mixed spots');
        const timingLabel = phaseInfo ? phaseInfo.label : 'their main timing';
        const peakLabel = phaseInfo ? phaseInfo.label : 'their peak phase';
        const topRegionShare = topRegions[0] ? (topRegions[0].count / Math.max(1, rec.count)) : 0;
        const eliteShare = rec.elite / Math.max(1, rec.count);
        const lowPressureShare = rec.lowPressure / Math.max(1, rec.count);
        const highContestShare = rec.highContest / Math.max(1, rec.count);
        const secondZone = topRegions[1] ? topRegions[1].name : (topSpots[1] ? (topSpots[1].label || topSpots[1].coords) : '');
        const thirdZone = topRegions[2] ? topRegions[2].name : (topSpots[2] ? (topSpots[2].label || topSpots[2].coords) : '');
        const topSpotNames = topSpots.map(s=> s.label || s.coords).filter(Boolean);
        const primarySpotKey = topSpots[0] ? String(topSpots[0].key||'') : '';
        const secondSpotKey = topSpots[1] ? String(topSpots[1].key||'') : '';
        const thirdSpotKey = topSpots[2] ? String(topSpots[2].key||'') : '';
        const primarySpot = topSpotNames[0] || zone;
        const secondSpot = topSpotNames[1] || secondZone || '';
        const thirdSpot = topSpotNames[2] || thirdZone || '';
        const counters = collectAdvice(5, [
          avgPressure < 30 && avgLife > 150 ? adviceItem(`Pre-place a sentry in ${zone} around ${timingLabel}; these wards live long because they dodge normal sentry routes.`, `zone:${zone}`, 'prep', primarySpotKey, zone) : '',
          (avgContest >= 60 || avgPressure >= 60) ? adviceItem(`Contest ${zone} on timing around ${timingLabel}; normal deward routes already catch these wards, so being on time matters most.`, `zone:${zone}`, 'contest', primarySpotKey, zone) : '',
          eliteShare >= 0.35 ? adviceItem(`Mirror-deward ${zone} before ${peakLabel}; that is where this player repeats high-value wards.`, `zone:${zone}`, 'mirror', primarySpotKey, zone) : '',
          adviceItem(`Watch ${zone} around ${timingLabel}; that is the repeat observer pattern.`, `zone:${zone}`, 'watch', primarySpotKey, zone),
          secondZone ? adviceItem(`Split one deward cycle between ${zone} and ${secondZone}; the pattern branches between both areas.`, `pair:${zone}|${secondZone}`, 'split', secondSpotKey || primarySpotKey, secondZone) : '',
          secondSpot ? adviceItem(`If the first sentry misses, check ${secondSpot} immediately after ${primarySpot}; this player does not stop at one exact cliff.`, `pair:${primarySpot}|${secondSpot}`, 'chain', secondSpotKey || primarySpotKey, secondSpot) : '',
          avgLife >= 150 ? adviceItem(`Bring body presence or smoke when you clear the warded route; these wards often survive because the area stays defended.`, 'general:escort', 'escort', '', '') : '',
          lowPressureShare >= 0.45 ? adviceItem(`Place the sentry a step off the standard cliff line near ${primarySpot}; many of the surviving wards are intentionally offset.`, `spot:${primarySpot}`, 'offset', primarySpotKey, primarySpot) : '',
          highContestShare >= 0.35 ? adviceItem(`Punish the timing window into this area, not just the pixel; this player still repeats the same setup even when wards get contested.`, `timing:${timingLabel}`, 'timing', '', '') : '',
          adviceItem(`Hold one extra sentry for the second cycle instead of spending both early; this profile comes back after the first clear.`, 'general:resource', 'resource', '', ''),
          secondZone ? adviceItem(`Ward one route into ${zone} and sentry the other route into ${secondZone}; forcing them through vision makes the deward easier.`, `pair:${zone}|${secondZone}`, 'route-split', secondSpotKey || primarySpotKey, secondZone) : '',
          adviceItem(`Ping the support entry route before ${timingLabel}; catching the player is better than only clearing the ward.`, 'general:entry', 'entry', '', ''),
          adviceItem(`Refresh vision after each successful deward; repeat patterns often return on the next cycle.`, 'general:refresh', 'refresh', '', ''),
          adviceItem(`If you cannot hold the area, deward the exit path from it; breaking the safe retreat still ruins the setup.`, 'general:exit', 'exit', '', ''),
          thirdZone ? adviceItem(`Keep a backup scan for ${thirdZone}; the pattern leaks into a third zone often enough to punish lazy resets.`, `zone:${thirdZone}`, 'third-zone', thirdSpotKey || secondSpotKey || primarySpotKey, thirdZone) : '',
          thirdSpot ? adviceItem(`After you clear ${primarySpot}, sweep ${thirdSpot} on the same pass; that alternate point keeps the pattern alive.`, `spot:${thirdSpot}`, 'third-spot', thirdSpotKey || secondSpotKey || primarySpotKey, thirdSpot) : ''
        ]);
        const improvements = collectAdvice(5, [
          avgLife < 90 ? adviceItem(`Delay this ward until your team has lane control or move cover; right now it gets checked on the first pass.`, `timing:${timingLabel}`, 'delay', '', '') : '',
          avgPressure >= 60 ? adviceItem(`Move one step off the common sentry line near ${primarySpot}; this pattern still overlaps too much with standard deward routes.`, `spot:${primarySpot}`, 'offset', primarySpotKey, primarySpot) : '',
          avgContest >= 60 ? adviceItem(`Keep the zone, but change the timing around ${timingLabel} so opponents cannot deward it on autopilot.`, `timing:${timingLabel}`, 'timing-shift', '', '') : '',
          topRegionShare >= 0.55 && secondZone ? adviceItem(`Mix in ${secondZone} next to ${zone}; repeating the same zone too often makes the read too easy.`, `zone:${secondZone}`, 'branch-zone', secondSpotKey || primarySpotKey, secondZone) : '',
          lowPressureShare < 0.3 ? adviceItem(`Lean harder into lower-pressure edge wards instead of the obvious entrances and rune approaches.`, 'general:edge', 'edge', '', '') : '',
          secondSpot ? adviceItem(`Alternate between ${primarySpot} and ${secondSpot} instead of anchoring on one exact point every game.`, `pair:${primarySpot}|${secondSpot}`, 'alternate', secondSpotKey || primarySpotKey, secondSpot) : adviceItem(`Keep the timing, but alternate two nearby ward points so the next sentry does not catch the same setup twice.`, 'general:alternate', 'alternate', primarySpotKey, ''),
          secondZone ? adviceItem(`Use ${secondZone} as the branch option when ${zone} is already under enemy control.`, `zone:${secondZone}`, 'fallback-zone', secondSpotKey || primarySpotKey, secondZone) : '',
          avgLife >= 150 && avgPressure < 30 ? adviceItem(`Tie these long-living wards to an objective or smoke window so the extra uptime converts into map gain.`, 'general:conversion', 'conversion', '', '') : '',
          highContestShare >= 0.35 ? adviceItem(`Show on lanes first and place the ward 20–40 seconds later; desyncing the timing matters more than changing the zone.`, `timing:${timingLabel}`, 'desync', '', '') : '',
          adviceItem(`Sync the ward with the teammate who can protect the nearest lane entry; unsupported deep wards are much easier to read and remove.`, 'general:team', 'team-sync', '', ''),
          adviceItem(`After one successful ward, change either height, timing, or approach on the next attempt.`, 'general:adapt', 'adapt', '', ''),
          adviceItem(`Keep one backup placement ready so a missed timing does not force the exact same ward again.`, 'general:backup', 'backup', '', ''),
          adviceItem(`Review which enemy sentry path removed the last ward and move one step off that line next time.`, 'general:review', 'review', '', ''),
          adviceItem(`If the map is dark, enter from the edge your team already controls instead of from the center access path.`, 'general:entry-path', 'entry-path', '', ''),
          thirdZone ? adviceItem(`Rotate one ward cycle into ${thirdZone} so opponents cannot narrow you down to only ${zone} and ${secondZone || primarySpot}.`, `zone:${thirdZone}`, 'third-zone', thirdSpotKey || secondSpotKey || primarySpotKey, thirdZone) : '',
          thirdSpot ? adviceItem(`Use ${thirdSpot} as the surprise placement after showing the usual ${primarySpot} setup once.`, `spot:${thirdSpot}`, 'third-spot', thirdSpotKey || secondSpotKey || primarySpotKey, thirdSpot) : ''
        ]);
        return {
          ...rec,
          avgLife,
          avgContest,
          avgPressure,
          avgQuality,
          topRegions,
          topSpots,
          phaseInfo,
          counters,
          improvements,
          counter: counters[0] && counters[0].text || '',
          improvement: improvements[0] && improvements[0].text || '',
          summary: `${rec.count} placements · avg ${fmtMMSS(avgLife)} · quality ${avgQuality}`
        };
      }).filter(rec=> rec.count>0);
      rows.sort((a,b)=> (b.avgQuality-a.avgQuality) || (b.elite-a.elite) || (b.count-a.count) || String(a.name).localeCompare(String(b.name)));
      if(focusSel.hasAny){ return rows.filter(rec=> focusSel.set.has(rec.aid)); }
      return rows.slice(0,3);
    }
    function renderIntro(playerTrends){
      const intro = root.querySelector('#wvIntro'); if(!intro) return;
      const lensValue = state.basis==='contest'
        ? (state.mode==='best' ? 'Safest wards on map' : 'Most contested wards')
        : (state.mode==='best' ? 'Highest-value ward spots' : 'Fastest punished ward spots');
      const lensText = state.basis==='contest'
        ? 'Contest shows which wards are easy to predict and punish.'
        : 'Lifetime favors wards that stay up and dodge standard sentries.';
      const heroChips = [state.team || 'All teams', twNow.label, playerSelectionLabel(), state.basis];
      const spotlight = playerTrends[0];
      const extraChip = spotlight ? `spotlight ${spotlight.name}` : `${best.length + worst.length} ranked spots`;
      intro.innerHTML = `<div class='wv-introbar'>
        <div class='wv-intro-main'>
          <div class='wv-intro-kicker'>Current view</div>
          <div class='wv-intro-value'>${esc(lensValue)}</div>
          <div class='wv-intro-text'>${esc(lensText)}</div>
        </div>
        <div class='wv-intro-meta'>${heroChips.concat(extraChip).map(ch=> `<span class='wv-intro-chip'>${esc(ch)}</span>`).join('')}</div>
      </div>`;
    }
    function renderSpotCards(arr, kind){
      if(!arr.length) return `<div class='wv-sub'>No data</div>`;
      return `<ul class='wv-spotcards'>` + arr.map((s,idx)=>{
        const key = String(s.spot||'');
        const label = spotLabel(s);
        const playersTop = topPlayersForItem(s, 3);
        const why = whyForSpot(s, kind);
        const contestBadge = `<span class='wv-badge'>contest ${Math.round(Number(s.contest||0))}</span>`;
        const timeBadge = `<span class='wv-badge'>avg ${fmtMMSS(Number(s.avg||0))}</span>`;
        const countBadge = Number(s.count||0)? `<span class='wv-badge'>x${Number(s.count||0)}</span>` : '';
        const pressureBadge = isFinite(Number(s.senPressure)) ? `<span class='wv-badge'>pressure ${Math.round(Number(s.senPressure||0))}</span>` : '';
        const eliteCls = eliteKeys.has(key) ? ' elite' : '';
        const playersLine = playersTop.length ? `<div class='wv-playerline'><b>Players:</b> ${playersTop.map(p=> `${esc(p.name)} x${p.count}${p.avg? ` · ${fmtMMSS(p.avg)}`:''}`).join(' · ')}</div>` : '';
        const ariaLbl = `${kind==='best' ? 'Best' : 'Worst'} ward ${idx+1}, ${label.coords}`;
        return `<li data-spot='${esc(key)}' class='wv-spotitem ${kind==='best'?'bestcard':'worstcard'}${eliteCls}' role='button' tabindex='0' aria-label='${esc(ariaLbl)}'>
          <div class='wv-spothead'>
            <div class='wv-spotmeta'>
              <span class='wv-rank'>#${idx+1}</span>
              <div class='wv-spottitle'>${esc(label.title)}</div>
              ${label.subtitle ? `<div class='wv-spotcoords'>${esc(label.subtitle)}</div>` : ''}
            </div>
            <button class='tab' data-pin='${esc(key)}'>${isPinned(key)?'Unpin':'Pin'}</button>
          </div>
          <div class='wv-why'>${esc(why || 'No clear reason available for current filters.')}</div>
          <div class='wv-chipline'>${state.basis==='contest' ? `${contestBadge}${pressureBadge}${countBadge}` : `${timeBadge}${contestBadge}${pressureBadge}${countBadge}`}</div>
          ${playersLine}
        </li>`;
      }).join('') + `</ul>`;
    }
    function renderPlayerTrends(){
      const host = root.querySelector('#wvTrends'); if(!host) return;
      const trends = buildPlayerTrends();
      renderIntro(trends);
      if(!trends.length){ host.innerHTML = `<div class='wv-sub'>No stable player pattern for the current filters.</div>`; return; }
      function renderAdviceList(items){
        return `<ol class='wv-counterlist'>${items.map(item=>{ const rec = (item && typeof item==='object' && !Array.isArray(item)) ? item : { text:String(item||''), targetSpot:'' }; const text = String(rec.text||'').trim(); if(!text) return ''; const target = String(rec.targetSpot||''); return `<li class='wv-counteritem'><span class='wv-countertext'>${esc(text)}</span>${target ? `<span class='wv-counteractions'><button class='wv-mini-action' data-goto='${esc(target)}' type='button'>Go</button><button class='wv-mini-action' data-pinspot='${esc(target)}' type='button'>Pin</button></span>` : ''}</li>`; }).join('')}</ol>`;
      }
      function renderTrendSpots(items){
        return `<ol class='wv-trendspots'>${(Array.isArray(items)? items: []).map(item=>{ const key = String(item && item.key || ''); const label = String(item && (item.label || item.coords) || 'Spot'); const count = Number(item && item.count || 0); return `<li class='wv-trendspotline'><span class='wv-trendspotmeta'>${esc(label)}<span class='count'>x${count}</span></span>${key ? `<span class='wv-counteractions'><button class='wv-mini-action' data-goto='${esc(key)}' type='button'>Go</button><button class='wv-mini-action' data-pinspot='${esc(key)}' type='button'>Pin</button></span>` : ''}</li>`; }).join('')}</ol>`;
      }
      host.innerHTML = `<div class='wv-trendlist'>${trends.map(rec=> {
        const targetSpot = rec.topSpots && rec.topSpots[0] ? String(rec.topSpots[0].key||'') : '';
        const counterItems = Array.isArray(rec.counters) && rec.counters.length ? rec.counters : (rec.counter ? [{ text:rec.counter, targetSpot:targetSpot }] : []);
        const improvementItems = Array.isArray(rec.improvements) && rec.improvements.length ? rec.improvements : (rec.improvement ? [{ text:rec.improvement, targetSpot:targetSpot }] : []);
        return `
        <div class='wv-trendcard'>
          <div class='wv-trendtop'>
            <div>
              <div class='wv-spottitle'>${esc(rec.name)}</div>
              <div class='wv-trendsub'>${esc(rec.summary)}</div>
            </div>
            <div class='wv-chipline'>
              ${rec.elite? `<span class='wv-badge'>elite ${rec.elite}</span>`:''}
              <span class='wv-badge'>contest ${rec.avgContest}</span>
              <span class='wv-badge'>pressure ${rec.avgPressure}</span>
            </div>
          </div>
          <div class='wv-trendsub' style='margin-top:8px'><b>Pattern:</b> ${rec.phaseInfo ? esc(rec.phaseInfo.label) : 'mixed timing'} · ${rec.topRegions.length ? esc(rec.topRegions.map(r=> r.name).join(' / ')) : esc(rec.topSpots.map(s=> s.label).join(' / ') || 'mixed map')}</div>
          ${rec.topRegions.length ? `<div class='wv-chipline'>${rec.topRegions.map(r=> `<span class='wv-badge'>${esc(r.name)} x${r.count}</span>`).join('')}</div>` : ''}
          ${rec.topSpots.length ? `<div class='wv-counterline'><b>Most placed spots:</b>${renderTrendSpots(rec.topSpots)}</div>` : ''}
          <div class='wv-counterline'><b>Counter:</b>${renderAdviceList(counterItems)}</div>
          <div class='wv-counterline'><b>Improve:</b>${renderAdviceList(improvementItems)}</div>
          ${targetSpot ? `<div class='wv-actions'><button class='tab' data-goto='${esc(targetSpot)}'>Go to on map</button><button class='tab' data-pinspot='${esc(targetSpot)}'>Go to + pin</button></div>` : ''}
        </div>`;
      }).join('')}</div>`;
    }
  // Index of spots currently rendered (accounts for clustering)
  const spotIndex = new Map();
  function equalSpotKey(a,b){ const ca=String(a||'').replace(/[\[\]\s]/g,''); const cb=String(b||'').replace(/[\[\]\s]/g,''); return ca===cb; }
  function parseXY(key){ try{ const c=String(key||'').replace(/[\[\]\s]/g,'').split(','); if(c.length!==2) return null; const x=parseFloat(c[0]), y=parseFloat(c[1]); if(!isFinite(x)||!isFinite(y)) return null; return {x,y}; }catch(_e){ return null; } }
  function getItemForKey(key){
    const k = String(key || '');
    const ck = k.replace(/[\[\]\s]/g,'');
    let it = null;
    try{
      // 1) direct in spotIndex (exact or cleaned)
      it = spotIndex.get(k) || null;
      if(!it){ for(const [sk,sv] of spotIndex.entries()){ if(equalSpotKey(sk,k)){ it = sv; break; } } }
      // 2) search lists by cleaned key
      function findIn(arr){ if(!Array.isArray(arr)) return null; const f = arr.find(s=> equalSpotKey(s.spot, k)); return f||null; }
      if(!it) it = findIn(filteredForRanking);
      if(!it) it = findIn(perfForRanking);
      if(!it) it = findIn(perf2);
      if(!it) it = findIn(best);
      if(!it) it = findIn(worst);
      if(!it) it = findIn(derived);
      // 3) numeric near-match tolerance on derived
      if(!it){ const xy = parseXY(k); if(xy){ const tol = 0.2; // tolerate small rounding differences
          function parseItemXY(skey){ const p=parseXY(skey); return p? p : null; }
          const cand = (derived||[]).find(s=>{ const p=parseItemXY(s.spot); return p && Math.abs(p.x-xy.x)<=tol && Math.abs(p.y-xy.y)<=tol; });
          if(cand) it=cand; }
      }
    }catch(_e){}
    return it;
  }
  function addSpot(list, cls){
    function colorForContest(d){ const t = Math.max(0, Math.min(1, Number(d||0)/100)); const h = 120*(1-t); const stroke = `hsl(${h} 80% 55%)`; const fill = `hsla(${h} 80% 55% / 0.32)`; return {stroke, fill}; }
    function drawSelectedRangeForSpot(cx, cy){
      try{
        svg.querySelectorAll('.spot-range').forEach(n=> n.remove());
        const range = document.createElementNS('http://www.w3.org/2000/svg','circle');
        range.setAttribute('cx', cx+'%');
        range.setAttribute('cy', cy+'%');
        range.setAttribute('r', String(selectionObsPct));
        range.setAttribute('class', 'spot-range');
        svg.insertBefore(range, svg.firstChild);
      }catch(_e){}
    }
    list.forEach(s=>{
      const {cx,cy}=norm(s.x,s.y);
      const key=String(s.spot||'');
      // track for details lookup
      try{ spotIndex.set(key, s); }catch(_e){}
  const drawIcon = true;
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
      if(eliteKeys.has(key)) klass+=' elite';
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
      // Make spot focusable/operable
      try{
        ring.setAttribute('tabindex','0');
        ring.setAttribute('role','button');
        const avgL = Number(s.avg||0); const cntL = Number(s.count||0);
        const mm = Math.floor(avgL/60), ss = avgL%60;
        const baseLbl = (state.basis==='contest') ? `Contest ${Math.round(Number(s.contest||0)||0)}` : `Average ${mm}m ${ss}s`;
        ring.setAttribute('aria-label', `Ward spot ${key.replace(/[\[\]\s]/g,'')} — ${baseLbl}, placements ${cntL}`);
      }catch(_e){}
      // Color the ring appropriately
      if(state.basis==='contest'){
        const {stroke, fill} = colorForContest(Number(s.contest||0));
        ring.style.stroke = stroke;
        ring.style.fill = fill;
        ring.setAttribute('stroke-width', '1');
      }
      // If regions are available, annotate with data-region for simple inspection/debug (comma-separated)
      try{
        const regs = Array.isArray(lastCtx && lastCtx.regions)? lastCtx.regions : [];
        if(regs.length){
          const nx = Number(cx)/100, ny = Number(cy)/100;
          function inPoly(x,y,poly){ let inside=false; for(let i=0,j=poly.length-1;i<poly.length;j=i++){ const xi=poly[i][0], yi=poly[i][1]; const xj=poly[j][0], yj=poly[j][1]; const intersect = ((yi>y)!==(yj>y)) && (x < (xj - xi) * (y - yi) / ((yj - yi)||1e-9) + xi); if(intersect) inside=!inside; } return inside; }
          const names = regs.filter(r=> Array.isArray(r.poly)&&r.poly.length>=3 && inPoly(nx,ny,r.poly)).map(r=> r.name||r.id||'Region');
          if(names.length) ring.setAttribute('data-region', names.join(','));
        }
      }catch(_e){}
      svg.appendChild(ring);
      const dot=document.createElementNS('http://www.w3.org/2000/svg','circle');
      dot.setAttribute('cx',cx+'%'); dot.setAttribute('cy',cy+'%');
      dot.setAttribute('r', isPinned(key)? '1.6' : '1.0'); dot.setAttribute('class', eliteKeys.has(key)? 'pindot elite' : 'pindot');
      let stroke = isPinned(key)? '#fbbf24' : (cls==='best'? '#34d399' : (cls==='worst'? '#ff6b6b' : 'rgba(255,215,0,0.85)'));
      if(state.basis==='contest' && !isPinned(key)){
        stroke = colorForContest(Number(s.contest||0)).stroke;
      }
      dot.style.fill = stroke; dot.setAttribute('opacity','0.95'); svg.appendChild(dot);
      function onPick(evt){
        const multi = evt && (evt.ctrlKey || evt.metaKey || evt.shiftKey);
        if(multi){ togglePin(key); return; }
        state.wspot = key; persistState();
        // highlight selected
        svg.querySelectorAll('.spot.selected').forEach(n=> n.classList.remove('selected'));
        ring.classList.add('selected');
        drawSelectedRangeForSpot(cx, cy);
        const box = ring.getBoundingClientRect();
  openFlyoutAt((box.left+box.right)/2, (box.top+box.bottom)/2, ring);
        renderFlyFor(key, s);
      }
      ring.addEventListener('click', onPick);
      dot.addEventListener('click', onPick);
      ring.addEventListener('keydown', (e)=>{ if(e.key==='Enter' || e.key===' '){ e.preventDefault(); onPick(e); } });
      ring.addEventListener('focus', ()=>{ try{ showTipFromSpot(ring); }catch(_e){} });
      ring.addEventListener('blur', ()=>{ try{ const tip=root.querySelector('#wvTip'); if(tip){ tip.classList.remove('show'); tip.setAttribute('aria-hidden','true'); } }catch(_e){} });
    });
  }
  // hotspots and sentry markers first (underlay)
  renderSentryHotspots();
  renderSentryMarkers();
  const primaryList = state.mode==='best' ? best : worst;
  addSpot(primaryList, state.mode==='best' ? 'best' : 'worst');
  const visibleKeys = new Set(primaryList.map(s=> String(s.spot||'')));
  const extraFocus = [];
  const extraSeen = new Set();
  for(const rawKey of [].concat(Array.isArray(state.pins) ? state.pins : [], state.wspot ? [state.wspot] : [])){
    const key = String(rawKey||'');
    if(!key || visibleKeys.has(key) || extraSeen.has(key)) continue;
    const item = getItemForKey(key);
    if(!item) continue;
    extraFocus.push(item);
    extraSeen.add(key);
  }
  if(extraFocus.length) addSpot(extraFocus, 'neutral');
      if(state.grid){ const g=document.createElementNS('http://www.w3.org/2000/svg','g'); for(let i=0;i<=10;i++){ const p=i*10; const v1=document.createElementNS('http://www.w3.org/2000/svg','line'); v1.setAttribute('x1',p+'%'); v1.setAttribute('y1','0%'); v1.setAttribute('x2',p+'%'); v1.setAttribute('y2','100%'); v1.setAttribute('stroke','rgba(255,255,255,.08)'); v1.setAttribute('stroke-width','0.3'); g.appendChild(v1); const v2=document.createElementNS('http://www.w3.org/2000/svg','line'); v2.setAttribute('x1','0%'); v2.setAttribute('y1',p+'%'); v2.setAttribute('x2','100%'); v2.setAttribute('y2',p+'%'); v2.setAttribute('stroke','rgba(255,255,255,.08)'); v2.setAttribute('stroke-width','0.3'); g.appendChild(v2);} svg.insertBefore(g, svg.firstChild); }
  
  // status line removed
  // update legend message based on vision mode/basis
    const legend = root.querySelector('#wvLegend');
    if(legend){ if(state.basis==='contest'){ legend.textContent = 'Green = safer, low-pressure vision. Red = predictable, heavily contested wards. Use the cards to see why and who places them.'; } else { legend.textContent = 'Green = long-lived, high-value wards. Red = fast-punished wards. The cards explain why and which players favor them.'; } }
      // lists
      const bestEl=root.querySelector('#wvBest'); if(bestEl) bestEl.innerHTML = renderSpotCards(best, 'best');
      const worstEl=root.querySelector('#wvWorst'); if(worstEl) worstEl.innerHTML = renderSpotCards(worst, 'worst');
    renderPlayerTrends();
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
  // Click on list to open details (non-button area)
  function bindListClicks(id){ const c=root.querySelector(id); if(!c) return; c.querySelectorAll('li[data-spot]').forEach(li=>{
  const activate = (e)=>{ if(e && e.target && e.target.closest && e.target.closest('[data-pin]')) return; const key=li.getAttribute('data-spot'); focusSpot(key, false); };
    li.addEventListener('click', activate);
    li.addEventListener('keydown', (e)=>{ if(e.key==='Enter' || e.key===' '){ e.preventDefault(); activate(e); } });
  }); }
  bindListClicks('#wvBest'); bindListClicks('#wvWorst');
  root.querySelectorAll('[data-goto]').forEach(btn=>{ btn.addEventListener('click', (e)=>{ e.preventDefault(); e.stopPropagation(); focusSpot(btn.getAttribute('data-goto'), false); }); btn.addEventListener('keydown', (e)=>{ if(e.key==='Enter' || e.key===' '){ e.preventDefault(); focusSpot(btn.getAttribute('data-goto'), false); } }); });
  root.querySelectorAll('[data-pinspot]').forEach(btn=>{ btn.addEventListener('click', (e)=>{ e.preventDefault(); e.stopPropagation(); focusSpot(btn.getAttribute('data-pinspot'), true); }); btn.addEventListener('keydown', (e)=>{ if(e.key==='Enter' || e.key===' '){ e.preventDefault(); focusSpot(btn.getAttribute('data-pinspot'), true); } }); });
  // Pin buttons in lists
  root.querySelectorAll('[data-pin]').forEach(btn=>{ btn.setAttribute('aria-pressed', String(isPinned(btn.getAttribute('data-pin')))); btn.addEventListener('click', (e)=>{ e.stopPropagation(); const key=btn.getAttribute('data-pin'); togglePin(key); }); btn.addEventListener('keydown', (e)=>{ if(e.key==='Enter' || e.key===' '){ e.preventDefault(); const key=btn.getAttribute('data-pin'); togglePin(key); } }); });
  // Update pins bar
  setPinsBar();
  // Update shared context for flyout lookups
  try{
    lastCtx.spotIndex = spotIndex;
    lastCtx.perfForRanking = filteredForRanking;
    lastCtx.perf2 = perf2;
    lastCtx.best = best;
    lastCtx.worst = worst;
    lastCtx.derived = derived;
    lastCtx.asset = asset;
    lastCtx.hasBounds = !!hasBounds;
    lastCtx.invertY = !!invertY;
    lastCtx.dynScale = dynScale;
    lastCtx.obsPct = obsPct;
    lastCtx.senPct = senPct;
    lastCtx.sentIdx = sentIdx;
  lastCtx.pressMap = pressMap;
  lastCtx.pressMax = maxAcc;
    // Optional objectives passed via map config or options, with support for shared map_locations.json structure
    let objectives = (mc && mc.objectives && Array.isArray(mc.objectives) ? mc.objectives : (cfg && cfg.options && Array.isArray(cfg.options.objectives) ? cfg.options.objectives : null)) || null;
    function locationPointNorm(x,y){
      const xx = Number(x||0), yy = Number(y||0);
      // map_locations.json stores editor percentages, not raw world coordinates
      if(isFinite(xx) && isFinite(yy) && xx>=0 && xx<=100 && yy>=0 && yy<=100){
        return { nx: xx/100, ny: yy/100 };
      }
      const n = norm(xx, yy);
      return { nx: Number(n.cx||0)/100, ny: Number(n.cy||0)/100 };
    }
    // If cfg.options.objectivesUrl is provided, try to fetch it and merge lazily
    async function tryLoadExternalObjectives(url){
      try{
        const res = await fetch(url, {cache:'no-store'});
        if(res.ok){
          const data = await res.json();
          // Accept either {items:[...]} or direct array
          const items = Array.isArray(data) ? data : (Array.isArray(data.items) ? data.items : []);
          // Points considered objectives for proximity: explicit objectives and camps
          const pts = items.filter(it=> (it && (String(it.type||'')==='objective' || String(it.type||'')==='camp')) && Array.isArray(it.points) && it.points.length)
            .map(it=>({ x: Number(it.points[0].x||0), y: Number(it.points[0].y||0), type: String(it.type||'objective'), name: String(it.name||it.id||it.type||'') }));
          const mapPts = items.filter(it=> it && (String(it.type||'')==='objective' || String(it.type||'')==='camp' || String(it.type||'')==='poi') && Array.isArray(it.points) && it.points.length)
            .map(it=>{ const n=locationPointNorm(Number(it.points[0].x||0), Number(it.points[0].y||0)); return { nx:n.nx, ny:n.ny, name:String(it.name||it.id||it.type||''), side:String(it.side||'') }; });
          const existing = Array.isArray(objectives) ? objectives.slice() : [];
          const merged = existing.concat(pts);
          lastCtx.objectivesNorm = merged.map(pt=>{ const n = locationPointNorm(pt.x, pt.y); return { nx: n.nx, ny: n.ny, type: String(pt.type||'') }; });
          if(mapPts.length) lastCtx.mapPoints = mapPts;
          // Also parse regions (polygons) for later use
          const regs = items.filter(it=> String(it.type||'')==='region' && it.shape && it.shape.kind==='polygon' && Array.isArray(it.points) && it.points.length>=3)
            .map(it=>({ id:String(it.id||''), name:String(it.name||''), side:String(it.side||''),
                        poly: it.points.map(p=>{ const n=locationPointNorm(Number(p.x||0), Number(p.y||0)); return [n.nx, n.ny]; }) }));
          if(regs.length){ lastCtx.regions = regs; }
          return;
        }
      }catch(_e){}
      // Fallback to current objectives if fetch failed
      const arr = Array.isArray(objectives)? objectives : [];
      lastCtx.objectivesNorm = arr.map(pt=>{ const n = locationPointNorm(pt.x, pt.y); return { nx: n.nx, ny: n.ny, type: String(pt.type||'') }; });
    }
    if(Array.isArray(objectives)){
      lastCtx.objectivesNorm = objectives.map(pt=>{ const n = locationPointNorm(pt.x, pt.y); return { nx: n.nx, ny: n.ny, type: String(pt.type||'') }; });
      lastCtx.mapPoints = [];
      // If an external URL is configured, augment lazily
      const url = cfg && cfg.options && cfg.options.objectivesUrl;
      if(url){ tryLoadExternalObjectives(String(url)); }
    } else {
      // No inline objectives: attempt external if configured, else empty
      const url = cfg && cfg.options && cfg.options.objectivesUrl;
      if(url){
        // Try the provided URL first
        tryLoadExternalObjectives(String(url));
        // Also attempt common fallbacks if path looks relative to docs/
        try{
          const isRel = !/^https?:/i.test(String(url));
          if(isRel){
            const rootAlt = String(url).replace(/^\.\/data\//,'../data/').replace(/^data\//,'../data/');
            if(rootAlt!==url) tryLoadExternalObjectives(rootAlt);
          }
        }catch(_e){}
      }
      else { lastCtx.objectivesNorm = []; lastCtx.mapPoints = []; }
    }
    // Ensure regions is always an array for downstream
    if(!Array.isArray(lastCtx.regions)) lastCtx.regions = [];
    if(!Array.isArray(lastCtx.mapPoints)) lastCtx.mapPoints = [];
  }catch(_e){}
  // If there's a selected spot in state, open flyout and attempt to highlight near the spot
  if(state.wspot){ try{ svg.querySelectorAll('.spot').forEach(n=>{ if(n.getAttribute('data-spot')===state.wspot){ n.classList.add('selected'); const cxSel = Number(n.getAttribute('data-cx')||0); const cySel = Number(n.getAttribute('data-cy')||0); if(isFinite(cxSel) && isFinite(cySel)){ const range = document.createElementNS('http://www.w3.org/2000/svg','circle'); range.setAttribute('cx', cxSel+'%'); range.setAttribute('cy', cySel+'%'); range.setAttribute('r', String(selectionObsPct)); range.setAttribute('class', 'spot-range'); svg.insertBefore(range, svg.firstChild); } const box=n.getBoundingClientRect(); openFlyoutAt((box.left+box.right)/2, (box.top+box.bottom)/2, n); } }); }catch(_e){} renderFlyFor(state.wspot); }
    }
    // initial render
  // Persist initial state (to reflect defaults/params)
  persistState();
  render();
  // Reset button binding
  try{ const rst=root.querySelector('#wvReset'); if(rst){ rst.addEventListener('click',()=>{
    state = { mode: (cfg && cfg.options && cfg.options.modeDefault) || 'best', team:'', player:'', time:'', overlay:true, grid:false, hotSentries:false, showSentries:false, minCount:1, topN:'all', basis: BASIS_DEFAULT, includeZeroWorst:false, pins:[], pquery:'', tquery:'', cluster:0, wspot:'' };
    // Clear URL params
    try{ const sp = new URLSearchParams(); replaceUrl(sp); }catch(_e){}
    // Clear storage
    try{ Object.keys(LS_KEY).forEach(k=> writeStorage(LS_KEY[k], '')); }catch(_e){}
    // Reset toggles
    try{ const ht=root.querySelector('#wvHot'); if(ht){ ht.checked = false; } }catch(_e){}
    try{ const smk=root.querySelector('#wvSentries'); if(smk){ smk.checked = false; } }catch(_e){}
    try{ const zw=root.querySelector('#wvZeroWorst'); if(zw){ zw.checked = false; const lab=zw.closest('label'); if(lab){ lab.style.display = (state.mode==='worst')? '' : 'none'; } } }catch(_e){}
    // Reset active buttons
    root.querySelectorAll('#wvTabs .tab').forEach(b=> b.classList.toggle('active',(b.dataset.wmode||'')===state.mode));
    try{ svg.style.display = ''; }catch(_e){}
    updateViewAndListLabels();
    setActiveTime(); setActiveMin(); setActiveTop(); setActiveBasis(); setActiveCluster(); setActiveMapToggles();
    persistState(); render();
  }); } }catch(_e){}
  }
  window.WardViewer = { mount };
})();

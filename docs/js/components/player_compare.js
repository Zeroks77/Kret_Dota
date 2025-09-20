/* Player Comparison Component
 * Contract:
 *   mount(containerEl, options):
 *     options = {
 *       data: { matches, playersIndex, heroes },
 *       leagueLock: 18438,
 *       onCopyLink?: (url) => void
 *     }
 * State:
 *   { playerA: number|null, playerB: number|null, side: 'all'|'radiant'|'dire' }
 * Minimal MVP:
 *   - Two pickers (A/B) populated from playersIndex
 *   - Filter bar (side)
 *   - Summary area with placeholders
 *   - Copy link button to persist state
 */

(function(){
  function ensureStyles(){
    if(document.getElementById('pc-styles')) return;
    const css = `
    .pc-wrap{display:flex;flex-direction:column;gap:10px}
    .pc-controls{display:flex;flex-wrap:wrap;gap:8px;align-items:end}
    .pc-controls label{font-size:12px;color:var(--muted)}
    .pc-summary{display:grid;grid-template-columns:1fr 1fr;gap:12px}
  .pc-full{display:flex;flex-direction:column;gap:12px}
    .pc-col{display:flex;flex-direction:column;gap:10px}
    .pc-card{border:1px solid var(--border);border-radius:12px;padding:10px;background:linear-gradient(180deg,rgba(255,255,255,.04),rgba(255,255,255,.02))}
  .pc-card-title{font-weight:600;margin:0 0 6px;color:var(--muted);display:flex;align-items:center;justify-content:space-between;position:relative}
    .pc-card-list{list-style:none;margin:0;padding:0}
    .pc-card-list li{display:flex;align-items:center;gap:8px;justify-content:space-between;padding:6px 0;border-bottom:1px solid rgba(255,255,255,.06)}
    .pc-card-list li:last-child{border-bottom:0}
    .pc-grid{display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px}
    .pc-pools{display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px;margin-top:6px}
    .pc-hero-list{list-style:none;margin:0;padding:0}
    .pc-hero-list li{display:flex;align-items:center;gap:8px;padding:6px 0;border-bottom:1px solid rgba(255,255,255,.06)}
    .pc-hero-list li:last-child{border-bottom:0}
    .pc-hero-icon{width:22px;height:22px;border-radius:6px;border:1px solid rgba(255,255,255,.1);object-fit:cover}
  .pc-item-icon{width:22px;height:22px;border-radius:6px;border:1px solid rgba(255,255,255,.1);object-fit:cover;background:rgba(255,255,255,.04)}
  .pc-item-row{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:6px 0;border-bottom:1px solid rgba(255,255,255,.06)}
  .pc-item-row.three{display:grid;grid-template-columns:1fr auto 1fr;align-items:center}
  .pc-item-row:last-child{border-bottom:0}
  .pc-item-mid{display:flex;align-items:center;gap:8px;justify-content:center}
  .pc-side{display:flex;align-items:center}
  .pc-side.a{justify-content:flex-start}
  .pc-side.b{justify-content:flex-end}
  .pc-badge.fast{color:#7be495}
  .pc-badge.slow{color:#ff8b8b}
  .pc-badge.even{color:var(--muted)}
    .pc-row{display:flex;align-items:center;justify-content:space-between;gap:8px}
    .pc-badge{display:inline-block;padding:2px 6px;border-radius:999px;background:var(--chip);font-size:12px}
    .pc-delta.pos{color:#7be495}
    .pc-delta.neg{color:#ff8b8b}
    .pc-bars{display:flex;flex-direction:column;gap:6px}
  .pc-bar{height:10px;background:rgba(255,255,255,.08);border-radius:999px;position:relative;overflow:hidden}
  .pc-bar.dual{display:block}
  .pc-bar .mid{position:absolute;left:50%;top:0;bottom:0;width:1px;background:rgba(255,255,255,.18)}
  .pc-bar > span{position:absolute;top:0;bottom:0;border-radius:999px}
  .pc-bar .bA{left:0;background:linear-gradient(90deg, rgba(123,228,149,.9), rgba(123,228,149,.5))}
  .pc-bar .bB{right:0;background:linear-gradient(90deg, rgba(255,139,139,.5), rgba(255,139,139,.9))}
    .pc-two{display:grid;grid-template-columns:1fr 1fr;gap:10px}
  .pc-note{font-size:12px;color:var(--muted);margin-top:4px}
    .pc-debug{font-size:12px;font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;color:var(--muted);white-space:pre-wrap}
    .pc-debug b{color:#d5eaff}
    /* Split layout for side-by-side metrics */
    .pc-split{display:flex;flex-direction:column;gap:6px}
    .pc-split-row{display:grid;grid-template-columns:1fr auto 1fr;align-items:center;gap:10px;padding:6px 0;border-bottom:1px solid rgba(255,255,255,.06)}
    .pc-split-row:last-child{border-bottom:0}
    .pc-split-left{display:flex;justify-content:flex-start;gap:6px;align-items:baseline}
    .pc-split-right{display:flex;justify-content:flex-end;gap:6px;align-items:baseline}
    .pc-center{color:var(--muted);font-size:12px}
    .pc-small{font-size:12px;color:var(--muted)}
    .pc-diff{font-size:12px}
    /* Dumbbell chart rows */
    .pc-dmb{display:grid;grid-template-columns:auto 1fr auto;align-items:center;gap:10px;padding:8px 0;border-bottom:1px solid rgba(255,255,255,.06)}
    .pc-dmb:last-child{border-bottom:0}
    .pc-dmb-label{color:var(--muted);font-size:12px}
    .pc-dmb-track{position:relative;height:12px}
    .pc-dmb-line{position:absolute;left:0;right:0;top:50%;height:2px;transform:translateY(-50%);background:rgba(255,255,255,.15);border-radius:2px}
  .pc-dmb-seg{position:absolute;top:50%;height:3px;transform:translateY(-50%);background:linear-gradient(90deg, rgba(123,228,149,.6), rgba(255,139,139,.6));border-radius:3px}
    .pc-dmb-a,.pc-dmb-b{position:absolute;top:50%;transform:translate(-50%,-50%);width:10px;height:10px;border-radius:50%}
    .pc-dmb-a{background:#7be495;box-shadow:0 0 0 2px rgba(123,228,149,.25)}
    .pc-dmb-b{background:#ff8b8b;box-shadow:0 0 0 2px rgba(255,139,139,.25)}
    .pc-dmb-values{font-size:12px}
  .pc-dmb-dotLabel{position:absolute;top:0;transform:translate(-50%,-150%);font-size:10px;color:var(--muted)}
  .pc-dmb-min,.pc-dmb-max{position:absolute;top:100%;transform:translateY(2px);font-size:10px;color:var(--muted)}
  .pc-dmb-min{left:0}
  .pc-dmb-max{right:0}
  /* Info flyout */
  .pc-info{background:transparent;border:1px solid var(--border);color:var(--muted);width:18px;height:18px;border-radius:50%;font-size:11px;line-height:16px;text-align:center;cursor:pointer;margin-left:8px}
  .pc-info:hover{background:rgba(255,255,255,.06)}
  .pc-flyout{display:none;position:absolute;right:0;top:100%;margin-top:6px;max-width:320px;background:rgba(18,18,18,.98);border:1px solid var(--border);border-radius:10px;padding:10px;font-size:12px;color:#d5eaff;z-index:30;box-shadow:0 8px 24px rgba(0,0,0,.35)}
  .pc-flyout.open{display:block}
    `;
    const s = document.createElement('style'); s.id='pc-styles'; s.textContent = css; document.head.appendChild(s);
  }
  function createEl(tag, attrs = {}, children = []){
    const el = document.createElement(tag);
    Object.entries(attrs).forEach(([k,v]) => {
      if (k === 'class') el.className = v;
      else if (k === 'text') el.textContent = v;
      else el.setAttribute(k, v);
    });
    children.forEach(c => el.appendChild(typeof c === 'string' ? document.createTextNode(c) : c));
    return el;
  }

  function withInfo(titleEl, text){
    try{
      const btn = createEl('button', { class:'pc-info', title:'Info', text:'i' });
      const fly = createEl('div', { class:'pc-flyout' }, [ createEl('div', { text: text }) ]);
      // toggle
      btn.addEventListener('click', (e)=>{
        e.stopPropagation();
        fly.classList.toggle('open');
      });
      // close on outside click
      document.addEventListener('click', (e)=>{
        if(!fly.contains(e.target) && e.target!==btn) fly.classList.remove('open');
      });
      const wrap = createEl('div');
      // move existing title text into left span for spacing
      const left = createEl('span');
      while(titleEl.firstChild){ left.appendChild(titleEl.firstChild); }
      wrap.appendChild(left);
      wrap.appendChild(btn);
      titleEl.appendChild(wrap);
      titleEl.appendChild(fly);
    }catch(_e){}
  }

  function parseQS(){
    const p = new URLSearchParams(location.search);
    const getNum = (k) => (p.get(k) ? Number(p.get(k)) : null);
    const from = p.get('from') ? Number(p.get('from')) : null;
    const to = p.get('to') ? Number(p.get('to')) : null;
    return {
      playerA: getNum('pcA'),
      playerB: getNum('pcB'),
      side: p.get('side') || 'all',
      from, to
    };
  }
  function writeQS(state){
    const p = new URLSearchParams(location.search);
    if (state.playerA) p.set('pcA', String(state.playerA)); else p.delete('pcA');
    if (state.playerB) p.set('pcB', String(state.playerB)); else p.delete('pcB');
    if (state.side && state.side !== 'all') p.set('side', state.side); else p.delete('side');
    // Do not manage from/to here; host page controls the global time window
    p.delete('time'); p.delete('pcdbg');
    const url = location.pathname + '?' + p.toString() + location.hash;
    history.replaceState(null, '', url);
    return new URL(url, location.origin).toString();
  }

  function fmtPct(n){
    if (!isFinite(n)) return '-';
    return (n*100).toFixed(1) + '%';
  }
  function fmt(n){
    if (n == null || !isFinite(n)) return '-';
    return String(Math.round(n));
  }

  function median(arr){
    const a = (arr||[]).filter(x=> typeof x==='number' && isFinite(x)).sort((x,y)=>x-y);
    if(!a.length) return NaN; const m = Math.floor(a.length/2);
    return (a.length%2) ? a[m] : (a[m-1]+a[m])/2;
  }

  function heroName(heroes, id){
    const h = heroes && heroes[String(id)] || heroes && heroes[id];
    return h && (h.name || h.localized_name) || `Hero ${id}`;
  }

  // Key items definition per role (simple global list for now)
  const KEY_ITEMS = [
    // id or name fragments are not guaranteed; we'll match by purchase_log item string
    // Cores/Initiation/Defense
    'blink', 'black_king_bar', 'mekansm', 'pipe', 'guardian_greaves', 'glimmer_cape', 'force_staff',
    'lotus_orb', 'heavens_halberd', 'crimson_guard', 'dagger',
    // Carry/Timing spikes
    'manta', 'silver_edge', 'desolator', 'radiance', 'assault',
    // Utility/Control
    'cyclone', /* Eul's */ 'orchid', 'bloodthorn', 'rod_of_atos', 'spirit_vessel',
    // Defensive
    'sphere', /* Linken */ 'eternal_shroud', 'aeon_disk',
    // Vision
    'gem', 'aghanims_shard'
  ];

  // Minimal item metadata resolver (extendable). We will map common item keys to display names and optionally icons if available in docs assets.
  const ITEM_META = {
    blink: { name: 'Blink Dagger', icon: 'img/items/blink.png' },
    black_king_bar: { name: 'Black King Bar', icon: 'img/items/black_king_bar.png' },
    manta: { name: 'Manta Style', icon: 'img/items/manta.png' },
    silver_edge: { name: 'Silver Edge', icon: 'img/items/silver_edge.png' },
    desolator: { name: 'Desolator', icon: 'img/items/desolator.png' },
    radiance: { name: 'Radiance', icon: 'img/items/radiance.png' },
    assault: { name: 'Assault Cuirass', icon: 'img/items/assault.png' },
    mekansm: { name: 'Mekansm', icon: 'img/items/mekansm.png' },
    pipe: { name: 'Pipe of Insight', icon: 'img/items/pipe.png' },
    guardian_greaves: { name: 'Guardian Greaves', icon: 'img/items/guardian_greaves.png' },
    glimmer_cape: { name: 'Glimmer Cape', icon: 'img/items/glimmer_cape.png' },
    force_staff: { name: 'Force Staff', icon: 'img/items/force_staff.png' },
    lotus_orb: { name: 'Lotus Orb', icon: 'img/items/lotus_orb.png' },
    heavens_halberd: { name: 'Heaven\'s Halberd', icon: 'img/items/heavens_halberd.png' },
    crimson_guard: { name: 'Crimson Guard', icon: 'img/items/crimson_guard.png' },
    dagger: { name: 'Blink Dagger', icon: 'img/items/blink.png' },
    cyclone: { name: 'Eul\'s Scepter of Divinity', icon: 'img/items/cyclone.png' },
    orchid: { name: 'Orchid Malevolence', icon: 'img/items/orchid.png' },
    bloodthorn: { name: 'Bloodthorn', icon: 'img/items/bloodthorn.png' },
    rod_of_atos: { name: 'Rod of Atos', icon: 'img/items/rod_of_atos.png' },
    spirit_vessel: { name: 'Spirit Vessel', icon: 'img/items/spirit_vessel.png' },
    sphere: { name: 'Linken\'s Sphere', icon: 'img/items/sphere.png' },
    eternal_shroud: { name: 'Eternal Shroud', icon: 'img/items/eternal_shroud.png' },
    aeon_disk: { name: 'Aeon Disk', icon: 'img/items/aeon_disk.png' },
    gem: { name: 'Gem of True Sight', icon: 'img/items/gem.png' },
    aghanims_shard: { name: 'Aghanim\'s Shard', icon: 'img/items/aghanims_shard.png' },
  };
  function resolveItemMeta(key){
    const k = (key||'').toLowerCase().replace(/^item_/,'');
    const m = ITEM_META[k];
    const name = m?.name || k.replace(/_/g,' ');
    // Prefer CDN icon to ensure availability; alias some keys
    const canonical = (k==='dagger') ? 'blink' : k;
    const cdn = `https://cdn.cloudflare.steamstatic.com/apps/dota2/images/items/${canonical}_lg.png`;
    const icon = cdn;
    return { name, icon };
  }

  function extractItemTimes(entries){
    // entries: [{ match, player }], return Map(itemName -> [firstTimesSec])
    const map = new Map();
    for(const {player:p} of entries){
      const log = Array.isArray(p.purchase_log) ? p.purchase_log : [];
      const first = new Map();
      for(const ev of log){
        const it = (ev.key||ev.item||'').toLowerCase();
        const t = Number(ev.time);
        if(!it || !isFinite(t)) continue;
        if(!KEY_ITEMS.some(k=> it.includes(k))) continue;
        if(!first.has(it)) first.set(it, t);
      }
      for(const [it, t] of first.entries()){
        if(!map.has(it)) map.set(it, []);
        map.get(it).push(t);
      }
    }
    return map;
  }

  async function extractItemTimesAsync(entries, playerId){
    const map = new Map();
    for(const {match:m, player:p0} of entries){
      let p = p0;
      const hasLog = Array.isArray(p?.purchase_log) && p.purchase_log.length>0;
      if(!hasLog){
        try{
          const md = await fetchDetail(m.match_id||m.id);
          if(md && Array.isArray(md.players)){
            const found = md.players.find(pp => Number(pp.account_id)===playerId);
            if(found) p = found;
          }
        }catch(_e){}
      }
      const log = Array.isArray(p?.purchase_log) ? p.purchase_log : [];
      const first = new Map();
      for(const ev of log){
        const it = (ev.key||ev.item||'').toLowerCase();
        const t = Number(ev.time);
        if(!it || !isFinite(t)) continue;
        if(!KEY_ITEMS.some(k=> it.includes(k))) continue;
        if(!first.has(it)) first.set(it, t);
      }
      for(const [it, t] of first.entries()){
        if(!map.has(it)) map.set(it, []);
        map.get(it).push(t);
      }
    }
    return map;
  }

  function secondsToMin(t){ if(!isFinite(t)) return '-'; const m=Math.floor(t/60), s=Math.floor(t%60); return `${m}:${String(s).padStart(2,'0')}`; }

  function isRadiantFlag(p){
    if (p == null) return null;
    if (p.isRadiant !== undefined) return !!p.isRadiant;
    if (p.is_radiant !== undefined) return !!p.is_radiant;
    if (p.player_slot !== undefined && p.player_slot !== null){
      const slot = Number(p.player_slot);
      if (!isNaN(slot)) return slot < 128;
    }
    return null;
  }

  function getPlayerEntries(matches, playerId, filters, timeWindow, dbg){
    const out = [];
    if (dbg){ dbg.withPlayer=0; dbg.included=0; dbg.sideFiltered=0; dbg.timeFiltered=0; dbg.missingPlayer=0; dbg.samples={include:[], side:[], time:[]}; }
    for(const m of matches||[]){
      const p = (m.players||[]).find(p => Number(p.account_id)===playerId);
      if (!p){ if(dbg) dbg.missingPlayer++; continue; }
      if (dbg) dbg.withPlayer++;

      // Side filter (only when player present)
      if (filters.side !== 'all'){
        const isRad = isRadiantFlag(p)===true;
        if ((filters.side==='radiant' && !isRad) || (filters.side==='dire' && isRad)){
          if (dbg){ dbg.sideFiltered++; if(dbg.samples.side.length<5) dbg.samples.side.push(m.match_id||m.id||''); }
          continue;
        }
      }

      // Time filter
      if (timeWindow){
        let st = Number(m.start_time);
        if (!isFinite(st)){
          const d = Date.parse(m.start_time);
          st = isNaN(d) ? null : Math.floor(d/1000);
        }
        if (st != null && st > 1e12) st = Math.floor(st/1000); // normalize ms -> s if needed
        if (st != null) {
          if (isFinite(timeWindow.from) && st < timeWindow.from){ if(dbg){ dbg.timeFiltered++; if(dbg.samples.time.length<5) dbg.samples.time.push(m.match_id||m.id||'<' ); } continue; }
          if (isFinite(timeWindow.to) && st > timeWindow.to){ if(dbg){ dbg.timeFiltered++; if(dbg.samples.time.length<5) dbg.samples.time.push(m.match_id||m.id||'>'); } continue; }
        }
      }

      out.push({ match:m, player:p });
      if (dbg){ dbg.included++; if(dbg.samples.include.length<5) dbg.samples.include.push(m.match_id||m.id||''); }
    }
    return out;
  }

  function computeHeroStats(matches, playerId, filters, timeWindow){
    if(!playerId) return { total:0, heroes:new Map(), wins:new Map() };
    const entries = getPlayerEntries(matches, playerId, filters, timeWindow);
    const heroes = new Map();
    const wins = new Map();
    for(const {match:m, player:p} of entries){
      const hid = Number(p.hero_id||0); if(!(hid>0)) continue;
      heroes.set(hid, (heroes.get(hid)||0)+1);
      const radWin=!!m.radiant_win; const won = (p.is_radiant||p.isRadiant) ? radWin : !radWin;
      wins.set(hid, (wins.get(hid)||0) + (won?1:0));
    }
    return { total: entries.length, heroes, wins };
  }

  function computeLaning(metrics){
    // metrics: array of per-match objects { lh10?, net10?, xp10? }
    const lh = [], net = [], xp = [];
    for(const m of metrics){ if(isFinite(m.lh10)) lh.push(m.lh10); if(isFinite(m.net10)) net.push(m.net10); if(isFinite(m.xp10)) xp.push(m.xp10); }
    return { lh10: median(lh), net10: median(net), xp10: median(xp), samples: { lh: lh.length, net: net.length, xp: xp.length } };
  }

  function extractLaningPerMatch(entry){
    const p = entry.player;
    const at = (arr, idx) => Array.isArray(arr) && arr.length>idx ? Number(arr[idx]) : NaN;
    // Try common OpenDota arrays; fall back to null if absent
    const lh10 = isFinite(at(p.lh_t,10)) ? at(p.lh_t,10) : isFinite(at(p.last_hits_t,10)) ? at(p.last_hits_t,10) : NaN;
    const net10 = isFinite(at(p.net_worth_t,10)) ? at(p.net_worth_t,10) : isFinite(at(p.gold_t,10)) ? at(p.gold_t,10) : NaN;
    const xp10 = isFinite(at(p.xp_t,10)) ? at(p.xp_t,10) : NaN;
    return { lh10, net10, xp10 };
  }

  async function extractLaningMetricsAsync(entries, playerId){
    const out = [];
    const at = (arr, idx) => Array.isArray(arr) && arr.length>idx ? Number(arr[idx]) : NaN;
    for(const {match:m, player:p0} of entries){
      let p = p0;
      const have = (q)=> isFinite(at(q,10));
      const hasAny = have(p?.lh_t)||have(p?.last_hits_t)||have(p?.net_worth_t)||have(p?.gold_t)||have(p?.xp_t);
      if(!hasAny){
        try{
          const md = await fetchDetail(m.match_id||m.id);
          if(md && Array.isArray(md.players)){
            const found = md.players.find(pp => Number(pp.account_id)===playerId);
            if(found) p = found;
          }
        }catch(_e){}
      }
      const lh10 = isFinite(at(p?.lh_t,10)) ? at(p.lh_t,10) : isFinite(at(p?.last_hits_t,10)) ? at(p.last_hits_t,10) : NaN;
      const net10 = isFinite(at(p?.net_worth_t,10)) ? at(p.net_worth_t,10) : isFinite(at(p?.gold_t,10)) ? at(p.gold_t,10) : NaN;
      const xp10 = isFinite(at(p?.xp_t,10)) ? at(p.xp_t,10) : NaN;
      out.push({ lh10, net10, xp10 });
    }
    return out;
  }

  function computeCoreAggregates(matches, playerId, filters, timeWindow){
    // filters: { time, side }
    if (!playerId) return null;
    const entries = getPlayerEntries(matches, playerId, filters, timeWindow);
    let g=0, wins=0, k=0, d=0, a=0, gpm=0, xpm=0, lh=0, dn=0, hdmg=0, tdmg=0;
    for (const {match:m, player:p} of entries){
      g++;
      const pr = isRadiantFlag(p);
      const playerIsRad = pr===null ? false : pr;
      const won = (playerIsRad && !!m.radiant_win) || (!playerIsRad && !m.radiant_win);
      if (won) wins++;
      k += p.kills||0; d += p.deaths||0; a += p.assists||0;
      gpm += p.gold_per_min||0; xpm += p.xp_per_min||0;
      lh += p.last_hits||0; dn += p.denies||0;
      hdmg += p.hero_damage||0; tdmg += p.tower_damage||0;
    }
    if (g===0) return { games:0 };
    return {
      games: g,
      wr: wins/g,
      k: k/g, d: d/g, a: a/g,
      gpm: gpm/g, xpm: xpm/g,
      lh: lh/g, dn: dn/g, hdmg: hdmg/g, tdmg: tdmg/g,
      kda: (k+a)/Math.max(1, d)
    };
  }

  // --- Detail fallback loader (cache) ---
  const __detailCache = new Map();
  async function fetchDetail(mid){
    try{ const key = Number(mid)||0; if(key>0 && __detailCache.has(key)) return __detailCache.get(key); }catch(_e){}
    const paths = (function(){
      const list = [];
      // relative to current doc
      list.push(`data/cache/OpenDota/matches/${mid}.json`);
      list.push(`../data/cache/OpenDota/matches/${mid}.json`);
      list.push(`../../data/cache/OpenDota/matches/${mid}.json`);
      // absolute from site root
      try{ list.push(`${new URL(`/data/cache/OpenDota/matches/${mid}.json`, location.origin).toString()}`); }catch(_e){}
      // absolute anchored at repo root before /docs/
      try{
        const p = location.pathname||'';
        const i = p.indexOf('/docs/');
        if(i>=0){
          const root = location.origin + p.slice(0, i+1);
          list.push(root + `data/cache/OpenDota/matches/${mid}.json`);
        }
      }catch(_e){}
      return list;
    })();
    async function tryLoad(url){ try{ const r=await fetch(url,{cache:'force-cache'}); if(r && r.ok){ return await r.json(); } }catch(_e){} return null; }
    let md = null;
    for(const u of paths){ md = await tryLoad(u); if(md) break; }
    if(!md){ try{ const api = await tryLoad(`https://api.opendota.com/api/matches/${mid}`); md = api||null; }catch(_e){}
    }
    if(!md) md = null;
    try{ const key = Number(mid)||0; if(key>0) __detailCache.set(key, md); }catch(_e){}
    return md;
  }

  async function computeCoreAggregatesAsync(matches, playerId, filters, timeWindow){
    if (!playerId) return null;
    const entries = getPlayerEntries(matches, playerId, filters, timeWindow);
    let g=0, wins=0, k=0, d=0, a=0, gpm=0, xpm=0, lh=0, dn=0, hdmg=0, tdmg=0;
    for(const {match:m, player:p0} of entries){
      let p = p0;
      // If basic fields are missing, pull detailed file
      const needsDetail = !(p && (Number.isFinite(p.kills) || Number.isFinite(p.gold_per_min) || Number.isFinite(p.xp_per_min)));
      if(needsDetail){
        try{
          const md = await fetchDetail(m.match_id||m.id);
          if(md && Array.isArray(md.players)){
            const found = md.players.find(pp => Number(pp.account_id)===playerId);
            if(found) p = found;
          }
          // also prefer md.radiant_win if present
          if(md && typeof md.radiant_win === 'boolean') m = { ...m, radiant_win: !!md.radiant_win };
        }catch(_e){}
      }
      if(!p) continue;
      g++;
      const pr = isRadiantFlag(p);
      const playerIsRad = pr===null ? false : pr;
      const won = (playerIsRad && !!m.radiant_win) || (!playerIsRad && !m.radiant_win);
      if (won) wins++;
      k += Number(p.kills||0); d += Number(p.deaths||0); a += Number(p.assists||0);
      gpm += Number(p.gold_per_min||0); xpm += Number(p.xp_per_min||0);
      lh += Number(p.last_hits||0); dn += Number(p.denies||0);
      hdmg += Number(p.hero_damage||0); tdmg += Number(p.tower_damage||0);
    }
    if (g===0) return { games:0 };
    return { games:g, wr: wins/g, k:k/g, d:d/g, a:a/g, gpm:gpm/g, xpm:xpm/g, lh: lh/g, dn: dn/g, hdmg: hdmg/g, tdmg: tdmg/g, kda: (k+a)/Math.max(1,d) };
  }

  function playersToOptions(playersIndex){
    const opts = [{ value: '', label: '— Player —' }];
    (playersIndex||[]).forEach(p => {
      const name = p.name || ('ID ' + p.account_id);
      opts.push({ value: String(p.account_id), label: name });
    });
    return opts;
  }

  function optionExists(selectEl, value){
    return Array.from(selectEl.options).some(o => o.value === String(value));
  }

  function appendFallbackOption(selectEl, value, label){
    const opt = document.createElement('option');
    opt.value = String(value);
    opt.text = label || ('ID ' + value);
    selectEl.appendChild(opt);
  }

  function mount(container, options){
    ensureStyles();
    // hydrate from URL, then localStorage fallback
    const ls = (()=>{ try{ return JSON.parse(localStorage.getItem('pc_state')||'{}'); }catch(_e){ return {}; } })();
  const state = Object.assign({ playerA:null, playerB:null, side:'all', from:null, to:null }, parseQS(), ls);
    const data = options?.data||{};
    const playersIndex = data.playersIndex||[];
    const heroes = data.heroes||{};

    const wrapper = createEl('div', { class: 'pc-wrap' });

    // Controls
    const controls = createEl('div', { class: 'pc-controls' });

    const selA = createEl('select', { class: 'pc-selectA' });
    const selB = createEl('select', { class: 'pc-selectB' });
    const sideSel = createEl('select', { class: 'pc-side' });
    const copyBtn = createEl('button', { class: 'pc-copy', text: 'Copy link' });

  playersToOptions(playersIndex).forEach(o => selA.appendChild(createEl('option', { value:o.value, text:o.label })));
  playersToOptions(playersIndex).forEach(o => selB.appendChild(createEl('option', { value:o.value, text:o.label })));

    ;[
      {v:'all', l:'Both'},
      {v:'radiant', l:'Radiant'},
      {v:'dire', l:'Dire'}
    ].forEach(o => sideSel.appendChild(createEl('option', { value:o.v, text:o.l })));

    controls.appendChild(createEl('label', { text: 'Player A' }));
    controls.appendChild(selA);
    controls.appendChild(createEl('label', { text: 'Player B' }));
    controls.appendChild(selB);
    controls.appendChild(createEl('label', { text: 'Side' }));
    controls.appendChild(sideSel);
    controls.appendChild(copyBtn);

    // Summary area
  const summary = createEl('div', { class: 'pc-summary' });
  const colA = createEl('div', { class: 'pc-col pc-col-a' });
  const colB = createEl('div', { class: 'pc-col pc-col-b' });
  // full-width area below the columns for comparative sections
  const fullWidth = createEl('div', { class:'pc-full' });
    summary.appendChild(colA);
    summary.appendChild(colB);

  wrapper.appendChild(controls);
  wrapper.appendChild(summary);
  wrapper.appendChild(fullWidth);
    container.innerHTML = '';
    container.appendChild(wrapper);

  // hydrate from state (ensure options exist for URL-provided players)
  if (state.playerA && !optionExists(selA, state.playerA)) appendFallbackOption(selA, state.playerA, 'ID '+state.playerA);
  if (state.playerB && !optionExists(selB, state.playerB)) appendFallbackOption(selB, state.playerB, 'ID '+state.playerB);
  if (state.playerA) selA.value = String(state.playerA);
  if (state.playerB) selB.value = String(state.playerB);
    sideSel.value = state.side;

    async function computeTimeWindow(){
      // If the host page provides an external range, prefer it
      try{
        if(options && options.useExternalRange && window.__dvRangeUnix && isFinite(window.__dvRangeUnix.from)){
          const from = Number(window.__dvRangeUnix.from)||0;
          const toRaw = Number(window.__dvRangeUnix.to);
          const to = isFinite(toRaw) && toRaw>0 ? toRaw : Infinity;
          return { from, to };
        }
      }catch(_e){}
      // Fallback: explicit from/to in URL, else unbounded
      const fHas = isFinite(state.from);
      const tHas = isFinite(state.to);
      if (fHas || tHas){
        let from = fHas ? Number(state.from) : 0;
        let to = tHas ? Number(state.to) : Infinity;
        // Treat to=0 as unbounded
        if (!isFinite(to) || to <= 0) to = Infinity;
        // If from and to are inverted, widen window
        if (isFinite(from) && isFinite(to) && from > to) { to = Infinity; }
        return { from, to };
      }
      return { from: 0, to: Infinity };
    }

  async function render(){
      colA.innerHTML = '';
      colB.innerHTML = '';
      fullWidth.innerHTML = '';
  const filters = { side: sideSel.value };
      const aId = selA.value ? Number(selA.value) : null;
      const bId = selB.value ? Number(selB.value) : null;
      const timeWindow = await computeTimeWindow();

  const aggA = computeCoreAggregates(data.matches||[], aId, filters, timeWindow);
  const aggB = computeCoreAggregates(data.matches||[], bId, filters, timeWindow);

      // Debug panel removed per request

      const makeCard = (title, items, infoText=null) => {
        const card = createEl('div', { class: 'pc-card' });
        const t = createEl('div', { class: 'pc-card-title', text: title });
        card.appendChild(t);
        if(infoText) withInfo(t, infoText);
        const list = createEl('ul', { class: 'pc-card-list' });
        items.forEach(i => list.appendChild(createEl('li', { text: i })));
        card.appendChild(list);
        return card;
      };
      const makeRowCard = (title, rows, infoText=null) => {
        const card = createEl('div', { class: 'pc-card' });
        const t = createEl('div', { class: 'pc-card-title', text: title });
        card.appendChild(t);
        if(infoText) withInfo(t, infoText);
        rows.forEach(r => card.appendChild(r));
        return card;
      };
      const barCompare = (label, aVal, bVal, fmtFn=(x)=>String(x), max=null) => {
        const row = createEl('div', { class: 'pc-row' });
        row.appendChild(createEl('div', { class:'sub', text: label }));
        const box = createEl('div', { style:'flex:1;display:flex;flex-direction:column;gap:4px;align-items:stretch' });
        const top = createEl('div', { class:'pc-row' }, [
          createEl('span', { class:'pc-badge', text: `A ${fmtFn(aVal)}` }),
          createEl('span', { class:'pc-badge', text: `B ${fmtFn(bVal)}` }),
        ]);
        const bar = createEl('div', { class:'pc-bar dual' });
        const safe = (n)=> !isFinite(n) || n<0 ? 0 : n;
        const base = Math.max(safe(aVal), safe(bVal), 1);
        const m = max!=null? max : base * 1.1;
        const aW = Math.round(50 * safe(aVal)/m);
        const bW = Math.round(50 * safe(bVal)/m);
        const mid = createEl('span', { class:'mid' });
        const aSpan = createEl('span', { class:'bA', style:`width:${aW}%;left:${50 - aW}%;` });
        const bSpan = createEl('span', { class:'bB', style:`width:${bW}%;right:${50 - bW}%;` });
        bar.appendChild(aSpan); bar.appendChild(mid); bar.appendChild(bSpan);
        box.appendChild(top); box.appendChild(bar);
        row.appendChild(box);
        return row;
      };

      // Dumbbell row helper: label | track (A to B) | values (A vs B, delta)
      const dumbbellRow = (label, aVal, bVal, max=null, fmtFn=(x)=>String(x))=>{
        const safe = (n)=> (isFinite(n)? n : 0);
        const base = Math.max(safe(aVal), safe(bVal), 1);
        const m = max!=null? max : base * 1.1;
        const pct = (v)=> 100 * (safe(v)/m);
        const row = createEl('div', { class:'pc-dmb' });
        row.appendChild(createEl('div', { class:'pc-dmb-label', text: label }));
        const track = createEl('div', { class:'pc-dmb-track' });
        const line = createEl('div', { class:'pc-dmb-line' });
        const aPct = pct(aVal), bPct = pct(bVal);
        const segL = Math.min(aPct, bPct), segR = Math.max(aPct, bPct);
        const seg = createEl('div', { class:'pc-dmb-seg', style:`left:${segL}%;width:${Math.max(0, segR - segL)}%` });
  const a = createEl('div', { class:'pc-dmb-a', style:`left:${aPct}%` });
  const b = createEl('div', { class:'pc-dmb-b', style:`left:${bPct}%` });
  const aLbl = createEl('div', { class:'pc-dmb-dotLabel', style:`left:${aPct}%`, text:'A' });
  const bLbl = createEl('div', { class:'pc-dmb-dotLabel', style:`left:${bPct}%`, text:'B' });
  const minLbl = createEl('div', { class:'pc-dmb-min', text:'0' });
  const maxLbl = createEl('div', { class:'pc-dmb-max', text: String(Math.round(m)) });
  track.appendChild(line); track.appendChild(seg); track.appendChild(a); track.appendChild(b); track.appendChild(aLbl); track.appendChild(bLbl); track.appendChild(minLbl); track.appendChild(maxLbl);
        row.appendChild(track);
        const d = safe(aVal) - safe(bVal);
        const deltaTxt = d>0? `A +${fmt(Math.abs(d))}` : d<0? `B +${fmt(Math.abs(d))}` : 'Even';
        const values = createEl('div', { class:'pc-dmb-values' }, [
          createEl('span', { class:'pc-badge', text:`A ${fmtFn(aVal)}` }),
          createEl('span', { class:'pc-badge', style:'margin-left:6px', text:`B ${fmtFn(bVal)}` }),
          createEl('span', { class:'pc-diff ' + (d>0?'pc-delta pos':d<0?'pc-delta neg':''), style:'margin-left:8px', text: deltaTxt })
        ]);
        row.appendChild(values);
        return row;
      };

  const itemsA = [];
      if (!aggA || aggA.games===0) itemsA.push('No games in range');
      else {
        itemsA.push(`Games: ${aggA.games}`);
        itemsA.push(`WR: ${fmtPct(aggA.wr)}`);
        itemsA.push(`K/D/A: ${fmt(aggA.k)}/${fmt(aggA.d)}/${fmt(aggA.a)}`);
        itemsA.push(`GPM/XPM: ${fmt(aggA.gpm)}/${fmt(aggA.xpm)}`);
      }
  colA.appendChild(makeCard('Summary A 🧑', itemsA, 'Averages across matches in range for Player A after side/time filters.'));

  const itemsB = [];
      if (!aggB || aggB.games===0) itemsB.push('No games in range');
      else {
        itemsB.push(`Games: ${aggB.games}`);
        itemsB.push(`WR: ${fmtPct(aggB.wr)}`);
        itemsB.push(`K/D/A: ${fmt(aggB.k)}/${fmt(aggB.d)}/${fmt(aggB.a)}`);
        itemsB.push(`GPM/XPM: ${fmt(aggB.gpm)}/${fmt(aggB.xpm)}`);
      }
  colB.appendChild(makeCard('Summary B 🧑', itemsB, 'Averages across matches in range for Player B after side/time filters.'));

  // Quick compare bars (WR, GPM, XPM)
      const renderBars = (aVals, bVals) => {
        const rows = [];
        {
          const r = barCompare('Winrate', aVals.wr*100, bVals.wr*100, n=>isFinite(n)? n.toFixed(1)+'%':'-');
          r.title = `Winrate across games in range. Samples — A: ${aVals.games}, B: ${bVals.games}.`;
          rows.push(r);
        }
        {
          const r = barCompare('GPM', aVals.gpm, bVals.gpm, n=>fmt(n));
          r.title = `Average Gold per Minute (per match average). Samples — A: ${aVals.games}, B: ${bVals.games}.`;
          rows.push(r);
        }
        {
          const r = barCompare('XPM', aVals.xpm, bVals.xpm, n=>fmt(n));
          r.title = `Average XP per Minute (per match average). Samples — A: ${aVals.games}, B: ${bVals.games}.`;
          rows.push(r);
        }
        const card = makeRowCard('Head-to-head 📊', rows);
        card.setAttribute('data-h2h','1');
        return card;
      };
      function makeH2HCard(aVals, bVals){
        const card = createEl('div', { class:'pc-card', 'data-h2h':'1' });
        const t = createEl('div', { class:'pc-card-title', text:'Head-to-head 📊' });
        card.appendChild(t);
        withInfo(t, 'Direct comparison of per-match averages and rates between Player A and B using included matches.');
        const add = (label, a, b, fmtF=fmt)=> card.appendChild(barCompare(label, a, b, fmtF));
        add('Winrate', aVals.wr*100, bVals.wr*100, n=>isFinite(n)? n.toFixed(1)+'%':'-');
        add('KDA', aVals.kda, bVals.kda, n=> isFinite(n)? n.toFixed(2) : '-');
        add('GPM', aVals.gpm, bVals.gpm);
        add('XPM', aVals.xpm, bVals.xpm);
        add('Last Hits', aVals.lh, bVals.lh);
        add('Denies', aVals.dn, bVals.dn);
        add('Hero Damage', aVals.hdmg, bVals.hdmg);
        add('Tower Damage', aVals.tdmg, bVals.tdmg);
        return card;
      }
      if(aggA && aggB && aggA.games>0 && aggB.games>0){
        fullWidth.appendChild(makeH2HCard(aggA, aggB));
      }

      // Hero pool overlap
  const hsA = computeHeroStats(data.matches||[], aId, filters, timeWindow);
  const hsB = computeHeroStats(data.matches||[], bId, filters, timeWindow);
      const listTop = (hs)=>{
        const ul = createEl('ul', { class:'pc-hero-list' });
        Array.from(hs.heroes.entries())
          .sort((x,y)=> y[1]-x[1])
          .slice(0,10)
          .forEach(([hid,c])=>{
            const wr = (hs.wins.get(hid)||0) / c;
            const li = createEl('li');
            const h = heroes && (heroes[String(hid)]||heroes[hid]) || {};
            const img = createEl('img', { class:'pc-hero-icon', src: h.icon || h.img || '', alt: h.name||('Hero '+hid) });
            const left = createEl('div', { style:'display:flex;align-items:center;gap:8px' }, [img, createEl('span', { text: h.name || heroName(heroes,hid) })]);
            const right = createEl('div', { class:'sub', text: `${c}g · ${fmtPct(wr)}` });
            li.appendChild(left); li.appendChild(right); ul.appendChild(li);
          });
        return ul;
      };
      const overlap = (()=>{
        const setA = new Set(Array.from(hsA.heroes.keys()));
        const common = Array.from(hsB.heroes.keys()).filter(h=> setA.has(h));
        const ul = createEl('ul', { class:'pc-hero-list' });
        common.sort((h1,h2)=> (hsA.heroes.get(h2)+hsB.heroes.get(h2)) - (hsA.heroes.get(h1)+hsB.heroes.get(h1))).slice(0,10)
          .forEach(hid=>{
            const aCnt = hsA.heroes.get(hid)||0, bCnt = hsB.heroes.get(hid)||0;
            const aWr = aCnt? (hsA.wins.get(hid)||0)/aCnt : NaN;
            const bWr = bCnt? (hsB.wins.get(hid)||0)/bCnt : NaN;
            const h = heroes && (heroes[String(hid)]||heroes[hid]) || {};
            const img = createEl('img', { class:'pc-hero-icon', src: h.icon || h.img || '', alt: h.name||('Hero '+hid) });
            const left = createEl('div', { style:'display:flex;align-items:center;gap:8px' }, [img, createEl('span', { text: h.name || heroName(heroes,hid) })]);
            const right = createEl('div', { class:'sub', text: `A:${aCnt}/${fmtPct(aWr)} · B:${bCnt}/${fmtPct(bWr)}` });
            const li = createEl('li'); li.appendChild(left); li.appendChild(right); ul.appendChild(li);
          });
        if(!ul.childNodes.length){ ul.appendChild(createEl('li', { text:'No overlap' })); }
        return ul;
      })();
      const poolWrap = createEl('div', { class: 'pc-pools' });
      const poolA = createEl('div', { class:'pc-card' });
  { const t = createEl('div', { class:'pc-card-title', text:'Hero Pool A (top 10) 🛡️' }); poolA.appendChild(t); withInfo(t, 'Most played heroes for Player A within filters; counts and win rates show usage and success.'); }
      poolA.appendChild(listTop(hsA));
  const poolO = createEl('div', { class:'pc-card' });
  { const t = createEl('div', { class:'pc-card-title', text:'Overlap (top 10) 🔁' }); poolO.appendChild(t); withInfo(t, 'Heroes both players fielded; helps compare on shared comfort picks.'); }
      poolO.appendChild(overlap);
  const poolB = createEl('div', { class:'pc-card' });
  { const t = createEl('div', { class:'pc-card-title', text:'Hero Pool B (top 10) 🗡️' }); poolB.appendChild(t); withInfo(t, 'Most played heroes for Player B within filters; counts and win rates show usage and success.'); }
      poolB.appendChild(listTop(hsB));
  poolWrap.appendChild(poolA); poolWrap.appendChild(poolO); poolWrap.appendChild(poolB);
  fullWidth.appendChild(poolWrap);

      // Unique picks removed to avoid redundancy

      // Laning diff (median @10: LH/Net/XP) if data available
  const aEntries = getPlayerEntries(data.matches||[], aId, filters, timeWindow).map(extractLaningPerMatch);
  const bEntries = getPlayerEntries(data.matches||[], bId, filters, timeWindow).map(extractLaningPerMatch);
      const lanA = computeLaning(aEntries);
      const lanB = computeLaning(bEntries);
      const fmtLan = (la, lb, key, label)=>{
        const va = la[key], vb = lb[key];
        if(!isFinite(va) || !isFinite(vb)) return `${label}: n/a`;
        const d = Math.round((va - vb));
        const s = d>0? `A +${d}` : d<0? `B +${Math.abs(d)}` : 'Even';
        return `${label}: A ${fmt(va)} vs B ${fmt(vb)} · ${s}`;
      };
      const lanRows = [];
      const maxLanBase = Math.max(
        isFinite(lanA.lh10)&&isFinite(lanB.lh10) ? Math.max(lanA.lh10, lanB.lh10) : 0,
        isFinite(lanA.net10)&&isFinite(lanB.net10) ? Math.max(lanA.net10, lanB.net10) : 0,
        isFinite(lanA.xp10)&&isFinite(lanB.xp10) ? Math.max(lanA.xp10, lanB.xp10) : 0,
        1
      );
      const maxLan = maxLanBase * 1.1;
      const maxLH = (isFinite(lanA.lh10) && isFinite(lanB.lh10)) ? 2 * Math.max(lanA.lh10, lanB.lh10) : maxLan;
      if(isFinite(lanA.lh10) && isFinite(lanB.lh10)) lanRows.push(dumbbellRow('LH@10', lanA.lh10, lanB.lh10, maxLH, fmt));
      if(isFinite(lanA.net10) && isFinite(lanB.net10)) lanRows.push(dumbbellRow('Net@10', lanA.net10, lanB.net10, maxLan, fmt));
      if(isFinite(lanA.xp10) && isFinite(lanB.xp10)) lanRows.push(dumbbellRow('XP@10', lanA.xp10, lanB.xp10, maxLan, fmt));
  const lanCard = lanRows.length? (function(){ const c=createEl('div', { class:'pc-card' }); const t=createEl('div', { class:'pc-card-title', text:'Laning diff (median) 🕙' }); c.appendChild(t); withInfo(t, 'Median values at 10: last hits, net worth, XP. Requires parsed data; falls back to details when missing.'); const w=createEl('div', { class:'pc-split' }); lanRows.forEach(r=>w.appendChild(r)); c.appendChild(w); return c; })() : makeCard('Laning diff (median) 🕙', ['n/a'], 'Median @10 from parsed arrays; when absent, we fetch detail files.');
      lanCard.setAttribute('data-laning','1');
      if(lanRows.length){
        const totalA = getPlayerEntries(data.matches||[], aId, filters, timeWindow).length;
        const totalB = getPlayerEntries(data.matches||[], bId, filters, timeWindow).length;
        const parsedA = Math.max(lanA.samples.lh, lanA.samples.net, lanA.samples.xp);
        const parsedB = Math.max(lanB.samples.lh, lanB.samples.net, lanB.samples.xp);
        const note = createEl('div', { class:'pc-note', text:`Parsed data availability — A: ${parsedA}/${totalA}, B: ${parsedB}/${totalB}` });
        lanCard.appendChild(note);
      }
      fullWidth.appendChild(lanCard);

      // If laning is empty, try async detail-backed laning metrics and update card
      if(lanRows.length===0 && (aId||bId)){
        Promise.all([
          extractLaningMetricsAsync(getPlayerEntries(data.matches||[], aId, filters, timeWindow), aId),
          extractLaningMetricsAsync(getPlayerEntries(data.matches||[], bId, filters, timeWindow), bId)
        ]).then(([LA, LB])=>{
          const la = computeLaning(LA||[]);
          const lb = computeLaning(LB||[]);
          const rows = [];
          const mBase = Math.max(
            isFinite(la.lh10)&&isFinite(lb.lh10) ? Math.max(la.lh10, lb.lh10) : 0,
            isFinite(la.net10)&&isFinite(lb.net10) ? Math.max(la.net10, lb.net10) : 0,
            isFinite(la.xp10)&&isFinite(lb.xp10) ? Math.max(la.xp10, lb.xp10) : 0,
            1
          );
          const m = mBase * 1.1;
          const mLH = (isFinite(la.lh10) && isFinite(lb.lh10)) ? 2 * Math.max(la.lh10, lb.lh10) : m;
          if(isFinite(la.lh10) && isFinite(lb.lh10)) rows.push(dumbbellRow('LH@10', la.lh10, lb.lh10, mLH, fmt));
          if(isFinite(la.net10) && isFinite(lb.net10)) rows.push(dumbbellRow('Net@10', la.net10, lb.net10, m, fmt));
          if(isFinite(la.xp10) && isFinite(lb.xp10)) rows.push(dumbbellRow('XP@10', la.xp10, lb.xp10, m, fmt));
          const newCard = rows.length? (function(){ const c=createEl('div', { class:'pc-card' }); const t=createEl('div', { class:'pc-card-title', text:'Laning diff (median) 🕙' }); c.appendChild(t); withInfo(t, 'Median values at 10 using detail-backed arrays if needed.'); const w=createEl('div', { class:'pc-split' }); rows.forEach(r=>w.appendChild(r)); c.appendChild(w); return c; })() : makeCard('Laning diff (median) 🕙', ['n/a'], 'Median @10 from parsed arrays; when absent, we fetch detail files.');
          newCard.setAttribute('data-laning','1');
          if(rows.length){
            const totalA = getPlayerEntries(data.matches||[], aId, filters, timeWindow).length;
            const totalB = getPlayerEntries(data.matches||[], bId, filters, timeWindow).length;
            const parsedA = Math.max(la.samples.lh, la.samples.net, la.samples.xp);
            const parsedB = Math.max(lb.samples.lh, lb.samples.net, lb.samples.xp);
            const note = createEl('div', { class:'pc-note', text:`Parsed data availability — A: ${parsedA}/${totalA}, B: ${parsedB}/${totalB}` });
            newCard.appendChild(note);
          }
          const old = fullWidth.querySelector('[data-laning="1"]');
          if(old) old.replaceWith(newCard); else fullWidth.appendChild(newCard);
        }).catch(()=>{});
      }

  // Item timings
  const itemEntriesA = getPlayerEntries(data.matches||[], aId, filters, timeWindow);
  const itemEntriesB = getPlayerEntries(data.matches||[], bId, filters, timeWindow);
  const aItems = extractItemTimes(itemEntriesA);
  const bItems = extractItemTimes(itemEntriesB);
      const renderItemsCard = (mapA, mapB) => {
        // Render as time list: centered item (icon+name), sides show A/B times with +/- for slower/faster
        const keys = new Set([ ...Array.from(mapA.keys()), ...Array.from(mapB.keys()) ]);
        const items = [];
        for(const k of keys){
          const arrA = mapA.get(k)||[];
          const arrB = mapB.get(k)||[];
          const medA = median(arrA);
          const medB = median(arrB);
          if(!isFinite(medA) && !isFinite(medB)) continue;
          const minMed = Math.min(isFinite(medA)?medA:Infinity, isFinite(medB)?medB:Infinity);
          items.push({ k, arrA, arrB, medA, medB, minMed });
        }
        items.sort((x,y)=> x.minMed - y.minMed);
        const listRows = [];
        const signFor = (val, other)=>{
          if(isFinite(val) && isFinite(other)){
            if(val < other) return { sign:'-', cls:'fast' };
            if(val > other) return { sign:'+', cls:'slow' };
            return { sign:'±', cls:'even' };
          }
          return { sign:'', cls:'' };
        };
        for(const it of items){
          const { k, arrA, arrB, medA, medB } = it;
          const { name, icon } = resolveItemMeta(k);
          const row = createEl('div', { class:'pc-item-row three' });
          const left = createEl('div', { class:'pc-side a' });
          const la = signFor(medA, medB);
          left.appendChild(createEl('span', { class:`pc-badge ${la.cls}`, title:`A samples: ${arrA.length}`, text:`${la.sign} ${secondsToMin(medA)}` }));
          const mid = createEl('div', { class:'pc-item-mid' });
          if(icon){
            const img = createEl('img', { class:'pc-item-icon', src: icon, alt: name });
            img.onerror = ()=>{ try{ img.remove(); }catch(_e){} };
            mid.appendChild(img);
          }
          mid.appendChild(createEl('span', { text: name }));
          const right = createEl('div', { class:'pc-side b' });
          const lb = signFor(medB, medA);
          right.appendChild(createEl('span', { class:`pc-badge ${lb.cls}`, title:`B samples: ${arrB.length}`, text:`${lb.sign} ${secondsToMin(medB)}` }));
          row.appendChild(left); row.appendChild(mid); row.appendChild(right);
          listRows.push(row);
        }
        let card;
        if(listRows.length){
          card = createEl('div', { class:'pc-card' });
          card.appendChild(createEl('div', { class:'pc-card-title', text:'Key item timings ⏱️ (median first purchase)' }));
          listRows.forEach(r=> card.appendChild(r));
        } else {
          // Fallback: top observed items (name only) if truly nothing
          const freq = [];
          const pushFreq = (map) => { for(const [kk, arr] of map.entries()) freq.push([kk, (arr||[]).length]); };
          pushFreq(mapA); pushFreq(mapB);
          freq.sort((x,y)=> y[1]-x[1]);
          const top = freq.slice(0,8).map(([kk,c])=> resolveItemMeta(kk).name + ' — ' + c);
          card = makeCard('Key item timings ⏱️', top.length? top : ['n/a']);
        }
        card.setAttribute('data-items','1');
        return card;
      };
      const itemCard = renderItemsCard(aItems, bItems);
      fullWidth.appendChild(itemCard);
      // If no items surfaced but we have games, try detail-backed purchase logs
      const countItems = (m)=> Array.from(m.values()).reduce((s,a)=> s + (Array.isArray(a)?a.length:0), 0);
      const includedItemsA = itemEntriesA.length;
      const includedItemsB = itemEntriesB.length;
      if((includedItemsA>0 && countItems(aItems)===0) || (includedItemsB>0 && countItems(bItems)===0)){
        Promise.all([
          extractItemTimesAsync(itemEntriesA, aId),
          extractItemTimesAsync(itemEntriesB, bId)
        ]).then(([NA, NB])=>{
          const newCard = renderItemsCard(NA||aItems, NB||bItems);
          const old = fullWidth.querySelector('[data-items="1"]');
          if(old) old.replaceWith(newCard); else fullWidth.appendChild(newCard);
        }).catch(()=>{});
      }

      // If aggregates look empty but we have included matches, try async detail-backed aggregates and update UI
      const looksEmpty = (x)=>!x || (!x.games || ((x.k||0)+(x.d||0)+(x.a||0)+(x.gpm||0)+(x.xpm||0)===0));
      const includedA = (function(){ const d={}; getPlayerEntries(data.matches||[], aId, filters, timeWindow, d); return d.included||0; })();
      const includedB = (function(){ const d={}; getPlayerEntries(data.matches||[], bId, filters, timeWindow, d); return d.included||0; })();
      if((includedA>0 && looksEmpty(aggA)) || (includedB>0 && looksEmpty(aggB))){
        Promise.all([
          computeCoreAggregatesAsync(data.matches||[], aId, filters, timeWindow),
          computeCoreAggregatesAsync(data.matches||[], bId, filters, timeWindow)
        ]).then(([NA, NB])=>{
          const newA = NA||aggA; const newB = NB||aggB;
          // rewrite summary cards
          colA.innerHTML = '';
          colB.innerHTML = '';
          const itemsA2 = [];
          if(!newA || newA.games===0) itemsA2.push('No games in range'); else {
            itemsA2.push(`Games: ${newA.games}`);
            itemsA2.push(`WR: ${fmtPct(newA.wr)}`);
            itemsA2.push(`K/D/A: ${fmt(newA.k)}/${fmt(newA.d)}/${fmt(newA.a)}`);
            itemsA2.push(`GPM/XPM: ${fmt(newA.gpm)}/${fmt(newA.xpm)}`);
          }
          colA.appendChild(makeCard('Summary A 🧑', itemsA2));
          const itemsB2 = [];
          if(!newB || newB.games===0) itemsB2.push('No games in range'); else {
            itemsB2.push(`Games: ${newB.games}`);
            itemsB2.push(`WR: ${fmtPct(newB.wr)}`);
            itemsB2.push(`K/D/A: ${fmt(newB.k)}/${fmt(newB.d)}/${fmt(newB.a)}`);
            itemsB2.push(`GPM/XPM: ${fmt(newB.gpm)}/${fmt(newB.xpm)}`);
          }
          colB.appendChild(makeCard('Summary B 🧑', itemsB2));

          // replace h2h bars card with full metrics
          if(newA && newB && newA.games>0 && newB.games>0){
            const newCard = makeH2HCard(newA, newB);
            const old = fullWidth.querySelector('[data-h2h="1"]');
            if(old) old.replaceWith(newCard); else fullWidth.appendChild(newCard);
          }
        }).catch(()=>{});
      }

      // Vision & Stacks card (initial) — uses basic per-player fields; will detail-fetch if missing
      async function computeVisionStacks(entries, playerId){
        let obs=0, sen=0, ok=0, sk=0, stacks=0, g=0;
        for(const {match:m, player:p0} of entries){
          let p = p0;
          const has = (x)=> Number.isFinite(p?.[x]);
          if(!(has('obs_placed')||has('sen_placed')||has('observer_kills')||has('sentry_kills')||has('camps_stacked'))){
            try{
              const md = await fetchDetail(m.match_id||m.id);
              if(md && Array.isArray(md.players)){
                const found = md.players.find(pp => Number(pp.account_id)===playerId);
                if(found) p = found;
              }
            }catch(_e){}
          }
          if(!p) continue;
          g++;
          obs += Number(p.obs_placed||0);
          sen += Number(p.sen_placed||0);
          ok += Number(p.observer_kills||0);
          sk += Number(p.sentry_kills||0);
          stacks += Number(p.camps_stacked||0);
        }
        return { games:g, obs, sen, dewards: ok+sk, stacks };
      }
      (async ()=>{
        const [va, vb] = await Promise.all([
          computeVisionStacks(getPlayerEntries(data.matches||[], aId, filters, timeWindow), aId),
          computeVisionStacks(getPlayerEntries(data.matches||[], bId, filters, timeWindow), bId)
        ]);
        const avg = (sum, g)=> g>0 ? (sum/g) : 0;
  const card = createEl('div', { class:'pc-card' });
  { const t=createEl('div', { class:'pc-card-title', text:'Vision & Stacks 👁️' }); card.appendChild(t); withInfo(t, 'Per-game averages for observers, sentries, dewards and camp stacks. Totals shown below.'); }
        const wrap = createEl('div', { class:'pc-split' });
  const maxV = Math.max(avg(va.obs,va.games), avg(vb.obs,vb.games), avg(va.sen,va.games), avg(vb.sen,vb.games), avg(va.dewards,va.games), avg(vb.dewards,vb.games), avg(va.stacks,va.games), avg(vb.stacks,vb.games), 1);
  const maxVh = maxV * 1.1;
  const row = (label, aSum, bSum)=> dumbbellRow(label, avg(aSum,va.games), avg(bSum,vb.games), maxVh, (x)=> isFinite(x)? (Math.round(x*10)/10).toString() : '-');
        wrap.appendChild(row('Observers/g', va.obs, vb.obs));
        wrap.appendChild(row('Sentries/g', va.sen, vb.sen));
        wrap.appendChild(row('Dewards/g', va.dewards, vb.dewards));
        wrap.appendChild(row('Stacks/g', va.stacks, vb.stacks));
        card.appendChild(wrap);
        const totals = createEl('div', { class:'pc-note', text:`Totals — A: obs ${fmt(va.obs)}, sen ${fmt(va.sen)}, dewards ${fmt(va.dewards)}, stacks ${fmt(va.stacks)} | B: obs ${fmt(vb.obs)}, sen ${fmt(vb.sen)}, dewards ${fmt(vb.dewards)}, stacks ${fmt(vb.stacks)}` });
        card.appendChild(totals);
        fullWidth.appendChild(card);
      })().catch(()=>{});

      // Objectives (±60s participation around Tower and Roshan events)
      async function computeObjectivesParticipation(entries, playerId){
        const windowSec = 60;
        let towersPart = 0, towersLH = 0, roshPart = 0, aegis = 0, roshTeamKills = 0, g=0;
        for(const {match:m, player:p0} of entries){
          let p = p0;
          let md = null;
          try{
            md = await fetchDetail(m.match_id||m.id);
            if(md && Array.isArray(md.players)){
              const found = md.players.find(pp => Number(pp.account_id)===playerId);
              if(found) p = found;
            }
          }catch(_e){}
          if(!md || !p) continue;
          g++;
          const playerSlot = Number(p.player_slot);
          const playerIsRad = isRadiantFlag(p)===true;
          const killsLog = Array.isArray(p.kills_log) ? p.kills_log : [];
          const deathsLog = Array.isArray(p.deaths_log) ? p.deaths_log : [];
          const inWindow = (t)=>{
            // any activity within [t-windowSec, t+windowSec]
            const lo = t - windowSec, hi = t + windowSec;
            const hasKill = killsLog.some(ev => isFinite(ev?.time) && ev.time>=lo && ev.time<=hi);
            const hasDeath = deathsLog.some(ev => isFinite(ev?.time) && ev.time>=lo && ev.time<=hi);
            return hasKill || hasDeath;
          };
          const objs = Array.isArray(md.objectives) ? md.objectives : [];
          for(const ev of objs){
            const t = Number(ev.time);
            if(!isFinite(t)) continue;
            if(ev.type === 'building_kill' && typeof ev.key === 'string' && ev.key.includes('tower')){
              // Tower last hit
              const evSlot = Number(ev.player_slot ?? ev.slot);
              if(isFinite(evSlot) && evSlot === playerSlot) towersLH++;
              // Only count participation when player's team destroyed the tower
              let killerTeamIsRad = null;
              if(isFinite(evSlot)) killerTeamIsRad = evSlot < 128;
              if(killerTeamIsRad === null){
                // If no player slot (e.g., creep/siege), try inferring from unit? else skip team filter
                // We'll accept these as potentially team-agnostic pushes; include participation if nearby
                if(inWindow(t)) towersPart++;
              } else {
                if(killerTeamIsRad === playerIsRad){
                  if(inWindow(t)) towersPart++;
                }
              }
            }
            if(ev.type === 'CHAT_MESSAGE_ROSHAN_KILL'){
              // team: 2=radiant, 3=dire
              const team = Number(ev.team);
              const teamIsRad = team===2 ? true : team===3 ? false : null;
              if(teamIsRad === null) continue;
              if(teamIsRad === playerIsRad){
                roshTeamKills++;
                if(inWindow(t)) roshPart++;
              }
            }
            if(ev.type === 'CHAT_MESSAGE_AEGIS'){
              const evSlot = Number(ev.player_slot ?? ev.slot);
              if(isFinite(evSlot) && evSlot === playerSlot){
                aegis++;
                // Count Aegis pickup also as Roshan participation for the player
                roshPart++;
              }
            }
          }
        }
        return { games:g, towersPart, towersLH, roshPart, aegis, roshTeamKills };
      }
      (async()=>{
        const [oa, ob] = await Promise.all([
          computeObjectivesParticipation(getPlayerEntries(data.matches||[], aId, filters, timeWindow), aId),
          computeObjectivesParticipation(getPlayerEntries(data.matches||[], bId, filters, timeWindow), bId)
        ]);
        const rows = [];
        const add = (label, a, b)=> rows.push(barCompare(label, a, b, n=>fmt(n)));
        add('Tower participation (±60s)', oa.towersPart, ob.towersPart);
        add('Tower last hits', oa.towersLH, ob.towersLH);
        add('Roshan participation (±60s)', oa.roshPart, ob.roshPart);
        add('Aegis pickups', oa.aegis, ob.aegis);
        const card = makeRowCard('Objectives ⚔️', rows, 'Participation within ±60s around tower deaths (team-side) and Roshan kills. Aegis pickups counted directly.');
        fullWidth.appendChild(card);
      })().catch(()=>{});

    // update URL state
    const url = writeQS({ playerA:aId, playerB:bId, side:filters.side });
    try{ localStorage.setItem('pc_state', JSON.stringify({ playerA:aId, playerB:bId, side:filters.side })); }catch(_e){}
      if (typeof options?.onCopyLink === 'function') options.onCopyLink(url);
    }

    selA.addEventListener('change', render);
    selB.addEventListener('change', render);
  sideSel.addEventListener('change', render);
    copyBtn.addEventListener('click', () => {
      const url = writeQS({ playerA: selA.value?Number(selA.value):null, playerB: selB.value?Number(selB.value):null, side: sideSel.value });
      navigator.clipboard?.writeText(url).catch(()=>{});
      copyBtn.textContent = 'Copied!';
      setTimeout(()=> copyBtn.textContent='Copy link', 1000);
    });

    // Listen for host range changes
    try{ window.addEventListener('dv:range-changed', ()=>{ render(); }); }catch(_e){}
    render();
  }

  // expose global namespace
  window.PlayerCompare = { mount };
})();

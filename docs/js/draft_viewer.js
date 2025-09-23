(function(){
  function esc(s){ return String(s||'').replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[c])); }
  function hero(meta, size){ if(!meta) return `<span class="badge">#?</span>`; const w=size||28; return `<span style="display:inline-flex;align-items:center;gap:6px"><img src='${esc(meta.img||meta.icon||'')}' alt='${esc(meta.name||'Hero')}' loading='lazy' decoding='async' style='width:${w}px;height:${w}px;border-radius:6px;border:1px solid rgba(255,255,255,.1)'><span>${esc(meta.name||'Hero')}</span></span>`; }
  function fmtPct(x){ return (x*100).toFixed(1)+'%'; }
  function ensureStyle(){
    if(document.getElementById('dv-draft-style')) return;
    const css = `
  .dv-draft .summary-grid{ display:grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 12px; align-items:start }
  .dv-draft .summary-grid > div{ min-width:0 }
  .dv-draft .card{ background: rgba(255,255,255,.03); border:1px solid rgba(255,255,255,.06); border-radius:12px; padding:10px }
  .dv-draft .card h4{ margin:0 0 8px 0; font-size:13px; color:var(--muted) }
  .dv-draft .chart{ display:flex; flex-direction:column; gap:6px }
  .dv-draft .bar{ display:flex; align-items:center; gap:8px }
  .dv-draft .bar .meter{ position:relative; flex:1; height:16px; background:rgba(255,255,255,.06); border:1px solid rgba(255,255,255,.08); border-radius:999px; overflow:hidden }
  .dv-draft .bar .fill{ position:absolute; top:0; left:0; bottom:0; width:0%; background:linear-gradient(90deg, rgba(68,197,92,.85), rgba(68,197,92,.55)); }
  .dv-draft .bar .info{ min-width:86px; text-align:right; font-variant-numeric: tabular-nums; color:var(--muted); font-size:12px }
  .dv-draft .bar .name{ display:inline-flex; align-items:center; gap:6px; min-width:160px }
  .dv-draft .tiny{ font-size:12px; color:var(--muted) }
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
      .dv-draft .field{ display:inline-flex; align-items:center; gap:6px; margin-left:8px }
      .dv-draft .field input{ width:160px; background:transparent; color:var(--text); border:1px solid var(--border); border-radius:8px; padding:5px 8px; font-size:12px }
      .dv-draft .badge{ display:inline-flex; align-items:center; gap:6px; background:rgba(255,255,255,.06); border:1px solid var(--border); border-radius:999px; padding:3px 8px; font-size:12px; color:var(--muted) }
      .dv-draft .btn{ padding:6px 10px; border:1px solid var(--border); background:linear-gradient(180deg, rgba(255,255,255,.07), rgba(255,255,255,.03)); color:var(--text); border-radius:8px; cursor:pointer; font-size:12px }
      .dv-draft .btn.secondary{ background:transparent }
      
      .dv-draft .hname{ white-space:nowrap; overflow:hidden; text-overflow:ellipsis; display:inline-block; max-width:200px }
      .dv-draft .dv-hero{ cursor:pointer; display:inline-block; border-radius:8px; padding:2px 4px; }
      .dv-draft .dv-hero:hover{ background: rgba(109,166,255,.12); }
    `;
    const el = document.createElement('style'); el.id='dv-draft-style'; el.textContent = css; document.head.appendChild(el);
  }

  function compute(details){
    const picks = new Map(); // hid -> {picks,wins}
    const bans = new Map();  // hid -> count
    const firstPick = new Map(); // hid -> {count,wins}
    const openingPairs = new Map(); // "a-b" -> {games,wins}
    const firstPickBySide = { Radiant: new Map(), Dire: new Map() }; // side -> hid -> {count,wins}
    const openingPairsBySide = { Radiant: new Map(), Dire: new Map() }; // side -> key -> {a,b,games,wins}
    const picksPhase = { P1: new Map(), P2: new Map() }; // phase -> hid -> {picks,wins}
    const bansPhase = { P1: new Map(), P2: new Map() }; // phase -> hid -> count
  let matches = 0; // matches with usable draft data
  const captains = new Map(); // aid -> {games,wins}

    for(const md of details||[]){ if(!md) continue; const radWin = !!md.radiant_win; const pbs = Array.isArray(md.picks_bans)? md.picks_bans: []; if(!pbs.length) continue; matches++;
      // captains if available
      try{
        const rc = Number(md.radiant_captain||0), dc = Number(md.dire_captain||0);
        if(rc){ const r = captains.get(rc)||{games:0,wins:0}; r.games++; if(radWin) r.wins++; captains.set(rc,r); }
        if(dc){ const r = captains.get(dc)||{games:0,wins:0}; r.games++; if(!radWin) r.wins++; captains.set(dc,r); }
      }catch(_e){}
      // Collect pick events per side in draft order
      const pickEvents = { Radiant: [], Dire: [] };
      const banEvents = { Radiant: [], Dire: [] };
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
          if(side){ banEvents[side].push({ hid, order }); }
        }
      }
      function teamWon(side){ return side==='Radiant' ? radWin : !radWin; }
      // First pick per side
      for(const side of ['Radiant','Dire']){
        const list = pickEvents[side].slice().sort((a,b)=> a.order - b.order);
        if(list.length){
          const fp = list[0];
          const r = firstPick.get(fp.hid) || { count:0, wins:0 }; r.count++; if(teamWon(side)) r.wins++; firstPick.set(fp.hid, r);
          const rs = firstPickBySide[side].get(fp.hid) || { count:0, wins:0 }; rs.count++; if(teamWon(side)) rs.wins++; firstPickBySide[side].set(fp.hid, rs);
        }
        // Opening pair: first two picks if present
        if(list.length>=2){ const a=list[0].hid, b=list[1].hid; const lo=Math.min(a,b), hi=Math.max(a,b); const key=`${lo}-${hi}`; const rec = openingPairs.get(key) || { a:lo, b:hi, games:0, wins:0 }; rec.games++; if(teamWon(side)) rec.wins++; openingPairs.set(key, rec); const recS = openingPairsBySide[side].get(key) || { a:lo, b:hi, games:0, wins:0 }; recS.games++; if(teamWon(side)) recS.wins++; openingPairsBySide[side].set(key, recS); }
        // Phase split for picks: first two picks of each side considered P1, rest P2
        if(list.length){ const split = Math.min(2, list.length); const won = teamWon(side); list.forEach((ev, idx)=>{ const ph = idx < split ? 'P1' : 'P2'; const rec = picksPhase[ph].get(ev.hid) || { picks:0, wins:0 }; rec.picks++; if(won) rec.wins++; picksPhase[ph].set(ev.hid, rec); }); }
        // Phase split for bans: half of bans per side considered P1, remainder P2
        const blist = banEvents[side].slice().sort((a,b)=> a.order - b.order);
        if(blist.length){ const splitB = Math.floor(blist.length/2); blist.forEach((ev, idx)=>{ const ph = idx < splitB ? 'P1' : 'P2'; bansPhase[ph].set(ev.hid, (bansPhase[ph].get(ev.hid)||0) + 1); }); }
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
    const first = Array.from(firstPick.entries()).map(([hid, v])=>({ hid:Number(hid), count:v.count, wins:v.wins, wr: v.count? (v.wins/v.count):0 })).sort((a,b)=> b.count - a.count || b.wr - a.wr);
    const firstSides = {
      Radiant: Array.from(firstPickBySide.Radiant.entries()).map(([hid, v])=>({ hid:Number(hid), count:v.count, wins:v.wins, wr: v.count? (v.wins/v.count):0 })).sort((a,b)=> b.count - a.count || b.wr - a.wr),
      Dire: Array.from(firstPickBySide.Dire.entries()).map(([hid, v])=>({ hid:Number(hid), count:v.count, wins:v.wins, wr: v.count? (v.wins/v.count):0 })).sort((a,b)=> b.count - a.count || b.wr - a.wr)
    };
    const pairs = Array.from(openingPairs.values()).map(v=>({ ...v, wr: v.games? (v.wins/v.games):0 })).sort((a,b)=> b.wr - a.wr || b.games - a.games);
    const pairsSides = {
      Radiant: Array.from(openingPairsBySide.Radiant.values()).map(v=>({ ...v, wr: v.games? (v.wins/v.games):0 })).sort((a,b)=> b.wr - a.wr || b.games - a.games),
      Dire: Array.from(openingPairsBySide.Dire.values()).map(v=>({ ...v, wr: v.games? (v.wins/v.games):0 })).sort((a,b)=> b.wr - a.wr || b.games - a.games)
    };
  const cont = Array.from(contest.values()).sort((a,b)=> b.contest - a.contest || b.picks - a.picks || b.bans - a.bans);
    const bansArr = Array.from(bans.entries()).map(([hid,cnt])=>({ hid:Number(hid), bans:cnt, banRate: matches? (cnt/matches):0, contestRate: matches? ((contest.get(Number(hid))?.contest||0)/matches):0, picks: (contest.get(Number(hid))?.picks)||0 })).sort((a,b)=> b.bans - a.bans || b.banRate - a.banRate);
  const topPicked = cont.slice().sort((a,b)=> b.picks - a.picks || b.wrPick - a.wrPick).filter(x=>x.picks>0).map(x=>({ hid:x.hid, picks:x.picks, wr: x.wrPick })).slice(0,5);
  const topBanned = bansArr.slice(0,5).map(x=>({ hid:x.hid, bans:x.bans, wr: (contest.get(x.hid)?.wrPick)||0 }));
  const topCaptains = Array.from(captains.entries()).map(([aid,v])=>({ aid:Number(aid), games:v.games, wins:v.wins, wr: v.games? (v.wins/v.games):0 })).sort((a,b)=> b.wr - a.wr || b.games - a.games).slice(0,5);
    const phasePicks = {
      P1: Array.from(picksPhase.P1.entries()).map(([hid, v])=>({ hid:Number(hid), picks:v.picks, wins:v.wins, wr: v.picks? (v.wins/v.picks):0 })).sort((a,b)=> b.picks - a.picks || b.wr - a.wr),
      P2: Array.from(picksPhase.P2.entries()).map(([hid, v])=>({ hid:Number(hid), picks:v.picks, wins:v.wins, wr: v.picks? (v.wins/v.picks):0 })).sort((a,b)=> b.picks - a.picks || b.wr - a.wr)
    };
    const phaseBans = {
      P1: Array.from(bansPhase.P1.entries()).map(([hid, cnt])=>({ hid:Number(hid), bans:cnt })).sort((a,b)=> b.bans - a.bans),
      P2: Array.from(bansPhase.P2.entries()).map(([hid, cnt])=>({ hid:Number(hid), bans:cnt })).sort((a,b)=> b.bans - a.bans)
    };
    const denied = Array.from(contest.values()).map(v=>{
      const pickRate = matches? (v.picks / matches) : 0; const banCnt = bans.get(v.hid)||0; const banRate = matches? (banCnt / matches) : 0; const contestRate = matches? (v.contest / matches) : 0; const deniedScore = banRate - pickRate; return { hid: v.hid, picks: v.picks, bans: banCnt, contest: v.contest, pickRate, banRate, contestRate, deniedScore };
    }).sort((a,b)=> b.deniedScore - a.deniedScore || b.bans - a.bans);
    return { contest: cont, firstPicks: first, openingPairs: pairs, topBans: bansArr, totalMatches: matches, phasePicks, phaseBans, firstPicksBySide: firstSides, openingPairsBySide: pairsSides, denied, charts: { topPicked, topBanned }, captains: topCaptains };
  }

  function mount(root, opts){
    if(!root) return; ensureStyle(); const heroes = (opts&&opts.heroes)||{}; const data = (opts&&opts.data)||{};
    const persistKey = (opts && opts.persistKey) || null;
    const nameResolver = (opts && opts.nameResolver) || (window.__resolver || (aid=> `Player ${aid}`));
    function hmeta(id){ return heroes[String(id)] || { name: `#${id}`, img: '' }; }
    function hueForWR(wr){ // 0..1 -> red(0) to green(120)
      const h = Math.max(0, Math.min(120, Math.round((wr||0)*120)));
      return `hsl(${h} 65% 45%)`;
    }
    function chartPicked(arr){
      if(!arr||!arr.length) return '<div class="sub">no data</div>';
      const max = Math.max(...arr.map(x=> x.picks||0), 1);
      return `<div class='chart'>${arr.map(x=>{
        const pct = Math.max(2, Math.round((x.picks/max)*100));
        const meta = hmeta(x.hid);
        const tip = `${esc(meta.name)} – Picks: ${x.picks}, WR: ${fmtPct(x.wr||0)}`;
        const color = hueForWR(x.wr||0);
        return `<div class='bar' title='${tip}'>
          <span class='name'>${hero(meta,20)}</span>
          <div class='meter'><div class='fill' style='width:${pct}%; background:${color}'></div></div>
          <span class='info'>${x.picks} • ${fmtPct(x.wr||0)}</span>
        </div>`;
      }).join('')}</div>`;
    }
    function chartBanned(arr){
      if(!arr||!arr.length) return '<div class="sub">no data</div>';
      const max = Math.max(...arr.map(x=> x.bans||0), 1);
      return `<div class='chart'>${arr.map(x=>{
        const pct = Math.max(2, Math.round((x.bans/max)*100));
        const meta = hmeta(x.hid);
        const tip = `${esc(meta.name)} – Bans: ${x.bans}, Pick WR: ${fmtPct(x.wr||0)}`;
        // Use WR color if available, otherwise neutral
        const color = hueForWR(x.wr||0);
        return `<div class='bar' title='${tip}'>
          <span class='name'>${hero(meta,20)}</span>
          <div class='meter'><div class='fill' style='width:${pct}%; background:${color}'></div></div>
          <span class='info'>${x.bans} • ${fmtPct(x.wr||0)}</span>
        </div>`;
      }).join('')}</div>`;
    }
    function listCaptains(arr){
      if(!arr||!arr.length) return '<div class="sub">no data</div>';
      return `<table class='table'>
        <thead><tr><th>Captain</th><th class='num'>Games</th><th class='num'>Wins</th><th class='num'>WR</th></tr></thead>
        <tbody>${arr.map(x=>{
          const nm = nameResolver ? (nameResolver(x.aid) || `Player ${x.aid}`) : `Player ${x.aid}`;
          return `<tr><td>${esc(nm)}</td><td class='num'>${x.games}</td><td class='num'>${x.wins}</td><td class='num'>${fmtPct(x.wr||0)}</td></tr>`;
        }).join('')}</tbody>
      </table>`;
    }
    function listContest(arr){ if(!arr||!arr.length) return '<div class="sub">no data</div>'; return `<table class='table'>
      <thead><tr><th>Hero</th><th class='num'>Picks</th><th class='num'>Bans</th><th class='num'>Contest</th><th class='num'>Pick WR</th></tr></thead>
      <tbody>${arr.map(x=>`<tr><td class='col-hero'><span class='dv-hero' data-hid='${x.hid}' title='Filter by ${esc(hmeta(x.hid).name||('#'+x.hid))}'>${hero(hmeta(x.hid),22)}</span> <span class='hname'></span></td><td class='num'>${x.picks}</td><td class='num'>${x.bans}</td><td class='num'>${x.contest}</td><td class='num'>${fmtPct(x.wrPick)}</td></tr>`).join('')}</tbody>
    </table>`; }
    function listFirst(arr){ if(!arr||!arr.length) return '<div class="sub">no data</div>'; return `<table class='table'>
      <thead><tr><th>Hero</th><th class='num'>First picks</th><th class='num'>WR</th></tr></thead>
      <tbody>${arr.map(x=>`<tr><td class='col-hero'><span class='dv-hero' data-hid='${x.hid}' title='Filter by ${esc(hmeta(x.hid).name||('#'+x.hid))}'>${hero(hmeta(x.hid),22)}</span> <span class='hname'></span></td><td class='num'>${x.count}</td><td class='num'>${fmtPct(x.wr)}</td></tr>`).join('')}</tbody>
    </table>`; }
    function listPairs(arr){ if(!arr||!arr.length) return '<div class="sub">no data</div>'; return `<table class='table'>
      <thead><tr><th>Opening pair</th><th class='num'>Games</th><th class='num'>WR</th></tr></thead>
      <tbody>${arr.map(x=>`<tr><td class='col-pair'><span class='dv-hero' data-hid='${x.a}' title='Filter by ${esc(hmeta(x.a).name||('#'+x.a))}'>${hero(hmeta(x.a),22)}</span> + <span class='dv-hero' data-hid='${x.b}' title='Filter by ${esc(hmeta(x.b).name||('#'+x.b))}'>${hero(hmeta(x.b),22)}</span></td><td class='num'>${x.games}</td><td class='num'>${fmtPct(x.wr)}</td></tr>`).join('')}</tbody>
    </table>`; }
    function listBans(arr){ if(!arr||!arr.length) return '<div class="sub">no data</div>'; const tm = Number(data.totalMatches||0); return `<table class='table'>
      <thead><tr><th>Hero</th><th class='num'>Bans</th><th class='num'>Ban rate</th><th class='num'>Contest rate</th><th class='num'>Picks</th></tr></thead>
      <tbody>${arr.map(x=>`<tr><td class='col-hero'><span class='dv-hero' data-hid='${x.hid}' title='Filter by ${esc(hmeta(x.hid).name||('#'+x.hid))}'>${hero(hmeta(x.hid),22)}</span> <span class='hname'></span></td><td class='num'>${x.bans}</td><td class='num'>${tm? fmtPct(x.banRate) : '-'}</td><td class='num'>${tm? fmtPct(x.contestRate) : '-'}</td><td class='num'>${x.picks||0}</td></tr>`).join('')}</tbody>
    </table>`; }
    function listPhasePicks(arr){ if(!arr||!arr.length) return '<div class="sub">no data</div>'; return `<table class='table'>
      <thead><tr><th>Hero</th><th class='num'>Picks</th><th class='num'>WR</th></tr></thead>
      <tbody>${arr.map(x=>`<tr><td class='col-hero'><span class='dv-hero' data-hid='${x.hid}' title='Filter by ${esc(hmeta(x.hid).name||('#'+x.hid))}'>${hero(hmeta(x.hid),22)}</span> <span class='hname'></span></td><td class='num'>${x.picks}</td><td class='num'>${fmtPct(x.wr)}</td></tr>`).join('')}</tbody>
    </table>`; }
    function listPhaseBans(arr){ if(!arr||!arr.length) return '<div class="sub">no data</div>'; return `<table class='table'>
      <thead><tr><th>Hero</th><th class='num'>Bans</th></tr></thead>
      <tbody>${arr.map(x=>`<tr><td class='col-hero'><span class='dv-hero' data-hid='${x.hid}' title='Filter by ${esc(hmeta(x.hid).name||('#'+x.hid))}'>${hero(hmeta(x.hid),22)}</span> <span class='hname'></span></td><td class='num'>${x.bans}</td></tr>`).join('')}</tbody>
    </table>`; }
    function listDenied(arr){ if(!arr||!arr.length) return '<div class="sub">no data</div>'; return `<table class='table'>
      <thead><tr><th>Hero</th><th class='num'>Bans</th><th class='num'>Picks</th><th class='num'>Contest</th><th class='num'>Ban rate</th><th class='num'>Pick rate</th><th class='num'>Denied</th></tr></thead>
      <tbody>${arr.map(x=>`<tr><td class='col-hero'><span class='dv-hero' data-hid='${x.hid}' title='Filter by ${esc(hmeta(x.hid).name||('#'+x.hid))}'>${hero(hmeta(x.hid),22)}</span> <span class='hname'></span></td><td class='num'>${x.bans}</td><td class='num'>${x.picks}</td><td class='num'>${x.contest}</td><td class='num'>${fmtPct(x.banRate)}</td><td class='num'>${fmtPct(x.pickRate)}</td><td class='num'>${fmtPct(x.deniedScore)}</td></tr>`).join('')}</tbody>
    </table>`; }
  // Toolbar with view switch + filters (streamlined grouping)
  const mode = (opts && opts.mode) || 'overview';
  // primary: overview | picks | bans | pairs
  let primary = ['overview','picks','bans','pairs'].includes(mode)? mode : 'overview';
  // submodes
  let picksSub = 'first'; // first | phase
  let bansSub = 'top'; // top | phase | denied
  // filters
  let minGames = 0, minWR = 0; // used for 'pairs'
  let heroFilter = '';
  let sideSel = 'all'; // all|Radiant|Dire (applies to picks: first and pairs)
  let phaseSel = 'P1'; // P1|P2
  if(persistKey){
    try{
      const saved = JSON.parse(localStorage.getItem(persistKey) || 'null');
      if(saved && typeof saved === 'object'){
        // Back-compat mapping from old curMode
        if(saved.curMode){
          const m = saved.curMode;
          if(m==='contest') primary='overview';
          else if(m==='first') { primary='picks'; picksSub='first'; }
          else if(m==='phase_picks') { primary='picks'; picksSub='phase'; }
          else if(m==='bans') { primary='bans'; bansSub='top'; }
          else if(m==='phase_bans') { primary='bans'; bansSub='phase'; }
          else if(m==='denied') { primary='bans'; bansSub='denied'; }
          else if(m==='pairs') { primary='pairs'; }
        }
        if(['overview','picks','bans','pairs'].includes(saved.primary)) primary = saved.primary;
        if(['first','phase'].includes(saved.picksSub)) picksSub = saved.picksSub;
        if(['top','phase','denied'].includes(saved.bansSub)) bansSub = saved.bansSub;
        if(Number.isFinite(saved.minGames)) minGames = Math.max(0, Math.floor(saved.minGames));
        if(Number.isFinite(saved.minWR)) minWR = Math.max(0, Math.min(100, saved.minWR));
        if(typeof saved.heroFilter === 'string') heroFilter = saved.heroFilter;
        if(saved.sideSel && ['all','Radiant','Dire'].includes(saved.sideSel)) sideSel = saved.sideSel;
        if(saved.phaseSel && ['P1','P2'].includes(saved.phaseSel)) phaseSel = saved.phaseSel;
      }
    }catch(_e){}
  }
  function seg(label, attr, value){ return `<button class='seg' ${attr}='${value}'>${label}</button>`; }
  function persist(){ if(!persistKey) return; try{ localStorage.setItem(persistKey, JSON.stringify({ primary, picksSub, bansSub, minGames, minWR, heroFilter, sideSel, phaseSel })); }catch(_e){} }
    root.innerHTML = `
      <div class='dv-draft'>
        <div class='toolbar'>
          ${seg('Overview','data-pmode','overview')}
          ${seg('Picks','data-pmode','picks')}
          ${seg('Bans','data-pmode','bans')}
          ${seg('Pairs','data-pmode','pairs')}
          <span class='switch'><label class='sub'>Min Games</label> <input type='number' id='dv-min-games' value='0' min='0' step='1' style='width:70px;background:transparent;color:var(--text);border:1px solid var(--border);border-radius:8px;padding:4px 6px'></span>
          <span class='switch'><label class='sub'>Min WR %</label> <input type='number' id='dv-min-wr' value='0' min='0' max='100' step='1' style='width:70px;background:transparent;color:var(--text);border:1px solid var(--border);border-radius:8px;padding:4px 6px'></span>
          <span class='field'><label class='sub'>Hero</label> <input type='text' id='dv-hero-filter' placeholder='filter hero...'></span>
          <button class='btn' id='dv-export-csv' title='Download current table as CSV'>Export CSV</button>
          <button class='btn secondary' id='dv-reset' title='Reset filters'>Reset</button>
          <span class='badge' id='dv-match-count' title='Matches with draft data' style='margin-left:auto;'></span>
          <div class='switch' id='dv-side-switch' title='Side filter for first picks and pairs'>
            <label class='sub'>Side</label>
            <button class='seg' data-side='all'>All</button>
            <button class='seg' data-side='Radiant'>Radiant</button>
            <button class='seg' data-side='Dire'>Dire</button>
          </div>
          <div class='switch' id='dv-phase-switch' title='Phase filter for picks/bans'>
            <label class='sub'>Phase</label>
            <button class='seg' data-phase='P1'>P1</button>
            <button class='seg' data-phase='P2'>P2</button>
          </div>
          <div class='switch' id='dv-subnav-picks' title='Picks view'>
            <label class='sub'>Picks</label>
            ${seg('First','data-picks-sub','first')}
            ${seg('Phase','data-picks-sub','phase')}
          </div>
          <div class='switch' id='dv-subnav-bans' title='Bans view'>
            <label class='sub'>Bans</label>
            ${seg('Top','data-bans-sub','top')}
            ${seg('Phase','data-bans-sub','phase')}
            ${seg('Denied','data-bans-sub','denied')}
          </div>
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
  // primary nav
  const tabs = root.querySelectorAll('.seg[data-pmode]'); tabs.forEach(b=> { const is=b.getAttribute('data-pmode')===primary; b.classList.toggle('active', is); b.setAttribute('aria-pressed', String(is)); });
      const mc = root.querySelector('#dv-match-count'); if(mc){ const tm = Number(data.totalMatches||0); mc.textContent = tm? `${tm} matches` : ''; }
      const hf = (heroFilter||'').trim().toLowerCase();
      const nameMatches = (hid)=>{ if(!hf) return true; const meta = hmeta(hid); const nm = String(meta.name||'').toLowerCase(); return nm.includes(hf) || String(hid).includes(hf); };
      // Toggle auxiliary control groups
      try{
        const sideBox = root.querySelector('#dv-side-switch');
        const phaseBox = root.querySelector('#dv-phase-switch');
        const picksSubBox = root.querySelector('#dv-subnav-picks');
        const bansSubBox = root.querySelector('#dv-subnav-bans');
        if(sideBox) sideBox.style.display = (primary==='pairs' || (primary==='picks' && picksSub==='first')) ? 'inline-flex' : 'none';
        if(phaseBox) phaseBox.style.display = (primary==='picks' && picksSub==='phase') || (primary==='bans' && bansSub==='phase') ? 'inline-flex' : 'none';
        if(picksSubBox) picksSubBox.style.display = (primary==='picks') ? 'inline-flex' : 'none';
        if(bansSubBox) bansSubBox.style.display = (primary==='bans') ? 'inline-flex' : 'none';
        // numeric filters only meaningful for pairs
        const mgWrap = root.querySelector('#dv-min-games')?.parentElement; const mwWrap = root.querySelector('#dv-min-wr')?.parentElement;
        if(mgWrap) mgWrap.style.display = (primary==='pairs') ? 'inline-flex' : 'none';
        if(mwWrap) mwWrap.style.display = (primary==='pairs') ? 'inline-flex' : 'none';
        // reflect active buttons
  if(sideBox){ sideBox.querySelectorAll('button[data-side]').forEach(b=> { const is=b.getAttribute('data-side')===sideSel; b.classList.toggle('active', is); b.setAttribute('aria-pressed', String(is)); }); }
  if(phaseBox){ phaseBox.querySelectorAll('button[data-phase]').forEach(b=> { const is=b.getAttribute('data-phase')===phaseSel; b.classList.toggle('active', is); b.setAttribute('aria-pressed', String(is)); }); }
  if(picksSubBox){ picksSubBox.querySelectorAll('button[data-picks-sub]').forEach(b=> { const is=b.getAttribute('data-picks-sub')===picksSub; b.classList.toggle('active', is); b.setAttribute('aria-pressed', String(is)); }); }
  if(bansSubBox){ bansSubBox.querySelectorAll('button[data-bans-sub]').forEach(b=> { const is=b.getAttribute('data-bans-sub')===bansSub; b.classList.toggle('active', is); b.setAttribute('aria-pressed', String(is)); }); }
      }catch(_e){}
      if(primary==='overview'){
        // Overview with charts + captains
        // Fallback: derive charts if missing (when precomputed data used)
        let topPicked = data.charts && Array.isArray(data.charts.topPicked) ? data.charts.topPicked.slice() : null;
        let topBanned = data.charts && Array.isArray(data.charts.topBanned) ? data.charts.topBanned.slice() : null;
        if(!topPicked){
          const contArr = Array.isArray(data.contest)? data.contest.slice(): [];
          topPicked = contArr.filter(x=>x.picks>0).sort((a,b)=> b.picks - a.picks || b.wrPick - a.wrPick).slice(0,5).map(x=>({hid:x.hid,picks:x.picks,wr:x.wrPick}));
        }
        if(!topBanned){
          const bansArr = Array.isArray(data.topBans)? data.topBans.slice(): [];
          // Need WR from contest
          const wrBy = new Map(); (Array.isArray(data.contest)? data.contest: []).forEach(x=> wrBy.set(x.hid, x.wrPick||0));
          topBanned = bansArr.slice(0,5).map(x=>({ hid:x.hid, bans:x.bans, wr: wrBy.get(x.hid)||0 }));
        }
        // Apply hero filter
        const filtPick = hf? topPicked.filter(x=> nameMatches(x.hid)) : topPicked;
        const filtBan = hf? topBanned.filter(x=> nameMatches(x.hid)) : topBanned;
        const picksHtml = `<div class='card'><h4>Top picked (WR color)</h4>${chartPicked(filtPick)}</div>`;
        const bansHtml = `<div class='card'><h4>Top banned (pick WR color)</h4>${chartBanned(filtBan)}</div>`;
        const caps = Array.isArray(data.captains)? data.captains.slice(): [];
        const capsHtml = `<div class='card'><h4>Top captains</h4>${listCaptains(caps)}</div>`;
        body.innerHTML = `<div class='summary-grid'><div>${picksHtml}</div><div>${bansHtml}</div><div>${capsHtml}</div></div>`;
      } else if(primary==='picks'){
        if(picksSub==='first'){
          let arr = sideSel==='all' ? (Array.isArray(data.firstPicks)? data.firstPicks.slice() : []) : ((data.firstPicksBySide && Array.isArray(data.firstPicksBySide[sideSel]))? data.firstPicksBySide[sideSel].slice(): []);
          if(hf) arr = arr.filter(x=> nameMatches(x.hid));
          body.innerHTML = listFirst(arr);
        } else {
          const arr0 = data.phasePicks && Array.isArray(data.phasePicks[phaseSel]) ? data.phasePicks[phaseSel].slice() : [];
          let arr = arr0;
          if(hf) arr = arr.filter(x=> nameMatches(x.hid));
          body.innerHTML = listPhasePicks(arr);
        }
      } else if(primary==='bans'){
        if(bansSub==='top'){
          let arr = Array.isArray(data.topBans)? data.topBans.slice() : [];
          if(hf) arr = arr.filter(x=> nameMatches(x.hid));
          body.innerHTML = listBans(arr);
        } else if(bansSub==='phase'){
          const arr0 = data.phaseBans && Array.isArray(data.phaseBans[phaseSel]) ? data.phaseBans[phaseSel].slice() : [];
          let arr = arr0;
          if(hf) arr = arr.filter(x=> nameMatches(x.hid));
          body.innerHTML = listPhaseBans(arr);
        } else {
          let arr = Array.isArray(data.denied)? data.denied.slice(): [];
          if(hf) arr = arr.filter(x=> nameMatches(x.hid));
          body.innerHTML = listDenied(arr);
        }
      } else { // pairs
        let arr = sideSel==='all' ? (Array.isArray(data.openingPairs)? data.openingPairs.slice(): []) : ((data.openingPairsBySide && Array.isArray(data.openingPairsBySide[sideSel]))? data.openingPairsBySide[sideSel].slice(): []);
        if(minGames>0) arr = arr.filter(x=> (x.games||0) >= minGames);
        if(minWR>0) arr = arr.filter(x=> ((x.wr||0)*100) >= minWR);
        if(hf) arr = arr.filter(x=> nameMatches(x.a) || nameMatches(x.b));
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
    root.querySelectorAll('.seg[data-pmode]').forEach(btn=> {
      btn.addEventListener('click', ()=>{ primary = btn.getAttribute('data-pmode'); persist(); render(); });
      btn.addEventListener('keydown', (e)=>{ if(e.key==='Enter' || e.key===' '){ e.preventDefault(); primary = btn.getAttribute('data-pmode'); persist(); render(); } });
    });
    const mg = root.querySelector('#dv-min-games'); const mw = root.querySelector('#dv-min-wr');
    // reflect persisted values in inputs
    try{ if(mg) mg.value = String(minGames); if(mw) mw.value = String(minWR); const hfEl = root.querySelector('#dv-hero-filter'); if(hfEl) hfEl.value = heroFilter; }catch(_e){}
    if(mg) mg.addEventListener('change', ()=>{ const v = Number(mg.value||0); minGames = isFinite(v)? Math.max(0, Math.floor(v)) : 0; persist(); render(); });
    if(mw) mw.addEventListener('change', ()=>{ const v = Number(mw.value||0); minWR = isFinite(v)? Math.max(0, Math.min(100, v)) : 0; persist(); render(); });
    const hfEl = root.querySelector('#dv-hero-filter'); if(hfEl){ hfEl.addEventListener('input', ()=>{ heroFilter = String(hfEl.value||''); persist(); render(); }); }
    const ex = root.querySelector('#dv-export-csv'); if(ex){ ex.addEventListener('click', ()=>{ try{ const csv = toCSV(); if(!csv) return; const blob = new Blob([csv], {type: 'text/csv;charset=utf-8;'}); const url = URL.createObjectURL(blob); const a = document.createElement('a'); a.href = url; a.download = `draft_${curMode}.csv`; document.body.appendChild(a); a.click(); setTimeout(()=>{ URL.revokeObjectURL(url); a.remove(); }, 0); }catch(_e){} }); }
    const rs = root.querySelector('#dv-reset'); if(rs){ rs.addEventListener('click', ()=>{ heroFilter=''; minGames=0; minWR=0; try{ const hfI=root.querySelector('#dv-hero-filter'); if(hfI) hfI.value=''; if(mg) mg.value='0'; if(mw) mw.value='0'; }catch(_e){} persist(); render(); }); }
    // side and phase switches
    const sideBox = root.querySelector('#dv-side-switch'); if(sideBox){
      sideBox.querySelectorAll('button[data-side]').forEach(b=> b.addEventListener('click', ()=>{ sideSel = b.getAttribute('data-side') || 'all'; persist(); render(); }));
      sideBox.addEventListener('keydown', (e)=>{ const btn=e.target.closest && e.target.closest('button[data-side]'); if(!btn) return; if(e.key==='Enter' || e.key===' '){ e.preventDefault(); sideSel = btn.getAttribute('data-side') || 'all'; persist(); render(); } });
    }
    const phaseBox = root.querySelector('#dv-phase-switch'); if(phaseBox){
      phaseBox.querySelectorAll('button[data-phase]').forEach(b=> b.addEventListener('click', ()=>{ phaseSel = b.getAttribute('data-phase') || 'P1'; persist(); render(); }));
      phaseBox.addEventListener('keydown', (e)=>{ const btn=e.target.closest && e.target.closest('button[data-phase]'); if(!btn) return; if(e.key==='Enter' || e.key===' '){ e.preventDefault(); phaseSel = btn.getAttribute('data-phase') || 'P1'; persist(); render(); } });
    }
    const picksSubBox = root.querySelector('#dv-subnav-picks'); if(picksSubBox){
      picksSubBox.querySelectorAll('button[data-picks-sub]').forEach(b=> b.addEventListener('click', ()=>{ picksSub = b.getAttribute('data-picks-sub') || 'first'; persist(); render(); }));
      picksSubBox.addEventListener('keydown', (e)=>{ const btn=e.target.closest && e.target.closest('button[data-picks-sub]'); if(!btn) return; if(e.key==='Enter' || e.key===' '){ e.preventDefault(); picksSub = btn.getAttribute('data-picks-sub') || 'first'; persist(); render(); } });
    }
    const bansSubBox = root.querySelector('#dv-subnav-bans'); if(bansSubBox){
      bansSubBox.querySelectorAll('button[data-bans-sub]').forEach(b=> b.addEventListener('click', ()=>{ bansSub = b.getAttribute('data-bans-sub') || 'top'; persist(); render(); }));
      bansSubBox.addEventListener('keydown', (e)=>{ const btn=e.target.closest && e.target.closest('button[data-bans-sub]'); if(!btn) return; if(e.key==='Enter' || e.key===' '){ e.preventDefault(); bansSub = btn.getAttribute('data-bans-sub') || 'top'; persist(); render(); } });
    }
    // hero click => filter
    root.addEventListener('click', (ev)=>{
      const el = ev.target && (ev.target.closest && ev.target.closest('.dv-hero'));
      if(!el) return; const hid = Number(el.getAttribute('data-hid')||0); if(!(hid>0)) return;
      const meta = hmeta(hid); const nm = meta && meta.name ? meta.name : String(hid);
      const input = root.querySelector('#dv-hero-filter'); if(input){ input.value = nm; }
      heroFilter = nm; persist(); render();
    });
  }

  window.DraftViewer = { mount, compute };
})();

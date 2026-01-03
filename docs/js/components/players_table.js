(function(global){
  const OD_PLAYER_URL = id => `https://www.opendota.com/players/${id}`;
  function fmtPct(x){ return (x*100).toFixed(1)+'%'; }

  function buildHeroList(p, heroMap){
    const data = Object.entries(p.heroes || {}).map(([hid, cnt])=>{
      const wins = Number(p.heroWins && p.heroWins[hid] || 0);
      const wrH = Number(cnt)>0 ? (wins/Number(cnt)) : 0;
      const meta = heroMap[String(hid)] || { name:`Hero ${hid}`, img:'' };
      return { hid, cnt:Number(cnt), wins, wrH, meta };
    }).sort((a,b)=> b.cnt - a.cnt || b.wrH - a.wrH || String(a.meta.name).localeCompare(String(b.meta.name)));
    return data.map(h=> `
      <div style='display:flex;align-items:center;gap:8px;justify-content:space-between;padding:3px 0;border-bottom:1px solid rgba(255,255,255,.06)'>
        <span style='display:flex;align-items:center;gap:8px'>
          <img src='${h.meta.img}' class='logo' alt='${h.meta.name}'>
          <span>${h.meta.name}</span>
        </span>
        <span><span class='badge'>x${h.cnt}</span><span class='badge'>WR ${fmtPct(h.wrH)}</span></span>
      </div>`).join('');
  }

  function renderRows(playersList, heroMap, opts){
    const teamResolver = opts && typeof opts.teamResolver==='function' ? opts.teamResolver : null;
    const primaryTeamByAid = (opts && opts.primaryTeamByAid) || {};

    return playersList.map(p=>{
      const wr = p.games ? (p.wins/p.games) : 0;
      const poolSize = Object.keys(p.heroes || {}).length;
      const resolvedTeam = teamResolver ? (teamResolver(p.account_id) || '') : '';
      const pt = primaryTeamByAid[String(p.account_id)];
      const teamName = resolvedTeam || (pt && pt.name) || '';
      const teamLabel = teamName ? ` <span class='sub' style='margin-left:6px'>(${teamName})</span>` : '';

      const listId = `hp-${p.account_id}`;
      const heroList = buildHeroList(p, heroMap);
      const heroesCell = `
        <div class='heroes'>
          <div class='has-hover' data-pop='${listId}' style='display:inline-block'>
            <button class='badge' data-action='toggle-pop' data-target='${listId}' title='Show per-hero breakdown'>Hero pool: <strong>${poolSize}</strong></button>
            <div id='${listId}' class='hovercard' style='min-width:320px'>
              <div class='title'>Per-hero breakdown</div>
              ${heroList || `<div class='sub'>no heroes</div>`}
            </div>
          </div>
        </div>`;

      return `
        <tr>
          <td data-sort='${String(p.name||'').toLowerCase()} ${teamName ? teamName.toLowerCase() : ''}'>
            <a href='${p.profile || (p.account_id? OD_PLAYER_URL(p.account_id):'#')}' target='_blank' rel='noopener'>${p.name || `Player ${p.account_id}`}</a>${teamLabel}
          </td>
          <td data-sort='${p.games||0}'>${p.games||0}</td>
          <td data-sort='${(p.wins||0)/(p.games||1)}'><span class='win'>${p.wins||0}</span>-<span class='loss'>${(p.games||0)-(p.wins||0)}</span></td>
          <td data-sort='${wr}'>${fmtPct(wr)}</td>
          <td data-sort='${poolSize}'>${heroesCell}</td>
        </tr>`;
    }).join('');
  }

  function wirePopovers(root){
    try{
      (root || document).querySelectorAll('[data-action="toggle-pop"]').forEach(btn=>{
        btn.addEventListener('click', (e)=>{
          e.preventDefault(); e.stopPropagation();
          const id = btn.getAttribute('data-target');
          const wrapper = btn.closest('.has-hover');
          if(!id||!wrapper) return;
          document.querySelectorAll('.has-hover.open').forEach(n=>{ if(n!==wrapper) n.classList.remove('open'); });
          wrapper.classList.toggle('open');
        });
      });
      document.addEventListener('click', (e)=>{
        document.querySelectorAll('.has-hover.open').forEach(n=>{ if(!n.contains(e.target)) n.classList.remove('open'); });
      });
    }catch(_e){}
  }

  global.PlayersTable = { renderRows, wirePopovers };
})(typeof window!=='undefined' ? window : globalThis);

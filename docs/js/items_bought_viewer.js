(function(){
  function esc(s){ return String(s||'').replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[c])); }
  function h(html){ const t=document.createElement('template'); t.innerHTML=html.trim(); return t.content.firstElementChild; }
  function injectStyles(){ if(document.getElementById('ib-base-styles')) return; const css=`
  .ib-wrapper{display:flex;flex-direction:column;gap:10px}
  .ib-toolbar{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:-2px 0 4px}
  .ib-toolbar .seg{padding:6px 10px;border:1px solid var(--border,rgba(255,255,255,.12));background:linear-gradient(180deg,rgba(255,255,255,.07),rgba(255,255,255,.03));border-radius:10px;font-size:12px;color:var(--text,#eef3fb);cursor:pointer}
  .ib-toolbar .seg.active{outline:2px solid rgba(109,166,255,.5);background:linear-gradient(180deg,rgba(109,166,255,.2),rgba(109,166,255,.08));border-color:rgba(109,166,255,.45)}
  .ib-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:14px}
  .ib-card{background:linear-gradient(180deg,rgba(255,255,255,.05),rgba(255,255,255,.02));border:1px solid var(--border,rgba(255,255,255,.08));border-radius:12px;padding:10px;display:flex;flex-direction:column}
  .ib-title{margin:0 0 6px;font-size:15px;font-weight:600;color:var(--muted,#9aa3b2)}
  ul.ib-list{list-style:none;margin:0;padding:0}
  ul.ib-list li{display:flex;align-items:center;justify-content:space-between;gap:8px;padding:6px 0;border-bottom:1px solid rgba(255,255,255,.06);font-size:13px}
  ul.ib-list li:last-child{border-bottom:0}
  .ib-badge{display:inline-block;padding:4px 8px;border-radius:999px;background:rgba(255,255,255,.08);font-size:11px;color:var(--text,#eef3fb)}
  .ib-empty{font-size:12px;color:var(--muted,#9aa3b2)}
  .ib-filters{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:4px 0 0}
  .ib-filters label{font-size:11px;display:flex;align-items:center;gap:4px;color:var(--muted,#9aa3b2)}
  .ib-filters input[type=number]{width:90px;padding:4px 6px;border-radius:8px;border:1px solid var(--border,rgba(255,255,255,.12));background:rgba(255,255,255,.06);color:var(--text,#eef3fb);font-size:12px}
  .ib-select{padding:6px 8px;border-radius:8px;border:1px solid #d0d4da;background:#ffffff;color:#111111;font-size:12px}
  .ib-select:focus{outline:2px solid #6da6ff; outline-offset:1px}
  .ib-select option{color:#111111;background:#ffffff}
  .ib-item{display:flex;align-items:center;gap:8px}
  .ib-item img{width:22px;height:22px;border-radius:6px;border:1px solid rgba(255,255,255,.1);background:#222}
  `; const st=document.createElement('style'); st.id='ib-base-styles'; st.textContent=css; document.head.appendChild(st); }
  function itemIcon(key){
    const k=(String(key||'').toLowerCase());
    const alias={
      'tp_scroll':'tpscroll','tpscroll':'tpscroll',
      'ward_observer':'ward_observer','ward_sentry':'ward_sentry','sentry_wards':'ward_sentry','observer_ward':'ward_observer','sentry_ward':'ward_sentry',
      'dust':'dust','dust_of_appearance':'dust',
      'rapier':'rapier','divine_rapier':'rapier'
    };
    const base=alias[k]||k;
    return `https://cdn.cloudflare.steamstatic.com/apps/dota2/images/items/${base}_lg.png`;
  }
  function mount(host, cfg){ injectStyles(); if(!host) return; const data = cfg&&cfg.data || {}; const meta = data.meta||{}; const items = Array.isArray(data.items)? data.items.map(it=>({
      item:it.item||it.name,
      name:it.name||it.item,
      count:Number(it.count||0),
      wins:Number(it.wins||0),
      wr:Number(it.wr||0),
      gold:Number(it.gold|| (meta[it.item||it.name] && meta[it.item||it.name].cost) || 0),
      role:it.role || (meta[it.item||it.name] && meta[it.item||it.name].role) || 'unknown',
      consumable: !!(it.consumable || (meta[it.item||it.name] && meta[it.item||it.name].consumable))
    })) : [];
    let state={ sort:'count', hideConsumables:false, minGold:0, minWr:0, role:'all' };
    function filtered(){ return items.filter(it=> (!state.hideConsumables || !it.consumable) && (it.gold>=state.minGold) && (it.wr>=state.minWr) && (state.role==='all' || (state.role==='core'? it.role!=='support' : it.role==='support')) ); }
    function sortArr(arr){ switch(state.sort){ case 'name': return arr.slice().sort((a,b)=> a.name.localeCompare(b.name)); case 'gold': return arr.slice().sort((a,b)=> (b.gold-a.gold)||(b.count-a.count)||a.name.localeCompare(b.name)); case 'count': default: return arr.slice().sort((a,b)=> (b.count-a.count)||(b.gold-a.gold)||a.name.localeCompare(b.name)); } }
    const root=h(`<div class='ib-wrapper'>
      <div class='ib-toolbar'>
        <button class='seg' data-sort='count'>Sort Count</button>
        <button class='seg' data-sort='gold'>Sort Gold</button>
        <button class='seg' data-sort='name'>Sort Name</button>
      </div>
      <div class='ib-filters'>
        <label><input type='checkbox' id='ibHideCons'> Hide Consumables</label>
        <label>Min Gold <input type='number' id='ibMinGold' min='0' step='100' value='0'></label>
        <label>Min WR % <input type='number' id='ibMinWr' min='0' max='100' step='1' value='0'></label>
        <select id='ibRole' class='ib-select'>
          <option value='all'>Alle Rollen</option>
          <option value='core'>Core</option>
          <option value='support'>Support</option>
        </select>
      </div>
      <div class='ib-grid'>
        <div class='ib-card'><h3 class='ib-title'>Items Bought</h3><ul class='ib-list' id='ibList'></ul></div>
      </div>
    </div>`);
    host.innerHTML=''; host.appendChild(root);
    function setActive(){ root.querySelectorAll('.ib-toolbar [data-sort]').forEach(b=> b.classList.toggle('active',(b.getAttribute('data-sort')||'')===state.sort)); }
    function pct(x){ return (Math.round(x*1000)/10).toFixed(1).replace(/\.0$/,'')+"%"; }
    function render(){ setActive(); const list=root.querySelector('#ibList'); if(!list) return; const arr = sortArr(filtered()); list.innerHTML = arr.length? arr.map(it=> `<li><span class='ib-item'><img src='${esc(itemIcon(it.item))}' alt=''><span>${esc(it.name)}</span></span><span style='display:flex;gap:6px;align-items:center'><span class='ib-badge'>x${it.count}</span>${it.wins||it.wr?`<span class='ib-badge'>WR ${esc(pct(it.wr||0))}</span>`:''}${it.gold?`<span class='ib-badge'>${it.gold}</span>`:''}${it.consumable?`<span class='ib-badge'>Cons</span>`:''}</span></li>`).join('') : `<li class='ib-empty'>Keine Items</li>`; }
    root.querySelector('.ib-toolbar').addEventListener('click', e=>{ const btn=e.target.closest('button.seg'); if(!btn) return; state.sort=btn.getAttribute('data-sort'); render(); });
    const hideCons = root.querySelector('#ibHideCons'); if(hideCons){ hideCons.addEventListener('change',()=>{ state.hideConsumables = !!hideCons.checked; render(); }); }
    const minGold = root.querySelector('#ibMinGold'); if(minGold){ minGold.addEventListener('input',()=>{ const v=parseInt(minGold.value||'0',10); state.minGold = isNaN(v)?0:v; render(); }); }
    const minWr = root.querySelector('#ibMinWr'); if(minWr){ minWr.addEventListener('input',()=>{ const v=parseFloat(minWr.value||'0'); state.minWr = isNaN(v)?0:Math.max(0,Math.min(100,v))/100; render(); }); }
    const roleSel = root.querySelector('#ibRole'); if(roleSel){ roleSel.addEventListener('change',()=>{ state.role = roleSel.value||'all'; render(); }); }
    render();
  }
  window.ItemsBoughtViewer = { mount };
})();

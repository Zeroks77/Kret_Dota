(function(){
  const LS_KEY = 'map_editor_state_v1';
  // When served from docs/, maps.json lives one level up at ../data/maps.json
  const MAPS_JSON = '../data/maps.json';
  const LOC_JSON = './data/map_locations.json';

  const $ = (sel,root=document)=>root.querySelector(sel);
  const $$ = (sel,root=document)=>Array.from(root.querySelectorAll(sel));

  function esc(s){ return String(s||'').replace(/[&<>"]|\n/g, c=>({
    '&':'&amp;','<':'&lt;','>':'&gt;','\n':'<br/>','"':'&quot;'
  })[c]||c); }

  const state = {
    patch: '',
    tool: 'select', // select|point|circle|polygon
    working: null, // current shape being edited
    selectedId: '',
    items: [], // {id,name,type,side,tags:[],notes, shape:{kind:'point'|'circle'|'polygon', points:[{x,y}], r?:number}, cx, cy}
    maps: null
  };

  function uid(){ return 'loc_' + Math.random().toString(36).slice(2,9); }

  function loadLS(){ try{ const s=localStorage.getItem(LS_KEY); if(!s) return; const obj=JSON.parse(s); Object.assign(state, obj); }catch(_){} }
  function saveLS(){ try{ localStorage.setItem(LS_KEY, JSON.stringify({ patch:state.patch, items:state.items })); }catch(_){} }

  async function fetchJSON(path){ const res = await fetch(path, {cache:'no-store'}); if(!res.ok) throw new Error('HTTP '+res.status); return res.json(); }

  function mapAssetFor(maps){
    // Graceful fallback when maps config is missing
    if(!maps || typeof maps !== 'object'){
      return { src: 'https://www.opendota.com/assets/images/dota2map/dota2map_full.jpg', bounds: null, cur: '' };
    }
    const cur = maps && maps.current;
    const major = maps && maps.major && maps.major[cur];
    const src = (major && major.src) || maps.default || 'https://www.opendota.com/assets/images/dota2map/dota2map_full.jpg';
    const bounds = major ? { minX:majormin(major.minX), minY:majormin(major.minY), maxX:majormax(major.maxX), maxY:majormax(major.maxY), invertY:!!major.invertY } : null;
    return { src, bounds, cur };
    function majormin(v){ return typeof v==='number'? v : undefined }
    function majormax(v){ return typeof v==='number'? v : undefined }
  }

  function setTool(tool){ state.tool = tool; $$('.toolbar .seg').forEach(b=> b.classList.toggle('active', b.dataset.tool===tool)); }

  function renderMap(){ const img=$('#mapImg'); if(!img) return; const conf = mapAssetFor(state.maps)||{}; if(conf && conf.src){ img.src = conf.src; } }

  function normFromClient(evt){ const svg=$('#svg'); const rect = svg.getBoundingClientRect(); const x = Math.max(0, Math.min(1, (evt.clientX-rect.left)/rect.width)); const y = Math.max(0, Math.min(1, (evt.clientY-rect.top)/rect.height)); return {x: +(x*100).toFixed(2), y: +(y*100).toFixed(2)}; }

  function draw(){ const svg=$('#svg'); svg.innerHTML='';
    for(const it of state.items){ const g = document.createElementNS('http://www.w3.org/2000/svg','g'); g.setAttribute('data-id', it.id);
      const selected = state.selectedId===it.id;
      if(selected) g.classList.add('g-selected');
      if(it.shape.kind==='point'){
        // halo (bigger ring) for selection
        if(selected){ const h = document.createElementNS('http://www.w3.org/2000/svg','circle'); h.setAttribute('cx', it.points[0].x+'%'); h.setAttribute('cy', it.points[0].y+'%'); h.setAttribute('r','2.4'); h.setAttribute('class','g-sel-halo'); g.appendChild(h); }
        const c = document.createElementNS('http://www.w3.org/2000/svg','circle');
        c.setAttribute('cx', it.points[0].x+'%'); c.setAttribute('cy', it.points[0].y+'%'); c.setAttribute('r','1.2'); c.setAttribute('class','g-point'); g.appendChild(c);
      } else if(it.shape.kind==='circle'){
        const cx=it.points[0].x, cy=it.points[0].y, r=it.shape.r||4;
        if(selected){ const h = document.createElementNS('http://www.w3.org/2000/svg','circle'); h.setAttribute('cx', cx+'%'); h.setAttribute('cy', cy+'%'); h.setAttribute('r', (r+1.2)+''); h.setAttribute('class','g-sel-halo'); g.appendChild(h); }
        const circ = document.createElementNS('http://www.w3.org/2000/svg','circle');
        circ.setAttribute('cx', cx+'%'); circ.setAttribute('cy', cy+'%'); circ.setAttribute('r', r+''); circ.setAttribute('class','g-circle'); g.appendChild(circ);
      } else if(it.shape.kind==='polygon'){
        const pts = it.points.map(p=> `${p.x},${p.y}`).join(' ');
        if(selected){ const halo = document.createElementNS('http://www.w3.org/2000/svg','polygon'); halo.setAttribute('points', pts); halo.setAttribute('class','g-sel-halo poly'); g.appendChild(halo); }
        const poly = document.createElementNS('http://www.w3.org/2000/svg','polygon');
        poly.setAttribute('points', pts); poly.setAttribute('class','g-poly'); g.appendChild(poly);
      }
      svg.appendChild(g);
    }
  }

  function refreshList(){ const box=$('#items'); const q = ($('#search').value||'').toLowerCase(); const ftype = $('#filterType').value||''; const list = state.items.filter(it=> !ftype || it.type===ftype).filter(it=>{
      const hay = [it.name, it.type, it.side, (it.tags||[]).join(',')].join(' ').toLowerCase(); return hay.includes(q);
    }).sort((a,b)=> String(a.name||'').localeCompare(String(b.name||'')));
    if(!list.length){ box.innerHTML = `<div class="sub">No items</div>`; return; }
    box.innerHTML = list.map(it=>{
      const tags = (it.tags||[]).map(t=>`<span class="badge">${esc(t)}</span>`).join(' ');
      return `<div class="item ${state.selectedId===it.id?'active':''}" data-id="${esc(it.id)}"><div><div><b>${esc(it.name||'')}</b></div><div class="sub">${esc(it.type)} ${it.side? '· '+esc(it.side):''}</div><div class="badges" style="margin-top:4px">${tags}</div></div><div class="sub">${it.shape.kind}</div></div>`;
    }).join('');
  }

  function pick(id){ state.selectedId = id||''; const it = state.items.find(x=> x.id===id) || null; if(!it) return bindProps(null); bindProps(it); draw(); refreshList(); }

  function bindProps(it){ $('#name').value = it? (it.name||'') : ''; $('#type').value = it? (it.type||'objective') : 'objective'; $('#side').value = it? (it.side||'') : ''; $('#tags').value = it? (it.tags||[]).join(',') : ''; $('#notes').value = it? (it.notes||'') : ''; const info=$('#shapeInfo'); if(!it){ info.innerHTML=''; return; } const sp = [];
    if(it.shape.kind==='point') sp.push(`<span class="badge">point [${it.points[0].x},${it.points[0].y}]</span>`);
    if(it.shape.kind==='circle') sp.push(`<span class="badge">center [${it.points[0].x},${it.points[0].y}]</span>`, `<span class="badge">r ${it.shape.r||4}%</span>`);
    if(it.shape.kind==='polygon') sp.push(`<span class="badge">${it.points.length} points</span>`);
    info.innerHTML = sp.join(' ');
  }

  function saveFromProps(){ const id = state.selectedId || uid(); let it = state.items.find(x=> x.id===id); if(!it){
      // initialize with a point at center if new
      it = { id, name: '', type: $('#type').value||'objective', side: $('#side').value||'', tags: [], notes:'', shape:{kind:'point', r:4}, points:[{x:50,y:50}] };
      state.items.push(it);
    }
    it.name = $('#name').value||''; it.type = $('#type').value||'objective'; it.side = $('#side').value||''; it.tags = ($('#tags').value||'').split(',').map(s=>s.trim()).filter(Boolean); it.notes = $('#notes').value||'';
    state.selectedId = it.id; saveLS(); draw(); refreshList(); }

  function delSelected(){ const id=state.selectedId; if(!id) return; const idx = state.items.findIndex(x=> x.id===id); if(idx>=0) state.items.splice(idx,1); state.selectedId=''; saveLS(); draw(); refreshList(); bindProps(null); }

  function onMapClick(evt){ const tool = state.tool; const pt = normFromClient(evt); if(tool==='select'){ // select nearest
      let best=null, bestD=1e9; for(const it of state.items){ if(!it.points||!it.points.length) continue; const p = it.points[0]; const d = Math.hypot((p.x-pt.x),(p.y-pt.y)); if(d<bestD){ bestD=d; best=it; } }
      if(best) pick(best.id); return; }
    if(tool==='point'){
      const it = { id: uid(), name:'', type: $('#category').value||'poi', side:'', tags:[], notes:'', shape:{kind:'point'}, points:[pt] };
      state.items.push(it); state.selectedId = it.id; saveLS(); draw(); refreshList(); bindProps(it); return;
    }
    if(tool==='circle'){
      if(!state.working){ state.working = { kind:'circle', start:pt };
      } else {
        // finalize
        const cx=state.working.start.x, cy=state.working.start.y; const r = Math.min(20, +(Math.hypot(pt.x-cx, pt.y-cy).toFixed(2)));
        const it={ id:uid(), name:'', type: $('#category').value||'camp', side:'', tags:[], notes:'', shape:{kind:'circle', r}, points:[{x:cx,y:cy}] };
        state.items.push(it); state.selectedId=it.id; state.working=null; saveLS(); draw(); refreshList(); bindProps(it);
      }
      return;
    }
    if(tool==='polygon'){
      if(!state.working){ state.working = { kind:'polygon', pts:[pt] };
      } else {
        // Add a point; finishing is handled by dblclick/Enter for reliability
        const w = state.working; w.pts.push(pt); drawWorking();
      }
      return;
    }
  }

  function drawWorking(){ const svg=$('#svg'); // redraw full for simplicity
    draw(); const w = state.working; if(!w) return; if(w.kind==='circle'){
      const cx=w.start.x, cy=w.start.y; const cursor = state.cursor || {x:cx,y:cy}; const r = Math.min(20, +(Math.hypot(cursor.x-cx, cursor.y-cy).toFixed(2)));
      const circ = document.createElementNS('http://www.w3.org/2000/svg','circle'); circ.setAttribute('cx',cx+'%'); circ.setAttribute('cy', cy+'%'); circ.setAttribute('r', r+''); circ.setAttribute('class','g-circle g-selected'); svg.appendChild(circ);
    } else if(w.kind==='polygon'){
      const pts = w.pts.concat(state.cursor? [state.cursor] : []).map(p=> `${p.x},${p.y}`).join(' ');
      const poly = document.createElementNS('http://www.w3.org/2000/svg','polyline'); poly.setAttribute('points', pts); poly.setAttribute('class','g-poly g-selected'); svg.appendChild(poly);
      // handles
      for(const p of w.pts){ const c = document.createElementNS('http://www.w3.org/2000/svg','circle'); c.setAttribute('cx',p.x+'%'); c.setAttribute('cy',p.y+'%'); c.setAttribute('r','0.8'); c.setAttribute('class','g-handle'); svg.appendChild(c); }
    }
  }

  function onMapMove(evt){ state.cursor = normFromClient(evt); if(state.working) drawWorking(); }

  function exportJSON(){ const obj = { patch: state.maps && state.maps.current || '', items: state.items };
    const blob = new Blob([JSON.stringify(obj,null,2)], {type:'application/json'});
    const url = URL.createObjectURL(blob); const a=document.createElement('a'); a.href=url; a.download='map_locations.json'; a.click(); setTimeout(()=> URL.revokeObjectURL(url), 500);
  }

  async function importJSON(){ try{ const input=document.createElement('input'); input.type='file'; input.accept='application/json'; input.onchange=async()=>{ const f=input.files[0]; if(!f) return; const txt = await f.text(); const obj = JSON.parse(txt); if(Array.isArray(obj.items)) state.items = obj.items; saveLS(); draw(); refreshList(); }; input.click(); }catch(e){ console.error(e); }
  }

  function toWardViewerObjectives(){ // convert points/circles centers tagged as objectives/towers/roshan into [{x,y,type}]
    const objs=[]; for(const it of state.items){ if(it.type!=='objective') continue; if(!it.points||!it.points.length) continue; const p=it.points[0]; const type=(it.tags||[])[0]||'objective'; objs.push({ x:p.x, y:p.y, type }); }
    return objs;
  }

  function exportClipboard(){ try{ const data = { objectives: toWardViewerObjectives() }; navigator.clipboard.writeText(JSON.stringify(data)); alert('Copied objectives JSON for Ward Viewer to clipboard'); }catch(e){ console.error(e); }
  }

  async function load(){
    loadLS();
    try{ state.maps = await fetchJSON(MAPS_JSON); }catch(e){ console.warn('maps.json load failed', e); state.maps = null; }
    // patch select
    const sel=$('#patch');
    if(sel){
      const maps=state.maps||{}; const cur = maps.current || '';
      const majors = (maps && maps.major) ? maps.major : {};
      const keys = Object.keys(majors);
      if(keys.length){
        sel.innerHTML = keys.map(k=>`<option value="${k}" ${k===cur?'selected':''}>${k}</option>`).join('');
        if(!sel.value && cur) sel.value = cur;
      } else {
        // Fallback single option
        sel.innerHTML = `<option value="">Default</option>`;
        sel.value = '';
      }
      sel.addEventListener('change', ()=>{ if(!state.maps) state.maps = { current: sel.value, major:{}, default:'https://www.opendota.com/assets/images/dota2map/dota2map_full.jpg' }; else state.maps.current = sel.value; renderMap(); });
    }
    renderMap(); draw(); refreshList(); bindProps(null);
  }

  function bindUI(){ $$('.toolbar .seg').forEach(b=> b.addEventListener('click', ()=> setTool(b.dataset.tool)) ); setTool('select');
    $('#map').addEventListener('click', onMapClick); $('#map').addEventListener('mousemove', onMapMove);
    // Finish polygon reliably on double-click
    $('#map').addEventListener('dblclick', (e)=>{
      const w = state.working; if(!w || w.kind!=='polygon') return;
      if(w.pts.length>=3){ const it={ id:uid(), name:'', type: $('#category').value||'region', side:'', tags:[], notes:'', shape:{kind:'polygon'}, points:w.pts.slice() };
        state.items.push(it); state.selectedId=it.id; state.working=null; saveLS(); draw(); refreshList(); bindProps(it); }
      e.preventDefault();
    });
    // Keyboard shortcuts: Enter=finish, Esc=cancel, Delete=delete, Ctrl+Z=undo point
    function isTypingTarget(el){
      if(!el) return false; const tag = String(el.tagName||'').toLowerCase();
      if(tag==='input' || tag==='textarea' || tag==='select') return true;
      if(el.isContentEditable) return true;
      return false;
    }
    document.addEventListener('keydown', (e)=>{
      // Do not intercept when typing in form fields
      if(isTypingTarget(e.target)) return;
      const w = state.working;
      if(e.key==='Enter'){
        if(w && w.kind==='polygon' && w.pts.length>=3){ const it={ id:uid(), name:'', type: $('#category').value||'region', side:'', tags:[], notes:'', shape:{kind:'polygon'}, points:w.pts.slice() };
          state.items.push(it); state.selectedId=it.id; state.working=null; saveLS(); draw(); refreshList(); bindProps(it); e.preventDefault(); return; }
        if(w && w.kind==='circle'){
          const cx=w.start.x, cy=w.start.y; const cur=state.cursor||{x:cx,y:cy}; const r = Math.min(20, +(Math.hypot(cur.x-cx, cur.y-cy).toFixed(2)));
          const it={ id:uid(), name:'', type: $('#category').value||'camp', side:'', tags:[], notes:'', shape:{kind:'circle', r}, points:[{x:cx,y:cy}] };
          state.items.push(it); state.selectedId=it.id; state.working=null; saveLS(); draw(); refreshList(); bindProps(it); e.preventDefault(); return;
        }
      }
      if(e.key==='Escape'){
        if(w){ state.working=null; draw(); e.preventDefault(); return; }
        if(state.selectedId){ state.selectedId=''; bindProps(null); draw(); refreshList(); e.preventDefault(); return; }
      }
      if(e.key==='Delete'){
        if(state.selectedId){ delSelected(); e.preventDefault(); return; }
      }
      if((e.ctrlKey||e.metaKey) && (e.key==='z' || e.key==='Z')){
        if(w && w.kind==='polygon' && w.pts.length>1){ w.pts.pop(); drawWorking(); e.preventDefault(); return; }
      }
    });
    $('#save').addEventListener('click', saveFromProps); $('#new').addEventListener('click', ()=>{ state.selectedId=''; bindProps(null); }); $('#remove').addEventListener('click', delSelected);
    $('#btnExport').addEventListener('click', exportClipboard); $('#btnDownload').addEventListener('click', exportJSON); $('#btnImport').addEventListener('click', importJSON);
    $('#items').addEventListener('click', (e)=>{ const it=e.target.closest('.item'); if(!it) return; pick(it.getAttribute('data-id')); });
    $('#name').addEventListener('change', saveFromProps); $('#type').addEventListener('change', saveFromProps); $('#side').addEventListener('change', saveFromProps); $('#tags').addEventListener('change', saveFromProps); $('#notes').addEventListener('change', saveFromProps);
    $('#search').addEventListener('input', refreshList); $('#filterType').addEventListener('change', refreshList);
  }

  document.addEventListener('DOMContentLoaded', ()=>{ bindUI(); load(); });
})();

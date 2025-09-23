// Shared URL params utility: normalize aliases to canonical keys and optionally rewrite URL in-place
(function(global){
  'use strict';
  const aliasMap = {
    // canonical -> aliases
    tab: ['section'],
    range: ['days'],
    from: ['start','since'],
    to: ['end','until'],
    aid: ['account','player','account_id','accountId','wplayer'],
    uonly: ['useronly','only','userOnly'],
    ui: ['lock','readonly'],
    pcA: ['pca','compareA','cmpA'],
    pcB: ['pcb','compareB','cmpB'],
    side: ['team','faction','wteam'],
    league: ['l','slug'],
    leaguePath: ['path'],
    // Ward viewer: keep canonical keys but accept friendlier aliases
    wspot: ['spot'],
    wpins: ['pins']
  };
  const canonicalKeys = Object.keys(aliasMap);
  const allAliases = new Map(); // alias -> canonical
  for(const canon of canonicalKeys){
    allAliases.set(canon.toLowerCase(), canon);
    for(const a of aliasMap[canon]){ allAliases.set(String(a).toLowerCase(), canon); }
  }
  function normalize(params){
    const out = new URLSearchParams();
    const tmp = new URLSearchParams(params);
    for(const [k,v] of tmp.entries()){
      const canon = allAliases.get(String(k).toLowerCase()) || k;
      // If duplicate via alias, prefer first seen canonical value; skip if already present
      if(!out.has(canon)) out.set(canon, v);
    }
    return out;
  }
  function canonicalizeInPlace(){
    try{
      const sp = normalize(location.search);
      const url = location.pathname + (sp.toString()? ('?'+sp.toString()):'') + location.hash;
      if(url !== location.href){ history.replaceState(null, '', url); }
      return sp;
    }catch(_e){ return new URLSearchParams(location.search); }
  }
  function getCanonical(){
    try{ return normalize(location.search); }catch(_e){ return new URLSearchParams(location.search); }
  }
  global.UrlParams = { normalize, canonicalizeInPlace, getCanonical, aliasMap };
})(window);

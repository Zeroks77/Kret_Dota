param(
  [int]$DelayMs = 1000,
  [int]$MaxRetries = 3,
  [int]$HttpTimeoutSec = 30,
  [string]$SteamApiKey,
  [bool]$PromptForSteamKey = $false,
  [object]$UpdateConstants = $true,
  [object]$FetchMatches    = $true,
  [object]$DiscoverMatches = $true,     # Discover league matches (Steam-only)
  [object]$UpdateShards    = $true,     # Write/merge simplified records into data/matches/YYYY-MM.json
  [object]$UpdateManifest  = $true,     # Rebuild data/manifest.json from shards
  [object]$RequestParse    = $false,    # Request OpenDota parse for up to -MaxParseRequests matches lacking enriched data
  [int]$MaxParseRequests = 50,
  [int]$ParseAttemptsPerMatch = 0,      # If >0, attempt this many parse requests per match that needs it
  [int]$ParseDelaySec = 30,             # Delay between parse attempts per match
  [int]$TeamDiscoveryRecentMonths = 2,  # Limit team discovery to the most recent N month shards
  [int]$TeamDiscoveryMaxTeams = 24,     # Cap number of teams to query via team endpoints
  [object]$SanitizeCache   = $false,    # Rewrite cached files to drop image fields that trigger false positives
  [bool]$DiscoverViaSteam = $true,
  [bool]$DiscoverViaOpenDota = $false,
  [bool]$DiscoverViaTeams = $false,
  [bool]$ForceRefetch = $false,
  [bool]$SkipFinalEnsure = $false,      # If true, skip the expensive final ensure pass across all cached matches
  [int]$ParseBudgetSec = 180,           # Hard cap on total seconds spent issuing parse requests
  [bool]$LeagueOnly = $true,            # Enforce league-only behavior for sharding/backfill
  [ValidateSet('default','discover','full','sanitize')][string]$Mode = 'default'
)

<#
  Fetches OpenDota constants (heroes, patch) and downloads missing
  match details for IDs referenced in data/matches/*.json (and optional
  data/allgames_parsed.json).

  Output:
   - data/cache/OpenDota/constants/heroes.json
   - data/cache/OpenDota/constants/patch.json
   - data/cache/OpenDota/matches/<match_id>.json

  Notes:
   - Idempotent; re-downloads only when a cache file is missing.
   - Uses conservative throttling (DelayMs) and small retry loop.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Ensure TLS 1.2 to avoid handshake glitches
try{ [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 }catch{}


function Get-RepoRoot(){ (Resolve-Path "$PSScriptRoot\.." | Select-Object -ExpandProperty Path) }
function Get-DataPath(){ Join-Path (Get-RepoRoot) 'data' }
function Ensure-Dir([string]$path){ $dir=[System.IO.Path]::GetDirectoryName($path); if($dir -and -not (Test-Path -LiteralPath $dir)){ New-Item -ItemType Directory -Path $dir -Force | Out-Null } }
function Read-JsonFile([string]$path){ if(-not (Test-Path -LiteralPath $path)){ return $null } try{ Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null } }
function Save-Json([object]$obj,[string]$path){
  Ensure-Dir $path
  try{
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $json = ($obj | ConvertTo-Json -Depth 100 -Compress)
    $sw.Stop(); $ser = $sw.ElapsedMilliseconds
    $sw.Restart()
    Set-Content -LiteralPath $path -Encoding UTF8 -NoNewline -Value $json
    $sw.Stop(); $wr = $sw.ElapsedMilliseconds
    Write-Log ("Save-Json: serialized in {0} ms, wrote in {1} ms -> {2}" -f $ser, $wr, $path)
  } catch {
    Write-Warning ("Save-Json failed for {0}: {1}" -f $path, (Format-HttpError $_))
    throw
  }
}

function Get-LeagueId(){ $info = Read-JsonFile (Join-Path (Get-DataPath) 'info.json'); try { return [int]$info.league_id } catch { return 0 } }

function Get-MatchLeagueId($md){
  try{
    if($null -eq $md){ return 0 }
    $val = $null
    try{ $val = $md.leagueid }catch{}
    if($null -ne $val -and [string]$val -ne ''){ try { return [int]$val } catch { return 0 } }
    if($md.league){
      try{ if($md.league.leagueid){ return [int]$md.league.leagueid } }catch{}
      try{ if($md.league.id){ return [int]$md.league.id } }catch{}
    }
    return 0
  } catch { return 0 }
}

function Invoke-Json([string]$Method,[string]$Uri){
  $backoff = 600
  for($i=1; $i -le $MaxRetries; $i++){
    try {
  return Invoke-RestMethod -Method $Method -Uri $Uri -Headers @{ 'Accept'='application/json'; 'User-Agent'='kret-dota-fetcher/1.0' } -TimeoutSec $HttpTimeoutSec -ErrorAction Stop
    } catch {
      $logUri = Sanitize-Uri $Uri
      Write-Warning ("HTTP {0} {1} failed (attempt {2}/{3}): {4}" -f $Method, $logUri, $i, $MaxRetries, (Format-HttpError $_))
      if ($i -ge $MaxRetries) { throw }
      Start-Sleep -Milliseconds $backoff
      $backoff = [Math]::Min($backoff*2, 5000)
    }
  }
}

function Write-Log([string]$msg){
  try{ $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); Write-Host ("[{0}] {1}" -f $ts, $msg) }catch{ Write-Host $msg }
}
function Sanitize-Uri([string]$u){
  if([string]::IsNullOrWhiteSpace($u)){ return $u }
  try{ return ($u -replace '(?i)(key=)([^&]+)','$1***') }catch{ return $u }
}

function Format-HttpError($err){
  try{
    $msg = ''
    try{ $msg = [string]$err.Exception.Message }catch{}
    $status = $null; $reason = $null
    try{ if($err.Exception.Response -and $err.Exception.Response.StatusCode){ $status = [int]$err.Exception.Response.StatusCode } }catch{}
    try{ if($err.Exception.Response -and $err.Exception.Response.StatusDescription){ $reason = [string]$err.Exception.Response.StatusDescription } }catch{}
    $detail = $null
    try{ if($err.ErrorDetails -and $err.ErrorDetails.Message){ $detail = ($err.ErrorDetails.Message -replace '\s+',' '); if($detail.Length -gt 300){ $detail = $detail.Substring(0,300)+'…' } } }catch{}
    $parts = @()
    if($status){ $parts += ("status="+$status) }
    if($reason){ $parts += ("reason='"+$reason+"'") }
    if($msg){ $parts += ("msg='"+$msg+"'") }
    if($detail){ $parts += ("detail='"+$detail+"'") }
    return ($parts -join ', ')
  } catch { return '' }
}

function To-Bool($v, [bool]$default){
  if($null -eq $v){ return $default }
  if($v -is [bool]){ return [bool]$v }
  try{
    $s = [string]$v
    if([string]::IsNullOrWhiteSpace($s)){ return $default }
    switch -Regex ($s.Trim().ToLowerInvariant()){
      '^(true|1|yes|on)$'  { return $true }
      '^(false|0|no|off)$' { return $false }
      default { return $default }
    }
  } catch { return $default }
}

function Update-Constants(){
  $data = Get-DataPath
  $constDir = Join-Path $data 'cache/OpenDota/constants'
  if(-not (Test-Path -LiteralPath $constDir)){ New-Item -ItemType Directory -Path $constDir -Force | Out-Null }

  Write-Log 'Fetching OpenDota constants: heroes'
  try{
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $heroes = Invoke-Json -Method GET -Uri 'https://api.opendota.com/api/constants/heroes'
    if($heroes){ Save-Json -obj $heroes -path (Join-Path $constDir 'heroes.json'); Set-Content -LiteralPath (Join-Path $data 'heroes.json') -Value (($heroes | ConvertTo-Json -Depth 50)) -Encoding UTF8 }
    $sw.Stop(); Write-Log ("Fetched heroes in {0} ms" -f $sw.ElapsedMilliseconds)
  } catch {
    Write-Warning ("Failed to fetch constants: heroes: {0}" -f (Format-HttpError $_))
  }
  Write-Log ("Throttle: sleeping {0} ms after constants/heroes" -f $DelayMs)
  Start-Sleep -Milliseconds $DelayMs

  Write-Log 'Fetching OpenDota constants: patch'
  try{
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $patch = Invoke-Json -Method GET -Uri 'https://api.opendota.com/api/constants/patch'
    if($patch){ Save-Json -obj $patch -path (Join-Path $constDir 'patch.json') }
    $sw.Stop(); Write-Log ("Fetched patch in {0} ms" -f $sw.ElapsedMilliseconds)
  } catch {
    Write-Warning ("Failed to fetch constants: patch: {0}" -f (Format-HttpError $_))
  }
}

function Remove-KeysByName($obj, [string[]]$names){
  if($null -eq $obj){ return }
  if($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [string])){
    foreach($it in @($obj)){ Remove-KeysByName -obj $it -names $names }
    return
  }
  if($obj.PSObject){
    foreach($n in $names){ if($obj.PSObject.Properties.Match($n).Count -gt 0){ try{ $null = $obj.PSObject.Properties.Remove($n) }catch{} } }
    foreach($p in @($obj.PSObject.Properties.Name)){
      try{ Remove-KeysByName -obj $obj.$p -names $names }catch{}
    }
  }
}

function Sanitize-MatchObject($obj){
  try{
    # Heuristic: OpenDota match objects have match_id and players; they generally don't include image_* fields.
    # To avoid expensive deep recursion (and potential hangs), skip sanitize for matches.
    if($obj -and $obj.PSObject){
      $hasMatchId = $obj.PSObject.Properties.Match('match_id').Count -gt 0
      $hasPlayers = $obj.PSObject.Properties.Match('players').Count -gt 0
      if($hasMatchId -and $hasPlayers){ return $obj }
    }
    # For smaller objects (e.g., constants), perform targeted removal
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Remove-KeysByName -obj $obj -names @('image_path','image_inventory')
    $sw.Stop()
    if($sw.ElapsedMilliseconds -gt 1000){ Write-Log ("Sanitize-MatchObject took {0} ms (non-match object)" -f $sw.ElapsedMilliseconds) }
    return $obj
  } catch { return $obj }
}

function Sanitize-ExistingCache(){
  $data = Get-DataPath
  $dir = Join-Path $data 'cache/OpenDota/matches'
  if(-not (Test-Path -LiteralPath $dir)){ return }
  $files = Get-ChildItem -LiteralPath $dir -Filter '*.json' -File
  $i=0; foreach($f in $files){
    try{
      $txt = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
      if([string]::IsNullOrWhiteSpace($txt)){ continue }
      $obj = $txt | ConvertFrom-Json
      if($null -eq $obj){ continue }
      $obj = Sanitize-MatchObject $obj
      Save-Json -obj $obj -path $f.FullName
      $i++
    } catch {}
  }
  Write-Log ("Sanitized {0} cached match files" -f $i)
}

function Get-MatchIdCandidates(){
  $data = Get-DataPath
  $ids = New-Object System.Collections.Generic.HashSet[int64]
  $matchesDir = Join-Path $data 'matches'
  if(Test-Path -LiteralPath $matchesDir){
    Get-ChildItem -LiteralPath $matchesDir -Filter '*.json' | ForEach-Object {
      try {
        $raw = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
        if([string]::IsNullOrWhiteSpace($raw)){ return }
        $json = $raw | ConvertFrom-Json
        if($json -is [System.Collections.IEnumerable]){
          foreach($it in $json){
            try {
              if($it -is [int64] -or $it -is [int]){ [void]$ids.Add([int64]$it) }
              elseif($it -and $it.PSObject.Properties.Name -contains 'match_id') { [void]$ids.Add([int64]$it.match_id) }
            } catch {}
          }
        }
      } catch {}
    }
  }
  $parsed = Join-Path $data 'allgames_parsed.json'
  if(Test-Path -LiteralPath $parsed){
    try {
      $arr = Get-Content -LiteralPath $parsed -Raw -Encoding UTF8 | ConvertFrom-Json
      if($arr -is [System.Collections.IEnumerable]){
        foreach($x in $arr){ try { [void]$ids.Add([int64]$x) } catch {} }
      }
    } catch {}
  }
  $out = New-Object System.Collections.Generic.List[int64]
  foreach($v in $ids){ [void]$out.Add([int64]$v) }
  return ($out.ToArray() | Sort-Object)
}

function Fetch-MissingMatches(){
  if($LeagueOnly){ Write-Log 'Skipping Fetch-MissingMatches due to -LeagueOnly'; return }
  $data = Get-DataPath
  $cacheDir = Join-Path $data 'cache/OpenDota/matches'
  if(-not (Test-Path -LiteralPath $cacheDir)){ New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }

  $ids = @(Get-MatchIdCandidates)
  $count = ($ids | Measure-Object).Count
  Write-Log ("Found {0} candidate match IDs" -f $count)
  if($count -le 0){ return }

  $i=0
  foreach($id in $ids){
    $i++
    $outFile = Join-Path $cacheDir ("{0}.json" -f $id)
    if(Test-Path -LiteralPath $outFile){ continue }
    Write-Log ("[{0}/{1}] Fetching match {2}" -f $i, $ids.Count, $id)
    try {
    $uri = ("https://api.opendota.com/api/matches/{0}" -f $id)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $obj = Invoke-Json -Method GET -Uri $uri
    $sw.Stop(); Write-Log ("HTTP GET ok for {0} in {1} ms" -f $id, $sw.ElapsedMilliseconds)
    if($obj){
      Write-Log ("Sanitizing match {0}" -f $id)
      $tm = [System.Diagnostics.Stopwatch]::StartNew()
      $obj = Sanitize-MatchObject $obj
      $tm.Stop(); Write-Log ("Sanitize done for {0} in {1} ms" -f $id, $tm.ElapsedMilliseconds)
      Save-Json -obj $obj -path $outFile
      try{ $sz = (Get-Item -LiteralPath $outFile).Length }catch{ $sz = 0 }
      Write-Log ("Saved cache for {0} ({1} bytes)" -f $id, $sz)
    }
    } catch {
    Write-Warning ("Failed to fetch match {0} (uri={1}): {2}" -f $id, (Sanitize-Uri $uri), (Format-HttpError $_))
    }
    Write-Log ("Throttle: sleeping {0} ms after match fetch" -f $DelayMs)
    Start-Sleep -Milliseconds $DelayMs
  }
}

function Discover-MatchIdsFromSteam(){
  $key = $env:STEAM_API_KEY
  $leagueId = Get-LeagueId
  if([string]::IsNullOrWhiteSpace($key) -or $leagueId -le 0){ Write-Log 'Skipping Steam discovery (missing STEAM_API_KEY or league_id)'; return @() }
  $funcStart = Get-Date
  Write-Log ("Discovering matches via Steam for league_id={0}" -f $leagueId)
  $base = 'https://api.steampowered.com/IDOTA2Match_570/GetMatchHistory/V001/'
  $all = New-Object System.Collections.Generic.List[object]
  $startAt = $null
  for($page=1; $page -le 50; $page++){
    $qs = @{ key=$key; league_id=$leagueId; matches_requested=100 }
    if($startAt){ $qs.start_at_match_id = $startAt }
    $uri = $base + '?' + ($qs.GetEnumerator() | ForEach-Object { [uri]::EscapeDataString($_.Name) + '=' + [uri]::EscapeDataString([string]$_.Value) } | Out-String).Trim().Replace("`r`n",'&')
    try{
  $resp = Invoke-Json -Method GET -Uri $uri
  $pageMatches = $resp.result.matches
  if(-not $pageMatches -or $pageMatches.Count -eq 0){ break }
  foreach($m in $pageMatches){ $all.Add([int64]$m.match_id) | Out-Null }
  $minId = ($pageMatches | Measure-Object -Property match_id -Minimum).Minimum
      if(-not $minId){ break }
      $startAt = [int64]$minId - 1
      Write-Log ("Throttle: sleeping {0} ms between Steam pages" -f $DelayMs)
      Start-Sleep -Milliseconds $DelayMs
    } catch {
      Write-Warning ("Steam discovery failed on page {0} (uri={1}): {2}" -f $page, (Sanitize-Uri $uri), (Format-HttpError $_))
      break
    }
  }
  $ids = @($all.ToArray() | Sort-Object -Unique)
  $cnt = (($ids | Measure-Object).Count)
  $dur = ((Get-Date) - $funcStart).TotalSeconds
  Write-Log ("Discovered {0} match IDs via Steam in {1:n1}s" -f $cnt, $dur)
  return $ids
}

function Get-LatestShardStartTime(){
  $data = Get-DataPath
  $dir = Join-Path $data 'matches'
  $latest = 0
  if(Test-Path -LiteralPath $dir){
    Get-ChildItem -LiteralPath $dir -Filter '*.json' | ForEach-Object {
      try{
        $arr = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach($r in $arr){ $st = 0; try { $st = [int64]$r.start_time } catch { $st = 0 } if($st -gt $latest){ $latest = $st } }
      } catch {}
    }
  }
  return [int64]$latest
}

function Discover-MatchIdsFromOpenDota(){
  $leagueId = Get-LeagueId
  if($leagueId -le 0){ return @() }
  Write-Log ("Discovering matches via OpenDota for league_id={0}" -f $leagueId)
  $uri = ("https://api.opendota.com/api/leagues/{0}/matches" -f $leagueId)
  try{
  $resp = Invoke-Json -Method GET -Uri $uri
    $cut = Get-LatestShardStartTime
    $ids = New-Object System.Collections.Generic.List[int64]
    foreach($m in $resp){
      try{
        $mid = 0; try { $mid = [int64]$m.match_id } catch { $mid = 0 }
        $st  = 0; try { $st = [int64]$m.start_time } catch { $st = 0 }
        # If start_time missing, include; otherwise include only newer than cutoff
        if($mid -gt 0 -and ($st -eq 0 -or $cut -le 0 -or $st -gt $cut)){
          [void]$ids.Add($mid)
        }
      } catch {}
    }
    $arr = $ids.ToArray() | Sort-Object -Unique
    Write-Log ("OpenDota discovery returned {0} candidates (cutoff={1})" -f $arr.Count, $cut)
    return $arr
  } catch {
    Write-Warning ("OpenDota league discovery failed (uri={0}): {1}" -f (Sanitize-Uri $uri), (Format-HttpError $_))
    return @()
  }
}

function Get-KnownTeamIds(){
  $data = Get-DataPath
  $dir = Join-Path $data 'matches'
  $set = New-Object System.Collections.Generic.HashSet[int]
  if(Test-Path -LiteralPath $dir){
    # Read only the most recent N month shards to keep CI runs fast
    $files = Get-ChildItem -LiteralPath $dir -Filter '*.json' | Sort-Object Name -Descending
    if($TeamDiscoveryRecentMonths -gt 0){ $files = $files | Select-Object -First $TeamDiscoveryRecentMonths }
    foreach($file in $files){
      try{
        $arr = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach($r in $arr){
          try{ [void]$set.Add([int]$r.radiant_team_id) }catch{}
          try{ [void]$set.Add([int]$r.dire_team_id) }catch{}
        }
      } catch {}
    }
  }
  $out = New-Object System.Collections.Generic.List[int]
  foreach($v in $set){ if($v -gt 0){ [void]$out.Add([int]$v) } }
  return $out.ToArray() | Sort-Object -Unique
}

function Discover-MatchIdsFromTeams(){
  $leagueId = Get-LeagueId
  if($leagueId -le 0){ return @() }
  $teamIds = @(Get-KnownTeamIds)
  if((($teamIds | Measure-Object).Count) -eq 0){ return @() }
  # Hard-cap number of teams to query to keep runtime bounded
  if($TeamDiscoveryMaxTeams -gt 0 -and (($teamIds | Measure-Object).Count) -gt $TeamDiscoveryMaxTeams){
    $teamIds = $teamIds | Select-Object -First $TeamDiscoveryMaxTeams
  }
  Write-Log ("Discovering matches via team endpoints for {0} teams (league_id={1})" -f (($teamIds | Measure-Object).Count), $leagueId)
  $list = New-Object System.Collections.Generic.List[int64]
  foreach($tid in $teamIds){
    $uri = ("https://api.opendota.com/api/teams/{0}/matches" -f $tid)
  try{
  $resp = Invoke-Json -Method GET -Uri $uri
    $resp = @($resp)
    foreach($m in ($resp | Where-Object { $_.leagueid -eq $leagueId })){
        try{ $mid = [int64]$m.match_id; if($mid -gt 0){ [void]$list.Add($mid) } }catch{}
      }
  } catch { Write-Warning ("Team matches fetch failed for team {0} (uri={1}): {2}" -f $tid, (Sanitize-Uri $uri), (Format-HttpError $_)) }
    Start-Sleep -Milliseconds $DelayMs
  }
  $ids = $list.ToArray() | Sort-Object -Unique
  $idsCount = (($ids | Measure-Object).Count)
  Write-Log ("Team discovery returned {0} candidates" -f $idsCount)
  return $ids
}

function Get-CachedMatchObjects(){
  $data = Get-DataPath
  $dir = Join-Path $data 'cache/OpenDota/matches'
  if(-not (Test-Path -LiteralPath $dir)){ return @() }
  $list = New-Object System.Collections.Generic.List[object]
  Get-ChildItem -LiteralPath $dir -Filter '*.json' | ForEach-Object {
    try{ $obj = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json; if($obj){ $list.Add($obj) | Out-Null } } catch {}
  }
  return $list.ToArray()
}

function To-ShardRecord($md){
  try{
    # Enforce league-only: skip records not belonging to configured league
    $targetLeague = Get-LeagueId
    if($targetLeague -gt 0){
      $mLeague = Get-MatchLeagueId $md
      if($mLeague -ne $targetLeague){ return $null }
    }
    $rec = [ordered]@{}
    $rec.match_id = [int64]$md.match_id
    $rec.start_time = [int]$md.start_time
    $rec.radiant_win = [bool]$md.radiant_win
    $rec.radiant_team_id = [int]($md.radiant_team_id)
    $rec.dire_team_id = [int]($md.dire_team_id)
    $rec.radiant_name = if($md.radiant_name){ [string]$md.radiant_name } else { 'Radiant' }
    $rec.dire_name = if($md.dire_name){ [string]$md.dire_name } else { 'Dire' }
    $pls = @()
    foreach($p in ($md.players|ForEach-Object { $_ })){
      $pls += [ordered]@{
        account_id = [int64]$p.account_id
        hero_id    = [int]$p.hero_id
        is_radiant = [bool]$p.isRadiant
        personaname= if($p.personaname){ [string]$p.personaname } else { $null }
        team_id    = if($p.isRadiant){ [int]$md.radiant_team_id } else { [int]$md.dire_team_id }
      }
    }
    $rec.players = $pls
    return $rec
  } catch { return $null }
}

function Ensure-Record-InShard($md){
  $rec = To-ShardRecord $md; if(-not $rec){ return $false }
  $data = Get-DataPath
  $dt = [DateTimeOffset]::FromUnixTimeSeconds([int64]$rec.start_time).UtcDateTime
  $fn = ("{0}-{1}.json" -f $dt.Year, $dt.ToString('MM'))
  $path = Join-Path (Join-Path $data 'matches') $fn
  $arr = @()
  if(Test-Path -LiteralPath $path){ try{ $arr = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $arr=@() } }
  if(-not ($arr | Where-Object { [int64]$_.match_id -eq [int64]$rec.match_id })){
    $arr = @($arr) + @($rec)
    $arr = $arr | Sort-Object start_time, match_id
    Save-Json -obj $arr -path $path
    Write-Log ("Updated shard: {0} (+1 match {1})" -f $fn, $rec.match_id)
    return $true
  }
  return $false
}

function Rebuild-Manifest(){
  $data = Get-DataPath
  $dir = Join-Path $data 'matches'
  $items = @()
  if(Test-Path -LiteralPath $dir){
    Get-ChildItem -LiteralPath $dir -Filter '*.json' | ForEach-Object {
      try{
        $month = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        $arr = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $items += @{ month=$month; file=("matches/"+$_.Name); count=(@($arr)).Count }
      } catch {}
    }
  }
  $manifest = @{ updated = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); months = $items | Sort-Object month }
  Save-Json -obj $manifest -path (Join-Path $data 'manifest.json')
  Write-Log 'Rebuilt data/manifest.json'
}

function Ensure-AllGamesParsed(){
  $data = Get-DataPath
  $dir = Join-Path $data 'matches'
  $ids = New-Object System.Collections.Generic.List[int64]
  if(Test-Path -LiteralPath $dir){
    Get-ChildItem -LiteralPath $dir -Filter '*.json' | ForEach-Object {
      try{
        $arr = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach($r in $arr){ try { [void]$ids.Add([int64]$r.match_id) } catch {} }
      } catch {}
    }
  }
  Save-Json -obj ($ids.ToArray() | Sort-Object -Unique) -path (Join-Path $data 'allgames_parsed.json')
  Write-Log 'Wrote data/allgames_parsed.json'
}

function Request-Parse-ForMissing(){
  $objs = Get-CachedMatchObjects
  $reqs = 0
  $start = Get-Date
  foreach($md in ($objs | Sort-Object match_id -Descending)){
    if($ParseBudgetSec -gt 0){
      $elapsed = ((Get-Date) - $start).TotalSeconds
      if($elapsed -ge $ParseBudgetSec){ Write-Warning ("Aborting parse requests after {0}s budget" -f $ParseBudgetSec); break }
    }
    if($reqs -ge $MaxParseRequests){ break }
    $needs = $false
    try {
      $hasPlayers = $md.players -and $md.players.Count -gt 0
      $hasObjectives = $md.objectives -and $md.objectives.Count -gt 0
      $hasUsage = $false
      if($hasPlayers){ foreach($p in $md.players){ if($p.purchase_log -or $p.item_uses -or $p.obs_killed -or $p.sen_killed){ $hasUsage = $true; break } } }
      if(-not ($hasPlayers -and $hasObjectives -and $hasUsage)){ $needs=$true }
    } catch { $needs=$true }
    if($needs){
      $mid = [int64]$md.match_id
      $attempts = [Math]::Max(1, [int]$ParseAttemptsPerMatch)
      for($a=1; $a -le $attempts; $a++){
        if($reqs -ge $MaxParseRequests){ break }
        try{ Invoke-Json -Method POST -Uri ("https://api.opendota.com/api/request/{0}" -f $mid) | Out-Null; Write-Log ("Requested parse for {0} (attempt {1}/{2})" -f $mid, $a, $attempts); $reqs++ } catch { Write-Warning ("Parse request failed for {0} (attempt {1}): {2}" -f $mid, $a, $_.Exception.Message) }
        if($a -lt $attempts){
          if($ParseBudgetSec -gt 0){
            $elapsed = ((Get-Date) - $start).TotalSeconds
            if($elapsed -ge $ParseBudgetSec){ break }
          }
          Write-Log ("Parse throttle: sleeping {0}s before retry" -f $ParseDelaySec)
          Start-Sleep -Seconds ([int]$ParseDelaySec)
        }
      }
      Write-Log ("Throttle: sleeping {0} ms after parse cycle" -f $DelayMs)
      Start-Sleep -Milliseconds $DelayMs
    }
  }
  Write-Log ("Parse requests sent: {0}" -f $reqs)
}

# ===== Main =====

$doConst    = To-Bool $UpdateConstants $true
$doMatches  = To-Bool $FetchMatches $true
$doDiscover = To-Bool $DiscoverMatches $false
$doShards   = To-Bool $UpdateShards $false
$doManifest = To-Bool $UpdateManifest $false
$doParseReq = To-Bool $RequestParse $false
$doSanitize = To-Bool $SanitizeCache $false

switch($Mode){
  'discover' { $doDiscover=$true; $doMatches=$true; $doShards=$true; $doManifest=$true }
  'full'     { $doDiscover=$true; $doMatches=$true; $doShards=$true; $doManifest=$true; $doParseReq=$true }
  'sanitize' { $doSanitize=$true; $doConst=$false; $doMatches=$false; $doDiscover=$false; $doShards=$false; $doManifest=$false; $doParseReq=$false }
}

# Optionally set STEAM_API_KEY from parameter or secure prompt
try{
  $needKey = [string]::IsNullOrWhiteSpace($env:STEAM_API_KEY)
  $keyFromParam = if([string]::IsNullOrWhiteSpace($SteamApiKey)) { $null } else { $SteamApiKey }
  if($keyFromParam){ $env:STEAM_API_KEY = $keyFromParam; Write-Log ("Using STEAM discovery (key length {0})" -f $keyFromParam.Length) }
  elseif($PromptForSteamKey -and $needKey -and $doDiscover){
    try{
      $sec = Read-Host -AsSecureString -Prompt 'Enter STEAM_API_KEY (input hidden)'
      if($sec){ $k = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)); if(-not [string]::IsNullOrWhiteSpace($k)){ $env:STEAM_API_KEY = $k; Write-Log ("Using STEAM discovery (key length {0})" -f $k.Length) } }
    } catch {}
  }
} catch {}

if($doConst){ Update-Constants }
if($doDiscover){
  $ids = @()
  # Discover sources based on toggles
  if($DiscoverViaSteam){ $ids += @(Discover-MatchIdsFromSteam) }
  if($DiscoverViaOpenDota){ $ids += @(Discover-MatchIdsFromOpenDota) }
  if($DiscoverViaTeams){ $ids += @(Discover-MatchIdsFromTeams) }
  $ids = $ids | Sort-Object -Unique
  if((($ids | Measure-Object).Count) -gt 0){
    # Ensure we fetch details for any newly discovered IDs
    $data = Get-DataPath
    $cacheDir = Join-Path $data 'cache/OpenDota/matches'
    $toFetch = @()
    if($ForceRefetch){ $toFetch = @($ids | ForEach-Object { [int64]$_ }) }
    else { foreach($id in $ids){ if(-not (Test-Path -LiteralPath (Join-Path $cacheDir ("{0}.json" -f $id)))){ $toFetch += [int64]$id } } }
    if((($toFetch | Measure-Object).Count) -gt 0){
      Write-Log ("Newly discovered needing fetch: {0}" -f (($toFetch | Measure-Object).Count))
      foreach($mid in ($toFetch | Sort-Object)){
        try{
          Write-Log ("Fetching discovered match {0}" -f $mid)
          $uri = ("https://api.opendota.com/api/matches/{0}" -f $mid)
          $sw = [System.Diagnostics.Stopwatch]::StartNew()
          $obj = Invoke-Json -Method GET -Uri $uri
          $sw.Stop(); Write-Log ("HTTP GET ok for {0} in {1} ms" -f $mid, $sw.ElapsedMilliseconds)
          if($obj){
            Write-Log ("Sanitizing match {0}" -f $mid)
            $tm = [System.Diagnostics.Stopwatch]::StartNew()
            $obj = Sanitize-MatchObject $obj
            $tm.Stop(); Write-Log ("Sanitize done for {0} in {1} ms" -f $mid, $tm.ElapsedMilliseconds)
            $outPath = (Join-Path $cacheDir ("{0}.json" -f $mid))
            Save-Json -obj $obj -path $outPath
            try{ $sz = (Get-Item -LiteralPath $outPath).Length }catch{ $sz = 0 }
            Write-Log ("Saved cache for {0} ({1} bytes)" -f $mid, $sz)
            if($doShards){ try{ [void](Ensure-Record-InShard $obj) } catch {} }
          }
        } catch { Write-Warning ("Fetch failed for {0} (uri={1}): {2}" -f $mid, (Sanitize-Uri $uri), (Format-HttpError $_)) }
        Write-Log ("Throttle: sleeping {0} ms after match fetch" -f $DelayMs)
        Start-Sleep -Milliseconds $DelayMs
      }
      if($doManifest){ Rebuild-Manifest; Ensure-AllGamesParsed }
    }
    # Also ensure shard entries for discovered IDs already in cache
    $existing = @(); foreach($id in $ids){ if(Test-Path -LiteralPath (Join-Path $cacheDir ("{0}.json" -f $id))){ $existing += [int64]$id } }
    if((($existing | Measure-Object).Count) -gt 0){
      Write-Log ("Ensuring shard records for existing cached: {0}" -f (($existing | Measure-Object).Count))
      foreach($mid in ($existing | Sort-Object)){
        try{
          $path = Join-Path $cacheDir ("{0}.json" -f $mid)
          $obj = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
          if($obj){ if($doShards){ try{ [void](Ensure-Record-InShard $obj) } catch {} } }
        } catch {}
      }
      if($doManifest){ Rebuild-Manifest; Ensure-AllGamesParsed }
    }
  }
}
if($doMatches){ Fetch-MissingMatches }
# Avoid the expensive full-shard ensure pass during discovery-focused runs; we've already
# ensured shard entries for newly discovered and existing discovered IDs above.
if($doShards -and ($Mode -eq 'default' -or $Mode -eq 'full') -and (-not $SkipFinalEnsure)){
  $targetLeague = Get-LeagueId
  Get-CachedMatchObjects | ForEach-Object {
    try {
      if($LeagueOnly){ $mLeague = Get-MatchLeagueId $_; if($targetLeague -gt 0 -and $mLeague -ne $targetLeague){ return } }
      [void](Ensure-Record-InShard $_)
    } catch {}
  }
}
if($doManifest){ Rebuild-Manifest; Ensure-AllGamesParsed }
if($doParseReq){ Request-Parse-ForMissing }
if($doSanitize){ Sanitize-ExistingCache }

Write-Log 'OpenDota data fetch complete.'

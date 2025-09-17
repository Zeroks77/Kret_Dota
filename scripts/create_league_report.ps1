param(
  [Parameter(Mandatory=$true)][string]$LeagueName,
  # Default docs root relative to this script (../docs)
  [string]$DocsRoot = "$PSScriptRoot/../docs",
  [int]$MaxPerMinute = 54,      # 10% safety under 60
  [int]$MaxPerDay = 1800,       # 10% safety under 2000
  [switch]$ForceRefreshLeagues, # Ignore cached leagues list
  [switch]$ForceRefreshProPlayers, # Ignore cached pro players list
  [switch]$SkipMatchesIfCached, # If league folder already exists with matches.json, skip re-download
  [switch]$NoIndexUpdate,       # Do not modify reports.json (dry generation)
  [switch]$VerboseLog,          # Custom verbose logging switch (avoid collision with common -Verbose)
  [switch]$UseDynamicFallback,  # Use dynamic.html instead of league_dynamic.html
  [int]$WardMinCount = 3,       # Minimum placements for ward spot to be considered
  [switch]$IncludeLowSampleWards # Allow falling back to lower sample if none meet threshold
  , [int]$DuoMinGames = 3        # Minimum games for a duo to be listed (lowered from 5)
)

<#
  Creates a static wrapper page for a specific Dota 2 league (e.g. "The International 2025")
  using OpenDota public API data. Produces a folder under docs/league/<YEAR>/<SLUG>/index.html
  pointing into dynamic viewer with a locked range covering all league matches.

  Steps:
   1. Fetch & cache leagues list -> data/cache/OpenDota/leagues.json
   2. Resolve league by name (case-insensitive substring match preferring exact, then longest match)
   3. Build slug (e.g. TI2025, RQ_WE)
   4. Fetch league matches list -> data/league/<SLUG>/matches.json
   5. Fetch missing detailed match JSON (rate limited <= MaxPerMinute & MaxPerDay)
   6. Aggregate server-side highlights + placements -> data/league/<SLUG>/report.json
   7. Write wrapper index.html pointing at league_dynamic.html (or dynamic.html with -UseDynamicFallback)
   8. Update docs/reports.json (group = 'league') unless -NoIndexUpdate

  Aggregated highlights include:
    - Best duo picks (offlane & safelane based on player.lane 3 / 1) with win rates
    - Best / worst heroes (>=5 games)
    - Ward spots (best/worst avg lifetime) & most dewards (players with highest obs_kills)
    - Player events: rampages (multi_kill 5), rapier pickups, aegis snatch (objective aegis_stolen)
    - Placements table (team games/wins sorted by wins -> winrate)

  Rate limiting:
    - Burst parallelism is avoided; we simply sleep to respect MaxPerMinute.
    - Daily cap is enforced by counting new fetches attempted in this run.

  Usage:
    pwsh ./scripts/create_league_report.ps1 -LeagueName "The International" -Verbose
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------- Helpers ----------
function Get-RepoRoot(){ (Resolve-Path "$PSScriptRoot/.." | Select-Object -ExpandProperty Path) }
function Get-DataPath(){ Join-Path (Get-RepoRoot) 'data' }
function Ensure-Dir([string]$p){ $d=[System.IO.Path]::GetDirectoryName($p); if($d -and -not (Test-Path -LiteralPath $d)){ New-Item -ItemType Directory -Path $d -Force | Out-Null } }
function Read-JsonFile([string]$p){ if(-not (Test-Path -LiteralPath $p)){ return $null } try{ Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json }catch{ $null } }
function Save-Json([object]$o,[string]$p){ Ensure-Dir $p; ($o | ConvertTo-Json -Depth 50) | Set-Content -LiteralPath $p -Encoding UTF8 }
function HtmlEncode([string]$s){ if($null -eq $s){ return '' } try{ return [System.Net.WebUtility]::HtmlEncode($s) }catch{ return ($s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;') } }
function Log([string]$m){ if($VerboseLog){ Write-Host $m } }

# ---------- Player alias normalization (extendable) ----------
# Map variant -> canonical. Add more as needed.
$playerAliases = [ordered]@{
  'YATOROGOD' = 'Yatoro'
  'Yatoro'    = 'Yatoro'
  'Collapse'  = 'Collapse'
  'N0tail'    = 'N0tail'
  'Johan'     = 'N0tail'
  'MATUMBAMAN'= 'MATUMBAMAN'
  'MATU'      = 'MATUMBAMAN'
  'MidOne'    = 'MidOne'
  'Puppey'    = 'Puppey'
  'Clement'   = 'Puppey'
}
function Normalize-PlayerName([string]$n){ if([string]::IsNullOrWhiteSpace($n)){ return $n } $t=$n.Trim(); foreach($k in $playerAliases.Keys){ if($t -ieq $k){ return $playerAliases[$k] } } return $t }

# ---------- League discovery ----------
$cacheDir = Join-Path (Get-DataPath) 'cache/OpenDota'
if(-not (Test-Path -LiteralPath $cacheDir)){ New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
$leagueCache = Join-Path $cacheDir 'leagues.json'
$needFetchLeagues = $ForceRefreshLeagues
if(-not $needFetchLeagues){ if(-not (Test-Path -LiteralPath $leagueCache)){ $needFetchLeagues = $true } }
if(-not $needFetchLeagues){
  # consider stale if older than 1 day
  try{ $age = (Get-Date) - (Get-Item -LiteralPath $leagueCache).LastWriteTimeUtc; if($age.TotalHours -gt 24){ $needFetchLeagues=$true } }catch{}
}
if($needFetchLeagues){
  Write-Host 'Fetching leagues list from OpenDota...'
  try{
    $leagues = Invoke-RestMethod -Method GET -Uri 'https://api.opendota.com/api/leagues' -Headers @{ 'Accept'='application/json'; 'User-Agent'='kret-league-fetcher/1.0' } -TimeoutSec 30
    if($leagues){ Save-Json -o $leagues -p $leagueCache }
  }catch{ throw "Failed to fetch leagues list: $($_.Exception.Message)" }
}else{ $leagues = Read-JsonFile $leagueCache }
if(-not $leagues){ throw 'No leagues data available' }

# ---------- Pro players fetch (for canonical names) ----------
$proPlayersCache = Join-Path $cacheDir 'proPlayers.json'
$needFetchPro = $ForceRefreshProPlayers
if(-not $needFetchPro){ if(-not (Test-Path -LiteralPath $proPlayersCache)){ $needFetchPro=$true } }
if(-not $needFetchPro){ try{ $age=(Get-Date) - (Get-Item -LiteralPath $proPlayersCache).LastWriteTimeUtc; if($age.TotalHours -gt 24){ $needFetchPro=$true } }catch{} }
if($needFetchPro){
  Write-Host 'Fetching pro players list from OpenDota...'
  try{
    $proPlayers = Invoke-RestMethod -Method GET -Uri 'https://api.opendota.com/api/proPlayers' -Headers @{ 'Accept'='application/json'; 'User-Agent'='kret-league-fetcher/1.0' } -TimeoutSec 30
    if($proPlayers){ Save-Json -o $proPlayers -p $proPlayersCache }
  }catch{ Write-Warning ("Failed to fetch pro players: {0}" -f $_.Exception.Message); $proPlayers = @() }
} else { $proPlayers = Read-JsonFile $proPlayersCache }
if(-not $proPlayers){ $proPlayers=@() }
Log ("Loaded pro players: {0}" -f (@($proPlayers).Count))

# Build index account_id -> display name (prefer team_tag + name else personaname)
$proPlayerIndex = @{}
foreach($pp in $proPlayers){
  try{
    $aid=0; try{ $aid=[int64]$pp.account_id }catch{}
    if($aid -le 0){ continue }
    $tag=''; try{ $tag=''+$pp.team_tag }catch{}
    $pname=''; try{ $pname=''+$pp.name }catch{}
    $pers=''; try{ $pers=''+$pp.personaname }catch{}
    $disp = if(-not [string]::IsNullOrWhiteSpace($tag) -and -not [string]::IsNullOrWhiteSpace($pname)){ "[$tag] $pname" } elseif(-not [string]::IsNullOrWhiteSpace($pname)){ $pname } elseif(-not [string]::IsNullOrWhiteSpace($pers)){ $pers } else { "Player $aid" }
    if(-not $proPlayerIndex.ContainsKey($aid)){ $proPlayerIndex[$aid]=$disp }
  }catch{}
}

# ---------- League matching ----------
$needle = $LeagueName.Trim()
$matches = @()
foreach($lg in $leagues){
  $name = ''+($lg.name)
  if([string]::IsNullOrWhiteSpace($name)){ continue }
  if($name -ieq $needle){ $matches += $lg; continue }
  if($name -like "*${needle}*") { $matches += $lg }
}
if((@($matches)).Count -eq 0){ throw "League name '$LeagueName' not found in leagues list" }
# Prefer exact (case-insensitive), else longest name containing
$exact = $matches | Where-Object { (''+$_.name).ToLower() -eq $needle.ToLower() }
$league = $null
if((@($exact)).Count -gt 0){ $league = ($exact | Select-Object -First 1) } else { $league = ($matches | Sort-Object { (''+$_.name).Length } -Descending | Select-Object -First 1) }
if(-not $league){ throw 'Failed to resolve league' }
$leagueId = [int]$league.leagueid
$leagueNameResolved = ''+$league.name
Write-Host ("Resolved league: {0} (id={1})" -f $leagueNameResolved, $leagueId)

# ---------- Slug generation ----------
function Make-LeagueSlug([string]$n){
  if([string]::IsNullOrWhiteSpace($n)){ return 'league' }
  $t=$n.Trim()
  # Special: The International 2025 -> TI2025
  if($t -match '^(?i)the international\s+(\d{4})$'){ return 'TI'+$Matches[1] }
  # Regional Qualifier West Europe -> RQ_WE (take initials of first two words + region initials)
  if($t -match '^(?i)(regional qualifier)\s+(.+)$'){
    $rest=$Matches[2]; $regionParts = ($rest -split '\s+') | Where-Object { $_ -match '^[A-Za-z]+' }
    $region = ($regionParts | ForEach-Object { $_.Substring(0,1).ToUpper() }) -join ''
    if([string]::IsNullOrWhiteSpace($region)){ $region='X' }
    return 'RQ_'+$region
  }
  # Generic: take uppercase initials and digits
  $words = $t -split '[^A-Za-z0-9]+'
  $abbr = ($words | Where-Object { $_ -ne '' } | ForEach-Object { if($_ -match '^[0-9]+$'){ $_ } else { $_.Substring(0,1).ToUpper() } }) -join ''
  if($abbr.Length -lt 3){ $abbr = ($t -replace '[^A-Za-z0-9]+','').Substring(0,[Math]::Min(8,($t -replace '[^A-Za-z0-9]+','').Length)) }
  return $abbr
}
$slug = Make-LeagueSlug $leagueNameResolved
Write-Host ("Slug = {0}" -f $slug)

# ---------- League matches summary ----------
$leagueDataDir = Join-Path (Get-DataPath) ("league/"+$slug)
if(-not (Test-Path -LiteralPath $leagueDataDir)){ New-Item -ItemType Directory -Path $leagueDataDir -Force | Out-Null }
$matchesFile = Join-Path $leagueDataDir 'matches.json'
$matches = $null
if(-not (Test-Path -LiteralPath $matchesFile) -or -not $SkipMatchesIfCached){
  Write-Host ("Fetching league matches list for id={0}" -f $leagueId)
  try{
    $matches = Invoke-RestMethod -Method GET -Uri ("https://api.opendota.com/api/leagues/{0}/matches" -f $leagueId) -Headers @{ 'Accept'='application/json'; 'User-Agent'='kret-league-fetcher/1.0' } -TimeoutSec 30
    if($matches){ Save-Json -o $matches -p $matchesFile }
  }catch{ throw "Failed to fetch league matches: $($_.Exception.Message)" }
}else{ $matches = Read-JsonFile $matchesFile }
if(-not $matches){ throw 'No matches for league' }

# ---------- Fetch individual match details with rate limiting ----------
$cacheMatchesDir = Join-Path (Get-DataPath) 'cache/OpenDota/matches'
if(-not (Test-Path -LiteralPath $cacheMatchesDir)){ New-Item -ItemType Directory -Path $cacheMatchesDir -Force | Out-Null }

$perMinuteWindow = @()
$newFetchesDay = 0
$maxNew = $MaxPerDay
$delayMs = [int][Math]::Ceiling(60000 / [Math]::Max(1,$MaxPerMinute))

$allIds = @(); foreach($m in $matches){ try{ $mid = [int64]$m.match_id; if($mid -gt 0){ $allIds += $mid } }catch{} }
$allIds = $allIds | Sort-Object -Unique
Write-Host ("Total match ids enumerated: {0}" -f (@($allIds)).Count)

foreach($mid in $allIds){
  $target = Join-Path $cacheMatchesDir ("{0}.json" -f $mid)
  if(Test-Path -LiteralPath $target){ continue }
  if($newFetchesDay -ge $maxNew){ Write-Warning "Daily fetch cap reached (MaxPerDay=$MaxPerDay)"; break }
  # Rate limiting: purge timestamps older than 60s
  $now=(Get-Date)
  $perMinuteWindow = $perMinuteWindow | Where-Object { ($now - $_).TotalSeconds -lt 60 }
  if((@($perMinuteWindow)).Count -ge $MaxPerMinute){
    $sleepMs = [Math]::Max(50, $delayMs)
    Start-Sleep -Milliseconds $sleepMs
    $now=(Get-Date)
    $perMinuteWindow = $perMinuteWindow | Where-Object { ($now - $_).TotalSeconds -lt 60 }
  if((@($perMinuteWindow)).Count -ge $MaxPerMinute){ continue }
  }
  try{
    Write-Host ("Fetching match {0}" -f $mid)
    $obj = Invoke-RestMethod -Method GET -Uri ("https://api.opendota.com/api/matches/{0}" -f $mid) -Headers @{ 'Accept'='application/json'; 'User-Agent'='kret-league-fetcher/1.0' } -TimeoutSec 30
    if($obj){ ($obj | ConvertTo-Json -Depth 100) | Set-Content -LiteralPath $target -Encoding UTF8; $newFetchesDay++; $perMinuteWindow += (Get-Date) }
  }catch{ Write-Warning ("Failed to fetch match {0}: {1}" -f $mid, $_.Exception.Message) }
  Start-Sleep -Milliseconds $delayMs
}

# ---------- Compute time range ----------
$startTimes = @(); foreach($m in $matches){ try{ $st=[int]$m.start_time; if($st -gt 0){ $startTimes += $st } }catch{} }
if((@($startTimes)).Count -eq 0){ throw 'No start times found for league matches' }
$fromUnix = ($startTimes | Measure-Object -Minimum).Minimum
$toUnix = ($startTimes | Measure-Object -Maximum).Maximum

# Expand to cover typical match duration window slightly (add +4h) so late same-day matches included by viewer queries
$toUnix = $toUnix + (4*3600)

# ---------- Load detailed match objects for aggregation ----------
$detailed = @()
foreach($mid in $allIds){
  $p = Join-Path $cacheMatchesDir ("{0}.json" -f $mid)
  if(Test-Path -LiteralPath $p){
    try{ $obj = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch{ $obj=$null }
    if($obj){ $detailed += $obj }
  }
}
if((@($detailed)).Count -eq 0){ Write-Warning 'No detailed match data loaded for aggregation.' }

# ---------- Aggregation helpers ----------
function New-PairKey([int]$a,[int]$b){ if($a -le $b){ return "$a-$b" } else { return "$b-$a" } }

# Collect team + hero structures
$teamStats = @{}
$heroStats = @{}
$duosOff = @{}
$duosSafe = @{}
$heroWins = @{}
$playerMeta = @{}
$playerStats = @{}
$rampageMap = @{}
$rapierMap = @{}
$aegisMap = @{}
$wardPlacement = @{}
$wardRemoval = @{}
$playerDewards = @{}

foreach($m in $detailed){
  $mid = [int64]$m.match_id
  $radWin = [bool]$m.radiant_win
  $duration = 0; try{ $duration = [int]$m.duration }catch{}
  $radTeam = 0; try{ $radTeam=[int]$m.radiant_team_id }catch{}
  $direTeam = 0; try{ $direTeam=[int]$m.dire_team_id }catch{}
  $radName = if($m.radiant_name){ [string]$m.radiant_name } else { 'Radiant' }
  $direName = if($m.dire_name){ [string]$m.dire_name } else { 'Dire' }
  foreach($t in @(@{id=$radTeam;name=$radName;win=$radWin}, @{id=$direTeam;name=$direName;win=(-not $radWin)})){
    if($t.id -gt 0){
      if(-not $teamStats.ContainsKey($t.id)){ $teamStats[$t.id] = [ordered]@{ team_id=$t.id; name=$t.name; games=0; wins=0; losses=0 } }
      $st = $teamStats[$t.id]; $st.games++ ; if($t.win){ $st.wins++ } else { $st.losses++ }
      if($t.name -and $t.name -notin @('Radiant','Dire')){ $st.name = $t.name }
    }
  }
  # Player loop
  foreach($p in @($m.players)){
    if(-not $p){ continue }
    $aid = 0; try{ $aid=[int64]$p.account_id }catch{}
    $hid = 0; try{ $hid=[int]$p.hero_id }catch{}
    $isRad = $false; try{ $isRad = [bool]$p.isRadiant }catch{}
    $lane = $null; try{ $lane = [int]$p.lane }catch{}
  $rawName = if($p.personaname){ [string]$p.personaname } elseif($aid -gt 0){ "Player $aid" } else { 'Unknown' }
  if($aid -gt 0 -and $proPlayerIndex.ContainsKey($aid)){ $rawName = $proPlayerIndex[$aid] }
  $name = Normalize-PlayerName $rawName
    if($aid -gt 0 -and -not $playerMeta.ContainsKey($aid)){ $playerMeta[$aid] = @{ name=$name } }
    $won = if($isRad){ $radWin } else { -not $radWin }
    if($aid -gt 0){
      if(-not $playerStats.ContainsKey($aid)){ $playerStats[$aid] = @{ games=0; wins=0; losses=0 } }
      $playerStats[$aid].games++ ; if($won){ $playerStats[$aid].wins++ } else { $playerStats[$aid].losses++ }
    }
    if($hid -gt 0){
      if(-not $heroStats.ContainsKey($hid)){ $heroStats[$hid] = @{ picks=0; wins=0 } }
      $heroStats[$hid].picks++ ; if($won){ $heroStats[$hid].wins++ }
    }
  }
  # Duo collection (need per lane heroes per team)
  $laneGroups = @{ } # key team+lane -> heroes (unique per match)
  foreach($p in @($m.players)){
    if(-not $p){ continue }
    $hid = 0; try{ $hid=[int]$p.hero_id }catch{}
    if($hid -le 0){ continue }
    $lane = $null; try{ $lane=[int]$p.lane }catch{}
  $teamId = if($p.isRadiant){ $radTeam } else { $direTeam }
  # Use ${} to avoid parser confusion with ':'
  $key = "${teamId}:${lane}"
    if(-not $laneGroups.ContainsKey($key)){ $laneGroups[$key] = New-Object System.Collections.Generic.List[int] }
    if(-not $laneGroups[$key].Contains($hid)){ $laneGroups[$key].Add($hid) | Out-Null }
  }
  foreach($k in $laneGroups.Keys){
  $parts = $k.Split(':'); if((@($parts)).Count -ne 2){ continue }
    $lane=[int]$parts[1]
    $heroes = $laneGroups[$k].ToArray()
    if((@($heroes)).Count -lt 2){ continue }
    for($i=0;$i -lt (@($heroes)).Count;$i++){
      for($j=$i+1;$j -lt (@($heroes)).Count;$j++){
        $a=$heroes[$i]; $b=$heroes[$j]; $key = New-PairKey $a $b
        $targetDict = if($lane -eq 3){ $duosOff } elseif($lane -eq 1){ $duosSafe } else { $null }
        if($null -eq $targetDict){ continue }
        if(-not $targetDict.ContainsKey($key)){ $targetDict[$key] = @{ a=$a; b=$b; games=0; wins=0 } }
        $targetDict[$key].games++ ; if($radWin){
          # Determine if duo belongs to radiant team by checking membership in radiant players
          # Simpler: check if any player hero list contains hero with isRadiant true; fallback: assume laneGroups mapping by team ensured correctness; decide winner based on team of laneGroup key
        }
        # To know winner: parse original laneGroup key team id vs radiant win
        $teamId=[int]$parts[0]
        $isWinner = ($teamId -eq $radTeam -and $radWin) -or ($teamId -eq $direTeam -and -not $radWin)
        if($isWinner){ $targetDict[$key].wins++ }
      }
    }
  }
  # Ward logs
  foreach($p in @($m.players)){
    if(-not $p){ continue }
    $aid=0; try{ $aid=[int64]$p.account_id }catch{}
    if($aid -gt 0){
      $dew=0; try{ $dew=[int]$p.obs_kills }catch{}
      if($dew -gt 0){ if(-not $playerDewards.ContainsKey($aid)){ $playerDewards[$aid]=0 }; $playerDewards[$aid]+=$dew }
    }
  }
  $obs = @(); try{ $obs = @($m.obs_log) }catch{}
  $obsLeft = @(); try{ $obsLeft = @($m.obs_left_log) }catch{}
  foreach($o in $obs){
    $key = ''+ $o.x +','+ $o.y
    if(-not $wardPlacement.ContainsKey($mid)){ $wardPlacement[$mid]=@() }
    $wardPlacement[$mid] += ,([pscustomobject]@{ x=[int]$o.x; y=[int]$o.y; time=[int]$o.time; key=$key })
  }
  foreach($ol in $obsLeft){
    if(-not $wardRemoval.ContainsKey($mid)){ $wardRemoval[$mid]=@() }
    $wardRemoval[$mid] += ,([pscustomobject]@{ x=[int]$ol.x; y=[int]$ol.y; time=[int]$ol.time; })
  }
  # Objectives
  $objectives = @(); try{ $objectives = @($m.objectives) }catch{}
  foreach($o in $objectives){
    $type = ''+$o.type
    if($type -eq 'multi_kill'){
      $key = ''+$o.key
      if($key -eq '5'){ # Rampage (5 kills)
        $slot = $o.slot
        $aid = 0; try{ $aid = [int64]($m.players[$slot].account_id) }catch{}
        if($aid -gt 0){ if(-not $rampageMap.ContainsKey($aid)){ $rampageMap[$aid]=@() }; $rampageMap[$aid] += $mid }
      }
    } elseif($type -eq 'aegis_stolen'){
      $slot = $o.slot
      $aid = 0; try{ $aid = [int64]($m.players[$slot].account_id) }catch{}
      if($aid -gt 0){ if(-not $aegisMap.ContainsKey($aid)){ $aegisMap[$aid]=@() }; $aegisMap[$aid] += $mid }
    }
  }
  # Fallback rampage detection via players.multi_kills (key '5') when objectives missing
  foreach($p in @($m.players)){
    if(-not $p){ continue }
    $aid=0; try{ $aid=[int64]$p.account_id }catch{}
    if($aid -le 0){ continue }
    try {
      $mk = $p.multi_kills
      if($mk -and $mk.PSObject.Properties.Name -contains '5'){
        $val = 0; try{ $val = [int]$mk.'5' }catch{}
        if($val -gt 0){ if(-not $rampageMap.ContainsKey($aid)){ $rampageMap[$aid]=@() }; if(-not ($rampageMap[$aid] -contains $mid)){ $rampageMap[$aid] += $mid } }
      }
    } catch {}
  }
  # Rapier purchases via purchase_log
  foreach($p in @($m.players)){
    if(-not $p){ continue }
    $aid=0; try{ $aid=[int64]$p.account_id }catch{}
    if($aid -le 0){ continue }
    $purch = @(); try{ $purch = @($p.purchase_log) }catch{}
    foreach($pl in $purch){ if((''+$pl.key) -eq 'rapier'){ if(-not $rapierMap.ContainsKey($aid)){ $rapierMap[$aid]=@() }; $rapierMap[$aid] += $mid } }
  }
}

# Compute ward lifetimes per (x,y)
$wardStats = @{}
foreach($mid in $wardPlacement.Keys){
  $placements = $wardPlacement[$mid]
  $removals = @(); if($wardRemoval.ContainsKey($mid)){ $removals = $wardRemoval[$mid] }
  $used = New-Object System.Collections.Generic.List[object]
  foreach($p in $placements | Sort-Object time){
    $matchRemoval = $null
    foreach($r in ($removals | Sort-Object time)){
      if(($r.x -eq $p.x) -and ($r.y -eq $p.y) -and -not ($used -contains $r) -and $r.time -ge $p.time){ $matchRemoval=$r; break }
    }
    if($matchRemoval){ $used.Add($matchRemoval) | Out-Null }
    $life = 0
    if($matchRemoval){ $life = [int]($matchRemoval.time - $p.time) } elseif($duration -gt 0) { $life = [int]([Math]::Min($duration, 4200) - $p.time) }
    if($life -lt 0){ $life = 0 }
    $coord = "$($p.x),$($p.y)"
    if(-not $wardStats.ContainsKey($coord)){ $wardStats[$coord] = @{ count=0; total=0 } }
    $wardStats[$coord].count++ ; $wardStats[$coord].total += $life
  }
}

# Build duo arrays
function To-DuoArray($dict){
  $out=@()
  foreach($k in $dict.Keys){
    $v=$dict[$k]
  if($v.games -ge $DuoMinGames){
      $out += [pscustomobject]@{
        a=$v.a; b=$v.b; games=$v.games; wins=$v.wins; winrate= if($v.games -gt 0){ [double]$v.wins/$v.games } else { 0 }
      }
    }
  }
  # Both properties descending (primary winrate, secondary games)
  return ($out | Sort-Object -Property winrate, games -Descending | Select-Object -First 8)
}
$duosOffArr = To-DuoArray $duosOff
$duosSafeArr = To-DuoArray $duosSafe

# Enrich duos with localized hero names if heroes constants available
try {
  $heroesConstPath = Join-Path (Join-Path (Get-DataPath) 'cache/OpenDota/constants') 'heroes.json'
  $heroConst = $null; if(Test-Path -LiteralPath $heroesConstPath){ $heroConst = Get-Content -LiteralPath $heroesConstPath -Raw -Encoding UTF8 | ConvertFrom-Json }
  function Add-HeroNamesToDuos([object[]]$arr){
    if(-not $arr){ return }
    foreach($d in $arr){
      if($d -and $heroConst){
        try {
          $ha = $heroConst."$($d.a)"; if($ha){ $d | Add-Member -NotePropertyName a_name -NotePropertyValue ($ha.localized_name) -Force }
          $hb = $heroConst."$($d.b)"; if($hb){ $d | Add-Member -NotePropertyName b_name -NotePropertyValue ($hb.localized_name) -Force }
        } catch {}
      }
    }
  }
  Add-HeroNamesToDuos $duosOffArr
  Add-HeroNamesToDuos $duosSafeArr
} catch { Write-Verbose "Failed duo hero name enrichment: $($_.Exception.Message)" }

# Hero best/worst
$heroPerf = @(); foreach($hid in $heroStats.Keys){ $hs=$heroStats[$hid]; if($hs.picks -ge 5){ $heroPerf += [pscustomobject]@{ hero_id=$hid; picks=$hs.picks; wins=$hs.wins; winrate= if($hs.picks -gt 0){ [double]$hs.wins/$hs.picks } else { 0 } } } }
$bestHeroes = $heroPerf | Sort-Object -Property winrate, picks -Descending | Select-Object -First 10
# Worst: PowerShell 5.1 compatible: first sort by picks desc (secondary), then stable sort by winrate asc (primary)
$worstHeroes = $heroPerf | Sort-Object -Property picks -Descending | Sort-Object -Property winrate | Select-Object -First 10

# Full hero list (include zero-pick heroes from constants if available)
$heroesAll = @()
foreach($hid in $heroStats.Keys){ $hs=$heroStats[$hid]; $wr = if($hs.picks -gt 0){ [double]$hs.wins/$hs.picks } else {0}; $heroesAll += [pscustomobject]@{ hero_id=$hid; picks=$hs.picks; wins=$hs.wins; winrate=$wr } }
try {
  $constHeroesPath = Join-Path (Join-Path (Get-DataPath) 'cache/OpenDota/constants') 'heroes.json'
  if(Test-Path -LiteralPath $constHeroesPath){
    $constHeroes = Get-Content -LiteralPath $constHeroesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach($prop in $constHeroes.PSObject.Properties.Name){
      $obj = $constHeroes.$prop
      if($obj -and $obj.id -gt 0){
        $hid=[int]$obj.id
        if(-not ($heroesAll | Where-Object { $_.hero_id -eq $hid })){ $heroesAll += [pscustomobject]@{ hero_id=$hid; picks=0; wins=0; winrate=0 } }
      }
    }
  }
} catch { Write-Verbose "Failed to append zero-pick heroes: $($_.Exception.Message)" }


# Ward best/worst with configurable threshold & fallback
$wardPerf = @(); foreach($c in $wardStats.Keys){ $ws=$wardStats[$c]; if($ws.count -ge $WardMinCount){ $parts = $c -split ','; $wx=0; $wy=0; if($parts.Length -ge 2){ [int]::TryParse($parts[0],[ref]$wx) | Out-Null; [int]::TryParse($parts[1],[ref]$wy) | Out-Null }; $wardPerf += [pscustomobject]@{ spot=$c; x=$wx; y=$wy; avgSeconds=[int]([Math]::Floor($ws.total / $ws.count)); count=$ws.count } } }
if((@($wardPerf)).Count -eq 0 -and $IncludeLowSampleWards){
  # fallback: accept any spot with at least 1 placement
  foreach($c in $wardStats.Keys){ $ws=$wardStats[$c]; if($ws.count -ge 1){ $parts = $c -split ','; $wx=0; $wy=0; if($parts.Length -ge 2){ [int]::TryParse($parts[0],[ref]$wx) | Out-Null; [int]::TryParse($parts[1],[ref]$wy) | Out-Null }; $wardPerf += [pscustomobject]@{ spot=$c; x=$wx; y=$wy; avgSeconds=[int]([Math]::Floor($ws.total / $ws.count)); count=$ws.count } } }
}
$bestSpots = $wardPerf | Sort-Object -Property avgSeconds, count -Descending | Select-Object -First 8
$worstSpots = $wardPerf | Sort-Object -Property count -Descending | Sort-Object -Property avgSeconds | Select-Object -First 8
# Collect all ward spots (count>=1) for fallback map rendering (limit later in client)
$wardAll = @(); foreach($c in $wardStats.Keys){ $ws=$wardStats[$c]; if($ws.count -ge 1){ $parts=$c -split ','; $wx=0;$wy=0; if($parts.Length -ge 2){ [int]::TryParse($parts[0],[ref]$wx)|Out-Null; [int]::TryParse($parts[1],[ref]$wy)|Out-Null }; $wardAll += [pscustomobject]@{ spot=$c; x=$wx; y=$wy; avgSeconds= if($ws.count -gt 0){ [int]([Math]::Floor($ws.total / $ws.count)) } else {0}; count=$ws.count } } }

# Player dewards
$mostDewards = @(); foreach($aid in $playerDewards.Keys){ $mostDewards += [pscustomobject]@{ account_id=$aid; name=$playerMeta[$aid].name; count=$playerDewards[$aid] } }
$mostDewards = $mostDewards | Sort-Object count -Descending | Select-Object -First 8

# Player events lists (expanded for correct brace closure)
function Build-EventList($map){
  $arr=@()
  foreach($aid in $map.Keys){
    $matches=$map[$aid] | Sort-Object -Unique
  $arr += [pscustomobject]@{ account_id=$aid; name=$playerMeta[$aid].name; count=(@($matches)).Count; matches=$matches }
  }
  return ($arr | Sort-Object count -Descending | Select-Object -First 10)
}
$rampages = Build-EventList $rampageMap
$rapiers = Build-EventList $rapierMap
$aegis = Build-EventList $aegisMap

# Full players list (all that appeared)
$playersAll = @(); foreach($aid in $playerStats.Keys){ $ps=$playerStats[$aid]; $wr = if($ps.games -gt 0){ [double]$ps.wins/$ps.games } else {0}; $nm = if($playerMeta.ContainsKey($aid)){ $playerMeta[$aid].name } else { "Player $aid" }; $playersAll += [pscustomobject]@{ account_id=$aid; name=$nm; games=$ps.games; wins=$ps.wins; losses=$ps.losses; winrate=$wr } }

# Placements
$placements = @(); foreach($tid in $teamStats.Keys){ $ts=$teamStats[$tid]; $wr = if($ts.games -gt 0){ [double]$ts.wins/$ts.games } else { 0 }; $placements += [pscustomobject]@{ team_id=$tid; name=$ts.name; games=$ts.games; wins=$ts.wins; losses=$ts.losses; winrate=$wr } }
$placements = $placements | Sort-Object -Property wins, winrate, games -Descending
$rank=1; foreach($p in $placements){ $p | Add-Member -NotePropertyName place -NotePropertyValue $rank; $rank++ }

# Aggregate object
$report = [ordered]@{
  league = @{ id=$leagueId; name=$leagueNameResolved; slug=$slug; from=$fromUnix; to=$toUnix };
  generated = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds();
  highlights = [ordered]@{
  duos = @{ offlane= @($duosOffArr); safelane= @($duosSafeArr) };
  heroes = @{ best=@($bestHeroes); worst=@($worstHeroes); all=@($heroesAll) };
  wards = @{ bestSpots=@($bestSpots); worstSpots=@($worstSpots); mostDewards=@($mostDewards); allSpots=@($wardAll) };
  players = @{ rampages=@($rampages); rapiers=@($rapiers); aegisSnatch=@($aegis); all=@($playersAll) };
  };
  placements = $placements
}

# Resolve docs root early for publishing
function Get-DocsRoot(){ try{ Resolve-Path -LiteralPath $DocsRoot -ErrorAction Stop | Select-Object -ExpandProperty Path }catch{ $DocsRoot } }
$docs = Get-DocsRoot
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if($docs -and ($docs -notlike "$repoRoot*")){
  # If resolution produced a path outside repo (e.g. C:\docs), fall back to repo docs folder
  $candidate = Join-Path $repoRoot 'docs'
  if(Test-Path -LiteralPath $candidate){ $docs = (Resolve-Path -LiteralPath $candidate).Path }
}

$reportFile = Join-Path $leagueDataDir 'report.json'
Save-Json -o $report -p $reportFile
Write-Host ("Wrote aggregated report JSON: {0}" -f $reportFile)

# Also publish a copy under docs/data so GitHub Pages (serving only /docs) can fetch it
try {
  $publicLeagueDataDir = Join-Path $docs ("data/league/"+$slug)
  if(-not (Test-Path -LiteralPath $publicLeagueDataDir)) { New-Item -ItemType Directory -Path $publicLeagueDataDir -Force | Out-Null }
  Copy-Item -LiteralPath $reportFile -Destination (Join-Path $publicLeagueDataDir 'report.json') -Force
  if(Test-Path -LiteralPath $matchesFile){ Copy-Item -LiteralPath $matchesFile -Destination (Join-Path $publicLeagueDataDir 'matches.json') -Force }
  # Ensure shared heroes.json is published once under docs/data for icon rendering
  $heroesSrc = Join-Path (Join-Path $PSScriptRoot '..') 'data\heroes.json'
  $heroesDestDir = Join-Path $docs 'data'
  if(Test-Path -LiteralPath $heroesSrc){ if(-not (Test-Path -LiteralPath $heroesDestDir)){ New-Item -ItemType Directory -Path $heroesDestDir -Force | Out-Null }
    $heroesDest = Join-Path $heroesDestDir 'heroes.json'
    if(-not (Test-Path -LiteralPath $heroesDest)) { Copy-Item -LiteralPath $heroesSrc -Destination $heroesDest -Force }
  }
  # Publish constants (heroes/patch) into docs/data/constants for any viewer
  $constSrcDir = Join-Path (Join-Path $PSScriptRoot '..') 'data\cache\OpenDota\constants'
  if(Test-Path -LiteralPath $constSrcDir){
    $constOutDir = Join-Path $docs 'data/constants'
    if(-not (Test-Path -LiteralPath $constOutDir)){ New-Item -ItemType Directory -Path $constOutDir -Force | Out-Null }
    foreach($fn in 'heroes.json','patch.json'){
      $srcFile = Join-Path $constSrcDir $fn
      if(Test-Path -LiteralPath $srcFile){ Copy-Item -LiteralPath $srcFile -Destination (Join-Path $constOutDir $fn) -Force }
    }
  }
  Write-Host ("Published league data into docs: {0}" -f $publicLeagueDataDir)
} catch { Write-Warning ("Failed to publish league data into docs: {0}" -f $_.Exception.Message) }

# ---------- Write wrapper ----------
# (docs root already resolved above)
$year = (Get-Date ([datetimeoffset]::FromUnixTimeSeconds([int64]$fromUnix).UtcDateTime)).Year
$folder = Join-Path $docs ("league/"+$year+"/"+$slug)
if(-not (Test-Path -LiteralPath $folder)){ New-Item -ItemType Directory -Path $folder -Force | Out-Null }
# Decide which dynamic file to embed
$dynamicFile = if($UseDynamicFallback){ 'dynamic.html' } else { 'league_dynamic.html' }
$title = "League Report - $leagueNameResolved"
$query = "?from=$fromUnix`&to=$toUnix`&tab=highlights`&lock=1`&league=$slug"
$html = @"
<!doctype html>
<html lang='en'>
<head>
<meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>$(HtmlEncode $title)</title>
<link href='https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap' rel='stylesheet'>
<style>body{margin:0;height:100vh;display:flex;flex-direction:column;background:#0b1020}.bar{display:flex;justify-content:space-between;align-items:center;padding:10px 12px;color:#eef1f7;background:rgba(255,255,255,.06);font-family:Inter,system-ui,Segoe UI,Roboto,Arial,sans-serif}.bar a{color:#9ec7ff;text-decoration:none}iframe{border:0;flex:1;width:100%}</style>
</head>
<body>
  <div class='bar'>
    <div>$(HtmlEncode $title)</div>
    <!-- Wrapper is at docs/league/<year>/<slug>/ so 3 levels up to reach docs root -->
    <div><a href='../../../$dynamicFile$query' target='_blank' rel='noopener'>Open in new tab</a></div>
  </div>
  <iframe src='../../../$dynamicFile$query' loading='eager' referrerpolicy='no-referrer'></iframe>
</body>
</html>
"@
Set-Content -LiteralPath (Join-Path $folder 'index.html') -Value $html -Encoding UTF8
Write-Host ("Wrote league report wrapper: {0}" -f (Join-Path $folder 'index.html'))

# ---------- Update reports.json ----------
function Normalize-Href([string]$href){
  if([string]::IsNullOrWhiteSpace($href)){ return '' }
  $h=$href.Trim()
  if($h.StartsWith('./')){ $h=$h.Substring(2) }
  if(-not $h.EndsWith('/')){ $h+='/'}
  return $h
}

function Update-ReportsJson(
  [string]$docsRoot,
  [string]$title,
  [string]$href,
  [string]$group,
  [datetime]$when,
  [string]$sortKey
){
  $file = Join-Path $docsRoot 'reports.json'
  $obj = @{ items=@() }
  if(Test-Path -LiteralPath $file){
    try{ $obj = Get-Content -Raw -Path $file | ConvertFrom-Json -ErrorAction Stop }catch{ $obj=@{items=@()} }
    if(-not $obj.items){ $obj=@{items=@()} }
  }
  $items=@(); $items += $obj.items
  for($i=0; $i -lt $items.Count; $i++){
    if($items[$i] -and $items[$i].href){ $items[$i].href = (Normalize-Href -href ([string]$items[$i].href)) }
  }
  $nhref = Normalize-Href -href $href
  $found=$false
  for($i=0; $i -lt $items.Count; $i++){
    if([string]$items[$i].href -eq [string]$nhref){
      $items[$i] = [pscustomobject]@{ title=$title; href=$nhref; group=$group; time=$when.ToString('yyyy-MM-ddTHH:mm:ssZ'); sort=$sortKey }
      $found=$true; break
    }
  }
  if(-not $found){
    $items += [pscustomobject]@{ title=$title; href=$nhref; group=$group; time=$when.ToString('yyyy-MM-ddTHH:mm:ssZ'); sort=$sortKey }
  }
  # Dedup
  $map=@{}
  foreach($it in $items){
    if(-not $it){ continue }
    $h=Normalize-Href -href ([string]$it.href)
    $t=0; try{ $t=[datetime]::Parse((''+$it.time)).ToFileTimeUtc() }catch{ $t=0 }
    if($map.ContainsKey($h)){
      $prev=$map[$h]; $pt=0; try{ $pt=[datetime]::Parse((''+$prev.time)).ToFileTimeUtc() }catch{ $pt=0 }
      if($t -gt $pt){ $map[$h]=$it }
    } else { $map[$h]=$it }
  }
  $items=@(); foreach($k in $map.Keys){ $items+=$map[$k] }
  $outJson = @{ items=$items } | ConvertTo-Json -Depth 5
  Set-Content -Path $file -Value $outJson -Encoding UTF8
}
if(-not $NoIndexUpdate){
  $now=(Get-Date).ToUniversalTime()
  $href = "league/$year/$slug/"
  Update-ReportsJson -docsRoot $docs -title $leagueNameResolved -href $href -group 'league' -when $now -sortKey ("$year-$slug")
  Write-Host ("Updated reports.json with league entry -> {0}" -f $href)
}

Write-Host 'League report generation complete.'

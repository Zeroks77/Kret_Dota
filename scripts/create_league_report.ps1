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
# Approved verb: New- (create parent directory if missing)
function New-ParentDirectory([string]$p){ $d=[System.IO.Path]::GetDirectoryName($p); if($d -and -not (Test-Path -LiteralPath $d)){ New-Item -ItemType Directory -Path $d -Force | Out-Null } }
function Read-JsonFile([string]$p){ if(-not (Test-Path -LiteralPath $p)){ return $null } try{ Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json }catch{ $null } }
function Save-Json([object]$o,[string]$p){ New-ParentDirectory $p; ($o | ConvertTo-Json -Depth 50) | Set-Content -LiteralPath $p -Encoding UTF8 }
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
function Convert-PlayerName([string]$n){ if([string]::IsNullOrWhiteSpace($n)){ return $n } $t=$n.Trim(); foreach($k in $playerAliases.Keys){ if($t -ieq $k){ return $playerAliases[$k] } } return $t }

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

# ---------- Hero constants (for ward attacker mapping) ----------
$heroNameToId = @{}
try{
  $heroesConstPath = Join-Path (Join-Path (Get-DataPath) 'cache/OpenDota/constants') 'heroes.json'
  if(Test-Path -LiteralPath $heroesConstPath){
    $constHeroes = Get-Content -LiteralPath $heroesConstPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach($prop in $constHeroes.PSObject.Properties.Name){
      $obj = $constHeroes.$prop
      if($obj -and $obj.id -gt 0){ $nm=''+$obj.name; if(-not [string]::IsNullOrWhiteSpace($nm)){ $heroNameToId[$nm] = [int]$obj.id } }
    }
  }
}catch{ Write-Verbose ("Failed loading hero constants: {0}" -f $_.Exception.Message) }

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
$leagueCandidates = @()
foreach($lg in $leagues){
  $name = ''+($lg.name)
  if([string]::IsNullOrWhiteSpace($name)){ continue }
  if($name -ieq $needle){ $leagueCandidates += $lg; continue }
  if($name -like "*${needle}*") { $leagueCandidates += $lg }
}
if((@($leagueCandidates)).Count -eq 0){ throw "League name '$LeagueName' not found in leagues list" }
# Prefer exact (case-insensitive), else longest name containing
$exact = $leagueCandidates | Where-Object { (''+$_.name).ToLower() -eq $needle.ToLower() }
$league = $null
if((@($exact)).Count -gt 0){ $league = ($exact | Select-Object -First 1) } else { $league = ($leagueCandidates | Sort-Object { (''+$_.name).Length } -Descending | Select-Object -First 1) }
if(-not $league){ throw 'Failed to resolve league' }
$leagueId = [int]$league.leagueid
$leagueNameResolved = ''+$league.name
Write-Host ("Resolved league: {0} (id={1})" -f $leagueNameResolved, $leagueId)

# ---------- Slug generation ----------
function Get-LeagueSlug([string]$n){
  if([string]::IsNullOrWhiteSpace($n)){ return 'league' }
  $t=$n.Trim()
  # Special: The International 2025 -> TI2025
  $m = [regex]::Match($t, '^(?i)the international\s+(\d{4})$')
  if($m.Success){ return 'TI' + $m.Groups[1].Value }
  # Regional Qualifier West Europe -> RQ_WE (take initials of first two words + region initials)
  $m2 = [regex]::Match($t, '^(?i)(regional qualifier)\s+(.+)$')
  if($m2.Success){
    $rest=$m2.Groups[2].Value; $regionParts = ($rest -split '\s+') | Where-Object { $_ -match '^[A-Za-z]+' }
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
$slug = Get-LeagueSlug $leagueNameResolved
Write-Host ("Slug = {0}" -f $slug)

# ---------- League matches summary ----------
$leagueDataDir = Join-Path (Get-DataPath) ("league/"+$slug)
if(-not (Test-Path -LiteralPath $leagueDataDir)){ New-Item -ItemType Directory -Path $leagueDataDir -Force | Out-Null }
$leagueMatchesFile = Join-Path $leagueDataDir 'matches.json'
$leagueMatches = $null
if(-not (Test-Path -LiteralPath $leagueMatchesFile) -or -not $SkipMatchesIfCached){
  Write-Host ("Fetching league matches list for id={0}" -f $leagueId)
  try{
    $leagueMatches = Invoke-RestMethod -Method GET -Uri ("https://api.opendota.com/api/leagues/{0}/matches" -f $leagueId) -Headers @{ 'Accept'='application/json'; 'User-Agent'='kret-league-fetcher/1.0' } -TimeoutSec 30
    if($leagueMatches){ Save-Json -o $leagueMatches -p $leagueMatchesFile }
  }catch{ throw "Failed to fetch league matches: $($_.Exception.Message)" }
}else{ $leagueMatches = Read-JsonFile $leagueMatchesFile }
if(-not $leagueMatches){ throw 'No matches for league' }

# ---------- Fetch individual match details with rate limiting ----------
$matchDetailsCacheDir = Join-Path (Get-DataPath) 'cache/OpenDota/matches'
if(-not (Test-Path -LiteralPath $matchDetailsCacheDir)){ New-Item -ItemType Directory -Path $matchDetailsCacheDir -Force | Out-Null }

$perMinuteWindow = @()
$newFetchesDay = 0
$maxNew = $MaxPerDay
$delayMs = [int][Math]::Ceiling(60000 / [Math]::Max(1,$MaxPerMinute))

$allIds = @(); foreach($m in $leagueMatches){ try{ $mid = [int64]$m.match_id; if($mid -gt 0){ $allIds += $mid } }catch{} }
$allIds = $allIds | Sort-Object -Unique
Write-Host ("Total match ids enumerated: {0}" -f (@($allIds)).Count)

foreach($mid in $allIds){
  $target = Join-Path $matchDetailsCacheDir ("{0}.json" -f $mid)
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
$startTimes = @(); foreach($m in $leagueMatches){ try{ $st=[int]$m.start_time; if($st -gt 0){ $startTimes += $st } }catch{} }
if((@($startTimes)).Count -eq 0){ throw 'No start times found for league matches' }
$fromUnix = ($startTimes | Measure-Object -Minimum).Minimum
$toUnix = ($startTimes | Measure-Object -Maximum).Maximum

# Expand to cover typical match duration window slightly (add +4h) so late same-day matches included by viewer queries
$toUnix = $toUnix + (4*3600)

# ---------- Load detailed match objects for aggregation ----------
$detailed = @()
foreach($mid in $allIds){
  $p = Join-Path $matchDetailsCacheDir ("{0}.json" -f $mid)
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
# removed unused $heroWins
$playerMeta = @{}
$playerStats = @{}
$playerTeamCount = @{} # aid -> (team_id -> appearances)
$rampageMap = @{}
$rapierMap = @{}
$aegisMap = @{}
$wardPlacement = @{}
$wardRemoval = @{}
# Sentry placements and viewer-precompute helpers
$sentryCountBy = @{}     # "x,y" -> count
$sentryBySide  = @{}     # "x,y" -> { Radiant={count}, Dire={count} }
$sentryByTeam  = @{}     # "x,y" -> team_id -> { count }
$sentrySamples = @{}     # "x,y" -> array of { t, side, teamId, aid }
# For ward viewer enriched data
$obsSamplesBy  = @{}     # "x,y" -> array of { t, life, side, teamId, aid }
$wardBySide    = @{}     # "x,y" -> { Radiant={count,total}, Dire={count,total} }
$wardByTeam    = @{}     # "x,y" -> team_id -> { count,total }
# Track players who actually placed observers (for viewer player list)
$obsPlacerCount = @{}     # aid -> placements
$playerDewards = @{}
# Track duration per match for ward lifetime fallback
$matchDurations = @{}

# Draft aggregation maps
$draftPickStats = @{}     # hid -> @{ picks=0; wins=0 }
$draftBanCount = @{}      # hid -> count
$draftFirstPick = @{}     # hid -> @{ count=0; wins=0 }
$draftOpeningPairs = @{}  # "a-b" -> @{ a=0; b=0; games=0; wins=0 }
# Additional draft helpers
$draftMatches = 0         # matches with usable picks_bans
$captainMap = @{}         # aid -> @{ games=0; wins=0 }

foreach($m in $detailed){
  $mid = [int64]$m.match_id
  $radWin = [bool]$m.radiant_win
  $duration = 0; try{ $duration = [int]$m.duration }catch{}
  # Remember duration per match for ward lifetime fallback later
  $matchDurations[$mid] = $duration
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
  $name = Convert-PlayerName $rawName
    if($aid -gt 0 -and -not $playerMeta.ContainsKey($aid)){ $playerMeta[$aid] = @{ name=$name } }
    $won = if($isRad){ $radWin } else { -not $radWin }
    if($aid -gt 0){
      if(-not $playerStats.ContainsKey($aid)){ $playerStats[$aid] = @{ games=0; wins=0; losses=0 } }
      $playerStats[$aid].games++ ; if($won){ $playerStats[$aid].wins++ } else { $playerStats[$aid].losses++ }
      # Track team assignment by appearances
      $teamForPlayer = if($isRad){ $radTeam } else { $direTeam }
      if($teamForPlayer -gt 0){
        if(-not $playerTeamCount.ContainsKey($aid)){ $playerTeamCount[$aid] = @{} }
        if(-not $playerTeamCount[$aid].ContainsKey($teamForPlayer)){ $playerTeamCount[$aid][$teamForPlayer] = 0 }
        $playerTeamCount[$aid][$teamForPlayer]++
      }
    }
    if($hid -gt 0){
      if(-not $heroStats.ContainsKey($hid)){ $heroStats[$hid] = @{ picks=0; wins=0 } }
      $heroStats[$hid].picks++ ; if($won){ $heroStats[$hid].wins++ }
    }
  }
  # Duo collection: mirror client logic exactly -> for each side and laneRole, only if exactly 2 players -> record that pair
  function Get-SidePlayers($players, [bool]$wantRadiant){
    $list = New-Object System.Collections.Generic.List[object]
    foreach($p in @($players)){
      if(-not $p){ continue }
      $isRad = $false
      try{
        if($p.PSObject.Properties.Name -contains 'isRadiant'){ $isRad = [bool]$p.isRadiant }
        elseif($p.PSObject.Properties.Name -contains 'is_radiant'){ $isRad = [bool]$p.is_radiant }
        else { $slot=0; try{ $slot=[int]$p.player_slot }catch{}; $isRad = ($slot -lt 128) }
      }catch{}
      if($isRad -ne $wantRadiant){ continue }
      $list.Add($p) | Out-Null
    }
    return ,$list.ToArray()
  }
  function Get-LaneRole([object]$p){
    try{ if($p.PSObject.Properties.Name -contains 'lane_role'){ return [int]$p.lane_role } }catch{}
    try{ if($p.PSObject.Properties.Name -contains 'lane'){ return [int]$p.lane } }catch{}
    return 0
  }
  foreach($side in @('Radiant','Dire')){
    $wantRad = ($side -eq 'Radiant')
    $teamWon = ($wantRad -and $radWin) -or ((-not $wantRad) -and (-not $radWin))
    $teamIdCurrent = if($wantRad){ $radTeam } else { $direTeam }
    $sidePlayers = Get-SidePlayers $m.players $wantRad
    foreach($laneCode in 1,3){
      $lanePlayers = @()
      foreach($sp in $sidePlayers){ if((Get-LaneRole $sp) -eq $laneCode){ $lanePlayers += ,$sp } }
      if((@($lanePlayers)).Count -ne 2){ continue }
      $a = 0; $b = 0
      try{ $a = [int]$lanePlayers[0].hero_id }catch{}
      try{ $b = [int]$lanePlayers[1].hero_id }catch{}
      if($a -le 0 -or $b -le 0){ continue }
      $lo=[Math]::Min($a,$b); $hi=[Math]::Max($a,$b); $pairKey = New-PairKey $lo $hi
      $targetDict = if($laneCode -eq 3){ $duosOff } else { $duosSafe }
      if(-not $targetDict.ContainsKey($pairKey)){ $targetDict[$pairKey] = @{ a=$lo; b=$hi; games=0; wins=0 } }
      $targetDict[$pairKey].games++
      if($teamWon){ $targetDict[$pairKey].wins++ }
    }
  }
  # Ward logs
  foreach($p in @($m.players)){
    if(-not $p){ continue }
    # Dewards per player
    $aid=0; try{ $aid=[int64]$p.account_id }catch{}
    if($aid -gt 0){
      $dew=0; try{ $dew=[int]$p.obs_kills }catch{}
      if($dew -gt 0){ if(-not $playerDewards.ContainsKey($aid)){ $playerDewards[$aid]=0 }; $playerDewards[$aid]+=$dew }
    }
    # Build slot -> account_id map for this match once (cheap to rebuild)
    $slotToAid = @{}
    foreach($pp in @($m.players)){
      if(-not $pp){ continue }
      $sa = 0; $aid2 = 0
      try{ $sa=[int]$pp.player_slot }catch{}
      try{ $aid2=[int64]$pp.account_id }catch{}
      if($aid2 -gt 0){ $slotToAid[$sa] = $aid2 }
    }
    # Observers placed by this player
    $pObs = @(); try{ $pObs = @($p.obs_log) }catch{}
    foreach($o in $pObs){
      # Normalize to integer grid to ensure consistent keys and matching with removals
      $ix = 0; $iy = 0
      try{ $ix = [int]([Math]::Round([double]$o.x)) }catch{}
      try{ $iy = [int]([Math]::Round([double]$o.y)) }catch{}
      if(-not $wardPlacement.ContainsKey($mid)){ $wardPlacement[$mid]=@() }
      # Store side/team/aid for viewer enrichment
      $side = if($isRad){ 'Radiant' } else { 'Dire' }
      $teamId = if($isRad){ $radTeam } else { $direTeam }
      $aidp = 0; try{ $aidp=[int64]$p.account_id }catch{}
      $wardPlacement[$mid] += ,([pscustomobject]@{ x=$ix; y=$iy; time=[int]$o.time; side=$side; teamId=$teamId; aid=$aidp })
      if($aidp -gt 0){ if(-not $obsPlacerCount.ContainsKey($aidp)){ $obsPlacerCount[$aidp]=0 }; $obsPlacerCount[$aidp]++ }
    }
  # Observers removed (left) for this player
    $pObsLeft = @(); try{ $pObsLeft = @($p.obs_left_log) }catch{}
    foreach($ol in $pObsLeft){
      $ix = 0; $iy = 0
      try{ $ix = [int]([Math]::Round([double]$ol.x)) }catch{}
      try{ $iy = [int]([Math]::Round([double]$ol.y)) }catch{}
      if(-not $wardRemoval.ContainsKey($mid)){ $wardRemoval[$mid]=@() }
      $wardRemoval[$mid] += ,([pscustomobject]@{ x=$ix; y=$iy; time=[int]$ol.time })
      # Attribute deward to attacker if available
      $attSlotSet = $false
      $aslot = $null
      try{ if($ol.PSObject.Properties.Name -contains 'player_slot'){ $aslot = [int]$ol.player_slot; $attSlotSet = $true } }catch{}
      if(-not $attSlotSet){ try{ if($ol.PSObject.Properties.Name -contains 'slot'){ $aslot = [int]$ol.slot; $attSlotSet = $true } }catch{} }
      if($attSlotSet -and $slotToAid.ContainsKey($aslot)){
        $atkAid = [int64]$slotToAid[$aslot]
        if($atkAid -gt 0){ if(-not $playerDewards.ContainsKey($atkAid)){ $playerDewards[$atkAid]=0 }; $playerDewards[$atkAid]++ }
      } else {
        # Fallback: map attackername hero -> player
        try{
          $an = ''+$ol.attackername
          if($an -and $an -like 'npc_dota_hero*'){
            $hidAtk = 0; if($heroNameToId.ContainsKey($an)){ $hidAtk = [int]$heroNameToId[$an] }
            if($hidAtk -gt 0){
              foreach($pp in @($m.players)){
                $hidp=0; try{ $hidp=[int]$pp.hero_id }catch{}
                if($hidp -eq $hidAtk){ $aidp=0; try{ $aidp=[int64]$pp.account_id }catch{}; if($aidp -gt 0){ if(-not $playerDewards.ContainsKey($aidp)){ $playerDewards[$aidp]=0 }; $playerDewards[$aidp]++ }; break }
              }
            }
          }
        }catch{}
      }
    }
    # Sentry placements for this player (pressure proxy)
    try{
      $pSen = @(); try{ $pSen = @($p.sen_log) }catch{}
      foreach($se in $pSen){
        $sx=0; $sy=0; try{ $sx=[int]([Math]::Round([double]$se.x)) }catch{}; try{ $sy=[int]([Math]::Round([double]$se.y)) }catch{}
        $st=0; try{ $st=[int]$se.time }catch{}
        $coord = "$sx,$sy"
        if(-not $sentryCountBy.ContainsKey($coord)){ $sentryCountBy[$coord]=0 }
        $sentryCountBy[$coord]++
        $sideSen = if($isRad){ 'Radiant' } else { 'Dire' }
        if(-not $sentryBySide.ContainsKey($coord)){ $sentryBySide[$coord] = @{ Radiant=@{count=0}; Dire=@{count=0} } }
        $sentryBySide[$coord][$sideSen].count++
        $teamIdSen = if($isRad){ $radTeam } else { $direTeam }
        if($teamIdSen -gt 0){ if(-not $sentryByTeam.ContainsKey($coord)){ $sentryByTeam[$coord]=@{} }
          if(-not $sentryByTeam[$coord].ContainsKey($teamIdSen)){ $sentryByTeam[$coord][$teamIdSen] = @{ count=0 } }
          $sentryByTeam[$coord][$teamIdSen].count++
        }
        if(-not $sentrySamples.ContainsKey($coord)){ $sentrySamples[$coord]=@() }
        $aidp=0; try{ $aidp=[int64]$p.account_id }catch{}
        $sentrySamples[$coord] += ,([pscustomobject]@{ t=$st; side=$sideSen; teamId=$teamIdSen; aid=$aidp })
      }
    }catch{}
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
  # Captains (if present in details)
  try {
    $rc = 0; try { $rc = [int64]$m.radiant_captain } catch {}
    $dc = 0; try { $dc = [int64]$m.dire_captain } catch {}
    if($rc -gt 0){ if(-not $captainMap.ContainsKey($rc)){ $captainMap[$rc] = @{ games=0; wins=0 } }; $captainMap[$rc].games++; if($radWin){ $captainMap[$rc].wins++ } }
    if($dc -gt 0){ if(-not $captainMap.ContainsKey($dc)){ $captainMap[$dc] = @{ games=0; wins=0 } }; $captainMap[$dc].games++; if(-not $radWin){ $captainMap[$dc].wins++ } }
  } catch {}
}

# Compute ward lifetimes per (x,y) and build viewer samples + bySide/byTeam aggregates
$wardStats = @{}
foreach($mid in $wardPlacement.Keys){
  $placements = $wardPlacement[$mid]
  $removals = @(); if($wardRemoval.ContainsKey($mid)){ $removals = $wardRemoval[$mid] }
  $matchDur = 0; if($matchDurations.ContainsKey($mid)){ $matchDur = [int]$matchDurations[$mid] }
  $used = New-Object System.Collections.Generic.List[object]
  foreach($p in $placements | Sort-Object time){
    $matchRemoval = $null
    foreach($r in ($removals | Sort-Object time)){
      if(($r.x -eq $p.x) -and ($r.y -eq $p.y) -and -not ($used -contains $r) -and $r.time -ge $p.time){ $matchRemoval=$r; break }
    }
    if($matchRemoval){ $used.Add($matchRemoval) | Out-Null }
    $life = 0
    if($matchRemoval){ $life = [int]($matchRemoval.time - $p.time) } elseif($matchDur -gt 0) { $life = [int]([Math]::Min($matchDur, 4200) - $p.time) }
    if($life -lt 0){ $life = 0 }
    $coord = "$($p.x),$($p.y)"
    if(-not $wardStats.ContainsKey($coord)){ $wardStats[$coord] = @{ count=0; total=0 } }
    $wardStats[$coord].count++ ; $wardStats[$coord].total += $life
    # Build viewer samples and aggregates by side/team
    if(-not $obsSamplesBy.ContainsKey($coord)){ $obsSamplesBy[$coord]=@() }
    $obsSamplesBy[$coord] += ,([pscustomobject]@{ t=[int]$p.time; life=[int]$life; side=([string]$p.side); teamId=[int]$p.teamId; aid=[int64]$p.aid })
    if(-not $wardBySide.ContainsKey($coord)){ $wardBySide[$coord] = @{ Radiant=@{count=0; total=0}; Dire=@{count=0; total=0} } }
    if(($p.side -eq 'Radiant') -or ($p.side -eq 'Dire')){ $wardBySide[$coord][$p.side].count++; $wardBySide[$coord][$p.side].total += $life }
    if([int]$p.teamId -gt 0){ if(-not $wardByTeam.ContainsKey($coord)){ $wardByTeam[$coord]=@{} }
      if(-not $wardByTeam[$coord].ContainsKey([int]$p.teamId)){ $wardByTeam[$coord][[int]$p.teamId] = @{ count=0; total=0 } }
      $wardByTeam[$coord][[int]$p.teamId].count++; $wardByTeam[$coord][[int]$p.teamId].total += $life
    }
  }
}

# Build duo arrays
function Get-DuoArray($dict){
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
  return ($out | Sort-Object -Property winrate, games -Descending)
}
$duosOffArr = Get-DuoArray $duosOff
$duosSafeArr = Get-DuoArray $duosSafe

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

# Draft precomputation from picks_bans
try {
  foreach($m in $detailed){
    if(-not $m){ continue }
    $radWin = $false; try{ $radWin = [bool]$m.radiant_win }catch{}
    $pbs = @(); try{ $pbs = @($m.picks_bans) }catch{}
    if((@($pbs)).Count -eq 0){ continue }
    $draftMatches++
    $radList = New-Object System.Collections.Generic.List[object]
    $dirList = New-Object System.Collections.Generic.List[object]
    foreach($pb in $pbs){
      $hid = 0; try{ $hid = [int]$pb.hero_id }catch{}
      if($hid -le 0){ continue }
      $isPick = $false; try{ $isPick = [bool]$pb.is_pick }catch{}
      $team = $null; $side = $null
      try{ $team = $pb.team }catch{}
      if($null -ne $team){ if([int]$team -eq 0){ $side='Radiant' } elseif([int]$team -eq 1){ $side='Dire' } }
      if(-not $side){ try{ if($pb.PSObject.Properties.Name -contains 'is_radiant'){ $side = ($pb.is_radiant) ? 'Radiant' : 'Dire' } }catch{} }
      $order=0; try{ $order = [int]($pb.order); if($order -eq 0){ $order = [int]($pb.pick_order) }; if($order -eq 0){ $order = [int]($pb.draft_order) } }catch{}
      if($isPick){
        if(-not $draftPickStats.ContainsKey($hid)){ $draftPickStats[$hid] = @{ picks=0; wins=0 } }
        $draftPickStats[$hid].picks++
        if($side -eq 'Radiant'){ $radList.Add(@{ hid=$hid; order=$order }) | Out-Null } elseif($side -eq 'Dire'){ $dirList.Add(@{ hid=$hid; order=$order }) | Out-Null }
      } else {
        if(-not $draftBanCount.ContainsKey($hid)){ $draftBanCount[$hid]=0 }
        $draftBanCount[$hid]++
      }
    }
    function TeamWon($s){ if($s -eq 'Radiant'){ return $radWin } else { return (-not $radWin) } }
    foreach($side in @('Radiant','Dire')){
      $list = if($side -eq 'Radiant'){ $radList } else { $dirList }
      $ordered = @($list | Sort-Object { $_.order })
      if((@($ordered)).Count -ge 1){
        $fp = $ordered[0]
        if($fp -and $fp.hid -gt 0){ if(-not $draftFirstPick.ContainsKey($fp.hid)){ $draftFirstPick[$fp.hid] = @{ count=0; wins=0 } }; $draftFirstPick[$fp.hid].count++; if(TeamWon $side){ $draftFirstPick[$fp.hid].wins++ } }
      }
      if((@($ordered)).Count -ge 2){
        $a=[int]$ordered[0].hid; $b=[int]$ordered[1].hid; if($a -gt 0 -and $b -gt 0){ $lo=[Math]::Min($a,$b); $hi=[Math]::Max($a,$b); $key="$lo-$hi"; if(-not $draftOpeningPairs.ContainsKey($key)){ $draftOpeningPairs[$key] = @{ a=$lo; b=$hi; games=0; wins=0 } }; $draftOpeningPairs[$key].games++; if(TeamWon $side){ $draftOpeningPairs[$key].wins++ } }
      }
      # Attribute pick wins to heroes on winning side
      if(TeamWon $side){ foreach($ev in $list){ $hid=[int]$ev.hid; if($hid -gt 0 -and $draftPickStats.ContainsKey($hid)){ $draftPickStats[$hid].wins++ } } }
    }
  }
} catch { Write-Verbose "Draft precompute failed: $($_.Exception.Message)" }

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

# ---------- Build Ward Viewer precomputed block ----------
# Teams list for viewer (id/name)
$viewerTeams = @()
foreach($tid in $teamStats.Keys){ $nm=''; try{ $nm = ''+$teamStats[$tid].name }catch{}; $viewerTeams += [pscustomobject]@{ id = [int]$tid; name = if($nm){ $nm } else { "Team $tid" } } }
# Players list (only those who placed observers)
$viewerPlayers = @()
foreach($aid in $obsPlacerCount.Keys){
  $nm = if($playerMeta.ContainsKey($aid)){ ''+$playerMeta[$aid].name } else { "Player $aid" }
  $viewerPlayers += [pscustomobject]@{ id=[int64]$aid; name=$nm; count=[int]$obsPlacerCount[$aid] }
}
$viewerPlayers = $viewerPlayers | Sort-Object -Property name
# Spots with samples, bySide/byTeam
$viewerSpots = @()
foreach($coord in $wardStats.Keys){
  $ws = $wardStats[$coord]; $parts = $coord -split ','; $wx=0;$wy=0; if($parts.Length -ge 2){ [int]::TryParse($parts[0],[ref]$wx)|Out-Null; [int]::TryParse($parts[1],[ref]$wy)|Out-Null }
  $samples = @(); if($obsSamplesBy.ContainsKey($coord)){ $samples = @($obsSamplesBy[$coord]) }
  $sideAgg = @{ Radiant = @{ count=0; total=0 }; Dire = @{ count=0; total=0 } }
  if($wardBySide.ContainsKey($coord)){ $s=$wardBySide[$coord]; $sideAgg.Radiant.count = [int]$s.Radiant.count; $sideAgg.Radiant.total = [int]$s.Radiant.total; $sideAgg.Dire.count = [int]$s.Dire.count; $sideAgg.Dire.total = [int]$s.Dire.total }
  $teamAgg = @{}
  if($wardByTeam.ContainsKey($coord)){
    foreach($tid in $wardByTeam[$coord].Keys){
      $k = [string]([int]$tid)
      $teamAgg[$k] = @{ count = [int]$wardByTeam[$coord][$tid].count; total = [int]$wardByTeam[$coord][$tid].total }
    }
  }
  # Build spot record (without Intelligence fields)
  $viewerSpots += [pscustomobject]@{ spot=$coord; x=[int]$wx; y=[int]$wy; count=[int]$ws.count; total=[int]$ws.total; bySide=$sideAgg; byTeam=$teamAgg; samples=$samples }
}
# Sentries with samples, bySide/byTeam
$viewerSentries = @()
foreach($coord in $sentryCountBy.Keys){
  $parts=$coord -split ','; $sx=0;$sy=0; if($parts.Length -ge 2){ [int]::TryParse($parts[0],[ref]$sx)|Out-Null; [int]::TryParse($parts[1],[ref]$sy)|Out-Null }
  $count = [int]$sentryCountBy[$coord]
  $sideAgg = @{ Radiant = @{ count=0 }; Dire = @{ count=0 } }
  if($sentryBySide.ContainsKey($coord)){ $s=$sentryBySide[$coord]; $sideAgg.Radiant.count = [int]$s.Radiant.count; $sideAgg.Dire.count = [int]$s.Dire.count }
  $teamAgg = @{}
  if($sentryByTeam.ContainsKey($coord)){
    foreach($tid in $sentryByTeam[$coord].Keys){
      $k = [string]([int]$tid)
      $teamAgg[$k] = @{ count = [int]$sentryByTeam[$coord][$tid].count }
    }
  }
  $samples = @(); if($sentrySamples.ContainsKey($coord)){ $samples = @($sentrySamples[$coord]) }
  $viewerSentries += [pscustomobject]@{ spot=$coord; x=[int]$sx; y=[int]$sy; count=$count; bySide=$sideAgg; byTeam=$teamAgg; samples=$samples }
}

# Player dewards
$mostDewards = @(); foreach($aid in $playerDewards.Keys){ $mostDewards += [pscustomobject]@{ account_id=$aid; name=$playerMeta[$aid].name; count=$playerDewards[$aid] } }
$mostDewards = $mostDewards | Sort-Object count -Descending | Select-Object -First 8

# Player events lists (expanded for correct brace closure)
function Build-EventList($map){
  $arr=@()
  foreach($aid in $map.Keys){
    $evMatches=$map[$aid] | Sort-Object -Unique
    $arr += [pscustomobject]@{ account_id=$aid; name=$playerMeta[$aid].name; count=(@($evMatches)).Count; matches=$evMatches }
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

# Draft precompute result arrays
$draftContest = @()
foreach($hid in $draftPickStats.Keys){ $pk=$draftPickStats[$hid]; $bn= if($draftBanCount.ContainsKey($hid)){ [int]$draftBanCount[$hid] } else { 0 }; $draftContest += [pscustomobject]@{ hid=[int]$hid; picks=[int]$pk.picks; pickWins=[int]$pk.wins; bans=$bn; contest=[int]($pk.picks + $bn); wrPick= if($pk.picks -gt 0){ [double]$pk.wins/$pk.picks } else { 0 } } }
$draftFirst = @(); foreach($hid in $draftFirstPick.Keys){ $fp=$draftFirstPick[$hid]; $draftFirst += [pscustomobject]@{ hid=[int]$hid; count=[int]$fp.count; wins=[int]$fp.wins; wr= if($fp.count -gt 0){ [double]$fp.wins/$fp.count } else { 0 } } }
$draftPairs = @(); foreach($k in $draftOpeningPairs.Keys){ $v=$draftOpeningPairs[$k]; $draftPairs += [pscustomobject]@{ a=[int]$v.a; b=[int]$v.b; games=[int]$v.games; wins=[int]$v.wins; wr= if($v.games -gt 0){ [double]$v.wins/$v.games } else { 0 } } }
# Build top bans table with rates
$draftTopBans = @()
foreach($hid in $draftBanCount.Keys){
  $bans = [int]$draftBanCount[$hid]
  $picks = if($draftPickStats.ContainsKey($hid)){ [int]$draftPickStats[$hid].picks } else { 0 }
  $contestCnt = $picks + $bans
  $banRate = if($draftMatches -gt 0){ [double]$bans / $draftMatches } else { 0 }
  $contestRate = if($draftMatches -gt 0){ [double]$contestCnt / $draftMatches } else { 0 }
  $draftTopBans += [pscustomobject]@{ hid=[int]$hid; bans=$bans; banRate=$banRate; contestRate=$contestRate; picks=$picks }
}
$draftTopBans = $draftTopBans | Sort-Object -Property bans, banRate -Descending
# Captains list (top by WR then games)
$captArr = @()
foreach($aid in $captainMap.Keys){
  $v = $captainMap[$aid]
  $wr = if($v.games -gt 0){ [double]$v.wins/$v.games } else { 0 }
  $captArr += [pscustomobject]@{ aid=[int64]$aid; games=[int]$v.games; wins=[int]$v.wins; wr=$wr }
}
$captArr = $captArr | Sort-Object -Property wr, games -Descending | Select-Object -First 10

# Precompute charts for Draft viewer
$chartTopPicked = @()
$topPickedSrc = $draftContest | Sort-Object -Property picks, wrPick -Descending | Select-Object -First 5
foreach($it in $topPickedSrc){ $chartTopPicked += [pscustomobject]@{ hid=[int]$it.hid; picks=[int]$it.picks; wr=[double]$it.wrPick } }
$chartTopBanned = @()
$topBannedSrc = $draftTopBans | Select-Object -First 5
foreach($it in $topBannedSrc){
  $hid = [int]$it.hid
  $wr = 0.0
  if($draftPickStats.ContainsKey($hid)){
    $p = [int]$draftPickStats[$hid].picks
    $w = [int]$draftPickStats[$hid].wins
    if($p -gt 0){ $wr = [double]$w / [double]$p }
  }
  $chartTopBanned += [pscustomobject]@{ hid=$hid; bans=[int]$it.bans; wr=$wr }
}
# Sort & limit like client
$draftContest = $draftContest | Sort-Object -Property contest, picks, bans -Descending | Select-Object -First 20
$draftFirst = $draftFirst | Sort-Object -Property count, wr -Descending | Select-Object -First 20
$draftPairs = $draftPairs | Sort-Object -Property wr, games -Descending | Select-Object -First 20

# Build player->team mapping (choose most frequent team_id per player in this league)
$playerTeams = @()
foreach($aid in $playerTeamCount.Keys){
  $map = $playerTeamCount[$aid]
  $bestTeam = 0; $bestCnt = -1
  foreach($tid in $map.Keys){ if($map[$tid] -gt $bestCnt){ $bestCnt = $map[$tid]; $bestTeam = [int]$tid } }
  if($bestTeam -gt 0){
    $tname = if($teamStats.ContainsKey($bestTeam)){ ''+$teamStats[$bestTeam].name } else { "Team $bestTeam" }
    $pname = if($playerMeta.ContainsKey($aid)){ ''+$playerMeta[$aid].name } else { "Player $aid" }
    $playerTeams += [pscustomobject]@{ account_id=[int64]$aid; name=$pname; team_id=[int]$bestTeam; team_name=$tname; appearances=[int]$bestCnt }
  } else {
    # No team observed; still include entry with team_id 0 if player appeared
    if($playerStats.ContainsKey($aid)){
      $pname = if($playerMeta.ContainsKey($aid)){ ''+$playerMeta[$aid].name } else { "Player $aid" }
      $playerTeams += [pscustomobject]@{ account_id=[int64]$aid; name=$pname; team_id=0; team_name=''; appearances=[int]$playerStats[$aid].games }
    }
  }
}

# Aggregate object
$report = [ordered]@{
  league = @{ id=$leagueId; name=$leagueNameResolved; slug=$slug; from=$fromUnix; to=$toUnix };
  generated = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds();
  playerTeams = @($playerTeams);
  highlights = [ordered]@{
  duos = @{ offlane= @($duosOffArr); safelane= @($duosSafeArr) };
  draft = @{ contest=@($draftContest); firstPicks=@($draftFirst); openingPairs=@($draftPairs); topBans=@($draftTopBans); totalMatches=[int]$draftMatches; captains=@($captArr); charts=@{ topPicked=@($chartTopPicked); topBanned=@($chartTopBanned) } };
  heroes = @{ best=@($bestHeroes); worst=@($worstHeroes); all=@($heroesAll) };
  wards = @{ bestSpots=@($bestSpots); worstSpots=@($worstSpots); mostDewards=@($mostDewards); allSpots=@($wardAll); viewer = @{ spots=@($viewerSpots); sentries=@($viewerSentries); teams=@($viewerTeams); players=@($viewerPlayers) } };
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
  if(Test-Path -LiteralPath $leagueMatchesFile){ Copy-Item -LiteralPath $leagueMatchesFile -Destination (Join-Path $publicLeagueDataDir 'matches.json') -Force }
  # Ensure shared data files are published under docs/data for the viewers
  $dataSrcDir = Join-Path (Join-Path $PSScriptRoot '..') 'data'
  $dataDestDir = Join-Path $docs 'data'
  if(-not (Test-Path -LiteralPath $dataDestDir)) { New-Item -ItemType Directory -Path $dataDestDir -Force | Out-Null }
  foreach($fn in 'heroes.json','maps.json','manifest.json','info.json'){
    try{
      $srcFile = Join-Path $dataSrcDir $fn
      if(Test-Path -LiteralPath $srcFile){ Copy-Item -LiteralPath $srcFile -Destination (Join-Path $dataDestDir $fn) -Force }
    }catch{ Write-Warning ("Failed to publish {0}: {1}" -f $fn, $_.Exception.Message) }
  }
  # Publish monthly shards if present (data/matches/*.json) to docs/data/matches
  try{
    $matchesSrcDir = Join-Path $dataSrcDir 'matches'
    if(Test-Path -LiteralPath $matchesSrcDir){
      $matchesDestDir = Join-Path $dataDestDir 'matches'
      if(-not (Test-Path -LiteralPath $matchesDestDir)) { New-Item -ItemType Directory -Path $matchesDestDir -Force | Out-Null }
      Get-ChildItem -LiteralPath $matchesSrcDir -Filter '*.json' | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $matchesDestDir $_.Name) -Force
      }
    }
  }catch{ Write-Warning ("Failed to publish monthly shards: {0}" -f $_.Exception.Message) }
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
  # Publish pro players list for league viewer lookups
  try{
    $proSrc = Join-Path (Join-Path $PSScriptRoot '..') 'data\cache\OpenDota\proPlayers.json'
    if(Test-Path -LiteralPath $proSrc){
      $ppOutDir = Join-Path $docs 'data/cache/OpenDota'
      if(-not (Test-Path -LiteralPath $ppOutDir)){ New-Item -ItemType Directory -Path $ppOutDir -Force | Out-Null }
      Copy-Item -LiteralPath $proSrc -Destination (Join-Path $ppOutDir 'proPlayers.json') -Force
    }
  }catch{ Write-Warning ("Failed to publish proPlayers.json: {0}" -f $_.Exception.Message) }
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
$query = "?from=$fromUnix`&to=$toUnix`&tab=highlights`&lock=1`&league=$slug`&leaguePath=data"
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
  </div>
  <iframe src='../../../$dynamicFile$query' loading='eager' referrerpolicy='no-referrer'></iframe>
</body>
</html>
"@
Set-Content -LiteralPath (Join-Path $folder 'index.html') -Value $html -Encoding UTF8
Write-Host ("Wrote league report wrapper: {0}" -f (Join-Path $folder 'index.html'))

# ---------- Update reports.json ----------
function Get-NormalizedHref([string]$href){
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
    if($items[$i] -and $items[$i].href){ $items[$i].href = (Get-NormalizedHref -href ([string]$items[$i].href)) }
  }
  $nhref = Get-NormalizedHref -href $href
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
  $h=Get-NormalizedHref -href ([string]$it.href)
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

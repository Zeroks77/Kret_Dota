<#
  ligascript.ps1  (repo-ready; incremental all-time + cached range reports)
  League: "Kret's EU Dota League" (LeagueID 18438)

  Data sources:
    - Steam Web API: GetMatchHistory (league matches), GetMatchDetails (fallback)
    - OpenDota: /matches/{id}, /constants/heroes, /constants/patch

  Modes:
    - All-time incremental: -Range All together with -StatePath and -StableAll
        * reads/writes state JSON (default: data/alltime-state.json)
        * fetches only new matches (match_id > last_seen_match_id or unseen)
        * appends compact match records to state.matches
        * updates name maps (playerNames, teamNames)
        * publishes stable filename when -StableAll is set

    - Range reports: -Range 30|60|120|Patch
        * if state with matches exists, derive the report purely from cache (no API calls)
        * else (first run) fetches from APIs as fallback

  Output:
    - Publishes HTML into repo/docs/ (GitHub Pages)
    - Maintains docs/index.html (report browser)
    - Commits/pushes with GITHUB_TOKEN when -GitAutoPush is used (GitHub Actions)

  Security:
    - Pass Steam key via -SteamApiKey or env:STEAM_API_KEY (no hard-coded key)
#>

param(
  [ValidateSet("30","60","120","Patch","All")]
  [string]$Range            = "30",
  [string]$OutFile          = ".\krets-overview.html",
  [int]   $MaxMatches       = 400,
  [int]   $OpenDotaDelayMs  = 1200,
  [int]   $SteamDelayMs     = 700,
  [int]   $MaxRetries       = 5,
  [int]   $InitialBackoffMs = 800,
  [int]   $TopN             = 10,
  [int]   $MinGamesPlayerTop= 5,
  [int]   $MinGamesTeamTop  = 3,
  [int]   $MinGamesHeroTopPlayer = 3,
  [int]   $MinGamesTeamTopPlayer = 3,
  [int]   $IndexMax         = 100,

  # Repo & CI
  [string]$RepoPath         = $PSScriptRoot,
  [switch]$PublishToRepo,
  [switch]$GitAutoPush,

  # All-time incremental state (and cache for ranges)
  [string]$StatePath        = (Join-Path ($PSScriptRoot) "data\alltime-state.json"),
  [switch]$StableAll,                  # write stable filename for All range
  [int]   $ProcessedKeep    = 8000,    # keep last N processed match IDs in state (auxiliary)

  # Steam key (param takes precedence; falls back to env:STEAM_API_KEY)
  [string]$SteamApiKey      = $env:STEAM_API_KEY,

  [switch]$VerboseLog,

  # Cache controls
  [switch]$DisableCache,
  [string]$CachePath        = (Join-Path ($PSScriptRoot) "data\cache"),
  [int]   $ConstantsTtlDays = 7,

  # Prefer reading pre-sharded monthly match JSONs under docs/data/matches for range runs
  [switch]$PreferShards
)

# ===== FIXED LEAGUE =====
$LEAGUE_NAME   = "Kret's EU Dota League"
$LEAGUE_ID     = 18438

# ===== Constants =====
$OD_BASE       = "https://api.opendota.com/api"
$OD_MATCH_URL  = { param($id) "https://www.opendota.com/matches/$id" }
$OD_PLAYER_URL = { param($id) "https://www.opendota.com/players/$id" }
$STEAM_BASE    = "https://api.steampowered.com/IDOTA2Match_570"

$SPECTRAL_BASE = "https://courier.spectral.gg/images/dota"
function Get-HeroPortraitUrl([string]$tag){ return "$SPECTRAL_BASE/portraits/$tag.png" }
function Get-TeamLogoUrl([int]$teamId){ if(-not $teamId){ return "$SPECTRAL_BASE/teams/default.png" } "$SPECTRAL_BASE/teams/square_$teamId.png" }
function Get-LeagueBannerUrl([int]$leagueId){ return "$SPECTRAL_BASE/leagues/${leagueId}_banner.png" }

# Time
$TZ = $null
try { $TZ = [TimeZoneInfo]::FindSystemTimeZoneById("Europe/Berlin") } catch {
  try { $TZ = [TimeZoneInfo]::FindSystemTimeZoneById("W. Europe Standard Time") } catch { $TZ = [TimeZoneInfo]::Local }
}
$EN = [System.Globalization.CultureInfo]::GetCultureInfo("en-US")

# ===== Utils =====
function Get-RoleName($lane_role, $is_roaming) {
  if ($is_roaming) { return "Roam" }
  switch ([int]$lane_role) { 1 { "Safe" } 2 { "Mid" } 3 { "Off" } 4 { "Jungle" } default { "Unknown" } }
}
function HtmlEscape([string]$s){ [System.Net.WebUtility]::HtmlEncode($s) }
function FmtPct([double]$x){ "{0:P1}" -f $x }
function Inc-Map([hashtable]$map, [string]$key) { if ($map.ContainsKey($key)) { $map[$key] = [int]$map[$key] + 1 } else { $map[$key] = 1 } }
function Slugify([string]$s){ if (-not $s) { return "" }; $t=$s.ToLowerInvariant(); $t=$t -replace "[^a-z0-9]+","-"; $t=$t.Trim("-"); return $t }

function Select-TopCandidate {
  param([System.Collections.Generic.List[object]]$Candidates,[int]$MinGames=1)
  $cand = $Candidates | Where-Object { $_.games -ge $MinGames } |
    Sort-Object @{e='winrate';Descending=$true}, @{e='games';Descending=$true}, @{e='wins';Descending=$true} |
    Select-Object -First 1
  if ($cand) { return $cand }
  return ($Candidates | Sort-Object @{e='winrate';Descending=$true}, @{e='games';Descending=$true}, @{e='wins';Descending=$true} | Select-Object -First 1)
}

# ===== HTTP & Throttling =====
$global:__LastOpenDotaCall = [datetime]::MinValue
$global:__LastSteamCall    = [datetime]::MinValue

$DefaultHeaders = @{ 'Accept'='application/json'; 'User-Agent'='krets-ligascript/2.3 (+https://opendota.com)' }

# ===== Disk cache helpers =====
function Use-Cache { return (-not $DisableCache) }
function Get-CacheFile([string]$service,[string]$kind,[string]$name){
  $dir = Join-Path $CachePath (Join-Path $service $kind)
  return (Join-Path $dir ("{0}.json" -f $name))
}
function Try-ReadJsonCache([string]$path,[int]$maxAgeDays){
  if (-not (Use-Cache)) { return $null }
  if (-not (Test-Path $path)) { return $null }
  if ($maxAgeDays -ge 0) {
    $age = (Get-Date) - (Get-Item $path).LastWriteTimeUtc
    if ($age.TotalDays -gt $maxAgeDays) { return $null }
  }
  try { return ((Get-Content -Path $path -Raw -Encoding UTF8) | ConvertFrom-Json) } catch { return $null }
}
function Write-JsonCache([object]$obj,[string]$path){
  if (-not (Use-Cache)) { return }
  Ensure-Dir $path
  try { ($obj | ConvertTo-Json -Depth 100) | Set-Content -Path $path -Encoding UTF8 } catch {}
}

function Start-Throttle([int]$ms, [ref]$last) {
  $elapsed = (Get-Date) - $last.Value
  $minSpan = [TimeSpan]::FromMilliseconds($ms)
  if ($elapsed -lt $minSpan) { Start-Sleep -Milliseconds ([int][math]::Max(0, ($minSpan - $elapsed).TotalMilliseconds)) }
}

function Build-QueryString([hashtable]$params) {
  $pairs = New-Object System.Collections.Generic.List[string]
  foreach ($k in $params.Keys) { [void]$pairs.Add( [uri]::EscapeDataString([string]$k) + "=" + [uri]::EscapeDataString([string]$params[$k]) ) }
  return ($pairs -join '&')
}
function Build-SteamUri([string]$endpoint, [hashtable]$query){
  if ([string]::IsNullOrWhiteSpace($SteamApiKey)) {
    throw "Steam API Key missing. Provide -SteamApiKey or set env STEAM_API_KEY."
  }
  $q=@{}; foreach($k in $query.Keys){ $q[$k]=$query[$k] }; $q["key"]=$SteamApiKey
  return ("{0}{1}?{2}" -f $STEAM_BASE, $endpoint, (Build-QueryString $q))
}
function Redact-Key([string]$uri){ if ($null -eq $uri) { return "" }; return ($uri -replace "([?&]key=)[^&]+", '$1REDACTED') }

function Invoke-Json {
  param([string]$Method,[string]$Uri,[hashtable]$Headers,[object]$Body,[ValidateSet("OpenDota","Steam","Other")][string]$Service="Other")
  $backoff = $InitialBackoffMs
  for ($attempt=0; $attempt -le $MaxRetries; $attempt++) {
    try {
      if ($Service -eq "OpenDota") { Start-Throttle -ms $OpenDotaDelayMs -last ([ref]$global:__LastOpenDotaCall) }
      if ($Service -eq "Steam")    { Start-Throttle -ms $SteamDelayMs    -last ([ref]$global:__LastSteamCall) }

      $u = $Uri; $hdrs = if ($Headers -and $Headers.Count -gt 0) { $Headers } else { $DefaultHeaders }
      if ($VerboseLog) {
        $dispUri = if ($Service -eq 'Steam') { Redact-Key $u } else { $u }
        Write-Host "HTTP $Method $dispUri" -ForegroundColor DarkGray
      }

      $params = @{ Method=$Method; Uri=$u; Headers=$hdrs; ErrorAction='Stop' }
      if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 50); $params.ContentType = "application/json" }
      $resp = Invoke-RestMethod @params
      if ($Service -eq "OpenDota") { $global:__LastOpenDotaCall = Get-Date }
      if ($Service -eq "Steam")    { $global:__LastSteamCall    = Get-Date }
      if ($null -ne $resp) { return $resp }

      if ($VerboseLog) { Write-Warning "Null response, trying webrequest fallback..." }
      $raw = Invoke-WebRequest -Uri $u -Headers $hdrs -Method $Method -ErrorAction Stop
      if ($raw -and $raw.Content) { return ($raw.Content | ConvertFrom-Json -ErrorAction Stop) }

      return $null
    } catch {
      $ex = $_.Exception
      $status = try { $ex.Response.StatusCode.Value__ } catch { 0 }
      if ($VerboseLog) { Write-Warning "Request failed ($status): $($ex.Message)" }
      if ($attempt -ge $MaxRetries -or ($status -ne 429 -and ($status -lt 500 -or $status -ge 600))) { throw }
      Start-Sleep -Milliseconds $backoff
      $backoff = [math]::Min($backoff * 2, 10000)
    }
  }
}

# ===== APIs =====
function Get-OpenDotaMatch([long]$matchId) {
  $cf = Get-CacheFile -service 'OpenDota' -kind 'matches' -name ([string]$matchId)
  $hit = Try-ReadJsonCache -path $cf -maxAgeDays -1
  if ($hit) { return $hit }
  $resp = Invoke-Json -Method GET -Uri "$OD_BASE/matches/$matchId" -Service OpenDota -Headers $DefaultHeaders
  if ($resp) { Write-JsonCache -obj $resp -path $cf }
  return $resp
}
function Get-OpenDotaHeroesConst {
  $cf = Get-CacheFile -service 'OpenDota' -kind 'constants' -name 'heroes'
  $hit = Try-ReadJsonCache -path $cf -maxAgeDays $ConstantsTtlDays
  if ($hit) { return $hit }
  $resp = Invoke-Json -Method GET -Uri "$OD_BASE/constants/heroes"  -Service OpenDota -Headers $DefaultHeaders
  if ($resp) { Write-JsonCache -obj $resp -path $cf }
  return $resp
}
function Get-OpenDotaPatchConst {
  $cf = Get-CacheFile -service 'OpenDota' -kind 'constants' -name 'patch'
  $hit = Try-ReadJsonCache -path $cf -maxAgeDays $ConstantsTtlDays
  if ($hit) { return $hit }
  $resp = Invoke-Json -Method GET -Uri "$OD_BASE/constants/patch"   -Service OpenDota -Headers $DefaultHeaders
  if ($resp) { Write-JsonCache -obj $resp -path $cf }
  return $resp
}

function Get-SteamMatchHistory([int]$leagueId, [int]$cutoffUnix, [int]$maxMatches){
  $list = New-Object System.Collections.Generic.List[object]
  $startAt = $null
  while ($list.Count -lt $maxMatches) {
    $qs = @{ league_id=$leagueId; matches_requested=100 }
    if ($startAt) { $qs.start_at_match_id = $startAt }
    $uri = Build-SteamUri "/GetMatchHistory/v1/" $qs
    $resp = Invoke-Json -Method GET -Uri $uri -Service Steam -Headers $DefaultHeaders
    if (-not $resp -or -not $resp.result -or -not $resp.result.matches) { break }
    $chunk = $resp.result.matches
    if ($chunk.Count -eq 0) { break }

    foreach ($m in $chunk) {
      $mid = [long]$m.match_id
      $st  = if ($m.start_time) { [long]$m.start_time } else { 0 }
      if ($cutoffUnix -gt 0 -and $st -lt $cutoffUnix) { $startAt = $null; break }
      $list.Add([pscustomobject]@{ match_id=$mid; start_time=$st }) | Out-Null
      if ($list.Count -ge $maxMatches) { break }
    }
    if ($list.Count -ge $maxMatches) { break }
    $minId = ($chunk | Measure-Object -Property match_id -Minimum).Minimum
    if (-not $minId) { break }
    $startAt = [long]$minId - 1
  }
  $seen = New-Object 'System.Collections.Generic.HashSet[long]'
  $out = @()
  foreach ($m in ($list | Sort-Object start_time -Descending)) {
    $mid = [long]$m.match_id
    if (-not $seen.Contains($mid)) { [void]$seen.Add($mid); $out += $m }
  }
  return $out | Select-Object -First $maxMatches
}

function Get-SteamMatchDetails([long]$matchId){
  $cf = Get-CacheFile -service 'Steam' -kind 'matches' -name ([string]$matchId)
  $hit = Try-ReadJsonCache -path $cf -maxAgeDays -1
  if ($hit) { return $hit }
  $uri  = Build-SteamUri "/GetMatchDetails/v1/" @{ match_id = $matchId }
  $resp = Invoke-Json -Method GET -Uri $uri -Service Steam -Headers $DefaultHeaders
  if ($resp -and $resp.result) { Write-JsonCache -obj $resp.result -path $cf; return $resp.result } else { return $null }
}

# ===== State =====
function Ensure-Dir([string]$p){ $d=[System.IO.Path]::GetDirectoryName($p); if($d -and -not (Test-Path $d)){ New-Item -ItemType Directory -Path $d -Force | Out-Null } }
function New-EmptyState {
  return [pscustomobject]@{
    last_seen_match_id   = 0
    last_seen_start_time = 0
    processed_match_ids  = @()
    matches              = @()           # list of compact match records
    playerNames          = @{}           # account_id -> last known name
    teamNames            = @{}           # team_id -> last known name
    # (optional cached aggregates kept for "All" quick page rendering if you want)
    teams                = @{}
    players              = @{}
    teamPlayers          = @{}
    heroStats            = @{}
    heroPlayerAgg        = @{}
  }
}

# Helpers: normalize maps for JSON and from JSON
function To-HashtableFromJson($obj){
  if ($obj -is [hashtable]) { return $obj }
  $h=@{}
  if ($null -eq $obj) { return $h }
  foreach ($prop in $obj.PSObject.Properties) { $h[$prop.Name] = $prop.Value }
  return $h
}
function To-NestedHashtableFromJson($obj){
  if ($obj -is [hashtable]) {
    foreach($k in @($obj.Keys)){
      $v = $obj[$k]
      if ($v -isnot [hashtable] -and $v -is [psobject]) { $obj[$k] = To-HashtableFromJson $v }
    }
    return $obj
  }
  $outer=@{}
  if ($null -eq $obj) { return $outer }
  foreach ($prop in $obj.PSObject.Properties) {
    $inner = $prop.Value
    if ($inner -isnot [hashtable] -and $inner -is [psobject]) { $inner = To-HashtableFromJson $inner }
    $outer[$prop.Name] = $inner
  }
  return $outer
}
function Map-StringKeys([hashtable]$map){
  $out=@{}
  if ($null -eq $map) { return $out }
  foreach ($k in $map.Keys) {
    $v = $map[$k]
    if ($v -is [hashtable]) { $v = Map-StringKeys $v }
    $out[[string]$k] = $v
  }
  return $out
}
function Load-State([string]$path){
  if (-not (Test-Path $path)) { return New-EmptyState }
  $raw = Get-Content -Path $path -Raw -Encoding UTF8
  if ([string]::IsNullOrWhiteSpace($raw)) { return New-EmptyState }
  $st = ($raw | ConvertFrom-Json)
  if (-not $st.matches)      { $st | Add-Member -NotePropertyName matches -NotePropertyValue @() }
  if (-not $st.playerNames)  { $st | Add-Member -NotePropertyName playerNames -NotePropertyValue @{} }
  if (-not $st.teamNames)    { $st | Add-Member -NotePropertyName teamNames -NotePropertyValue @{} }
  if (-not $st.teams)        { $st | Add-Member -NotePropertyName teams -NotePropertyValue @{} }
  if (-not $st.players)      { $st | Add-Member -NotePropertyName players -NotePropertyValue @{} }
  if (-not $st.teamPlayers)  { $st | Add-Member -NotePropertyName teamPlayers -NotePropertyValue @{} }
  if (-not $st.heroStats)    { $st | Add-Member -NotePropertyName heroStats -NotePropertyValue @{} }
  if (-not $st.heroPlayerAgg){ $st | Add-Member -NotePropertyName heroPlayerAgg -NotePropertyValue @{} }
  if (-not $st.processed_match_ids){ $st | Add-Member -NotePropertyName processed_match_ids -NotePropertyValue @() }
  # Convert JSON objects to Hashtables for runtime safety
  $st.playerNames   = To-HashtableFromJson $st.playerNames
  $st.teamNames     = To-HashtableFromJson $st.teamNames
  $st.teams         = To-HashtableFromJson $st.teams
  $st.players       = To-HashtableFromJson $st.players
  $st.heroStats     = To-HashtableFromJson $st.heroStats
  $st.teamPlayers   = To-NestedHashtableFromJson $st.teamPlayers
  $st.heroPlayerAgg = To-NestedHashtableFromJson $st.heroPlayerAgg
  return $st
}
function Save-State([object]$state,[string]$path){
  Ensure-Dir $path
  ($state | ConvertTo-Json -Depth 100) | Set-Content -Path $path -Encoding UTF8
}

# ===== Build hero map =====
function Build-HeroMap($heroesConst) {
  $map = @{}
  if ($null -eq $heroesConst) { return $map }
  if ($heroesConst -is [System.Collections.IDictionary]) {
    foreach ($kv in $heroesConst.GetEnumerator()) {
      $v = $kv.Value; if ($v -eq $null) { continue }
      $id  = [int]$v.id
      $tag = ([string]$v.name) -replace 'npc_dota_hero_',''
      $map[$id] = [pscustomobject]@{ id=$id; tag=$tag; name=$v.localized_name }
    } ; return $map
  }
  foreach ($prop in $heroesConst.PSObject.Properties) {
    $v = $prop.Value; if ($v -eq $null) { continue }
    $id  = [int]$v.id
    $tag = ([string]$v.name) -replace 'npc_dota_hero_',''
    $map[$id] = [pscustomobject]@{ id=$id; tag=$tag; name=$v.localized_name }
  } ; return $map
}

# ===== Cutoff helpers =====
function Get-LatestPatchUnix() {
  $patch = Get-OpenDotaPatchConst
  if ($null -eq $patch) { return 0 }
  $latest = $null
  foreach ($prop in $patch.PSObject.Properties) {
    $v = $prop.Value; if ($v -eq $null) { continue }
    $d = $null
    if ($v.date -is [string]) { [void][DateTimeOffset]::TryParse($v.date, [ref]$d) }
    elseif ($v.date -is [double] -or $v.date -is [int]) { $d = [DateTimeOffset]::FromUnixTimeSeconds([long]$v.date) }
    if ($d -ne $null) { if ($latest -eq $null -or $d -gt $latest) { $latest = $d } }
  }
  if ($latest -eq $null) { return 0 }
  return [int][double]$latest.ToUnixTimeSeconds()
}
function Get-CutoffUnix { param([string]$Range)
  switch ($Range) {
    "30"  { [int][double]([DateTimeOffset]::UtcNow.AddDays(-30).ToUnixTimeSeconds()) }
    "60"  { [int][double]([DateTimeOffset]::UtcNow.AddDays(-60).ToUnixTimeSeconds()) }
    "120" { [int][double]([DateTimeOffset]::UtcNow.AddDays(-120).ToUnixTimeSeconds()) }
    "All" { 0 }
    "Patch" { Get-LatestPatchUnix }
    default { [int][double]([DateTimeOffset]::UtcNow.AddDays(-30).ToUnixTimeSeconds()) }
  }
}

# ===== Compact match record builder =====
function Build-MatchRecordFromOD($md){
  $players = @()
  foreach ($p in $md.players) {
    $tid = if ($p.isRadiant) { [int]$md.radiant_team_id } else { [int]$md.dire_team_id }
    $players += [pscustomobject]@{
      account_id = [int64]$p.account_id
      hero_id    = [int]$p.hero_id
      is_radiant = [bool]$p.isRadiant
      personaname= $p.personaname
      team_id    = $tid
    }
  }
  $picks_bans = @()
  if ($md.picks_bans) {
    foreach ($pb in $md.picks_bans) {
      $picks_bans += [pscustomobject]@{ hero_id=[int]$pb.hero_id; is_pick=[bool]$pb.is_pick }
    }
  }
  return [pscustomobject]@{
    match_id         = [long]$md.match_id
    start_time       = [int64]$md.start_time
    radiant_win      = [bool]$md.radiant_win
    radiant_team_id  = [int]$md.radiant_team_id
    dire_team_id     = [int]$md.dire_team_id
    radiant_name     = $md.radiant_name
    dire_name        = $md.dire_name
    players          = $players
    picks_bans       = $picks_bans
  }
}
function Build-MatchRecordFromSteam($sd){
  $players = @()
  foreach ($p in $sd.players) {
    $players += [pscustomobject]@{
      account_id = [int64]$p.account_id
      hero_id    = [int]$p.hero_id
      is_radiant = [bool]($p.player_slot -band 0x80 -eq 0)
      personaname= $null
      team_id    = $null   # will be set from radiant/dire ids below
    }
  }
  $picks_bans = @()
  if ($sd.picks_bans) {
    foreach ($pb in $sd.picks_bans) {
      $picks_bans += [pscustomobject]@{ hero_id=[int]$pb.hero_id; is_pick=[bool]$pb.is_pick }
    }
  }
  return [pscustomobject]@{
    match_id         = [long]$sd.match_id
    start_time       = [int64]$sd.start_time
    radiant_win      = [bool]$sd.radiant_win
    radiant_team_id  = [int]$sd.radiant_team_id
    dire_team_id     = [int]$sd.dire_team_id
    radiant_name     = $sd.radiant_name
    dire_name        = $sd.dire_name
    players          = $players
    picks_bans       = $picks_bans
  }
}

# ===== Aggregate from a subset of cached matches =====
function Aggregate-FromMatches {
  param(
    [array]$MatchesSubset,
    [hashtable]$PlayerNamesMap,
    [hashtable]$TeamNamesMap
  )
  $teams=@{}; $players=@{}; $teamPlayers=@{}; $heroStats=@{}; $heroPlayerAgg=@{}
  foreach ($m in $MatchesSubset) {
    $radWin = [bool]$m.radiant_win
    $radTeamId = [int]$m.radiant_team_id
    $dirTeamId = [int]$m.dire_team_id
    $radName = if ($TeamNamesMap[[string]$radTeamId]) { $TeamNamesMap[[string]$radTeamId] } elseif ($m.radiant_name) { $m.radiant_name } else { "Radiant" }
    $dirName = if ($TeamNamesMap[[string]$dirTeamId]) { $TeamNamesMap[[string]$dirTeamId] } elseif ($m.dire_name) { $m.dire_name } else { "Dire" }

    if ($radTeamId) {
      if (-not $teams.ContainsKey($radTeamId)) { $teams[$radTeamId] = [pscustomobject]@{ team_id=$radTeamId; name=$radName; games=0; wins=0; losses=0 } }
      $teams[$radTeamId].games++; if ($radWin) { $teams[$radTeamId].wins++ } else { $teams[$radTeamId].losses++ }
      if ($radName -and $radName -ne "Radiant") { $teams[$radTeamId].name = $radName }
    }
    if ($dirTeamId) {
      if (-not $teams.ContainsKey($dirTeamId)) { $teams[$dirTeamId] = [pscustomobject]@{ team_id=$dirTeamId; name=$dirName; games=0; wins=0; losses=0 } }
      $teams[$dirTeamId].games++; if ($radWin) { $teams[$dirTeamId].losses++ } else { $teams[$dirTeamId].wins++ }
      if ($dirName -and $dirName -ne "Dire") { $teams[$dirTeamId].name = $dirName }
    }

    if ($m.picks_bans) {
      foreach ($pb in $m.picks_bans) {
        $hid = [int]$pb.hero_id
        if (-not $heroStats.ContainsKey($hid)) { $heroStats[$hid] = [pscustomobject]@{ picks=0; wins=0; bans=0 } }
        if (-not $pb.is_pick) { $heroStats[$hid].bans++ }
      }
    }

    foreach ($p in $m.players) {
      $id = [int64]$p.account_id
      if ($id -le 0) { continue }
      if (-not $players.ContainsKey($id)) {
        $nm = if ($p.personaname) { $p.personaname } elseif ($PlayerNamesMap[[string]$id]) { $PlayerNamesMap[[string]$id] } else { "Player $id" }
        $players[$id] = [pscustomobject]@{ account_id=$id; name=$nm; games=0; wins=0; roles=@{}; heroes=@{}; profile = (& $OD_PLAYER_URL $id) }
      }
      $ps = $players[$id]; $ps.games++
      $won = if ($p.is_radiant) { $radWin } else { -not $radWin }
      if ($won) { $ps.wins++ }
      Inc-Map $ps.roles "Unknown"   # role is not stored in cache; optional

      $hid = [int]$p.hero_id
      if ($hid -gt 0) {
        Inc-Map $ps.heroes ([string]$hid)
        if (-not $heroStats.ContainsKey($hid)) { $heroStats[$hid] = [pscustomobject]@{ picks=0; wins=0; bans=0 } }
        $heroStats[$hid].picks++; if ($won) { $heroStats[$hid].wins++ }

        if (-not $heroPlayerAgg.ContainsKey($hid)) { $heroPlayerAgg[$hid] = @{} }
        if (-not $heroPlayerAgg[$hid].ContainsKey($id)) {
          $heroPlayerAgg[$hid][$id] = [pscustomobject]@{ account_id=$id; name=$ps.name; games=0; wins=0; profile=$ps.profile }
        }
        $hp = $heroPlayerAgg[$hid][$id]; $hp.games++; if ($won) { $hp.wins++ }
      }

      $teamId = if ($p.is_radiant) { $radTeamId } else { $dirTeamId }
      if ($teamId) {
        if (-not $teamPlayers.ContainsKey($teamId)) { $teamPlayers[$teamId] = @{} }
        if (-not $teamPlayers[$teamId].ContainsKey($id)) {
          $teamPlayers[$teamId][$id] = [pscustomobject]@{ account_id=$id; name=$ps.name; games=0; wins=0; profile=$ps.profile }
        }
        $tp = $teamPlayers[$teamId][$id]; $tp.games++; if ($won) { $tp.wins++ }
      }
    }
  }
  return [pscustomobject]@{
    teams=$teams; players=$players; teamPlayers=$teamPlayers; heroStats=$heroStats; heroPlayerAgg=$heroPlayerAgg
  }
}

# ===== Repo publishing (ASCII-safe Index) =====
function Save-ReportToRepo {
  param(
    [Parameter(Mandatory)][string]$RepoPath,
    [Parameter(Mandatory)][string]$Html,
    [Parameter(Mandatory)][string]$LeagueName,
    [Parameter(Mandatory)][string]$Range,
    [int]$IndexMax = 100,
    [switch]$GitAutoPush,
    [switch]$StableAll,
    [string[]]$ExtraCommitPaths
  )
  if (-not (Test-Path $RepoPath)) { throw "RepoPath not found: $RepoPath" }
  $docs = Join-Path $RepoPath "docs"
  if (-not (Test-Path $docs)) { New-Item -ItemType Directory -Path $docs -Force | Out-Null }

  $slugLeague = if ($LeagueName) { Slugify $LeagueName } else { "league" }
  switch ($Range) {
    "30"   { $rangeSlug = "30-days" }
    "60"   { $rangeSlug = "60-days" }
    "120"  { $rangeSlug = "120-days" }
    "Patch"{ $rangeSlug = "last-patch" }
    "All"  { $rangeSlug = "all-games" }
    default{ $rangeSlug = Slugify $Range }
  }
  $stamp = Get-Date -Format "yyyy-MM-dd_HHmm"
  if ($Range -eq "All" -and $StableAll) {
    $file = ($slugLeague + "_" + $rangeSlug + "_latest.html")
  } else {
    $file = ($slugLeague + "_" + $rangeSlug + "_" + $stamp + ".html")
  }
  $outPath = Join-Path $docs $file

  # Save report
  $Html | Set-Content -Path $outPath -Encoding UTF8

  # Collect items for index (newest first)
  $items = Get-ChildItem $docs -Filter "*.html" | Where-Object { $_.Name -ne "index.html" } |
           Sort-Object LastWriteTime -Descending | Select-Object -First $IndexMax

  function Map-RangeLabel([string]$slug){
    switch ($slug) {
      "30-days" {"30 days"} "60-days" {"60 days"} "120-days" {"120 days"} "last-patch" {"Last patch"} "all-games" {"All games"}
      default { $slug }
    }
  }
  function Detect-RangeSlug([string]$nm){
    $parts = [System.IO.Path]::GetFileNameWithoutExtension($nm).Split("_")
    if ($parts.Length -ge 3) { return $parts[$parts.Length-2] }
    return "unknown"
  }

  $entryRows = New-Object System.Collections.Generic.List[string]
  foreach($it in $items){
    $nm = $it.Name
    $href = "./$nm"
    $dtIso = (Get-Date $it.LastWriteTime -Format "yyyy-MM-dd HH:mm")
    $rangeSlug2 = Detect-RangeSlug $nm
    $rangeLabel = Map-RangeLabel $rangeSlug2
    $ticks = [string]$it.LastWriteTime.Ticks
    $line = ('<li class="item" data-range="{0}" data-time="{1}"><a href="{2}">{3} - {4}</a></li>' -f $rangeSlug2, $ticks, $href, $dtIso, $rangeLabel)
    [void]$entryRows.Add($line)
  }
  $listHtml = ($entryRows -join "`n")

$indexHtml = @"
<!doctype html>
<html lang='en'>
<head>
<meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>$(HtmlEscape $LeagueName) - Reports</title>
<link href='https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap' rel='stylesheet'>
<style>
:root{--bg:#0b1020;--panel:#121832;--muted:#9aa3b2;--text:#eef1f7;--accent:#6da6ff;--chip:#1a2142;--border:rgba(255,255,255,.08)}
*{box-sizing:border-box}
body{margin:0;background:radial-gradient(1200px 600px at 10% -10%, #172045, transparent 60%), var(--bg);color:var(--text);font-family:Inter,system-ui,Segoe UI,Roboto,Arial,sans-serif;height:100vh;display:flex}
.sidebar{width:360px;min-width:280px;max-width:420px;background:linear-gradient(180deg,rgba(255,255,255,.04),rgba(255,255,255,.02));border-right:1px solid var(--border);padding:16px;display:flex;flex-direction:column;gap:12px}
.brand h1{font-size:20px;margin:0}
.sub{color:var(--muted);font-size:13px}
.filters{display:flex;flex-wrap:wrap;gap:6px}
.btn{padding:6px 10px;border:1px solid var(--border);border-radius:10px;background:#0e1533;color:var(--text);cursor:pointer;font-size:12px}
.btn.active{outline:2px solid rgba(109,166,255,.6)}
.search{width:100%;padding:8px 10px;border-radius:10px;border:1px solid var(--border);background:rgba(255,255,255,.04);color:var(--text);outline:none}
.list{margin:0;padding:0;list-style:none;overflow:auto;border:1px solid var(--border);border-radius:12px;flex:1;background:rgba(255,255,255,.02)}
.item a{display:block;padding:10px 12px;color:var(--text);text-decoration:none;border-bottom:1px solid rgba(255,255,255,.06)}
.item a:hover{background:rgba(255,255,255,.06)}
.item.active a{background:rgba(109,166,255,.18)}
.viewer{flex:1;display:flex;flex-direction:column}
.viewerbar{display:flex;align-items:center;justify-content:space-between;padding:10px 12px;border-bottom:1px solid var(--border);background:rgba(255,255,255,.03)}
.viewerbar .title{font-weight:600}
.viewerbar .nav{display:flex;gap:8px}
.nav .btn{padding:6px 10px}
iframe{border:0;flex:1;width:100%}
a{color:var(--accent)}
</style>
</head>
<body>
  <aside class='sidebar'>
    <div class='brand'>
      <h1>Reports - $(HtmlEscape $LeagueName)</h1>
      <div class='sub'>Pick a run or filter by range.</div>
    </div>
    <div class='filters'>
  <a class='btn' href='./dynamic.html' target='_blank' rel='noopener' title='Interactive page with custom timeframe'>Dynamic view</a>
      <button class='btn' data-f='all'>All entries</button>
      <button class='btn' data-f='30-days'>30 days</button>
      <button class='btn' data-f='60-days'>60 days</button>
      <button class='btn' data-f='120-days'>120 days</button>
      <button class='btn' data-f='last-patch'>Last patch</button>
      <button class='btn' data-f='all-games'>All games</button>
    </div>
    <input id='q' class='search' type='text' placeholder='Search (date/range) ...'>
    <ul id='list' class='list'>
$listHtml
    </ul>
  </aside>

  <main class='viewer'>
    <div class='viewerbar'>
      <div class='title' id='viewerTitle'>-</div>
      <div class='nav'>
        <button class='btn' id='prevBtn' title='Previous (ArrowUp)'><- Previous</button>
        <button class='btn' id='nextBtn' title='Next (ArrowDown)'>Next -></button>
        <a class='btn' id='openNew' target='_blank' rel='noopener'>Open in new tab</a>
      </div>
    </div>
    <iframe id='frame' src='about:blank' loading='eager' referrerpolicy='no-referrer'></iframe>
  </main>

<script>
(function(){
  const list = document.getElementById('list');
  const items = Array.from(list.querySelectorAll('.item'));
  const q = document.getElementById('q');
  const btns = Array.from(document.querySelectorAll('.filters .btn'));
  const frame = document.getElementById('frame');
  const title = document.getElementById('viewerTitle');
  const openNew = document.getElementById('openNew');
  const prevBtn = document.getElementById('prevBtn');
  const nextBtn = document.getElementById('nextBtn');
  let filter = 'all'; let selIndex = -1;

  function vis(){ return items.filter(li => li.style.display !== 'none'); }
  function txt(li){ const a=li.querySelector('a'); return a ? a.textContent.trim() : li.getAttribute('data-range'); }

  function apply(){
    const term = q.value.trim().toLowerCase(); let n=0;
    items.forEach(li=>{
      const rg = li.getAttribute('data-range'), t = txt(li).toLowerCase();
      const ok = (filter==='all' || rg===filter) && (!term || t.includes(term));
      li.style.display = ok ? '' : 'none'; if (ok) n++;
    });
    if (n===0){ selIndex=-1; frame.src='about:blank'; title.textContent='No results'; openNew.removeAttribute('href'); }
    else if (selIndex<0){ select(0); }
    sync();
  }
  function select(i){
    const v = vis(); if (!v.length) return;
    if (i<0) i=0; if (i>=v.length) i=v.length-1;
    v.forEach(li => li.classList.remove('active'));
    const li=v[i]; li.classList.add('active');
    const a=li.querySelector('a');
    if (a){ const href=a.getAttribute('href'); frame.src=href; title.textContent=a.textContent.trim(); openNew.setAttribute('href',href); history.replaceState(null,'','#file='+encodeURIComponent(href)); }
    selIndex=i; li.scrollIntoView({block:'nearest'}); sync();
  }
  function sync(){ const v=vis(); prevBtn.disabled = (selIndex<=0 || !v.length); nextBtn.disabled = (selIndex>=v.length-1 || !v.length); }

  items.forEach(li=>li.addEventListener('click', e=>{e.preventDefault(); const v=vis(); const idx=v.indexOf(li); if (idx>=0) select(idx);}));
  btns.forEach(b=>b.addEventListener('click', ()=>{ btns.forEach(x=>x.classList.remove('active')); b.classList.add('active'); filter=b.getAttribute('data-f'); apply(); }));
  q.addEventListener('input', apply);
  prevBtn.addEventListener('click', ()=> select(selIndex-1));
  nextBtn.addEventListener('click', ()=> select(selIndex+1));
  document.addEventListener('keydown', ev=>{ if (ev.key==='ArrowUp'){ev.preventDefault(); select(selIndex-1);} if (ev.key==='ArrowDown'){ev.preventDefault(); select(selIndex+1);} });

  function init(){
    const params = new URLSearchParams(location.search);
    const rangeQ = params.get('range');
    const file = new URLSearchParams(location.hash.replace(/^#/, '')).get('file');
    if (rangeQ){ const btn=btns.find(b=>b.getAttribute('data-f')===rangeQ); if (btn) btn.click(); } else { btns[0].classList.add('active'); }
    if (file){ const t=items.find(li => li.querySelector('a')?.getAttribute('href')===file); if (t && t.style.display!=='none'){ const v=vis(); const idx=v.indexOf(t); if (idx>=0){ select(idx); return; } } }
    apply();
  }
  init();
})();
</script>
</body>
</html>
"@

  $indexPath = Join-Path $docs "index.html"
  $indexHtml | Set-Content -Path $indexPath -Encoding UTF8

  if ($GitAutoPush) {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $git) { Write-Warning "git not found - skipping push." }
    else {
      Push-Location $RepoPath
      try {
        git add -- "docs/$file" "docs/index.html" | Out-Null
        if ($ExtraCommitPaths) {
          foreach ($p in $ExtraCommitPaths) {
            $rel = (Resolve-Path $p).Path.Replace((Resolve-Path $RepoPath).Path, "").TrimStart("\","/")
            git add -- $rel | Out-Null
          }
        }
        $msg = "publish: $file"
        git commit -m $msg | Out-Null
        git push | Out-Null
        Write-Host "git push OK." -ForegroundColor Green
      } catch { Write-Warning ("git push failed: " + $_.Exception.Message) } finally { Pop-Location }
    }
  }
  return $outPath
}

# ===== Data export for client-side dynamic viewer =====
function Export-DataForClient {
  param(
    [Parameter(Mandatory)][string]$RepoPath,
    [Parameter(Mandatory)][object]$State,
    [Parameter(Mandatory)][hashtable]$HeroMap
  )
  $dataDir = Join-Path $RepoPath "data"
  if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }

  # Optionally export a small info file (no full matches blob here to avoid duplication)
  $info = [pscustomobject]@{
    league_id    = $LEAGUE_ID
    league_name  = $LEAGUE_NAME
    generated_at = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  }
  ($info | ConvertTo-Json -Depth 10) | Set-Content -Path (Join-Path $dataDir "info.json") -Encoding UTF8

  # Export hero metadata map for client-side labels and images
  $heroesOut = @{}
  foreach ($hid in $HeroMap.Keys) {
    $v = $HeroMap[$hid]
    $heroesOut[[string]$hid] = @{ id=$v.id; tag=$v.tag; name=$v.name; img=(Get-HeroPortraitUrl $v.tag) }
  }
  ($heroesOut | ConvertTo-Json -Depth 5) | Set-Content -Path (Join-Path $dataDir "heroes.json") -Encoding UTF8

  # Also export monthly-sharded matches under docs/data/matches/YYYY-MM.json and a manifest
  $matchesDir = Join-Path $dataDir "matches"
  if (-not (Test-Path $matchesDir)) { New-Item -ItemType Directory -Path $matchesDir -Force | Out-Null }

  function Get-MonthKey([long]$unix){
    try { $dto=[DateTimeOffset]::FromUnixTimeSeconds([long]$unix); return $dto.ToString("yyyy-MM") } catch { return "unknown" }
  }
  $buckets = @{}
  foreach ($m in $State.matches) {
    $mk = Get-MonthKey ([long]$m.start_time)
    if (-not $buckets.ContainsKey($mk)) { $buckets[$mk] = New-Object System.Collections.Generic.List[object] }
    $buckets[$mk].Add($m) | Out-Null
  }
  $manifest = @()
  $exportedFiles = @((Join-Path $dataDir "info.json"), (Join-Path $dataDir "heroes.json"))
  foreach ($mk in ($buckets.Keys | Sort-Object)) {
  $arr = $buckets[$mk].ToArray()
    $outPath = Join-Path $matchesDir ("{0}.json" -f $mk)
    ($arr | ConvertTo-Json -Depth 100) | Set-Content -Path $outPath -Encoding UTF8
    $manifest += [pscustomobject]@{ month=$mk; file=("matches/{0}.json" -f $mk); count=$arr.Count }
    $exportedFiles += ,$outPath
  }
  $manObj = [pscustomobject]@{ updated=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); months=$manifest }
  $manifestPath = Join-Path $dataDir "manifest.json"
  ($manObj | ConvertTo-Json -Depth 10) | Set-Content -Path $manifestPath -Encoding UTF8
  $exportedFiles += ,$manifestPath

  return $exportedFiles
}

# Load matches from monthly shards under docs/data/matches for range runs
function Load-MatchesFromShards {
  param([string]$RepoPath,[int]$CutoffUnix)
  $base = if ($RepoPath) { $RepoPath } else { $PSScriptRoot }
  $matchesDir = Join-Path $base "data\matches"
  if (-not (Test-Path $matchesDir)) { return @() }
  $files = Get-ChildItem $matchesDir -Filter "*.json" -File -ErrorAction SilentlyContinue
  if (-not $files -or $files.Count -eq 0) { return @() }
  $all = New-Object System.Collections.Generic.List[object]
  foreach ($f in $files) {
    try {
      $arr = (Get-Content -Path $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json)
    if ($arr) { foreach($x in $arr){ $all.Add($x) | Out-Null } }
    } catch { }
  }
  $allArr = $all.ToArray()
  $subset = $allArr
  if ($CutoffUnix -gt 0) { $subset = @($allArr | Where-Object { [int64]$_.start_time -ge $CutoffUnix }) }
  return $subset
}

# ================= MAIN =================
try {
  Write-Host "League: $LEAGUE_NAME (ID $LEAGUE_ID)"
  $cutoffUnix = Get-CutoffUnix -Range $Range
  if ($Range -ne "All") { Write-Host "Range: $Range -> from Unix $cutoffUnix" }

  # Load hero constants once
  Write-Host "Fetching hero constants (OpenDota) ..." -ForegroundColor Cyan
  $heroesConst = Get-OpenDotaHeroesConst
  $heroMap = Build-HeroMap $heroesConst

  # Load or init state
  $state = Load-State -path $StatePath

  # Helper to compute aggregates from cache for range runs
  function Compute-FromCache([string]$range,[int]$cutUnix){
    $subset = $null
    if ($PreferShards) {
      $subset = Load-MatchesFromShards -RepoPath $RepoPath -CutoffUnix $cutUnix
      if ($subset -and $subset.Count -gt 0) { return (Aggregate-FromMatches -MatchesSubset $subset -PlayerNamesMap $state.playerNames -TeamNamesMap $state.teamNames) }
    }
    if (-not $state.matches -or $state.matches.Count -eq 0) { return $null }
    $subset = if ($cutUnix -gt 0) { @($state.matches | Where-Object { [int64]$_.start_time -ge $cutUnix }) } else { @($state.matches) }
    if ($range -eq "Patch" -and $cutUnix -gt 0) { $subset = @($state.matches | Where-Object { [int64]$_.start_time -ge $cutUnix }) }
    if ($subset.Count -eq 0) { return $null }
    return (Aggregate-FromMatches -MatchesSubset $subset -PlayerNamesMap $state.playerNames -TeamNamesMap $state.teamNames)
  }

  # Aggregation stores for the report
  $teams = @{}; $players=@{}; $teamPlayers=@{}; $heroStats=@{}; $heroPlayerAgg=@{}

  if ($Range -eq "All") {
    # ===== All-time incremental: fetch only new, append to state, update aggregates =====
    Write-Host "All-time mode: loading latest league matches from Steam ..." -ForegroundColor Cyan
    $recent = Get-SteamMatchHistory -leagueId $LEAGUE_ID -cutoffUnix 0 -maxMatches $MaxMatches
    if (-not $recent) { throw "No matches returned by Steam." }

    # Build set of existing match ids to avoid duplicates
    $existingIds = New-Object 'System.Collections.Generic.HashSet[long]'
    foreach ($x in $state.matches) { [void]$existingIds.Add([long]$x.match_id) }

    $lastSeenId   = [long]$state.last_seen_match_id
    $lastSeenTime = [long]$state.last_seen_start_time
    $processed    = @(); if ($state.processed_match_ids) { $processed = @($state.processed_match_ids) }

    # Adopt existing aggregates to continue (optional, keeps "All" fast)
    $teams         = $state.teams
    $players       = $state.players
    $teamPlayers   = $state.teamPlayers
    $heroStats     = $state.heroStats
    $heroPlayerAgg = $state.heroPlayerAgg

    $new = @($recent | Where-Object {
      (-not $existingIds.Contains([long]$_.match_id)) -and (-not $processed -or ($processed -notcontains ([long]$_.match_id)))
    })
    Write-Host ("New matches detected: " + $new.Count)

    foreach ($m in $new | Sort-Object start_time) {
      $mid = [long]$m.match_id
      $md = $null
      try { $md = Get-OpenDotaMatch -matchId $mid } catch { $md = $null }
      $rec = $null
      if ($md) {
        $rec = Build-MatchRecordFromOD $md
      } else {
        $sd = Get-SteamMatchDetails -matchId $mid
        if ($sd) { $rec = Build-MatchRecordFromSteam $sd }
      }
      if (-not $rec) { continue }

      # fill team_id on Steam fallback players
      foreach ($pp in $rec.players) {
        if ($pp.team_id -eq $null) {
          $tid = if ($pp.is_radiant) { [int]$rec.radiant_team_id } else { [int]$rec.dire_team_id }
          $pp.team_id = $tid
        }
        if ($pp.personaname) { $state.playerNames[[string]$pp.account_id] = $pp.personaname }
      }
      if ($rec.radiant_team_id -and $rec.radiant_name) { $state.teamNames[[string]$rec.radiant_team_id] = $rec.radiant_name }
      if ($rec.dire_team_id -and $rec.dire_name)       { $state.teamNames[[string]$rec.dire_team_id]    = $rec.dire_name }

      # append to cache
      $state.matches += ,$rec
      $processed += ,$mid
      if ($mid -gt $lastSeenId)   { $lastSeenId   = $mid }
      if ($rec.start_time -gt $lastSeenTime) { $lastSeenTime = [long]$rec.start_time }

      # update "All" aggregates as we go (same logic as before, using rec)
      $radWin = $rec.radiant_win
      $radTeamId = $rec.radiant_team_id; $dirTeamId = $rec.dire_team_id
      $radName = if ($rec.radiant_name) { $rec.radiant_name } else { "Radiant" }
      $dirName = if ($rec.dire_name)    { $rec.dire_name }    else { "Dire" }

      if ($radTeamId) {
        if (-not $teams.ContainsKey($radTeamId)) { $teams[$radTeamId] = [pscustomobject]@{ team_id=$radTeamId; name=$radName; games=0; wins=0; losses=0 } }
        $teams[$radTeamId].games++; if ($radWin) { $teams[$radTeamId].wins++ } else { $teams[$radTeamId].losses++ }
        if ($radName -and $radName -ne "Radiant") { $teams[$radTeamId].name = $radName }
      }
      if ($dirTeamId) {
        if (-not $teams.ContainsKey($dirTeamId)) { $teams[$dirTeamId] = [pscustomobject]@{ team_id=$dirTeamId; name=$dirName; games=0; wins=0; losses=0 } }
        $teams[$dirTeamId].games++; if ($radWin) { $teams[$dirTeamId].losses++ } else { $teams[$dirTeamId].wins++ }
        if ($dirName -and $dirName -ne "Dire") { $teams[$dirTeamId].name = $dirName }
      }

      if ($rec.picks_bans) {
        foreach ($pb in $rec.picks_bans) {
          $hid = [int]$pb.hero_id
          if (-not $heroStats.ContainsKey($hid)) { $heroStats[$hid] = [pscustomobject]@{ picks=0; wins=0; bans=0 } }
          if (-not $pb.is_pick) { $heroStats[$hid].bans++ }
        }
      }

      foreach ($p in $rec.players) {
        $id = [int64]$p.account_id
        if ($id -le 0) { continue }
        if (-not $players.ContainsKey($id)) {
          $nm = if ($state.playerNames[[string]$id]) { $state.playerNames[[string]$id] } else { "Player $id" }
          $players[$id] = [pscustomobject]@{ account_id=$id; name=$nm; games=0; wins=0; roles=@{}; heroes=@{}; profile = (& $OD_PLAYER_URL $id) }
        }
        $ps = $players[$id]; $ps.games++
        $won = if ($p.is_radiant) { $radWin } else { -not $radWin }
        if ($won) { $ps.wins++ }
        Inc-Map $ps.roles "Unknown"
        $hid = [int]$p.hero_id
        if ($hid -gt 0) {
          Inc-Map $ps.heroes ([string]$hid)
          if (-not $heroStats.ContainsKey($hid)) { $heroStats[$hid] = [pscustomobject]@{ picks=0; wins=0; bans=0 } }
          $heroStats[$hid].picks++; if ($won) { $heroStats[$hid].wins++ }

          if (-not $heroPlayerAgg.ContainsKey($hid)) { $heroPlayerAgg[$hid] = @{} }
          if (-not $heroPlayerAgg[$hid].ContainsKey($id)) {
            $heroPlayerAgg[$hid][$id] = [pscustomobject]@{ account_id=$id; name=$ps.name; games=0; wins=0; profile=$ps.profile }
          }
          $hp = $heroPlayerAgg[$hid][$id]; $hp.games++; if ($won) { $hp.wins++ }
        }

        $teamId = if ($p.is_radiant) { $radTeamId } else { $dirTeamId }
        if ($teamId) {
          if (-not $teamPlayers.ContainsKey($teamId)) { $teamPlayers[$teamId] = @{} }
          if (-not $teamPlayers[$teamId].ContainsKey($id)) {
            $teamPlayers[$teamId][$id] = [pscustomobject]@{ account_id=$id; name=$ps.name; games=0; wins=0; profile=$ps.profile }
          }
          $tp = $teamPlayers[$teamId][$id]; $tp.games++; if ($won) { $tp.wins++ }
        }
      }
    } # foreach new

    # trim processed ids list
    if ($processed.Count -gt $ProcessedKeep) { $processed = $processed | Select-Object -Last $ProcessedKeep }

    # write state back
    $state.last_seen_match_id   = $lastSeenId
    $state.last_seen_start_time = $lastSeenTime
    $state.processed_match_ids  = @($processed)
  $state.teams         = Map-StringKeys $teams
  $state.players       = Map-StringKeys $players
  $state.teamPlayers   = Map-StringKeys $teamPlayers
  $state.heroStats     = Map-StringKeys $heroStats
  $state.heroPlayerAgg = Map-StringKeys $heroPlayerAgg

    Save-State -state $state -path $StatePath
    $extraCommit = @($StatePath)  # ensure committed if -PublishToRepo

  } else {
    # ===== Range report (prefer cache) =====
    $agg = $null
    if ($Range -eq "Patch") {
      Write-Host "Resolving last patch cutoff via OpenDota ..." -ForegroundColor Cyan
      $cutoffUnix = Get-CutoffUnix -Range "Patch"
    }
    $agg = Compute-FromCache -range $Range -cutUnix $cutoffUnix
    if ($agg -ne $null) {
      Write-Host "Using cached matches from state to build range report." -ForegroundColor Green
      $teams = $agg.teams; $players = $agg.players; $teamPlayers = $agg.teamPlayers; $heroStats = $agg.heroStats; $heroPlayerAgg = $agg.heroPlayerAgg
    } else {
      # First install / empty cache fallback: fetch online just for this range
      Write-Host "Cache empty -> fetching from Steam/OpenDota for range ..." -ForegroundColor Yellow
      $matches = Get-SteamMatchHistory -leagueId $LEAGUE_ID -cutoffUnix $cutoffUnix -maxMatches $MaxMatches
      if (-not $matches -or $matches.Count -eq 0) { throw "No matches in the selected range." }

      foreach ($m in $matches) {
        $mid = [long]$m.match_id
        $md = $null
        try { $md = Get-OpenDotaMatch -matchId $mid } catch { $md = $null }
        $rec = $null
        if ($md) { $rec = Build-MatchRecordFromOD $md } else {
          $sd = Get-SteamMatchDetails -matchId $mid
          if ($sd) { $rec = Build-MatchRecordFromSteam $sd }
        }
        if ($rec) {
          # Aggregate in-memory for this run
          $agg2 = Aggregate-FromMatches -MatchesSubset @($rec) -PlayerNamesMap $state.playerNames -TeamNamesMap $state.teamNames
          # merge agg2 into current agg structures (single match each loop)
          # Teams
          foreach ($kv in $agg2.teams.GetEnumerator()) {
            $t=$kv.Value
            if (-not $teams.ContainsKey($t.team_id)) { $teams[$t.team_id] = [pscustomobject]@{ team_id=$t.team_id; name=$t.name; games=0; wins=0; losses=0 } }
            $teams[$t.team_id].games += $t.games; $teams[$t.team_id].wins += $t.wins; $teams[$t.team_id].losses += $t.losses
            if ($t.name -and $t.name -ne "Radiant" -and $t.name -ne "Dire") { $teams[$t.team_id].name = $t.name }
          }
          # Players
          foreach ($pv in $agg2.players.GetEnumerator()) {
            $p=$pv.Value
            if (-not $players.ContainsKey($p.account_id)) { $players[$p.account_id] = [pscustomobject]@{ account_id=$p.account_id; name=$p.name; games=0; wins=0; roles=@{}; heroes=@{}; profile=$p.profile } }
            $players[$p.account_id].games += $p.games; $players[$p.account_id].wins += $p.wins
            foreach ($rk in $p.roles.Keys) { Inc-Map $players[$p.account_id].roles $rk }
            foreach ($hk in $p.heroes.Keys) { $cnt=[int]$p.heroes[$hk]; for($i=0;$i -lt $cnt;$i++){ Inc-Map $players[$p.account_id].heroes $hk } }
          }
          # TeamPlayers
          foreach ($tk in $agg2.teamPlayers.Keys) {
            if (-not $teamPlayers.ContainsKey($tk)) { $teamPlayers[$tk] = @{} }
            foreach ($pp in $agg2.teamPlayers[$tk].Values) {
              if (-not $teamPlayers[$tk].ContainsKey($pp.account_id)) { $teamPlayers[$tk][$pp.account_id] = [pscustomobject]@{ account_id=$pp.account_id; name=$pp.name; games=0; wins=0; profile=$pp.profile } }
              $teamPlayers[$tk][$pp.account_id].games += $pp.games; $teamPlayers[$tk][$pp.account_id].wins += $pp.wins
            }
          }
          # HeroStats
          foreach ($hk in $agg2.heroStats.Keys) {
            if (-not $heroStats.ContainsKey($hk)) { $heroStats[$hk] = [pscustomobject]@{ picks=0; wins=0; bans=0 } }
            $heroStats[$hk].picks += $agg2.heroStats[$hk].picks
            $heroStats[$hk].wins  += $agg2.heroStats[$hk].wins
            $heroStats[$hk].bans  += $agg2.heroStats[$hk].bans
          }
          # HeroPlayerAgg
          foreach ($hk in $agg2.heroPlayerAgg.Keys) {
            if (-not $heroPlayerAgg.ContainsKey($hk)) { $heroPlayerAgg[$hk] = @{} }
            foreach ($pp in $agg2.heroPlayerAgg[$hk].Values) {
              if (-not $heroPlayerAgg[$hk].ContainsKey($pp.account_id)) {
                $heroPlayerAgg[$hk][$pp.account_id] = [pscustomobject]@{ account_id=$pp.account_id; name=$pp.name; games=0; wins=0; profile=$pp.profile }
              }
              $heroPlayerAgg[$hk][$pp.account_id].games += $pp.games
              $heroPlayerAgg[$hk][$pp.account_id].wins  += $pp.wins
            }
          }
        }
      }
    } # end fallback
  } # end range handling

  # ===== Build lists from aggregates =====
  $teamList = ($teams.Values | ForEach-Object {
    $wr = if ($_.games -gt 0) { [double]$_.wins / $_.games } else { 0 }
    [pscustomobject]@{ team_id=$_.team_id; name=$_.name; games=$_.games; wins=$_.wins; losses=$_.losses; winrate=$wr; logo=(Get-TeamLogoUrl $_.team_id) }
  }) | Sort-Object @{e='winrate';Descending=$true}, @{e='games';Descending=$true}

  $playerList = ($players.Values | ForEach-Object {
    $wr = if ($_.games -gt 0) { [double]$_.wins / $_.games } else { 0 }
    $topHeroes=@()
    if ($_.heroes.Count -gt 0) {
      $heroCounts = $_.heroes.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 3
      foreach ($hc in $heroCounts) {
        $hid=[int]$hc.Key; $cnt=$hc.Value
        $meta=$heroMap[$hid]; $hName= if($meta -and $meta.name){$meta.name}else{"Hero $hid"}
        $hTag = if($meta -and $meta.tag){$meta.tag}else{"default"}
        $topHeroes += [pscustomobject]@{ id=$hid; count=$cnt; name=$hName; tag=$hTag; img=(Get-HeroPortraitUrl $hTag) }
      }
    }
    [pscustomobject]@{ account_id=$_.account_id; name=$_.name; games=$_.games; wins=$_.wins; winrate=$wr; topHeroes=$topHeroes; profile=$_.profile }
  }) | Sort-Object @{e='winrate';Descending=$true}, @{e='games';Descending=$true}

  $heroSummary = ($heroStats.Keys | ForEach-Object {
    $hid=[int]$_; $hs=$heroStats[$hid]
    $picks=[int]$hs.picks; $wins=[int]$hs.wins; $bans=[int]$hs.bans
    $wr = if ($picks -gt 0) { [double]$wins / $picks } else { 0 }
    $meta=$heroMap[$hid]; $name= if($meta -and $meta.name){$meta.name}else{"Hero $hid"}
    $tag = if($meta -and $meta.tag){$meta.tag}else{"default"}
    [pscustomobject]@{ id=$hid; name=$name; tag=$tag; img=(Get-HeroPortraitUrl $tag); picks=$picks; wins=$wins; bans=$bans; winrate=$wr }
  })

  $topMostPicked = $heroSummary | Sort-Object @{e='picks';Descending=$true}, @{e='winrate';Descending=$true} | Select-Object -First $TopN
  $topBanned     = $heroSummary | Sort-Object @{e='bans';Descending=$true}, @{e='picks';Descending=$true} | Select-Object -First $TopN

  # top players/teams for header
  $topPlayersHdr = $playerList | Where-Object { $_.games -ge $MinGamesPlayerTop } |
                   Sort-Object @{e='winrate';Descending=$true}, @{e='games';Descending=$true} |
                   Select-Object -First $TopN
  $topTeamsHdr   = $teamList   | Where-Object { $_.games -ge $MinGamesTeamTop } |
                   Sort-Object @{e='winrate';Descending=$true}, @{e='games';Descending=$true} |
                   Select-Object -First $TopN

  # best player per team
  $teamTopPerformer=@{}
  foreach ($t in $teamList) {
    $tid=[int]$t.team_id
    if (-not $tid -or -not $teamPlayers.ContainsKey($tid)) { continue }
    $candArr = New-Object System.Collections.Generic.List[object]
    foreach ($pp in $teamPlayers[$tid].Values) {
      $wrp = if ($pp.games -gt 0) { [double]$pp.wins / $pp.games } else { 0 }
      $candArr.Add([pscustomobject]@{ name=$pp.name; account_id=$pp.account_id; games=$pp.games; wins=$pp.wins; winrate=$wrp; profile=$pp.profile }) | Out-Null
    }
    if ($candArr.Count -gt 0) {
      $best = Select-TopCandidate -Candidates $candArr -MinGames $MinGamesTeamTopPlayer
      if ($best) { $teamTopPerformer[$tid] = $best }
    }
  }
  # best player per hero
  $heroBestPlayer=@{}
  foreach ($hid in $heroPlayerAgg.Keys) {
    $candArr = New-Object System.Collections.Generic.List[object]
    foreach ($pp in $heroPlayerAgg[$hid].Values) {
      $wrp = if ($pp.games -gt 0) { [double]$pp.wins / $pp.games } else { 0 }
      $candArr.Add([pscustomobject]@{ name=$pp.name; account_id=$pp.account_id; games=$pp.games; wins=$pp.wins; winrate=$wrp; profile=$pp.profile }) | Out-Null
    }
    if ($candArr.Count -gt 0) {
      $best = Select-TopCandidate -Candidates $candArr -MinGames $MinGamesHeroTopPlayer
      if ($best) { $heroBestPlayer[[int]$hid] = $best }
    }
  }

  # ===== HTML helpers =====
  function Html-List($items, $fmtSb) { $out=@(); foreach($it in $items){ $out += (& $fmtSb $it) }; ($out -join "`n") }

  function Html-PlayersTable {
    $rows = New-Object System.Text.StringBuilder; $i=1
    foreach ($p in $playerList) {
      $wrNum = if ($p.games -gt 0) { [double]$p.wins/$p.games } else { 0 }
      $heroesMarkup = if ($p.topHeroes -and $p.topHeroes.Count -gt 0) {
        "<div class='heroes'>" + ( ($p.topHeroes | ForEach-Object {
          "<div class='hero' title='$(HtmlEscape $_.name)'><img src='$(HtmlEscape $_.img)' alt='$(HtmlEscape $_.name)'><div>$(HtmlEscape $_.name)<br><span class='sub'>x$($_.count)</span></div></div>"
        }) -join "`n" ) + "</div>"
      } else { "<span class='sub'>-</span>" }
@"
    <tr>
      <td data-sort='$i'>$i</td>
      <td data-sort='$(HtmlEscape $p.name)'><a href="$(HtmlEscape $p.profile)" target="_blank" rel="noopener">$(HtmlEscape $p.name)</a></td>
      <td data-sort='$($p.games)'>$($p.games)</td>
      <td data-sort='$wrNum'><span class="win">$($p.wins)</span>-<span class="loss">$([int]($p.games - $p.wins))</span></td>
      <td class="winrate" data-sort='$wrNum'>$(FmtPct $p.winrate)</td>
      <td>$heroesMarkup</td>
    </tr>
"@ | ForEach-Object { [void]$rows.AppendLine($_) }
      $i++
    }
@"
  <table class="table sortable" id="playersTable">
    <thead>
      <tr>
        <th data-type="num">#</th>
        <th data-type="text">Player</th>
        <th data-type="num">Games</th>
        <th data-type="num">W-L</th>
        <th data-type="num">Win rate</th>
        <th data-type="text">Top 3 heroes</th>
      </tr>
    </thead>
    <tbody>
$($rows.ToString())
    </tbody>
  </table>
"@
  }

  function Html-TeamsTable {
    $rows = New-Object System.Text.StringBuilder; $i=1
    foreach ($t in $teamList) {
      $tp = $teamTopPerformer[[int]$t.team_id]
      $tpText = if ($tp) { "<a href='$(HtmlEscape $tp.profile)' target='_blank'>$(HtmlEscape $tp.name)</a> - $(FmtPct $tp.winrate) ($($tp.wins)/$($tp.games))" } else { "<span class='sub'>no data</span>" }
      $tname = if ($t.name) { $t.name } else { "Team $($t.team_id)" }
      $tpSort = if ($tp) { $tp.winrate } else { 0 }
@"
      <tr>
        <td data-sort='$i'>$i</td>
        <td class="teamcell" data-sort='$(HtmlEscape $tname)'><img class="logo" src="$(HtmlEscape $t.logo)" alt=""><span>$(HtmlEscape $tname)</span></td>
        <td data-sort='$($t.games)'>$($t.games)</td>
        <td data-sort='$([double]$t.wins/([math]::Max(1,$t.games)))'><span class="win">$($t.wins)</span>-<span class="loss">$([int]$t.losses)</span></td>
        <td class="winrate" data-sort='$($t.winrate)'>$(FmtPct $t.winrate)</td>
        <td data-sort='$tpSort'>$tpText</td>
      </tr>
"@ | ForEach-Object { [void]$rows.AppendLine($_) }
      $i++
    }
@"
  <table class="table sortable" id="teamsTable">
    <thead><tr>
      <th data-type="num">#</th>
      <th data-type="text">Team</th>
      <th data-type="num">Games</th>
      <th data-type="num">W-L</th>
      <th data-type="num">Win rate</th>
      <th data-type="num">Top performer</th>
    </tr></thead>
    <tbody>
$($rows.ToString())
    </tbody>
  </table>
"@
  }

  function Html-HeroesTable {
    $rows = New-Object System.Text.StringBuilder; $i=1
    foreach ($h in ($heroSummary | Sort-Object @{e='picks';Descending=$true})) {
      $best = $heroBestPlayer[[int]$h.id]
      $bestHtml = if ($best) { "<a href='$(HtmlEscape $best.profile)' target='_blank'>$(HtmlEscape $best.name)</a> - $(FmtPct $best.winrate) ($($best.wins)/$($best.games))" } else { "<span class='sub'>no data</span>" }
      $bestSort = if ($best) { $best.winrate } else { 0 }
@"
      <tr>
        <td data-sort='$i'>$i</td>
        <td data-sort='$(HtmlEscape $h.name)'><div style="display:flex;align-items:center;gap:8px"><img src="$(HtmlEscape $h.img)" style="width:28px;height:28px;border-radius:6px;border:1px solid rgba(255,255,255,.1)"><span>$(HtmlEscape $h.name)</span></div></td>
        <td data-sort='$($h.picks)'>$($h.picks)</td>
        <td data-sort='$($h.bans)'>$($h.bans)</td>
        <td data-sort='$($h.wins)'>$($h.wins)</td>
        <td class="winrate" data-sort='$($h.winrate)'>$(FmtPct $h.winrate)</td>
        <td data-sort='$bestSort'>$bestHtml</td>
      </tr>
"@ | ForEach-Object { [void]$rows.AppendLine($_) }
      $i++
    }
@"
  <div class="toolbar">
    <input id="heroSearch" class="search" type="text" placeholder="Search hero ..." />
  </div>
  <table class="table sortable" id="heroesTable">
    <thead><tr>
      <th data-type="num">#</th>
      <th data-type="text">Hero</th>
      <th data-type="num">Picks</th>
      <th data-type="num">Bans</th>
      <th data-type="num">Wins</th>
      <th data-type="num">Hero WR</th>
      <th data-type="num">Best player</th>
    </tr></thead>
    <tbody>
$($rows.ToString())
    </tbody>
  </table>
"@
  }

  # ===== Header summaries =====
  function Html-List { param($items,$fmt) $o=@(); foreach($it in $items){ $o+=(& $fmt $it) }; ($o -join "`n") }
  $summaryHeroesHtml = Html-List $topMostPicked { param($h) "<li><img src='$(HtmlEscape $h.img)' alt=''><span>$(HtmlEscape $h.name)</span><span class='badge'>Picks: $($h.picks)</span><span class='badge'>WR: <strong>$(FmtPct $h.winrate)</strong></span></li>" }
  $summaryBansHtml   = Html-List $topBanned     { param($h) "<li><img src='$(HtmlEscape $h.img)' alt=''><span>$(HtmlEscape $h.name)</span><span class='badge'>Bans: $($h.bans)</span><span class='badge'>Picks: $($h.picks)</span></li>" }
  $summaryPlayersHdr = Html-List $topPlayersHdr { param($p) "<li><span><a href='$(HtmlEscape $p.profile)' target='_blank'>$(HtmlEscape $p.name)</a></span><span class='badge'>$($p.games) games</span><span class='badge'>WR: <strong>$(FmtPct $p.winrate)</strong></span></li>" }
  $summaryTeamsHdr   = Html-List $topTeamsHdr   { param($t) "<li><img class='logo' src='$(HtmlEscape $t.logo)'><span>$(HtmlEscape $t.name)</span><span class='badge'>$($t.games) games</span><span class='badge'>WR: <strong>$(FmtPct $t.winrate)</strong></span></li>" }

  $leagueBanner = Get-LeagueBannerUrl $LEAGUE_ID
  $title = "$LEAGUE_NAME - Overview ($Range)"
  $sub   = "Range: $Range - Source: Steam + OpenDota (cached) - Times in Europe/Berlin"

  # ===== CSS =====
  $css = @"
:root { --bg:#0b1020; --card:#121832; --muted:#9aa3b2; --text:#eef1f7; --accent:#6da6ff; --ok:#7be495; --bad:#ff8b8b; --chip:#1a2142; --grid:#1a2244; --shadow:0 10px 30px rgba(0,0,0,.35) }
*{box-sizing:border-box} body{margin:0;padding:24px;background:radial-gradient(1200px 600px at 10% -10%, #172045, transparent 60%), var(--bg);color:var(--text);font-family:Inter,system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif}
a{color:var(--accent);text-decoration:none} h1{font-size:28px;margin:0 0 8px} h2{font-size:20px;margin:24px 0 12px}
.container{max-width:1200px;margin:0 auto} .header{display:flex;align-items:center;gap:16px;margin-bottom:16px}
.header img{height:44px;border-radius:8px} .sub{color:var(--muted);font-size:14px}
.card{background:linear-gradient(180deg,rgba(255,255,255,.04),rgba(255,255,255,.02));border:1px solid rgba(255,255,255,.08);border-radius:16px;box-shadow:var(--shadow);padding:16px}
.table{width:100%;border-collapse:collapse} .table th,.table td{padding:10px 8px;border-bottom:1px solid rgba(255,255,255,.06)}
.table th{text-align:left;color:var(--muted);font-weight:600;font-size:13px} .table td{font-size:14px}
.badge{display:inline-block;padding:4px 8px;border-radius:999px;background:var(--chip);color:var(--text);font-size:12px}
.winrate{font-weight:600} .win{color:var(--ok)} .loss{color:var(--bad)}
.summary-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:12px}
.summary-card h3{margin:0 0 8px;font-size:16px}
.summary-card ul{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:6px}
.summary-card li{display:flex;align-items:center;gap:8px}
.summary-card img{width:24px;height:24px;border-radius:6px;object-fit:cover;border:1px solid rgba(255,255,255,.1)}
.heroes{display:flex;gap:8px;flex-wrap:wrap}
.hero{display:inline-flex;flex-direction:column;align-items:center;gap:4px;font-size:11px;width:64px}
.hero img{width:64px;height:36px;object-fit:cover;border-radius:8px;border:1px solid rgba(255,255,255,.08)}
.logo{width:20px;height:20px;border-radius:50%;object-fit:cover;border:1px solid rgba(255,255,255,.1)}
.teamcell{display:flex;align-items:center;gap:8px}
.table th{cursor:pointer; position:relative}
.table th.sorted-asc::after{content:" ▲"; font-size:11px; color:var(--muted)}
.table th.sorted-desc::after{content:" ▼"; font-size:11px; color:var(--muted)}
.toolbar{display:flex;justify-content:flex-end;gap:8px;margin-bottom:8px}
.search{background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.12);border-radius:10px;color:var(--text);padding:8px 10px;outline:none}
.search::placeholder{color:var(--muted)}
"@

  # ===== Final HTML =====
  $playersHtml = Html-PlayersTable
  $teamsHtml   = Html-TeamsTable
  $heroesHtml  = Html-HeroesTable

  $html = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>$(HtmlEscape $title)</title>
<meta property="og:title" content="$(HtmlEscape $title)">
<meta property="og:description" content="Summary, Players, Teams & Heroes - Range: $Range (from cache)">
<meta property="og:image" content="$(HtmlEscape $leagueBanner)">
<meta property="og:type" content="website">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
<style>$css</style>
</head>
<body>
<div class="container">
  <div class="header">
    <img src="$(HtmlEscape $leagueBanner)" alt="League">
    <div>
      <h1>$(HtmlEscape $LEAGUE_NAME) - Overview</h1>
      <div class="sub">$(HtmlEscape $sub)</div>
    </div>
  </div>

  <section class="card">
    <div class="summary-grid">
      <div class="summary-card">
        <h3>Most picked heroes</h3>
        <ul>
$(Html-List $topMostPicked { param($h) "<li><img src='$(HtmlEscape $h.img)' alt=''><span>$(HtmlEscape $h.name)</span><span class='badge'>Picks: $($h.picks)</span><span class='badge'>WR: <strong>$(FmtPct $h.winrate)</strong></span></li>" })
        </ul>
      </div>
      <div class="summary-card">
        <h3>Most banned heroes</h3>
        <ul>
$(Html-List $topBanned { param($h) "<li><img src='$(HtmlEscape $h.img)' alt=''><span>$(HtmlEscape $h.name)</span><span class='badge'>Bans: $($h.bans)</span><span class='badge'>Picks: $($h.picks)</span></li>" })
        </ul>
      </div>
      <div class="summary-card">
        <h3>Top players (min $MinGamesPlayerTop games)</h3>
        <ul>
$(Html-List $topPlayersHdr { param($p) "<li><span><a href='$(HtmlEscape $p.profile)' target='_blank'>$(HtmlEscape $p.name)</a></span><span class='badge'>$($p.games) games</span><span class='badge'>WR: <strong>$(FmtPct $p.winrate)</strong></span></li>" })
        </ul>
      </div>
      <div class="summary-card">
        <h3>Top teams (min $MinGamesTeamTop games)</h3>
        <ul>
$(Html-List $topTeamsHdr { param($t) "<li><img class='logo' src='$(HtmlEscape $t.logo)'><span>$(HtmlEscape $t.name)</span><span class='badge'>$($t.games) games</span><span class='badge'>WR: <strong>$(FmtPct $t.winrate)</strong></span></li>" })
        </ul>
      </div>
    </div>
  </section>

  <section class="card">
    <h2>Players</h2>
$playersHtml
  </section>

  <section class="card">
    <h2>Teams (with top performer)</h2>
$teamsHtml
  </section>

  <section class="card">
    <h2>All heroes - Picks/Bans/Wins & best player</h2>
$heroesHtml
  </section>
</div>

<script>
(function(){
function v(td){
  if(td.dataset && td.dataset.sort!==undefined){ return parseFloat(td.dataset.sort); }
  const t = td.textContent.trim().replace('%','').replace(',','.');
  const n = parseFloat(t);
  return isNaN(n) ? td.textContent.trim().toLowerCase() : n;
}
function sortTable(table, col, type, asc){
  const tbody = table.tBodies[0], rows = Array.from(tbody.rows);
  rows.sort((a,b)=>{
    let va=v(a.cells[col]), vb=v(b.cells[col]);
    if(type==='text'){ va=(''+va).toLowerCase(); vb=(''+vb).toLowerCase(); return asc?va.localeCompare(vb):vb.localeCompare(va); }
    va=parseFloat(va)||0; vb=parseFloat(vb)||0; return asc?va-vb:vb-va;
  });
  rows.forEach(r=>tbody.appendChild(r));
  table.querySelectorAll('th').forEach(th=>th.classList.remove('sorted-asc','sorted-desc'));
  const th=table.querySelectorAll('th')[col]; th.classList.add(asc?'sorted-asc':'sorted-desc');
}
document.querySelectorAll('table.sortable').forEach(table=>{
  table.querySelectorAll('th').forEach((th,i)=>{
    th.addEventListener('click', ()=>{
      const type = th.dataset.type || 'text';
      const asc = !th.classList.contains('sorted-asc');
      sortTable(table,i,type,asc);
    });
  });
});
const heroInput=document.getElementById('heroSearch');
if(heroInput){
  heroInput.addEventListener('input', ()=>{
    const q=heroInput.value.trim().toLowerCase();
    document.querySelectorAll('#heroesTable tbody tr').forEach(tr=>{
      const name=tr.querySelector('td:nth-child(2)')?.textContent.trim().toLowerCase()||'';
      tr.style.display = (!q || name.includes(q)) ? '' : 'none';
    });
  });
}
})();
</script>

</body>
</html>
"@

  # ===== Save/publish =====
  $extraCommit = @()
  if ($Range -eq "All") { $extraCommit += $StatePath }

  if ($PublishToRepo -and $RepoPath) {
  # Export client data for dynamic viewer
  $exported = Export-DataForClient -RepoPath $RepoPath -State $state -HeroMap $heroMap
  $extraCommit = @($extraCommit + $exported)

  $published = Save-ReportToRepo -RepoPath $RepoPath -Html $html -LeagueName $LEAGUE_NAME -Range $Range `
         -IndexMax $IndexMax -GitAutoPush:$GitAutoPush -StableAll:$StableAll -ExtraCommitPaths $extraCommit
    Write-Host "Published: $published" -ForegroundColor Green
    if ($OutFile) { $html | Set-Content -Path $OutFile -Encoding UTF8 }
  } else {
    $html | Set-Content -Path $OutFile -Encoding UTF8
    Write-Host "OK: $OutFile" -ForegroundColor Green
  }

} catch {
  Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
  if ($_.InvocationInfo) { Write-Host ("At {0}:{1}" -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber) -ForegroundColor Yellow }
  if ($_.ScriptStackTrace) { Write-Host "Stack:" -ForegroundColor Yellow; Write-Host $_.ScriptStackTrace }
  Write-Host ("Exception: {0}" -f ($_.Exception | Out-String))
  exit 1
}

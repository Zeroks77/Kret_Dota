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

      <div>
        <h3>Roshan taken (by match)</h3>
        <ul class="simple">
$(
  if ($high -and $high.PSObject.Properties.Name -contains 'roshanByMatch' -and $high.roshanByMatch -and $high.roshanByMatch.Count -gt 0) {
    $list = @($high.roshanByMatch | Sort-Object @{e='total';Descending=$true}, @{e='match_id';Descending=$true} | Select-Object -First 10)
    ($list | ForEach-Object { $mid=[string]$_.match_id; $url = & $OD_MATCH_URL $mid; "<li><a class='badge' target='_blank' href='"+(HtmlEscape $url)+"'>M$mid</a><span class='badge'>Radiant x$($_.Radiant)</span><span class='badge'>Dire x$($_.Dire)</span><span class='badge'>Total: $($_.total)</span></li>" }) -join "`n"
  } else { "<li><span class='sub'>no Roshan events in this period</span></li>" }
)
        </ul>
  $objWarn
$(
  if ($high -and $high.PSObject.Properties.Name -contains 'aegisSnatch' -and $high.aegisSnatch -and $high.aegisSnatch.Count -gt 0) {
    $items = ($high.aegisSnatch | ForEach-Object {
      $sec=[int]$_.time; $mm=[int]([math]::Floor($sec/60)); $ss=[int]($sec%60)
      $mid=[string]$_.match_id; $url = & $OD_MATCH_URL $mid
      $team = if ($_.team) { [string]$_.team } else { '' }
      $p = $_.player
      $nm = if ($p -and $p.name) { [string]$p.name } else { 'Unknown' }
      $hero = if ($p -and $p.hero) { [string]$p.hero } else { '' }
      $prof = if ($p -and $p.profile) { [string]$p.profile } else { '' }
      "<li><span>Aegis snatch:</span><span class='badge'>${team}</span><span>" + $( if($prof){ "<a href='"+(HtmlEscape $prof)+"' target='_blank'>"+(HtmlEscape $nm)+"</a>" } else { (HtmlEscape $nm) } ) + $( if ($hero){ " ("+(HtmlEscape $hero)+")" } else { "" } ) + "</span><a class='badge' target='_blank' href='"+(HtmlEscape $url)+"'>${mm}m ${ss}s</a></li>"
    }) -join "`n"
    "<div class='sub' style='margin-top:6px'>Aegis snatches</div><ul class='simple'>${items}</ul>"
  } else { '' }
)
$(
  # Tormentor by match (aggregate by match/team, hide player)
  if ($high -and $high.PSObject.Properties.Name -contains 'tormentor' -and $high.tormentor -and $high.tormentor.Count -gt 0) {
    $agg = @{}
    foreach($e in $high.tormentor){
      try {
        $mid = [string]$e.match_id; if (-not $mid) { continue }
        if (-not $agg.ContainsKey($mid)) { $agg[$mid] = @{ Radiant = 0; Dire = 0; total = 0 } }
        $add = 1; try { if ($e.PSObject.Properties.Name -contains 'count' -and $null -ne $e.count) { $add = [int]$e.count } } catch {}
        $team = if ($e.team) { [string]$e.team } else { '' }
        if ($team -eq 'Radiant') { $agg[$mid]['Radiant'] = [int]$agg[$mid]['Radiant'] + $add }
        elseif ($team -eq 'Dire') { $agg[$mid]['Dire'] = [int]$agg[$mid]['Dire'] + $add }
        $agg[$mid]['total'] = [int]$agg[$mid]['Radiant'] + [int]$agg[$mid]['Dire']
      } catch {}
    }
    $list = @(); foreach($k in $agg.Keys){ $list += [pscustomobject]@{ match_id=[int64]$k; Radiant=[int]$agg[$k]['Radiant']; Dire=[int]$agg[$k]['Dire']; total=[int]$agg[$k]['total'] } }
    if ($list.Count -gt 0) {
      $list = @($list | Sort-Object @{e='total';Descending=$true}, @{e='match_id';Descending=$true} | Select-Object -First 10)
      $items = ($list | ForEach-Object { $mid=[string]$_.match_id; $url = & $OD_MATCH_URL $mid; "<li><a class='badge' target='_blank' href='"+(HtmlEscape $url)+"'>M$mid</a><span class='badge'>Radiant x$($_.Radiant)</span><span class='badge'>Dire x$($_.Dire)</span><span class='badge'>Total: $($_.total)</span></li>" }) -join "`n"
      "<div class='sub' style='margin-top:6px'>Tormentor kills by match</div><ul class='simple'>${items}</ul>"
    } else { '' }
  } else { '' }
)
}

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
  <#
    Deprecated: reportgenerator.ps1

    This script used to build HTML reports. The project has moved to a unified
    dynamic viewer (docs/dynamic.html) with static wrapper generation handled by
    scripts/create_dynamic_reports.ps1, and data fetching handled by
    scripts/fetch_opendota_data.ps1.

    For backward compatibility in CI and local use, this script now only fetches
    OpenDota constants and cached match details. It ignores previous parameters
    related to HTML generation.
  #>

  param(
    [int]$OpenDotaDelayMs  = 1200,
    [switch]$PublishToRepo,
    [string]$RepoPath = $PSScriptRoot
  if ($resp) { Write-JsonCache -obj $resp -path $cf }
  Set-StrictMode -Version Latest
  $ErrorActionPreference = 'Stop'
      try {
  function Get-RepoRoot(){ (Resolve-Path "$PSScriptRoot" | Select-Object -ExpandProperty Path) }
  $paths = Get-ParseFiles -RepoPath $RepoPath
  Write-Host 'reportgenerator.ps1 is deprecated. Running data fetcher instead.' -ForegroundColor Yellow
  $fetcher = Join-Path (Join-Path (Get-RepoRoot) 'scripts') 'fetch_opendota_data.ps1'
  if (-not (Test-Path -LiteralPath $fetcher)) { throw "Fetcher not found: $fetcher" }
  & $fetcher -DelayMs $OpenDotaDelayMs
  Write-Host 'Done.'
  foreach($x in (Load-IdArray -path $paths.ready)) { [void]$ready.Add($x) }
  $reqs = 0
  foreach ($id in $newIds) {
    if (-not $ready.Contains($id)) {
      [void]$ready.Add($id)
    }
    if ($reqs -lt $MaxRequests) { Request-OpenDotaParse -matchId $id; $reqs++ }
  }
  # Enumerate HashSet values safely (avoid calling .ToArray() on value types in PS)
  $vals = New-Object System.Collections.Generic.List[long]
  foreach($v in $ready){ [void]$vals.Add([long]$v) }
  Save-IdArray -ids ($vals.ToArray() | Sort-Object) -path $paths.ready
  return $paths.ready
}

# ===== Exclude list (monthly only) =====
function Load-ExcludeSet {
  param([string]$RepoPath)
  try {
    $path = if ($RepoPath) { Join-Path $RepoPath "data/exclude.json" } else { Join-Path $PSScriptRoot "data/exclude.json" }
    if (-not (Test-Path -LiteralPath $path)) { return [System.Collections.Generic.HashSet[string]]::new() }
    $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if (-not $raw) { return [System.Collections.Generic.HashSet[string]]::new() }
    $data = $raw | ConvertFrom-Json
    $set = [System.Collections.Generic.HashSet[string]]::new()
    if ($data -is [array]) { foreach($id in $data){ if ($id){ [void]$set.Add([string]$id) } } }
    elseif ($data.exclude -is [array]) { foreach($id in $data.exclude){ if ($id){ [void]$set.Add([string]$id) } } }
    return $set
  } catch { Write-Warning ("Failed to read exclude list: " + $_.Exception.Message); return [System.Collections.Generic.HashSet[string]]::new() }
}

# ===== Highlights helpers (OpenDota parse + extraction) =====
function Get-ObjectiveTeam([object]$ev){
  # Try multiple shapes OpenDota may return to resolve team -> 'Radiant' | 'Dire'
  try {
    if ($null -ne $ev.team) {
      $t = $ev.team
      # numeric 2/3 or string 'radiant'/'dire'
      try { $n = [int]$t } catch { $n = $null }
      if ($n -eq 2) { return 'Radiant' }
      if ($n -eq 3) { return 'Dire' }
      $s = [string]$t
      if ($s) {
        if ($s -match 'radiant') { return 'Radiant' }
        if ($s -match 'dire') { return 'Dire' }
      }
    }
  } catch {}
  # Fallback: player_slot if present (<128 Radiant else Dire)
  try {
    if ($null -ne $ev.player_slot) {
      $ps = [int]$ev.player_slot
      return ($(if ($ps -lt 128) { 'Radiant' } else { 'Dire' }))
    }
  } catch {}
  # Fallback: boolean radiant
  try {
    if ($null -ne $ev.radiant) { return ($(if ($ev.radiant) { 'Radiant' } else { 'Dire' })) }
  } catch {}
  return $null
}

# Map player_slot to player record and enriched display info (name/hero)
function Resolve-PlayerInfoBySlot([object]$md,[int]$slot,[hashtable]$HeroMap,[hashtable]$PlayerNamesMap){
  $p = $null
  try { $p = @($md.players | Where-Object { $_.PSObject.Properties.Name -contains 'player_slot' -and [int]$_.player_slot -eq $slot })[0] } catch { $p = $null }
  if (-not $p) { return $null }
  $aid = 0; try { $aid = [int64]$p.account_id } catch {}
  $nm  = $null
  if ($aid -gt 0) {
    if ($PlayerNamesMap -and $PlayerNamesMap.ContainsKey([string]$aid)) { $nm = [string]$PlayerNamesMap[[string]$aid] }
    if (-not $nm -and $p.personaname) { $nm = [string]$p.personaname }
  }
  if (-not $nm) { $nm = if ($aid -gt 0) { "Player $aid" } else { "Unknown" } }
  $hid = 0; try { $hid = [int]$p.hero_id } catch {}
  $hero = $null; if ($hid -gt 0 -and $HeroMap.ContainsKey([string]$hid)) { $hero = $HeroMap[[string]$hid].name }
  $prof = if ($aid -gt 0) { & $OD_PLAYER_URL $aid } else { $null }
  return [pscustomobject]@{ account_id=$aid; name=$nm; hero_id=$hid; hero=$hero; profile=$prof }
}
function Request-OpenDotaParse([long]$matchId){
  try { $null = Invoke-Json -Method POST -Uri "$OD_BASE/request/$matchId" -Service OpenDota -Headers $DefaultHeaders; Write-Host "Requested parse for ${matchId}: requested" -ForegroundColor DarkCyan }
  catch { Write-Warning ("Parse request failed for ${matchId}: " + $_.Exception.Message) }
}

function Ensure-OD-Match([long]$matchId,[int]$retries=0,[int]$delayMs=0){
  # Defaults: 5 attempts with 3s delay if not specified
  if ($retries -le 0) { $retries = 5 }
  if ($delayMs -le 0) { $delayMs = 3000 }

  $md = $null
  try { $md = Get-OpenDotaMatch -matchId $matchId } catch { $md = $null }
  if ($null -ne $md -and $md.players -and $md.players.Count -gt 0) {
    # If objectives are missing, actively request parse and poll for enriched data
    $needsEnrich = $false
    try { if (-not ($md.PSObject.Properties.Name -contains 'objectives') -or -not $md.objectives -or $md.objectives.Count -eq 0) { $needsEnrich = $true } } catch {}
    if ($needsEnrich) {
      for($i=1; $i -le $retries; $i++){
        try { Request-OpenDotaParse -matchId $matchId } catch {}
        Start-Sleep -Milliseconds $delayMs
        try { $fresh = Get-OpenDotaMatch -matchId $matchId -BypassCache } catch { $fresh = $null }
        if ($fresh -and $fresh.players -and $fresh.players.Count -gt 0) {
          $md = $fresh
          try { if ($md.objectives -and $md.objectives.Count -gt 0) { break } } catch {}
        }
      }
    }
    return $md
  }

  for($i=1; $i -le $retries; $i++){
    try { Request-OpenDotaParse -matchId $matchId } catch {}
    Start-Sleep -Milliseconds $delayMs
    try { $md = Get-OpenDotaMatch -matchId $matchId -BypassCache } catch { $md = $null }
    if ($null -ne $md -and $md.players -and $md.players.Count -gt 0) { return $md }
  }
  return $md
}

function Build-Monthly-Highlights {
  param(
    [Parameter(Mandatory)][array]$MatchesSubset,
    [Parameter(Mandatory)][hashtable]$HeroMap,
    [hashtable]$PlayerNamesMap,
    [int]$PollRetries = 0,
    [int]$PollDelayMs = 0
  )
  # Aggregates
  $rampages = @{}              # account_id -> count
  $rampageGames = @{}          # account_id -> hashtable of match_id -> count
  $wardSpots = @{}             # "x,y" -> count
  $wardEvents = New-Object System.Collections.Generic.List[object]  # individual ward logs
  # New aggregations: teammates, courier kills, camps stacked
  $pairCounts = @{}            # "aid1-aid2" -> games together (same team)
  $courierKillsBy = @{}        # account_id -> total courier kills
  $campsStackedBy = @{}        # account_id -> total camps stacked
  # Hero tag -> id reverse map (for parsing attackername like npc_dota_hero_disruptor)
  $TagToHeroId = @{}
  try {
    foreach($kv in $HeroMap.GetEnumerator()){
      $v = $kv.Value
      if ($null -ne $v -and $v.tag) { $TagToHeroId[[string]$v.tag] = [int]$v.id }
    }
  } catch {}
  $wardLifeMax = @{}            # "x,y" -> longest observed lifetime (seconds)
  $ObsNaturalSec = 480          # assume natural expiry if no removal is seen
  $roshanTeam = @{ Radiant=0; Dire=0 }
  # Per-team Roshan kills per match (for top matches display)
  $roshanPerMatch = @{ Radiant=@{}; Dire=@{} }
  # Awards aggregates
  $DeathsInWins     = @{}   # aid -> deaths (only in matches won)
  $TowerDamageBy    = @{}   # aid -> total tower damage
  $TeamTowerSumById = @{}   # aid -> sum of team tower damage across matches he played
  $RoshParticipation= @{}   # aid -> count of roshan kills participated (team rosh)
  $SmokeUses        = @{}   # aid -> count of smokes purchased
  $RunesCount       = @{}   # aid -> runes taken (sum of all types)
  $WardScore        = @{}   # aid -> obs_kills+sen_kills + 0.5*(obs_placed+sen_placed)
  $AegisSnatched    = @{}   # aid -> count of aegis stolen
  $EarlyBest        = @{}   # aid -> best net worth @10
  $Clutch           = @{}   # aid -> @{ tk: team kills in last 10%; contrib: kills+assists in last 10% }
  # Special objectives
  $aegisSnatch = New-Object System.Collections.Generic.List[object]
  $tormentorTaken = New-Object System.Collections.Generic.List[object]
  # Top single-match performances trackers
  $bestGPM    = $null   # @{ account_id; name; profile; value; match_id }
  $bestKills  = $null
  $bestAssists= $null
  $bestNet    = $null
  $duos = @{ Safe=@{}; Off=@{} }  # lane -> key "hid1-hid2" -> @{ games; wins }

  # Player-centric ward stats
  $obsPlacedBy = @{}   # account_id -> total observer wards placed
  $dewardsBy   = @{}   # account_id -> total enemy observers killed
  $lifeBy      = @{}   # account_id -> List[int] of lifetimes for own observers
  $pname       = @{}   # account_id -> last known name

  # Match durations
  $durList = New-Object System.Collections.Generic.List[object]
  $objectivesSeen = 0

  foreach ($m in $MatchesSubset) {
    $mid = [long]$m.match_id
    if ($mid -le 0) { continue }
    $md = Ensure-OD-Match -matchId $mid -retries $PollRetries -delayMs $PollDelayMs
    if (-not $md) { continue }

  # Rampages + ward logs
  $mPlaced = New-Object System.Collections.Generic.List[object]
  $mLeft   = New-Object System.Collections.Generic.List[object]
    # Per-match: hero_id -> account_id map for deward fallback
    $HeroToAccount = @{}
    try {
      foreach($p0 in $md.players){ try { $hid=[int]$p0.hero_id; $aid=[int64]$p0.account_id; if ($hid -gt 0 -and $aid -gt 0) { $HeroToAccount[$hid] = $aid } } catch {} }
    } catch {}
    $hasObsKillsField = $false
    # Precompute per-match tower damage sums per side (for objective gamer share)
    $tdSums = @{ Radiant=0; Dire=0 }
    foreach($pp in $md.players){
      try { $td = 0; if ($pp.PSObject.Properties.Name -contains 'tower_damage' -and $pp.tower_damage -ne $null) { $td = [int]$pp.tower_damage }
        if ($pp.isRadiant) { $tdSums.Radiant += $td } else { $tdSums.Dire += $td } } catch {}
    }

    foreach ($p in $md.players) {
      $aid = [int64]$p.account_id
      # Name cache
      try {
        $nm = $null
        if ($p.personaname) { $nm = [string]$p.personaname }
        elseif ($PlayerNamesMap -and $PlayerNamesMap.ContainsKey([string]$aid)) { $nm = [string]$PlayerNamesMap[[string]$aid] }
        if (-not $nm -and $aid -gt 0) { $nm = ("Player {0}" -f $aid) }
        if ($aid -gt 0 -and $nm) { $pname[$aid] = $nm }
      } catch {}
      # Top single-match metrics (per player per match)
      try {
        # Resolve display name once
        $nmTop = if ($pname.ContainsKey($aid)) { $pname[$aid] } elseif ($PlayerNamesMap -and $PlayerNamesMap.ContainsKey([string]$aid)) { $PlayerNamesMap[[string]$aid] } else { if ($aid -gt 0) { ("Player {0}" -f $aid) } else { $null } }
        $prof = if ($aid -gt 0) { & $OD_PLAYER_URL $aid } else { $null }
        # Highest GPM
        $gpm = 0; try { if ($p.PSObject.Properties.Name -contains 'gold_per_min' -and $null -ne $p.gold_per_min) { $gpm = [int]$p.gold_per_min } } catch {}
        if ($gpm -gt 0) {
          if (-not $bestGPM -or [int]$bestGPM.value -lt $gpm) { $bestGPM = [pscustomobject]@{ account_id=$aid; name=$nmTop; profile=$prof; value=$gpm; match_id=$mid } }
        }
        # Highest Kills
        $kills = 0; try { if ($p.PSObject.Properties.Name -contains 'kills' -and $null -ne $p.kills) { $kills = [int]$p.kills } } catch {}
        if ($kills -gt 0) {
          if (-not $bestKills -or [int]$bestKills.value -lt $kills) { $bestKills = [pscustomobject]@{ account_id=$aid; name=$nmTop; profile=$prof; value=$kills; match_id=$mid } }
        }
        # Highest Assists
        $ass = 0; try { if ($p.PSObject.Properties.Name -contains 'assists' -and $null -ne $p.assists) { $ass = [int]$p.assists } } catch {}
        if ($ass -gt 0) {
          if (-not $bestAssists -or [int]$bestAssists.value -lt $ass) { $bestAssists = [pscustomobject]@{ account_id=$aid; name=$nmTop; profile=$prof; value=$ass; match_id=$mid } }
        }
        # Highest Net Worth (fallbacks: total_gold, last of gold_t)
        $net = 0
        try { if ($p.PSObject.Properties.Name -contains 'net_worth' -and $null -ne $p.net_worth) { $net = [int]$p.net_worth } } catch {}
        if ($net -le 0) {
          try { if ($p.PSObject.Properties.Name -contains 'total_gold' -and $null -ne $p.total_gold) { $net = [int]$p.total_gold } } catch {}
        }
        if ($net -le 0) {
          try { if ($p.PSObject.Properties.Name -contains 'gold_t' -and $p.gold_t -and $p.gold_t.Count -gt 0) { $net = [int]$p.gold_t[$p.gold_t.Count-1] } } catch {}
        }
        if ($net -gt 0) {
          if (-not $bestNet -or [int]$bestNet.value -lt $net) { $bestNet = [pscustomobject]@{ account_id=$aid; name=$nmTop; profile=$prof; value=$net; match_id=$mid } }
        }
      } catch {}
      if ($p.multi_kills) {
        $mk = $p.multi_kills
        $r = 0
        try { if ($mk.PSObject.Properties.Name -contains '5') { $r = [int]$mk.'5' } } catch { $r = 0 }
        if ($r -gt 0 -and $aid -gt 0) {
          if (-not $rampages.ContainsKey($aid)) { $rampages[$aid]=0 }
          $rampages[$aid]+=$r
          if (-not $rampageGames.ContainsKey($aid)) { $rampageGames[$aid] = @{} }
          $midKey = [string]$mid
          if (-not $rampageGames[$aid].ContainsKey($midKey)) { $rampageGames[$aid][$midKey] = 0 }
          $rampageGames[$aid][$midKey] = [int]$rampageGames[$aid][$midKey] + $r
        }
      }
      # Awards: deaths in wins, tower damage, early farmer, ward score, smokes, runes
      try {
        $won = $false; try { $won = if ($p.isRadiant) { [bool]$md.radiant_win } else { -not [bool]$md.radiant_win } } catch {}
        $deaths = 0; try { if ($p.PSObject.Properties.Name -contains 'deaths' -and $p.deaths -ne $null) { $deaths = [int]$p.deaths } } catch {}
        if ($aid -gt 0 -and $won -and $deaths -gt 0) { if (-not $DeathsInWins[$aid]) { $DeathsInWins[$aid]=0 }; $DeathsInWins[$aid] = [int]$DeathsInWins[$aid] + $deaths }
      } catch {}
      try {
        $td = 0; try { if ($p.PSObject.Properties.Name -contains 'tower_damage' -and $p.tower_damage -ne $null) { $td = [int]$p.tower_damage } } catch {}
        if ($aid -gt 0 -and $td -gt 0) { if (-not $TowerDamageBy[$aid]) { $TowerDamageBy[$aid]=0 }; $TowerDamageBy[$aid] = [int]$TowerDamageBy[$aid] + $td }
        # add team sum for this player's side
        $sideSum = if ($p.isRadiant) { [int]$tdSums.Radiant } else { [int]$tdSums.Dire }
        if ($aid -gt 0) { if (-not $TeamTowerSumById[$aid]) { $TeamTowerSumById[$aid]=0 }; $TeamTowerSumById[$aid] = [int]$TeamTowerSumById[$aid] + $sideSum }
      } catch {}
      try {
        # Early farmer net worth at 10min from gold_t
        $nw10 = 0; if ($p.PSObject.Properties.Name -contains 'gold_t' -and $p.gold_t -and $p.gold_t.Count -gt 10) { $nw10 = [int]$p.gold_t[10] }
        if ($aid -gt 0 -and $nw10 -gt 0) { if (-not $EarlyBest[$aid] -or [int]$EarlyBest[$aid] -lt $nw10) { $EarlyBest[$aid] = $nw10 } }
      } catch {}
      try {
        # Ward score
        $ok = 0; if ($p.PSObject.Properties.Name -contains 'obs_kills' -and $p.obs_kills -ne $null) { $ok = [int]$p.obs_kills }
        $sk = 0; if ($p.PSObject.Properties.Name -contains 'sen_kills' -and $p.sen_kills -ne $null) { $sk = [int]$p.sen_kills } elseif ($p.PSObject.Properties.Name -contains 'sen_killed' -and $p.sen_killed -ne $null) { $sk = [int]$p.sen_killed }
        $op = 0; if ($p.PSObject.Properties.Name -contains 'obs_placed' -and $p.obs_placed -ne $null) { $op = [int]$p.obs_placed }
        $sp = 0; if ($p.PSObject.Properties.Name -contains 'sen_placed' -and $p.sen_placed -ne $null) { $sp = [int]$p.sen_placed }
        $score = [double]$ok + [double]$sk + 0.5*([double]$op + [double]$sp)
        if ($aid -gt 0 -and $score -gt 0) { if (-not $WardScore[$aid]) { $WardScore[$aid]=0.0 } ; $WardScore[$aid] = [double]$WardScore[$aid] + $score }
      } catch {}
      try {
        # Smokes used
        if ($p.PSObject.Properties.Name -contains 'purchase_log' -and $p.purchase_log) {
          $cnt = 0
          foreach($it in $p.purchase_log){ try { $k = (''+$it.key).ToLower(); if ($k -eq 'smoke_of_deceit') { $cnt++ } } catch {} }
          if ($aid -gt 0 -and $cnt -gt 0) { if (-not $SmokeUses[$aid]) { $SmokeUses[$aid]=0 }; $SmokeUses[$aid] = [int]$SmokeUses[$aid] + $cnt }
        }
      } catch {}
      try {
        # Runes taken
        if ($p.PSObject.Properties.Name -contains 'runes' -and $p.runes) {
          $sum = 0; foreach($rv in $p.runes.PSObject.Properties){ try { $sum += [int]$rv.Value } catch {} }
          if ($aid -gt 0 -and $sum -gt 0) { if (-not $RunesCount[$aid]) { $RunesCount[$aid]=0 }; $RunesCount[$aid] = [int]$RunesCount[$aid] + $sum }
        }
      } catch {}
      # Courier kills & Camps stacked
      try {
        $ck = 0; if ($p.PSObject.Properties.Name -contains 'courier_kills' -and $null -ne $p.courier_kills) { $ck = [int]$p.courier_kills }
        if ($aid -gt 0 -and $ck -gt 0) { if (-not $courierKillsBy[$aid]) { $courierKillsBy[$aid] = 0 }; $courierKillsBy[$aid] += $ck }
      } catch {}
      try {
        $st = 0; if ($p.PSObject.Properties.Name -contains 'camps_stacked' -and $null -ne $p.camps_stacked) { $st = [int]$p.camps_stacked }
        if ($aid -gt 0 -and $st -gt 0) { if (-not $campsStackedBy[$aid]) { $campsStackedBy[$aid] = 0 }; $campsStackedBy[$aid] += $st }
      } catch {}
      # Observer placements per player
      try {
        $cObs = 0
        if ($p.obs_log) { $cObs = @($p.obs_log).Count }
        elseif ($p.PSObject.Properties.Name -contains 'obs_placed' -and $p.obs_placed) { $cObs = [int]$p.obs_placed }
        if ($aid -gt 0 -and $cObs -gt 0) { if (-not $obsPlacedBy[$aid]) { $obsPlacedBy[$aid]=0 }; $obsPlacedBy[$aid] += $cObs }
      } catch {}
      # Dewards (enemy observers killed)
      try {
        $dk = 0
  if ($p.PSObject.Properties.Name -contains 'obs_kills') { $hasObsKillsField = $true }
  if ($p.PSObject.Properties.Name -contains 'obs_kills' -and $null -ne $p.obs_kills) { $dk = [int]$p.obs_kills }
        # Fallback: some parsed matches may only include sen_log with 'deward' type; count those as well if present
        if ($dk -eq 0 -and $p.PSObject.Properties.Name -contains 'sen_log' -and $p.sen_log) {
          try {
            $dk2 = 0
            foreach($s in $p.sen_log){ try { if ($s.action -eq 'deward' -or $s.type -eq 'obs_kill'){ $dk2++ } } catch {} }
            if ($dk2 -gt 0) { $dk = [int]$dk2 }
          } catch {}
        }
        if ($aid -gt 0 -and $dk -gt 0) { if (-not $dewardsBy[$aid]) { $dewardsBy[$aid]=0 }; $dewardsBy[$aid] += $dk }
      } catch {}
      # Lifetimes per player's observers
      try {
        $placedT = New-Object System.Collections.Generic.List[int]
        $leftT   = New-Object System.Collections.Generic.List[int]
        if ($p.obs_log)      { foreach($o in $p.obs_log){ try { [void]$placedT.Add([int]$o.time) } catch {} } }
        if ($p.obs_left_log) { foreach($o in $p.obs_left_log){ try { [void]$leftT.Add([int]$o.time) } catch {} } }
        if ($placedT.Count -gt 0) {
          $pt = @($placedT.ToArray() | Sort-Object)
          $lt = @($leftT.ToArray() | Sort-Object)
          $j=0
          for($i=0;$i -lt $pt.Count;$i++){
            $tP = [int]$pt[$i]
            while($j -lt $lt.Count -and [int]$lt[$j] -lt $tP){ $j++ }
            $life = $ObsNaturalSec
            if ($j -lt $lt.Count){ $life = [int]([int]$lt[$j] - $tP); $j++ }
            if ($life -lt 0) { $life = 0 }
            if ($aid -gt 0) {
              if (-not $lifeBy[$aid]) { $lifeBy[$aid] = New-Object System.Collections.Generic.List[int] }
              [void]$lifeBy[$aid].Add([int]$life)
            }
          }
        }
      } catch {}
      if ($p.obs_log) {
        foreach($o in $p.obs_log){ try { $ix=[int]$o.x; $iy=[int]$o.y; $t=[int]$o.time; $key = ("{0},{1}" -f $ix, $iy); if (-not $wardSpots[$key]){ $wardSpots[$key]=0 }; $wardSpots[$key]++; $wardEvents.Add([pscustomobject]@{ x=$ix; y=$iy; type='obs' }) | Out-Null; $mPlaced.Add([pscustomobject]@{ x=$ix; y=$iy; time=$t }) | Out-Null } catch { } }
      }
      if ($p.PSObject.Properties.Name -contains 'obs_left_log' -and $p.obs_left_log) {
        foreach($o in $p.obs_left_log){ try { $mLeft.Add([pscustomobject]@{ x=[int]$o.x; y=[int]$o.y; time=[int]$o.time }) | Out-Null } catch {} }
      }
      if ($p.sen_log) {
        foreach($s in $p.sen_log){ try { $wardEvents.Add([pscustomobject]@{ x=[int]$s.x; y=[int]$s.y; type='sen' }) | Out-Null } catch { } }
      }
    }

    # Teammate pairs (within each team per match)
    try {
      $rA = @(); $dA = @()
      foreach($pp in $md.players){ try { if ($pp.account_id -and [int64]$pp.account_id -gt 0) {
            if ($pp.isRadiant) { $rA += [int64]$pp.account_id } else { $dA += [int64]$pp.account_id }
          } } catch {} }
      foreach($arr in @($rA,$dA)){
        if ($arr.Count -ge 2) {
          for($i=0;$i -lt $arr.Count;$i++){
            for($j=$i+1;$j -lt $arr.Count;$j++){
              $a=[int64]$arr[$i]; $b=[int64]$arr[$j]; if ($a -le 0 -or $b -le 0) { continue }
              $lo = if ($a -lt $b) { $a } else { $b }
              $hi = if ($a -lt $b) { $b } else { $a }
              $key = ("{0}-{1}" -f $lo,$hi)
              if (-not $pairCounts[$key]) { $pairCounts[$key] = 0 }
              $pairCounts[$key] = [int]$pairCounts[$key] + 1
            }
          }
        }
      }
    } catch {}

    # Robust dewards fallback: if OpenDota didn't include obs_kills field, derive from obs_left_log attackername
    if (-not $hasObsKillsField) {
      try {
        foreach($q in $md.players){
          if ($q.PSObject.Properties.Name -contains 'obs_left_log' -and $q.obs_left_log) {
            foreach($ol in $q.obs_left_log){
              try {
                $an = [string]$ol.attackername
                if ($an -and $an.StartsWith('npc_dota_hero_')) {
                  $tag = ($an -replace '^npc_dota_hero_','')
                  $hid = $null
                  try { if ($TagToHeroId.ContainsKey($tag)) { $hid = [int]$TagToHeroId[$tag] } } catch {}
                  if ($hid -gt 0 -and $HeroToAccount.ContainsKey($hid)) {
                    $killer = [int64]$HeroToAccount[$hid]
                    if ($killer -gt 0) { if (-not $dewardsBy[$killer]) { $dewardsBy[$killer]=0 }; $dewardsBy[$killer]++ }
                  }
                }
              } catch {}
            }
          }
        }
      } catch {}
    }

  # Objectives: Roshan + detect Aegis snatch and Tormentor
    if ($md.objectives) {
      foreach ($ev in $md.objectives) {
        $typ = $ev.type
        if ($typ -eq 'roshan_kill') {
          $t = Get-ObjectiveTeam -ev $ev
          if ($t) {
            $roshanTeam[$t] = [int]$roshanTeam[$t] + 1
            try {
              $midKey = [string]$mid
              if (-not $roshanPerMatch[$t].ContainsKey($midKey)) { $roshanPerMatch[$t][$midKey] = 0 }
              $roshanPerMatch[$t][$midKey] = [int]$roshanPerMatch[$t][$midKey] + 1
              # Credit all players on killing team for Roshan participation
              foreach($pp in $md.players){ try { $pid=[int64]$pp.account_id; if ($pid -gt 0) { $side = if ($pp.isRadiant) { 'Radiant' } else { 'Dire' }; if ($side -eq $t) { if (-not $RoshParticipation[$pid]) { $RoshParticipation[$pid]=0 }; $RoshParticipation[$pid]++ } } } catch {} }
            } catch {}
          }
        }
        # Aegis snatch: explicit chat objective
        try {
          $tStr = ''+($typ)
          if ($tStr -match 'CHAT_MESSAGE_AEGIS_STOLEN') {
            $team = Get-ObjectiveTeam -ev $ev
            $slot = $null; try { if ($ev.PSObject.Properties.Name -contains 'player_slot') { $slot = [int]$ev.player_slot } } catch {}
            $pi = $null; if ($slot -ne $null) { $pi = Resolve-PlayerInfoBySlot -md $md -slot $slot -HeroMap $HeroMap -PlayerNamesMap $PlayerNamesMap }
            $sec = 0; try { if ($ev.PSObject.Properties.Name -contains 'time' -and $ev.time -ne $null) { $sec = [int]$ev.time } } catch {}
            $aegisSnatch.Add([pscustomobject]@{ match_id=$mid; time=$sec; team=$team; player=$pi }) | Out-Null
            try { if ($pi -and $pi.account_id -gt 0) { $id=[int64]$pi.account_id; if (-not $AegisSnatched[$id]) { $AegisSnatched[$id]=0 }; $AegisSnatched[$id]++ } } catch {}
          }
        } catch {}
        # Tormentor: keyword match on objective metadata (type/key/slot/unit/msg)
        try {
          $ts = ''+($typ)
          $key = try { ''+($ev.key) } catch { '' }
          $unit = try { ''+($ev.unit) } catch { '' }
          $msg = try { ''+($ev.msg) } catch { '' }
          if ($ts -match 'tormentor|CHAT_MESSAGE_TORMENTOR_KILL|CHAT_MESSAGE_MINIBOSS|miniboss' -or $key -match 'tormentor|miniboss' -or $unit -match 'tormentor|miniboss' -or $msg -match 'tormentor|miniboss') {
            $team = Get-ObjectiveTeam -ev $ev
            $slot = $null; try { if ($ev.PSObject.Properties.Name -contains 'player_slot') { $slot = [int]$ev.player_slot } } catch {}
            $pi = $null; if ($slot -ne $null) { $pi = Resolve-PlayerInfoBySlot -md $md -slot $slot -HeroMap $HeroMap -PlayerNamesMap $PlayerNamesMap }
            $sec = 0; try { if ($ev.PSObject.Properties.Name -contains 'time' -and $ev.time -ne $null) { $sec = [int]$ev.time } } catch {}
            $tormentorTaken.Add([pscustomobject]@{ match_id=$mid; time=$sec; team=$team; player=$pi; confidence='explicit' }) | Out-Null
          }
        } catch {}
      }
      try { if ($md.objectives.Count -gt 0) { $objectivesSeen++ } } catch {}
    }
    # Fallback: if no explicit tormentor event for this match, derive from per-player killed dictionary (miniboss/tormentor keys)
    try {
      $hasExplicit = $false
      try { if ($tormentorTaken.Count -gt 0) { $hasExplicit = ($tormentorTaken | Where-Object { $_.match_id -eq $mid -and $_.confidence -eq 'explicit' } | Measure-Object).Count -gt 0 } } catch {}
      if (-not $hasExplicit) {
        foreach($pp in $md.players){
          try {
            $killed = $pp.killed
            if ($null -ne $killed) {
              $ct = 0
              foreach($kv in $killed.PSObject.Properties){
                $kk = [string]$kv.Name; $vv = 0; try { $vv = [int]$kv.Value } catch {}
                if ($kk -match 'miniboss|tormentor') { $ct += $vv }
              }
              if ($ct -gt 0) {
                $slot = [int]$pp.player_slot
                $pi = Resolve-PlayerInfoBySlot -md $md -slot $slot -HeroMap $HeroMap -PlayerNamesMap $PlayerNamesMap
                $team = if ($slot -lt 128) { 'Radiant' } else { 'Dire' }
                $tormentorTaken.Add([pscustomobject]@{ match_id=$mid; time=$null; team=$team; player=$pi; confidence='derived'; count=$ct }) | Out-Null
              }
            }
          } catch {}
        }
      }
    } catch {}
    # Clutch King via teamfights in last 10%
    try {
      $durT = 0; try { if ($null -ne $md.duration) { $durT = [int]$md.duration } } catch {}
      if ($durT -gt 0 -and $md.PSObject.Properties.Name -contains 'teamfights' -and $md.teamfights) {
        # Build slot->aid map
        $slotToAid = @{}; foreach($pp in $md.players){ try { $slotToAid[[int]$pp.player_slot] = [int64]$pp.account_id } catch {} }
        $startCut = [double]$durT * 0.9
        $tfList = @($md.teamfights | Where-Object { try { [double]$_.start -ge $startCut } catch { $false } })
        if ($tfList.Count -gt 0) {
          $tk = @{ Radiant=0; Dire=0 }
          foreach($tf in $tfList){ try { foreach($pl in $tf.players){ try { $slot=[int]$pl.player_slot; $side = if ($slot -lt 128) { 'Radiant' } else { 'Dire' }; $tk[$side] += ([int]$pl.kills) } catch {} } } catch {} }
          foreach($tf in $tfList){ try { foreach($pl in $tf.players){ try { $slot=[int]$pl.player_slot; $aid = if ($slotToAid.ContainsKey($slot)) { [int64]$slotToAid[$slot] } else { 0 }; if ($aid -le 0) { continue }
                $side = if ($slot -lt 128) { 'Radiant' } else { 'Dire' }
                $kp = ([int]$pl.kills) + ([int]$pl.assists)
                if (-not $Clutch[$aid]) { $Clutch[$aid] = [pscustomobject]@{ tk=0; contrib=0 } }
                $Clutch[$aid].tk += [int]$tk[$side]
                $Clutch[$aid].contrib += [int]$kp } catch {} } } catch {} }
        }
      }
    } catch {}
    # Heuristic Tormentor (optional): If no explicit tormentor objective in this match, you could infer via other signals.
    # Skipped here due to limited item state in cached data; explicit events will be reported when present.

  # Lane duos (Safe=1, Off=3)
    $bySide = @{ Radiant=@($md.players | Where-Object { $_.isRadiant }); Dire=@($md.players | Where-Object { -not $_.isRadiant }) }
    foreach ($lane in @('Safe','Off')){
      $laneCode = if ($lane -eq 'Safe') { 1 } else { 3 }
      $rL = @($bySide.Radiant | Where-Object { [int]$_.lane_role -eq $laneCode })
      $dL = @($bySide.Dire    | Where-Object { [int]$_.lane_role -eq $laneCode })
      if ($rL.Count -eq 2 -and $dL.Count -eq 2) {
        $rAvg = (@($rL | ForEach-Object { try { [double]$_.lane_efficiency_pct } catch { 0.0 } }) | Measure-Object -Average).Average
        $dAvg = (@($dL | ForEach-Object { try { [double]$_.lane_efficiency_pct } catch { 0.0 } }) | Measure-Object -Average).Average
        $rPair = @([int]$rL[0].hero_id,[int]$rL[1].hero_id) | Sort-Object
        $dPair = @([int]$dL[0].hero_id,[int]$dL[1].hero_id) | Sort-Object
        $rKey = ("{0}-{1}" -f $rPair[0],$rPair[1]); $dKey=("{0}-{1}" -f $dPair[0],$dPair[1])
        if (-not $duos[$lane].ContainsKey($rKey)) { $duos[$lane][$rKey] = [pscustomobject]@{ games=0; wins=0 } }
        if (-not $duos[$lane].ContainsKey($dKey)) { $duos[$lane][$dKey] = [pscustomobject]@{ games=0; wins=0 } }
        $duos[$lane][$rKey].games++; $duos[$lane][$dKey].games++
        if (($rAvg - $dAvg) -ge 0) { $duos[$lane][$rKey].wins++ } else { $duos[$lane][$dKey].wins++ }
      }
    }

  # Compute longest lifetimes for observer wards in this match by pairing placement with first removal at same cell
    try {
      $pBy = @{}; $lBy = @{}
      foreach($e in $mPlaced){ $k=("{0},{1}" -f $e.x,$e.y); if (-not $pBy[$k]) { $pBy[$k]=New-Object System.Collections.Generic.List[int] }; [void]$pBy[$k].Add([int]$e.time) }
      foreach($e in $mLeft){   $k=("{0},{1}" -f $e.x,$e.y); if (-not $lBy[$k]) { $lBy[$k]=New-Object System.Collections.Generic.List[int] }; [void]$lBy[$k].Add([int]$e.time) }
      foreach($k in $pBy.Keys){
        $pt = @($pBy[$k].ToArray() | Sort-Object)
        $lt = if ($lBy[$k]) { @($lBy[$k].ToArray() | Sort-Object) } else { @() }
        $j = 0
        for($i=0; $i -lt $pt.Count; $i++){
          $tP = [int]$pt[$i]
          while($j -lt $lt.Count -and [int]$lt[$j] -lt $tP){ $j++ }
          $life = $ObsNaturalSec
          if ($j -lt $lt.Count){ $life = [int]([int]$lt[$j] - $tP); $j++ }
          if ($life -lt 0) { $life = 0 }
          if (-not $wardLifeMax[$k] -or [int]$wardLifeMax[$k] -lt $life) { $wardLifeMax[$k] = [int]$life }
        }
      }
    } catch {}

    # Duration capture
    try {
  $dur = 0; if ($null -ne $md.duration) { $dur = [int]$md.duration }
      $rname = if ($md.radiant_name) { [string]$md.radiant_name } else { 'Radiant' }
      $dname = if ($md.dire_name) { [string]$md.dire_name } else { 'Dire' }
      $durList.Add([pscustomobject]@{ match_id=$mid; duration=$dur; radiant=$rname; dire=$dname; radiant_win=[bool]$md.radiant_win }) | Out-Null
    } catch {}
  }

  # Build outputs
  $rampList = @()
  foreach($kv in $rampages.GetEnumerator()) {
    $aid=[int64]$kv.Key; $nm = if ($pname.ContainsKey($aid)) { $pname[$aid] } else { if ($PlayerNamesMap -and $PlayerNamesMap.ContainsKey([string]$aid)) { $PlayerNamesMap[[string]$aid] } else { ("Player {0}" -f $aid) } }
    $marr = @()
    if ($rampageGames.ContainsKey($aid)) {
      foreach($mk in $rampageGames[$aid].GetEnumerator()){
        $marr += [pscustomobject]@{ match_id=[long]$mk.Key; count=[int]$mk.Value }
      }
  $marr = $marr | Sort-Object @{e='count';Descending=$true}, @{e='match_id';Descending=$true}
    }
    $rampList += [pscustomobject]@{ account_id=$aid; name=$nm; profile=(& $OD_PLAYER_URL $aid); count=[int]$kv.Value; matches=$marr }
  }
  $rampList = $rampList | Sort-Object count -Descending | Select-Object -First 10

  $wardTop = @()
  $wardPoints = @()
  foreach($kv in $wardSpots.GetEnumerator()) {
    $wardTop += [pscustomobject]@{ spot=$kv.Key; count=[int]$kv.Value }
    try {
      $parts = $kv.Key.Split(','); $wx=[int]$parts[0]; $wy=[int]$parts[1]
      $wardPoints += [pscustomobject]@{ x=$wx; y=$wy; count=[int]$kv.Value }
    } catch {}
  }
  # stable spot ids for DOM linking
  $wardTop = $wardTop | Sort-Object count -Descending | Select-Object -First 10
  for($i=0;$i -lt $wardTop.Count;$i++){ try { $wardTop[$i] | Add-Member -NotePropertyName spotId -NotePropertyValue ("spot"+$i) -Force } catch {} }

  # Build longest-lived list (top 10 by maxSeconds, min 3 placements). Reuse spotId from wardTop when available, else derive stable id.
  $wardLongest = @()
  if ($wardLifeMax.Keys.Count -gt 0) {
    $idMap = @{}; foreach($w in $wardTop){ $idMap[[string]$w.spot] = $w.spotId }
    foreach($kv in $wardLifeMax.GetEnumerator()) {
      $s = [string]$kv.Key
      $count = try { if ($wardSpots.ContainsKey($s)) { [int]$wardSpots[$s] } else { 0 } } catch { 0 }
      if ($count -lt 3) { continue }
      $sid = $idMap[$s]
      if (-not $sid -or [string]::IsNullOrWhiteSpace($sid)) { $sid = ("spot_" + ($s -replace '[^0-9]', '_')) }
      $wardLongest += [pscustomobject]@{ spot=$s; maxSeconds=[int]$kv.Value; spotId=$sid; count=$count }
    }
    $wardLongest = $wardLongest | Sort-Object maxSeconds -Descending | Select-Object -First 10
  }

  # Player ward stat lists
  $mostPlacedArr = @()
  foreach($kv in $obsPlacedBy.GetEnumerator()){
    $aid=[int64]$kv.Key; if ($aid -le 0) { continue }
    $nm = if ($pname.ContainsKey($aid)) { $pname[$aid] } else { if ($PlayerNamesMap -and $PlayerNamesMap.ContainsKey([string]$aid)) { $PlayerNamesMap[[string]$aid] } else { ("Player {0}" -f $aid) } }
    $mostPlacedArr += [pscustomobject]@{ account_id=$aid; name=$nm; profile=(& $OD_PLAYER_URL $aid); count=[int]$kv.Value }
  }
  $mostPlacedArr = $mostPlacedArr | Sort-Object count -Descending | Select-Object -First 5

  $mostDewardsArr = @()
  foreach($kv in $dewardsBy.GetEnumerator()){
    $aid=[int64]$kv.Key; if ($aid -le 0) { continue }
    $nm = if ($pname.ContainsKey($aid)) { $pname[$aid] } else { if ($PlayerNamesMap -and $PlayerNamesMap.ContainsKey([string]$aid)) { $PlayerNamesMap[[string]$aid] } else { ("Player {0}" -f $aid) } }
    $mostDewardsArr += [pscustomobject]@{ account_id=$aid; name=$nm; profile=(& $OD_PLAYER_URL $aid); count=[int]$kv.Value }
  }
  $mostDewardsArr = $mostDewardsArr | Sort-Object count -Descending | Select-Object -First 5

  $longestAvgArr = @()
  foreach($kv in $lifeBy.GetEnumerator()){
    $aid=[int64]$kv.Key; if ($aid -le 0) { continue }
    $lst = $kv.Value
    $cnt = [int]$lst.Count
    if ($cnt -le 0) { continue }
    $avg = [double]((($lst | Measure-Object -Average).Average) )
    if (-not $avg) { $avg = 0 }
    $nm = if ($pname.ContainsKey($aid)) { $pname[$aid] } else { if ($PlayerNamesMap -and $PlayerNamesMap.ContainsKey([string]$aid)) { $PlayerNamesMap[[string]$aid] } else { ("Player {0}" -f $aid) } }
    $longestAvgArr += [pscustomobject]@{ account_id=$aid; name=$nm; profile=(& $OD_PLAYER_URL $aid); avgSeconds=[int][math]::Round($avg); samples=$cnt }
  }
  $longestAvgArr = $longestAvgArr | Sort-Object avgSeconds -Descending | Select-Object -First 5

  # Top teammates (pairs with most games together)
  $teammatesTop = @()
  foreach($kv in $pairCounts.GetEnumerator()){
    try {
      $parts = ([string]$kv.Key).Split('-'); $a=[int64]$parts[0]; $b=[int64]$parts[1]; $cnt=[int]$kv.Value
      $n1 = if ($pname.ContainsKey($a)) { $pname[$a] } elseif ($PlayerNamesMap[[string]$a]) { $PlayerNamesMap[[string]$a] } else { "Player $a" }
      $n2 = if ($pname.ContainsKey($b)) { $pname[$b] } elseif ($PlayerNamesMap[[string]$b]) { $PlayerNamesMap[[string]$b] } else { "Player $b" }
      $teammatesTop += [pscustomobject]@{ a=$a; b=$b; name1=$n1; name2=$n2; profile1=(& $OD_PLAYER_URL $a); profile2=(& $OD_PLAYER_URL $b); games=$cnt }
    } catch {}
  }
  if ($teammatesTop.Count -gt 0) { $teammatesTop = $teammatesTop | Sort-Object @{e='games';Descending=$true}, @{e='name1'} | Select-Object -First 3 }

  # Top courier kills / camps stacked
  $courierTop = @(); foreach($kv in $courierKillsBy.GetEnumerator()){
    $aid=[int64]$kv.Key; $nm = if ($pname.ContainsKey($aid)) { $pname[$aid] } elseif ($PlayerNamesMap[[string]$aid]) { $PlayerNamesMap[[string]$aid] } else { "Player $aid" }
    $courierTop += [pscustomobject]@{ account_id=$aid; name=$nm; profile=(& $OD_PLAYER_URL $aid); count=[int]$kv.Value }
  }
  if ($courierTop.Count -gt 0) { $courierTop = $courierTop | Sort-Object count -Descending | Select-Object -First 3 }
  $stackTop = @(); foreach($kv in $campsStackedBy.GetEnumerator()){
    $aid=[int64]$kv.Key; $nm = if ($pname.ContainsKey($aid)) { $pname[$aid] } elseif ($PlayerNamesMap[[string]$aid]) { $PlayerNamesMap[[string]$aid] } else { "Player $aid" }
    $stackTop += [pscustomobject]@{ account_id=$aid; name=$nm; profile=(& $OD_PLAYER_URL $aid); count=[int]$kv.Value }
  }
  if ($stackTop.Count -gt 0) { $stackTop = $stackTop | Sort-Object count -Descending | Select-Object -First 3 }

  $safeTop = @(); $offTop=@()
  foreach($kv in $duos.Safe.GetEnumerator()){
    $a = [int]($kv.Key.Split('-')[0]); $b=[int]($kv.Key.Split('-')[1]); $v=$kv.Value
    $wr = if ($v.games -gt 0) { [double]$v.wins/$v.games } else { 0 }
    $safeTop += [pscustomobject]@{ a=$a; b=$b; games=$v.games; wins=$v.wins; winrate=$wr }
  }
  foreach($kv in $duos.Off.GetEnumerator()){
    $a = [int]($kv.Key.Split('-')[0]); $b=[int]($kv.Key.Split('-')[1]); $v=$kv.Value
    $wr = if ($v.games -gt 0) { [double]$v.wins/$v.games } else { 0 }
    $offTop += [pscustomobject]@{ a=$a; b=$b; games=$v.games; wins=$v.wins; winrate=$wr }
  }
  $safeTop = $safeTop | Sort-Object @{e='winrate';Descending=$true}, @{e='games';Descending=$true} | Select-Object -First 5
  $offTop  = $offTop  | Sort-Object @{e='winrate';Descending=$true}, @{e='games';Descending=$true} | Select-Object -First 5

  # Roshan totals and top matches
  $roshanAgg = [pscustomobject]@{ Radiant=$roshanTeam.Radiant; Dire=$roshanTeam.Dire }
  # Build per-match Roshan aggregation (Radiant/Dire counts per match)
  $roshanByMatch = @()
  try {
    $allKeys = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach($k in $roshanPerMatch.Radiant.Keys){ [void]$allKeys.Add([string]$k) }
    foreach($k in $roshanPerMatch.Dire.Keys){ [void]$allKeys.Add([string]$k) }
    foreach($k in $allKeys){
      try {
        $r = 0; $d = 0
        if ($roshanPerMatch.Radiant.ContainsKey($k)) { $r = [int]$roshanPerMatch.Radiant[$k] }
        if ($roshanPerMatch.Dire.ContainsKey($k))    { $d = [int]$roshanPerMatch.Dire[$k] }
        $mid = 0
        try { $mid = [int64]$k } catch { try { $mid = [int64]::Parse($k) } catch { $mid = 0 } }
        $roshanByMatch += [pscustomobject]@{ match_id=$mid; Radiant=$r; Dire=$d; total=([int]$r + [int]$d) }
      } catch {}
    }
  } catch {}
  function Get-TopRoshan($ht){
    try {
      $arr = @()
      foreach($kv in $ht.GetEnumerator()){
        $arr += [pscustomobject]@{ match_id=[long]$kv.Key; count=[int]$kv.Value }
      }
      if ($arr.Count -eq 0) { return @() }
      $arr = $arr | Sort-Object @{e='count';Descending=$true}, @{e='match_id';Descending=$true}
      $max = [int]$arr[0].count
      return @($arr | Where-Object { [int]$_.count -eq $max } | Select-Object -First 3)
    } catch { return @() }
  }
  $roshanTop = [pscustomobject]@{
    Radiant = (Get-TopRoshan $roshanPerMatch.Radiant)
    Dire    = (Get-TopRoshan $roshanPerMatch.Dire)
  }
  # Build Top-Single block
  $topSingle = [pscustomobject]@{}
  if ($bestGPM)     { $topSingle | Add-Member -NotePropertyName gpm     -NotePropertyValue $bestGPM -Force }
  if ($bestKills)   { $topSingle | Add-Member -NotePropertyName kills   -NotePropertyValue $bestKills -Force }
  if ($bestAssists) { $topSingle | Add-Member -NotePropertyName assists -NotePropertyValue $bestAssists -Force }
  if ($bestNet)     { $topSingle | Add-Member -NotePropertyName networth -NotePropertyValue $bestNet -Force }

  # Duration lists
  $durArr = $durList.ToArray()
  $durLongest = @($durArr | Sort-Object duration -Descending | Select-Object -First 3)
  $durShortest = @($durArr | Sort-Object duration | Select-Object -First 3)

  # ===== Awards (top 3 each) =====
  function TopN([hashtable]$map,[int]$n){ $arr=@(); foreach($kv in $map.GetEnumerator()){ $arr += [pscustomobject]@{ account_id=[int64]$kv.Key; val=[double]$kv.Value } }; if ($arr.Count -eq 0) { return @() }; return @($arr | Sort-Object @{e='val';Descending=$true} | Select-Object -First $n) }
  function WithNames($arr){ $o=@(); foreach($x in $arr){ $aid=[int64]$x.account_id; $nm = if ($pname.ContainsKey($aid)) { $pname[$aid] } elseif ($PlayerNamesMap[[string]$aid]) { $PlayerNamesMap[[string]$aid] } else { "Player $aid" }; $o += [pscustomobject]@{ account_id=$aid; name=$nm; profile=(& $OD_PLAYER_URL $aid); val=[double]$x.val } }; return $o }
  # Space Creator
  $aw_space = WithNames (TopN $DeathsInWins 3)
  # Objective Gamer (share and rosh)
  $aw_obj = @()
  foreach($kv in $TowerDamageBy.GetEnumerator()){
    $aid = [int64]$kv.Key
    $td  = [double]$kv.Value
    $teamTot = 0.0
    if ($TeamTowerSumById.ContainsKey($aid)) { $teamTot = [double]$TeamTowerSumById[$aid] }
    $share = if ($teamTot -gt 0) { $td / $teamTot } else { 0.0 }
    $nm = if ($pname.ContainsKey($aid)) { $pname[$aid] } elseif ($PlayerNamesMap[[string]$aid]) { $PlayerNamesMap[[string]$aid] } else { "Player $aid" }
    $ro = 0
    if ($RoshParticipation.ContainsKey($aid)) { $ro = [int]$RoshParticipation[$aid] }
    $aw_obj += [pscustomobject]@{ account_id=$aid; name=$nm; profile=(& $OD_PLAYER_URL $aid); share=[double]$share; rosh=[int]$ro }
  }
  if ($aw_obj.Count -gt 0) { $aw_obj = @($aw_obj | Sort-Object @{e='share';Descending=$true}, @{e='rosh';Descending=$true} | Select-Object -First 3) }
  # Early Farmer top 3
  $aw_early = @(); foreach($kv in $EarlyBest.GetEnumerator()){ $aid=[int64]$kv.Key; $nm = if ($pname.ContainsKey($aid)) { $pname[$aid] } elseif ($PlayerNamesMap[[string]$aid]) { $PlayerNamesMap[[string]$aid] } else { "Player $aid" }; $aw_early += [pscustomobject]@{ account_id=$aid; name=$nm; profile=(& $OD_PLAYER_URL $aid); value=[int]$kv.Value } }; if ($aw_early.Count -gt 0) { $aw_early = @($aw_early | Sort-Object @{e='value';Descending=$true} | Select-Object -First 3) }
  # Clutch King
  $aw_clutch = @(); foreach($kv in $Clutch.GetEnumerator()){ $aid=[int64]$kv.Key; $st=$kv.Value; $ratio = if ($st.tk -gt 0) { [double]$st.contrib / [double]$st.tk } else { 0.0 }; $nm = if ($pname.ContainsKey($aid)) { $pname[$aid] } elseif ($PlayerNamesMap[[string]$aid]) { $PlayerNamesMap[[string]$aid] } else { "Player $aid" }; $aw_clutch += [pscustomobject]@{ account_id=$aid; name=$nm; profile=(& $OD_PLAYER_URL $aid); ratio=[double]$ratio } }; if ($aw_clutch.Count -gt 0) { $aw_clutch = @($aw_clutch | Sort-Object @{e='ratio';Descending=$true} | Select-Object -First 3) }
  # Other simple maps
  $aw_courier = WithNames (TopN $courierKillsBy 3)
  $aw_stack   = WithNames (TopN $campsStackedBy 3)
  $aw_smoke   = WithNames (TopN $SmokeUses 3)
  $aw_runes   = WithNames (TopN $RunesCount 3)
  $aw_vision  = WithNames (TopN $WardScore 3)
  $aw_aegis   = WithNames (TopN $AegisSnatched 3)

  $awards = [pscustomobject]@{
    spaceCreator = $aw_space
    objectiveGamer = $aw_obj
    earlyFarmer = $aw_early
    clutchKing = $aw_clutch
    courierAssassin = $aw_courier
    visionMvp = $aw_vision
    stackMaster = $aw_stack
    smokeCommander = $aw_smoke
    runeController = $aw_runes
    aegisSnatcher = $aw_aegis
  }

  return [pscustomobject]@{
    rampages   = $rampList
    wardSpots  = $wardTop
  wardPoints = $wardPoints
  wardEvents = $wardEvents.ToArray()
  wardLongest = $wardLongest
    wardPlayers = [pscustomobject]@{ mostPlaced=$mostPlacedArr; mostDewards=$mostDewardsArr; longestAvg=$longestAvgArr }
  teammates  = $teammatesTop
  courierTop = $courierTop
  stackTop   = $stackTop
    safeDuos   = $safeTop
    offDuos    = $offTop
  roshan     = $roshanAgg
  roshanTop  = $roshanTop
  roshanByMatch = $roshanByMatch
  topSingle  = $topSingle
  aegisSnatch = $aegisSnatch.ToArray()
  tormentor   = $tormentorTaken.ToArray()
  objectivesSeen = ([bool]($objectivesSeen -gt 0))
    durationLongest = $durLongest
    durationShortest = $durShortest
    awards = $awards
  }
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

# Load match records directly from cached OpenDota match JSONs (fallback when Steam is unavailable)
function Load-MatchRecordsFromODCache {
  param([string]$RepoPath,[int]$CutoffUnix)
  $base = if ($RepoPath) { $RepoPath } else { $PSScriptRoot }
  $dir = Join-Path $base 'data/cache/OpenDota/matches'
  if (-not (Test-Path -LiteralPath $dir)) { return @() }
  $files = Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue
  if (-not $files -or $files.Count -eq 0) { return @() }
  $out = New-Object System.Collections.Generic.List[object]
  foreach($f in $files){
    try {
      $md = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($md -and $md.match_id) {
        if ($CutoffUnix -gt 0 -and [int64]$md.start_time -lt $CutoffUnix) { continue }
        $rec = Build-MatchRecordFromOD $md
        if ($rec) { $out.Add($rec) | Out-Null }
      }
    } catch {}
  }
  return $out.ToArray()
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
  $v = $kv.Value; if ($null -eq $v) { continue }
      $id  = [int]$v.id
      $tag = ([string]$v.name) -replace 'npc_dota_hero_',''
      $map[$id] = [pscustomobject]@{ id=$id; tag=$tag; name=$v.localized_name }
    } ; return $map
  }
  foreach ($prop in $heroesConst.PSObject.Properties) {
  $v = $prop.Value; if ($null -eq $v) { continue }
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
  $v = $prop.Value; if ($null -eq $v) { continue }
    $d = $null
    if ($v.date -is [string]) { [void][DateTimeOffset]::TryParse($v.date, [ref]$d) }
    elseif ($v.date -is [double] -or $v.date -is [int]) { $d = [DateTimeOffset]::FromUnixTimeSeconds([long]$v.date) }
  if ($null -ne $d) { if ($null -eq $latest -or $d -gt $latest) { $latest = $d } }
  }
  if ($null -eq $latest) { return 0 }
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
        $hid = [int]$pb.hero_id; $hidKey = [string]$hid
        if (-not $heroStats.ContainsKey($hidKey)) { $heroStats[$hidKey] = [pscustomobject]@{ picks=0; wins=0; bans=0 } }
        if (-not $pb.is_pick) { $heroStats[$hidKey].bans++ }
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
        $hidKey = [string]$hid
        Inc-Map $ps.heroes $hidKey
        if (-not $heroStats.ContainsKey($hidKey)) { $heroStats[$hidKey] = [pscustomobject]@{ picks=0; wins=0; bans=0 } }
        $heroStats[$hidKey].picks++; if ($won) { $heroStats[$hidKey].wins++ }

        if (-not $heroPlayerAgg.ContainsKey($hidKey)) { $heroPlayerAgg[$hidKey] = @{} }
        if (-not $heroPlayerAgg[$hidKey].ContainsKey($id)) {
          $heroPlayerAgg[$hidKey][$id] = [pscustomobject]@{ account_id=$id; name=$ps.name; games=0; wins=0; profile=$ps.profile }
        }
        $hp = $heroPlayerAgg[$hidKey][$id]; $hp.games++; if ($won) { $hp.wins++ }
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
  # Pinned dynamic viewer entry at the top
  $entryRows.Add('<li class="item" data-range="dynamic" data-time="9223372036854775807"><a href="./dynamic.html">Dynamic view (custom timeframe)</a></li>') | Out-Null
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
.has-hover{position:relative}
.hovercard{display:none;position:absolute;left:0;top:100%;margin-top:6px;z-index:5;min-width:260px;max-width:420px;padding:10px;border-radius:10px;background:rgba(15,20,40,.96);border:1px solid rgba(255,255,255,.12);box-shadow:0 8px 24px rgba(0,0,0,.35)}
.hovercard .title{font-weight:600;color:var(--muted);font-size:12px;margin-bottom:6px}
.hovercard a{display:inline-block;margin:2px 6px 2px 0;background:var(--chip);padding:3px 8px;border-radius:999px}
.has-hover:hover > .hovercard{display:block}
/* Hero gallery inside hovercard */
.hovercard .heroes{max-width:520px}
</style>
</head>
<body>
  <aside class='sidebar'>
    <div class='brand'>
      <h1>Reports - $(HtmlEscape $LeagueName)</h1>
      <div class='sub'>Pick a run or filter by range.</div>
    </div>
  <!-- Filters removed; Dynamic view is available as a pinned list entry below -->
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
  const frame = document.getElementById('frame');
  const title = document.getElementById('viewerTitle');
  const openNew = document.getElementById('openNew');
  const prevBtn = document.getElementById('prevBtn');
  const nextBtn = document.getElementById('nextBtn');
  let selIndex = -1;

  function vis(){ return items.filter(li => li.style.display !== 'none'); }
  function txt(li){ const a=li.querySelector('a'); return a ? a.textContent.trim() : li.getAttribute('data-range'); }

  function apply(){
    const term = q.value.trim().toLowerCase(); let n=0;
    items.forEach(li=>{
      const t = txt(li).toLowerCase();
      const ok = (!term || t.includes(term));
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
  q.addEventListener('input', apply);
  prevBtn.addEventListener('click', ()=> select(selIndex-1));
  nextBtn.addEventListener('click', ()=> select(selIndex+1));
  document.addEventListener('keydown', ev=>{ if (ev.key==='ArrowUp'){ev.preventDefault(); select(selIndex-1);} if (ev.key==='ArrowDown'){ev.preventDefault(); select(selIndex+1);} });

  function init(){
    const file = new URLSearchParams(location.hash.replace(/^#/, '')).get('file');
    if (file){ const t=items.find(li => li.querySelector('a')?.getAttribute('href')===file); if (t){ const v=items; const idx=v.indexOf(t); if (idx>=0){ select(idx); return; } } }
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
  git add -- "docs/$file" "docs/index.html" "docs/dynamic.html" | Out-Null
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

  # Collect files we want to include in commit before we reach the publish stage
  $preExtraCommit = @()

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

  if ($Range -eq "All" -and -not $PreferShards) {
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
      try { $md = Ensure-OD-Match -matchId $mid -retries 5 -delayMs 3000 } catch { $md = $null }
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
  if ($null -eq $pp.team_id) {
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
          $hid = [int]$pb.hero_id; $hidKey=[string]$hid
          if (-not $heroStats.ContainsKey($hidKey)) { $heroStats[$hidKey] = [pscustomobject]@{ picks=0; wins=0; bans=0 } }
          if (-not $pb.is_pick) { $heroStats[$hidKey].bans++ }
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
          $hidKey=[string]$hid
          Inc-Map $ps.heroes $hidKey
          if (-not $heroStats.ContainsKey($hidKey)) { $heroStats[$hidKey] = [pscustomobject]@{ picks=0; wins=0; bans=0 } }
          $heroStats[$hidKey].picks++; if ($won) { $heroStats[$hidKey].wins++ }

          if (-not $heroPlayerAgg.ContainsKey($hidKey)) { $heroPlayerAgg[$hidKey] = @{} }
          if (-not $heroPlayerAgg[$hidKey].ContainsKey($id)) {
            $heroPlayerAgg[$hidKey][$id] = [pscustomobject]@{ account_id=$id; name=$ps.name; games=0; wins=0; profile=$ps.profile }
          }
          $hp = $heroPlayerAgg[$hidKey][$id]; $hp.games++; if ($won) { $hp.wins++ }
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

  # Build parsed/pending lists across all cached matches and save files
  Write-Host "Auditing OpenDota parse status for all cached matches ..." -ForegroundColor Cyan
  $audit = Audit-ParsedStatus -MatchRecords $state.matches
  $paths = Get-ParseFiles -RepoPath $RepoPath
  # allgames_parsed.json: store only match_ids, sorted by date
  $parsedIds = @($audit.parsed | Sort-Object start_time | ForEach-Object { [long]$_.match_id })
  Save-IdArray -ids $parsedIds -path $paths.parsed
  # ready_toParse.json: match_ids not parsed yet
  $pendingList = @([long[]]$audit.pending)
  Save-IdArray -ids ($pendingList | Sort-Object) -path $paths.ready
  # Proactively request OpenDota parse for a capped batch of oldest pending matches
  if ($pendingList -and $pendingList.Count -gt 0) {
    $pendSorted = $pendingList | Sort-Object
    $reqIds = @($pendSorted | Select-Object -First 100)
    try {
      $readyPath = Update-ReadyToParse -newIds $reqIds -RepoPath $RepoPath -MaxRequests 100
      Write-Host ("Requested OpenDota parse for {0} pending matches" -f $reqIds.Count) -ForegroundColor DarkCyan
      $extraCommit += ,$readyPath
    } catch { Write-Warning ("Parse request batch failed: " + $_.Exception.Message) }
  }
  $extraCommit += ,$paths.parsed
  $extraCommit += ,$paths.ready

  } else {
    # ===== Range report (prefer cache) =====
    $agg = $null
    if ($Range -eq "Patch") {
      Write-Host "Resolving last patch cutoff via OpenDota ..." -ForegroundColor Cyan
      $cutoffUnix = Get-CutoffUnix -Range "Patch"
    }
    $agg = Compute-FromCache -range $Range -cutUnix $cutoffUnix
  if ($null -ne $agg) {
      Write-Host "Using cached matches from state to build range report." -ForegroundColor Green
      $teams = $agg.teams; $players = $agg.players; $teamPlayers = $agg.teamPlayers; $heroStats = $agg.heroStats; $heroPlayerAgg = $agg.heroPlayerAgg
      # Monthly exclude: recompute aggregates excluding listed matches
      if ($Range -eq "30") {
        $excludeSet = Load-ExcludeSet -RepoPath $RepoPath
        if (-not $excludeSet) { $excludeSet = [System.Collections.Generic.HashSet[string]]::new() }
        $exSet = $excludeSet
        $monthSubset = if ($cutoffUnix -gt 0) {
          @($state.matches | Where-Object {
            try { ([int64]$_.start_time -ge $cutoffUnix) -and -not ($exSet -and $exSet.Contains([string]$_.match_id)) } catch { $true }
          })
        } else {
          @($state.matches | Where-Object {
            try { -not ($exSet -and $exSet.Contains([string]$_.match_id)) } catch { $true }
          })
        }
        if ($monthSubset.Count -gt 0) {
          $aggX = Aggregate-FromMatches -MatchesSubset $monthSubset -PlayerNamesMap $state.playerNames -TeamNamesMap $state.teamNames
          $teams = $aggX.teams; $players = $aggX.players; $teamPlayers = $aggX.teamPlayers; $heroStats = $aggX.heroStats; $heroPlayerAgg = $aggX.heroPlayerAgg
          Write-Host ("Monthly exclude applied: using {0} matches" -f $monthSubset.Count) -ForegroundColor DarkYellow
        }
      }
        # ===== Apply exclude list to All-time stats (display only) =====
        if ($Range -eq "All") {
          $excludeSet = Load-ExcludeSet -RepoPath $RepoPath
          if ($excludeSet -and $excludeSet.Count -gt 0) {
            $allSubset = @($state.matches | Where-Object { -not $excludeSet.Contains([string]$_.match_id) })
            if ($allSubset.Count -gt 0) {
              $aggEx = Aggregate-FromMatches -MatchesSubset $allSubset -PlayerNamesMap $state.playerNames -TeamNamesMap $state.teamNames
              $teams = $aggEx.teams; $players = $aggEx.players; $teamPlayers = $aggEx.teamPlayers; $heroStats = $aggEx.heroStats; $heroPlayerAgg = $aggEx.heroPlayerAgg
              Write-Host ("All-time exclude applied: using {0} matches" -f $allSubset.Count) -ForegroundColor DarkYellow
            } else {
              Write-Host "All-time exclude removed all matches; rendering empty aggregates." -ForegroundColor Yellow
              $teams=@{}; $players=@{}; $teamPlayers=@{}; $heroStats=@{}; $heroPlayerAgg=@{}
            }
          }
        }

    } else {
      # First install / empty cache fallback: fetch online just for this range
      Write-Host "Cache empty -> fetching from Steam/OpenDota for range ..." -ForegroundColor Yellow
      $script:__HandledViaODCache = $false
      $matchList = $null
      try {
        $matchList = Get-SteamMatchHistory -leagueId $LEAGUE_ID -cutoffUnix $cutoffUnix -maxMatches $MaxMatches
      } catch {
        Write-Warning ("Steam history fetch failed: " + $_.Exception.Message)
        Write-Host "Attempting fallback to local OpenDota match cache ..." -ForegroundColor Yellow
        $recs = Load-MatchRecordsFromODCache -RepoPath $RepoPath -CutoffUnix $cutoffUnix
        if ($recs -and $recs.Count -gt 0) {
          Write-Host ("Using {0} cached OpenDota matches from disk." -f $recs.Count) -ForegroundColor Green
          # Merge these into aggregates directly and skip Steam path
          $teams = @{}; $players=@{}; $teamPlayers=@{}; $heroStats=@{}; $heroPlayerAgg=@{}
          $agg2 = Aggregate-FromMatches -MatchesSubset $recs -PlayerNamesMap $state.playerNames -TeamNamesMap $state.teamNames
          $teams = $agg2.teams; $players = $agg2.players; $teamPlayers = $agg2.teamPlayers; $heroStats = $agg2.heroStats; $heroPlayerAgg = $agg2.heroPlayerAgg
          # Short-circuit: assign and jump out of fallback branch by simulating matches processed
          $matchList = @()  # indicate handled via cache
          $script:__HandledViaODCache = $true
        } else {
          throw
        }
      }
      # If Steam returned no matches without throwing, try OD cache too
      if (-not $script:__HandledViaODCache -and (-not $matchList -or $matchList.Count -eq 0)) {
        Write-Host "Steam returned no matches; attempting fallback to local OpenDota match cache ..." -ForegroundColor Yellow
        $recs = Load-MatchRecordsFromODCache -RepoPath $RepoPath -CutoffUnix $cutoffUnix
        if ($recs -and $recs.Count -gt 0) {
          Write-Host ("Using {0} cached OpenDota matches from disk." -f $recs.Count) -ForegroundColor Green
          $agg2 = Aggregate-FromMatches -MatchesSubset $recs -PlayerNamesMap $state.playerNames -TeamNamesMap $state.teamNames
          $teams = $agg2.teams; $players = $agg2.players; $teamPlayers = $agg2.teamPlayers; $heroStats = $agg2.heroStats; $heroPlayerAgg = $agg2.heroPlayerAgg
          $matchList = @()
          $script:__HandledViaODCache = $true
        }
      }
      if ($Range -eq "30" -and -not $script:__HandledViaODCache -and $matchList) {
        $excludeSet = Load-ExcludeSet -RepoPath $RepoPath
        if (-not $excludeSet) { $excludeSet = [System.Collections.Generic.HashSet[string]]::new() }
        $exSet = $excludeSet
        $matchList = @($matchList | Where-Object {
          try { -not ($exSet -and $exSet.Contains([string]$_.match_id)) } catch { $true }
        })
      }
      if (-not $script:__HandledViaODCache -and (-not $matchList -or $matchList.Count -eq 0)) { throw "No matches in the selected range." }

  if (-not $script:__HandledViaODCache -and $matchList) {
  foreach ($m in $matchList) {
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
            $hkStr = [string]$hk
            if (-not $heroStats.ContainsKey($hkStr)) { $heroStats[$hkStr] = [pscustomobject]@{ picks=0; wins=0; bans=0 } }
            $heroStats[$hkStr].picks += $agg2.heroStats[$hk].picks
            $heroStats[$hkStr].wins  += $agg2.heroStats[$hk].wins
            $heroStats[$hkStr].bans  += $agg2.heroStats[$hk].bans
          }
          # HeroPlayerAgg
          foreach ($hk in $agg2.heroPlayerAgg.Keys) {
            $hkStr = [string]$hk
            if (-not $heroPlayerAgg.ContainsKey($hkStr)) { $heroPlayerAgg[$hkStr] = @{} }
            foreach ($pp in $agg2.heroPlayerAgg[$hk].Values) {
              if (-not $heroPlayerAgg[$hkStr].ContainsKey($pp.account_id)) {
                $heroPlayerAgg[$hkStr][$pp.account_id] = [pscustomobject]@{ account_id=$pp.account_id; name=$pp.name; games=0; wins=0; profile=$pp.profile }
              }
              $heroPlayerAgg[$hkStr][$pp.account_id].games += $pp.games
              $heroPlayerAgg[$hkStr][$pp.account_id].wins  += $pp.wins
            }
          }
        }
      } # end foreach matches
      } # end not handled via OD cache
  } # end fallback
  } # end range handling

  # ===== Build lists from aggregates =====
  $teamList = ($teams.Values | ForEach-Object {
    $wr = if ($_.games -gt 0) { [double]$_.wins / $_.games } else { 0 }
    [pscustomobject]@{ team_id=$_.team_id; name=$_.name; games=$_.games; wins=$_.wins; losses=$_.losses; winrate=$wr; logo=(Get-TeamLogoUrl $_.team_id) }
  }) | Sort-Object @{e='winrate';Descending=$true}, @{e='games';Descending=$true}

  $playerList = ($players.Values | ForEach-Object {
    $wr = if ($_.games -gt 0) { [double]$_.wins / $_.games } else { 0 }
  $allHeroes=@()
  $heroWL = @{}
    if ($_.heroes.Count -gt 0) {
      $heroCounts = (Get-MapEnumerator $_.heroes)
      foreach ($hc in $heroCounts) {
        $hid=[int]$hc.Key; $cnt=[int]$hc.Value
        $meta=$heroMap[$hid]; $hName= if($meta -and $meta.name){$meta.name}else{"Hero $hid"}
        $hTag = if($meta -and $meta.tag){$meta.tag}else{"default"}
    # derive per-hero W/L for this player from heroPlayerAgg map
    $wins=0; $games=$cnt
    try { if ($heroPlayerAgg.ContainsKey([string]$hid)) { $hp = $heroPlayerAgg[[string]$hid][[int]$_.account_id]; if ($hp){ $wins = [int]$hp.wins; $games = [int]$hp.games } } } catch {}
    $loss = [int]([math]::Max(0, $games - $wins))
    $wrp = if ($games -gt 0) { [double]$wins/$games } else { 0 }
    $allHeroes += [pscustomobject]@{ id=$hid; count=$games; wins=$wins; losses=$loss; wr=$wrp; name=$hName; tag=$hTag; img=(Get-HeroPortraitUrl $hTag) }
      }
      $allHeroes = $allHeroes | Sort-Object name
    }
  [pscustomobject]@{ account_id=$_.account_id; name=$_.name; games=$_.games; wins=$_.wins; winrate=$wr; topHeroes=$allHeroes; profile=$_.profile }
  }) | Sort-Object @{e='games';Descending=$true}, @{e='winrate';Descending=$true}, @{e='name'}

  $heroSummary = (Get-MapEnumerator $heroStats | ForEach-Object {
    $hid = [int]$_.Key; $hs=$_.Value
    $picks=[int]$hs.picks; $wins=[int]$hs.wins; $bans=[int]$hs.bans
    $wr = if ($picks -gt 0) { [double]$wins / $picks } else { 0 }
    $meta=$heroMap[$hid]; $name= if($meta -and $meta.name){$meta.name}else{"Hero $hid"}
    $tag = if($meta -and $meta.tag){$meta.tag}else{"default"}
    [pscustomobject]@{ id=$hid; name=$name; tag=$tag; img=(Get-HeroPortraitUrl $tag); picks=$picks; wins=$wins; bans=$bans; winrate=$wr }
  })

  # Include all heroes (even with zero picks/bans) for the Heroes table, sorted by name
  $heroSummaryAll = @()
  foreach ($hid in ($heroMap.Keys | Sort-Object)) {
    $meta = $heroMap[$hid]
    $name = if ($meta -and $meta.name) { $meta.name } else { "Hero $hid" }
    $tag  = if ($meta -and $meta.tag)  { $meta.tag  } else { "default" }
    $existing = $heroSummary | Where-Object { $_.id -eq [int]$hid } | Select-Object -First 1
    if ($existing) { $heroSummaryAll += ,$existing }
    else { $heroSummaryAll += ,[pscustomobject]@{ id=[int]$hid; name=$name; tag=$tag; img=(Get-HeroPortraitUrl $tag); picks=0; wins=0; bans=0; winrate=0 } }
  }

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
  foreach ($kv in (Get-MapEnumerator $heroPlayerAgg)) {
    $hid = [int]$kv.Key
    $candArr = New-Object System.Collections.Generic.List[object]
    foreach ($pp in ($kv.Value).Values) {
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
  $hrows = ($p.topHeroes | ForEach-Object { "<tr><td style='text-align:left'><div style='display:flex;align-items:center;gap:8px'><img src='" + (HtmlEscape $_.img) + "' style='width:22px;height:22px;border-radius:6px;border:1px solid rgba(255,255,255,.1)'><span>" + (HtmlEscape $_.name) + "</span></div></td><td>" + ([string]$_.count) + "</td><td><span class='win'>" + ([string][int]$_.wins) + "</span>-<span class='loss'>" + ([string][int]$_.losses) + "</span></td><td>" + (FmtPct $_.wr) + "</td></tr>" }) -join ""
  $htable = "<table class='table' style='min-width:420px'><thead><tr><th>Hero</th><th>Games</th><th>W-L</th><th>WR</th></tr></thead><tbody>" + $hrows + "</tbody></table>"
  $count = [int]$p.topHeroes.Count
  "<div class='has-hover'><a href='#' class='badge player-heroes' data-player='" + (HtmlEscape $p.account_id) + "'>" + $count + " heroes</a><div class='hovercard' style='display:none'><div class='title'>Heroes played (" + $count + ") - " + (HtmlEscape $p.name) + "</div>" + $htable + "</div></div>"
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
  <th data-type="text">Heroes played</th>
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
  foreach ($h in ($heroSummaryAll | Sort-Object @{e='name'})) {
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
  $HeaderN = 3
  $topMostPicked3 = $topMostPicked | Select-Object -First $HeaderN
  $topBanned3     = $topBanned     | Select-Object -First $HeaderN
  $topPlayers3    = $topPlayersHdr | Select-Object -First $HeaderN
  $topPlayed3     = ($playerList | Sort-Object @{e='games';Descending=$true}, @{e='winrate';Descending=$true} | Select-Object -First $HeaderN)
  $minGamesHeroWR = 5
  $bestHeroWR = ($heroSummaryAll | Where-Object { $_.picks -ge $minGamesHeroWR } | Sort-Object @{e='winrate';Descending=$true}, @{e='picks';Descending=$true} | Select-Object -First 1)
  $worstHeroWR = ($heroSummaryAll | Where-Object { $_.picks -ge $minGamesHeroWR } | Sort-Object @{e='winrate'}, @{e='picks';Descending=$true} | Select-Object -First 1)

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
/* Use grid for stable one-line rows: [icon/logo] [name grows/ellipsizes] [badge] [badge] */
.summary-card li{display:grid;grid-template-columns:auto minmax(0,1fr) auto auto;align-items:center;gap:8px;min-height:28px}
.summary-card li > .name{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.summary-card li > .name a{display:inline-block;max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.summary-card .badge{white-space:nowrap}
.summary-card img{width:24px;height:24px;border-radius:6px;object-fit:cover;border:1px solid rgba(255,255,255,.1)}
.heroes{display:flex;gap:8px;flex-wrap:wrap}
.hero{display:inline-flex;flex-direction:column;align-items:center;gap:4px;font-size:11px;width:64px}
.hero img{width:64px;height:36px;object-fit:cover;border-radius:8px;border:1px solid rgba(255,255,255,.08)}
.logo{width:20px;height:20px;border-radius:50%;object-fit:cover;border:1px solid rgba(255,255,255,.1)}
.teamcell{display:flex;align-items:center;gap:8px}
.grid2{display:grid;grid-template-columns:repeat(2,1fr);gap:12px}
.grid3{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}
.simple{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:6px}
.cal{margin-top:8px}
.cal .grid7{display:grid;grid-template-columns:repeat(7,1fr);gap:6px}
.cal .dow div{color:var(--muted);font-size:12px;text-align:center}
.cal .day{min-height:88px;border:1px solid rgba(255,255,255,.08);border-radius:10px;padding:8px;background:linear-gradient(180deg,rgba(255,255,255,.03),rgba(255,255,255,.015))}
.cal .date{font-weight:600;color:var(--muted);font-size:12px;margin-bottom:4px}
.cal .matches{display:flex;flex-wrap:wrap;gap:4px}
.cal .matches a{display:inline-block;background:var(--chip);color:var(--text);border-radius:999px;font-size:11px;padding:2px 6px}
.table th{cursor:pointer; position:relative}
.table th.sorted-asc::after{content:" ▲"; font-size:11px; color:var(--muted)}
.table th.sorted-desc::after{content:" ▼"; font-size:11px; color:var(--muted)}
.toolbar{display:flex;justify-content:flex-end;gap:8px;margin-bottom:8px}
.wardmap{margin:8px 0 0;position:relative;width:100%;aspect-ratio:1/1;background:url('https://www.opendota.com/assets/images/dota2map/dota2map_full.jpg') center/cover no-repeat;border:1px solid rgba(255,255,255,.08);border-radius:12px}
.wardmap.half{width:50%; margin:8px auto 0}
.wardgrid{display:grid;grid-template-columns:1.2fr .8fr;gap:12px;align-items:start}
.wardleft{position:relative}
.wardright{position:relative}
@media (max-width: 980px){.wardgrid{grid-template-columns:1fr}}
.wardmap .dot{position:absolute;transform:translate(-50%,-50%);border-radius:50%;background:rgba(109,166,255,.85);box-shadow:0 0 0 1px rgba(255,255,255,.15)}
/* Ward highlight improvements */
.wardmap svg .spot{ transition: opacity .15s ease, fill .15s ease, stroke .15s ease }
/* When highlighting a regular spot (popular spots overlay): swap from yellow to green */
.wardmap svg .spot.hl:not(.longest){ fill: rgba(52,211,153,.14) !important; stroke:#34d399 !important; filter: drop-shadow(0 0 10px rgba(52,211,153,.7)); stroke-width:2.2 !important; opacity:1 !important }
/* When highlighting a longest-lived spot (turquoise -> red) */
.wardmap svg .spot.longest.hl{ fill: rgba(255,107,107,.12) !important; stroke:#ff6b6b !important; filter: drop-shadow(0 0 10px rgba(255,107,107,.75)); stroke-width:2.2 !important; opacity:1 !important }
.wardmap.highlighting svg .spot:not(.hl){ opacity:.25 !important }
.search{background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.12);border-radius:10px;color:var(--text);padding:8px 10px;outline:none}
.search::placeholder{color:var(--muted)}
.tabs{display:flex;gap:6px;margin:6px 0 8px}
.tab{padding:6px 10px;border:1px solid rgba(255,255,255,.12);background:linear-gradient(180deg,rgba(255,255,255,.07),rgba(255,255,255,.03));border-radius:10px;color:var(--text);cursor:pointer;font-size:12px;transition:all .15s ease}
.tab:hover{filter:brightness(1.08)}
.tab.active{outline:2px solid rgba(109,166,255,.5);background:linear-gradient(180deg,rgba(109,166,255,.2),rgba(109,166,255,.08));border-color:rgba(109,166,255,.45)}
.tabpane{margin-top:6px}
"@

  # ===== Final HTML =====
  $playersHtml = Html-PlayersTable
  $teamsHtml   = Html-TeamsTable
  $heroesHtml  = Html-HeroesTable

  # Build highlights block for monthly (and calendar)
  $highBlock = ""
  if ($Range -eq "30") {
    # Build from state with exclude applied
    $excludeSet = Load-ExcludeSet -RepoPath $RepoPath
    if (-not $excludeSet) { $excludeSet = [System.Collections.Generic.HashSet[string]]::new() }
    $exSet = $excludeSet
    $monthSubset = if ($cutoffUnix -gt 0) {
      @($state.matches | Where-Object {
        try { ([int64]$_.start_time -ge $cutoffUnix) -and -not ($exSet -and $exSet.Contains([string]$_.match_id)) } catch { $true }
      })
    } else {
      @($state.matches | Where-Object {
        try { -not ($exSet -and $exSet.Contains([string]$_.match_id)) } catch { $true }
      })
    }
    # Always attempt highlights; when empty, render fallbacks
    $high = $null
    if ($monthSubset.Count -gt 0) {
  $high = Build-Monthly-Highlights -MatchesSubset $monthSubset -HeroMap $heroMap -PlayerNamesMap $state.playerNames -PollRetries 5 -PollDelayMs 3000
    }

    # Daily parse kickoff: request parse for any pending from previous runs + newly seen unparsed in this month
    try {
      $paths = Get-ParseFiles -RepoPath $RepoPath
      $pendingPrev = Load-IdArray -path $paths.ready
      if ($pendingPrev -and $pendingPrev.Count -gt 0) {
        Write-Host ("Daily kickoff: requesting parse for {0} pending matches" -f $pendingPrev.Count) -ForegroundColor DarkCyan
        # Limit to avoid API abuse; request oldest 100 first
        $pendReq = @($pendingPrev | Select-Object -First 100)
        foreach($id in $pendReq){ Request-OpenDotaParse -matchId $id }
      }
      # New within this month window that are not parsed yet
  $needNow = New-Object System.Collections.Generic.List[long]
  foreach($m in $monthSubset){ $mid=[long]$m.match_id; if (-not (Is-OD-Parsed -matchId $mid)) { $needNow.Add($mid) | Out-Null } }
      if ($needNow.Count -gt 0) {
        Write-Host ("Daily kickoff: adding {0} newly-unparsed matches to ready_toParse and requesting parse" -f $needNow.Count) -ForegroundColor DarkCyan
  $readyPath = Update-ReadyToParse -newIds ($needNow.ToArray()) -RepoPath $RepoPath -MaxRequests 100
  $preExtraCommit += ,$readyPath
      }
    } catch { Write-Warning ("Daily parse kickoff skipped: " + $_.Exception.Message) }

    # Build calendar for the last 30 days (rolling weeks)
    $dayMap = @{}
    $minDt = $null; $maxDt = $null
    foreach($m in $monthSubset){
      try {
        $utc = [DateTime]([DateTimeOffset]::FromUnixTimeSeconds([int64]$m.start_time)).UtcDateTime
        $loc = [TimeZoneInfo]::ConvertTimeFromUtc($utc, $TZ)
        $d = $loc.Date
        $key = $d.ToString('yyyy-MM-dd')
        if (-not $dayMap[$key]) { $dayMap[$key] = New-Object System.Collections.Generic.List[object] }
        [void]$dayMap[$key].Add($m)
        if ($null -eq $minDt -or $d -lt $minDt) { $minDt = $d }
        if ($null -eq $maxDt -or $d -gt $maxDt) { $maxDt = $d }
      } catch {}
    }
    if ($null -eq $minDt) { $minDt = ([TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow,$TZ)).Date }
    if ($null -eq $maxDt) { $maxDt = $minDt }
    $startIdx = (([int]$minDt.DayOfWeek + 6) % 7)
    $gridStart = $minDt.AddDays(-$startIdx)
    $endIdx = 6 - (([int]$maxDt.DayOfWeek + 6) % 7)
    $gridEnd = $maxDt.AddDays($endIdx)
    $dowNames = @('Mon','Tue','Wed','Thu','Fri','Sat','Sun')
    $calCells = New-Object System.Text.StringBuilder
    $dcur = $gridStart
    while ($dcur -le $gridEnd) {
      $key = $dcur.ToString('yyyy-MM-dd')
  $dayMatches = if ($dayMap[$key]) { $dayMap[$key] } else { @() }
      $mm = @()
      $shown = 0
      foreach($mmc in $dayMatches){
        if ($shown -ge 6) { break }
        $mid = [string]$mmc.match_id
        $mm += "<a href='$(HtmlEscape (& $OD_MATCH_URL $mid))' target='_blank'>M$mid</a>"
        $shown++
      }
      $extra = $dayMatches.Count - $shown
      if ($extra -gt 0) { $mm += "<span class='badge'>+$extra</span>" }
      $dimClass = if (($dcur -lt $minDt) -or ($dcur -gt $maxDt)) { " style='opacity:.5'" } else { "" }
  $cell = "<div class='day'$dimClass><div class='date'>$($dcur.Day)</div><div class='matches'>$(($mm -join ' '))</div></div>"
      [void]$calCells.AppendLine($cell)
      $dcur = $dcur.AddDays(1)
    }

    function DuoHtml2($arr){ $o=@(); foreach($d in $arr){ $a=$heroMap[[int]$d.a]; $b=$heroMap[[int]$d.b]; $aN= if($a){$a.name}else{"#"+$d.a}; $bN= if($b){$b.name}else{"#"+$d.b}; $o += "<li><span>"+(HtmlEscape $aN)+" + "+(HtmlEscape $bN)+"</span><span class='badge'>WR: <strong>"+(FmtPct $d.winrate)+"</strong></span><span class='badge'>G: $($d.games)</span></li>" }; ($o -join "`n") }

  function RampHover($rp){
    if (-not $rp.matches -or $rp.matches.Count -eq 0) { return "" }
    $items = @()
    foreach($m in $rp.matches){
      $mid = [string]$m.match_id
      $url = & $OD_MATCH_URL $mid
      $cnt = [int]$m.count
      $label = if ($cnt -gt 1) { "x$cnt (same match)" } else { "x$cnt" }
      $items += "<a href='"+(HtmlEscape $url)+"' target='_blank'>M$mid</a><span class='badge'>${label}</span>"
    }
    return ("<div class='hovercard'><div class='title'>Rampage matches</div>" + ($items -join " ") + "</div>")
  }

  # NOTE: This All-time block was incorrectly nested inside the monthly (30-day) branch.
  # Keep it disabled here and reinsert a top-level version before final HTML.
  if ($false -and $Range -eq "All") {
    # Build All-time highlights (no calendar)
    $excludeSet = Load-ExcludeSet -RepoPath $RepoPath
    if (-not $excludeSet) { $excludeSet = [System.Collections.Generic.HashSet[string]]::new() }
    $exSet = $excludeSet
    $allSubset = @($state.matches | Where-Object {
      try { -not ($exSet -and $exSet.Contains([string]$_.match_id)) } catch { $true }
    })
    $highAll = $null
    if ($allSubset.Count -gt 0) {
      $highAll = Build-Monthly-Highlights -MatchesSubset $allSubset -HeroMap $heroMap -PlayerNamesMap $state.playerNames -PollRetries 0 -PollDelayMs 0
    }

    function DuoHtml2($arr){ $o=@(); foreach($d in $arr){ $a=$heroMap[[int]$d.a]; $b=$heroMap[[int]$d.b]; $aN= if($a){$a.name}else{"#"+$d.a}; $bN= if($b){$b.name}else{"#"+$d.b}; $o += "<li><span>"+(HtmlEscape $aN)+" + "+(HtmlEscape $bN)+"</span><span class='badge'>WR: <strong>"+(FmtPct $d.winrate)+"</strong></span><span class='badge'>G: $($d.games)</span></li>" }; ($o -join "`n") }

    function RampHoverAll($rp){
      if (-not $rp.matches -or $rp.matches.Count -eq 0) { return "" }
      $items = @()
      foreach($m in $rp.matches){ $mid = [string]$m.match_id; $url = & $OD_MATCH_URL $mid; $cnt=[int]$m.count; $label = if ($cnt -gt 1) { "x$cnt (same match)" } else { "x$cnt" }; $items += "<a href='"+(HtmlEscape $url)+"' target='_blank'>M$mid</a><span class='badge'>${label}</span>" }
      return ("<div class='hovercard'><div class='title'>Rampage matches</div>" + ($items -join " ") + "</div>")
    }

    $rampHtmlAll = if ($highAll -and $highAll.rampages -and $highAll.rampages.Count -gt 0) {
      ($highAll.rampages | ForEach-Object { $hover = RampHoverAll $_; "<li class='has-hover'><span><a href='"+(HtmlEscape $_.profile)+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge ramp-badge' tabindex='0'>x$($_.count)</span>$hover</li>" }) -join "`n"
    } else { "<li><span class='sub'>no games</span></li>" }
    $rosRAll = if ($highAll -and $highAll.roshan -and $highAll.roshan.PSObject.Properties.Name -contains 'Radiant') { [int]$highAll.roshan.Radiant } else { 0 }
    $rosDAll = if ($highAll -and $highAll.roshan -and $highAll.roshan.PSObject.Properties.Name -contains 'Dire') { [int]$highAll.roshan.Dire } else { 0 }
    $objWarnAll = if ($highAll -and $highAll.PSObject.Properties.Name -contains 'objectivesSeen' -and -not $highAll.objectivesSeen) { "<div class='sub'>no objective data in parsed matches</div>" } else { "" }
    $objNoneAll = if ( ($rosRAll + $rosDAll) -eq 0 ) { "<div class='sub'>no Roshan events in this period</div>" } else { "" }
    $rosTopRAll = ""; $rosTopDAll = ""
    if ($highAll -and $highAll.PSObject.Properties.Name -contains 'roshanTop' -and $highAll.roshanTop) {
      try { if ($highAll.roshanTop.Radiant -and $highAll.roshanTop.Radiant.Count -gt 0) { $rosTopRAll = ' ' + (($highAll.roshanTop.Radiant | ForEach-Object { $mid=[string]$_.match_id; $cnt=[int]$_.count; "<a class='badge' target='_blank' href='"+(HtmlEscape (& $OD_MATCH_URL $mid))+"'>M$mid</a><span class='badge'>x$cnt</span>" }) -join ' ') } } catch {}
      try { if ($highAll.roshanTop.Dire    -and $highAll.roshanTop.Dire.Count -gt 0)    { $rosTopDAll = ' ' + (($highAll.roshanTop.Dire    | ForEach-Object { $mid=[string]$_.match_id; $cnt=[int]$_.count; "<a class='badge' target='_blank' href='"+(HtmlEscape (& $OD_MATCH_URL $mid))+"'>M$mid</a><span class='badge'>x$cnt</span>" }) -join ' ') } } catch {}
    }

    # Ward map background image: use latest match across allSubset
    $mapConf = Load-MapConfig -RepoPath $RepoPath
    $mapBgUrl = $mapConf.default
    $mapScale = if ($mapConf.defaultScale) { [int]$mapConf.defaultScale } else { 127 }
    $mapInvertY = $false
    try {
      $latestUnixAll = 0
      foreach($m in $allSubset){ $u=[long]$m.start_time; if ($u -gt $latestUnixAll) { $latestUnixAll = $u } }
      if ($latestUnixAll -gt 0) {
        $maj = Get-MajorPatchForUnix -unix $latestUnixAll
        $asset = Resolve-MapAsset -MapConf $mapConf -MajorTag $maj
        $cand = $null; $scale = $null; $invY = $null
        if ($asset -is [string]) { $cand = [string]$asset }
        elseif ($asset -is [psobject]) { try { $cand = [string]$asset.src } catch {}; try { if ($asset.scale) { $scale = [int]$asset.scale } } catch {}; try { if ($null -ne $asset.invertY) { $invY = [bool]$asset.invertY } } catch {} }
        if ($scale) { $mapScale = $scale }
        if ($null -ne $invY) { $mapInvertY = $invY }
        if ($cand -and ($cand -notmatch '^https?://')) {
          $copied = Copy-AssetToDocs -RepoPath $RepoPath -RelPath $cand
          if ($copied) { $mapBgUrl = $cand -replace "\\","/"; $assetDocPath = Join-Path (Join-Path $RepoPath 'docs') $cand; $preExtraCommit += ,$assetDocPath }
        } elseif ($cand) { $mapBgUrl = $cand }
      }
    } catch {}

    $highBlock = @"
  <section class="card">
    <h2>Highlights (All time)</h2>
    <div class="grid3">
      <div>
        <h3>Rampages</h3>
        <ul class="simple">
$rampHtmlAll
        </ul>
      </div>
      <div>
        <h3>Roshan taken (by match)</h3>
        <ul class="simple">
$(
  if ($highAll -and $highAll.PSObject.Properties.Name -contains 'roshanByMatch' -and $highAll.roshanByMatch -and $highAll.roshanByMatch.Count -gt 0) {
    $list = @($highAll.roshanByMatch | Sort-Object @{e='total';Descending=$true}, @{e='match_id';Descending=$true} | Select-Object -First 10)
    ($list | ForEach-Object { $mid=[string]$_.match_id; $url = & $OD_MATCH_URL $mid; "<li><a class='badge' target='_blank' href='"+(HtmlEscape $url)+"'>M$mid</a><span class='badge'>Radiant x$($_.Radiant)</span><span class='badge'>Dire x$($_.Dire)</span><span class='badge'>Total: $($_.total)</span></li>" }) -join "`n"
  } else { "<li><span class='sub'>no Roshan events in this period</span></li>" }
)
        </ul>
  $objWarnAll
$(
  # Aegis snatches (explicit)
  if ($highAll -and $highAll.PSObject.Properties.Name -contains 'aegisSnatch' -and $highAll.aegisSnatch -and $highAll.aegisSnatch.Count -gt 0) {
    $items = ($highAll.aegisSnatch | ForEach-Object {
      $sec = [int]$_.time; $mm=[int]([math]::Floor($sec/60)); $ss=[int]($sec%60)
      $mid=[string]$_.match_id; $url = & $OD_MATCH_URL $mid
      $team = if ($_.team) { [string]$_.team } else { '' }
      $p = $_.player
      $nm = if ($p -and $p.name) { [string]$p.name } else { 'Unknown' }
      $hero = if ($p -and $p.hero) { [string]$p.hero } else { '' }
      $prof = if ($p -and $p.profile) { [string]$p.profile } else { '' }
      "<li><span>Aegis snatch:</span><span class='badge'>${team}</span><span>" + $( if($prof){ "<a href='"+(HtmlEscape $prof)+"' target='_blank'>"+(HtmlEscape $nm)+"</a>" } else { (HtmlEscape $nm) } ) + $( if ($hero){ " ("+(HtmlEscape $hero)+")" } else { "" } ) + "</span><a class='badge' target='_blank' href='"+(HtmlEscape $url)+"'>${mm}m ${ss}s</a></li>"
    }) -join "`n"
    "<div class='sub' style='margin-top:6px'>Aegis snatches</div><ul class='simple'>${items}</ul>"
  } else { '' }
)
$(
  # Tormentor by match (aggregate by match/team, hide player)
  if ($highAll -and $highAll.PSObject.Properties.Name -contains 'tormentor' -and $highAll.tormentor -and $highAll.tormentor.Count -gt 0) {
    $agg = @{}
    foreach($e in $highAll.tormentor){
      try {
        $mid = [string]$e.match_id; if (-not $mid) { continue }
        if (-not $agg.ContainsKey($mid)) { $agg[$mid] = @{ Radiant = 0; Dire = 0; total = 0 } }
        $add = 1; try { if ($e.PSObject.Properties.Name -contains 'count' -and $null -ne $e.count) { $add = [int]$e.count } } catch {}
        $team = if ($e.team) { [string]$e.team } else { '' }
        if ($team -eq 'Radiant') { $agg[$mid]['Radiant'] = [int]$agg[$mid]['Radiant'] + $add }
        elseif ($team -eq 'Dire') { $agg[$mid]['Dire'] = [int]$agg[$mid]['Dire'] + $add }
        $agg[$mid]['total'] = [int]$agg[$mid]['Radiant'] + [int]$agg[$mid]['Dire']
      } catch {}
    }
    $list = @(); foreach($k in $agg.Keys){ $list += [pscustomobject]@{ match_id=[int64]$k; Radiant=[int]$agg[$k]['Radiant']; Dire=[int]$agg[$k]['Dire']; total=[int]$agg[$k]['total'] } }
    if ($list.Count -gt 0) {
      $list = @($list | Sort-Object @{e='total';Descending=$true}, @{e='match_id';Descending=$true} | Select-Object -First 10)
      $items = ($list | ForEach-Object { $mid=[string]$_.match_id; $url = & $OD_MATCH_URL $mid; "<li><a class='badge' target='_blank' href='"+(HtmlEscape $url)+"'>M$mid</a><span class='badge'>Radiant x$($_.Radiant)</span><span class='badge'>Dire x$($_.Dire)</span><span class='badge'>Total: $($_.total)</span></li>" }) -join "`n"
      "<div class='sub' style='margin-top:6px'>Tormentor kills by match</div><ul class='simple'>${items}</ul>"
    } else { '' }
  } else { '' }
)
      </div>
      <div>
        <h3>Top single-match performances</h3>
        <ul class="simple">
$(
  $out=@()
  if ($highAll -and $highAll.topSingle) {
    if ($highAll.topSingle.PSObject.Properties.Name -contains 'gpm' -and $highAll.topSingle.gpm) {
      $p=$highAll.topSingle.gpm; $out += "<li><span><a href='"+(HtmlEscape $p.profile)+"' target='_blank'>"+(HtmlEscape $p.name)+"</a></span><span class='badge'>Highest GPM: <strong>$($p.value)</strong></span><a class='badge' target='_blank' href='"+(HtmlEscape (& $OD_MATCH_URL $p.match_id))+"'>Match</a></li>"
    }
    if ($highAll.topSingle.PSObject.Properties.Name -contains 'kills' -and $highAll.topSingle.kills) {
      $p=$highAll.topSingle.kills; $out += "<li><span><a href='"+(HtmlEscape $p.profile)+"' target='_blank'>"+(HtmlEscape $p.name)+"</a></span><span class='badge'>Highest Kills: <strong>$($p.value)</strong></span><a class='badge' target='_blank' href='"+(HtmlEscape (& $OD_MATCH_URL $p.match_id))+"'>Match</a></li>"
    }
    if ($highAll.topSingle.PSObject.Properties.Name -contains 'assists' -and $highAll.topSingle.assists) {
      $p=$highAll.topSingle.assists; $out += "<li><span><a href='"+(HtmlEscape $p.profile)+"' target='_blank'>"+(HtmlEscape $p.name)+"</a></span><span class='badge'>Highest Assists: <strong>$($p.value)</strong></span><a class='badge' target='_blank' href='"+(HtmlEscape (& $OD_MATCH_URL $p.match_id))+"'>Match</a></li>"
    }
    if ($highAll.topSingle.PSObject.Properties.Name -contains 'networth' -and $highAll.topSingle.networth) {
      $p=$highAll.topSingle.networth; $out += "<li><span><a href='"+(HtmlEscape $p.profile)+"' target='_blank'>"+(HtmlEscape $p.name)+"</a></span><span class='badge'>Highest Net Worth: <strong>$($p.value)</strong></span><a class='badge' target='_blank' href='"+(HtmlEscape (& $OD_MATCH_URL $p.match_id))+"'>Match</a></li>"
    }
  }
  if ($out.Count -eq 0) { "<li><span class='sub'>no games</span></li>" } else { ($out -join "`n") }
)
        </ul>
      </div>
    </div>
  <div class="grid3">
      <div>
        <h3>Most common teammates</h3>
        <ul class="simple">
$(if ($highAll -and $highAll.PSObject.Properties.Name -contains 'teammates' -and $highAll.teammates -and $highAll.teammates.Count -gt 0) { ($highAll.teammates | ForEach-Object { "<li><span><a href='$(HtmlEscape $_.profile1)' target='_blank'>$(HtmlEscape $_.name1)</a> + <a href='$(HtmlEscape $_.profile2)' target='_blank'>$(HtmlEscape $_.name2)</a></span><span class='badge'>x$($_.games)</span></li>" }) -join "`n" } else { "<li><span class='sub'>no games</span></li>" })
        </ul>
      </div>
      <div>
        <h3>Most courier kills</h3>
        <ul class="simple">
$(if ($highAll -and $highAll.PSObject.Properties.Name -contains 'courierTop' -and $highAll.courierTop -and $highAll.courierTop.Count -gt 0) { ($highAll.courierTop | ForEach-Object { "<li><span><a href='$(HtmlEscape $_.profile)' target='_blank'>$(HtmlEscape $_.name)</a></span><span class='badge'>x$($_.count)</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" })
        </ul>
      </div>
      <div>
        <h3>Most camps stacked</h3>
        <ul class="simple">
$(if ($highAll -and $highAll.PSObject.Properties.Name -contains 'stackTop' -and $highAll.stackTop -and $highAll.stackTop.Count -gt 0) { ($highAll.stackTop | ForEach-Object { "<li><span><a href='$(HtmlEscape $_.profile)' target='_blank'>$(HtmlEscape $_.name)</a></span><span class='badge'>x$($_.count)</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" })
        </ul>
      </div>
    </div>
    <div class="grid2">
      <div>
        <h3>Best Safe Lane Duos</h3>
        <ul class="simple">
$(if ($highAll -and $highAll.safeDuos) { DuoHtml2 $highAll.safeDuos } else { "<li><span class='sub'>no games</span></li>" })
        </ul>
      </div>
      <div>
        <h3>Best Off Lane Duos</h3>
        <ul class="simple">
$(if ($highAll -and $highAll.offDuos) { DuoHtml2 $highAll.offDuos } else { "<li><span class='sub'>no games</span></li>" })
        </ul>
      </div>
    </div>
    <div class="grid2">
      <div>
  <h3>3 longest matches</h3>
        <ul class="simple">
$(
  if ($highAll -and $highAll.durationLongest -and $highAll.durationLongest.Count -gt 0) {
    ($highAll.durationLongest | ForEach-Object {
      $sec=[int]$_.duration; $mm=[int]([math]::Floor($sec/60)); $ss=[int]($sec%60)
      $vs = (HtmlEscape ($_.radiant + ' vs ' + $_.dire))
      $win = if ($_.radiant_win) { 'Radiant' } else { 'Dire' }
      "<li><span><a target='_blank' href='"+(HtmlEscape (& $OD_MATCH_URL $_.match_id))+"'>${vs}</a></span><span class='badge'>${mm}m ${ss}s</span><span class='badge'>Winner: ${win}</span></li>"
    }) -join "`n"
  } else { "<li><span class='sub'>no games</span></li>" }
)
        </ul>
      </div>
      <div>
  <h3>3 shortest matches</h3>
        <ul class="simple">
$(
  if ($highAll -and $highAll.durationShortest -and $highAll.durationShortest.Count -gt 0) {
    ($highAll.durationShortest | ForEach-Object {
      $sec=[int]$_.duration; $mm=[int]([math]::Floor($sec/60)); $ss=[int]($sec%60)
      $vs = (HtmlEscape ($_.radiant + ' vs ' + $_.dire))
      $win = if ($_.radiant_win) { 'Radiant' } else { 'Dire' }
      "<li><span><a target='_blank' href='"+(HtmlEscape (& $OD_MATCH_URL $_.match_id))+"'>${vs}</a></span><span class='badge'>${mm}m ${ss}s</span><span class='badge'>Winner: ${win}</span></li>"
    }) -join "`n"
  } else { "<li><span class='sub'>no games</span></li>" }
)
        </ul>
      </div>
    </div>
  <h3>Ward Spots</h3>
  <div class="wardgrid">
    <div class="wardleft">
      <div class="sub" style="margin:-4px 0 8px">All tracked games | Number = count of observer placements at spot | Circle = observer vision radius (~1600u).</div>
      <div class="wardmap" style="background-image:url('$(HtmlEscape $mapBgUrl)')">
        <svg id="wardSvg" viewBox="0 0 100 100" preserveAspectRatio="none" width="100%" height="100%">
$(
  if ($highAll -and $highAll.wardEvents -and $highAll.wardEvents.Count -gt 0) {
  $obsPct = $null; $senPct = $null; $obsUnits=$null; $senUnits=$null; $cellUnits=$null; $spanX=$null
    try { $majTagTmp = Get-MajorPatchForUnix -unix $latestUnixAll; $assetTmp = Resolve-MapAsset -MapConf $mapConf -MajorTag $majTagTmp; if ($assetTmp -is [psobject]) { if ($assetTmp.obsRadiusUnits){$obsUnits=[double]$assetTmp.obsRadiusUnits}; if ($assetTmp.senRadiusUnits){$senUnits=[double]$assetTmp.senRadiusUnits}; if ($assetTmp.cellUnits){$cellUnits=[double]$assetTmp.cellUnits}; if ($null -ne $assetTmp.minX -and $null -ne $assetTmp.maxX){ $spanX=[double]$assetTmp.maxX - [double]$assetTmp.minX } } } catch {}
    if (-not $cellUnits) { try { if ($mapConf.defaultCellUnits){ $cellUnits = [double]$mapConf.defaultCellUnits } } catch {} }
    if (-not $obsUnits)  { try { if ($mapConf.defaultObsRadiusUnits){ $obsUnits = [double]$mapConf.defaultObsRadiusUnits } } catch {} }
    if (-not $senUnits)  { try { if ($mapConf.defaultSenRadiusUnits){ $senUnits = [double]$mapConf.defaultSenRadiusUnits } } catch {} }
    if (-not $spanX -or $spanX -le 0) { $spanX = [double]$mapScale }
    if ($obsUnits -and $cellUnits -and $spanX -gt 0) { $obsPct = [math]::Round(($obsUnits / ($cellUnits * $spanX)) * 100, 2) }
    if ($senUnits -and $cellUnits -and $spanX -gt 0) { $senPct = [math]::Round(($senUnits / ($cellUnits * $spanX)) * 100, 2) }
    if (-not $obsPct) { try { if ($assetTmp -is [psobject] -and $assetTmp.obsRadiusPct) { $obsPct = [double]$assetTmp.obsRadiusPct } } catch {} }
    if (-not $senPct) { try { if ($assetTmp -is [psobject] -and $assetTmp.senRadiusPct) { $senPct = [double]$assetTmp.senRadiusPct } } catch {} }
    if (-not $obsPct) { $obsPct = if ($mapConf.defaultObsRadiusPct) { [double]$mapConf.defaultObsRadiusPct } else { 10 } }
    if (-not $senPct) { $senPct = if ($mapConf.defaultSenRadiusPct) { [double]$mapConf.defaultSenRadiusPct } else { 6 } }
  $spotMap = @{}; foreach($e in $highAll.wardEvents){ try { $kx=[int]$e.x; $ky=[int]$e.y; $k = ("{0},{1}" -f $kx,$ky); if (-not $spotMap[$k]){ $spotMap[$k] = @{ obs=$false; sen=$false } }; if ($e.type -eq 'obs'){ $spotMap[$k].obs = $true } elseif ($e.type -eq 'sen'){ $spotMap[$k].sen = $true } } catch {} }
  $ranked = @($highAll.wardSpots); $rankLongest = @($highAll.wardLongest)
  $svgSpots = ($ranked | ForEach-Object { try { $kspot=[string]$_.spot; if (-not $kspot){ return '' }; $parts=$kspot.Split(','); $px=[double]$parts[0]; $py=[double]$parts[1]; $minX=$null; $minY=$null; $maxX=$null; $maxY=$null; try { if ($assetTmp -is [psobject]) { if ($assetTmp.minX -ne $null) { $minX=[double]$assetTmp.minX }; if ($assetTmp.minY -ne $null) { $minY=[double]$assetTmp.minY }; if ($assetTmp.maxX -ne $null) { $maxX=[double]$assetTmp.maxX }; if ($assetTmp.maxY -ne $null) { $maxY=[double]$assetTmp.maxY } } } catch {}; if ($minX -ne $null -and $minY -ne $null -and $maxX -ne $null -and $maxY -ne $null -and $maxX -gt $minX -and $maxY -gt $minY) { if ($px -lt $minX){$px=$minX}; if ($px -gt $maxX){$px=$maxX}; if ($py -lt $minY){$py=$minY}; if ($py -gt $maxY){$py=$maxY}; $cx=[math]::Round((($px - $minX)/($maxX - $minX))*100,2); $yy=(($py - $minY)/($maxY - $minY)); if ($mapInvertY){ $yy = 1.0 - $yy }; $cy=[math]::Round(($yy)*100,2) } else { $scale=[double]$mapScale; if ($px -lt 0){$px=0}; if ($px -gt $scale){$px=$scale}; if ($py -lt 0){$py=0}; if ($py -gt $scale){$py=$scale}; $cx=[math]::Round(($px/$scale)*100,2); $yy=($py/$scale); if ($mapInvertY){ $yy = 1.0 - $yy }; $cy=[math]::Round(($yy)*100,2) }; $info=$spotMap[$kspot]; $isObs=[bool]$info.obs; $svgOut=New-Object System.Text.StringBuilder; $elId = if ($_.spotId) { [string]$_.spotId } elseif ($info -and $info.id) { [string]$info.id } else { $null }; if ($isObs) { $rpct=$obsPct; $stroke='rgba(255,215,0,0.65)'; $fill='rgba(255,215,0,0.08)'; $idAttr= if ($elId) { (" id='"+$elId+"'") } else { '' }; $cnt= try { [int]$_.count } catch { 0 }; [void]$svgOut.Append("          <circle"+$idAttr+" class='spot' cx='${cx}%' cy='${cy}%' r='${rpct}' fill='${fill}' stroke='${stroke}' stroke-width='0.8' opacity='0.8'>`n            <title>Spot ${kspot} - Placements: ${cnt} - Period: All time</title>`n          </circle>`n          <circle cx='${cx}%' cy='${cy}%' r='1.0' fill='${stroke}' opacity='0.85' />") }; $svgOut.ToString() } catch { '' } }) -join "`n"
  $svgLongest = ($rankLongest | ForEach-Object { try { $kspot=[string]$_.spot; if (-not $kspot){ return '' }; $parts=$kspot.Split(','); $px=[double]$parts[0]; $py=[double]$parts[1]; $minX=$null; $minY=$null; $maxX=$null; $maxY=$null; try { if ($assetTmp -is [psobject]) { if ($assetTmp.minX -ne $null) { $minX=[double]$assetTmp.minX }; if ($assetTmp.minY -ne $null) { $minY=[double]$assetTmp.minY }; if ($assetTmp.maxX -ne $null) { $maxX=[double]$assetTmp.maxX }; if ($assetTmp.maxY -ne $null) { $maxY=[double]$assetTmp.maxY } } } catch {}; if ($minX -ne $null -and $minY -ne $null -and $maxX -ne $null -and $maxY -ne $null -and $maxX -gt $minX -and $maxY -gt $minY) { if ($px -lt $minX){$px=$minX}; if ($px -gt $maxX){$px=$maxX}; if ($py -lt $minY){$py=$minY}; if ($py -gt $maxY){$py=$maxY}; $cx=[math]::Round((($px - $minX)/($maxX - $minX))*100,2); $yy=(($py - $minY)/($maxY - $minY)); if ($mapInvertY){ $yy = 1.0 - $yy }; $cy=[math]::Round(($yy)*100,2) } else { $scale=[double]$mapScale; if ($px -lt 0){$px=0}; if ($px -gt $scale){$px=$scale}; if ($py -lt 0){$py=0}; if ($py -gt $scale){$py=$scale}; $cx=[math]::Round(($px/$scale)*100,2); $yy=($py/$scale); if ($mapInvertY){ $yy = 1.0 - $yy }; $cy=[math]::Round(($yy)*100,2) }; $info=$spotMap[$kspot]; $isObs=[bool]$info.obs; $svgOut=New-Object System.Text.StringBuilder; $elId = if ($_.spotId) { [string]$_.spotId } elseif ($info -and $info.id) { [string]$info.id } else { $null }; if ($isObs) { $rpct=$obsPct; $stroke='rgba(86,227,150,0.55)'; $fill='rgba(86,227,150,0.06)'; $idAttr= if ($elId) { (" id='"+$elId+"'") } else { '' }; $mx= try { [int]$_.maxSeconds } catch { $null }; $mm = if ($mx -ne $null) { [int]([math]::Floor($mx/60)) } else { 0 }; $ss = if ($mx -ne $null) { [int]($mx % 60) } else { 0 }; $pc = try { [int]$_.count } catch { 0 }; [void]$svgOut.Append("          <circle"+$idAttr+" class='spot longest' cx='${cx}%' cy='${cy}%' r='${rpct}' fill='${fill}' stroke='${stroke}' stroke-width='0.6' opacity='0.7'>`n            <title>Spot ${kspot} - Longest life: ${mm}m ${ss}s - Placements: ${pc}</title>`n          </circle>`n          <circle cx='${cx}%' cy='${cy}%' r='0.8' fill='${stroke}' opacity='0.75' />") }; $svgOut.ToString() } catch { '' } }) -join "`n"

  "<g id='ov-spots'>${svgSpots}</g><g id='ov-longest' style='display:none'>${svgLongest}</g>"
  } else { "          <!-- no wards -->" }
)
        </svg>
      </div>
      <div style="display:flex;align-items:center;gap:10px;margin-top:10px">
        <label style="font-size:13px;color:var(--muted)"><input id="toggleSpots" type="checkbox" checked style="vertical-align:middle;margin-right:6px">Show ward overlay</label>
      </div>
      <script>
      (function(){
        const svg = document.getElementById('wardSvg');
        if (!svg) return;
        const wrap = svg.closest('.wardmap');
        const active = new Set();
        function setHighlight(id, on){
          if (!id) return;
          const els = svg.querySelectorAll('#'+CSS.escape(id));
          if (els && els.length){ els.forEach(el=> el.classList.toggle('hl', !!on)); }
          if (on) { active.add(id); } else { active.delete(id); }
          if (wrap){ wrap.classList.toggle('highlighting', active.size>0); }
        }
        window.__wardHover = { setHighlight };
      })();
      </script>
    </div>
    <div class="wardright">
      <div class="tabs">
        <button class="tab active" data-tab="spots">Most popular spots</button>
        <button class="tab" data-tab="players">Players</button>
  <button class="tab" data-tab="longest">Longest-lived spots (min 3 placements)</button>
      </div>
      <div id="tab-spots" class="tabpane active">
        <ul id="spotList" class="simple" style="margin-top:8px">
$(if ($highAll -and $highAll.wardSpots) { ($highAll.wardSpots | ForEach-Object { $sid = if ($_.spotId){$_.spotId}else{""}; "<li data-spot='${sid}'><span>Spot $($_.spot)</span><span class='badge'>x$($_.count)</span></li>" }) -join "`n" } else { "<li><span class='sub'>no games</span></li>" })
        </ul>
      </div>
      <div id="tab-players" class="tabpane" style="display:none">
      <div class="grid3">
        <div>
          <h4>Most placed</h4>
          <ul class="simple">
$(if ($highAll -and $highAll.wardPlayers -and $highAll.wardPlayers.mostPlaced) { ($highAll.wardPlayers.mostPlaced | ForEach-Object { "<li><span><a href='"+(HtmlEscape $_.profile)+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>x$($_.count)</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" })
          </ul>
        </div>
        <div>
          <h4>Most dewards</h4>
          <ul class="simple">
$(if ($highAll -and $highAll.wardPlayers -and $highAll.wardPlayers.mostDewards) { ($highAll.wardPlayers.mostDewards | ForEach-Object { "<li><span><a href='"+(HtmlEscape $_.profile)+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>x$($_.count)</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" })
          </ul>
        </div>
        <div>
          <h4>Most successful (avg. lifetime)</h4>
          <ul class="simple">
$(if ($highAll -and $highAll.wardPlayers -and $highAll.wardPlayers.longestAvg) { ($highAll.wardPlayers.longestAvg | ForEach-Object { $sec=[int]$_.avgSeconds; $mm=[int]([math]::Floor($sec/60)); $ss=[int]($sec%60); "<li><span><a href='"+(HtmlEscape $_.profile)+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>${mm}m ${ss}s avg</span><span class='badge'>n=$($_.samples)</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" })
          </ul>
        </div>
      </div>
    </div>
      <div id="tab-longest" class="tabpane" style="display:none">
      $( if ($highAll -and $highAll.wardLongest -and $highAll.wardLongest.Count -gt 0) { $items = ($highAll.wardLongest | ForEach-Object { $sid = if ($_.spotId){$_.spotId}else{""}; $sec=[int]$_.maxSeconds; $mm=[int]([math]::Floor($sec/60)); $ss=[int]($sec%60); $pc = try { [int]$_.count } catch { 0 }; "<li data-spot='${sid}'><span>Spot $($_.spot)</span><span class='badge'>${mm}m ${ss}s</span><span class='badge'>x${pc}</span></li>" }) -join "`n"; "<ul id='longestList' class='simple' style='opacity:.85'>${items}</ul>" } else { '<ul class="simple"><li><span class="sub">no data</span></li></ul>' } )
      </div>
      <script>
      (function(){
        const root = document.currentScript.closest('.wardright');
        const tabs = Array.from(root.querySelectorAll('.tabs .tab'));
        const svg = document.getElementById('wardSvg');
        const gSpots = svg ? svg.querySelector('#ov-spots') : null;
        const gLongest = svg ? svg.querySelector('#ov-longest') : null;
        function show(name){
          root.querySelectorAll('.tabpane').forEach(p=>p.style.display='none');
          root.querySelector('#tab-'+name).style.display='';
          tabs.forEach(b=>b.classList.toggle('active', b.getAttribute('data-tab')===name));
          if (gSpots && gLongest){ if (name==='longest'){ gSpots.style.display='none'; gLongest.style.display=''; } else { gSpots.style.display=''; gLongest.style.display='none'; } }
        }
        tabs.forEach(b=>b.addEventListener('click', ()=> show(b.getAttribute('data-tab'))));
        function wireHover(ul){ const hover = window.__wardHover; if (!hover || !ul) return; ul.addEventListener('mouseover', e => { const li = e.target.closest('li[data-spot]'); if (!li) return; hover.setHighlight(li.getAttribute('data-spot'), true); }); ul.addEventListener('mouseout', e => { const li = e.target.closest('li[data-spot]'); if (!li) return; hover.setHighlight(li.getAttribute('data-spot'), false); }); }
        wireHover(document.getElementById('spotList'));
        wireHover(document.getElementById('longestList'));
        const toggle = document.getElementById('toggleSpots'); if (toggle && svg){ toggle.addEventListener('change', ()=>{ svg.style.display = toggle.checked ? '' : 'none'; }); }
      })();
      </script>
    </div>
  </div>
"@
    # Append Awards (All time)
    $awAll = if ($highAll -and ($highAll.PSObject.Properties.Name -contains 'awards')) { $highAll.awards } else { $null }
    if ($awAll) {
      $spaceAll = if ($awAll.spaceCreator -and $awAll.spaceCreator.Count -gt 0) { ($awAll.spaceCreator | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>x"+([int]$_.val)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $ogAll = if ($awAll.objectiveGamer -and $awAll.objectiveGamer.Count -gt 0) { ($awAll.objectiveGamer | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>"+(FmtPct $_.share)+"</span><span class='badge'>Rosh: x"+([int]$_.rosh)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $earlyAll = if ($awAll.earlyFarmer -and $awAll.earlyFarmer.Count -gt 0) { ($awAll.earlyFarmer | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>"+([int]$_.value)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $clutchAll = if ($awAll.clutchKing -and $awAll.clutchKing.Count -gt 0) { ($awAll.clutchKing | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>"+(FmtPct $_.ratio)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $courierAll = if ($awAll.courierAssassin -and $awAll.courierAssassin.Count -gt 0) { ($awAll.courierAssassin | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>x"+([int]$_.val)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $visionAll = if ($awAll.visionMvp -and $awAll.visionMvp.Count -gt 0) { ($awAll.visionMvp | ForEach-Object { $v=[double]$_.val; $vs=([string]([math]::Round($v,1))); "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>"+$vs+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $stackAll = if ($awAll.stackMaster -and $awAll.stackMaster.Count -gt 0) { ($awAll.stackMaster | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>x"+([int]$_.val)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $smokeAll = if ($awAll.smokeCommander -and $awAll.smokeCommander.Count -gt 0) { ($awAll.smokeCommander | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>x"+([int]$_.val)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $runesAll = if ($awAll.runeController -and $awAll.runeController.Count -gt 0) { ($awAll.runeController | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>x"+([int]$_.val)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $aegisAll = if ($awAll.aegisSnatcher -and $awAll.aegisSnatcher.Count -gt 0) { ($awAll.aegisSnatcher | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>x"+([int]$_.val)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }

      $highBlock += @"
  <section class="card">
    <h2>Awards (All time)</h2>
    <div class="grid3">
      <div>
        <h3>Space Creator – most deaths in wins</h3>
        <ul class="simple">
$spaceAll
        </ul>
      </div>
      <div>
        <h3>Objective Gamer – tower share + rosh</h3>
        <ul class="simple">
$ogAll
        </ul>
      </div>
      <div>
        <h3>Early Farmer – net worth @10:00</h3>
        <ul class="simple">
$earlyAll
        </ul>
      </div>
    </div>
    <div class="grid3" style="margin-top:8px">
      <div>
        <h3>Clutch King – KP in last 10%</h3>
        <ul class="simple">
$clutchAll
        </ul>
      </div>
      <div>
        <h3>Courier Assassin – most couriers</h3>
        <ul class="simple">
$courierAll
        </ul>
      </div>
      <div>
        <h3>Vision MVP – warding/dewarding</h3>
        <ul class="simple">
$visionAll
        </ul>
      </div>
    </div>
    <div class="grid3" style="margin-top:8px">
      <div>
        <h3>Stack Master – most stacks</h3>
        <ul class="simple">
$stackAll
        </ul>
      </div>
      <div>
        <h3>Smoke Commander – most smokes</h3>
        <ul class="simple">
$smokeAll
        </ul>
      </div>
      <div>
        <h3>Rune Controller – runes taken</h3>
        <ul class="simple">
$runesAll
        </ul>
      </div>
    </div>
    <div class="grid3" style="margin-top:8px">
      <div>
        <h3>Aegis Snatcher – most snatches</h3>
        <ul class="simple">
$aegisAll
        </ul>
      </div>
    </div>
  </section>
"@
    }
  }
  $rampHtml = if ($high -and $high.rampages -and $high.rampages.Count -gt 0) {
      ($high.rampages | ForEach-Object {
        $hover = RampHover $_
    "<li class='has-hover'><span><a href='"+(HtmlEscape $_.profile)+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge ramp-badge' tabindex='0'>x$($_.count)</span>$hover</li>"
      }) -join "`n"
    } else { "<li><span class='sub'>no games</span></li>" }
  $rosR = if ($high -and $high.roshan -and $high.roshan.PSObject.Properties.Name -contains 'Radiant') { [int]$high.roshan.Radiant } else { 0 }
  $rosD = if ($high -and $high.roshan -and $high.roshan.PSObject.Properties.Name -contains 'Dire') { [int]$high.roshan.Dire } else { 0 }
  $objWarn = if ($high -and $high.PSObject.Properties.Name -contains 'objectivesSeen' -and -not $high.objectivesSeen) { "<div class='sub'>no objective data in parsed matches</div>" } else { "" }
  $objNone = if ( ($rosR + $rosD) -eq 0 ) { "<div class='sub'>no Roshan events in this period</div>" } else { "" }
  $rosTopR = ""; $rosTopD = ""
  if ($high -and $high.PSObject.Properties.Name -contains 'roshanTop' -and $high.roshanTop) {
    try {
      if ($high.roshanTop.Radiant -and $high.roshanTop.Radiant.Count -gt 0) {
        $rosTopR = ' ' + (($high.roshanTop.Radiant | ForEach-Object { $mid=[string]$_.match_id; $cnt=[int]$_.count; "<a class='badge' target='_blank' href='"+(HtmlEscape (& $OD_MATCH_URL $mid))+"'>M$mid</a><span class='badge'>x$cnt</span>" }) -join ' ')
      }
    } catch {}
    try {
      if ($high.roshanTop.Dire -and $high.roshanTop.Dire.Count -gt 0) {
        $rosTopD = ' ' + (($high.roshanTop.Dire | ForEach-Object { $mid=[string]$_.match_id; $cnt=[int]$_.count; "<a class='badge' target='_blank' href='"+(HtmlEscape (& $OD_MATCH_URL $mid))+"'>M$mid</a><span class='badge'>x$cnt</span>" }) -join ' ')
      }
    } catch {}
  }

    $calHeader = ($dowNames | ForEach-Object { "<div>$_</div>" }) -join ""

    # Resolve ward map background image based on latest match's patch within this month window
    $mapConf = Load-MapConfig -RepoPath $RepoPath
    $mapBgUrl = $mapConf.default
    $mapScale = if ($mapConf.defaultScale) { [int]$mapConf.defaultScale } else { 127 }
    $mapInvertY = $false
    try {
      $latestUnix = 0
      foreach($m in $monthSubset){ $u=[long]$m.start_time; if ($u -gt $latestUnix) { $latestUnix = $u } }
      if ($latestUnix -gt 0) {
        $maj = Get-MajorPatchForUnix -unix $latestUnix
        # Resolve even if maj is null to allow fallback to 'current'
        $asset = Resolve-MapAsset -MapConf $mapConf -MajorTag $maj
          # asset can be plain string (URL/path) or object { src, scale, invertY }
          $cand = $null; $scale = $null; $invY = $null
          if ($asset -is [string]) { $cand = [string]$asset }
          elseif ($asset -is [psobject]) {
            try { $cand = [string]$asset.src } catch {}
            try { if ($asset.scale) { $scale = [int]$asset.scale } } catch {}
            try { if ($null -ne $asset.invertY) { $invY = [bool]$asset.invertY } } catch {}
          }
          if ($scale) { $mapScale = $scale }
          if ($null -ne $invY) { $mapInvertY = $invY }
          if ($VerboseLog) { Write-Host ("Map resolve: major='$maj' cand='${cand}' scale=$mapScale invertY=$mapInvertY") -ForegroundColor DarkGray }
          if ($cand -and ($cand -notmatch '^https?://')) {
            # Treat as repo-relative asset (e.g., img/7_39/..). Copy into docs and reference relatively from report.
            $copied = Copy-AssetToDocs -RepoPath $RepoPath -RelPath $cand
            if ($copied) {
              $mapBgUrl = $cand -replace "\\","/"
              # Track for commit
              $assetDocPath = Join-Path (Join-Path $RepoPath 'docs') $cand
              $preExtraCommit += ,$assetDocPath
              if ($VerboseLog) { Write-Host ("Map copy OK -> docs path: '$assetDocPath' web: '$mapBgUrl'") -ForegroundColor DarkGray }
            } else {
              if ($VerboseLog) { Write-Warning ("Map copy failed for '$cand' - keeping default background") }
            }
          } elseif ($cand) {
            $mapBgUrl = $cand
            if ($VerboseLog) { Write-Host ("Map resolve: using remote URL '$mapBgUrl'") -ForegroundColor DarkGray }
          }
      }
    } catch { }

  $highBlock = @"
  <section class="card">
    <h2>Calendar (last 30 days)</h2>
    <div class="cal">
      <div class="grid7 dow">$calHeader</div>
      <div class="grid7">$($calCells.ToString())</div>
    </div>
  </section>

  <section class="card">
    <h2>Highlights (Monthly)</h2>
    <div class="grid3">
      <div>
        <h3>Rampages</h3>
        <ul class="simple">
$rampHtml
        </ul>
      </div>
      <div>
        <h3>Roshan taken</h3>
        <ul class="simple">
          <li><span>Radiant</span><span class='badge'>x$rosR</span>$rosTopR</li>
          <li><span>Dire</span><span class='badge'>x$rosD</span>$rosTopD</li>
        </ul>
  $objWarn
  $objNone
$(
  if ($high -and $high.PSObject.Properties.Name -contains 'aegisSnatch' -and $high.aegisSnatch -and $high.aegisSnatch.Count -gt 0) {
    $items = ($high.aegisSnatch | ForEach-Object {
      $sec=[int]$_.time; $mm=[int]([math]::Floor($sec/60)); $ss=[int]($sec%60)
      $mid=[string]$_.match_id; $url = & $OD_MATCH_URL $mid
      $team = if ($_.team) { [string]$_.team } else { '' }
      $p = $_.player
      $nm = if ($p -and $p.name) { [string]$p.name } else { 'Unknown' }
      $hero = if ($p -and $p.hero) { [string]$p.hero } else { '' }
      $prof = if ($p -and $p.profile) { [string]$p.profile } else { '' }
      "<li><span>Aegis snatch:</span><span class='badge'>${team}</span><span>" + $( if($prof){ "<a href='"+(HtmlEscape $prof)+"' target='_blank'>"+(HtmlEscape $nm)+"</a>" } else { (HtmlEscape $nm) } ) + $( if ($hero){ " ("+(HtmlEscape $hero)+")" } else { "" } ) + "</span><a class='badge' target='_blank' href='"+(HtmlEscape $url)+"'>${mm}m ${ss}s</a></li>"
    }) -join "`n"
    "<div class='sub' style='margin-top:6px'>Aegis snatches</div><ul class='simple'>${items}</ul>"
  } else { '' }
)
$(
  # Tormentor by match (aggregate by match/team, hide player)
  if ($high -and $high.PSObject.Properties.Name -contains 'tormentor' -and $high.tormentor -and $high.tormentor.Count -gt 0) {
    $agg = @{}
    foreach($e in $high.tormentor){
      try {
        $mid = [string]$e.match_id; if (-not $mid) { continue }
        if (-not $agg.ContainsKey($mid)) { $agg[$mid] = @{ Radiant = 0; Dire = 0; total = 0 } }
        $add = 1; try { if ($e.PSObject.Properties.Name -contains 'count' -and $null -ne $e.count) { $add = [int]$e.count } } catch {}
        $team = if ($e.team) { [string]$e.team } else { '' }
        if ($team -eq 'Radiant') { $agg[$mid]['Radiant'] = [int]$agg[$mid]['Radiant'] + $add }
        elseif ($team -eq 'Dire') { $agg[$mid]['Dire'] = [int]$agg[$mid]['Dire'] + $add }
        $agg[$mid]['total'] = [int]$agg[$mid]['Radiant'] + [int]$agg[$mid]['Dire']
      } catch {}
    }
    $list = @(); foreach($k in $agg.Keys){ $list += [pscustomobject]@{ match_id=[int64]$k; Radiant=[int]$agg[$k]['Radiant']; Dire=[int]$agg[$k]['Dire']; total=[int]$agg[$k]['total'] } }
    if ($list.Count -gt 0) {
      $list = @($list | Sort-Object @{e='total';Descending=$true}, @{e='match_id';Descending=$true} | Select-Object -First 10)
      $items = ($list | ForEach-Object { $mid=[string]$_.match_id; $url = & $OD_MATCH_URL $mid; "<li><a class='badge' target='_blank' href='"+(HtmlEscape $url)+"'>M$mid</a><span class='badge'>Radiant x$($_.Radiant)</span><span class='badge'>Dire x$($_.Dire)</span><span class='badge'>Total: $($_.total)</span></li>" }) -join "`n"
      "<div class='sub' style='margin-top:6px'>Tormentor kills by match</div><ul class='simple'>${items}</ul>"
    } else { '' }
  } else { '' }
)
      </div>
      <div>
        <h3>Top single-match performances</h3>
        <ul class="simple">
$(
  $out=@()
  if ($high -and $high.topSingle) {
    if ($high.topSingle.PSObject.Properties.Name -contains 'gpm' -and $high.topSingle.gpm) {
      $p=$high.topSingle.gpm; $out += "<li><span><a href='"+(HtmlEscape $p.profile)+"' target='_blank'>"+(HtmlEscape $p.name)+"</a></span><span class='badge'>Highest GPM: <strong>$($p.value)</strong></span><a class='badge' target='_blank' href='"+(HtmlEscape (& $OD_MATCH_URL $p.match_id))+"'>Match</a></li>"
    }
    if ($high.topSingle.PSObject.Properties.Name -contains 'kills' -and $high.topSingle.kills) {
      $p=$high.topSingle.kills; $out += "<li><span><a href='"+(HtmlEscape $p.profile)+"' target='_blank'>"+(HtmlEscape $p.name)+"</a></span><span class='badge'>Highest Kills: <strong>$($p.value)</strong></span><a class='badge' target='_blank' href='"+(HtmlEscape (& $OD_MATCH_URL $p.match_id))+"'>Match</a></li>"
    }
    if ($high.topSingle.PSObject.Properties.Name -contains 'assists' -and $high.topSingle.assists) {
      $p=$high.topSingle.assists; $out += "<li><span><a href='"+(HtmlEscape $p.profile)+"' target='_blank'>"+(HtmlEscape $p.name)+"</a></span><span class='badge'>Highest Assists: <strong>$($p.value)</strong></span><a class='badge' target='_blank' href='"+(HtmlEscape (& $OD_MATCH_URL $p.match_id))+"'>Match</a></li>"
    }
    if ($high.topSingle.PSObject.Properties.Name -contains 'networth' -and $high.topSingle.networth) {
      $p=$high.topSingle.networth; $out += "<li><span><a href='"+(HtmlEscape $p.profile)+"' target='_blank'>"+(HtmlEscape $p.name)+"</a></span><span class='badge'>Highest Net Worth: <strong>$($p.value)</strong></span><a class='badge' target='_blank' href='"+(HtmlEscape (& $OD_MATCH_URL $p.match_id))+"'>Match</a></li>"
    }
  }
  if ($out.Count -eq 0) { "<li><span class='sub'>no games</span></li>" } else { ($out -join "`n") }
)
        </ul>
      </div>
    </div>
    <div class="grid2">
      <div>
        <h3>Best Safe Lane Duos</h3>
        <ul class="simple">
$(if ($high -and $high.safeDuos) { DuoHtml2 $high.safeDuos } else { "<li><span class='sub'>no games</span></li>" })
        </ul>
      </div>
      <div>
        <h3>Best Off Lane Duos</h3>
        <ul class="simple">
$(if ($high -and $high.offDuos) { DuoHtml2 $high.offDuos } else { "<li><span class='sub'>no games</span></li>" })
        </ul>
      </div>
    </div>
    <div class="grid2">
      <div>
  <h3>3 longest matches</h3>
        <ul class="simple">
$(
  if ($high -and $high.durationLongest -and $high.durationLongest.Count -gt 0) {
    ($high.durationLongest | ForEach-Object {
      $sec=[int]$_.duration; $mm=[int]([math]::Floor($sec/60)); $ss=[int]($sec%60)
      $vs = (HtmlEscape ($_.radiant + ' vs ' + $_.dire))
      $win = if ($_.radiant_win) { 'Radiant' } else { 'Dire' }
      "<li><span><a target='_blank' href='"+(HtmlEscape (& $OD_MATCH_URL $_.match_id))+"'>${vs}</a></span><span class='badge'>${mm}m ${ss}s</span><span class='badge'>Winner: ${win}</span></li>"
    }) -join "`n"
  } else { "<li><span class='sub'>no games</span></li>" }
)
        </ul>
      </div>
      <div>
  <h3>3 shortest matches</h3>
        <ul class="simple">
$(
  if ($high -and $high.durationShortest -and $high.durationShortest.Count -gt 0) {
    ($high.durationShortest | ForEach-Object {
      $sec=[int]$_.duration; $mm=[int]([math]::Floor($sec/60)); $ss=[int]($sec%60)
      $vs = (HtmlEscape ($_.radiant + ' vs ' + $_.dire))
      $win = if ($_.radiant_win) { 'Radiant' } else { 'Dire' }
      "<li><span><a target='_blank' href='"+(HtmlEscape (& $OD_MATCH_URL $_.match_id))+"'>${vs}</a></span><span class='badge'>${mm}m ${ss}s</span><span class='badge'>Winner: ${win}</span></li>"
    }) -join "`n"
  } else { "<li><span class='sub'>no games</span></li>" }
)
        </ul>
      </div>
    </div>
  <h3>Ward Spots</h3>
  <div class="wardgrid">
    <div class="wardleft">
      <div class="sub" style="margin:-4px 0 8px">
      $(
        # Human-readable timeframe label from the calendar min/max days
        try {
          if ($minDt -and $maxDt) { "Period: $($minDt.ToString('dd.MM.')) - $($maxDt.ToString('dd.MM.')) | Number = count of observer placements at spot | Circle = observer vision radius (~1600u)." }
          else { "Period: last 30 days | Number = count of observer placements at spot | Circle = observer vision radius (~1600u)." }
        } catch { "Period: last 30 days | Number = count of observer placements at spot | Circle = observer vision radius (~1600u)." }
      )
      </div>
      <div class="wardmap" style="background-image:url('$(HtmlEscape $mapBgUrl)')">
        <svg id="wardSvg" viewBox="0 0 100 100" preserveAspectRatio="none" width="100%" height="100%">
$(
  if ($high -and $high.wardEvents -and $high.wardEvents.Count -gt 0) {
  # Determine radii (percent of map width). Prefer unit-based conversion; only use percents as fallback.
  $obsPct = $null; $senPct = $null
  $obsUnits = $null; $senUnits = $null; $cellUnits = $null
  $spanX = $null
    try {
      $majTagTmp = $null
      if ($latestUnix -gt 0) { $majTagTmp = Get-MajorPatchForUnix -unix $latestUnix }
      $assetTmp = Resolve-MapAsset -MapConf $mapConf -MajorTag $majTagTmp
      if ($assetTmp -is [psobject]) {
        # Intentionally do NOT read obsRadiusPct/senRadiusPct here to avoid overriding unit-based sizing
        if ($assetTmp.obsRadiusUnits) { $obsUnits = [double]$assetTmp.obsRadiusUnits }
        if ($assetTmp.senRadiusUnits) { $senUnits = [double]$assetTmp.senRadiusUnits }
        if ($assetTmp.cellUnits) { $cellUnits = [double]$assetTmp.cellUnits }
  if ($null -ne $assetTmp.minX -and $null -ne $assetTmp.maxX) { $spanX = [double]$assetTmp.maxX - [double]$assetTmp.minX }
      }
    } catch {}
    if (-not $cellUnits) { try { if ($mapConf.defaultCellUnits){ $cellUnits = [double]$mapConf.defaultCellUnits } } catch {} }
    if (-not $obsUnits)  { try { if ($mapConf.defaultObsRadiusUnits){ $obsUnits = [double]$mapConf.defaultObsRadiusUnits } } catch {} }
    if (-not $senUnits)  { try { if ($mapConf.defaultSenRadiusUnits){ $senUnits = [double]$mapConf.defaultSenRadiusUnits } } catch {} }
    if (-not $spanX -or $spanX -le 0) { $spanX = [double]$mapScale }
    # Compute from units when possible (preferred)
    if ($obsUnits -and $cellUnits -and $spanX -gt 0) { $obsPct = [math]::Round(($obsUnits / ($cellUnits * $spanX)) * 100, 2) }
    if ($senUnits -and $cellUnits -and $spanX -gt 0) { $senPct = [math]::Round(($senUnits / ($cellUnits * $spanX)) * 100, 2) }
    # Fallback percents: first from per-patch percent if defined, else global defaults, else sane constants
    if (-not $obsPct) {
      try { if ($assetTmp -is [psobject] -and $assetTmp.obsRadiusPct) { $obsPct = [double]$assetTmp.obsRadiusPct } } catch {}
    }
    if (-not $senPct) {
      try { if ($assetTmp -is [psobject] -and $assetTmp.senRadiusPct) { $senPct = [double]$assetTmp.senRadiusPct } } catch {}
    }
    if (-not $obsPct) { $obsPct = if ($mapConf.defaultObsRadiusPct) { [double]$mapConf.defaultObsRadiusPct } else { 10 } }
    if (-not $senPct) { $senPct = if ($mapConf.defaultSenRadiusPct) { [double]$mapConf.defaultSenRadiusPct } else { 6 } }
    # Deduplicate ward spots by map cell (x,y) so each location is drawn once; prefer marking as observer if any obs placed here
  $spotMap = @{}
  foreach($e in $high.wardEvents){ try { $kx = [int]$e.x; $ky=[int]$e.y; $k = ("{0},{1}" -f $kx,$ky); if (-not $spotMap[$k]){ $spotMap[$k] = @{ obs=$false; sen=$false } }; if ($e.type -eq 'obs'){ $spotMap[$k].obs = $true } elseif ($e.type -eq 'sen'){ $spotMap[$k].sen = $true } } catch {} }
  # Prepare two overlays: (1) Most popular spots by placements, (2) Longest-lived spots
  $ranked = @($high.wardSpots)
  $rankLongest = @($high.wardLongest)
  $svgSpots = ($ranked | ForEach-Object {
      try {
        $kspot = [string]$_.spot
        if (-not $kspot) { return '' }
        $parts = $kspot.Split(','); $px=[double]$parts[0]; $py=[double]$parts[1]
        # Normalize using per-patch min/max bounds when available, else fall back to scale
        $minX=$null; $minY=$null; $maxX=$null; $maxY=$null
        try {
          if ($assetTmp -is [psobject]) {
            if ($assetTmp.minX -ne $null) { $minX = [double]$assetTmp.minX }
            if ($assetTmp.minY -ne $null) { $minY = [double]$assetTmp.minY }
            if ($assetTmp.maxX -ne $null) { $maxX = [double]$assetTmp.maxX }
            if ($assetTmp.maxY -ne $null) { $maxY = [double]$assetTmp.maxY }
          }
        } catch {}
        if ($minX -ne $null -and $minY -ne $null -and $maxX -ne $null -and $maxY -ne $null -and $maxX -gt $minX -and $maxY -gt $minY) {
          # Clamp to bounds
          if ($px -lt $minX){$px=$minX}; if ($px -gt $maxX){$px=$maxX}
          if ($py -lt $minY){$py=$minY}; if ($py -gt $maxY){$py=$maxY}
          $cx = [math]::Round((($px - $minX)/($maxX - $minX))*100, 2)
          $yy = (($py - $minY)/($maxY - $minY)); if ($mapInvertY) { $yy = 1.0 - $yy }
          $cy = [math]::Round(($yy)*100,2)
        } else {
          $scale = [double]$mapScale
          if ($px -lt 0){$px=0}; if ($px -gt $scale){$px=$scale}
          if ($py -lt 0){$py=0}; if ($py -gt $scale){$py=$scale}
          $cx = [math]::Round(($px/$scale)*100,2)
          $yy = ($py/$scale); if ($mapInvertY) { $yy = 1.0 - $yy }
          $cy = [math]::Round(($yy)*100,2)
        }
  $info = $spotMap[$kspot]
  $isObs = [bool]$info.obs
        $svgOut = New-Object System.Text.StringBuilder
        # Prefer stable id from highlights list for list->map hover; fallback to any computed id
        $elId = if ($_.spotId) { [string]$_.spotId } elseif ($info -and $info.id) { [string]$info.id } else { $null }
  if ($isObs) {
          $rpct = $obsPct; $stroke='rgba(255,215,0,0.65)'; $fill='rgba(255,215,0,0.08)'
          $idAttr = if ($elId) { (" id='"+$elId+"'") } else { '' }
          $cnt = try { [int]$_.count } catch { 0 }
          $tf = try { if ($minDt -and $maxDt) { "$($minDt.ToString('dd.MM.'))-$($maxDt.ToString('dd.MM.'))" } else { "last 30 days" } } catch { "last 30 days" }
          [void]$svgOut.Append("          <circle"+$idAttr+" class='spot' cx='${cx}%' cy='${cy}%' r='${rpct}' fill='${fill}' stroke='${stroke}' stroke-width='0.8' opacity='0.8'>`n            <title>Spot ${kspot} - Placements: ${cnt} - Period: ${tf}</title>`n          </circle>`n          <circle cx='${cx}%' cy='${cy}%' r='1.0' fill='${stroke}' opacity='0.85' />")
        }
  # Skip sentry-only spots to reduce clutter; list and hover link focus on observers
        $svgOut.ToString()
      } catch { '' }
    }) -join "`n"

  $svgLongest = ($rankLongest | ForEach-Object {
      try {
        $kspot = [string]$_.spot
        if (-not $kspot) { return '' }
        $parts = $kspot.Split(','); $px=[double]$parts[0]; $py=[double]$parts[1]
        $minX=$null; $minY=$null; $maxX=$null; $maxY=$null
        try {
          if ($assetTmp -is [psobject]) {
            if ($assetTmp.minX -ne $null) { $minX = [double]$assetTmp.minX }
            if ($assetTmp.minY -ne $null) { $minY = [double]$assetTmp.minY }
            if ($assetTmp.maxX -ne $null) { $maxX = [double]$assetTmp.maxX }
            if ($assetTmp.maxY -ne $null) { $maxY = [double]$assetTmp.maxY }
          }
        } catch {}
        if ($minX -ne $null -and $minY -ne $null -and $maxX -ne $null -and $maxY -ne $null -and $maxX -gt $minX -and $maxY -gt $minY) {
          if ($px -lt $minX){$px=$minX}; if ($px -gt $maxX){$px=$maxX}
          if ($py -lt $minY){$py=$minY}; if ($py -gt $maxY){$py=$maxY}
          $cx = [math]::Round((($px - $minX)/($maxX - $minX))*100, 2)
          $yy = (($py - $minY)/($maxY - $minY)); if ($mapInvertY) { $yy = 1.0 - $yy }
          $cy = [math]::Round(($yy)*100,2)
        } else {
          $scale = [double]$mapScale
          if ($px -lt 0){$px=0}; if ($px -gt $scale){$px=$scale}
          if ($py -lt 0){$py=0}; if ($py -gt $scale){$py=$scale}
          $cx = [math]::Round(($px/$scale)*100,2)
          $yy = ($py/$scale); if ($mapInvertY) { $yy = 1.0 - $yy }
          $cy = [math]::Round(($yy)*100,2)
        }
        $info = $spotMap[$kspot]
        $isObs = [bool]$info.obs
        $svgOut = New-Object System.Text.StringBuilder
        $elId = if ($_.spotId) { [string]$_.spotId } elseif ($info -and $info.id) { [string]$info.id } else { $null }
        if ($isObs) {
          $rpct = $obsPct; $stroke='rgba(86,227,150,0.55)'; $fill='rgba(86,227,150,0.06)'
          $idAttr = if ($elId) { (" id='"+$elId+"'") } else { '' }
          $mx = try { [int]$_.maxSeconds } catch { $null }
          $mm = if ($mx -ne $null) { [int]([math]::Floor($mx/60)) } else { 0 }
          $ss = if ($mx -ne $null) { [int]($mx % 60) } else { 0 }
          $pc = try { [int]$_.count } catch { 0 }
          [void]$svgOut.Append("          <circle"+$idAttr+" class='spot longest' cx='${cx}%' cy='${cy}%' r='${rpct}' fill='${fill}' stroke='${stroke}' stroke-width='0.6' opacity='0.7'>`n            <title>Spot ${kspot} - Longest life: ${mm}m ${ss}s - Placements: ${pc}</title>`n          </circle>`n          <circle cx='${cx}%' cy='${cy}%' r='0.8' fill='${stroke}' opacity='0.75' />")
        }
        $svgOut.ToString()
      } catch { '' }
    }) -join "`n"

  "<g id='ov-spots'>${svgSpots}</g><g id='ov-longest' style='display:none'>${svgLongest}</g>"
  } else { "          <!-- no wards -->" }
)
        </svg>
      </div>
      <div style="display:flex;align-items:center;gap:10px;margin-top:10px">
        <label style="font-size:13px;color:var(--muted)"><input id="toggleSpots" type="checkbox" checked style="vertical-align:middle;margin-right:6px">Show ward overlay</label>
      </div>
      <script>
      (function(){
        const svg = document.getElementById('wardSvg');
        if (!svg) return;
        const wrap = svg.closest('.wardmap');
        const active = new Set();
        function setHighlight(id, on){
          if (!id) return;
          const els = svg.querySelectorAll('#'+CSS.escape(id));
          if (els && els.length){ els.forEach(el=> el.classList.toggle('hl', !!on)); }
          if (on) { active.add(id); } else { active.delete(id); }
          if (wrap){ wrap.classList.toggle('highlighting', active.size>0); }
        }
        window.__wardHover = { setHighlight };
      })();
      </script>
    </div>
    <div class="wardright">
      <div class="tabs">
        <button class="tab active" data-tab="spots">Most popular spots</button>
        <button class="tab" data-tab="players">Players</button>
  <button class="tab" data-tab="longest">Longest-lived spots (min 3 placements)</button>
      </div>
      <div id="tab-spots" class="tabpane active">
        <ul id="spotList" class="simple" style="margin-top:8px">
$(if ($high -and $high.wardSpots) { ($high.wardSpots | ForEach-Object { $sid = if ($_.spotId){$_.spotId}else{""}; "<li data-spot='${sid}'><span>Spot $($_.spot)</span><span class='badge'>x$($_.count)</span></li>" }) -join "`n" } else { "<li><span class='sub'>no games</span></li>" })
        </ul>
      </div>
      <div id="tab-players" class="tabpane" style="display:none">
      <div class="grid3">
        <div>
          <h4>Most placed</h4>
          <ul class="simple">
$(if ($high -and $high.wardPlayers -and $high.wardPlayers.mostPlaced) { ($high.wardPlayers.mostPlaced | ForEach-Object { "<li><span><a href='"+(HtmlEscape $_.profile)+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>x$($_.count)</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" })
          </ul>
        </div>
        <div>
          <h4>Most dewards</h4>
          <ul class="simple">
$(if ($high -and $high.wardPlayers -and $high.wardPlayers.mostDewards) { ($high.wardPlayers.mostDewards | ForEach-Object { "<li><span><a href='"+(HtmlEscape $_.profile)+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>x$($_.count)</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" })
          </ul>
        </div>
        <div>
          <h4>Most successful (avg. lifetime)</h4>
          <ul class="simple">
$(if ($high -and $high.wardPlayers -and $high.wardPlayers.longestAvg) {
  ($high.wardPlayers.longestAvg | ForEach-Object {
    $sec = [int]$_.avgSeconds; $mm = [int]([math]::Floor($sec/60)); $ss = [int]($sec % 60)
    "<li><span><a href='"+(HtmlEscape $_.profile)+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>${mm}m ${ss}s avg</span><span class='badge'>n=$($_.samples)</span></li>"
  }) -join "`n"
} else { "<li><span class='sub'>no data</span></li>" })
          </ul>
        </div>
      </div>
    </div>
      <div id="tab-longest" class="tabpane" style="display:none">
      $(
        if ($high -and $high.wardLongest -and $high.wardLongest.Count -gt 0) {
          $items = ($high.wardLongest | ForEach-Object {
            $sid = if ($_.spotId){$_.spotId}else{""}
            $sec = [int]$_.maxSeconds
            $mm = [int]([math]::Floor($sec/60))
            $ss = [int]($sec % 60)
            $pc = try { [int]$_.count } catch { 0 }
            "<li data-spot='${sid}'><span>Spot $($_.spot)</span><span class='badge'>${mm}m ${ss}s</span><span class='badge'>x${pc}</span></li>"
          }) -join "`n"
          "<ul id='longestList' class='simple' style='opacity:.85'>${items}</ul>"
        } else { '<ul class="simple"><li><span class="sub">no data</span></li></ul>' }
      )
      </div>
      <script>
      (function(){
        const root = document.currentScript.closest('.wardright');
        const tabs = Array.from(root.querySelectorAll('.tabs .tab'));
        const svg = document.getElementById('wardSvg');
        const gSpots = svg ? svg.querySelector('#ov-spots') : null;
        const gLongest = svg ? svg.querySelector('#ov-longest') : null;
        function show(name){
          root.querySelectorAll('.tabpane').forEach(p=>p.style.display='none');
          root.querySelector('#tab-'+name).style.display='';
          tabs.forEach(b=>b.classList.toggle('active', b.getAttribute('data-tab')===name));
          if (gSpots && gLongest){
            if (name==='longest'){ gSpots.style.display='none'; gLongest.style.display=''; }
            else { gSpots.style.display=''; gLongest.style.display='none'; }
          }
        }
        tabs.forEach(b=>b.addEventListener('click', ()=> show(b.getAttribute('data-tab'))));
        // wire hover for visible lists
        function wireHover(ul){
          const hover = window.__wardHover; if (!hover) return;
          if (!ul) return;
          ul.addEventListener('mouseover', e => {
            const li = e.target.closest('li[data-spot]'); if (!li) return;
            hover.setHighlight(li.getAttribute('data-spot'), true);
          });
          ul.addEventListener('mouseout', e => {
            const li = e.target.closest('li[data-spot]'); if (!li) return;
            hover.setHighlight(li.getAttribute('data-spot'), false);
          });
        }
  wireHover(document.getElementById('spotList'));
  wireHover(document.getElementById('longestList'));
  const toggle = document.getElementById('toggleSpots');
        if (toggle && svg){
          toggle.addEventListener('change', ()=>{ svg.style.display = toggle.checked ? '' : 'none'; });
        }
      })();
      </script>
    </div>
  </div>
"@
    # Append Awards (Monthly)
    $aw = if ($high -and ($high.PSObject.Properties.Name -contains 'awards')) { $high.awards } else { $null }
    if ($aw) {
      $space = if ($aw.spaceCreator -and $aw.spaceCreator.Count -gt 0) { ($aw.spaceCreator | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>x"+([int]$_.val)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $og = if ($aw.objectiveGamer -and $aw.objectiveGamer.Count -gt 0) { ($aw.objectiveGamer | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>"+(FmtPct $_.share)+"</span><span class='badge'>Rosh: x"+([int]$_.rosh)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $early = if ($aw.earlyFarmer -and $aw.earlyFarmer.Count -gt 0) { ($aw.earlyFarmer | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>"+([int]$_.value)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $clutch = if ($aw.clutchKing -and $aw.clutchKing.Count -gt 0) { ($aw.clutchKing | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>"+(FmtPct $_.ratio)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $courier = if ($aw.courierAssassin -and $aw.courierAssassin.Count -gt 0) { ($aw.courierAssassin | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>x"+([int]$_.val)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $vision = if ($aw.visionMvp -and $aw.visionMvp.Count -gt 0) { ($aw.visionMvp | ForEach-Object { $v=[double]$_.val; $vs=([string]([math]::Round($v,1))); "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>"+$vs+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $stack = if ($aw.stackMaster -and $aw.stackMaster.Count -gt 0) { ($aw.stackMaster | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>x"+([int]$_.val)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $smoke = if ($aw.smokeCommander -and $aw.smokeCommander.Count -gt 0) { ($aw.smokeCommander | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>x"+([int]$_.val)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $runes = if ($aw.runeController -and $aw.runeController.Count -gt 0) { ($aw.runeController | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>x"+([int]$_.val)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $aegis = if ($aw.aegisSnatcher -and $aw.aegisSnatcher.Count -gt 0) { ($aw.aegisSnatcher | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>x"+([int]$_.val)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }

      $highBlock += @"
  <section class="card">
    <h2>Awards (Monthly)</h2>
    <div class="grid3">
      <div>
        <h3>Space Creator – most deaths in wins</h3>
        <ul class="simple">
$space
        </ul>
      </div>
      <div>
        <h3>Objective Gamer – tower share + rosh</h3>
        <ul class="simple">
$og
        </ul>
      </div>
      <div>
        <h3>Early Farmer – net worth @10:00</h3>
        <ul class="simple">
$early
        </ul>
      </div>
    </div>
    <div class="grid3" style="margin-top:8px">
      <div>
        <h3>Clutch King – KP in last 10%</h3>
        <ul class="simple">
$clutch
        </ul>
      </div>
      <div>
        <h3>Courier Assassin – most couriers</h3>
        <ul class="simple">
$courier
        </ul>
      </div>
      <div>
        <h3>Vision MVP – warding/dewarding</h3>
        <ul class="simple">
$vision
        </ul>
      </div>
    </div>
    <div class="grid3" style="margin-top:8px">
      <div>
        <h3>Stack Master – most stacks</h3>
        <ul class="simple">
$stack
        </ul>
      </div>
      <div>
        <h3>Smoke Commander – most smokes</h3>
        <ul class="simple">
$smoke
        </ul>
      </div>
      <div>
        <h3>Rune Controller – runes taken</h3>
        <ul class="simple">
$runes
        </ul>
      </div>
    </div>
    <div class="grid3" style="margin-top:8px">
      <div>
        <h3>Aegis Snatcher – most snatches</h3>
        <ul class="simple">
$aegis
        </ul>
      </div>
    </div>
  </section>
"@
    }
  }

  # Top-level All-time highlights (moved out of monthly branch)
  if ($Range -eq "All") {
    # Build All-time highlights (no calendar)
    $excludeSet = Load-ExcludeSet -RepoPath $RepoPath
    if (-not $excludeSet) { $excludeSet = [System.Collections.Generic.HashSet[string]]::new() }
    $exSet = $excludeSet
    $allSubset = @($state.matches | Where-Object {
      try { -not ($exSet -and $exSet.Contains([string]$_.match_id)) } catch { $true }
    })
    $highAll = $null
    if ($allSubset.Count -gt 0) {
      $highAll = Build-Monthly-Highlights -MatchesSubset $allSubset -HeroMap $heroMap -PlayerNamesMap $state.playerNames -PollRetries 0 -PollDelayMs 0
    }

    function DuoHtml2($arr){ $o=@(); foreach($d in $arr){ $a=$heroMap[[int]$d.a]; $b=$heroMap[[int]$d.b]; $aN= if($a){$a.name}else{"#"+$d.a}; $bN= if($b){$b.name}else{"#"+$d.b}; $o += "<li><span>"+(HtmlEscape $aN)+" + "+(HtmlEscape $bN)+"</span><span class='badge'>WR: <strong>"+(FmtPct $d.winrate)+"</strong></span><span class='badge'>G: $($d.games)</span></li>" }; ($o -join "`n") }

    function RampHoverAll($rp){
      if (-not $rp.matches -or $rp.matches.Count -eq 0) { return "" }
      $items = @()
      foreach($m in $rp.matches){ $mid = [string]$m.match_id; $url = & $OD_MATCH_URL $mid; $cnt=[int]$m.count; $label = if ($cnt -gt 1) { "x$cnt (same match)" } else { "x$cnt" }; $items += "<a href='"+(HtmlEscape $url)+"' target='_blank'>M$mid</a><span class='badge'>${label}</span>" }
      return ("<div class='hovercard'><div class='title'>Rampage matches</div>" + ($items -join " ") + "</div>")
    }

    $rampHtmlAll = if ($highAll -and $highAll.rampages -and $highAll.rampages.Count -gt 0) {
      ($highAll.rampages | ForEach-Object { $hover = RampHoverAll $_; "<li class='has-hover'><span><a href='"+(HtmlEscape $_.profile)+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge ramp-badge' tabindex='0'>x$($_.count)</span>$hover</li>" }) -join "`n"
    } else { "<li><span class='sub'>no games</span></li>" }
    $rosRAll = if ($highAll -and $highAll.roshan -and $highAll.roshan.PSObject.Properties.Name -contains 'Radiant') { [int]$highAll.roshan.Radiant } else { 0 }
    $rosDAll = if ($highAll -and $highAll.roshan -and $highAll.roshan.PSObject.Properties.Name -contains 'Dire') { [int]$highAll.roshan.Dire } else { 0 }
    $objWarnAll = if ($highAll -and $highAll.PSObject.Properties.Name -contains 'objectivesSeen' -and -not $highAll.objectivesSeen) { "<div class='sub'>no objective data in parsed matches</div>" } else { "" }
    $objNoneAll = if ( ($rosRAll + $rosDAll) -eq 0 ) { "<div class='sub'>no Roshan events in this period</div>" } else { "" }
    $rosTopRAll = ""; $rosTopDAll = ""
    if ($highAll -and $highAll.PSObject.Properties.Name -contains 'roshanTop' -and $highAll.roshanTop) {
      try { if ($highAll.roshanTop.Radiant -and $highAll.roshanTop.Radiant.Count -gt 0) { $rosTopRAll = ' ' + (($highAll.roshanTop.Radiant | ForEach-Object { $mid=[string]$_.match_id; $cnt=[int]$_.count; "<a class='badge' target='_blank' href='"+(HtmlEscape (& $OD_MATCH_URL $mid))+"'>M$mid</a><span class='badge'>x$cnt</span>" }) -join ' ') } } catch {}
      try { if ($highAll.roshanTop.Dire    -and $highAll.roshanTop.Dire.Count -gt 0)    { $rosTopDAll = ' ' + (($highAll.roshanTop.Dire    | ForEach-Object { $mid=[string]$_.match_id; $cnt=[int]$_.count; "<a class='badge' target='_blank' href='"+(HtmlEscape (& $OD_MATCH_URL $mid))+"'>M$mid</a><span class='badge'>x$cnt</span>" }) -join ' ') } } catch {}
    }

    # Ward map background image: use latest match across allSubset
    $mapConf = Load-MapConfig -RepoPath $RepoPath
    $mapBgUrl = $mapConf.default
    $mapScale = if ($mapConf.defaultScale) { [int]$mapConf.defaultScale } else { 127 }
    $mapInvertY = $false
    try {
      $latestUnixAll = 0
      foreach($m in $allSubset){ $u=[long]$m.start_time; if ($u -gt $latestUnixAll) { $latestUnixAll = $u } }
      if ($latestUnixAll -gt 0) {
        $maj = Get-MajorPatchForUnix -unix $latestUnixAll
        $asset = Resolve-MapAsset -MapConf $mapConf -MajorTag $maj
        $cand = $null; $scale = $null; $invY = $null
        if ($asset -is [string]) { $cand = [string]$asset }
        elseif ($asset -is [psobject]) { try { $cand = [string]$asset.src } catch {}; try { if ($asset.scale) { $scale = [int]$asset.scale } } catch {}; try { if ($null -ne $asset.invertY) { $invY = [bool]$asset.invertY } } catch {} }
        if ($scale) { $mapScale = $scale }
        if ($null -ne $invY) { $mapInvertY = $invY }
        if ($cand -and ($cand -notmatch '^https?://')) {
          $copied = Copy-AssetToDocs -RepoPath $RepoPath -RelPath $cand
          if ($copied) { $mapBgUrl = $cand -replace "\\","/"; $assetDocPath = Join-Path (Join-Path $RepoPath 'docs') $cand; $preExtraCommit += ,$assetDocPath }
        } elseif ($cand) { $mapBgUrl = $cand }
      }
    } catch {}

    $highBlock = @"
  <section class="card">
    <h2>Highlights (All time)</h2>
    <div class="grid3">
      <div>
        <h3>Rampages</h3>
        <ul class="simple">
$rampHtmlAll
        </ul>
      </div>
      <div>
        <h3>Roshan taken (by match)</h3>
        <ul class="simple">
$(
  if ($highAll -and $highAll.PSObject.Properties.Name -contains 'roshanByMatch' -and $highAll.roshanByMatch -and $highAll.roshanByMatch.Count -gt 0) {
    $list = @($highAll.roshanByMatch | Sort-Object @{e='total';Descending=$true}, @{e='match_id';Descending=$true} | Select-Object -First 10)
    ($list | ForEach-Object { $mid=[string]$_.match_id; $url = & $OD_MATCH_URL $mid; "<li><a class='badge' target='_blank' href='"+(HtmlEscape $url)+"'>M$mid</a><span class='badge'>Radiant x$($_.Radiant)</span><span class='badge'>Dire x$($_.Dire)</span><span class='badge'>Total: $($_.total)</span></li>" }) -join "`n"
  } else { "<li><span class='sub'>no Roshan events in this period</span></li>" }
)
        </ul>
  $objWarnAll
$(
  # Aegis snatches (explicit)
  if ($highAll -and $highAll.PSObject.Properties.Name -contains 'aegisSnatch' -and $highAll.aegisSnatch -and $highAll.aegisSnatch.Count -gt 0) {
    $items = ($highAll.aegisSnatch | ForEach-Object {
      $sec = [int]$_.time; $mm=[int]([math]::Floor($sec/60)); $ss=[int]($sec%60)
      $mid=[string]$_.match_id; $url = & $OD_MATCH_URL $mid
      $team = if ($_.team) { [string]$_.team } else { '' }
      $p = $_.player
      $nm = if ($p -and $p.name) { [string]$p.name } else { 'Unknown' }
      $hero = if ($p -and $p.hero) { [string]$p.hero } else { '' }
      $prof = if ($p -and $p.profile) { [string]$p.profile } else { '' }
      "<li><span>Aegis snatch:</span><span class='badge'>${team}</span><span>" + $( if($prof){ "<a href='"+(HtmlEscape $prof)+"' target='_blank'>"+(HtmlEscape $nm)+"</a>" } else { (HtmlEscape $nm) } ) + $( if ($hero){ " ("+(HtmlEscape $hero)+")" } else { "" } ) + "</span><a class='badge' target='_blank' href='"+(HtmlEscape $url)+"'>${mm}m ${ss}s</a></li>"
    }) -join "`n"
    "<div class='sub' style='margin-top:6px'>Aegis snatches</div><ul class='simple'>${items}</ul>"
  } else { '' }
)
$(
  # Tormentor by match (aggregate by match/team, hide player)
  if ($highAll -and $highAll.PSObject.Properties.Name -contains 'tormentor' -and $highAll.tormentor -and $highAll.tormentor.Count -gt 0) {
    $agg = @{}
    foreach($e in $highAll.tormentor){
      try {
        $mid = [string]$e.match_id; if (-not $mid) { continue }
        if (-not $agg.ContainsKey($mid)) { $agg[$mid] = @{ Radiant = 0; Dire = 0; total = 0 } }
        $add = 1; try { if ($e.PSObject.Properties.Name -contains 'count' -and $null -ne $e.count) { $add = [int]$e.count } } catch {}
        $team = if ($e.team) { [string]$e.team } else { '' }
        if ($team -eq 'Radiant') { $agg[$mid]['Radiant'] = [int]$agg[$mid]['Radiant'] + $add }
        elseif ($team -eq 'Dire') { $agg[$mid]['Dire'] = [int]$agg[$mid]['Dire'] + $add }
        $agg[$mid]['total'] = [int]$agg[$mid]['Radiant'] + [int]$agg[$mid]['Dire']
      } catch {}
    }
    $list = @(); foreach($k in $agg.Keys){ $list += [pscustomobject]@{ match_id=[int64]$k; Radiant=[int]$agg[$k]['Radiant']; Dire=[int]$agg[$k]['Dire']; total=[int]$agg[$k]['total'] } }
    if ($list.Count -gt 0) {
      $list = @($list | Sort-Object @{e='total';Descending=$true}, @{e='match_id';Descending=$true} | Select-Object -First 10)
      $items = ($list | ForEach-Object { $mid=[string]$_.match_id; $url = & $OD_MATCH_URL $mid; "<li><a class='badge' target='_blank' href='"+(HtmlEscape $url)+"'>M$mid</a><span class='badge'>Radiant x$($_.Radiant)</span><span class='badge'>Dire x$($_.Dire)</span><span class='badge'>Total: $($_.total)</span></li>" }) -join "`n"
      "<div class='sub' style='margin-top:6px'>Tormentor kills by match</div><ul class='simple'>${items}</ul>"
    } else { '' }
  } else { '' }
)
      </div>
      <div>
        <h3>Top single-match performances</h3>
        <ul class="simple">
$(
  $out=@()
  if ($highAll -and $highAll.topSingle) {
    if ($highAll.topSingle.PSObject.Properties.Name -contains 'gpm' -and $highAll.topSingle.gpm) {
      $p=$highAll.topSingle.gpm; $out += "<li><span><a href='"+(HtmlEscape $p.profile)+"' target='_blank'>"+(HtmlEscape $p.name)+"</a></span><span class='badge'>Highest GPM: <strong>$($p.value)</strong></span><a class='badge' target='_blank' href='"+(HtmlEscape (& $OD_MATCH_URL $p.match_id))+"'>Match</a></li>"
    }
    if ($highAll.topSingle.PSObject.Properties.Name -contains 'kills' -and $highAll.topSingle.kills) {
      $p=$highAll.topSingle.kills; $out += "<li><span><a href='"+(HtmlEscape $p.profile)+"' target='_blank'>"+(HtmlEscape $p.name)+"</a></span><span class='badge'>Highest Kills: <strong>$($p.value)</strong></span><a class='badge' target='_blank' href='"+(HtmlEscape (& $OD_MATCH_URL $p.match_id))+"'>Match</a></li>"
    }
    if ($highAll.topSingle.PSObject.Properties.Name -contains 'assists' -and $highAll.topSingle.assists) {
      $p=$highAll.topSingle.assists; $out += "<li><span><a href='"+(HtmlEscape $p.profile)+"' target='_blank'>"+(HtmlEscape $p.name)+"</a></span><span class='badge'>Highest Assists: <strong>$($p.value)</strong></span><a class='badge' target='_blank' href='"+(HtmlEscape (& $OD_MATCH_URL $p.match_id))+"'>Match</a></li>"
    }
    if ($highAll.topSingle.PSObject.Properties.Name -contains 'networth' -and $highAll.topSingle.networth) {
      $p=$highAll.topSingle.networth; $out += "<li><span><a href='"+(HtmlEscape $p.profile)+"' target='_blank'>"+(HtmlEscape $p.name)+"</a></span><span class='badge'>Highest Net Worth: <strong>$($p.value)</strong></span><a class='badge' target='_blank' href='"+(HtmlEscape (& $OD_MATCH_URL $p.match_id))+"'>Match</a></li>"
    }
  }
  if ($out.Count -eq 0) { "<li><span class='sub'>no games</span></li>" } else { ($out -join "`n") }
)
        </ul>
      </div>
    </div>
  <div class="grid3">
      <div>
        <h3>Most common teammates</h3>
        <ul class="simple">
$(if ($highAll -and $highAll.PSObject.Properties.Name -contains 'teammates' -and $highAll.teammates -and $highAll.teammates.Count -gt 0) { ($highAll.teammates | ForEach-Object { "<li><span><a href='$(HtmlEscape $_.profile1)' target='_blank'>$(HtmlEscape $_.name1)</a> + <a href='$(HtmlEscape $_.profile2)' target='_blank'>$(HtmlEscape $_.name2)</a></span><span class='badge'>x$($_.games)</span></li>" }) -join "`n" } else { "<li><span class='sub'>no games</span></li>" })
        </ul>
      </div>
      <div>
        <h3>Most courier kills</h3>
        <ul class="simple">
$(if ($highAll -and $highAll.PSObject.Properties.Name -contains 'courierTop' -and $highAll.courierTop -and $highAll.courierTop.Count -gt 0) { ($highAll.courierTop | ForEach-Object { "<li><span><a href='$(HtmlEscape $_.profile)' target='_blank'>$(HtmlEscape $_.name)</a></span><span class='badge'>x$($_.count)</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" })
        </ul>
      </div>
      <div>
        <h3>Most camps stacked</h3>
        <ul class="simple">
$(if ($highAll -and $highAll.PSObject.Properties.Name -contains 'stackTop' -and $highAll.stackTop -and $highAll.stackTop.Count -gt 0) { ($highAll.stackTop | ForEach-Object { "<li><span><a href='$(HtmlEscape $_.profile)' target='_blank'>$(HtmlEscape $_.name)</a></span><span class='badge'>x$($_.count)</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" })
        </ul>
      </div>
    </div>
    <div class="grid2">
      <div>
        <h3>Best Safe Lane Duos</h3>
        <ul class="simple">
$(if ($highAll -and $highAll.safeDuos) { DuoHtml2 $highAll.safeDuos } else { "<li><span class='sub'>no games</span></li>" })
        </ul>
      </div>
      <div>
        <h3>Best Off Lane Duos</h3>
        <ul class="simple">
$(if ($highAll -and $highAll.offDuos) { DuoHtml2 $highAll.offDuos } else { "<li><span class='sub'>no games</span></li>" })
        </ul>
      </div>
    </div>
    <div class="grid2">
      <div>
  <h3>3 longest matches</h3>
        <ul class="simple">
$(
  if ($highAll -and $highAll.durationLongest -and $highAll.durationLongest.Count -gt 0) {
    ($highAll.durationLongest | ForEach-Object {
      $sec=[int]$_.duration; $mm=[int]([math]::Floor($sec/60)); $ss=[int]($sec%60)
      $vs = (HtmlEscape ($_.radiant + ' vs ' + $_.dire))
      $win = if ($_.radiant_win) { 'Radiant' } else { 'Dire' }
      "<li><span><a target='_blank' href='"+(HtmlEscape (& $OD_MATCH_URL $_.match_id))+"'>${vs}</a></span><span class='badge'>${mm}m ${ss}s</span><span class='badge'>Winner: ${win}</span></li>"
    }) -join "`n"
  } else { "<li><span class='sub'>no games</span></li>" }
)
        </ul>
      </div>
      <div>
  <h3>3 shortest matches</h3>
        <ul class="simple">
$(
  if ($highAll -and $highAll.durationShortest -and $highAll.durationShortest.Count -gt 0) {
    ($highAll.durationShortest | ForEach-Object {
      $sec=[int]$_.duration; $mm=[int]([math]::Floor($sec/60)); $ss=[int]($sec%60)
      $vs = (HtmlEscape ($_.radiant + ' vs ' + $_.dire))
      $win = if ($_.radiant_win) { 'Radiant' } else { 'Dire' }
      "<li><span><a target='_blank' href='"+(HtmlEscape (& $OD_MATCH_URL $_.match_id))+"'>${vs}</a></span><span class='badge'>${mm}m ${ss}s</span><span class='badge'>Winner: ${win}</span></li>"
    }) -join "`n"
  } else { "<li><span class='sub'>no games</span></li>" }
)
        </ul>
      </div>
    </div>
  <h3>Ward Spots</h3>
  <div class="wardgrid">
    <div class="wardleft">
      <div class="sub" style="margin:-4px 0 8px">All tracked games | Number = count of observer placements at spot | Circle = observer vision radius (~1600u).</div>
      <div class="wardmap" style="background-image:url('$(HtmlEscape $mapBgUrl)')">
        <svg id="wardSvg" viewBox="0 0 100 100" preserveAspectRatio="none" width="100%" height="100%">
$(
  if ($highAll -and $highAll.wardEvents -and $highAll.wardEvents.Count -gt 0) {
  $obsPct = $null; $senPct = $null; $obsUnits=$null; $senUnits=$null; $cellUnits=$null; $spanX=$null
    try { $majTagTmp = Get-MajorPatchForUnix -unix $latestUnixAll; $assetTmp = Resolve-MapAsset -MapConf $mapConf -MajorTag $majTagTmp; if ($assetTmp -is [psobject]) { if ($assetTmp.obsRadiusUnits){$obsUnits=[double]$assetTmp.obsRadiusUnits}; if ($assetTmp.senRadiusUnits){$senUnits=[double]$assetTmp.senRadiusUnits}; if ($assetTmp.cellUnits){$cellUnits=[double]$assetTmp.cellUnits}; if ($null -ne $assetTmp.minX -and $null -ne $assetTmp.maxX){ $spanX=[double]$assetTmp.maxX - [double]$assetTmp.minX } } } catch {}
    if (-not $cellUnits) { try { if ($mapConf.defaultCellUnits){ $cellUnits = [double]$mapConf.defaultCellUnits } } catch {} }
    if (-not $obsUnits)  { try { if ($mapConf.defaultObsRadiusUnits){ $obsUnits = [double]$mapConf.defaultObsRadiusUnits } } catch {} }
    if (-not $senUnits)  { try { if ($mapConf.defaultSenRadiusUnits){ $senUnits = [double]$mapConf.defaultSenRadiusUnits } } catch {} }
    if (-not $spanX -or $spanX -le 0) { $spanX = [double]$mapScale }
    if ($obsUnits -and $cellUnits -and $spanX -gt 0) { $obsPct = [math]::Round(($obsUnits / ($cellUnits * $spanX)) * 100, 2) }
    if ($senUnits -and $cellUnits -and $spanX -gt 0) { $senPct = [math]::Round(($senUnits / ($cellUnits * $spanX)) * 100, 2) }
    if (-not $obsPct) { try { if ($assetTmp -is [psobject] -and $assetTmp.obsRadiusPct) { $obsPct = [double]$assetTmp.obsRadiusPct } } catch {} }
    if (-not $senPct) { try { if ($assetTmp -is [psobject] -and $assetTmp.senRadiusPct) { $senPct = [double]$assetTmp.senRadiusPct } } catch {} }
    if (-not $obsPct) { $obsPct = if ($mapConf.defaultObsRadiusPct) { [double]$mapConf.defaultObsRadiusPct } else { 10 } }
    if (-not $senPct) { $senPct = if ($mapConf.defaultSenRadiusPct) { [double]$mapConf.defaultSenRadiusPct } else { 6 } }
  $spotMap = @{}; foreach($e in $highAll.wardEvents){ try { $kx=[int]$e.x; $ky=[int]$e.y; $k = ("{0},{1}" -f $kx,$ky); if (-not $spotMap[$k]){ $spotMap[$k] = @{ obs=$false; sen=$false } }; if ($e.type -eq 'obs'){ $spotMap[$k].obs = $true } elseif ($e.type -eq 'sen'){ $spotMap[$k].sen = $true } } catch {} }
  $ranked = @($highAll.wardSpots); $rankLongest = @($highAll.wardLongest)
  $svgSpots = ($ranked | ForEach-Object { try { $kspot=[string]$_.spot; if (-not $kspot){ return '' }; $parts=$kspot.Split(','); $px=[double]$parts[0]; $py=[double]$parts[1]; $minX=$null; $minY=$null; $maxX=$null; $maxY=$null; try { if ($assetTmp -is [psobject]) { if ($assetTmp.minX -ne $null) { $minX=[double]$assetTmp.minX }; if ($assetTmp.minY -ne $null) { $minY=[double]$assetTmp.minY }; if ($assetTmp.maxX -ne $null) { $maxX=[double]$assetTmp.maxX }; if ($assetTmp.maxY -ne $null) { $maxY=[double]$assetTmp.maxY } } } catch {}; if ($minX -ne $null -and $minY -ne $null -and $maxX -ne $null -and $maxY -ne $null -and $maxX -gt $minX -and $maxY -gt $minY) { if ($px -lt $minX){$px=$minX}; if ($px -gt $maxX){$px=$maxX}; if ($py -lt $minY){$py=$minY}; if ($py -gt $maxY){$py=$maxY}; $cx=[math]::Round((($px - $minX)/($maxX - $minX))*100,2); $yy=(($py - $minY)/($maxY - $minY)); if ($mapInvertY){ $yy = 1.0 - $yy }; $cy=[math]::Round(($yy)*100,2) } else { $scale=[double]$mapScale; if ($px -lt 0){$px=0}; if ($px -gt $scale){$px=$scale}; if ($py -lt 0){$py=0}; if ($py -gt $scale){$py=$scale}; $cx=[math]::Round(($px/$scale)*100,2); $yy=($py/$scale); if ($mapInvertY){ $yy = 1.0 - $yy }; $cy=[math]::Round(($yy)*100,2) }; $info=$spotMap[$kspot]; $isObs=[bool]$info.obs; $svgOut=New-Object System.Text.StringBuilder; $elId = if ($_.spotId) { [string]$_.spotId } elseif ($info -and $info.id) { [string]$info.id } else { $null }; if ($isObs) { $rpct=$obsPct; $stroke='rgba(255,215,0,0.65)'; $fill='rgba(255,215,0,0.08)'; $idAttr= if ($elId) { (" id='"+$elId+"'") } else { '' }; $cnt= try { [int]$_.count } catch { 0 }; [void]$svgOut.Append("          <circle"+$idAttr+" class='spot' cx='${cx}%' cy='${cy}%' r='${rpct}' fill='${fill}' stroke='${stroke}' stroke-width='0.8' opacity='0.8'>`n            <title>Spot ${kspot} - Placements: ${cnt} - Period: All time</title>`n          </circle>`n          <circle cx='${cx}%' cy='${cy}%' r='1.0' fill='${stroke}' opacity='0.85' />") }; $svgOut.ToString() } catch { '' } }) -join "`n"
  $svgLongest = ($rankLongest | ForEach-Object { try { $kspot=[string]$_.spot; if (-not $kspot){ return '' }; $parts=$kspot.Split(','); $px=[double]$parts[0]; $py=[double]$parts[1]; $minX=$null; $minY=$null; $maxX=$null; $maxY=$null; try { if ($assetTmp -is [psobject]) { if ($assetTmp.minX -ne $null) { $minX=[double]$assetTmp.minX }; if ($assetTmp.minY -ne $null) { $minY=[double]$assetTmp.minY }; if ($assetTmp.maxX -ne $null) { $maxX=[double]$assetTmp.maxX }; if ($assetTmp.maxY -ne $null) { $maxY=[double]$assetTmp.maxY } } } catch {}; if ($minX -ne $null -and $minY -ne $null -and $maxX -ne $null -and $maxY -ne $null -and $maxX -gt $minX -and $maxY -gt $minY) { if ($px -lt $minX){$px=$minX}; if ($px -gt $maxX){$px=$maxX}; if ($py -lt $minY){$py=$minY}; if ($py -gt $maxY){$py=$maxY}; $cx=[math]::Round((($px - $minX)/($maxX - $minX))*100,2); $yy=(($py - $minY)/($maxY - $minY)); if ($mapInvertY){ $yy = 1.0 - $yy }; $cy=[math]::Round(($yy)*100,2) } else { $scale=[double]$mapScale; if ($px -lt 0){$px=0}; if ($px -gt $scale){$px=$scale}; if ($py -lt 0){$py=0}; if ($py -gt $scale){$py=$scale}; $cx=[math]::Round(($px/$scale)*100,2); $yy=($py/$scale); if ($mapInvertY){ $yy = 1.0 - $yy }; $cy=[math]::Round(($yy)*100,2) }; $info=$spotMap[$kspot]; $isObs=[bool]$info.obs; $svgOut=New-Object System.Text.StringBuilder; $elId = if ($_.spotId) { [string]$_.spotId } elseif ($info -and $info.id) { [string]$info.id } else { $null }; if ($isObs) { $rpct=$obsPct; $stroke='rgba(86,227,150,0.55)'; $fill='rgba(86,227,150,0.06)'; $idAttr= if ($elId) { (" id='"+$elId+"'") } else { '' }; $mx= try { [int]$_.maxSeconds } catch { $null }; $mm = if ($mx -ne $null) { [int]([math]::Floor($mx/60)) } else { 0 }; $ss = if ($mx -ne $null) { [int]($mx % 60) } else { 0 }; $pc = try { [int]$_.count } catch { 0 }; [void]$svgOut.Append("          <circle"+$idAttr+" class='spot longest' cx='${cx}%' cy='${cy}%' r='${rpct}' fill='${fill}' stroke='${stroke}' stroke-width='0.6' opacity='0.7'>`n            <title>Spot ${kspot} - Longest life: ${mm}m ${ss}s - Placements: ${pc}</title>`n          </circle>`n          <circle cx='${cx}%' cy='${cy}%' r='0.8' fill='${stroke}' opacity='0.75' />") }; $svgOut.ToString() } catch { '' } }) -join "`n"

  "<g id='ov-spots'>${svgSpots}</g><g id='ov-longest' style='display:none'>${svgLongest}</g>"
  } else { "          <!-- no wards -->" }
)
        </svg>
      </div>
      <div style="display:flex;align-items:center;gap:10px;margin-top:10px">
        <label style="font-size:13px;color:var(--muted)"><input id="toggleSpots" type="checkbox" checked style="vertical-align:middle;margin-right:6px">Show ward overlay</label>
      </div>
      <script>
      (function(){
        const svg = document.getElementById('wardSvg');
        if (!svg) return;
        const wrap = svg.closest('.wardmap');
        const active = new Set();
        function setHighlight(id, on){
          if (!id) return;
          const els = svg.querySelectorAll('#'+CSS.escape(id));
          if (els && els.length){ els.forEach(el=> el.classList.toggle('hl', !!on)); }
          if (on) { active.add(id); } else { active.delete(id); }
          if (wrap){ wrap.classList.toggle('highlighting', active.size>0); }
        }
        window.__wardHover = { setHighlight };
      })();
      </script>
    </div>
    <div class="wardright">
      <div class="tabs">
        <button class="tab active" data-tab="spots">Most popular spots</button>
        <button class="tab" data-tab="players">Players</button>
  <button class="tab" data-tab="longest">Longest-lived spots (min 3 placements)</button>
      </div>
      <div id="tab-spots" class="tabpane active">
        <ul id="spotList" class="simple" style="margin-top:8px">
$(if ($highAll -and $highAll.wardSpots) { ($highAll.wardSpots | ForEach-Object { $sid = if ($_.spotId){$_.spotId}else{""}; "<li data-spot='${sid}'><span>Spot $($_.spot)</span><span class='badge'>x$($_.count)</span></li>" }) -join "`n" } else { "<li><span class='sub'>no games</span></li>" })
        </ul>
      </div>
      <div id="tab-players" class="tabpane" style="display:none">
      <div class="grid3">
        <div>
          <h4>Most placed</h4>
          <ul class="simple">
$(if ($highAll -and $highAll.wardPlayers -and $highAll.wardPlayers.mostPlaced) { ($highAll.wardPlayers.mostPlaced | ForEach-Object { "<li><span><a href='"+(HtmlEscape $_.profile)+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>x$($_.count)</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" })
          </ul>
        </div>
        <div>
          <h4>Most dewards</h4>
          <ul class="simple">
$(if ($highAll -and $highAll.wardPlayers -and $highAll.wardPlayers.mostDewards) { ($highAll.wardPlayers.mostDewards | ForEach-Object { "<li><span><a href='"+(HtmlEscape $_.profile)+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>x$($_.count)</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" })
          </ul>
        </div>
        <div>
          <h4>Most successful (avg. lifetime)</h4>
          <ul class="simple">
$(if ($highAll -and $highAll.wardPlayers -and $highAll.wardPlayers.longestAvg) { ($highAll.wardPlayers.longestAvg | ForEach-Object { $sec=[int]$_.avgSeconds; $mm=[int]([math]::Floor($sec/60)); $ss=[int]($sec%60); "<li><span><a href='"+(HtmlEscape $_.profile)+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>${mm}m ${ss}s avg</span><span class='badge'>n=$($_.samples)</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" })
          </ul>
        </div>
      </div>
    </div>
      <div id="tab-longest" class="tabpane" style="display:none">
      $( if ($highAll -and $highAll.wardLongest -and $highAll.wardLongest.Count -gt 0) { $items = ($highAll.wardLongest | ForEach-Object { $sid = if ($_.spotId){$_.spotId}else{""}; $sec=[int]$_.maxSeconds; $mm=[int]([math]::Floor($sec/60)); $ss=[int]($sec%60); $pc = try { [int]$_.count } catch { 0 }; "<li data-spot='${sid}'><span>Spot $($_.spot)</span><span class='badge'>${mm}m ${ss}s</span><span class='badge'>x${pc}</span></li>" }) -join "`n"; "<ul id='longestList' class='simple' style='opacity:.85'>${items}</ul>" } else { '<ul class="simple"><li><span class="sub">no data</span></li></ul>' } )
      </div>
      <script>
      (function(){
        const root = document.currentScript.closest('.wardright');
        const tabs = Array.from(root.querySelectorAll('.tabs .tab'));
        const svg = document.getElementById('wardSvg');
        const gSpots = svg ? svg.querySelector('#ov-spots') : null;
        const gLongest = svg ? svg.querySelector('#ov-longest') : null;
        function show(name){
          root.querySelectorAll('.tabpane').forEach(p=>p.style.display='none');
          root.querySelector('#tab-'+name).style.display='';
          tabs.forEach(b=>b.classList.toggle('active', b.getAttribute('data-tab')===name));
          if (gSpots && gLongest){ if (name==='longest'){ gSpots.style.display='none'; gLongest.style.display=''; } else { gSpots.style.display=''; gLongest.style.display='none'; } }
        }
        tabs.forEach(b=>b.addEventListener('click', ()=> show(b.getAttribute('data-tab'))));
        function wireHover(ul){ const hover = window.__wardHover; if (!hover || !ul) return; ul.addEventListener('mouseover', e => { const li = e.target.closest('li[data-spot]'); if (!li) return; hover.setHighlight(li.getAttribute('data-spot'), true); }); ul.addEventListener('mouseout', e => { const li = e.target.closest('li[data-spot]'); if (!li) return; hover.setHighlight(li.getAttribute('data-spot'), false); }); }
        wireHover(document.getElementById('spotList'));
        wireHover(document.getElementById('longestList'));
        const toggle = document.getElementById('toggleSpots'); if (toggle && svg){ toggle.addEventListener('change', ()=>{ svg.style.display = toggle.checked ? '' : 'none'; }); }
      })();
      </script>
    </div>
  </div>
"@
    # Append Awards (All time)
    $awAll = if ($highAll -and ($highAll.PSObject.Properties.Name -contains 'awards')) { $highAll.awards } else { $null }
    if ($awAll) {
      $spaceAll = if ($awAll.spaceCreator -and $awAll.spaceCreator.Count -gt 0) { ($awAll.spaceCreator | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>x"+([int]$_.val)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $ogAll = if ($awAll.objectiveGamer -and $awAll.objectiveGamer.Count -gt 0) { ($awAll.objectiveGamer | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>"+(FmtPct $_.share)+"</span><span class='badge'>Rosh: x"+([int]$_.rosh)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $earlyAll = if ($awAll.earlyFarmer -and $awAll.earlyFarmer.Count -gt 0) { ($awAll.earlyFarmer | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>"+([int]$_.value)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $clutchAll = if ($awAll.clutchKing -and $awAll.clutchKing.Count -gt 0) { ($awAll.clutchKing | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>"+(FmtPct $_.ratio)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $courierAll = if ($awAll.courierAssassin -and $awAll.courierAssassin.Count -gt 0) { ($awAll.courierAssassin | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>x"+([int]$_.val)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $visionAll = if ($awAll.visionMvp -and $awAll.visionMvp.Count -gt 0) { ($awAll.visionMvp | ForEach-Object { $v=[double]$_.val; $vs=([string]([math]::Round($v,1))); "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>"+$vs+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $stackAll = if ($awAll.stackMaster -and $awAll.stackMaster.Count -gt 0) { ($awAll.stackMaster | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>x"+([int]$_.val)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $smokeAll = if ($awAll.smokeCommander -and $awAll.smokeCommander.Count -gt 0) { ($awAll.smokeCommander | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>x"+([int]$_.val)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $runesAll = if ($awAll.runeController -and $awAll.runeController.Count -gt 0) { ($awAll.runeController | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>x"+([int]$_.val)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }
      $aegisAll = if ($awAll.aegisSnatcher -and $awAll.aegisSnatcher.Count -gt 0) { ($awAll.aegisSnatcher | ForEach-Object { "<li><span><a href='"+(HtmlEscape (& $OD_PLAYER_URL $_.account_id))+"' target='_blank'>"+(HtmlEscape $_.name)+"</a></span><span class='badge'>x"+([int]$_.val)+"</span></li>" }) -join "`n" } else { "<li><span class='sub'>no data</span></li>" }

      $highBlock += @"
  <section class="card">
    <h2>Awards (All time)</h2>
    <div class="grid3">
      <div>
        <h3>Space Creator – most deaths in wins</h3>
        <ul class="simple">
$spaceAll
        </ul>
      </div>
      <div>
        <h3>Objective Gamer – tower share + rosh</h3>
        <ul class="simple">
$ogAll
        </ul>
      </div>
      <div>
        <h3>Early Farmer – net worth @10:00</h3>
        <ul class="simple">
$earlyAll
        </ul>
      </div>
    </div>
    <div class="grid3" style="margin-top:8px">
      <div>
        <h3>Clutch King – KP in last 10%</h3>
        <ul class="simple">
$clutchAll
        </ul>
      </div>
      <div>
        <h3>Courier Assassin – most couriers</h3>
        <ul class="simple">
$courierAll
        </ul>
      </div>
      <div>
        <h3>Vision MVP – warding/dewarding</h3>
        <ul class="simple">
$visionAll
        </ul>
      </div>
    </div>
    <div class="grid3" style="margin-top:8px">
      <div>
        <h3>Stack Master – most stacks</h3>
        <ul class="simple">
$stackAll
        </ul>
      </div>
      <div>
        <h3>Smoke Commander – most smokes</h3>
        <ul class="simple">
$smokeAll
        </ul>
      </div>
      <div>
        <h3>Rune Controller – runes taken</h3>
        <ul class="simple">
$runesAll
        </ul>
      </div>
    </div>
    <div class="grid3" style="margin-top:8px">
      <div>
        <h3>Aegis Snatcher – most snatches</h3>
        <ul class="simple">
$aegisAll
        </ul>
      </div>
    </div>
  </section>
"@
    }
  }

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
        <h3>Top 3 most picked heroes</h3>
        <ul>
$(Html-List $topMostPicked3 { param($h) "<li><img src='$(HtmlEscape $h.img)' alt=''><span class='name'>$(HtmlEscape $h.name)</span><span class='badge'>Picks: $($h.picks)</span><span class='badge'>WR: <strong>$(FmtPct $h.winrate)</strong></span></li>" })
        </ul>
      </div>
      <div class="summary-card">
        <h3>Top 3 most banned heroes</h3>
        <ul>
$(Html-List $topBanned3 { param($h) "<li><img src='$(HtmlEscape $h.img)' alt=''><span class='name'>$(HtmlEscape $h.name)</span><span class='badge'>Bans: $($h.bans)</span><span class='badge'>Picks: $($h.picks)</span></li>" })
        </ul>
      </div>
      <div class="summary-card">
        <h3>Top 3 players (WR, > $MinGamesPlayerTop games)</h3>
        <ul>
$(Html-List $topPlayers3 { param($p) "<li><span class='name'><a href='$(HtmlEscape $p.profile)' target='_blank'>$(HtmlEscape $p.name)</a></span><span class='badge'>$($p.games) games</span><span class='badge'>WR: <strong>$(FmtPct $p.winrate)</strong></span></li>" })
        </ul>
      </div>
      <div class="summary-card">
        <h3>Top 3 most played inhouses</h3>
        <ul>
$(Html-List $topPlayed3 { param($p) "<li><span class='name'><a href='$(HtmlEscape $p.profile)' target='_blank'>$(HtmlEscape $p.name)</a></span><span class='badge'>$($p.games) games</span><span class='badge'>WR: <strong>$(FmtPct $p.winrate)</strong></span></li>" })
        </ul>
      </div>
      <div class="summary-card">
        <h3>Highest win rate hero (min 5 games)</h3>
        <ul>
$(if ($bestHeroWR) { "<li><img src='$(HtmlEscape $bestHeroWR.img)' alt=''><span class='name'>$(HtmlEscape $bestHeroWR.name)</span><span class='badge'>Picks: $($bestHeroWR.picks)</span><span class='badge'>WR: <strong>$(FmtPct $bestHeroWR.winrate)</strong></span></li>" } else { "<li><span class='sub'>no data</span></li>" })
        </ul>
      </div>
      <div class="summary-card">
        <h3>Lowest win rate hero (min 5 games)</h3>
        <ul>
$(if ($worstHeroWR) { "<li><img src='$(HtmlEscape $worstHeroWR.img)' alt=''><span class='name'>$(HtmlEscape $worstHeroWR.name)</span><span class='badge'>Picks: $($worstHeroWR.picks)</span><span class='badge'>WR: <strong>$(FmtPct $worstHeroWR.winrate)</strong></span></li>" } else { "<li><span class='sub'>no data</span></li>" })
        </ul>
      </div>
    </div>
  </section>
  <!-- Main tabs for All-time report sections -->
  <div class="tabs" id="mainTabs" style="margin-top:12px">
    <button class="tab active" data-tab="highlights">Highlights</button>
    <button class="tab" data-tab="players">Players</button>
    <button class="tab" data-tab="heroes">Heroes</button>
    <button class="tab" data-tab="teams">Teams</button>
  </div>

  <div id="pane-highlights" class="tabpane active">
$highBlock
  </div>

  <div id="pane-players" class="tabpane" style="display:none">
    <section class="card">
      <h2>Players</h2>
$playersHtml
    </section>
  </div>

  <div id="pane-heroes" class="tabpane" style="display:none">
    <section class="card">
      <h2>All heroes - Picks/Bans/Wins & best player</h2>
$heroesHtml
    </section>
  </div>

  <div id="pane-teams" class="tabpane" style="display:none">
    <section class="card">
      <h2>Teams (with top performer)</h2>
$teamsHtml
    </section>
  </div>
</div>

<script>
(function(){
// Top-level tabs (Highlights / Players / Heroes / Teams)
const tabsRoot = document.getElementById('mainTabs');
if (tabsRoot){
  const tabs = Array.from(tabsRoot.querySelectorAll('.tab'));
  function showTab(name){
    ['highlights','players','heroes','teams'].forEach(id=>{
      const pane = document.getElementById('pane-'+id);
      if (pane) pane.style.display = (id===name)? '' : 'none';
    });
    tabs.forEach(b=> b.classList.toggle('active', b.getAttribute('data-tab')===name));
  }
  tabs.forEach(b=> b.addEventListener('click', ()=> showTab(b.getAttribute('data-tab'))));
}
// Rampage hovercard: make it clickable and stable on hover/click
document.querySelectorAll('.has-hover .ramp-badge').forEach(badge=>{
  const li = badge.closest('.has-hover');
  const card = li ? li.querySelector('.hovercard') : null;
  if (!card) return;
  function open(){ card.style.display='block'; li.classList.add('open'); }
  function close(){ card.style.display='none'; li.classList.remove('open'); }
  let locked = false;
  // Keep open while hovering badge or card
  badge.addEventListener('mouseenter', open);
  if (card) { card.addEventListener('mouseenter', open); }
  // Close when leaving the entire item (unless locked by click)
  li.addEventListener('mouseleave', ()=>{ if (!locked) close(); });
  // Toggle lock on click for easier clicking
  badge.addEventListener('click', (e)=>{ e.stopPropagation(); e.preventDefault(); locked = !locked; if (locked) open(); else close(); });
  // Close when clicking outside
  document.addEventListener('click', (ev)=>{ if (!li.contains(ev.target)) { locked=false; close(); } });
  // Keyboard accessibility
  badge.addEventListener('keydown', (ev)=>{ if (ev.key==='Enter' || ev.key===' ') { ev.preventDefault(); badge.click(); } });
});
// Click-to-open for player heroes lists
document.querySelectorAll('.has-hover .player-heroes').forEach(link=>{
  const li = link.closest('.has-hover');
  const card = li ? li.querySelector('.hovercard') : null;
  if (!card) return;
  function open(){ card.style.display='block'; li.classList.add('open'); }
  function close(){ card.style.display='none'; li.classList.remove('open'); }
  let locked = false;
  link.addEventListener('click', (e)=>{ e.preventDefault(); locked=!locked; if(locked) open(); else close(); });
  card.addEventListener('mouseenter', open);
  li.addEventListener('mouseleave', ()=>{ if (!locked) close(); });
  document.addEventListener('click', (ev)=>{ if (!li.contains(ev.target)) { locked=false; close(); } });
  link.addEventListener('keydown', (ev)=>{ if (ev.key==='Enter' || ev.key===' ') { ev.preventDefault(); link.click(); } });
});
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
  if ($preExtraCommit -and $preExtraCommit.Count -gt 0) { $extraCommit = @($extraCommit + $preExtraCommit) }

  if ($PublishToRepo -and $RepoPath) {
  # Export client data for dynamic viewer
  $exported = Export-DataForClient -RepoPath $RepoPath -State $state -HeroMap $heroMap
  $extraCommit = @($extraCommit + $exported)

  # Skip exporting highlights snapshots; dynamic viewer computes highlights client-side.
  try { } catch { }

  $published = Save-ReportToRepo -RepoPath $RepoPath -Html $html -LeagueName $LEAGUE_NAME -Range $Range `
         -IndexMax $IndexMax -GitAutoPush:$GitAutoPush -StableAll:$StableAll -ExtraCommitPaths $extraCommit
    Write-Host "Published: $published" -ForegroundColor Green
  if ($OutFile) { Write-Host "Note: -OutFile is ignored when -PublishToRepo is used to avoid duplicates." -ForegroundColor Yellow }
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

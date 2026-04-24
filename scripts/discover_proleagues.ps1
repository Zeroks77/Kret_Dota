<#
.SYNOPSIS
  Discovers and categorizes Tier-1/2 pro leagues from OpenDota, then optionally
  generates reports for newly discovered leagues.

.DESCRIPTION
  1. Fetches/refreshes the OpenDota leagues list
  2. Filters professional-tier leagues with IDs > threshold (recent leagues)
  3. Matches against known series patterns (TI, DreamLeague, PGL, BLAST, ESL, etc.)
  4. Compares with existing tracked leagues in data/league/
  5. Outputs data/league_tiers.json with discovery status
  6. Optionally triggers report generation for new leagues

.PARAMETER MinLeagueId
  Minimum league ID to consider (filters out ancient leagues). Default 17000.

.PARAMETER AutoTrack
  Automatically create league folders + trigger report generation for newly
  discovered Tier 1 leagues.

.PARAMETER RefreshTrackedGroups
  Refresh already tracked league groups and merge missing qualifier ids without
  auto-tracking unrelated historical leagues.

.PARAMETER DryRun
  List discovered leagues without creating anything.

.PARAMETER IncludeTier2
  Also auto-track Tier 2 leagues (FISSURE, EPL, Predator, etc.)

.PARAMETER ForceRefreshLeagues
  Force re-fetch of leagues list from OpenDota API.

.EXAMPLE
  pwsh ./scripts/discover_proleagues.ps1 -DryRun
  pwsh ./scripts/discover_proleagues.ps1 -AutoTrack
  pwsh ./scripts/discover_proleagues.ps1 -AutoTrack -IncludeTier2
#>

param(
  [int]$MinLeagueId = 17000,
  [switch]$AutoTrack,
  [switch]$RefreshTrackedGroups,
  [switch]$DryRun,
  [switch]$IncludeTier2,
  [object]$TrackOnlyCompleted = $true,
  [int]$CompletedGraceDays = 10,
  [int]$CompletionCacheMaxAgeHours = 12,
  [ValidateSet('tier1','all')]
  [string]$DiscoveryScope = 'tier1',
  [switch]$ForceRefreshLeagues,
  [switch]$SkipMatchesIfCached,
  [int]$MaxPerMinute = 54,
  [int]$MaxPerDay = 1800
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Convert-ToBool([object]$Value, [bool]$Default = $false) {
  if ($null -eq $Value) { return $Default }
  if ($Value -is [bool]) { return [bool]$Value }
  $s = ('' + $Value).Trim().ToLowerInvariant()
  if ([string]::IsNullOrWhiteSpace($s)) { return $Default }
  if ($s -in @('1','true','yes','y','on')) { return $true }
  if ($s -in @('0','false','no','n','off')) { return $false }
  try { return [System.Convert]::ToBoolean($Value) } catch { return $Default }
}

$TrackOnlyCompleted = Convert-ToBool -Value $TrackOnlyCompleted -Default $true

# Load shared helpers
. "$PSScriptRoot/lib/common.ps1"

$dataPath    = Get-DataPath
$cachePath   = Get-CachePath
$tiersFile   = Join-Path $dataPath 'league_tiers.json'

# ---------- 1. Fetch leagues ----------
$leagueCachePath = Join-Path $cachePath 'leagues.json'
$leagues = Get-CachedOrFetch -CachePath $leagueCachePath -Endpoint 'leagues' -MaxAgeHours 24 -Force:$ForceRefreshLeagues
if (-not $leagues) { throw 'Failed to load leagues data' }

Write-Host ("Loaded {0} total leagues from OpenDota" -f @($leagues).Count)

# ---------- 2. Filter professional leagues with recent IDs ----------
$proLeagues = @($leagues) | Where-Object {
  $_.tier -eq 'professional' -and [int]$_.leagueid -ge $MinLeagueId
}

Write-Host ("Found {0} professional leagues with ID >= {1}" -f @($proLeagues).Count, $MinLeagueId)

# ---------- 3. Categorize by known series ----------
$discovered = @()
foreach ($lg in $proLeagues) {
  $name = '' + $lg.name
  $id   = [int]$lg.leagueid
  if ([string]::IsNullOrWhiteSpace($name)) { continue }

  $tierInfo = Get-LeagueTier $name
  $slug     = Get-LeagueSlug $name

  $discovered += [pscustomobject]@{
    leagueid = $id
    name     = $name
    slug     = $slug
    tier     = $tierInfo.Tier
    series   = $tierInfo.Series
    matches_count = 0
    latest_start = 0
    is_completed = $false
    eligible_for_tracking = $false
    status   = 'discovered'  # will be updated below
  }
}

function Test-IsQualifierLeague([string]$name) {
  if ([string]::IsNullOrWhiteSpace($name)) { return $false }
  return ($name -match '(?i)\bqualifier(s)?\b|\bclosed qualifiers?\b|\bopen qualifiers?\b|\bregional qualifiers?\b|\broad to the international\b')
}

function Get-LeagueCompletionInfo([int]$LeagueId) {
  $cacheDir = Join-Path $cachePath 'leagues'
  if (-not (Test-Path -LiteralPath $cacheDir)) {
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
  }
  $cacheFile = Join-Path $cacheDir ("{0}-matches.json" -f $LeagueId)

  $matches = $null
  try {
    $matches = Get-CachedOrFetch -CachePath $cacheFile -Endpoint ("leagues/{0}/matches" -f $LeagueId) -MaxAgeHours $CompletionCacheMaxAgeHours
  } catch {
    $matches = $null
  }

  $count = 0
  $latest = 0
  if ($matches) {
    $arr = @($matches)
    $count = $arr.Count
    foreach ($m in $arr) {
      $st = 0
      try { $st = [int]$m.start_time } catch { $st = 0 }
      if ($st -gt $latest) { $latest = $st }
    }
  }

  $completed = $false
  if ($count -gt 0 -and $latest -gt 0) {
    $threshold = [int][DateTimeOffset]::UtcNow.AddDays(-[double]$CompletedGraceDays).ToUnixTimeSeconds()
    $completed = ($latest -le $threshold)
  }

  return [ordered]@{
    matches_count = $count
    latest_start  = $latest
    is_completed  = $completed
  }
}

function Get-LeagueGroupKey([string]$name, [string]$series) {
  $n = ('' + $name).ToLowerInvariant()
  $s = ('' + $series).ToLowerInvariant()

  if ($s -eq 'ti') {
    if ($n -match '(20\d{2})') { return "ti-$($Matches[1])" }
  }
  if ($s -eq 'dreamleague') {
    if ($n -match 'season\s+(\d+)') { return "dreamleague-s$($Matches[1])" }
  }
  if ($s -eq 'pgl' -and $n -match 'wallachia') {
    if ($n -match 'season\s*#?\s*(\d+)') { return "pgl-wallachia-s$($Matches[1])" }
  }
  if ($s -eq 'esl') {
    if ($n -match 'esl one\s+([a-z]+)\s+(20\d{2})') { return "eslone-$($Matches[1])-$($Matches[2])" }
  }
  if ($s -eq 'blast') {
    if ($n -match 'slam\s+([ivx]+|\d+)') { return "blast-slam-$($Matches[1].ToUpperInvariant())" }
  }

  $base = $n -replace '(?i)\b(closed|open|regional|road to the international|qualifier|qualifiers)\b', ''
  $base = $base -replace '[^a-z0-9]+', '-'
  $base = $base.Trim('-')
  if ([string]::IsNullOrWhiteSpace($base)) { $base = 'unknown' }
  if (-not [string]::IsNullOrWhiteSpace($s)) { return "$s-$base" }
  return $base
}

if ($DiscoveryScope -eq 'tier1') {
  $discovered = @($discovered | Where-Object { $_.tier -eq 1 })
}

# Sort by ID descending (newest first)
$discovered = $discovered | Sort-Object leagueid -Descending

Write-Host ""
Write-Host "=== Discovered Pro Leagues ==="
Write-Host ("-" * 70)

# ---------- 4. Compare with existing tracked leagues ----------
$leagueDataDir = Join-Path $dataPath 'league'
$existingSlugs  = @()
if (Test-Path -LiteralPath $leagueDataDir) {
  $existingSlugs = @(Get-ChildItem -LiteralPath $leagueDataDir -Directory | ForEach-Object { $_.Name })
}

# Load existing tiers file if present
$existingTiers = @()
if (Test-Path -LiteralPath $tiersFile) {
  try {
    $existingTiers = @((Read-JsonFile $tiersFile).leagues)
  } catch { $existingTiers = @() }
}
$existingIdSet = @{}
foreach ($et in $existingTiers) {
  if ($et -and $et.leagueid) { $existingIdSet[[int]$et.leagueid] = $et }
}

# Mark status for each discovered league
$newLeagues  = @()
$tier1Count  = 0
$tier2Count  = 0
$trackedCount = 0
$pendingCount = 0
$completionById = @{}

foreach ($d in $discovered) {
  # Check if already tracked (folder exists OR tiers file explicitly marked as tracked)
  $wasTrackedInTiers = $false
  if ($existingIdSet.ContainsKey([int]$d.leagueid)) {
    $prev = $existingIdSet[[int]$d.leagueid]
    if ($prev -and ('' + $prev.status) -eq 'tracked') { $wasTrackedInTiers = $true }
  }
  if ($d.slug -in $existingSlugs -or $wasTrackedInTiers) {
    $d.status = 'tracked'
    $trackedCount++
  }
  else {
    $d.status = 'discovered'
  }

  $lid = [int]$d.leagueid
  if (-not $completionById.ContainsKey($lid)) {
    $completionById[$lid] = Get-LeagueCompletionInfo -LeagueId $lid
  }
  $c = $completionById[$lid]
  $d.matches_count = [int]$c.matches_count
  $d.latest_start = [int]$c.latest_start
  $d.is_completed = [bool]$c.is_completed

  $tierLabel = switch ($d.tier) { 1 { 'Tier 1' } 2 { 'Tier 2' } default { 'Tier 3' } }
  $statusIcon = switch ($d.status) {
    'tracked'    { '[TRACKED]' }
    'discovered' { '[NEW]    ' }
    default      { '[?]      ' }
  }
  $completionIcon = if ($d.is_completed) { '[DONE]' } elseif ($d.matches_count -gt 0) { '[LIVE]' } else { '[UNK ]' }
  $seriesTag = if ($d.series) { "($($d.series))" } else { '' }

  if ($d.tier -le 2) {
    Write-Host ("{0} {1} {2,6} {3,-8} {4,-50} {5}" -f $statusIcon, $completionIcon, $d.leagueid, $tierLabel, $d.name, $seriesTag)
  }

  if ($d.tier -eq 1) { $tier1Count++ }
  if ($d.tier -eq 2) { $tier2Count++ }

  if ($d.status -eq 'discovered') {
    $shouldTrack = ($d.tier -eq 1) -or ($IncludeTier2 -and $d.tier -eq 2)
    $completeGate = (-not $TrackOnlyCompleted) -or $d.is_completed
    if ($shouldTrack -and $completeGate) {
      $d.eligible_for_tracking = $true
      $newLeagues += $d
    }
    elseif ($shouldTrack -and -not $completeGate) {
      $pendingCount++
    }
  }
}

Write-Host ("-" * 70)
Write-Host ("Summary: {0} Tier-1, {1} Tier-2, {2} already tracked" -f $tier1Count, $tier2Count, $trackedCount)
Write-Host ("{0} new leagues eligible for tracking" -f @($newLeagues).Count)
if ($TrackOnlyCompleted) {
  Write-Host ("{0} discovered leagues held back (not completed yet; grace={1}d)" -f $pendingCount, $CompletedGraceDays)
}

# ---------- 5. Save tiers file ----------
# Merge discovered with existing (keep existing status if already tracked)
$mergedLeagues = @()
$seenIds = @{}

foreach ($d in $discovered) {
  $id = [int]$d.leagueid
  if ($seenIds.ContainsKey($id)) { continue }
  $seenIds[$id] = $true

  # Preserve 'complete' status from existing
  if ($existingIdSet.ContainsKey($id) -and $existingIdSet[$id].status -eq 'complete') {
    $d.status = 'complete'
  }

  $mergedLeagues += $d
}

$tiersOutput = [ordered]@{
  updated  = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  count    = @($mergedLeagues).Count
  leagues  = @($mergedLeagues)
}

if (-not $DryRun) {
  Save-Json -o $tiersOutput -p $tiersFile
  Write-Host ("Saved league tiers to: {0}" -f $tiersFile)
}

# ---------- 6. Auto-track / refresh league groups ----------
if (($AutoTrack -or $RefreshTrackedGroups) -and -not $DryRun) {
  Write-Host ""
  Write-Host "=== Refreshing league groups (qualifier merge enabled) ==="

  $trackPool = @($discovered | Where-Object {
    ($_.tier -eq 1) -or ($IncludeTier2 -and $_.tier -eq 2)
  })

  $byGroup = @{}
  foreach ($l in $trackPool) {
    $gk = Get-LeagueGroupKey -name $l.name -series $l.series
    if (-not $byGroup.ContainsKey($gk)) { $byGroup[$gk] = @() }
    $byGroup[$gk] += $l
  }

  function Get-TrackedReportMergedLeagueIds([string]$Slug) {
    if ([string]::IsNullOrWhiteSpace($Slug)) { return @() }
    $reportPath = Join-Path $dataPath ("league/{0}/report.json" -f $Slug)
    $report = Read-JsonFile $reportPath
    if (-not $report -or -not $report.league) { return @() }

    $ids = @()
    try { $ids += [int]$report.league.id } catch {}
    try { $ids += @($report.league.merged_league_ids | ForEach-Object { [int]$_ }) } catch {}
    return @($ids | Where-Object { $_ -gt 0 } | Sort-Object -Unique)
  }

  $groupsNeedingRefresh = @()
  foreach ($kv in $byGroup.GetEnumerator()) {
    $members = @($kv.Value)
    if ($RefreshTrackedGroups -and -not $AutoTrack) {
      $hasTrackedAnchor = @($members | Where-Object { $_.status -eq 'tracked' -or $existingSlugs -contains $_.slug }).Count -gt 0
      if (-not $hasTrackedAnchor) { continue }
    }
    $trackedNonQualifier = @($members | Where-Object { $_.status -eq 'tracked' -and -not (Test-IsQualifierLeague $_.name) } | Sort-Object leagueid -Descending)
    $discoveredNonQualifier = @($members | Where-Object { $_.status -eq 'discovered' -and -not (Test-IsQualifierLeague $_.name) } | Sort-Object leagueid -Descending)
    $fallback = @($members | Sort-Object leagueid -Descending)

    $primary = $null
    if ($trackedNonQualifier.Count -gt 0) { $primary = $trackedNonQualifier[0] }
    elseif ($discoveredNonQualifier.Count -gt 0) { $primary = $discoveredNonQualifier[0] }
    elseif ($fallback.Count -gt 0) { $primary = $fallback[0] }

    $allIds = @($members | ForEach-Object { [int]$_.leagueid } | Sort-Object -Unique)
    $needsRefresh = (@($members | Where-Object { $_.status -eq 'discovered' -and $_.eligible_for_tracking }).Count -gt 0)
    if (-not $needsRefresh -and $primary) {
      $reportIds = @(Get-TrackedReportMergedLeagueIds -Slug ('' + $primary.slug))
      if ($reportIds.Count -eq 0) {
        $needsRefresh = $true
      } elseif (@(Compare-Object -ReferenceObject $allIds -DifferenceObject $reportIds).Count -gt 0) {
        $needsRefresh = $true
      }
    }

    if ($needsRefresh) {
      $groupsNeedingRefresh += [pscustomobject]@{ key = $kv.Key; members = $members; primary = $primary; allIds = $allIds }
    }
  }

  if ($groupsNeedingRefresh.Count -eq 0) {
    Write-Host "  No league groups require refresh."
  }

  foreach ($g in $groupsNeedingRefresh) {
    $members = @($g.members)
    $primary = $g.primary
    $allIds = @($g.allIds)
    $extraIds = @($allIds | Where-Object { $_ -ne [int]$primary.leagueid })

    Write-Host ("  Generating merged report for group '{0}' via: {1} (id={2}); merged league ids: {3}" -f $g.key, $primary.name, $primary.leagueid, (($allIds -join ', ')))

    try {
      $invokeArgs = @(
        '-File', (Join-Path $PSScriptRoot 'create_league_report.ps1'),
        '-LeagueName', $primary.name,
        '-MaxPerMinute', $MaxPerMinute,
        '-MaxPerDay', $MaxPerDay
      )
      if ($extraIds.Count -gt 0) { $invokeArgs += @('-IncludeLeagueIds', ($extraIds -join ',')) }
      if ($SkipMatchesIfCached) { $invokeArgs += '-SkipMatchesIfCached' }

      & pwsh @invokeArgs

      foreach ($m in $members) { $m.status = 'tracked' }
      Write-Host ("  -> Successfully tracked (merged): {0}" -f $primary.slug)
    }
    catch {
      Write-Warning ("  -> Failed to track group {0}: {1}" -f $g.key, $_.Exception.Message)
    }
  }

  # Re-save with updated statuses
  $tiersOutput.leagues = @($mergedLeagues)
  Save-Json -o $tiersOutput -p $tiersFile
}

if ($DryRun) {
  Write-Host ""
  Write-Host "DRY RUN - no changes made. Use -AutoTrack to generate reports."
}

# ---------- 7. Output summary for API ----------
$apiSummary = @($mergedLeagues | Where-Object { $_.tier -le 2 } | ForEach-Object {
  [pscustomobject]@{
    id     = $_.leagueid
    name   = $_.name
    slug   = $_.slug
    tier   = $_.tier
    series = $_.series
    status = $_.status
  }
})

# Save to docs/api/v1/leagues/tiers.json for frontend consumption
$docsApiDir = Join-Path (Get-DocsPath) 'api/v1/leagues'
if (-not $DryRun) {
  if (-not (Test-Path -LiteralPath $docsApiDir)) {
    New-Item -ItemType Directory -Path $docsApiDir -Force | Out-Null
  }
  Save-Json -o $apiSummary -p (Join-Path $docsApiDir 'tiers.json')
  Write-Host ("Published league tiers API: docs/api/v1/leagues/tiers.json")
}

Write-Host ""
Write-Host "League discovery complete."

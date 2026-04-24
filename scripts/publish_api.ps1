<#
.SYNOPSIS
  Publishes all data into docs/api/v1/ for GitHub Pages consumption.

.DESCRIPTION
  Builds a clean REST-like API surface under docs/api/v1/:
    - manifest.json       (index of all available endpoints)
    - leagues/index.json  (all leagues with metadata)
    - leagues/{slug}/report.json, matches.json, wards.json
    - monthly/index.json  (monthly shard index)
    - monthly/{YYYY-MM}.json
    - constants/heroes.json, patches.json
    - stats/global.json   (cross-league averages)
    - stats/{slug}.json   (per-league averages)
    - meta/reports.json   (sidebar report index)

.PARAMETER DocsRoot
  Root docs folder. Default: ../docs relative to this script.

.EXAMPLE
  pwsh ./scripts/publish_api.ps1
#>

param(
  [string]$DocsRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Load shared helpers
. "$PSScriptRoot/lib/common.ps1"

$repoRoot = Get-RepoRoot
$dataDir  = Get-DataPath
$docsDir  = if ($DocsRoot) { $DocsRoot } else { Get-DocsPath }
$apiDir   = Join-Path $docsDir 'api/v1'

Write-Host "Publishing API to: $apiDir"

# Ensure directories
function Ensure-Dir([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) {
    New-Item -ItemType Directory -Path $p -Force | Out-Null
  }
}
Ensure-Dir $apiDir

# ====== Constants ======
$constDir = Join-Path $apiDir 'constants'
Ensure-Dir $constDir

$srcConst = Join-Path $dataDir 'cache/OpenDota/constants'
foreach ($fn in 'heroes.json', 'patch.json', 'items.json') {
  $src = Join-Path $srcConst $fn
  if (Test-Path -LiteralPath $src) {
    Copy-Item -LiteralPath $src -Destination (Join-Path $constDir $fn) -Force
    Write-Host "  constants/$fn"
  }
}

# Also publish heroes.json from data root (richer)
$heroSrc = Join-Path $dataDir 'heroes.json'
if (Test-Path -LiteralPath $heroSrc) {
  Copy-Item -LiteralPath $heroSrc -Destination (Join-Path $constDir 'heroes_full.json') -Force
}

# ====== Leagues ======
$leaguesApiDir = Join-Path $apiDir 'leagues'
Ensure-Dir $leaguesApiDir

$leagueDataRoot = Join-Path $dataDir 'league'
$leagueIndex = @()

if (Test-Path -LiteralPath $leagueDataRoot) {
  $slugDirs = Get-ChildItem -LiteralPath $leagueDataRoot -Directory
  foreach ($dir in $slugDirs) {
    $slug = $dir.Name
    $reportSrc = Join-Path $dir.FullName 'report.json'
    $matchesSrc = Join-Path $dir.FullName 'matches.json'

    if (-not (Test-Path -LiteralPath $reportSrc)) { continue }

    $report = Read-JsonFile $reportSrc
    if (-not $report) { continue }

    # Create league API directory
    $leagueApiPath = Join-Path $leaguesApiDir $slug
    Ensure-Dir $leagueApiPath

    # Copy report and matches
    Copy-Item -LiteralPath $reportSrc -Destination (Join-Path $leagueApiPath 'report.json') -Force

    if (Test-Path -LiteralPath $matchesSrc) {
      Copy-Item -LiteralPath $matchesSrc -Destination (Join-Path $leagueApiPath 'matches.json') -Force
    }

    # Extract wards into separate file for lighter initial loads
    if ($report.highlights -and $report.highlights.wards -and $report.highlights.wards.viewer) {
      $wardData = @{
        bestSpots  = $report.highlights.wards.bestSpots
        worstSpots = $report.highlights.wards.worstSpots
        allSpots   = $report.highlights.wards.allSpots
        viewer     = $report.highlights.wards.viewer
      }
      Save-JsonCompact -o $wardData -p (Join-Path $leagueApiPath 'wards.json')
    }

    # Extract averages into per-league stats
    $statsDir = Join-Path $apiDir 'stats'
    Ensure-Dir $statsDir
    if ($report.PSObject.Properties['averages'] -and $report.averages) {
      Save-Json -o $report.averages -p (Join-Path $statsDir "$slug.json")
    }

    # Ward summary if exists
    $wardSumSrc = Join-Path $dir.FullName 'ward_summary.json'
    if (Test-Path -LiteralPath $wardSumSrc) {
      Copy-Item -LiteralPath $wardSumSrc -Destination (Join-Path $leagueApiPath 'ward_summary.json') -Force
    }

    # Build index entry
    $leagueMeta = $report.league
    $matchCount = 0
    try { $matchCount = @($report.placements | ForEach-Object { $_.games } | Measure-Object -Sum).Sum / 2 } catch {}
    if ($matchCount -le 0) {
      try {
        if ($report.PSObject.Properties['averages'] -and $report.averages) {
          $matchCount = $report.averages.total_matches
        }
      } catch {}
    }

    $entry = [ordered]@{
      slug       = $slug
      id         = if ($leagueMeta.id) { [int]$leagueMeta.id } else { 0 }
      name       = if ($leagueMeta.name) { '' + $leagueMeta.name } else { $slug }
      from       = if ($leagueMeta.from) { [int]$leagueMeta.from } else { 0 }
      to         = if ($leagueMeta.to) { [int]$leagueMeta.to } else { 0 }
      matches    = [int]$matchCount
      generated  = if ($report.generated) { [int]$report.generated } else { 0 }
      hasAverages = ($report.PSObject.Properties['averages'] -and $null -ne $report.averages)
      endpoints  = @{
        report  = "leagues/$slug/report.json"
        matches = "leagues/$slug/matches.json"
        wards   = "leagues/$slug/wards.json"
        stats   = "stats/$slug.json"
      }
    }
    $leagueIndex += [pscustomobject]$entry
    Write-Host "  leagues/$slug/"
  }
}

# Sort leagues by 'from' date descending (newest first)
$leagueIndex = @($leagueIndex | Sort-Object -Property { $_.from } -Descending)
Save-Json -o $leagueIndex -p (Join-Path $leaguesApiDir 'index.json')
Write-Host "  leagues/index.json ($(@($leagueIndex).Count) leagues)"

# ====== Monthly shards ======
$monthlyApiDir = Join-Path $apiDir 'monthly'
Ensure-Dir $monthlyApiDir

$monthlyIndex = @()
$shardsSrc = Join-Path $dataDir 'matches'
if (Test-Path -LiteralPath $shardsSrc) {
  $shardFiles = Get-ChildItem -LiteralPath $shardsSrc -Filter '*.json' | Sort-Object Name -Descending
  foreach ($sf in $shardFiles) {
    Copy-Item -LiteralPath $sf.FullName -Destination (Join-Path $monthlyApiDir $sf.Name) -Force

    $month = $sf.BaseName  # e.g. "2025-07"
    $count = 0
    try {
      $content = Read-JsonFile $sf.FullName
      $count = @($content).Count
    } catch {}

    $monthlyIndex += [pscustomobject][ordered]@{
      month    = $month
      count    = $count
      endpoint = "monthly/$($sf.Name)"
    }
    Write-Host "  monthly/$($sf.Name)"
  }
}

Save-Json -o $monthlyIndex -p (Join-Path $monthlyApiDir 'index.json')

# ====== Global stats (aggregate across all leagues) ======
$statsDir = Join-Path $apiDir 'stats'
Ensure-Dir $statsDir

$globalDurations  = @()
$globalFBTimes    = @()
$globalRoshTimes  = @()
$globalKills      = @()
$globalRadWins    = 0
$globalTotalGames = 0

foreach ($entry in $leagueIndex) {
  $statsFile = Join-Path $statsDir "$($entry.slug).json"
  if (-not (Test-Path -LiteralPath $statsFile)) { continue }
  $stats = Read-JsonFile $statsFile
  if (-not $stats) { continue }

  $n = if ($stats.total_matches) { [int]$stats.total_matches } else { 0 }
  $globalTotalGames += $n

  if ($stats.avg_duration -gt 0) { $globalDurations += $stats.avg_duration }
  if ($stats.first_blood_time -gt 0) { $globalFBTimes += $stats.first_blood_time }
  if ($stats.first_roshan_time -gt 0) { $globalRoshTimes += $stats.first_roshan_time }
  if ($stats.avg_kills -gt 0) { $globalKills += $stats.avg_kills }
  if ($stats.radiant_winrate -gt 0 -and $n -gt 0) { $globalRadWins += [int]([Math]::Round($stats.radiant_winrate * $n)) }
}

$globalStats = [ordered]@{
  total_matches     = $globalTotalGames
  avg_duration      = if (@($globalDurations).Count -gt 0) { [int]([Math]::Round(($globalDurations | Measure-Object -Average).Average)) } else { 0 }
  first_blood_time  = if (@($globalFBTimes).Count -gt 0) { [int]([Math]::Round(($globalFBTimes | Measure-Object -Average).Average)) } else { 0 }
  first_roshan_time = if (@($globalRoshTimes).Count -gt 0) { [int]([Math]::Round(($globalRoshTimes | Measure-Object -Average).Average)) } else { 0 }
  avg_kills         = if (@($globalKills).Count -gt 0) { [Math]::Round(($globalKills | Measure-Object -Average).Average, 1) } else { 0 }
  radiant_winrate   = if ($globalTotalGames -gt 0) { [Math]::Round([double]$globalRadWins / $globalTotalGames, 3) } else { 0 }
  leagues_count     = @($leagueIndex).Count
  updated           = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
}

Save-Json -o $globalStats -p (Join-Path $statsDir 'global.json')
Write-Host "  stats/global.json"

# ====== Meta ======
$metaDir = Join-Path $apiDir 'meta'
Ensure-Dir $metaDir

# Copy reports.json
$reportsSrc = Join-Path $docsDir 'reports.json'
if (Test-Path -LiteralPath $reportsSrc) {
  Copy-Item -LiteralPath $reportsSrc -Destination (Join-Path $metaDir 'reports.json') -Force
  Write-Host "  meta/reports.json"
}

# Copy maps config
$mapsSrc = Join-Path $dataDir 'maps.json'
if (Test-Path -LiteralPath $mapsSrc) {
  Copy-Item -LiteralPath $mapsSrc -Destination (Join-Path $metaDir 'maps.json') -Force
}

# Copy info
$infoSrc = Join-Path $dataDir 'info.json'
if (Test-Path -LiteralPath $infoSrc) {
  Copy-Item -LiteralPath $infoSrc -Destination (Join-Path $metaDir 'info.json') -Force
}

# Copy proPlayers (lookup table for league viewer name resolution)
$proSrc = Join-Path $dataDir 'cache/OpenDota/proPlayers.json'
if (Test-Path -LiteralPath $proSrc) {
  Copy-Item -LiteralPath $proSrc -Destination (Join-Path $metaDir 'proPlayers.json') -Force
  Write-Host "  meta/proPlayers.json"
}

# ====== Manifest ======
$manifest = [ordered]@{
  version   = 'v1'
  updated   = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  base_url  = 'api/v1/'
  endpoints = [ordered]@{
    leagues_index   = 'leagues/index.json'
    league_report   = 'leagues/{slug}/report.json'
    league_matches  = 'leagues/{slug}/matches.json'
    league_wards    = 'leagues/{slug}/wards.json'
    monthly_index   = 'monthly/index.json'
    monthly_data    = 'monthly/{month}.json'
    stats_global    = 'stats/global.json'
    stats_league    = 'stats/{slug}.json'
    constants_heroes = 'constants/heroes.json'
    constants_patches = 'constants/patch.json'
    meta_reports    = 'meta/reports.json'
    meta_maps       = 'meta/maps.json'
  }
  leagues   = @($leagueIndex | ForEach-Object { $_.slug })
  monthly   = @($monthlyIndex | ForEach-Object { $_.month })
}

Save-Json -o $manifest -p (Join-Path $apiDir 'manifest.json')
Write-Host "  manifest.json"

Write-Host ""
Write-Host ("API published: {0} leagues, {1} monthly shards" -f @($leagueIndex).Count, @($monthlyIndex).Count)
Write-Host "Done."

<#
.SYNOPSIS
  Validates league report completeness and match-cache coverage.

.DESCRIPTION
  Checks each league under data/league (optionally tracked leagues only) and validates:
  - report.json exists
  - matches.json exists and contains match IDs
  - per-match cache files exist under data/cache/OpenDota/matches

  Writes a validation summary to data/validation/league_data_validation.json.
#>

param(
  [switch]$CheckTrackedOnly,
  [switch]$FailOnMissing,
  [string]$OutFile = 'data/validation/league_data_validation.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/lib/common.ps1"

$dataDir = Get-DataPath
$leagueDir = Join-Path $dataDir 'league'
$cacheDir = Join-Path $dataDir 'cache/OpenDota/matches'

if (-not (Test-Path -LiteralPath $leagueDir)) {
  throw "League directory not found: $leagueDir"
}

$trackedBySlug = @{}
if ($CheckTrackedOnly) {
  $tiersPath = Join-Path $dataDir 'league_tiers.json'
  if (Test-Path -LiteralPath $tiersPath) {
    try {
      $tiers = Read-JsonFile $tiersPath
      foreach ($l in @($tiers.leagues)) {
        if (-not $l) { continue }
        if (('' + $l.status) -eq 'tracked' -and -not [string]::IsNullOrWhiteSpace('' + $l.slug)) {
          $trackedBySlug['' + $l.slug] = $true
        }
      }
    } catch {
      Write-Warning ("Failed to read league tiers: {0}" -f $_.Exception.Message)
    }
  }
}

$leagueFolders = @(Get-ChildItem -LiteralPath $leagueDir -Directory | Sort-Object Name)
if ($CheckTrackedOnly) {
  $leagueFolders = @($leagueFolders | Where-Object { $trackedBySlug.ContainsKey($_.Name) })
}

$items = @()
$missingTotal = 0
$leaguesWithIssues = 0

foreach ($folder in $leagueFolders) {
  $slug = '' + $folder.Name
  $matchesPath = Join-Path $folder.FullName 'matches.json'
  $reportPath = Join-Path $folder.FullName 'report.json'

  $hasMatches = Test-Path -LiteralPath $matchesPath
  $hasReport = Test-Path -LiteralPath $reportPath

  $matchIds = @()
  if ($hasMatches) {
    try {
      $matches = Read-JsonFile $matchesPath
      $matchIds = @($matches | ForEach-Object {
        try { [int64]$_.match_id } catch { 0 }
      } | Where-Object { $_ -gt 0 } | Sort-Object -Unique)
    } catch {
      Write-Warning ("Invalid matches file for {0}: {1}" -f $slug, $_.Exception.Message)
    }
  }

  $missingIds = @()
  foreach ($mid in $matchIds) {
    $cacheFile = Join-Path $cacheDir ("{0}.json" -f $mid)
    if (-not (Test-Path -LiteralPath $cacheFile)) {
      $missingIds += $mid
    }
  }

  $presentCount = @($matchIds).Count - @($missingIds).Count
  if ($presentCount -lt 0) { $presentCount = 0 }

  $coverage = 1.0
  if (@($matchIds).Count -gt 0) {
    $coverage = [Math]::Round(([double]$presentCount / [double]@($matchIds).Count), 4)
  }

  $hasIssue = (-not $hasReport) -or (-not $hasMatches) -or (@($missingIds).Count -gt 0)
  if ($hasIssue) { $leaguesWithIssues++ }
  $missingTotal += @($missingIds).Count

  $items += [ordered]@{
    slug = $slug
    has_report = $hasReport
    has_matches = $hasMatches
    expected_matches = @($matchIds).Count
    cached_matches = $presentCount
    missing_matches = @($missingIds).Count
    coverage = $coverage
    ok = -not $hasIssue
    missing_match_ids = @($missingIds | Select-Object -First 100)
  }
}

$summary = [ordered]@{
  generated = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  checked_tracked_only = [bool]$CheckTrackedOnly
  league_count = @($items).Count
  leagues_with_issues = $leaguesWithIssues
  total_missing_matches = $missingTotal
  all_ok = ($leaguesWithIssues -eq 0)
  leagues = @($items)
}

$outPath = Join-Path (Join-Path $PSScriptRoot '..') $OutFile
$outDir = Split-Path -Parent $outPath
if (-not (Test-Path -LiteralPath $outDir)) {
  New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
Save-Json -o $summary -p $outPath

Write-Host ("Validation wrote: {0}" -f $outPath)
Write-Host ("Checked leagues: {0} | issues: {1} | missing cache files: {2}" -f $summary.league_count, $summary.leagues_with_issues, $summary.total_missing_matches)

if ($FailOnMissing -and -not $summary.all_ok) {
  throw "League data validation failed: missing data detected."
}

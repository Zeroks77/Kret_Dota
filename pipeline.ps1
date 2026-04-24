<#
.SYNOPSIS
  Unified Kret Dota pipeline — single entry point for all data operations.

.DESCRIPTION
  Replaces the previous multi-script setup. Run with -Steps to select phases:

    full      = fetch + discover + leagues + validate + wards + monthly + publish + cleanup + legacy-clean  (default)
    rerun-all = hard refresh (force fetch + parse + full rebuild + validate + publish + cleanup + legacy-clean)
    fetch     = Download OpenDota constants + match details + parse requests
    discover  = Auto-discover new Tier 1/2 pro leagues from OpenDota
    leagues   = Rebuild all league reports (aggregation)
    validate  = Validate league report + cache completeness
    wards     = Recompute ward analysis for all leagues
    monthly   = Generate last-full-month wrapper page
    patch     = Generate current-patch wrapper page
    publish   = Publish docs/api/v1/ from data/
    user      = Generate a user report (requires -UserName, -UserAccountId)
    cleanup   = Remove expired user reports
    legacy-clean = Remove old published legacy data and rebuild docs/reports.json
    last30    = Regenerate last-30-days wrapper

  API key:
    Local:  create .env at repo root with OPENDOTA_API_KEY=your_key
    CI:     set OPENDOTA_API_KEY as a GitHub repository variable/secret
    Without key: 60 req/min, 3000/day.  With key: 3000 req/min, unlimited.

.EXAMPLE
  # Full pipeline (local dev):
  pwsh ./pipeline.ps1

  # Just fetch new data:
  pwsh ./pipeline.ps1 -Steps fetch

  # Fetch + rebuild leagues:
  pwsh ./pipeline.ps1 -Steps fetch,leagues

  # Generate user report:
  pwsh ./pipeline.ps1 -Steps user -UserName "Yatoro" -UserAccountId 321580662

  # CI daily run:
  pwsh ./pipeline.ps1 -Steps fetch,discover,leagues,wards,publish,cleanup
#>

param(
  [ValidateSet('full','rerun-all','fetch','discover','leagues','validate','wards','monthly','patch','publish','user','cleanup','last30','legacy-clean')]
  [string[]]$Steps = @('full'),

  # ---------- API keys (auto-loaded from .env / env vars) ----------
  [string]$OpenDotaApiKey,
  [string]$SteamApiKey,

  # ---------- Fetch options ----------
  [switch]$DiscoverViaSteam,
  [switch]$DiscoverViaOpenDota,
  [switch]$DiscoverViaTeams,
  [switch]$RequestParse,
  [int]$MaxParseRequests = 50,
  [switch]$ForceRefetch,

  # ---------- League options ----------
  [string]$LeagueName,               # For single league rebuild
  [switch]$SkipMatchesIfCached,
  [switch]$IncludeTier2,
  [bool]$TrackOnlyCompleted = $true,
  [int]$CompletedGraceDays = 10,
  [switch]$FailOnValidation,

  # ---------- Monthly / Last30 ----------
  [switch]$LastFullMonth,
  [int]$Year,
  [int]$Month,
  [int]$RangeDays = 30,

  # ---------- User report ----------
  [string]$UserName,
  [long]$UserAccountId,
  [int]$UserRangeDays = 30,
  [int]$UserPersistDays = 5,

  # ---------- General ----------
  [switch]$DryRun,
  [switch]$VerboseLog
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Ensure TLS 1.2
try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 } catch {}

# ---------- Load shared library ----------
. "$PSScriptRoot/scripts/lib/common.ps1"

# ---------- Initialize API keys ----------
# Allow passing via param (overrides env)
if (-not [string]::IsNullOrWhiteSpace($OpenDotaApiKey)) {
  $env:OPENDOTA_API_KEY = $OpenDotaApiKey
}
if (-not [string]::IsNullOrWhiteSpace($SteamApiKey)) {
  $env:STEAM_API_KEY = $SteamApiKey
}
Initialize-ApiKeys

# ---------- Expand composite modes into ordered step list ----------
$allSteps = @('fetch','discover','leagues','validate','wards','monthly','publish','cleanup','legacy-clean')
if ($Steps.Count -eq 1 -and $Steps[0] -eq 'full') {
  $Steps = $allSteps
}
if ($Steps.Count -eq 1 -and $Steps[0] -eq 'rerun-all') {
  $ForceRefetch = $true
  $RequestParse = $true
  if ($MaxParseRequests -lt 999999) { $MaxParseRequests = 999999 }
  $SkipMatchesIfCached = $false
  $Steps = $allSteps
}

$pipelineStart = Get-Date
$repoRoot = Get-RepoRoot
$dataDir  = Get-DataPath
$docsDir  = Get-DocsPath
$scriptsDir = Join-Path $repoRoot 'scripts'

Write-Host "`n=== Kret Dota Pipeline ===" -ForegroundColor Cyan
Write-Host "Steps: $($Steps -join ', ')"
Write-Host "Repo:  $repoRoot"
Write-Host ""

function Get-Unix([datetime]$dt) {
  return [int][DateTimeOffset]::new($dt.ToUniversalTime()).ToUnixTimeSeconds()
}

function Get-MonthLabel([datetime]$dt) {
  return $dt.ToString('MMMM yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Update-ReportsIndexFromSources {
  param([string]$DataDir, [string]$DocsDir)

  $items = @()

  # League entries => league_dynamic.html?slug=<slug>
  $leagueRoot = Join-Path $DataDir 'league'
  if (Test-Path -LiteralPath $leagueRoot) {
    $leagueDirs = Get-ChildItem -LiteralPath $leagueRoot -Directory | Sort-Object Name
    foreach ($d in $leagueDirs) {
      $slug = $d.Name
      $repPath = Join-Path $d.FullName 'report.json'
      if (-not (Test-Path -LiteralPath $repPath)) { continue }
      $rep = Read-JsonFile $repPath
      if (-not $rep) { continue }

      $name = $null
      try { $name = '' + $rep.league.name } catch {}
      if ([string]::IsNullOrWhiteSpace($name)) { $name = $slug }

      $fromTs = 0
      try { $fromTs = [int]$rep.league.from } catch {}
      if ($fromTs -le 0) { try { $fromTs = [int]$rep.generated } catch {} }
      if ($fromTs -le 0) { $fromTs = Get-Unix (Get-Date) }

      $year = (Get-Date -Date ([DateTimeOffset]::FromUnixTimeSeconds($fromTs).UtcDateTime)).Year
      $timeIso = ([DateTimeOffset]::FromUnixTimeSeconds($fromTs).UtcDateTime).ToString('yyyy-MM-ddTHH:mm:ssZ')

      $items += [pscustomobject]@{
        title = $name
        href  = "league_dynamic.html?slug=$slug"
        group = 'league'
        time  = $timeIso
        sort  = "$year-$slug"
      }
    }
  }

  # Monthly entries => dynamic.html?from=<ts>&to=<ts>
  $matchesRoot = Join-Path $DataDir 'matches'
  if (Test-Path -LiteralPath $matchesRoot) {
    $shards = Get-ChildItem -LiteralPath $matchesRoot -Filter '*.json' | Sort-Object Name
    foreach ($s in $shards) {
      if ($s.BaseName -notmatch '^(\d{4})-(\d{2})$') { continue }
      $y = [int]$Matches[1]
      $m = [int]$Matches[2]
      if ($m -lt 1 -or $m -gt 12) { continue }

      $from = Get-Date -Date ("{0:D4}-{1:D2}-01T00:00:00Z" -f $y, $m)
      $to = $from.AddMonths(1)
      $fromTs = Get-Unix $from
      $toTs = Get-Unix $to
      $label = "$(Get-MonthLabel $from)"

      $items += [pscustomobject]@{
        title = $label
        href  = "dynamic.html?from=$fromTs&to=$toTs&tab=highlights&lock=1"
        group = 'monthly'
        time  = $to.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        sort  = ('{0:D4}-{1:D2}' -f $y, $m)
      }
    }
  }

  $sorted = @($items | Sort-Object -Property { $_.time } -Descending)
  $reportsPath = Join-Path $DocsDir 'reports.json'
  Save-Json -o ([ordered]@{ items = $sorted }) -p $reportsPath
  Write-Host "  Rebuilt reports index: $reportsPath ($(@($sorted).Count) entries)"
}

function Remove-LegacyPublishedData {
  param([string]$DocsDir)

  $targets = @(
    (Join-Path $DocsDir 'league/2025'),
    (Join-Path $DocsDir 'data')
  )

  # Remove legacy monthly wrapper folders (e.g. 2025-August-Report)
  if (Test-Path -LiteralPath $DocsDir) {
    $legacyMonthly = Get-ChildItem -LiteralPath $DocsDir -Directory | Where-Object { $_.Name -match '^\d{4}-[A-Za-z]+-Report$' }
    foreach ($d in $legacyMonthly) { $targets += $d.FullName }
  }

  foreach ($t in $targets | Select-Object -Unique) {
    if (Test-Path -LiteralPath $t) {
      Remove-Item -LiteralPath $t -Recurse -Force
      Write-Host "  Removed legacy path: $t"
    }
  }

  $legacyLeagueRoot = Join-Path $DocsDir 'league'
  if (Test-Path -LiteralPath $legacyLeagueRoot) {
    $remaining = @(Get-ChildItem -LiteralPath $legacyLeagueRoot -Force -ErrorAction SilentlyContinue)
    if ($remaining.Count -eq 0) {
      Remove-Item -LiteralPath $legacyLeagueRoot -Force
      Write-Host "  Removed empty legacy path: $legacyLeagueRoot"
    }
  }
}

# ============================================================
# STEP: fetch — Download constants + match details from OpenDota
# ============================================================
if ('fetch' -in $Steps) {
  Write-Step 'FETCH — OpenDota data'
  $fetchStart = Get-Date

  $fetchArgs = @(
    '-NoProfile', '-File', (Join-Path $scriptsDir 'fetch_opendota_data.ps1'),
    '-Mode', 'full',
    '-LeagueOnly', $true
  )
  if ($DiscoverViaSteam)    { $fetchArgs += @('-DiscoverViaSteam', $true) }
  if ($DiscoverViaOpenDota) { $fetchArgs += @('-DiscoverViaOpenDota', $true) }
  if ($DiscoverViaTeams)    { $fetchArgs += @('-DiscoverViaTeams', $true) }
  if ($RequestParse)        { $fetchArgs += @('-RequestParse:$true', '-MaxParseRequests', "$MaxParseRequests") }
  if ($ForceRefetch)        { $fetchArgs += '-ForceRefetch:$true' }

  & pwsh @fetchArgs
  Write-Host "  Fetch completed in $(Format-Duration $fetchStart)" -ForegroundColor Green
}

# ============================================================
# STEP: discover — Auto-discover new Tier 1/2 pro leagues
# ============================================================
if ('discover' -in $Steps) {
  Write-Step 'DISCOVER — Pro league auto-discovery'
  $discStart = Get-Date

  $discArgs = @(
    '-NoProfile', '-File', (Join-Path $scriptsDir 'discover_proleagues.ps1'),
    '-RefreshTrackedGroups',
    '-TrackOnlyCompleted', "$(if($TrackOnlyCompleted){1}else{0})",
    '-CompletedGraceDays', "$CompletedGraceDays"
  )
  if ($IncludeTier2) { $discArgs += '-IncludeTier2' }
  if ($SkipMatchesIfCached) { $discArgs += '-SkipMatchesIfCached' }
  if ($DryRun) {
    # In dry-run, replace -AutoTrack with -DryRun
    $discArgs = @(
      '-NoProfile', '-File', (Join-Path $scriptsDir 'discover_proleagues.ps1'),
      '-DryRun'
    )
  }

  & pwsh @discArgs
  Write-Host "  Discovery completed in $(Format-Duration $discStart)" -ForegroundColor Green
}

# ============================================================
# STEP: leagues — Rebuild league reports
# ============================================================
if ('leagues' -in $Steps) {
  Write-Step 'LEAGUES — Rebuild league reports'
  $leaguesStart = Get-Date

  if (-not [string]::IsNullOrWhiteSpace($LeagueName)) {
    # Single league
    $lArgs = @(
      '-NoProfile', '-File', (Join-Path $scriptsDir 'create_league_report.ps1'),
      '-LeagueName', $LeagueName
    )
    if ($SkipMatchesIfCached) { $lArgs += '-SkipMatchesIfCached' }
    if ($VerboseLog)          { $lArgs += '-VerboseLog' }
    & pwsh @lArgs
  } else {
    # All leagues
    $leagueDir = Join-Path $dataDir 'league'
    if (Test-Path -LiteralPath $leagueDir) {
      $dirs = Get-ChildItem -LiteralPath $leagueDir -Directory | Sort-Object Name
      $ok = 0; $skip = 0; $fail = 0
      foreach ($d in $dirs) {
        $slug = $d.Name
        $reportPath = Join-Path $d.FullName 'report.json'
        $rep = Read-JsonFile $reportPath
        $name = $null
        if ($rep -and $rep.league -and $rep.league.name) { $name = '' + $rep.league.name }
        if ([string]::IsNullOrWhiteSpace($name)) {
          Write-Host "  [skip] $slug — no report.json with league name" -ForegroundColor Yellow
          $skip++; continue
        }
        Write-Host "  [run ] $name (slug: $slug)" -ForegroundColor Cyan
        try {
          $lArgs = @(
            '-NoProfile', '-File', (Join-Path $scriptsDir 'create_league_report.ps1'),
            '-LeagueName', $name
          )
          if ($SkipMatchesIfCached) { $lArgs += '-SkipMatchesIfCached' }
          if ($VerboseLog)          { $lArgs += '-VerboseLog' }
          & pwsh @lArgs
          $ok++
        } catch {
          Write-Host "  [fail] $name`: $($_.Exception.Message)" -ForegroundColor Red
          $fail++
        }
      }
      Write-Host "  Leagues: ok=$ok, skipped=$skip, failed=$fail" -ForegroundColor Green
    } else {
      Write-Host "  No leagues found in $leagueDir" -ForegroundColor Yellow
    }
  }
  Write-Host "  Leagues completed in $(Format-Duration $leaguesStart)" -ForegroundColor Green
}

# ============================================================
# STEP: validate — Validate league data completeness
# ============================================================
if ('validate' -in $Steps) {
  Write-Step 'VALIDATE — League data completeness'
  $validateStart = Get-Date

  $vArgs = @(
    '-NoProfile', '-File', (Join-Path $scriptsDir 'validate_league_data.ps1'),
    '-CheckTrackedOnly'
  )
  if ($FailOnValidation) { $vArgs += '-FailOnMissing' }

  & pwsh @vArgs
  Write-Host "  Validation completed in $(Format-Duration $validateStart)" -ForegroundColor Green
}

# ============================================================
# STEP: wards — Recompute ward analysis for all leagues
# ============================================================
if ('wards' -in $Steps) {
  Write-Step 'WARDS — Ward spot analysis'
  $wardsStart = Get-Date

  $leagueDir = Join-Path $dataDir 'league'
  if (Test-Path -LiteralPath $leagueDir) {
    $dirs = Get-ChildItem -LiteralPath $leagueDir -Directory | Sort-Object Name
    foreach ($d in $dirs) {
      $slug = $d.Name
      $matchesFile = Join-Path $d.FullName 'matches.json'
      if (-not (Test-Path -LiteralPath $matchesFile)) {
        Write-Host "  [skip] $slug — no matches.json" -ForegroundColor Yellow
        continue
      }
      Write-Host "  [run ] Ward analysis: $slug" -ForegroundColor Cyan
      try {
        & pwsh -NoProfile -File (Join-Path $scriptsDir 'analyze_ward_spots.ps1') `
          -LeagueSlug $slug `
          -LeaguePath $d.FullName
      } catch {
        Write-Host "  [fail] $slug`: $($_.Exception.Message)" -ForegroundColor Red
      }
    }
  }
  Write-Host "  Wards completed in $(Format-Duration $wardsStart)" -ForegroundColor Green
}

# ============================================================
# STEP: monthly — Generate last-full-month wrapper
# ============================================================
if ('monthly' -in $Steps) {
  Write-Step 'MONTHLY — Month report wrapper'
  $monthlyStart = Get-Date

  $mArgs = @(
    '-NoProfile', '-File', (Join-Path $scriptsDir 'create_dynamic_reports.ps1'),
    '-GenerateMonthly'
  )
  if ($LastFullMonth -or ('full' -in $allSteps)) { $mArgs += '-LastFullMonth' }
  if ($Year)  { $mArgs += @('-Year', $Year) }
  if ($Month) { $mArgs += @('-Month', $Month) }

  & pwsh @mArgs
  Write-Host "  Monthly completed in $(Format-Duration $monthlyStart)" -ForegroundColor Green
}

# ============================================================
# STEP: patch — Generate current-patch wrapper
# ============================================================
if ('patch' -in $Steps) {
  Write-Step 'PATCH — Patch report wrapper'
  & pwsh -NoProfile -File (Join-Path $scriptsDir 'create_dynamic_reports.ps1') -GeneratePatch
}

# ============================================================
# STEP: publish — Build docs/api/v1/
# ============================================================
if ('publish' -in $Steps) {
  Write-Step 'PUBLISH — API surface (docs/api/v1/)'
  $pubStart = Get-Date

  & pwsh -NoProfile -File (Join-Path $scriptsDir 'publish_api.ps1')
  & pwsh -NoProfile -File (Join-Path $scriptsDir 'precompute_dynamic_stats.ps1')
  Write-Host "  Publish completed in $(Format-Duration $pubStart)" -ForegroundColor Green
}

# ============================================================
# STEP: user — Generate a user report
# ============================================================
if ('user' -in $Steps) {
  Write-Step 'USER — User report'

  if ([string]::IsNullOrWhiteSpace($UserName) -or $UserAccountId -le 0) {
    throw 'User report requires -UserName and -UserAccountId parameters.'
  }

  $uArgs = @(
    '-NoProfile', '-File', (Join-Path $scriptsDir 'create_user_report.ps1'),
    '-Name', $UserName,
    '-AccountId', $UserAccountId,
    '-RangeDays', $UserRangeDays,
    '-PersistDays', $UserPersistDays
  )
  & pwsh @uArgs
}

# ============================================================
# STEP: cleanup — Remove expired user reports
# ============================================================
if ('cleanup' -in $Steps) {
  Write-Step 'CLEANUP — Prune expired user reports'
  & pwsh -NoProfile -File (Join-Path $scriptsDir 'create_user_report.ps1') -Cleanup -PersistDays $UserPersistDays
}

# ============================================================
# STEP: legacy-clean — Remove old published wrappers/data and rebuild reports index
# ============================================================
if ('legacy-clean' -in $Steps) {
  Write-Step 'LEGACY-CLEAN — Remove old published data and rebuild reports index'
  Remove-LegacyPublishedData -DocsDir $docsDir
  Update-ReportsIndexFromSources -DataDir $dataDir -DocsDir $docsDir
}

# ============================================================
# STEP: last30 — Regenerate last-30-days wrapper
# ============================================================
if ('last30' -in $Steps) {
  Write-Step 'LAST30 — Last N days wrapper'

  $now = (Get-Date).ToUniversalTime()
  $toUnix   = [int][math]::Floor([datetimeoffset]::new($now).ToUnixTimeSeconds())
  $fromUnix = [int][math]::Floor([datetimeoffset]::new($now.AddDays(-[double]$RangeDays)).ToUnixTimeSeconds())
  $query = "?from=$fromUnix&to=$toUnix&tab=highlights&lock=1"

  # Append map + league filters
  try {
    $maps = Read-JsonFile (Join-Path $dataDir 'maps.json')
    if ($maps -and $maps.current) { $query += "&map=$($maps.current)" }
  } catch {}
  try {
    $info = Read-JsonFile (Join-Path $dataDir 'info.json')
    if ($info -and $info.league_id) { $query += "&league=$($info.league_id)" }
  } catch {}

  Write-DotaWrapper -OutDir (Split-Path (Join-Path $docsDir 'last-30-days.html')) `
    -Title "Last $RangeDays Days Report" `
    -IframeSrc "./dynamic.html$query" `
    -BackLink './index.html'

  # Also write the flat HTML for backward compat
  $wrapperHtml = @"
<!doctype html>
<html lang='en'>
<head>
<meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>Last $RangeDays Days Report</title>
<link rel='stylesheet' href='css/dota-theme.css'>
<style>
  body{margin:0;height:100vh;display:flex;flex-direction:column;position:relative;z-index:1}
  .bar{display:flex;justify-content:space-between;align-items:center;padding:10px 16px;border-bottom:1px solid var(--border);background:rgba(200,170,110,.02)}
  .bar-title{font-weight:700;color:var(--gold-light)}
  iframe{border:0;flex:1;width:100%}
</style>
</head>
<body>
  <div class='bar'>
    <div class='bar-title'>Last $RangeDays Days Report</div>
    <a style='color:var(--gold);text-decoration:none;font-size:13px' href='./index.html'>&#8592; Back</a>
  </div>
  <iframe src="./dynamic.html$query" loading="eager" referrerpolicy="no-referrer"></iframe>
</body>
</html>
"@
  $outPath = Join-Path $docsDir 'last-30-days.html'
  New-ParentDirectory $outPath
  Set-Content -LiteralPath $outPath -Value $wrapperHtml -Encoding UTF8
  Write-Host "  Wrote $outPath"
}

# ============================================================
# Done
# ============================================================
$totalTime = Format-Duration $pipelineStart
Write-Host "`n=== Pipeline completed in $totalTime ===" -ForegroundColor Green

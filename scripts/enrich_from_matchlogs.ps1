<#!
.SYNOPSIS
  Enrich matches using existing OpenDota match logs (no replay parsing required).

.DESCRIPTION
  Reads cached OpenDota match JSON files (players[].purchase_log, obs_log/sen_log, *_left_log, picks_bans, etc.)
  and produces per-match enrichment JSON with derived metrics like ward lifetimes and item first-purchase timings.

  Output is written to data/enriched/matches/<match_id>.json (by default).

.PARAMETER CacheMatchesDir
  Path to directory containing cached OpenDota match JSON files, e.g. data/cache/OpenDota/matches.

.PARAMETER OutDir
  Directory where enriched per-match JSON files will be written.

.PARAMETER Limit
  Optional maximum number of matches to process.

.PARAMETER MatchIds
  Optional explicit list of match IDs to process. If omitted, all *.json under CacheMatchesDir will be processed.

.EXAMPLE
  pwsh -File scripts/enrich_from_matchlogs.ps1 -CacheMatchesDir data/cache/OpenDota/matches -OutDir data/enriched/matches -Limit 100

#>

throw "Deprecated: This script is no longer supported. Use scripts/ingest_batch.ps1 with your own replay parser instead."

param(
  [Parameter(Mandatory=$true)]
  [string]$CacheMatchesDir,

  [Parameter(Mandatory=$true)]
  [string]$OutDir,

  [int]$Limit = 0,

  [long[]]$MatchIds
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Ensure-Directory {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

function Get-MatchFiles {
  param([string]$Dir, [long[]]$Ids)
  if ($Ids -and $Ids.Count -gt 0) {
    foreach ($id in $Ids) {
      $p = Join-Path $Dir ("$id.json")
      if (Test-Path -LiteralPath $p) { Get-Item -LiteralPath $p } else { Write-Warning "Missing cached match JSON: $p" }
    }
  } else {
    Get-ChildItem -LiteralPath $Dir -Filter *.json -File | Sort-Object Name
  }
}

function Index-FirstItemPurchases {
  param($players)
  $res = @{}
  if (-not $players) { return $res }
  foreach ($p in $players) {
    $aid = $p.account_id
    $firstMap = @{}
    $logs = $p.purchase_log
    if ($logs) {
      foreach ($ev in $logs) {
        $item = [string]$ev.key
        if (-not $item -or $item -eq '') { continue }
        if (-not $firstMap.ContainsKey($item)) { $firstMap[$item] = [int]$ev.time }
      }
    }
    $res[[string]$aid] = @()
    foreach ($k in $firstMap.Keys) {
      $res[[string]$aid] += @{ item = $k; time = $firstMap[$k] }
    }
  }
  return $res
}

function Build-WardEvents {
  param($players)
  $observer = @()
  $sentry = @()
  if (-not $players) { return @{ observer=@(); sentry=@() } }
  foreach ($p in $players) {
    $aid = $p.account_id
    # Observers
    if ($p.obs_log) {
      foreach ($ev in $p.obs_log) {
        $observer += [pscustomobject]@{
          owner_aid = $aid
          x = $ev.x; y = $ev.y; time = [int]$ev.time
          removed_at = $null
          lifetime = $null
        }
      }
    }
    if ($p.obs_left_log) {
      # naive pairing by proximity of x/y/time
      foreach ($lv in $p.obs_left_log) {
        $lx = $lv.x; $ly = $lv.y; $lt = [int]$lv.time
        # find closest unmatched placement within reasonable radius & time window
        $idx = -1; $best = 1e9
        for ($i=0; $i -lt $observer.Count; $i++) {
          $o = $observer[$i]
          if ($o.removed_at) { continue }
          $dt = [math]::Abs(($lt) - ($o.time))
          $dx = [math]::Abs(($lx) - ($o.x))
          $dy = [math]::Abs(($ly) - ($o.y))
          $score = $dt + ($dx*1.0) + ($dy*1.0)
          if ($score -lt $best) { $best = $score; $idx = $i }
        }
        if ($idx -ge 0) {
          $observer[$idx].removed_at = $lt
          $observer[$idx].lifetime = $lt - $observer[$idx].time
        }
      }
    }
    # Sentries
    if ($p.sen_log) {
      foreach ($ev in $p.sen_log) {
        $sentry += [pscustomobject]@{
          owner_aid = $aid
          x = $ev.x; y = $ev.y; time = [int]$ev.time
          removed_at = $null
          lifetime = $null
        }
      }
    }
    if ($p.sen_left_log) {
      foreach ($lv in $p.sen_left_log) {
        $lx = $lv.x; $ly = $lv.y; $lt = [int]$lv.time
        $idx = -1; $best = 1e9
        for ($i=0; $i -lt $sentry.Count; $i++) {
          $o = $sentry[$i]
          if ($o.removed_at) { continue }
          $dt = [math]::Abs(($lt) - ($o.time))
          $dx = [math]::Abs(($lx) - ($o.x))
          $dy = [math]::Abs(($ly) - ($o.y))
          $score = $dt + ($dx*1.0) + ($dy*1.0)
          if ($score -lt $best) { $best = $score; $idx = $i }
        }
        if ($idx -ge 0) {
          $sentry[$idx].removed_at = $lt
          $sentry[$idx].lifetime = $lt - $sentry[$idx].time
        }
      }
    }
  }
  return @{ observer = $observer; sentry = $sentry }
}

function New-Enrichment {
  param($matchObj)
  $players = $matchObj.players
  $eid = $matchObj.match_id
  $itemFirst = Index-FirstItemPurchases -players $players
  $wards = Build-WardEvents -players $players
  $campFarm = Build-CampsAndFarming -players $players
  $now = [DateTime]::UtcNow.ToString('o')
  return [pscustomobject]@{
    match_id = $eid
    enriched = @{
      item_first_purchase = $itemFirst
      wards = $wards
      camps = $campFarm.camps
      farming = $campFarm.farming
      # placeholders for future replay-only metrics
      stacks = @()    # TODO: replay-based
      smokes = @()    # TODO: replay-based
      objectives = @()# TODO: replay-based
    }
    meta = @{
      source = 'opendota-logs'
      generated_at = $now
    }
  }
}

# Build per-player camps and farming metrics from OpenDota player objects
function Build-CampsAndFarming {
  param($players)
  $camps = @{}
  $farming = @{}
  foreach($p in ($players | Where-Object { $_ })){
    $aid = [string]$p.account_id
    if(-not $aid) { continue }
    $neutral_kills = [int]($p.neutral_kills)
    $lane_kills = [int]($p.lane_kills)
    $ancient_kills = 0
    if($p.killed){
      $ancient_kills = ($p.killed.PSObject.Properties | Where-Object { $_.Name -like '*ancient*' } | ForEach-Object { [int]$_.Value } | Measure-Object -Sum).Sum
      if(-not $ancient_kills) { $ancient_kills = 0 }
    }
    $stacks = [int]($p.camps_stacked)
    $blocked = $null # Not available from OpenDota logs reliably
    $camps[$aid] = @{ stacked = $stacks; blocked = $blocked; farmed = @{ neutral_kills=$neutral_kills; lane_kills=$lane_kills; ancient_kills=$ancient_kills } }

    # Farming patterns & preferences
    $lh10 = $null; $lh20 = $null; $dn10 = $null
    try { if($p.lh_t -and $p.lh_t.Count -gt 10) { $lh10 = [int]$p.lh_t[10] } } catch {}
    try { if($p.lh_t -and $p.lh_t.Count -gt 20) { $lh20 = [int]$p.lh_t[20] } } catch {}
    try { if($p.dn_t -and $p.dn_t.Count -gt 10) { $dn10 = [int]$p.dn_t[10] } } catch {}
    $gpm = $p.gold_per_min
    $xpm = $p.xp_per_min
    $ratio = $null
    if(($neutral_kills + $lane_kills) -gt 0){ $ratio = [math]::Round($neutral_kills / ($neutral_kills + $lane_kills), 3) }
    $pref = $null
    if($ratio -ne $null){
      if($ratio -gt 0.6){ $pref = 'neutral' }
      elseif($ratio -lt 0.4){ $pref = 'lane' }
      else { $pref = 'mixed' }
    }
    $farming[$aid] = @{ lh10 = $lh10; lh20 = $lh20; dn10 = $dn10; gpm = $gpm; xpm = $xpm; neutral_vs_lane_ratio = $ratio; creep_preference = $pref }
  }
  return @{ camps=$camps; farming=$farming }
}

Write-Host "[enrich] Cache: $CacheMatchesDir"
Write-Host "[enrich] OutDir: $OutDir"
Ensure-Directory -Path $OutDir

$files = Get-MatchFiles -Dir $CacheMatchesDir -Ids $MatchIds
if ($Limit -gt 0) { $files = $files | Select-Object -First $Limit }

$n=0
foreach ($f in $files) {
  try {
    $json = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if (-not $json) { continue }
    $mid = $json.match_id
    if (-not $mid) { Write-Warning "No match_id in $($f.Name)"; continue }
    $outPath = Join-Path $OutDir ("$mid.json")
    $enr = New-Enrichment -matchObj $json
    $enr | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $outPath -Encoding UTF8
    $n++
  } catch {
    Write-Warning "Failed $($f.Name): $($_.Exception.Message)"
  }
}

Write-Host "[enrich] Done. Wrote $n files to $OutDir"

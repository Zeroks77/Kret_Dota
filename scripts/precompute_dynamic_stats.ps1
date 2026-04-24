<#
.SYNOPSIS
  Pre-compute Match Averages + item rankings for the canned dynamic-viewer
  ranges (30 / 60 / 120 days, last patch, all time) so the viewer can render
  large ranges instantly without aggregating 400+ cached match details client-side.

.OUTPUTS
  docs/api/v1/stats/dynamic.json
    {
      "updated":   <unix>,
      "patch":     "7.41",
      "patch_at":  <unix>,
      "ranges": {
        "30":    { ... },
        "60":    { ... },
        "120":   { ... },
        "patch": { ... },
        "all":   { ... }
      }
    }

  Each range entry:
    {
      total_matches, considered_matches,
      avg_duration, first_blood_time, first_roshan_time, first_tormentor_time,
      avg_kills, avg_towers, radiant_winrate,
      from_unix, to_unix,
      top_items:   [ { key, name, count }, ... ],   # top 3 (excl. consumables)
      least_items: [ { key, name, count }, ... ]    # bottom 3 (excl. consumables, count>0)
    }
#>

[CmdletBinding()]
param(
  [int[]] $Days = @(30, 60, 120),
  [int]   $TopN = 20,
  [int]   $LeastN = 20
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')

$repoRoot   = Get-RepoRoot
$dataDir    = Get-DataPath
$docsDir    = Get-DocsPath
$cacheDir   = Join-Path (Get-CachePath) 'matches'
$apiStats   = Join-Path $docsDir 'api/v1/stats'
$patchFile  = Join-Path $docsDir 'api/v1/constants/patch.json'
$itemsFile  = Join-Path $docsDir 'api/v1/constants/items.json'   # optional
if (-not (Test-Path -LiteralPath $apiStats)) { New-Item -ItemType Directory -Path $apiStats -Force | Out-Null }

function Try-ReadJson([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  try { return Read-JsonFile $p } catch { return $null }
}

# ---- 1) Resolve "last patch" boundary -------------------------------------------------
$patchName = $null; $patchUnix = 0
$patchData = Try-ReadJson $patchFile
if ($patchData) {
  try {
    $latest = $patchData | Sort-Object -Property @{ Expression = { [datetime]$_.date }; Descending = $true } | Select-Object -First 1
    if ($latest) {
      $patchName = '' + $latest.name
      $patchUnix = [int][DateTimeOffset]::Parse($latest.date).ToUnixTimeSeconds()
    }
  } catch { $patchName = $null }
}

# ---- 2) Consumable filter (matches viewer fallback list) ------------------------------
$Consumables = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($k in @(
    'tango','tango_single','flask','enchanted_mango','clarity','faerie_spirit','bottle',
    'tpscroll','dust','dust_of_appearance','ward_observer','ward_sentry','ward_dispenser',
    'smoke_of_deceit','cheese','aegis','river_painter','river_painter2','river_painter3',
    'river_painter4','river_painter5','river_painter6','river_painter7',
    'branches'
  )) { [void]$Consumables.Add($k) }

# Optional: pull additional consumables from constants/items.json (qual=consumable / cons=true)
# Also collect components (recipe parts) so they can be excluded from "most/least bought".
# Allowlist: very few items that OpenDota mis-classifies as 'component' but are bought standalone.
# Keep this minimal — anything that's primarily a stat-stick / recipe part should NOT be here.
$ComponentAllowlist = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($k in @(
    'blink','quelling_blade','wind_lace'
  )) { [void]$ComponentAllowlist.Add($k) }
$Components = New-Object 'System.Collections.Generic.HashSet[string]'
# Cheap items (boots, sticks, branches, wards, etc.) clutter the most-bought ranking.
# Anything with known cost < $MinItemCost is excluded; items without known cost rely on the consumable/component sets.
$MinItemCost = 1000
$itemMeta = Try-ReadJson $itemsFile
if ($itemMeta) {
  foreach ($prop in $itemMeta.PSObject.Properties) {
    $m = $prop.Value
    if ($null -eq $m) { continue }
    $isCons = $false
    try { if (('' + $m.qual) -ieq 'consumable') { $isCons = $true } } catch {}
    try { if ([bool]$m.cons -eq $true) { $isCons = $true } } catch {}
    if ($isCons) { [void]$Consumables.Add($prop.Name.ToLowerInvariant()) }
    try {
      $q = ('' + $m.qual).ToLowerInvariant()
      # qual 'component' = explicit recipe part. qual 'secret_shop' = bulk stat-stick (point_booster, mystic_staff, reaver, demon_edge, ultimate_orb, platemail, hyperstone, vitality/energy booster, …) — also pure components for build-up items.
      if (($q -eq 'component' -or $q -eq 'secret_shop') -and -not $ComponentAllowlist.Contains($prop.Name.ToLowerInvariant())) {
        [void]$Components.Add($prop.Name.ToLowerInvariant())
      }
    } catch {}
  }
}

function Get-ItemDisplayName([string]$key) {
  if ($itemMeta -and ($itemMeta.PSObject.Properties.Name -contains $key)) {
    try {
      $dn = '' + $itemMeta.$key.dname
      if ($dn) { return $dn }
    } catch {}
  }
  $words = ($key -replace '_',' ') -split '\s+' | Where-Object { $_ }
  $titled = foreach ($w in $words) {
    if ($w.Length -gt 0) { $w.Substring(0,1).ToUpper() + $w.Substring(1) } else { $w }
  }
  return ($titled -join ' ')
}

# ---- 3) Collect match ids from monthly shards ----------------------------------------
$monthlyDir = Join-Path $dataDir 'matches'
if (-not (Test-Path -LiteralPath $monthlyDir)) {
  throw "Monthly shards directory not found: $monthlyDir"
}

$matchMeta = New-Object 'System.Collections.Generic.List[object]'
foreach ($f in Get-ChildItem -LiteralPath $monthlyDir -Filter '*.json' -File) {
  $rows = Try-ReadJson $f.FullName
  if (-not $rows) { continue }
  foreach ($r in @($rows)) {
    $mid = 0; try { $mid = [int64]$r.match_id } catch {}
    if ($mid -le 0) { continue }
    $st = 0; try { $st = [int64]$r.start_time } catch {}
    $matchMeta.Add([pscustomobject]@{
      match_id    = $mid
      start_time  = $st
      radiant_win = [bool]$r.radiant_win
    })
  }
}
Write-Host ("Loaded {0} match rows from monthly shards." -f $matchMeta.Count)

# ---- 4) Aggregate one range -----------------------------------------------------------
function Aggregate-Range {
  param(
    [Parameter(Mandatory=$true)] $Rows,        # array of meta rows in range
    [int] $FromUnix = 0,
    [int] $ToUnix   = 0
  )
  $durSum = 0; $durN = 0
  $fbSum  = 0; $fbN  = 0
  $rsSum  = 0; $rsN  = 0
  $tmSum  = 0; $tmN  = 0
  $kSum   = 0; $kN   = 0
  $twSum  = 0; $twN  = 0
  $radWins = 0
  $considered = 0
  $purchase = @{}

  foreach ($row in $Rows) {
    $cachePath = Join-Path $cacheDir ("$($row.match_id).json")
    $md = Try-ReadJson $cachePath
    if (-not $md) { continue }
    $considered++

    # Duration
    try { $d = [int]$md.duration; if ($d -gt 0) { $durSum += $d; $durN++ } } catch {}

    # First blood
    try { $fb = [int]$md.first_blood_time; if ($fb -gt 0) { $fbSum += $fb; $fbN++ } } catch {}

    # Iterate objectives once for Roshan + Tormentor (earliest each)
    $firstRosh = 0; $firstTorm = 0
    foreach ($obj in @($md.objectives)) {
      if (-not $obj) { continue }
      $t = '' + $obj.type
      $sec = 0; try { $sec = [int]$obj.time } catch {}
      if ($sec -le 0) { continue }
      if ($t -match '(?i)roshan_kill|CHAT_MESSAGE_ROSHAN_KILL') {
        if ($firstRosh -eq 0 -or $sec -lt $firstRosh) { $firstRosh = $sec }
      }
      $hay = ($t + '|' + ('' + $obj.key) + '|' + ('' + $obj.unit) + '|' + ('' + $obj.subtype)).ToLowerInvariant()
      if ($hay -match 'tormentor|miniboss') {
        if ($firstTorm -eq 0 -or $sec -lt $firstTorm) { $firstTorm = $sec }
      }
    }
    if ($firstRosh -gt 0) { $rsSum += $firstRosh; $rsN++ }
    if ($firstTorm -gt 0) { $tmSum += $firstTorm; $tmN++ }

    # Kills + tower kills + purchases
    $matchKills = 0; $hasKillData = $false
    $matchTowers = 0; $hasTowerData = $false
    foreach ($p in @($md.players)) {
      if (-not $p) { continue }
      try { $kk = [int]$p.kills; $matchKills += $kk; $hasKillData = $true } catch {}
      try {
        $tk = $null
        try { $tk = [int]$p.tower_kills } catch {}
        if ($null -ne $tk) { $matchTowers += $tk; $hasTowerData = $true }
      } catch {}

      foreach ($ev in @($p.purchase_log)) {
        if (-not $ev) { continue }
        $key = ''
        try { $key = ('' + $ev.key).ToLowerInvariant() } catch {}
        if (-not $key) { try { $key = ('' + $ev.item).ToLowerInvariant() } catch {} }
        if (-not $key) { continue }
        if ($Consumables.Contains($key)) { continue }
        if ($Components.Contains($key)) { continue }
        # Cheap-item filter (boots/wand/stick/branches): drop anything below $MinItemCost gold.
        if ($itemMeta -and ($itemMeta.PSObject.Properties.Name -contains $key)) {
          try { $cost = [int]$itemMeta.$key.cost } catch { $cost = 0 }
          if ($cost -gt 0 -and $cost -lt $MinItemCost) { continue }
        }
        if ($purchase.ContainsKey($key)) { $purchase[$key] = $purchase[$key] + 1 }
        else { $purchase[$key] = 1 }
      }
    }
    if ($hasKillData) { $kSum += $matchKills; $kN++ }
    if ($hasTowerData) { $twSum += $matchTowers; $twN++ }

    if ([bool]$md.radiant_win) { $radWins++ }
  }

  $rankedTop = $purchase.GetEnumerator() | Sort-Object -Property @{ Expression = { $_.Value }; Descending = $true }, Key | Select-Object -First $TopN
  $rankedLeast = $purchase.GetEnumerator() | Where-Object { $_.Value -gt 0 } | Sort-Object -Property @{ Expression = { $_.Value }; Descending = $false }, Key | Select-Object -First $LeastN

  $top = @()
  foreach ($e in $rankedTop) {
    $top += [ordered]@{ key = $e.Key; name = (Get-ItemDisplayName $e.Key); count = [int]$e.Value }
  }
  $least = @()
  foreach ($e in $rankedLeast) {
    $least += [ordered]@{ key = $e.Key; name = (Get-ItemDisplayName $e.Key); count = [int]$e.Value }
  }

  return [ordered]@{
    total_matches        = @($Rows).Count
    considered_matches   = $considered
    avg_duration         = if ($durN -gt 0) { [int]([math]::Round($durSum / $durN)) } else { 0 }
    first_blood_time     = if ($fbN  -gt 0) { [int]([math]::Round($fbSum  / $fbN )) } else { 0 }
    first_roshan_time    = if ($rsN  -gt 0) { [int]([math]::Round($rsSum  / $rsN )) } else { 0 }
    first_tormentor_time = if ($tmN  -gt 0) { [int]([math]::Round($tmSum  / $tmN )) } else { 0 }
    avg_kills            = if ($kN   -gt 0) { [math]::Round($kSum / $kN, 1) } else { 0 }
    avg_towers           = if ($twN  -gt 0) { [math]::Round($twSum / $twN, 1) } else { 0 }
    radiant_winrate      = if (@($Rows).Count -gt 0) { [math]::Round([double]$radWins / @($Rows).Count, 3) } else { 0 }
    from_unix            = $FromUnix
    to_unix              = $ToUnix
    top_items            = $top
    least_items          = $least
  }
}

# ---- 5) Build all ranges --------------------------------------------------------------
$nowUnix = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$ranges  = [ordered]@{}

function Filter-Rows([int]$fromUnix, [int]$toUnix) {
  $matchMeta | Where-Object { $_.start_time -ge $fromUnix -and ($toUnix -le 0 -or $_.start_time -le $toUnix) }
}

foreach ($d in $Days) {
  $from = $nowUnix - ($d * 86400)
  Write-Host ("Aggregating range: last {0} days ..." -f $d)
  $rows = @(Filter-Rows $from $nowUnix)
  $ranges["$d"] = Aggregate-Range -Rows $rows -FromUnix $from -ToUnix $nowUnix
}

if ($patchUnix -gt 0) {
  Write-Host ("Aggregating range: since patch {0} ..." -f $patchName)
  $rows = @(Filter-Rows $patchUnix $nowUnix)
  $ranges['patch'] = Aggregate-Range -Rows $rows -FromUnix $patchUnix -ToUnix $nowUnix
}

Write-Host "Aggregating range: all time ..."
$rows = [object[]]$matchMeta.ToArray()
Write-Host ("  rows: " + $rows.Count)
$ranges['all'] = Aggregate-Range -Rows $rows -FromUnix 0 -ToUnix $nowUnix

# ---- 6) Persist -----------------------------------------------------------------------
$payload = [ordered]@{
  updated   = $nowUnix
  patch     = $patchName
  patch_at  = $patchUnix
  ranges    = $ranges
}

$out = Join-Path $apiStats 'dynamic.json'
Save-Json -o $payload -p $out
Write-Host ("Wrote {0}" -f $out)

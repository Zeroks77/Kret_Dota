param(
  [string]$LeagueSlug = '',
  [string]$LeaguePath = '',
  [string]$OutJson = 'data/ward_spots_summary.json',
  [string]$OutCsv = 'data/ward_spots_summary.csv',
  [ValidateSet('', 'early','mid','earlylate','late','superlate')]
  [string]$TimeWindow = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-TimeWindowBounds([string]$tw){
  switch($tw){
    ''          { return @{ min= [double]-1; max=[double]::PositiveInfinity; label='all' } }
    'early'     { return @{ min= 0;    max= 600;  label='0-10m' } }
    'mid'       { return @{ min= 600;  max= 2100; label='10-35m' } }
    'earlylate' { return @{ min= 2100; max= 3000; label='35-50m' } }
    'late'      { return @{ min= 3000; max= 4500; label='50-75m' } }
    'superlate' { return @{ min= 4500; max= [double]::PositiveInfinity; label='75m+' } }
  }
}

function Get-MatchIdList([string]$slug, [string]$path){
  $ids = @()
  $pathsToTry = @()
  if($path -and (Test-Path $path)){
    $pathsToTry += $path
  }
  if($slug){
    $pathsToTry += @(
      (Join-Path -Path 'docs/data/league' -ChildPath (Join-Path $slug 'matches.json')),
      (Join-Path -Path 'docs/league/2025' -ChildPath (Join-Path $slug 'matches.json')),
      (Join-Path -Path 'docs/league/2024' -ChildPath (Join-Path $slug 'matches.json'))
    )
  }
  foreach($p in $pathsToTry){
    if(Test-Path $p){
      try {
        $json = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
        if($json -is [array]){
          $ids += ($json | ForEach-Object { $_.match_id })
        } elseif($json.matches){
          $ids += ($json.matches | ForEach-Object { $_.match_id })
        }
      } catch { Write-Warning ("Failed to read {0}: {1}" -f $p, $($_)) }
    }
  }
  # de-dup & sanitize
  $ids = $ids | Where-Object { $_ } | Select-Object -Unique
  return @($ids)
}

function Median([object[]]$arr){
  if(-not $arr -or $arr.Count -eq 0){ return 0 }
  $s = @($arr | Sort-Object)
  $n = $s.Count
  if($n -eq 0){ return 0 }
  if($n % 2 -eq 1){ return [int]$s[ [int]([math]::Floor($n/2)) ] }
  else { return [int]([math]::Floor( ( [int]$s[$n/2 - 1] + [int]$s[$n/2] ) / 2 )) }
}

$tw = Get-TimeWindowBounds $TimeWindow

# Build target list of match files
$cacheDir = 'data/cache/OpenDota/matches'
if(-not (Test-Path $cacheDir)){ throw "Cache directory not found: $cacheDir" }

$targetIds = @(Get-MatchIdList -slug $LeagueSlug -path $LeaguePath)
$files = @()
if($targetIds -and $targetIds.Count -gt 0){
  $files = $targetIds | ForEach-Object { Join-Path $cacheDir ("$_.json") } | Where-Object { Test-Path $_ }
} else {
  $files = Get-ChildItem -LiteralPath $cacheDir -File -Filter '*.json' | Select-Object -ExpandProperty FullName
}
if(-not $files -or $files.Count -eq 0){ throw "No cached match files found to analyze." }

# Aggregators
$spotCount = @{}
$spotTotalLife = @{}
$spotSamples = @{}
# Detailed samples per spot: list of @{ t=..., life=..., aid=..., side=..., teamId=... }
$spotSamplesDetails = @{}
$spotBySide = @{}

# Sentry aggregates
$senCount = @{}
$senSamples = @{}
$senBySide = @{}
$senByTeam = @{}

[int]$totalPlacements = 0
[int]$filesRead = 0

foreach($file in $files){
  try{
    $data = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
    $filesRead++
  $dur = [int]($data.duration | ForEach-Object { $_ } | Select-Object -First 1)
    if(-not $dur){ $dur = 0 }
    $rid = [int]($data.radiant_team_id | ForEach-Object { $_ } | Select-Object -First 1)
    $did = [int]($data.dire_team_id | ForEach-Object { $_ } | Select-Object -First 1)
    foreach($p in ($data.players)){ if(-not $p){ continue }
      $isRad = $false
      if($p.PSObject.Properties['isRadiant']){ $isRad = [bool]$p.isRadiant }
      elseif($p.PSObject.Properties['is_radiant']){ $isRad = [bool]$p.is_radiant }
      else { $isRad = ([int]$p.player_slot) -lt 128 }
      $side = if($isRad){ 'Radiant' } else { 'Dire' }
      $teamId = if($isRad){ $rid } else { $did }
      $obs = @(); if($p.PSObject.Properties['obs_log']){ $obs = @($p.obs_log) }
      $left = @(); if($p.PSObject.Properties['obs_left_log']){ $left = @($p.obs_left_log) }
      # to match removals, index left by coord then time ascending
      $leftIdx = @{}
      foreach($l in $left){
        $key = "{0},{1}" -f ([int]$l.x), ([int]$l.y)
        if(-not $leftIdx.ContainsKey($key)){ $leftIdx[$key] = New-Object System.Collections.Generic.List[object] }
        $leftIdx[$key].Add(@{ t = [int]$l.time; used = $false })
      }
      # Important: clone Keys to avoid 'collection modified during enumeration' issues on Windows PowerShell
      foreach($k in @($leftIdx.Keys)){
        $leftIdx[$k] = @($leftIdx[$k] | Sort-Object -Property t)
      }

      foreach($o in $obs){
        $t = [int]$o.time
        if(-not ($t -ge $tw.min -and $t -lt $tw.max)) { continue }
        $x = [int]$o.x; $y = [int]$o.y
        $key = "{0},{1}" -f $x, $y
        $life = 0
        if($leftIdx.ContainsKey($key)){
          $arr = $leftIdx[$key]
          $picked = $null
          foreach($ev in $arr){ if(-not $ev.used -and $ev.t -ge $t){ $picked = $ev; break } }
          if($picked){ $life = [int]([math]::Max(0, $picked.t - $t)); $picked.used = $true }
          else { $life = [int]([math]::Max(0, [math]::Min(360, $dur - $t))) }
        } else {
          $life = [int]([math]::Max(0, [math]::Min(360, $dur - $t)))
        }
        if($life -gt 360){ $life = 360 }
        if(-not $spotCount.ContainsKey($key)){ $spotCount[$key] = 0 }
        if(-not $spotTotalLife.ContainsKey($key)){ $spotTotalLife[$key] = 0 }
  if(-not $spotSamples.ContainsKey($key)){ $spotSamples[$key] = New-Object System.Collections.Generic.List[int] }
  if(-not $spotSamplesDetails.ContainsKey($key)){ $spotSamplesDetails[$key] = New-Object System.Collections.Generic.List[object] }
        if(-not $spotBySide.ContainsKey($key)){ $spotBySide[$key] = @{ Radiant = @{ count=0; total=0 }; Dire = @{ count=0; total=0 } } }
        $spotCount[$key] = $spotCount[$key] + 1
        $spotTotalLife[$key] = $spotTotalLife[$key] + $life
  $spotSamples[$key].Add([int]$life)
  # Add detailed sample for viewer (time, lifetime, account id, side, team)
  $aid = [int]($p.account_id | ForEach-Object { $_ } | Select-Object -First 1)
  $sampleObj = @{ t = [int]$t; life = [int]$life; aid = $aid; side = $side; teamId = $teamId }
  $spotSamplesDetails[$key].Add($sampleObj)
        $sideRec = $spotBySide[$key].$side; $sideRec.count = $sideRec.count + 1; $sideRec.total = $sideRec.total + $life
        $totalPlacements++
      }

      # Sentry placements (no lifetime needed for precompute, just counts and samples)
      $sen = @(); if($p.PSObject.Properties['sen_log']){ $sen = @($p.sen_log) }
      foreach($s in $sen){
        $sx = [int]$s.x; $sy = [int]$s.y
        $skey = "{0},{1}" -f $sx, $sy
        if(-not $senCount.ContainsKey($skey)){ $senCount[$skey] = 0 }
        if(-not $senSamples.ContainsKey($skey)){ $senSamples[$skey] = New-Object System.Collections.Generic.List[object] }
        if(-not $senBySide.ContainsKey($skey)){ $senBySide[$skey] = @{ Radiant = @{ count=0 }; Dire = @{ count=0 } } }
        if(-not $senByTeam.ContainsKey($skey)){ $senByTeam[$skey] = @{} }
        $senCount[$skey] = $senCount[$skey] + 1
        $senSamples[$skey].Add(@{ t = [int]$s.time; side=$side; teamId=$teamId; aid = [int]($p.account_id|ForEach-Object { $_ }|Select-Object -First 1) })
        $sb = $senBySide[$skey].$side; $sb.count = $sb.count + 1
        if($teamId){
          $tb = $senByTeam[$skey]
          if(-not $tb.ContainsKey([string]$teamId)){ $tb[[string]$teamId] = @{ count=0 } }
          $tb[[string]$teamId].count = $tb[[string]$teamId].count + 1
        }
      }
    }
  } catch {
    Write-Warning ("Failed to parse {0}: {1}" -f $file, $($_))
  }
}

# Build summary
$items = @()
foreach($key in $spotCount.Keys){
  $parts = $key -split ','
  $x = [int]$parts[0]; $y = [int]$parts[1]
  $count = [int]$spotCount[$key]
  $total = [int]$spotTotalLife[$key]
  $avg = if($count -gt 0){ [int][math]::Round($total / [math]::Max(1,$count)) } else { 0 }
  # Expand the List[int] into an int[] for median calculation
  $samples = @($spotSamples[$key] | ForEach-Object { $_ })
  $median = Median -arr $samples
  $bySide = $spotBySide[$key]
  $samplesArr = @()
  if($spotSamplesDetails.ContainsKey($key)){ $samplesArr = @($spotSamplesDetails[$key] | ForEach-Object { $_ }) }
  $items += [pscustomobject]@{ spot=$key; x=$x; y=$y; count=$count; avgSeconds=$avg; medianSeconds=$median; totalSeconds=$total; bySide=$bySide; samples=$samplesArr }
}

# Sort by count desc then avg desc
$sorted = $items | Sort-Object -Property @{Expression='count'; Descending=$true}, @{Expression='avgSeconds'; Descending=$true}

$summary = [pscustomobject]@{
  analyzedFiles = $filesRead
  placements = $totalPlacements
  uniqueSpots = $items.Count
  timeWindow = $tw.label
  league = $LeagueSlug
  topSpots = ($sorted | Select-Object -First 50)
  spots = $sorted
  sentries = (@($senCount.Keys) | ForEach-Object {
    $parts = $_ -split ','; $sx=[int]$parts[0]; $sy=[int]$parts[1]
    [pscustomobject]@{
      spot = $_
      x = $sx
      y = $sy
      count = [int]$senCount[$_]
      bySide = $senBySide[$_]
      byTeam = $senByTeam[$_]
      samples = @($senSamples[$_] | ForEach-Object { $_ })
    }
  }) | Sort-Object -Property @{Expression='count';Descending=$true}
}

# Ensure output dir exists
$OutJsonDir = Split-Path -Parent $OutJson
$OutCsvDir = Split-Path -Parent $OutCsv
if($OutJsonDir -and -not (Test-Path $OutJsonDir)) { New-Item -ItemType Directory -Path $OutJsonDir -Force | Out-Null }
if($OutCsvDir -and -not (Test-Path $OutCsvDir)) { New-Item -ItemType Directory -Path $OutCsvDir -Force | Out-Null }

# If league provided and no explicit OutJson/Csv passed, write next to league folder
if((($LeagueSlug -and -not [string]::IsNullOrWhiteSpace($LeagueSlug)) -or ($LeaguePath -and -not [string]::IsNullOrWhiteSpace($LeaguePath))) -and -not $PSBoundParameters.ContainsKey('OutJson') -and -not $PSBoundParameters.ContainsKey('OutCsv')){
  $slug = $LeagueSlug
  if(-not $slug -and $LeaguePath){ $slug = Split-Path -Leaf $LeaguePath }
  $targetDir = if($LeaguePath){ $LeaguePath } else { Join-Path 'docs/data/league' $slug }
  if(-not (Test-Path $targetDir)){ New-Item -ItemType Directory -Force -Path $targetDir | Out-Null }
  $OutJson = Join-Path $targetDir 'ward_summary.json'
  $OutCsv = Join-Path $targetDir 'ward_summary.csv'
}

# Write JSON
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutJson -Encoding UTF8

# Write CSV
$csvRows = $sorted | Select-Object spot,x,y,count,avgSeconds,medianSeconds,totalSeconds,
  @{n='radiantCount';e={$_.bySide.Radiant.count}}, @{n='radiantTotal';e={$_.bySide.Radiant.total}},
  @{n='direCount';e={$_.bySide.Dire.count}}, @{n='direTotal';e={$_.bySide.Dire.total}}
$csvRows | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8

Write-Host "Done. Files written:" -ForegroundColor Green
Write-Host " - $OutJson"
Write-Host " - $OutCsv"

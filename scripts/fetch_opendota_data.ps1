param(
  [int]$DelayMs = 1200,
  [int]$MaxRetries = 3,
  [switch]$UpdateConstants,
  [switch]$FetchMatches
)

<#
  Fetches OpenDota constants (heroes, patch) and downloads missing
  match details for IDs referenced in data/matches/*.json (and optional
  data/allgames_parsed.json).

  Output:
   - data/cache/OpenDota/constants/heroes.json
   - data/cache/OpenDota/constants/patch.json
   - data/cache/OpenDota/matches/<match_id>.json

  Notes:
   - Idempotent; re-downloads only when a cache file is missing.
   - Uses conservative throttling (DelayMs) and small retry loop.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepoRoot(){ (Resolve-Path "$PSScriptRoot\.." | Select-Object -ExpandProperty Path) }
function Get-DataPath(){ Join-Path (Get-RepoRoot) 'data' }
function Ensure-Dir([string]$path){ $dir=[System.IO.Path]::GetDirectoryName($path); if($dir -and -not (Test-Path -LiteralPath $dir)){ New-Item -ItemType Directory -Path $dir -Force | Out-Null } }
function Read-JsonFile([string]$path){ if(-not (Test-Path -LiteralPath $path)){ return $null } try{ Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null } }

function Invoke-Json([string]$Method,[string]$Uri){
  $backoff = 600
  for($i=1; $i -le $MaxRetries; $i++){
    try {
      $resp = Invoke-RestMethod -Method $Method -Uri $Uri -Headers @{ 'Accept'='application/json'; 'User-Agent'='kret-dota-fetcher/1.0' } -ErrorAction Stop
      return $resp
    } catch {
      if ($i -ge $MaxRetries) { throw }
      Start-Sleep -Milliseconds $backoff
      $backoff = [Math]::Min($backoff*2, 5000)
    }
  }
}

function Save-Json([object]$obj,[string]$path){ Ensure-Dir $path; ($obj | ConvertTo-Json -Depth 100) | Set-Content -LiteralPath $path -Encoding UTF8 }

function Update-Constants(){
  $data = Get-DataPath
  $constDir = Join-Path $data 'cache/OpenDota/constants'
  if(-not (Test-Path -LiteralPath $constDir)){ New-Item -ItemType Directory -Path $constDir -Force | Out-Null }

  Write-Host 'Fetching OpenDota constants: heroes'
  $heroes = Invoke-Json -Method GET -Uri 'https://api.opendota.com/api/constants/heroes'
  if($heroes){ Save-Json -obj $heroes -path (Join-Path $constDir 'heroes.json'); Set-Content -LiteralPath (Join-Path $data 'heroes.json') -Value (($heroes | ConvertTo-Json -Depth 50)) -Encoding UTF8 }

  Write-Host 'Fetching OpenDota constants: patch'
  $patch = Invoke-Json -Method GET -Uri 'https://api.opendota.com/api/constants/patch'
  if($patch){ Save-Json -obj $patch -path (Join-Path $constDir 'patch.json') }
}

function Get-MatchIdCandidates(){
  $data = Get-DataPath
  $ids = New-Object System.Collections.Generic.HashSet[int64]
  $matchesDir = Join-Path $data 'matches'
  if(Test-Path -LiteralPath $matchesDir){
    Get-ChildItem -LiteralPath $matchesDir -Filter '*.json' | ForEach-Object {
      try {
        $raw = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
        if([string]::IsNullOrWhiteSpace($raw)){ return }
        $json = $raw | ConvertFrom-Json
        if($json -is [System.Collections.IEnumerable]){
          foreach($it in $json){
            try {
              if($it -is [int64] -or $it -is [int]){ [void]$ids.Add([int64]$it) }
              elseif($it -and $it.PSObject.Properties.Name -contains 'match_id') { [void]$ids.Add([int64]$it.match_id) }
            } catch {}
          }
        }
      } catch {}
    }
  }
  $parsed = Join-Path $data 'allgames_parsed.json'
  if(Test-Path -LiteralPath $parsed){
    try {
      $arr = Get-Content -LiteralPath $parsed -Raw -Encoding UTF8 | ConvertFrom-Json
      if($arr -is [System.Collections.IEnumerable]){
        foreach($x in $arr){ try { [void]$ids.Add([int64]$x) } catch {} }
      }
    } catch {}
  }
  $out = New-Object System.Collections.Generic.List[int64]
  foreach($v in $ids){ [void]$out.Add([int64]$v) }
  return ($out.ToArray() | Sort-Object)
}

function Fetch-MissingMatches(){
  $data = Get-DataPath
  $cacheDir = Join-Path $data 'cache/OpenDota/matches'
  if(-not (Test-Path -LiteralPath $cacheDir)){ New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }

  $ids = Get-MatchIdCandidates
  Write-Host ("Found {0} candidate match IDs" -f $ids.Count)

  $i=0
  foreach($id in $ids){
    $i++
    $outFile = Join-Path $cacheDir ("{0}.json" -f $id)
    if(Test-Path -LiteralPath $outFile){ continue }
    Write-Host ("[{0}/{1}] Fetching match {2}" -f $i, $ids.Count, $id)
    try {
      $obj = Invoke-Json -Method GET -Uri ("https://api.opendota.com/api/matches/{0}" -f $id)
      if($obj){ Save-Json -obj $obj -path $outFile }
    } catch {
      Write-Warning ("Failed to fetch match {0}: {1}" -f $id, $_.Exception.Message)
    }
    Start-Sleep -Milliseconds $DelayMs
  }
}

# ===== Main =====
$doConst = ($PSBoundParameters.ContainsKey('UpdateConstants') -and $UpdateConstants) -or (-not $PSBoundParameters.ContainsKey('UpdateConstants'))
$doMatches = ($PSBoundParameters.ContainsKey('FetchMatches') -and $FetchMatches) -or (-not $PSBoundParameters.ContainsKey('FetchMatches'))

if($doConst){ Update-Constants }
if($doMatches){ Fetch-MissingMatches }

Write-Host 'OpenDota data fetch complete.'
param(
  [int]$MaxConcurrency = 3,
  [int]$DelayMs = 800
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-Directory([string]$p){ $d=[System.IO.Path]::GetDirectoryName($p); if($d -and -not (Test-Path $d)){ New-Item -ItemType Directory -Path $d -Force | Out-Null } }

$Root = Resolve-Path "$PSScriptRoot\.." | Select-Object -ExpandProperty Path
$Data = Join-Path $Root 'data'
$Cache = Join-Path $Data 'cache\OpenDota'
$ConstDir = Join-Path $Cache 'constants'
$MatchDir = Join-Path $Cache 'matches'

# Create dirs
$null = New-Item -ItemType Directory -Force -Path $ConstDir, $MatchDir -ErrorAction SilentlyContinue

function Invoke-FetchJson([string]$url){
  try{
    Write-Host "GET $url"
    $r = Invoke-WebRequest -UseBasicParsing -Uri $url -Headers @{ 'Accept'='application/json'; 'User-Agent'='krets-ligascript/3.0 (+https://opendota.com)' } -TimeoutSec 60
    if($r.StatusCode -lt 200 -or $r.StatusCode -ge 300){ return $null }
    $txt = $r.Content
    if([string]::IsNullOrWhiteSpace($txt)){ return $null }
    return $txt
  } catch {
    return $null
  }
}

# Refresh constants (heroes, patch)
$heroesTxt = Invoke-FetchJson 'https://api.opendota.com/api/constants/heroes'
if($heroesTxt){ Initialize-Directory (Join-Path $ConstDir 'heroes.json'); Set-Content -Path (Join-Path $ConstDir 'heroes.json') -Value $heroesTxt -Encoding UTF8 }
$patchTxt = Invoke-FetchJson 'https://api.opendota.com/api/constants/patch'
if($patchTxt){ Initialize-Directory (Join-Path $ConstDir 'patch.json'); Set-Content -Path (Join-Path $ConstDir 'patch.json') -Value $patchTxt -Encoding UTF8 }

# Collect match ids from data/matches/*.json
$matchIdSet = New-Object 'System.Collections.Generic.HashSet[int64]'
Get-ChildItem -Path (Join-Path $Data 'matches') -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
  try{
    $arr = Get-Content -Raw -Path $_.FullName | ConvertFrom-Json -ErrorAction Stop
    foreach($m in $arr){
      $mid = 0
      if($m.PSObject.Properties.Name -contains 'match_id'){ $mid = [int64]$m.match_id }
      elseif($m.PSObject.Properties.Name -contains 'matchId'){ $mid = [int64]$m.matchId }
      if($mid -gt 0){ [void]$matchIdSet.Add($mid) }
    }
  }catch{ }
}

$ids = $matchIdSet | Sort-Object

Write-Host "Found $($ids.Count) match ids from shards."

# Throttled parallel-ish fetch
$sem = [System.Collections.Concurrent.ConcurrentQueue[int64]]::new()
foreach($id in $ids){ $sem.Enqueue($id) }

$jobs = @()
for($i=0; $i -lt $MaxConcurrency; $i++){
  $jobs += Start-Job -ScriptBlock {
    param($q,$matchDir,$delay)
    while($true){
      $id = 0
      $deq = $q.TryDequeue([ref]$id)
      if(-not $deq){ break }
      $outFile = Join-Path $matchDir ("{0}.json" -f $id)
      if(Test-Path -LiteralPath $outFile){ Start-Sleep -Milliseconds 50; continue }
      try{
        $u = "https://api.opendota.com/api/matches/$id"
        $txt = Invoke-WebRequest -UseBasicParsing -Uri $u -Headers @{ 'Accept'='application/json'; 'User-Agent'='krets-ligascript/3.0 (+https://opendota.com)' } -TimeoutSec 60
        if($txt.StatusCode -ge 200 -and $txt.StatusCode -lt 300){ $body=$txt.Content; if($body){ Set-Content -Path $outFile -Value $body -Encoding UTF8 } }
        Start-Sleep -Milliseconds $delay
      }catch{ Start-Sleep -Milliseconds ($delay*2) }
    }
  } -ArgumentList $sem,$MatchDir,$DelayMs
}

Wait-Job -Job $jobs | Out-Null
Receive-Job -Job $jobs | Out-Null
Remove-Job -Job $jobs -Force -ErrorAction SilentlyContinue | Out-Null

Write-Host "Done. Updated constants and fetched any missing match details."

<#!
.SYNOPSIS
  Download Dota 2 replay files (.dem.bz2) for a list of match IDs using a local mapping CSV.

.DESCRIPTION
  Builds Valve replay URLs using (cluster, replay_salt) from a CSV mapping file.
  No OpenDota calls are made. Writes .dem.bz2 files into -OutDir and skips existing files.

.PARAMETER MatchIds
  Explicit list of match IDs to download.

.PARAMETER MatchListFile
  Path to a text file with one match ID per line.

.PARAMETER MappingCsv
  CSV file with headers: match_id,cluster,replay_salt

.PARAMETER OutDir
  Output directory for replays (default: data/replays).

.EXAMPLE
  pwsh -File scripts/download_replays.ps1 -MatchIds 8299260483,8299261932 -MappingCsv scripts/replay_mapping.csv -OutDir data/replays

.EXAMPLE
  pwsh -File scripts/download_replays.ps1 -MatchListFile scripts/sample_match_ids.txt -MappingCsv scripts/replay_mapping.csv -OutDir data/replays

#>

param(
  [object]$MatchIds,
  [string]$MatchListFile,
  [Parameter(Mandatory=$true)]
  [string]$MappingCsv,
  [string]$OutDir = "data/replays"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-DirectoryIfMissing { param([string]$Path) if(-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null } }

function Get-MatchIdsFromFile { param([string]$Path)
  if(-not $Path) { return @() }
  if(-not (Test-Path -LiteralPath $Path)) { throw "MatchListFile not found: $Path" }
  $ids = @()
  Get-Content -LiteralPath $Path | ForEach-Object { $line = $_.Trim(); if($line -match '^[0-9]+$'){ $ids += [long]$line } }
  return $ids
}

function Get-ReplayInfoFromMapping {
  param([string]$CsvPath)
  if(-not (Test-Path -LiteralPath $CsvPath)) {
    # Try resolve relative to repo root
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $alt = Join-Path $repoRoot $CsvPath
    if(Test-Path -LiteralPath $alt){ $CsvPath = $alt } else { throw "MappingCsv not found: $CsvPath" }
  }
  $map = @{}
  $rows = Import-Csv -LiteralPath $CsvPath
  foreach($r in $rows){
    $mid = [string]$r.match_id
    $cl = [int]$r.cluster
    $salt = [int]$r.replay_salt
    if($mid -and $cl -and $salt){ $map[$mid] = @{ cluster=$cl; salt=$salt } }
  }
  return $map
}

function Get-ReplayUrl { param([long]$MatchId, [int]$Cluster, [int]$Salt)
  # Valve CDN URL pattern; http is commonly used. https may or may not work depending on cluster.
  return ("http://replay{0}.valve.net/570/{1}_{2}.dem.bz2" -f $Cluster, $MatchId, $Salt)
}

function Invoke-DownloadReplay { param([long]$MatchId, $Mapping)
  $info = $Mapping[[string]$MatchId]
  if(-not $info) { Write-Warning "No cluster/replay_salt for $MatchId (skip)"; return $false }
  $url = Get-ReplayUrl -MatchId $MatchId -Cluster ([int]$info.cluster) -Salt ([int]$info.salt)
  $outFile = Join-Path $OutDir ("$MatchId.dem.bz2")
  if(Test-Path -LiteralPath $outFile) { Write-Host "[replays] Exists: $MatchId"; return $true }
  try{
    Write-Host "[replays] Download $MatchId from $url"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $outFile -TimeoutSec 600
    return $true
  }catch{
    Write-Warning ("Download failed {0}: {1}" -f $MatchId, $_.Exception.Message)
    return $false
  }
}

$ids = @()
if($MatchIds -ne $null){
  if($MatchIds -is [array]){ $ids += $MatchIds }
  elseif($MatchIds -is [string]){ $ids += ($MatchIds -split ',' | ForEach-Object { $_.Trim() }) }
  else { $ids += $MatchIds }
}
if($MatchListFile) { $ids += (Get-MatchIdsFromFile -Path $MatchListFile) }
$ids = @($ids | Where-Object { $_ -ne $null -and $_ -ne '' } | ForEach-Object { [long]$_ } | Select-Object -Unique)
if(-not $ids -or @($ids).Count -eq 0) { throw "No match IDs provided. Use -MatchIds or -MatchListFile." }

# Normalize OutDir to repo root if relative
if(-not [System.IO.Path]::IsPathRooted($OutDir)){
  $repoRoot = Split-Path $PSScriptRoot -Parent
  $OutDir = Join-Path $repoRoot $OutDir
}
New-DirectoryIfMissing -Path $OutDir
Write-Host "[replays] OutDir: $OutDir"
Write-Host "[replays] MappingCsv: $MappingCsv"
Write-Host "[replays] Count: $(@($ids).Count)"

$mapping = Get-ReplayInfoFromMapping -CsvPath $MappingCsv

$ok=0; $fail=0
foreach($id in $ids) {
  $r = Invoke-DownloadReplay -MatchId $id -Mapping $mapping
  if($r){ $ok++ } else { $fail++ }
}
Write-Host "[replays] Done. ok=$ok, failed=$fail"

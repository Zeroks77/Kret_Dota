<#!
.SYNOPSIS
  Orchestrate replay ingestion in small batches with cleanup.

.DESCRIPTION
  Given a set of match IDs (from a file, JSON, or league folder), this script will:
   1) Resolve match IDs
   2) Download replays for up to -BatchSize (max 5) using mapping CSV
   3) Parse them with the configured parser command
   4) Optionally delete the replay files
   5) Repeat until all matches are processed

.PARAMETER Source
  Type of input: 'list', 'monthly', or 'league'.
  - list: read from -MatchListFile (one ID per line) or -MatchIds
  - monthly: read IDs from data/matches/YYYY-MM.json (array of objects with match_id)
  - league: read from chunks/league/<LEAGUE>/matches.json (array with match_id fields)

.PARAMETER LeagueCode
  Required when -Source league. E.g. 'CDM2025SR'

.PARAMETER Month
  Required when -Source monthly. E.g. '2025-09'

.PARAMETER MatchIds
  Explicit match IDs to run (only for -Source list)

.PARAMETER MatchListFile
  Path to a text file with one match ID per line (only for -Source list)

.PARAMETER MappingCsv
  CSV with columns match_id,cluster,replay_salt

.PARAMETER ParserCmd
  Command template for the parser with {in} and {out} placeholders

.PARAMETER BatchSize
  Number of matches per batch. Will be clamped to 5 to respect CI storage limits.

.PARAMETER KeepReplays
  If set, do not delete .dem/.dem.bz2 after parsing.

.EXAMPLE
  pwsh -File scripts/ingest_batch.ps1 -Source list -MatchListFile scripts/sample_match_ids.txt -MappingCsv scripts/replay_mapping.csv -ParserCmd "node scripts/replay_parser.js --in {in} --out {out}" -BatchSize 5

#>

param(
  [Parameter(Mandatory=$true)]
  [ValidateSet('list','monthly','league')]
  [string]$Source,
  [string]$LeagueCode,
  [string]$Month,
  [long[]]$MatchIds,
  [string]$MatchListFile,
  [Parameter(Mandatory=$true)]
  [string]$MappingCsv,
  [Parameter(Mandatory=$true)]
  [string]$ParserCmd,
  [int]$BatchSize = 5,
  [switch]$KeepReplays,
  [string]$ReplaysDir = "data/replays",
  [string]$OutDir = "data/enriched/matches"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Clamp($v,$min,$max){ if($v -lt $min){ return $min } if($v -gt $max){ return $max } return $v }
$BatchSize = Clamp $BatchSize 1 5

function Read-IdsFromTxt { param([string]$Path)
  if(-not (Test-Path -LiteralPath $Path)) { throw "File not found: $Path" }
  $ids = @()
  Get-Content -LiteralPath $Path | ForEach-Object { $t = $_.Trim(); if($t -match '^[0-9]+$'){ $ids += [long]$t } }
  return $ids
}

function Read-IdsFromMonthly { param([string]$MonthStr)
  $p = Join-Path "data/matches" ("$MonthStr.json")
  if(-not (Test-Path -LiteralPath $p)) { throw "Monthly file not found: $p" }
  $arr = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
  return @($arr | ForEach-Object { [long]$_.match_id })
}

function Read-IdsFromLeague { param([string]$Code)
  $p = Join-Path (Join-Path "chunks/league" $Code) "matches.json"
  if(-not (Test-Path -LiteralPath $p)) { throw "League matches.json not found: $p" }
  $arr = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
  return @($arr | ForEach-Object { [long]$_.match_id })
}

function New-DirectoryIfMissing { param([string]$Path) if(-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null } }

function Remove-ReplayFiles { param([long[]]$Ids)
  foreach($id in $Ids){
    $p1 = Join-Path $ReplaysDir ("$id.dem")
    $p2 = Join-Path $ReplaysDir ("$id.dem.bz2")
    if(Test-Path -LiteralPath $p1){ Remove-Item -LiteralPath $p1 -Force }
    if(Test-Path -LiteralPath $p2){ Remove-Item -LiteralPath $p2 -Force }
  }
}

# Resolve IDs
$ids = @()
if($Source -eq 'list'){
  if($MatchIds -and $MatchIds.Count -gt 0){ $ids += $MatchIds }
  if($MatchListFile){ $ids += (Read-IdsFromTxt -Path $MatchListFile) }
  if(-not $ids -or $ids.Count -eq 0){ throw "Provide -MatchIds or -MatchListFile for Source=list" }
}elseif($Source -eq 'monthly'){
  if(-not $Month){ throw "Provide -Month (YYYY-MM) for Source=monthly" }
  $ids = Read-IdsFromMonthly -MonthStr $Month
}elseif($Source -eq 'league'){
  if(-not $LeagueCode){ throw "Provide -LeagueCode for Source=league" }
  $ids = Read-IdsFromLeague -Code $LeagueCode
}
$ids = $ids | Sort-Object -Unique

Write-Host ("[ingest] Total matches: {0}" -f $ids.Count)
New-DirectoryIfMissing -Path $ReplaysDir
New-DirectoryIfMissing -Path $OutDir

# Process in batches
$cursor = 0
while($cursor -lt $ids.Count){
  $batch = $ids[$cursor..([Math]::Min($cursor+$BatchSize-1, $ids.Count-1))]
  Write-Host ("[ingest] Batch {0}-{1} of {2} (size {3})" -f ($cursor+1), ($cursor+$batch.Count), $ids.Count, $batch.Count)

  # 1) Download
  pwsh -NoProfile -File scripts/download_replays.ps1 -MatchIds $batch -MappingCsv $MappingCsv -OutDir $ReplaysDir

  # 2) Parse (filtered by the same IDs)
  pwsh -NoProfile -File scripts/parse_replays.ps1 -ReplaysDir $ReplaysDir -OutDir $OutDir -ParserCmd $ParserCmd -MatchIds $batch

  # 3) Cleanup only those with successful outputs
  if(-not $KeepReplays){
    $okIds = @()
    foreach($id in $batch){ if(Test-Path -LiteralPath (Join-Path $OutDir ("$id.json"))){ $okIds += $id } }
    if($okIds.Count -gt 0){ Remove-ReplayFiles -Ids $okIds }
  }

  $cursor += $batch.Count
}

Write-Host "[ingest] Done"

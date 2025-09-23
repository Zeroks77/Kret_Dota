<#!
.SYNOPSIS
  Ingest Kret Daily matches for a given day in controlled batches.

.DESCRIPTION
  Reads match IDs from data/matches/YYYY-MM.json for the given date and filters by that day.
  Then runs ingest_batch.ps1 with BatchSize<=5, downloads, parses, and cleans up.

.PARAMETER Date
  Date in format YYYY-MM-DD. Defaults to today in UTC.

.PARAMETER MappingCsv
  CSV with match_id,cluster,replay_salt.

.PARAMETER ParserCmd
  Parser command template with {in} and {out}.

.EXAMPLE
  pwsh -File scripts/ingest_daily.ps1 -Date 2025-09-23 -MappingCsv scripts/replay_mapping.csv -ParserCmd "node scripts/replay_parser.js --in {in} --out {out}"
#>

param(
  [string]$Date,
  [Parameter(Mandatory=$true)]
  [string]$MappingCsv,
  [Parameter(Mandatory=$true)]
  [string]$ParserCmd,
  [int]$BatchSize = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function GetDateOnlyFromEpoch {
  param([long]$ts)
  # Input start_time appears to be epoch seconds; adjust to UTC
  return ([DateTimeOffset]::FromUnixTimeSeconds([long]$ts)).UtcDateTime.ToString('yyyy-MM-dd')
}

if(-not $Date){ $Date = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd') }
$month = $Date.Substring(0,7)
$path = Join-Path "data/matches" ("$month.json")
if(-not (Test-Path -LiteralPath $path)) { throw "Monthly matches file not found: $path" }

$all = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
$ids = @()
foreach($m in $all){ if((GetDateOnlyFromEpoch -ts $m.start_time) -eq $Date){ $ids += [long]$m.match_id } }
$ids = $ids | Sort-Object -Unique
if($ids.Count -eq 0){ Write-Host "[daily] No matches for $Date"; exit 0 }

Write-Host ("[daily] {0} matches for {1}" -f $ids.Count, $Date)

pwsh -NoProfile -File scripts/ingest_batch.ps1 -Source list -MatchIds $ids -MappingCsv $MappingCsv -ParserCmd $ParserCmd -BatchSize $BatchSize

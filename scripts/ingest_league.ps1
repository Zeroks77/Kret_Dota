<#!
.SYNOPSIS
  Ingest a league's matches in small batches with replay cleanup.

.PARAMETER LeagueCode
  League folder code (e.g., TI2025) under chunks/league/<LeagueCode>/matches.json

.PARAMETER MappingCsv
  CSV with match_id,cluster,replay_salt

.PARAMETER ParserCmd
  Parser command template with {in} and {out}

.PARAMETER BatchSize
  Max 5 to respect CI limits
#>

param(
  [Parameter(Mandatory=$true)]
  [string]$LeagueCode,
  [Parameter(Mandatory=$true)]
  [string]$MappingCsv,
  [Parameter(Mandatory=$true)]
  [string]$ParserCmd,
  [int]$BatchSize = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

pwsh -NoProfile -File scripts/ingest_batch.ps1 -Source league -LeagueCode $LeagueCode -MappingCsv $MappingCsv -ParserCmd $ParserCmd -BatchSize $BatchSize

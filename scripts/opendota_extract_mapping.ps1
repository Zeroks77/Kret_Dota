<#!
.SYNOPSIS
  Build a replay mapping CSV (match_id, cluster, replay_salt) from cached OpenDota match JSON files.

.PARAMETER MatchIds
  One or more match IDs to extract.

.PARAMETER OutCsv
  Output CSV path (default: scripts/replay_mapping.generated.csv)

.EXAMPLE
  pwsh -File scripts/opendota_extract_mapping.ps1 -MatchIds 8299260483,8299261932 -OutCsv scripts/replay_mapping_one.csv
#>

param(
  [Parameter(Mandatory=$true)]
  [object]$MatchIds,
  [string]$CacheDir = (Join-Path (Split-Path $PSScriptRoot -Parent) "data/cache/OpenDota/matches"),
  [string]$OutCsv = (Join-Path $PSScriptRoot "replay_mapping.generated.csv")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-FromCache { param([long]$MatchId)
  $path = Join-Path $CacheDir ("{0}.json" -f $MatchId)
  if(-not (Test-Path -LiteralPath $path)) { throw "Cache missing: $path" }
  $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  $cluster = $json.cluster
  $salt = $json.replay_salt
  if(-not $cluster -or -not $salt){ throw "Missing cluster/replay_salt in $path" }
  [pscustomobject]@{ match_id = [string]$MatchId; cluster = [int]$cluster; replay_salt = [int]$salt }
}

$ids = @()
if($MatchIds -is [array]){ $ids += $MatchIds }
elseif($MatchIds -is [string]){
  $ids += ($MatchIds -split ',' | ForEach-Object { $_.Trim() })
} else {
  $ids += $MatchIds
}
$ids = $ids | Where-Object { $_ -ne $null -and $_ -ne '' } | ForEach-Object { [long]$_ }

$rows = @()
foreach($id in $ids){ $rows += (Get-FromCache -MatchId $id) }

# ensure parent directory exists for OutCsv
$parent = Split-Path -Parent $OutCsv
if($parent -and -not (Test-Path -LiteralPath $parent)){
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
}

$rows | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8
Write-Host "[mapping] Wrote: $OutCsv (rows=$($rows.Count))"

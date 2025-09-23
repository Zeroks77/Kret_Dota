<#!
.SYNOPSIS
  Parse downloaded replay files and emit enriched per-match JSON.

.DESCRIPTION
  Iterates over .dem.bz2 files in data/replays (or a given folder), invokes a parser command (Node/Python)
  to extract events/metrics, and writes normalized enriched JSON to data/enriched/matches.

  The actual parser implementation is not bundled here; configure -ParserCmd to point to your tool, e.g.:
    -ParserCmd "node scripts/replay_parser.js --in {in} --out {out}"
  or -ParserCmd "python scripts/replay_parser.py --in {in} --out {out}"

.PARAMETER ReplaysDir
  Directory with replay files (.dem.bz2 or .dem). Default: data/replays

.PARAMETER OutDir
  Output directory for enriched per-match JSON. Default: data/enriched/matches

.PARAMETER ParserCmd
  Command template with placeholders {in} and {out}.

.PARAMETER Limit
  Optional limit of files to process.

.EXAMPLE
  pwsh -File scripts/parse_replays.ps1 -ParserCmd "node scripts/replay_parser.js --in {in} --out {out}" -Limit 10

#>

param(
  [string]$ReplaysDir = "data/replays",
  [string]$OutDir = "data/enriched/matches",
  [Parameter(Mandatory=$true)]
  [string]$ParserCmd,
  [int]$Limit = 0,
  [long[]]$MatchIds
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-DirectoryIfMissing { param([string]$Path) if(-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null } }

function Get-ReplayFiles { param([string]$Dir, [long[]]$Ids)
  # accept both .dem and .dem.bz2
  $all = Get-ChildItem -LiteralPath $Dir -File | Where-Object { $_.Name -match '\\.dem(\\.bz2)?$' }
  if($Ids -and $Ids.Count -gt 0){
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach($i in $Ids){ [void]$set.Add([string]$i) }
    return $all | Where-Object {
      if ($_.Name -match '^(\d+)') { $set.Contains($Matches[1]) } else { $false }
    } | Sort-Object Name
  }
  return $all | Sort-Object Name
}

New-DirectoryIfMissing -Path $OutDir
Write-Host "[parse] ReplaysDir: $ReplaysDir"
Write-Host "[parse] OutDir: $OutDir"
Write-Host "[parse] ParserCmd: $ParserCmd"

$files = Get-ReplayFiles -Dir $ReplaysDir -Ids $MatchIds
if($Limit -gt 0) { $files = $files | Select-Object -First $Limit }

$ok=0; $fail=0
foreach($f in $files) {
  try {
  # infer match_id from filename prefix (handles .dem and .dem.bz2)
  $mid = $null
  if($f.Name -match '^(\d+)') { $mid = [long]$Matches[1] }
    if(-not $mid) { Write-Warning "Skip (no match_id in name): $($f.Name)"; continue }
    $outPath = Join-Path $OutDir ("$mid.json")
    if(Test-Path -LiteralPath $outPath) { Write-Host "[parse] Exists: $($f.Name)"; $ok++; continue }

    $cmd = $ParserCmd.Replace('{in}', $f.FullName).Replace('{out}', $outPath)
    Write-Host "[parse] Run: $cmd"
    $proc = Start-Process -FilePath pwsh -ArgumentList "-NoProfile","-Command", $cmd -NoNewWindow -Wait -PassThru
    if($proc.ExitCode -eq 0 -and (Test-Path -LiteralPath $outPath)) { $ok++ } else { $fail++; Write-Warning "Parser failed for $($f.Name) exit=$($proc.ExitCode)" }
  } catch {
    $fail++
    Write-Warning ("Error for {0}: {1}" -f $f.Name, $_.Exception.Message)
  }
}

Write-Host "[parse] Done. ok=$ok, failed=$fail"

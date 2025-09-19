param(
  [switch]$SkipMatchesIfCached,
  [switch]$NoIndexUpdate,
  [switch]$VerboseLog
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepoRoot(){ (Resolve-Path "$PSScriptRoot/.." | Select-Object -ExpandProperty Path) }
function Read-JsonFile([string]$p){ if(-not (Test-Path -LiteralPath $p)){ return $null } try{ Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json }catch{ $null } }

$root = Get-RepoRoot
$leagueDir = Join-Path $root 'data/league'
if(-not (Test-Path -LiteralPath $leagueDir)){
  throw "No leagues folder found at: $leagueDir"
}

$dirs = Get-ChildItem -LiteralPath $leagueDir -Directory | Sort-Object Name
if(-not $dirs -or $dirs.Count -eq 0){
  Write-Host "No league subfolders found under $leagueDir" -ForegroundColor Yellow
  return
}

$ok = 0; $skip = 0; $fail = 0
foreach($d in $dirs){
  $slug = $d.Name
  $reportPath = Join-Path $d.FullName 'report.json'
  $name = $null
  $rep = Read-JsonFile $reportPath
  if($rep -and $rep.league -and $rep.league.name){ $name = ''+$rep.league.name }
  if([string]::IsNullOrWhiteSpace($name)){
    # Try docs/data mirror as fallback
    $docsReport = Join-Path $root ("docs/data/league/$slug/report.json")
    $rep2 = Read-JsonFile $docsReport
    if($rep2 -and $rep2.league -and $rep2.league.name){ $name = ''+$rep2.league.name }
  }
  if([string]::IsNullOrWhiteSpace($name)){
    Write-Host ("[skip] Could not resolve league name for slug '{0}' (missing report.json)." -f $slug) -ForegroundColor Yellow
    $skip++
    continue
  }
  Write-Host ("[run ] {0}  (slug: {1})" -f $name, $slug) -ForegroundColor Cyan
  try{
    $invokeArgs = @('-File', (Join-Path $root 'scripts/create_league_report.ps1'), '-LeagueName', $name)
    if($SkipMatchesIfCached){ $invokeArgs += '-SkipMatchesIfCached' }
    if($NoIndexUpdate){ $invokeArgs += '-NoIndexUpdate' }
    if($VerboseLog){ $invokeArgs += '-VerboseLog' }
    pwsh -NoProfile @invokeArgs
    $ok++
  }catch{
    Write-Host ("[fail] {0}: {1}" -f $name, $_.Exception.Message) -ForegroundColor Red
    $fail++
  }
}

Write-Host ("Done. ok={0}, skipped={1}, failed={2}" -f $ok, $skip, $fail) -ForegroundColor Green

param(
  [string[]]$Slugs = @(),
  [string[]]$LeagueRoots = @('docs/league/2025'),
  [string]$DataLeagueRoot = 'docs/data/league',
  [ValidateSet('', 'early','mid','earlylate','late','superlate')]
  [string]$TimeWindow = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ExistingSlugs([string[]]$roots, [string]$dataRoot){
  $set = New-Object System.Collections.Generic.HashSet[string]
  foreach($r in $roots){
    if([string]::IsNullOrWhiteSpace($r)){ continue }
    if(Test-Path $r){
      Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { [void]$set.Add($_.Name) }
    }
  }
  if($dataRoot -and (Test-Path $dataRoot)){
    Get-ChildItem -LiteralPath $dataRoot -Directory -ErrorAction SilentlyContinue |
      ForEach-Object { [void]$set.Add($_.Name) }
  }
  return ,@($set)
}

$all = @()
if($Slugs -and $Slugs.Count){ $all += $Slugs }
$all += (Get-ExistingSlugs -roots $LeagueRoots -dataRoot $DataLeagueRoot)
$all = $all | Where-Object { $_ } | Select-Object -Unique

if(-not $all -or $all.Count -eq 0){
  Write-Warning 'No league slugs found.'
  exit 0
}

Write-Host ("Found {0} slugs: {1}" -f $all.Count, ($all -join ', ')) -ForegroundColor Cyan

$ok = 0; $fail = 0
foreach($slug in $all){
  Write-Host ("[WardPrecompute] -> {0}" -f $slug) -ForegroundColor Yellow
  try{
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File','scripts/analyze_ward_spots.ps1','-LeagueSlug', $slug)
    if($PSBoundParameters.ContainsKey('TimeWindow') -and -not [string]::IsNullOrWhiteSpace($TimeWindow)){
      $argList += @('-TimeWindow', $TimeWindow)
    }
    & powershell @argList
    if($LASTEXITCODE -ne 0){ throw "analyze_ward_spots exited with $LASTEXITCODE" }
    $ok++
  } catch {
    $fail++; Write-Warning ("Failed for {0}: {1}" -f $slug, $_)
  }
}

Write-Host ("Done. Success: {0}, Failed: {1}" -f $ok, $fail) -ForegroundColor Green

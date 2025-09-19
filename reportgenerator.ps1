param(
  [int]$Range = 30,
  [switch]$PreferShards,
  [switch]$PublishToRepo,
  [string]$RepoPath = '.',
  [string]$OutFile = 'docs/last-30-days.html'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepoRoot(){
  try{ return (Resolve-Path -LiteralPath "$PSScriptRoot" | Select-Object -ExpandProperty Path) }catch{ return (Get-Location).Path }
}

function ConvertTo-HtmlEncoded([string]$s){ if($null -eq $s){ return '' } try{ return [System.Net.WebUtility]::HtmlEncode($s) } catch { return ($s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;' -replace "'",'&#39;') } }

function Initialize-Directory([string]$p){ $d=[System.IO.Path]::GetDirectoryName($p); if($d -and -not (Test-Path -LiteralPath $d)){ New-Item -ItemType Directory -Path $d -Force | Out-Null } }

# Compute range
$now = (Get-Date).ToUniversalTime()
$toUnix = [int][math]::Floor([datetimeoffset]::new($now).ToUnixTimeSeconds())
$fromUnix = [int][math]::Floor([datetimeoffset]::new($now.AddDays(-[double]$Range)).ToUnixTimeSeconds())

# Build query string to dynamic.html
# Lock the viewer and land on highlights by default
$query = ("?from=$fromUnix" + "`&to=$toUnix" + "`&tab=highlights" + "`&lock=1")

# Optional: include current major map tag if available
try{
  $root = Get-RepoRoot
  $mapsPath = Join-Path $root 'data/maps.json'
  if(Test-Path -LiteralPath $mapsPath){
    $maps = Get-Content -LiteralPath $mapsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if($maps -and $maps.current){ $major = [string]$maps.current; if(-not [string]::IsNullOrWhiteSpace($major)){ $query += "`&map=$major" } }
  }
}catch{}

# Optional: append league filter from data/info.json
try{
  $root = Get-RepoRoot
  $infoPath = Join-Path $root 'data/info.json'
  if(Test-Path -LiteralPath $infoPath){
    $info = Get-Content -LiteralPath $infoPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if($info -and $info.league_id){ $query += "`&league=$($info.league_id)" }
  }
}catch{}

# Compose wrapper HTML
$title = "Last $Range Days Report"
$html = @"
<!doctype html>
<html lang='en'>
<head>
<meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>$(ConvertTo-HtmlEncoded $title)</title>
<link href='https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap' rel='stylesheet'>
<style>
  body{margin:0;height:100vh;display:flex;flex-direction:column;background:#0b1020}
  .bar{display:flex;justify-content:space-between;align-items:center;padding:10px 12px;color:#eef1f7;background:rgba(255,255,255,.06);font-family:Inter,system-ui,Segoe UI,Roboto,Arial,sans-serif}
  .bar a{color:#9ec7ff;text-decoration:none}
  iframe{border:0;flex:1;width:100%}
</style>
</head>
<body>
  <div class='bar'>
    <div>$(ConvertTo-HtmlEncoded $title)</div>
    <div><a href="./dynamic.html$query" target="_blank" rel="noopener">Open in new tab</a></div>
  </div>
  <iframe src="./dynamic.html$query" loading="eager" referrerpolicy="no-referrer"></iframe>
</body>
</html>
"@

# Resolve output path relative to repo root
try{
  $root = Get-RepoRoot
  $outPath = if([System.IO.Path]::IsPathRooted($OutFile)){ $OutFile } else { Join-Path $root $OutFile }
  Initialize-Directory $outPath
  Set-Content -LiteralPath $outPath -Value $html -Encoding UTF8
  Write-Host ("Wrote wrapper: {0}" -f $outPath)
}catch{
  Write-Error $_
  exit 1
}

# Note: PreferShards / PublishToRepo / RepoPath are accepted for compatibility with tasks, but not used here.
exit 0

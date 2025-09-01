param(
  [Parameter(Mandatory=$true)][string]$Name,
  [Parameter(Mandatory=$true)][int]$AccountId,
  [int]$RangeDays = 30,
  [string]$DocsRoot = "$PSScriptRoot\..\docs",
  [int]$PersistDays = 5,
  [switch]$Cleanup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepoRoot(){ (Resolve-Path "$PSScriptRoot\.." | Select-Object -ExpandProperty Path) }
function Get-DocsRoot(){
  try{
    $p = Resolve-Path -LiteralPath $DocsRoot -ErrorAction Stop | Select-Object -ExpandProperty Path
    return $p
  } catch {
    try{
      $base = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..') | Select-Object -ExpandProperty Path
      $guess = Join-Path $base 'docs'
      if(-not (Test-Path -LiteralPath $guess)){ New-Item -ItemType Directory -Path $guess -Force | Out-Null }
      return $guess
    } catch {
      return (Join-Path $PSScriptRoot '..\docs')
    }
  }
}
function ConvertTo-HtmlEncoded([string]$s){ if($null -eq $s){ return '' } try{ return [System.Net.WebUtility]::HtmlEncode($s) } catch { return ($s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;' -replace "'",'&#39;') } }

function Normalize-Href([string]$href){ if([string]::IsNullOrWhiteSpace($href)){ return '' } $h=$href.Trim(); if($h.StartsWith('./')){ $h=$h.Substring(2) } if(-not $h.EndsWith('/')){ $h=$h+'/' } return $h }

function Update-ReportsJson([string]$docsRoot,[string]$title,[string]$href,[string]$group,[datetime]$when,[string]$sortKey){
  $file = Join-Path $docsRoot 'reports.json'
  $obj = @{ items = @() }
  if(Test-Path -LiteralPath $file){ try{ $obj = Get-Content -Raw -Path $file | ConvertFrom-Json -ErrorAction Stop } catch { $obj = @{ items = @() } } if(-not $obj.items){ $obj = @{ items = @() } } }
  $items = @(); $items += $obj.items
  for($i=0; $i -lt $items.Count; $i++){ if($items[$i] -and $items[$i].href){ $items[$i].href = (Normalize-Href -href ([string]$items[$i].href)) } }
  $nhref = Normalize-Href -href $href
  $found = $false
  for($i=0; $i -lt $items.Count; $i++){
    if([string]$items[$i].href -eq [string]$nhref){ $items[$i] = [pscustomobject]@{ title=$title; href=$nhref; group=$group; time=$when.ToString('yyyy-MM-ddTHH:mm:ssZ'); sort=$sortKey }; $found=$true; break }
  }
  if(-not $found){ $items += [pscustomobject]@{ title=$title; href=$nhref; group=$group; time=$when.ToString('yyyy-MM-ddTHH:mm:ssZ'); sort=$sortKey } }
  # Dedup by href keeping newest time
  $map=@{}; foreach($it in $items){ if(-not $it){ continue } $h=Normalize-Href -href ([string]$it.href); $t=0; try{ $t=[datetime]::Parse((""+$it.time)).ToFileTimeUtc() }catch{ $t=0 } if($map.ContainsKey($h)){ $prev=$map[$h]; $pt=0; try{ $pt=[datetime]::Parse((""+$prev.time)).ToFileTimeUtc() }catch{ $pt=0 } if($t -gt $pt){ $map[$h]=$it } } else { $map[$h]=$it } }
  $items=@(); foreach($k in $map.Keys){ $items+=$map[$k] }
  $outJson = @{ items=$items } | ConvertTo-Json -Depth 5
  Set-Content -Path $file -Value $outJson -Encoding UTF8
}

function Write-Wrapper([string]$outDir,[string]$title,[string]$query){
  if(-not (Test-Path $outDir)){ New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
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
  .sub{color:#9aa3b2}
</style>
</head>
<body>
  <div class='bar'>
    <div>$(ConvertTo-HtmlEncoded $title)<div class='sub'>Temporary user report (auto-deletes after $PersistDays days)</div></div>
    <div><a href="../../dynamic.html$query" target="_blank" rel="noopener">Open in new tab</a></div>
  </div>
  <iframe src="../../dynamic.html$query" loading="eager" referrerpolicy="no-referrer"></iframe>
</body>
</html>
"@
  Set-Content -Path (Join-Path $outDir 'index.html') -Value $html -Encoding UTF8
}

if($Cleanup){
  $docs = Get-DocsRoot
  $file = Join-Path $docs 'reports.json'
  if(-not (Test-Path -LiteralPath $file)){ return }
  $obj = Get-Content -Raw -Path $file | ConvertFrom-Json -ErrorAction SilentlyContinue
  if(-not $obj -or -not $obj.items){ return }
  $cutoff = (Get-Date).ToUniversalTime().AddDays(-[double]$PersistDays)
  $keep = @()
  foreach($it in $obj.items){
    if(([string]$it.group).ToLower() -ne 'user'){ $keep += $it; continue }
    $t = $null; try{ $t=[datetime]::Parse((""+$it.time)).ToUniversalTime() }catch{ $t=$null }
    $href = [string]$it.href; if([string]::IsNullOrWhiteSpace($href)){ continue }
    $href = $href.Trim('/').TrimStart('./')
    $path = Join-Path $docs $href
    $expired = $false
    if($t -ne $null){ $expired = ($t -lt $cutoff) }
    if(-not $expired){
      if(Test-Path -LiteralPath $path){ $keep += $it } else { # missing folder, drop
      }
    } else {
      if(Test-Path -LiteralPath $path){ try{ Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue }catch{} }
    }
  }
  $outJson = @{ items = $keep } | ConvertTo-Json -Depth 5
  Set-Content -Path $file -Value $outJson -Encoding UTF8
  return
}

# Create new user report
$docs = Get-DocsRoot
$now = (Get-Date).ToUniversalTime()
$toUnix = [int][math]::Floor([datetimeoffset]::new($now).ToUnixTimeSeconds())
$fromUnix = [int][math]::Floor([datetimeoffset]::new($now.AddDays(-[double]$RangeDays)).ToUnixTimeSeconds())
$slug = ($Name -replace '[^A-Za-z0-9_-]+','-').Trim('-')
if([string]::IsNullOrWhiteSpace($slug)){ $slug = "user" }
$stamp = $now.ToString('yyyyMMdd-HHmmss')
$folder = "User-Reports/$stamp-$slug"
$outDir = Join-Path $docs $folder
$title = "User Report - $Name - " + $now.ToString('yyyy-MM-dd')
$query = ("?from=$fromUnix" + "`&to=$toUnix" + "`&tab=highlights" + "`&lock=1" + "`&aid=$AccountId" + "`&uonly=1")
Write-Wrapper -outDir $outDir -title $title -query $query
Update-ReportsJson -docsRoot $docs -title $title -href ("{0}/" -f $folder) -group 'user' -when $now -sortKey $now.ToString('yyyy-MM-ddTHH:mm:ssZ')
Write-Host "Created user report: $title -> $folder"

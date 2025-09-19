param(
  [switch]$GenerateMonthly,
  [switch]$LastFullMonth,
  [int]$Year,
  [int]$Month,
  [switch]$GeneratePatch,
  [string]$DocsRoot = "$PSScriptRoot\..\docs"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$tag = $null
$ver = $null
$startUnix = $null
$nowUnix = $null
$displayVer = $null

function Initialize-Directory([string]$p){ $d=[System.IO.Path]::GetDirectoryName($p); if($d -and -not (Test-Path $d)){ New-Item -ItemType Directory -Path $d -Force | Out-Null } }

function Get-RepoRoot(){
  $root = Resolve-Path "$PSScriptRoot\.." | Select-Object -ExpandProperty Path
  return $root
}

function Get-DataPath(){
  $root = Get-RepoRoot
  return Join-Path $root 'data'
}

function Read-JsonFile([string]$path){ if(-not (Test-Path $path)){ return $null } try{ Get-Content -Raw -Path $path | ConvertFrom-Json -ErrorAction Stop }catch{ $null } }

function Get-MonthName([int]$m){
  $names = @('January','February','March','April','May','June','July','August','September','October','November','December')
  if($m -lt 1 -or $m -gt 12){ return "Month-$m" }
  return $names[$m-1]
}

function Get-Month-Range([int]$y,[int]$m){
  $from = [datetime]::SpecifyKind([datetime]::new($y,$m,1,0,0,0), [DateTimeKind]::Utc)
  $to   = $from.AddMonths(1).AddSeconds(-1)
  $fromUnix = [int][math]::Floor([datetimeoffset]::new($from).ToUnixTimeSeconds())
  $toUnix   = [int][math]::Floor([datetimeoffset]::new($to).ToUnixTimeSeconds())
  return [pscustomobject]@{ FromUnix=$fromUnix; ToUnix=$toUnix }
}

function Get-LastFullMonth(){
  $now = (Get-Date).ToUniversalTime()
  $dt = Get-Date -Date ([datetime]::new($now.Year,$now.Month,1,0,0,0,[DateTimeKind]::Utc)).AddMonths(-1)
  return @{Year=$dt.Year; Month=$dt.Month}
}

function Get-CurrentMajorPatchTag(){
  $dataPath = Get-DataPath
  $maps = Read-JsonFile (Join-Path $dataPath 'maps.json')
  # maps.json structure: { current: '7.39', major: { '7.39': { src, scale, ... } } }
  if($maps -and $maps.current){ return [string]$maps.current }
  return $null
}

function Convert-TagToVersion([string]$tag){ if([string]::IsNullOrWhiteSpace($tag)){ return $null } return ($tag -replace '_','.') }

function Get-Patch-StartUnix([string]$version){
  # Try local cached constants first
  $dataPath = Get-DataPath
  $constFile = Join-Path $dataPath 'cache\OpenDota\constants\patch.json'
  $const = Read-JsonFile $constFile
  if(-not $const){ return $null }
  # Helper: parse patch date (strings may be MM/dd/yyyy or other variants)
  function Convert-PatchDateToUnix($dateVal){
    if($dateVal -is [int] -or $dateVal -is [long]){ return [int]$dateVal }
    $s = '' + $dateVal
    if([string]::IsNullOrWhiteSpace($s)){ return $null }
    try{
      $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
      $ci = [System.Globalization.CultureInfo]::InvariantCulture
      $formats = @(
        'yyyy-MM-dd''T''HH:mm:ss''Z''',
        'yyyy-MM-dd HH:mm:ss',
        'yyyy-MM-dd',
        'MM/dd/yyyy HH:mm:ss',
        'M/d/yyyy H:mm:ss',
        'MM/dd/yyyy',
        'dd/MM/yyyy HH:mm:ss',
        'd/M/yyyy H:mm:ss',
        'dd/MM/yyyy'
      )
      $dt = $null
      if([datetime]::TryParseExact($s, $formats, $ci, $styles, [ref]$dt)){
        return [int][math]::Floor([datetimeoffset]::new($dt).ToUnixTimeSeconds())
      }
      # Fallback to invariant Parse
      $dt = [datetime]::Parse($s, $ci, $styles)
      return [int][math]::Floor([datetimeoffset]::new($dt).ToUnixTimeSeconds())
    } catch { return $null }
  }
  # File is an array of objects: [{ name, date, id }, ...]
  $candidates = @()
  foreach($it in $const){
    if($null -ne $it -and $it.PSObject.Properties.Name -contains 'date'){
  $ts = Convert-PatchDateToUnix $it.date
      $ver = if($it.PSObject.Properties.Name -contains 'name'){ [string]$it.name } elseif($it.PSObject.Properties.Name -contains 'patch'){ [string]$it.patch } else { '' }
      if($ts){ $candidates += [pscustomobject]@{ version=$ver; unix=$ts } }
    }
  }
  if(-not $candidates.Count){ return $null }
  $candidates = $candidates | Sort-Object unix
  if($version){
    $match = $candidates | Where-Object { $_.version -eq $version } | Select-Object -Last 1
    if($match){ return $match.unix }
    $major = ($version -replace '([^0-9\.]).*','$1')
    if([string]::IsNullOrWhiteSpace($major)) { $major = ($version -replace '[^0-9\.]','') }
    $match = $candidates | Where-Object { $_.version -like "$major*" } | Select-Object -First 1
    if($match){ return $match.unix }
  }
  return ($candidates | Select-Object -Last 1).unix
}

function Get-Patch-Version-AtUnix([int]$unix){
  $dataPath = Get-DataPath
  $constFile = Join-Path $dataPath 'cache\OpenDota\constants\patch.json'
  $const = Read-JsonFile $constFile
  if(-not $const){ return $null }
  function Convert-PatchDateToUnix2($dateVal){
    if($dateVal -is [int] -or $dateVal -is [long]){ return [int]$dateVal }
    $s = '' + $dateVal
    if([string]::IsNullOrWhiteSpace($s)){ return $null }
    try{
      $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
      $ci = [System.Globalization.CultureInfo]::InvariantCulture
      $formats = @(
        'yyyy-MM-dd''T''HH:mm:ss''Z''',
        'yyyy-MM-dd HH:mm:ss',
        'yyyy-MM-dd',
        'MM/dd/yyyy HH:mm:ss',
        'M/d/yyyy H:mm:ss',
        'MM/dd/yyyy',
        'dd/MM/yyyy HH:mm:ss',
        'd/M/yyyy H:mm:ss',
        'dd/MM/yyyy'
      )
      $dt = $null
      if([datetime]::TryParseExact($s, $formats, $ci, $styles, [ref]$dt)){
        return [int][math]::Floor([datetimeoffset]::new($dt).ToUnixTimeSeconds())
      }
      $dt = [datetime]::Parse($s, $ci, $styles)
      return [int][math]::Floor([datetimeoffset]::new($dt).ToUnixTimeSeconds())
    } catch { return $null }
  }
  $candidates = @()
  foreach($it in $const){
    if($null -ne $it -and $it.PSObject.Properties.Name -contains 'date'){
  $ts = Convert-PatchDateToUnix2 $it.date
      $ver = if($it.PSObject.Properties.Name -contains 'name'){ [string]$it.name } elseif($it.PSObject.Properties.Name -contains 'patch'){ [string]$it.patch } else { '' }
      if($ts){ $candidates += [pscustomobject]@{ version=$ver; unix=$ts } }
    }
  }
  if(-not $candidates.Count){ return $null }
  $candidates = $candidates | Sort-Object unix
  if(-not $unix){ return ($candidates | Select-Object -Last 1).version }
  $match = $candidates | Where-Object { $_.unix -le $unix } | Select-Object -Last 1
  if($match){ return $match.version }
  return $null
}

function ConvertTo-HtmlEncoded([string]$s){
  if($null -eq $s){ return '' }
  try{ return [System.Net.WebUtility]::HtmlEncode($s) } catch { return ($s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;' -replace "'",'&#39;') }
}

function Write-Dynamic-Wrapper([string]$outDir,[string]$title,[string]$query){
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
</style>
</head>
<body>
  <div class='bar'>
    <div>$(ConvertTo-HtmlEncoded $title)</div>
    <div><a href="../dynamic.html$query" target="_blank" rel="noopener">Open in new tab</a></div>
  </div>
  <iframe src="../dynamic.html$query" loading="eager" referrerpolicy="no-referrer"></iframe>
</body>
</html>
"@
  $out = Join-Path $outDir 'index.html'
  Set-Content -Path $out -Value $html -Encoding UTF8
  Write-Host "Wrote $out"
}

function Normalize-Href([string]$href){
  if([string]::IsNullOrWhiteSpace($href)){ return '' }
  $h = $href.Trim()
  if($h.StartsWith('./')){ $h = $h.Substring(2) }
  if(-not $h.EndsWith('/')){ $h = $h + '/' }
  return $h
}

function Update-ReportsJson([string]$docsRoot,[string]$title,[string]$href,[string]$group,[datetime]$when,[string]$sortKey){
  $file = Join-Path $docsRoot 'reports.json'
  $obj = @{ items = @() }
  if(Test-Path -LiteralPath $file){
    try{ $obj = Get-Content -Raw -Path $file | ConvertFrom-Json -ErrorAction Stop } catch { $obj = @{ items = @() } }
    if(-not $obj.items){ $obj = @{ items = @() } }
  }
  # Normalize existing hrefs
  $items = @(); $items += $obj.items
  for($i=0; $i -lt $items.Count; $i++){ if($items[$i] -and $items[$i].href){ $items[$i].href = (Normalize-Href -href ([string]$items[$i].href)) } }
  # Upsert by href
  $found = $false
  $nhref = Normalize-Href -href $href
  for($i=0; $i -lt $items.Count; $i++){
    if([string]$items[$i].href -eq [string]$nhref){
      $items[$i] = [pscustomobject]@{ title=$title; href=$href; group=$group; time=$when.ToString('yyyy-MM-ddTHH:mm:ssZ'); sort=$sortKey }
      $found=$true; break
    }
  }
  if(-not $found){ $items += [pscustomobject]@{ title=$title; href=$nhref; group=$group; time=$when.ToString('yyyy-MM-ddTHH:mm:ssZ'); sort=$sortKey } }
  # Deduplicate by normalized href keeping the most recent time
  $map = @{}
  foreach($it in $items){
    if(-not $it){ continue }
    $h = Normalize-Href -href ([string]$it.href)
    $t = $null; try{ $t = [datetime]::Parse((""+$it.time)) }catch{ $t = Get-Date '1970-01-01Z' }
    if($map.ContainsKey($h)){
      $prev = $map[$h]
      $pt = $null; try{ $pt = [datetime]::Parse((""+$prev.time)) }catch{ $pt = Get-Date '1970-01-01Z' }
      if($t -gt $pt){ $map[$h] = $it }
    } else {
      $map[$h] = $it
    }
  }
  $items = @(); foreach($k in $map.Keys){ $items += $map[$k] }
  $outJson = @{ items = $items } | ConvertTo-Json -Depth 5
  Set-Content -Path $file -Value $outJson -Encoding UTF8
  Write-Host "Updated $file with entry: $title -> $href"
}

# ===== Execution =====
$rootDocs = Resolve-Path $DocsRoot | Select-Object -ExpandProperty Path

if($GenerateMonthly){
  $ym = if($LastFullMonth){ Get-LastFullMonth } else { @{ Year = if($Year){$Year}else{ (Get-Date).ToUniversalTime().Year }; Month = if($Month){$Month}else{ (Get-Date).ToUniversalTime().Month } } }
  $r = Get-Month-Range -y $ym.Year -m $ym.Month
  $monthName = Get-MonthName $ym.Month
  $folderName = "{0}-{1}-Report" -f $ym.Year, $monthName
  $outDir = Join-Path $rootDocs $folderName
  # Determine patch version at the end of this month; use major (e.g., 7.39)
  $patchVer = Get-Patch-Version-AtUnix -unix $r.ToUnix
  $major = if($patchVer){ ($patchVer -replace '^(\d+\.\d+).*','$1') } else { Get-CurrentMajorPatchTag }
  $query = ("?from=$($r.FromUnix)" + "`&to=$($r.ToUnix)" + "`&tab=highlights" + "`&lock=1")
  # Append league filter if available from data/info.json
  try{
    $dataPath = Get-DataPath
    $info = Read-JsonFile (Join-Path $dataPath 'info.json')
    if($info -and $info.league_id){ $query += "`&league=$($info.league_id)" }
  }catch{}
  if($major){ $query += "`&map=$major" }
  $title = if($major){ "Monthly Report - $monthName $($ym.Year) - $major" } else { "Monthly Report - $monthName $($ym.Year)" }
  Write-Dynamic-Wrapper -outDir $outDir -title $title -query $query
  # Update index for sidebar
  $idxTitle = "$monthName $($ym.Year)"
  Update-ReportsJson -docsRoot $rootDocs -title $idxTitle -href ("{0}/" -f $folderName) -group 'monthly' -when ((Get-Date).ToUniversalTime()) -sortKey ("$($ym.Year)-$($ym.Month.ToString('00'))")
}

if($GeneratePatch){
  $tag = Get-CurrentMajorPatchTag
  $ver = if($tag){ Convert-TagToVersion $tag } else { $null }
  $startUnix = if($ver){ Get-Patch-StartUnix $ver } else { Get-Patch-StartUnix $null }
  if(-not $startUnix){ $startUnix = [int][math]::Floor([datetimeoffset]::new((Get-Date).ToUniversalTime().AddDays(-60)).ToUnixTimeSeconds()) }
  $nowUnix = [int][math]::Floor([datetimeoffset]::new((Get-Date).ToUniversalTime()).ToUnixTimeSeconds())
  $displayVer = if($ver){ $ver } else { 'Latest Patch' }
  $folderName = if($ver){ "Patch - $ver - Report" } else { "Patch - Latest - Report" }
  $outDir = Join-Path $rootDocs $folderName
  $query = ("?from=$startUnix" + "`&to=$nowUnix" + "`&tab=highlights" + "`&lock=1")
  try{
    $dataPath = Get-DataPath
    $info = Read-JsonFile (Join-Path $dataPath 'info.json')
    if($info -and $info.league_id){ $query += "`&league=$($info.league_id)" }
  }catch{}
  Write-Dynamic-Wrapper -outDir $outDir -title "Patch Report - $displayVer" -query $query
  # Update index for sidebar
  Update-ReportsJson -docsRoot $rootDocs -title "$displayVer" -href ("{0}/" -f $folderName) -group 'patch' -when ((Get-Date).ToUniversalTime()) -sortKey $displayVer
}

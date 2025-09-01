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
  if($maps -and $maps.major -and $maps.major.PSObject.Properties.Name -contains 'current'){
    return [string]$maps.major.current # e.g. '7_39'
  }
  return $null
}

function Convert-TagToVersion([string]$tag){ if([string]::IsNullOrWhiteSpace($tag)){ return $null } return ($tag -replace '_','.') }

function Get-Patch-StartUnix([string]$version){
  # Try local cached constants first
  $dataPath = Get-DataPath
  $constFile = Join-Path $dataPath 'cache\OpenDota\constants\patch.json'
  $const = Read-JsonFile $constFile
  if($const){
    # patch constants structure is a map of entries, pick the matching version or nearest preceding
    $candidates = @()
    foreach($k in $const.PSObject.Properties.Name){
      $it = $const.$k
      if($it -and $it.date){
        $ts = if($it.date -is [int]){ [int]$it.date } else { [int][math]::Floor(([datetime]::Parse($it.date)).ToUniversalTime().Subtract([datetime]'1970-01-01Z').TotalSeconds) }
        $ver = if($it.name){ [string]$it.name } elseif($it.patch){ [string]$it.patch } else { [string]$k }
        $candidates += [pscustomobject]@{ version=$ver; unix=$ts }
      }
    }
    if($version){
      $match = $candidates | Where-Object { $_.version -eq $version } | Sort-Object unix | Select-Object -Last 1
      if($match){ return $match.unix }
      # fallback: find first candidate whose version starts with desired major (e.g., 7.39a -> 7.39)
      $major = ($version -replace '[^0-9\.]','')
      $match = $candidates | Where-Object { $_.version -like "$major*" } | Sort-Object unix | Select-Object -First 1
      if($match){ return $match.unix }
    }
    # latest if nothing provided
    $latest = $candidates | Sort-Object unix | Select-Object -Last 1
    if($latest){ return $latest.unix }
  }
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

function Update-ReportsJson([string]$docsRoot,[string]$title,[string]$href,[string]$group,[datetime]$when,[string]$sortKey){
  $file = Join-Path $docsRoot 'reports.json'
  $obj = @{ items = @() }
  if(Test-Path -LiteralPath $file){
    try{ $obj = Get-Content -Raw -Path $file | ConvertFrom-Json -ErrorAction Stop } catch { $obj = @{ items = @() } }
    if(-not $obj.items){ $obj = @{ items = @() } }
  }
  $items = @()
  $items += $obj.items
  # Upsert by href
  $found = $false
  for($i=0; $i -lt $items.Count; $i++){
    if([string]$items[$i].href -eq [string]$href){
      $items[$i] = [pscustomobject]@{ title=$title; href=$href; group=$group; time=$when.ToString('yyyy-MM-ddTHH:mm:ssZ'); sort=$sortKey }
      $found=$true; break
    }
  }
  if(-not $found){ $items += [pscustomobject]@{ title=$title; href=$href; group=$group; time=$when.ToString('yyyy-MM-ddTHH:mm:ssZ'); sort=$sortKey } }
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
  $query = ("?from=$($r.FromUnix)" + "`&to=$($r.ToUnix)" + "`&tab=highlights" + "`&lock=1")
  Write-Dynamic-Wrapper -outDir $outDir -title "Monthly Report – $monthName $($ym.Year)" -query $query
  # Update index for sidebar
  Update-ReportsJson -docsRoot $rootDocs -title "${monthName} $($ym.Year)" -href ("{0}/" -f $folderName) -group 'monthly' -when ((Get-Date).ToUniversalTime()) -sortKey ("$($ym.Year)-$($ym.Month.ToString('00'))")
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
  Write-Dynamic-Wrapper -outDir $outDir -title "Patch Report – $displayVer" -query $query
  # Update index for sidebar
  Update-ReportsJson -docsRoot $rootDocs -title "$displayVer" -href ("{0}/" -f $folderName) -group 'patch' -when ((Get-Date).ToUniversalTime()) -sortKey $displayVer
}

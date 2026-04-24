<#
  Shared helpers for Kret Dota pipeline scripts.
  Dot-source from any script:  . "$PSScriptRoot/lib/common.ps1"
  Or from repo root:           . "$PSScriptRoot/scripts/lib/common.ps1"
#>

# ---------- Path helpers ----------
function Get-RepoRoot {
  # Works when called from scripts/lib/, scripts/, or repo root
  $candidates = @(
    (Join-Path $PSScriptRoot '..')        # from scripts/*
    (Join-Path $PSScriptRoot '../..')     # from scripts/lib/
    $PSScriptRoot                          # from repo root
  )
  foreach ($c in $candidates) {
    $r = Resolve-Path $c -ErrorAction SilentlyContinue
    if ($r -and (Test-Path (Join-Path $r.Path 'data'))) { return $r.Path }
  }
  # fallback
  $r = Resolve-Path (Join-Path $PSScriptRoot '..') -ErrorAction SilentlyContinue
  if ($r) { return $r.Path }
  return (Split-Path $PSScriptRoot -Parent)
}

function Get-DataPath { Join-Path (Get-RepoRoot) 'data' }
function Get-CachePath { Join-Path (Get-DataPath) 'cache/OpenDota' }
function Get-DocsPath { Join-Path (Get-RepoRoot) 'docs' }

function New-ParentDirectory([string]$p) {
  $d = [System.IO.Path]::GetDirectoryName($p)
  if ($d -and -not (Test-Path -LiteralPath $d)) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
  }
}

# ---------- JSON I/O ----------
function Read-JsonFile([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  try { Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json }
  catch { $null }
}

function Save-Json(
  [Alias('obj')][object]$o,
  [Alias('path')][string]$p,
  [int]$Depth = 50
) {
  New-ParentDirectory $p
  ($o | ConvertTo-Json -Depth $Depth -Compress:$false) |
    Set-Content -LiteralPath $p -Encoding UTF8
}

function Save-JsonCompact([object]$o, [string]$p) {
  New-ParentDirectory $p
  ($o | ConvertTo-Json -Depth 50 -Compress) |
    Set-Content -LiteralPath $p -Encoding UTF8
}

# ---------- HTML encoding ----------
function HtmlEncode([string]$s) {
  if ($null -eq $s) { return '' }
  try { return [System.Net.WebUtility]::HtmlEncode($s) }
  catch { return ($s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;') }
}

# ---------- Logging ----------
function Log([string]$m) {
  if ($script:VerboseLog -or $VerbosePreference -eq 'Continue') {
    Write-Host $m
  }
}

# ---------- League helpers ----------
function Get-LeagueSlug([string]$n) {
  if ([string]::IsNullOrWhiteSpace($n)) { return 'league' }
  $t = $n.Trim()
  # The International 2025 -> TI2025
  $m = [regex]::Match($t, '^(?i)the international\s+(\d{4})$')
  if ($m.Success) { return 'TI' + $m.Groups[1].Value }
  # Regional Qualifier abbreviation
  $m2 = [regex]::Match($t, '^(?i)(regional qualifier)\s+(.+)$')
  if ($m2.Success) {
    $rest = $m2.Groups[2].Value
    $regionParts = ($rest -split '\s+') | Where-Object { $_ -match '^[A-Za-z]+' }
    $region = ($regionParts | ForEach-Object { $_.Substring(0,1).ToUpper() }) -join ''
    if ([string]::IsNullOrWhiteSpace($region)) { $region = 'X' }
    return 'RQ_' + $region
  }
  # Generic: uppercase initials + digits
  $words = $t -split '[^A-Za-z0-9]+'
  $abbr = ($words | Where-Object { $_ -ne '' } | ForEach-Object {
    if ($_ -match '^[0-9]+$') { $_ } else { $_.Substring(0,1).ToUpper() }
  }) -join ''
  if ($abbr.Length -lt 3) {
    $clean = ($t -replace '[^A-Za-z0-9]+','')
    $abbr = $clean.Substring(0, [Math]::Min(8, $clean.Length))
  }
  return $abbr
}

# Known Tier-1 series patterns for auto-discovery
$script:Tier1Patterns = @(
  @{ Pattern = '(?i)the international';         Series = 'TI';          Tier = 1 }
  @{ Pattern = '(?i)dreamleague\s+season';      Series = 'DreamLeague'; Tier = 1 }
  @{ Pattern = '(?i)pgl\s+wallachia';           Series = 'PGL';         Tier = 1 }
  @{ Pattern = '(?i)blast\s+(slam|premier)';    Series = 'BLAST';       Tier = 1 }
  @{ Pattern = '(?i)esl\s+one';                 Series = 'ESL';         Tier = 1 }
  @{ Pattern = '(?i)betboom\s+dacha';           Series = 'BetBoom';     Tier = 1 }
  @{ Pattern = '(?i)esports\s+world\s+cup';     Series = 'EWC';         Tier = 1 }
  @{ Pattern = '(?i)riyadh\s+masters';          Series = 'Riyadh';      Tier = 1 }
  @{ Pattern = '(?i)fissure\s+(universe|playground)'; Series = 'FISSURE'; Tier = 2 }
  @{ Pattern = '(?i)european\s+pro\s+league';   Series = 'EPL';         Tier = 2 }
  @{ Pattern = '(?i)predator\s+league';         Series = 'Predator';    Tier = 2 }
  @{ Pattern = '(?i)clavision';                 Series = 'CDM';         Tier = 2 }
)

function Get-LeagueTier([string]$name) {
  foreach ($p in $script:Tier1Patterns) {
    if ($name -match $p.Pattern) {
      return @{ Tier = $p.Tier; Series = $p.Series }
    }
  }
  return @{ Tier = 3; Series = '' }
}

# ---------- Player name normalization ----------
$script:PlayerAliases = [ordered]@{
  'YATOROGOD'  = 'Yatoro';   'Yatoro'    = 'Yatoro'
  'Collapse'   = 'Collapse';  'N0tail'    = 'N0tail';   'Johan' = 'N0tail'
  'MATUMBAMAN'  = 'MATUMBAMAN'; 'MATU'     = 'MATUMBAMAN'
  'MidOne'     = 'MidOne';    'Puppey'    = 'Puppey';   'Clement' = 'Puppey'
}

function Convert-PlayerName([string]$n) {
  if ([string]::IsNullOrWhiteSpace($n)) { return $n }
  $t = $n.Trim()
  foreach ($k in $script:PlayerAliases.Keys) {
    if ($t -ieq $k) { return $script:PlayerAliases[$k] }
  }
  return $t
}

# ---------- API rate-limiter ----------
# OpenDota limits:
#   Without API key:  60/min,   3000/day
#   With API key:     3000/min, unlimited
class RateLimiter {
  [int]$MaxPerMinute
  [int]$MaxPerDay
  [int]$DayCount
  [System.Collections.Generic.List[datetime]]$Window

  RateLimiter([int]$rpm, [int]$rpd) {
    $this.MaxPerMinute = $rpm
    $this.MaxPerDay = $rpd
    $this.DayCount = 0
    $this.Window = [System.Collections.Generic.List[datetime]]::new()
  }

  [bool] CanFetch() {
    if ($this.MaxPerDay -le 0) { return $true }  # unlimited
    return ($this.DayCount -lt $this.MaxPerDay)
  }

  [void] WaitForSlot() {
    $now = [datetime]::UtcNow
    # Purge old entries
    $cutoff = $now.AddSeconds(-60)
    $this.Window.RemoveAll({ param($d) $d -lt $cutoff }) | Out-Null
    if ($this.Window.Count -ge $this.MaxPerMinute) {
      $sleepMs = [int][Math]::Ceiling(60000 / [Math]::Max(1, $this.MaxPerMinute))
      Start-Sleep -Milliseconds ([Math]::Max(50, $sleepMs))
    }
  }

  [void] Record() {
    $this.Window.Add([datetime]::UtcNow)
    if ($this.MaxPerDay -gt 0) { $this.DayCount++ }
  }
}

# Factory: create a RateLimiter with correct limits based on whether API key is present
function New-RateLimiter {
  if (-not [string]::IsNullOrWhiteSpace($script:OpenDotaApiKey)) {
    # With API key: 3000/min, unlimited daily (use 0 for unlimited)
    return [RateLimiter]::new(2700, 0)   # 10% safety margin
  } else {
    # Without API key: 60/min, 3000/day
    return [RateLimiter]::new(55, 2700)  # 10% safety margin
  }
}

# ---------- .env loading ----------
# Loads variables from a .env file into the current scope.
# Supports OPENDOTA_API_KEY, STEAM_API_KEY, etc.
$script:OpenDotaApiKey = $null

function Import-DotEnv {
  $envFile = Join-Path (Get-RepoRoot) '.env'
  if (-not (Test-Path -LiteralPath $envFile)) { return }
  Get-Content -LiteralPath $envFile -Encoding UTF8 | ForEach-Object {
    $line = $_.Trim()
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { return }
    $eqIdx = $line.IndexOf('=')
    if ($eqIdx -le 0) { return }
    $key   = $line.Substring(0, $eqIdx).Trim()
    $value = $line.Substring($eqIdx + 1).Trim().Trim('"').Trim("'")
    [Environment]::SetEnvironmentVariable($key, $value, 'Process')
  }
}

function Initialize-ApiKeys {
  # Load .env first (local dev)
  Import-DotEnv
  # OpenDota API key: param > env > .env
  if (-not [string]::IsNullOrWhiteSpace($env:OPENDOTA_API_KEY)) {
    $script:OpenDotaApiKey = $env:OPENDOTA_API_KEY
  }
  $hasKey = -not [string]::IsNullOrWhiteSpace($script:OpenDotaApiKey)
  $mode = if ($hasKey) { 'authenticated (3000/min, unlimited daily)' } else { 'anonymous (60/min, 3000/day)' }
  Write-Host "OpenDota API mode: $mode"
}

# ---------- OpenDota API ----------
function Invoke-OpenDotaApi([string]$Endpoint, [string]$Method = 'GET', [int]$TimeoutSec = 30) {
  $uri = "https://api.opendota.com/api/$Endpoint"
  if (-not [string]::IsNullOrWhiteSpace($script:OpenDotaApiKey)) {
    $sep = if ($Endpoint.Contains('?')) { '&' } else { '?' }
    $uri = "${uri}${sep}api_key=$($script:OpenDotaApiKey)"
  }
  $headers = @{
    'Accept'     = 'application/json'
    'User-Agent' = 'kret-dota-pipeline/2.0'
  }
  Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -TimeoutSec $TimeoutSec
}

# ---------- Cached fetch with staleness ----------
function Get-CachedOrFetch([string]$CachePath, [string]$Endpoint, [int]$MaxAgeHours = 24, [switch]$Force) {
  $needFetch = $Force.IsPresent
  if (-not $needFetch -and -not (Test-Path -LiteralPath $CachePath)) { $needFetch = $true }
  if (-not $needFetch) {
    try {
      $age = (Get-Date) - (Get-Item -LiteralPath $CachePath).LastWriteTimeUtc
      if ($age.TotalHours -gt $MaxAgeHours) { $needFetch = $true }
    } catch { $needFetch = $true }
  }

  if ($needFetch) {
    Write-Host "Fetching $Endpoint ..."
    $data = Invoke-OpenDotaApi $Endpoint
    if ($data) { Save-Json -o $data -p $CachePath }
    return $data
  }
  return (Read-JsonFile $CachePath)
}

# ---------- Reports.json management ----------
function Get-NormalizedHref([string]$href) {
  if ([string]::IsNullOrWhiteSpace($href)) { return '' }
  $h = $href.Trim()
  if ($h.StartsWith('./')) { $h = $h.Substring(2) }
  if (-not $h.EndsWith('/')) { $h += '/' }
  return $h
}

function Update-ReportsJson {
  param(
    [string]$DocsRoot,
    [string]$Title,
    [string]$Href,
    [string]$Group,
    [datetime]$When,
    [string]$SortKey
  )
  $file = Join-Path $DocsRoot 'reports.json'
  $obj = @{ items = @() }
  if (Test-Path -LiteralPath $file) {
    try { $obj = Get-Content -Raw -Path $file | ConvertFrom-Json -ErrorAction Stop }
    catch { $obj = @{ items = @() } }
    if (-not $obj.items) { $obj = @{ items = @() } }
  }
  $items = @(); $items += $obj.items
  for ($i = 0; $i -lt $items.Count; $i++) {
    if ($items[$i] -and $items[$i].href) {
      $items[$i].href = (Get-NormalizedHref ([string]$items[$i].href))
    }
  }
  $nhref = Get-NormalizedHref $Href
  $found = $false
  for ($i = 0; $i -lt $items.Count; $i++) {
    if ([string]$items[$i].href -eq [string]$nhref) {
      $items[$i] = [pscustomobject]@{
        title = $Title; href = $nhref; group = $Group
        time = $When.ToString('yyyy-MM-ddTHH:mm:ssZ'); sort = $SortKey
      }
      $found = $true; break
    }
  }
  if (-not $found) {
    $items += [pscustomobject]@{
      title = $Title; href = $nhref; group = $Group
      time = $When.ToString('yyyy-MM-ddTHH:mm:ssZ'); sort = $SortKey
    }
  }
  # Dedup by href, keep newest
  $map = @{}
  foreach ($it in $items) {
    if (-not $it) { continue }
    $h = Get-NormalizedHref ([string]$it.href)
    $t = 0; try { $t = [datetime]::Parse(('' + $it.time)).ToFileTimeUtc() } catch { $t = 0 }
    if ($map.ContainsKey($h)) {
      $prev = $map[$h]; $pt = 0
      try { $pt = [datetime]::Parse(('' + $prev.time)).ToFileTimeUtc() } catch { $pt = 0 }
      if ($t -gt $pt) { $map[$h] = $it }
    }
    else { $map[$h] = $it }
  }
  $items = @(); foreach ($k in $map.Keys) { $items += $map[$k] }
  $outJson = @{ items = $items } | ConvertTo-Json -Depth 5
  Set-Content -Path $file -Value $outJson -Encoding UTF8
}

# ---------- HTML wrapper generation ----------
function Write-DotaWrapper {
  param(
    [string]$OutDir,
    [string]$Title,
    [string]$IframeSrc,
    [string]$Subtitle,
    [string]$BackLink = '../index.html'
  )
  if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
  $escapedTitle = HtmlEncode $Title
  $subtitleHtml = if ($Subtitle) { "<div style='color:var(--text-muted);font-size:12px'>$(HtmlEncode $Subtitle)</div>" } else { '' }
  $backHtml = if ($BackLink) { "<a style='color:var(--gold);text-decoration:none;font-size:13px' href='$BackLink'>&#8592; Back</a>" } else { '' }
  $html = @"
<!doctype html>
<html lang='en'>
<head>
<meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>$escapedTitle</title>
<link rel='stylesheet' href='../css/dota-theme.css'>
<style>
  body{margin:0;height:100vh;display:flex;flex-direction:column;position:relative;z-index:1}
  .bar{display:flex;justify-content:space-between;align-items:center;padding:10px 16px;border-bottom:1px solid var(--border);background:rgba(200,170,110,.02)}
  .bar-title{font-weight:700;color:var(--gold-light)}
  iframe{border:0;flex:1;width:100%}
</style>
</head>
<body>
  <div class='bar'>
    <div><div class='bar-title'>$escapedTitle</div>$subtitleHtml</div>
    $backHtml
  </div>
  <iframe src="$IframeSrc" loading="eager" referrerpolicy="no-referrer"></iframe>
  <script>
    (function(){
      try{var f=document.querySelector('iframe');if(!f)return;var s=f.getAttribute('src');if(!s)return;var u=new URL(s,location.href);u.searchParams.set('cb',Date.now().toString());f.src=u.pathname+u.search;}catch(_){}
    })();
  </script>
</body>
</html>
"@
  $out = Join-Path $OutDir 'index.html'
  Set-Content -LiteralPath $out -Value $html -Encoding UTF8
  Write-Host "  Wrote $out"
}

# ---------- Logging helpers ----------
function Write-Step([string]$msg) {
  $ts = (Get-Date).ToString('HH:mm:ss')
  Write-Host "`n[$ts] === $msg ===" -ForegroundColor Cyan
}

function Format-Duration([datetime]$start) {
  $d = (Get-Date) - $start
  if ($d.TotalMinutes -ge 1) { return ('{0:n1}m' -f $d.TotalMinutes) }
  return ('{0:n1}s' -f $d.TotalSeconds)
}

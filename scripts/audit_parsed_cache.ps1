param(
    [int]$LeagueId = 18438,
    [string]$CacheDir = "..\data\cache\OpenDota\matches",
    [switch]$WriteReport
)

# Resolve paths relative to this script's location
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
if (-not (Test-Path $CacheDir)) {
    $CacheDir = Join-Path $Root "data\cache\OpenDota\matches"
}

if (-not (Test-Path $CacheDir)) {
    Write-Error "Cache directory not found: $CacheDir"
    exit 1
}

function Test-Parsed($match) {
    if ($null -eq $match) { return $false }
    # Explicit OpenDota signal
    try { if ($match.od_data.has_parsed -eq $true) { return $true } } catch { }
    # Basic structure present?
    $players = $match.players
    if (-not ($players -is [System.Collections.IEnumerable]) -or $players.Count -lt 10) { return $false }
    # Any typical parsed fields?
    foreach ($p in $players) {
        if (-not $p) { continue }
        if ($p.purchase_log -and $p.purchase_log.Count -gt 0) { return $true }
        if ($p.kills_log -and $p.kills_log.Count -gt 0) { return $true }
        if ($p.deaths_log -and $p.deaths_log.Count -gt 0) { return $true }
        if ($p.gold_t -and $p.gold_t.Count -gt 0) { return $true }
        if ($p.xp_t -and $p.xp_t.Count -gt 0) { return $true }
        if ($p.lh_t -and $p.lh_t.Count -gt 0) { return $true }
        if ($p.life_state -and $p.life_state.Keys.Count -gt 0) { return $true }
    }
    # Objectives array is also a strong signal
    if ($match.objectives -and $match.objectives.Count -gt 0) { return $true }
    return $false
}

$files = Get-ChildItem -Path $CacheDir -Filter '*.json' -File -ErrorAction SilentlyContinue
if ($files.Count -eq 0) {
    Write-Host "No cached match files found in $CacheDir"
    exit 0
}

$total = 0
$leagueTotal = 0
$parsed = 0
$unparsed = @()

foreach ($f in $files) {
    $total++
    try {
        $json = Get-Content -Raw -Path $f.FullName | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Warning "Failed to parse JSON: $($f.Name)"
        continue
    }
    $lid = 0
    try { $lid = [int]($json.leagueid) } catch { $lid = 0 }
    if ($lid -ne $LeagueId) { continue }
    $leagueTotal++
    if (Test-Parsed $json) { $parsed++ } else { $unparsed += [int]$json.match_id }
}

Write-Host "League $LeagueId cache audit"
Write-Host "  Cached files total: $($files.Count)"
Write-Host "  League matches in cache: $leagueTotal"
Write-Host "  Parsed: $parsed"
Write-Host "  Not parsed: $($unparsed.Count)"
if ($unparsed.Count -gt 0) {
    Write-Host "  Missing parsed data for match IDs (first 50):" ("{0}" -f ($unparsed | Select-Object -First 50 -join ', '))
}

if ($WriteReport) {
    $out = [PSCustomObject]@{
        league_id = $LeagueId
        league_cached = $leagueTotal
        parsed = $parsed
        unparsed_count = $unparsed.Count
        unparsed_ids = $unparsed
        generated_at = [int][double]::Parse((Get-Date -UFormat %s))
    }
    $outPath = Join-Path $Root "data\cache\audit_parsed_${LeagueId}.json"
    $out | ConvertTo-Json -Depth 6 | Set-Content -Path $outPath -Encoding UTF8
    Write-Host "Report written to $outPath"
}

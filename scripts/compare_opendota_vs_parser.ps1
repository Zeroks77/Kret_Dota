param(
  [Parameter(Mandatory=$true)][long]$MatchId,
  [string]$OpenDotaPath = "data/cache/OpenDota/matches/{mid}.json",
  [string]$ParserPath = "data/parsed/{mid}.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$odFile = $OpenDotaPath.Replace('{mid}', "$MatchId")
$myFile = $ParserPath.Replace('{mid}', "$MatchId")
if(!(Test-Path -LiteralPath $odFile)) { throw "Missing OpenDota file: $odFile" }
if(!(Test-Path -LiteralPath $myFile)) { throw "Missing parser file: $myFile" }

$od = Get-Content -Raw -LiteralPath $odFile | ConvertFrom-Json -Depth 100
$my = Get-Content -Raw -LiteralPath $myFile | ConvertFrom-Json -Depth 100

# Helpers
function PropNames($o) { if($null -ne $o){ $o.PSObject.Properties.Name } else { @() } }
function CountOf($x) { if($null -eq $x){ 0 } else { @($x).Count } }
function GetProp($obj, $name) { if($null -eq $obj){ return $null } $p = $obj.PSObject.Properties[$name]; if($p){ return $p.Value } return $null }

# Runes
[int]$runesOd = 0; foreach($p in @($od.players)){ $runesOd += CountOf $p.runes_log }
[int]$runesMy = CountOf (GetProp $my.enriched 'runes_events')

# Smokes
[int]$smokesOd = 0; foreach($p in @($od.players)){
  if($p.item_uses){
    $names = PropNames $p.item_uses
    if($names -contains 'smoke_of_deceit') { $smokesOd += [int]$p.item_uses.smoke_of_deceit }
    elseif($names -contains 'item_smoke_of_deceit') { $smokesOd += [int]$p.item_uses.item_smoke_of_deceit }
  }
}
[int]$smokesMy = CountOf (GetProp $my.enriched 'smokes_events')

# Wards
[int]$obsOd=0; [int]$senOd=0; [int]$obsLeftOd=0; [int]$senLeftOd=0
foreach($p in @($od.players)){
  $obsOd     += CountOf $p.obs_log
  $senOd     += CountOf $p.sen_log
  $obsLeftOd += CountOf $p.obs_left_log
  $senLeftOd += CountOf $p.sen_left_log
}
$wardsEvents = @((GetProp $my.enriched 'wards_events'))
[int]$obsMy = (@($wardsEvents) | Where-Object { $_.type -eq 'item_ward_observer' } | Measure-Object).Count
[int]$senMy = (@($wardsEvents) | Where-Object { $_.type -eq 'item_ward_sentry' } | Measure-Object).Count
[int]$dewardsMy = (@($wardsEvents) | Where-Object { $_.removed_at -ne $null } | Measure-Object).Count

# Buybacks
[int]$buybacksOd=0; foreach($p in @($od.players)){ $buybacksOd += CountOf $p.buyback_log }
[int]$buybacksMy = CountOf (GetProp $my.enriched 'buybacks')

# Building kills
[int]$buildingKillsOd = (@(@($od.objectives) | Where-Object { $_.type -eq 'building_kill' }) | Measure-Object).Count
[int]$buildingKillsMy = (@(@(GetProp $my.enriched 'objectives_basic') | Where-Object { $_.event -eq 'building_kill' }) | Measure-Object).Count

# Roshan / Aegis
$rk = (@(@($od.objectives) | Where-Object { $_.type -eq 'CHAT_MESSAGE_ROSHAN_KILL' }) | Select-Object -First 1)
$roshanKillOd = if($rk){ [int]$rk.time } else { $null }
[int]$aegisOd = (@(@($od.objectives) | Where-Object { $_.type -like 'CHAT_MESSAGE_AEGIS*' }) | Measure-Object).Count
$rs = GetProp $my.enriched 'roshan_summary'
$rkMyVal = GetProp $rs 'kill_time'
$roshanKillMy = if($rkMyVal -ne $null){ [int]$rkMyVal } else { $null }
$aegisHolderMy = GetProp $rs 'aegis_holder'
$aegisPickupVal = GetProp $rs 'aegis_pickup_time'
$aegisPickupTimeMy = if($aegisPickupVal -ne $null){ [int]$aegisPickupVal } else { $null }

# Ability uses
[int]$abilityUsesOd=0; foreach($p in @($od.players)){
  if($p.ability_uses){ foreach($k in PropNames $p.ability_uses){ $abilityUsesOd += [int]$p.ability_uses.$k } }
}
[int]$abilityUsesMy = 0; $agg = GetProp $my.enriched 'aggregated_stats'; $byAbility = GetProp $agg 'ability_usage_by_ability'; if($byAbility){ foreach($k in PropNames $byAbility){ $abilityUsesMy += [int]$byAbility.$k } }

# Report
$report = [ordered]@{
  match_id_od = $od.match_id
  match_id_my = $my.match_id
  runes = @{ od=$runesOd; my=$runesMy; diff=$runesMy-$runesOd }
  smokes = @{ od=$smokesOd; my=$smokesMy; diff=$smokesMy-$smokesOd }
  wards = @{ obs_od=$obsOd; sen_od=$senOd; obs_my=$obsMy; sen_my=$senMy; dewards_od_obs=$obsLeftOd; dewards_od_sen=$senLeftOd; dewards_my=$dewardsMy }
  buybacks = @{ od=$buybacksOd; my=$buybacksMy; diff=$buybacksMy-$buybacksOd }
  building_kills = @{ od=$buildingKillsOd; my=$buildingKillsMy; diff=$buildingKillsMy-$buildingKillsOd }
  roshan = @{ kill_time_od=$roshanKillOd; kill_time_my=$roshanKillMy; aegis_events_od=$aegisOd; aegis_holder_my=$aegisHolderMy; aegis_pickup_time_my=$aegisPickupTimeMy }
  ability_uses = @{ od=$abilityUsesOd; my=$abilityUsesMy; diff=$abilityUsesMy-$abilityUsesOd }
}
$report | ConvertTo-Json -Depth 6

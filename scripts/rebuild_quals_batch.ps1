$jobs = @(
  @{ Name='BLAST SLAM VI';            Ids='19148,19154,19155' }
  @{ Name='DreamLeague Season 26';    Ids='17874' }
  @{ Name='DreamLeague Season 28';    Ids='19089' }
  @{ Name='ESL One Birmingham 2026';  Ids='19090' }
  @{ Name='ESL One Raleigh 2025';     Ids='17629' }
  @{ Name='Esports World Cup 2025';   Ids='18210' }
)
foreach($j in $jobs){
  Write-Host ('=== '+$j.Name+' :: '+$j.Ids+' ===') -ForegroundColor Cyan
  & pwsh -NoProfile -File "$PSScriptRoot/create_league_report.ps1" -LeagueName $j.Name -IncludeLeagueIds $j.Ids
}

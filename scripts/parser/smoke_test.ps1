param(
  [string]$ReplayPath,
  [string]$OutPath = "data/enriched/matches/test.json"
)

if(-not (Test-Path -LiteralPath $ReplayPath)){
  throw "ReplayPath missing: $ReplayPath"
}

$jar = "scripts/parser/clarity-cli/target/clarity-cli-0.1.0-jar-with-dependencies.jar"
if(-not (Test-Path -LiteralPath $jar)){
  Write-Host "[smoke] Build jar"
  $mvn = Get-Command mvn -ErrorAction SilentlyContinue
  if(-not $mvn){
    Write-Warning "Maven not found. Please install Maven (winget, choco) or run 'mvn -f scripts/parser/clarity-cli/pom.xml package' manually."
    throw "Maven missing"
  }
  & mvn -q -f scripts/parser/clarity-cli/pom.xml -DskipTests package
}

$outDir = Split-Path -Parent $OutPath
if($outDir -and -not (Test-Path -LiteralPath $outDir)){
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

Write-Host "[smoke] Run clarity-cli"
& java -jar $jar --in $ReplayPath --out $OutPath

if(Test-Path -LiteralPath $OutPath){ Write-Host "[smoke] OK -> $OutPath" } else { throw "No output produced" }

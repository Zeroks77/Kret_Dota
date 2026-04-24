param(
  [int]$Range = 30,
  [switch]$PreferShards,
  [switch]$PublishToRepo,
  [string]$RepoPath = '.',
  [string]$OutFile = 'docs/last-30-days.html'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pipelinePath = Join-Path $PSScriptRoot 'pipeline.ps1'
if (-not (Test-Path -LiteralPath $pipelinePath)) {
  throw "pipeline.ps1 not found at $pipelinePath"
}

# Keep this wrapper for task compatibility; delegate all logic to the unified pipeline.
& pwsh -NoProfile -File $pipelinePath -Steps last30,publish,legacy-clean -RangeDays $Range
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
exit 0

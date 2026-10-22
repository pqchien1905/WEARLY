param(
  [ValidateSet('quick','full','browser','runtime')][string]$Profile='quick',
  [ValidateSet('operations','tryon','stylist','admin','recovery','refunds','promotions','shipments','sessions')][string]$Browser='operations',
  [switch]$ReuseBuild
)
$ErrorActionPreference='Stop'
$workspace=Split-Path -Parent $PSScriptRoot
$nodeDirectory=Join-Path $workspace '.tools/node-v24.22.0-win-x64'
$previousPath=$env:PATH
if (Test-Path -LiteralPath $nodeDirectory) { $env:PATH="$nodeDirectory;$env:PATH" }
$node=(Get-Command node -ErrorAction Stop).Source
$flutter=Join-Path $workspace '.tools/flutter/bin/flutter.bat'
if (!(Test-Path -LiteralPath $flutter)) { $flutter=(Get-Command flutter -ErrorAction Stop).Source }
function Invoke-Checked([string]$Program,[string[]]$CommandArguments) {
  # PowerShell 5.1 may wrap harmless native stderr; the exit code is authoritative.
  $ErrorActionPreference='Continue'
  & $Program @CommandArguments
  $result=$LASTEXITCODE
  if ($result -ne 0) { throw "Acceptance command failed (exit $result): $Program" }
}
Push-Location $workspace
try {
  if ($Profile -in @('quick','full')) {
    Push-Location (Join-Path $workspace 'backend')
    try {
      foreach ($stage in @('lint','build','test')) { Invoke-Checked 'npm.cmd' @('run',$stage) }
    } finally { Pop-Location }
    $toolTests=@(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.test.cjs' -File | Sort-Object Name | ForEach-Object FullName)
    Invoke-Checked $node (@('--test')+$toolTests)
    if ($Profile -eq 'full') {
      Invoke-Checked 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'test-backend.ps1'),'-WithWorker','-WithStorage')
    }
    Push-Location (Join-Path $workspace 'frontend')
    try {
      Invoke-Checked $flutter @('pub','get','--enforce-lockfile')
      Invoke-Checked $flutter @('analyze','--no-pub')
      Invoke-Checked $flutter @('test','--no-pub','--reporter','expanded')
    } finally { Pop-Location }
  } elseif ($Profile -eq 'browser') {
    Invoke-Checked $node @((Join-Path $PSScriptRoot 'test-frontend-api.cjs'),"--$Browser")
  } else {
    $runtimeArguments=@((Join-Path $PSScriptRoot 'verify-local-runtime.cjs'))
    if ($ReuseBuild) { $runtimeArguments+='--reuse-build' }
    Invoke-Checked $node $runtimeArguments
  }
  Write-Output "PASS acceptance $Profile"
} finally { Pop-Location; $env:PATH=$previousPath }

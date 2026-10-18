param([ValidateSet('install','build','check','run','worker','studio')][string]$Action = 'run')
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$portableNode = Join-Path $workspace '.tools/node-v24.22.0-win-x64'
if (Test-Path -LiteralPath $portableNode) { $env:PATH = "$portableNode;$env:PATH" }
Push-Location (Join-Path $workspace 'backend')
try {
  switch ($Action) {
    'install' { & npm.cmd ci }
    'build' { & npm.cmd run build }
    'check' {
      & npm.cmd run lint
      if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
      & npm.cmd run build
      if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
      & npm.cmd test
    }
    'run' { & npm.cmd run start:dev }
    'worker' { & npm.cmd run worker }
    'studio' { & npm.cmd run prisma:studio }
  }
  $result = $LASTEXITCODE
} finally { Pop-Location }
exit $result

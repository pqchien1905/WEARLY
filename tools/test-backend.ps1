$ErrorActionPreference = 'Stop'
$previousEnvironment = @{}
foreach ($name in @('PATH','DATABASE_URL','TEST_DATABASE_URL','NODE_ENV')) {
  $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name,'Process')
}
$workspace = Split-Path -Parent $PSScriptRoot
$portableNode = Join-Path $workspace '.tools/node-v24.22.0-win-x64'
if (Test-Path -LiteralPath $portableNode) { $env:PATH = "$portableNode;$env:PATH" }
Push-Location (Join-Path $workspace 'backend')
try {
  & node (Join-Path $PSScriptRoot 'create-test-db.cjs')
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  $line = Get-Content '.env.test' | Where-Object { $_.StartsWith('TEST_DATABASE_URL=') } | Select-Object -First 1
  if (!$line) { throw 'TEST_DATABASE_URL missing from backend/.env.test' }
  $env:TEST_DATABASE_URL = $line.Substring('TEST_DATABASE_URL='.Length)
  $env:DATABASE_URL = $env:TEST_DATABASE_URL
  $env:NODE_ENV = 'test'
  & npm.cmd run prisma:deploy
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  & npm.cmd run test:e2e
  $result = $LASTEXITCODE
} finally {
  Pop-Location
  foreach ($name in $previousEnvironment.Keys) {
    [Environment]::SetEnvironmentVariable($name,$previousEnvironment[$name],'Process')
  }
}
exit $result

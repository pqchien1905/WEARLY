param([switch]$WithWorker, [switch]$WithStorage)
$ErrorActionPreference = 'Stop'
$previousEnvironment = @{}
foreach ($name in @('PATH','DATABASE_URL','TEST_DATABASE_URL','NODE_ENV','TEST_REDIS_HOST','TEST_REDIS_PORT','TEST_S3_ENDPOINT','TEST_S3_BUCKET','PASSWORD_RECOVERY_ENABLED','LOCAL_MAIL_ENABLED','VNPAY_ENABLED')) {
  $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name,'Process')
}
$workspace = Split-Path -Parent $PSScriptRoot
$portableNode = Join-Path $workspace '.tools/node-v24.22.0-win-x64'
if (Test-Path -LiteralPath $portableNode) { $env:PATH = "$portableNode;$env:PATH" }
Push-Location (Join-Path $workspace 'backend')
try {
  # Windows PowerShell 5.1 wraps redirected native stderr (including Prisma's
  # normal config notice) as ErrorRecord. Native exit codes remain authoritative.
  $ErrorActionPreference = 'Continue'
  & node (Join-Path $PSScriptRoot 'create-test-db.cjs')
  $ErrorActionPreference = 'Stop'
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  $line = Get-Content '.env.test' | Where-Object { $_.StartsWith('TEST_DATABASE_URL=') } | Select-Object -First 1
  if (!$line) { throw 'TEST_DATABASE_URL missing from backend/.env.test' }
  $env:TEST_DATABASE_URL = $line.Substring('TEST_DATABASE_URL='.Length)
  $env:DATABASE_URL = $env:TEST_DATABASE_URL
  $env:NODE_ENV = 'test'
  # Fixtures opt in with their own transports/configuration. A local .env must
  # not activate unrelated integrations or impose its browser origin on tests.
  $env:PASSWORD_RECOVERY_ENABLED = 'false'
  $env:LOCAL_MAIL_ENABLED = 'false'
  $env:VNPAY_ENABLED = 'false'
  if ($WithWorker) {
    if (!$env:TEST_REDIS_HOST) { $env:TEST_REDIS_HOST = '127.0.0.1' }
    if (!$env:TEST_REDIS_PORT) { $env:TEST_REDIS_PORT = '6379' }
  }
  if ($WithStorage) {
    $storage = @{}
    foreach ($entry in Get-Content '.env') {
      if ($entry -match '^(S3_[A-Z_]+)=(.*)$') { $storage[$matches[1]] = $matches[2].Trim('"', "'") }
    }
    if (!$env:TEST_S3_ENDPOINT) { $env:TEST_S3_ENDPOINT = $storage['S3_ENDPOINT'] }
    if (!$env:TEST_S3_BUCKET) { $env:TEST_S3_BUCKET = $storage['S3_BUCKET'] + '-test' }
  }
  $ErrorActionPreference = 'Continue'
  & npm.cmd run prisma:deploy
  $ErrorActionPreference = 'Stop'
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  $ErrorActionPreference = 'Continue'
  & npm.cmd run test:e2e
  $result = $LASTEXITCODE
} finally {
  $ErrorActionPreference = 'Stop'
  Pop-Location
  foreach ($name in $previousEnvironment.Keys) {
    [Environment]::SetEnvironmentVariable($name,$previousEnvironment[$name],'Process')
  }
}
exit $result

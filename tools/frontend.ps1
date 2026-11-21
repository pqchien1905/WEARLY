param(
  [ValidateSet('run','api','demo','build','build-demo','build-api','check','preview')][string]$Action = 'api',
  [string]$ApiUrl = 'http://localhost:3000/api/v1',
  [ValidateSet('web-server','chrome','edge')][string]$Device = 'web-server',
  [ValidateRange(1,65535)][int]$PreviewPort = 5173
)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$portableGit = Join-Path $workspace '.tools/git/cmd'
if (Test-Path -LiteralPath $portableGit) { $env:PATH = "$portableGit;$env:PATH" }
if ($Action -eq 'preview') {
  $webBuild = Join-Path $workspace 'frontend/build/web'
  if (!(Test-Path -LiteralPath (Join-Path $webBuild 'index.html')) -or !(Test-Path -LiteralPath (Join-Path $webBuild 'main.dart.js'))) {
    Write-Host 'No release build found. Run .\tools\frontend.ps1 build-api once, then preview.' -ForegroundColor Yellow
    exit 1
  }
  $node = Join-Path $workspace '.tools/node-v24.22.0-win-x64/node.exe'
  if (!(Test-Path -LiteralPath $node)) { $node = (Get-Command node -ErrorAction Stop).Source }
  Write-Host 'Serving the existing release build; Flutter debugging is not started.' -ForegroundColor Cyan
  Write-Host 'Keep the API and image storage running. Start local MinIO with .\tools\start-storage.ps1.'
  Write-Host 'After source changes, run .\tools\frontend.ps1 build-api again.'
  & $node (Join-Path $PSScriptRoot 'serve.cjs') $PreviewPort
  exit $LASTEXITCODE
}
$flutter = Join-Path $workspace '.tools/flutter/bin/flutter.bat'
if (!(Test-Path -LiteralPath $flutter)) { $flutter = (Get-Command flutter -ErrorAction Stop).Source }
if ($Action -in @('run', 'api', 'demo')) {
  $frontendListeners = @(Get-NetTCPConnection -State Listen -LocalPort 8080 -ErrorAction SilentlyContinue)
  if ($frontendListeners.Count -gt 0) {
    $frontendOwners = ($frontendListeners.OwningProcess | Sort-Object -Unique) -join ', '
    Write-Host "Port 8080 is already in use (PID: $frontendOwners)." -ForegroundColor Yellow
    Write-Host 'If the shop is already running, open http://localhost:8080.'
    Write-Host 'To start a new Flutter session, stop the existing server first (press q in its terminal), then run this command again.'
    exit 1
  }
  Write-Host 'Open http://localhost:8080 in your browser after compilation finishes.' -ForegroundColor Cyan
  if ($Device -eq 'web-server') {
    Write-Host 'After code changes: press R in this terminal, then refresh the browser. Press q to stop.'
  } else {
    Write-Host 'Keep the browser launched by Flutter open for debugging. If it closes, press q and run this command again.'
  }
}
Push-Location (Join-Path $workspace 'frontend')
try {
  # Windows PowerShell 5.1 wraps redirected native stderr as an ErrorRecord,
  # including harmless Flutter diagnostics. Check native exit codes below.
  $ErrorActionPreference = 'Continue'
  & $flutter pub get
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  switch ($Action) {
    'run' { & $flutter run --no-pub -d $Device --web-hostname=127.0.0.1 --web-port=8080 --dart-define=USE_REMOTE_API=true "--dart-define=API_BASE_URL=$ApiUrl" }
    'demo' { & $flutter run --no-pub -d $Device --web-hostname=127.0.0.1 --web-port=8080 --dart-define=DEMO_MODE=true }
    'api' { & $flutter run --no-pub -d $Device --web-hostname=127.0.0.1 --web-port=8080 --dart-define=USE_REMOTE_API=true "--dart-define=API_BASE_URL=$ApiUrl" }
    'build' { & $flutter build web --no-pub --release --dart-define=USE_REMOTE_API=true "--dart-define=API_BASE_URL=$ApiUrl" }
    'build-demo' { & $flutter build web --no-pub --release --dart-define=DEMO_MODE=true }
    'build-api' { & $flutter build web --no-pub --release --dart-define=USE_REMOTE_API=true "--dart-define=API_BASE_URL=$ApiUrl" }
    'check' {
      & $flutter analyze --no-pub
      if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
      & $flutter test --no-pub --reporter expanded
    }
  }
  $result = $LASTEXITCODE
} finally { $ErrorActionPreference = 'Stop'; Pop-Location }
exit $result

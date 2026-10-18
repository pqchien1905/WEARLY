param([ValidateSet('run','build','check','preview')][string]$Action = 'run')
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$portableGit = Join-Path $workspace '.tools/git/cmd'
if (Test-Path -LiteralPath $portableGit) { $env:PATH = "$portableGit;$env:PATH" }
$flutter = Join-Path $workspace '.tools/flutter/bin/flutter.bat'
if (!(Test-Path -LiteralPath $flutter)) { $flutter = (Get-Command flutter -ErrorAction Stop).Source }
if ($Action -eq 'preview') {
  $node = Join-Path $workspace '.tools/node-v24.22.0-win-x64/node.exe'
  if (!(Test-Path -LiteralPath $node)) { $node = (Get-Command node -ErrorAction Stop).Source }
  & $node (Join-Path $PSScriptRoot 'serve.cjs')
  exit $LASTEXITCODE
}
Push-Location (Join-Path $workspace 'frontend')
try {
  & $flutter pub get
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  switch ($Action) {
    'run' { & $flutter run -d chrome --dart-define=DEMO_MODE=true }
    'build' { & $flutter build web --release --dart-define=DEMO_MODE=true }
    'check' {
      & $flutter analyze
      if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
      & $flutter test --reporter expanded
    }
  }
  $result = $LASTEXITCODE
} finally { Pop-Location }
exit $result

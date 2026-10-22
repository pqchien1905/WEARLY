param([ValidateSet('backup')][string]$Action='backup',[string]$EnvFile='backend/.env')
$ErrorActionPreference='Stop'
$workspace=Split-Path -Parent $PSScriptRoot
$node=Join-Path $workspace '.tools/node-v24.22.0-win-x64/node.exe'
if (!(Test-Path -LiteralPath $node)) { $node=(Get-Command node -ErrorAction Stop).Source }
$ErrorActionPreference='Continue'
& $node (Join-Path $PSScriptRoot 'native-recovery.cjs') $Action --env-file $EnvFile
exit $LASTEXITCODE

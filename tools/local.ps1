param(
  [ValidateSet('build','start','status','stop')][string]$Action='status',
  [ValidateRange(1,65535)][int]$ApiPort=3000,
  [ValidateRange(1,65535)][int]$WebPort=8080,
  [string]$EnvFile='backend/.env'
)
$ErrorActionPreference='Stop'
$workspace=Split-Path -Parent $PSScriptRoot
$node=Join-Path $workspace '.tools/node-v24.22.0-win-x64/node.exe'
if (!(Test-Path -LiteralPath $node)) { $node=(Get-Command node -ErrorAction Stop).Source }
$ErrorActionPreference='Continue'
& $node (Join-Path $PSScriptRoot 'local-runtime.cjs') $Action --workspace $workspace --api-port $ApiPort --web-port $WebPort --env-file $EnvFile
exit $LASTEXITCODE

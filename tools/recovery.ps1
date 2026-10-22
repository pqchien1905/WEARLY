param([ValidateSet('backup','restore')][string]$Action='backup',[string]$EnvFile='backend/.env',[string]$Archive)
$ErrorActionPreference='Stop'
$workspace=Split-Path -Parent $PSScriptRoot
$node=Join-Path $workspace '.tools/node-v24.22.0-win-x64/node.exe'
if (!(Test-Path -LiteralPath $node)) { $node=(Get-Command node -ErrorAction Stop).Source }
$recoveryArguments=@((Join-Path $PSScriptRoot 'native-recovery.cjs'),$Action)
if ($Action -eq 'restore') {
  if (!$Archive) { throw 'Restore requires -Archive with a complete local backup directory' }
  $recoveryArguments+=$Archive
}
$recoveryArguments+=@('--env-file',$EnvFile)
$ErrorActionPreference='Continue'
& $node @recoveryArguments
exit $LASTEXITCODE

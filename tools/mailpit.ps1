param([ValidateSet('install','start','status','stop')][string]$Action='start')
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$workspace=Split-Path -Parent $PSScriptRoot
$folder=Join-Path $workspace '.tools/mailpit'
$binary=Join-Path $folder 'mailpit.exe'
$portableNode=Join-Path $workspace '.tools/node-v24.22.0-win-x64'
if(Test-Path -LiteralPath $portableNode){$env:PATH="$portableNode;$env:PATH"}
function Install-Mailpit {
  New-Item -ItemType Directory -Path $folder -Force | Out-Null
  $archive=Join-Path $folder 'mailpit-v1.31.6-windows-amd64.zip'
  if(!(Test-Path -LiteralPath $archive)){
    Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/axllent/mailpit/releases/download/v1.31.6/mailpit-windows-amd64.zip' -OutFile $archive
  }
  $expected='5d5ad094bfb3bac9004f9d1105d2335fea9f8952c09951df73ae0a280e34d3b1'
  if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected){throw 'Mailpit archive checksum mismatch; nothing executed.'}
  $extract=Join-Path $folder 'verified-v1.31.6'
  Expand-Archive -LiteralPath $archive -DestinationPath $extract -Force
  Copy-Item -LiteralPath (Join-Path $extract 'mailpit.exe') -Destination $binary -Force
  & $binary version --no-release-check
  if($LASTEXITCODE -ne 0){throw 'Mailpit version check failed.'}
}
if($Action -eq 'install'){Install-Mailpit;exit 0}
if($Action -eq 'start' -and !(Test-Path -LiteralPath $binary)){Install-Mailpit}
if($Action -eq 'stop'){
  $statePath=Join-Path $folder 'process.json'
  if(!(Test-Path -LiteralPath $statePath)){Write-Output 'No managed Mailpit process.';exit 0}
  $state=Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
  $mailpitProcess=Get-Process -Id $state.pid -ErrorAction SilentlyContinue
  if(!$mailpitProcess){Write-Output 'Mailpit is already stopped.';exit 0}
  if(!$mailpitProcess.Path -or $mailpitProcess.Path -ne $state.binary){throw 'Process identity changed; refusing to stop an unrelated process.'}
  Stop-Process -Id $mailpitProcess.Id
  Write-Output 'Mailpit stopped; inbox database retained.'
  exit 0
}
& node (Join-Path $PSScriptRoot 'mailpit-runtime.cjs') $Action
exit $LASTEXITCODE

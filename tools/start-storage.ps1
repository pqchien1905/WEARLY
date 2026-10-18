param()
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$directory = Join-Path $workspace '.tools/minio'
$executable = Join-Path $directory 'minio.exe'
$expectedHash = 'AF709E6BA68488404E85ACDD22A3030D0F5E56A108D4B27D744F18CEB50861B4'
New-Item -ItemType Directory -Path $directory -Force | Out-Null
if (!(Test-Path -LiteralPath $executable)) {
  Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/minio/minio/releases/download/RELEASE.2025-09-07T16-13-09Z/minio.windows-amd64.RELEASE.2025-09-07T16-13-09Z.exe' -OutFile $executable
}
if ((Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash -ne $expectedHash) { throw 'MinIO checksum mismatch' }
$configuration = @{}
foreach ($line in Get-Content -LiteralPath (Join-Path $workspace 'backend/.env')) {
  if ($line -match '^([A-Z0-9_]+)=(.*)$') { $configuration[$matches[1]] = $matches[2].Trim('"', "'") }
}
if (!$configuration['S3_ACCESS_KEY_ID'] -or !$configuration['S3_SECRET_ACCESS_KEY']) { throw 'Configure S3 credentials in backend/.env first' }
if ($configuration['S3_ENDPOINT'] -notin @('http://localhost:9000','http://127.0.0.1:9000')) { throw 'This helper supports local development storage only' }
$previousUser = $env:MINIO_ROOT_USER
$previousPassword = $env:MINIO_ROOT_PASSWORD
try {
  $listener = Get-NetTCPConnection -LocalPort 9000 -State Listen -ErrorAction SilentlyContinue
  if ($listener) {
    $process = Get-Process -Id $listener[0].OwningProcess
    if ($process.Path -ne $executable) { throw 'Port 9000 is occupied by another process' }
    Write-Output 'Existing local MinIO process found.'
  } else {
    $env:MINIO_ROOT_USER = $configuration['S3_ACCESS_KEY_ID']
    $env:MINIO_ROOT_PASSWORD = $configuration['S3_SECRET_ACCESS_KEY']
    $data = Join-Path $directory 'data'
    $process = Start-Process -FilePath $executable -ArgumentList @('server', ('"' + $data + '"'), '--address', '127.0.0.1:9000', '--console-address', '127.0.0.1:9001') -WorkingDirectory $directory -WindowStyle Hidden -RedirectStandardOutput (Join-Path $directory 'server.log') -RedirectStandardError (Join-Path $directory 'server.err.log') -PassThru
    Set-Content -LiteralPath (Join-Path $directory 'server.pid') -Value $process.Id
  }
  $ready = $false
  for ($attempt = 0; $attempt -lt 20; $attempt++) {
    try {
      $response = Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:9000/minio/health/live' -TimeoutSec 2
      if ($response.StatusCode -eq 200) { $ready = $true; break }
    } catch { Start-Sleep -Seconds 1 }
  }
  if (!$ready) { throw 'MinIO did not become ready; inspect .tools/minio/server.err.log' }
  & node (Join-Path $PSScriptRoot 'prepare-storage.cjs')
  if ($LASTEXITCODE -ne 0) { throw 'Private bucket setup failed' }
  Write-Output 'Local S3 ready: http://127.0.0.1:9000; console: http://127.0.0.1:9001'
} finally {
  $env:MINIO_ROOT_USER = $previousUser
  $env:MINIO_ROOT_PASSWORD = $previousPassword
}

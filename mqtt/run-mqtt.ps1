$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

$mosqExe = 'C:\Program Files\mosquitto\mosquitto.exe'
$confFile = Join-Path $PSScriptRoot 'mosquitto_local.conf'

if (-not (Test-Path $confFile)) {
    Write-Host "[ERROR] File konfigurasi tidak ditemukan: $confFile" -ForegroundColor Red
    exit 1
}

if (Test-Path $mosqExe) {
    Write-Host "Menjalankan Mosquitto dengan config lokal..." -ForegroundColor Green
    & $mosqExe -c $confFile -v
    exit $LASTEXITCODE
}

if (Get-Command mosquitto -ErrorAction SilentlyContinue) {
    Write-Host "Menjalankan Mosquitto dari PATH..." -ForegroundColor Green
    mosquitto -c $confFile -v
    exit $LASTEXITCODE
}

Write-Host "[ERROR] Mosquitto belum ditemukan. Install dulu dari https://mosquitto.org/download/" -ForegroundColor Red
exit 1

$ErrorActionPreference = 'Stop'

$mosquittoExe = 'C:\Program Files\Mosquitto\mosquitto.exe'
$configPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'mqtt\mosquitto_local.conf'

if (-not (Test-Path $mosquittoExe)) {
    Write-Error "Mosquitto tidak ditemukan di: $mosquittoExe"
}

if (-not (Test-Path $configPath)) {
    Write-Error "Config MQTT tidak ditemukan di: $configPath"
}

Write-Host "Menjalankan broker MQTT lokal di port 1884..."
& $mosquittoExe -c $configPath -v

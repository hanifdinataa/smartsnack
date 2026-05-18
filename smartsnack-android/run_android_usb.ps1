$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$safeBuildDir = Join-Path $projectRoot '.build\smartsnack_android'

Write-Host 'Menjalankan SmartSnack Flutter ke HP Android via USB...'
Write-Host "Project : $projectRoot"
Write-Host "Build dir aman : $safeBuildDir"

Push-Location $projectRoot
try {
    flutter run -d TECNO LI7 --build-dir $safeBuildDir
} finally {
    Pop-Location
}

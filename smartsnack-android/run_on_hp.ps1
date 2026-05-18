param(
    [string]$DriveLetter = "S",
    [int]$ApiPort = 8000,
    [string]$DeviceId = ""
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$androidLocalProps = Join-Path $projectRoot "android\local.properties"

if (!(Test-Path $androidLocalProps)) {
    throw "File not found: $androidLocalProps"
}

$props = @{}
Get-Content $androidLocalProps | ForEach-Object {
    if ($_ -match "^\s*([^=]+)=(.*)$") {
        $props[$matches[1].Trim()] = $matches[2].Trim()
    }
}

if (!$props.ContainsKey("sdk.dir")) {
    throw "sdk.dir not found in android/local.properties"
}

$sdkDir = $props["sdk.dir"] -replace "\\\\", "\"
$adb = Join-Path $sdkDir "platform-tools\adb.exe"
if (!(Test-Path $adb)) {
    throw "adb not found: $adb"
}

if (!$props.ContainsKey("flutter.sdk")) {
    throw "flutter.sdk not found in android/local.properties"
}

$flutterSdk = $props["flutter.sdk"] -replace "\\\\", "\"
$flutterBatA = Join-Path $flutterSdk "bin\flutter.bat"
$flutterBatB = Join-Path $flutterSdk "flutter\bin\flutter.bat"
$flutterBat = if (Test-Path $flutterBatA) { $flutterBatA } elseif (Test-Path $flutterBatB) { $flutterBatB } else { "" }
if ([string]::IsNullOrWhiteSpace($flutterBat)) {
    throw "flutter.bat not found under flutter.sdk: $flutterSdk"
}

$drive = "$DriveLetter`:"

# Recreate mapping each run so path is deterministic.
cmd /c "subst $drive /d" | Out-Null
cmd /c "subst $drive `"$projectRoot`""

if ($LASTEXITCODE -ne 0) {
    throw "Failed to map $drive to project root."
}

Write-Host "Mapped project to $drive"
Write-Host "Using adb: $adb"
Write-Host "Using flutter: $flutterBat"

& $adb start-server | Out-Null
$devices = & $adb devices
Write-Host ($devices -join [Environment]::NewLine)

if ($DeviceId -eq "") {
    $deviceRows = $devices | Where-Object { $_ -match "^\S+\s+device$" }
    if ($deviceRows.Count -eq 0) {
        throw "No Android device detected. Connect phone and enable USB debugging."
    }
    $DeviceId = (& $adb get-serialno).Trim()
    if ([string]::IsNullOrWhiteSpace($DeviceId) -or $DeviceId -eq "unknown" -or $DeviceId -eq "no devices/emulators found") {
        throw "Unable to detect Android device serial."
    }
}

Write-Host "Using device: $DeviceId"
& $adb -s $DeviceId reverse "tcp:$ApiPort" "tcp:$ApiPort" | Out-Null
Write-Host "adb reverse tcp:$ApiPort -> tcp:$ApiPort applied."

Push-Location "$drive\"
try {
    & $flutterBat clean
    if ($LASTEXITCODE -ne 0) { throw "flutter clean failed." }

    & $flutterBat pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed." }

    & $flutterBat run -d $DeviceId "--dart-define=API_BASE_URL=http://127.0.0.1:$ApiPort"
    if ($LASTEXITCODE -ne 0) { throw "flutter run failed." }
}
finally {
    Pop-Location
}

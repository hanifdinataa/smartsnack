@echo off
setlocal

cd /d "%~dp0"

set "MOSQ_EXE=C:\Program Files\mosquitto\mosquitto.exe"
set "CONF_FILE=%~dp0mosquitto_local.conf"

if not exist "%CONF_FILE%" (
  echo [ERROR] File konfigurasi tidak ditemukan: "%CONF_FILE%"
  pause
  exit /b 1
)

if exist "%MOSQ_EXE%" (
  echo Menjalankan Mosquitto dengan config lokal...
  "%MOSQ_EXE%" -c "%CONF_FILE%" -v
  goto :eof
)

where mosquitto >nul 2>&1
if %errorlevel%==0 (
  echo Menjalankan Mosquitto dari PATH...
  mosquitto -c "%CONF_FILE%" -v
  goto :eof
)

echo [ERROR] Mosquitto belum ditemukan.
echo Install dulu dari: https://mosquitto.org/download/
pause
exit /b 1

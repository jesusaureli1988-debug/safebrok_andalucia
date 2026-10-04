@echo off
setlocal
cd /d "%~dp0\.."

set "DESKTOP_DISABLED=0"

echo [1/5] Comprobando Flutter...
where flutter >nul 2>nul
if errorlevel 1 (
  echo ERROR: Flutter no esta disponible en PATH.
  exit /b 1
)

echo [2/5] Preparando Flutter solo para Android...
call flutter config --no-enable-windows-desktop
if errorlevel 1 goto :fail
call flutter config --no-enable-linux-desktop
if errorlevel 1 goto :fail
call flutter config --no-enable-macos-desktop
if errorlevel 1 goto :fail
set "DESKTOP_DISABLED=1"

echo [3/5] Limpiando y restaurando dependencias...
call flutter clean
if errorlevel 1 goto :fail
call flutter pub get
if errorlevel 1 goto :fail

echo [4/5] Generando APK release...
call flutter build apk --release
if errorlevel 1 goto :fail

echo [5/5] Verificando resultado...
set "APK=build\app\outputs\flutter-apk\app-release.apk"
if not exist "%APK%" (
  echo ERROR: No se encontro %APK%
  goto :fail
)
for %%I in ("%APK%") do echo APK: %%~fI ^(%%~zI bytes^)
powershell -NoProfile -Command "Get-FileHash -Algorithm SHA256 -LiteralPath '%APK%' | Format-List"

call :restore_desktop
echo.
echo APK generada correctamente. No publiques app_versions hasta subir y probar este archivo.
endlocal
exit /b 0

:fail
set "BUILD_EXIT=%ERRORLEVEL%"
if "%BUILD_EXIT%"=="0" set "BUILD_EXIT=1"
call :restore_desktop
echo.
echo ERROR: No se pudo generar la APK.
endlocal & exit /b %BUILD_EXIT%

:restore_desktop
if "%DESKTOP_DISABLED%"=="1" (
  echo Restaurando soporte Flutter de escritorio...
  call flutter config --enable-windows-desktop >nul
  call flutter config --enable-linux-desktop >nul
  call flutter config --enable-macos-desktop >nul
)
exit /b 0
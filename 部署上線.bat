@echo off
setlocal
cd /d "%~dp0"
if errorlevel 1 (
  echo ERROR: Cannot open the project folder.
  pause
  exit /b 1
)

set "PATH=C:\Windows\System32;C:\Windows\System32\WindowsPowerShell\v1.0;C:\Program Files\Git\cmd;C:\sdk\flutter\bin;%PATH%"

where firebase >nul 2>nul
if errorlevel 1 (
  echo ERROR: "firebase" command not found on PATH.
  echo Install the Firebase CLI first ^(npm install -g firebase-tools^), then run this again.
  pause
  exit /b 1
)

echo [1/2] Building release web bundle...
echo.
call "C:\sdk\flutter\bin\flutter.bat" build web --release
if errorlevel 1 (
  echo.
  echo ERROR: flutter build web failed. See the message above.
  pause
  exit /b 1
)

echo.
echo [2/2] Deploying build\web to Firebase Hosting...
echo.
call firebase deploy --only hosting
set "deploy_exit_code=%errorlevel%"

echo.
if not "%deploy_exit_code%"=="0" (
  echo ERROR: firebase deploy failed. See the message above.
) else (
  echo Deploy finished.
)
echo.
pause
exit /b %deploy_exit_code%

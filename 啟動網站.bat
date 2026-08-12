@echo off
setlocal
cd /d "%~dp0"
if errorlevel 1 (
  echo ERROR: Cannot open the project folder.
  pause
  exit /b 1
)

set "PATH=C:\Windows\System32;C:\Windows\System32\WindowsPowerShell\v1.0;C:\Program Files\Git\cmd;C:\sdk\flutter\bin;%PATH%"

echo Starting Flutter Web in Microsoft Edge...
echo Keep this window open while testing the website.
echo.

call "C:\sdk\flutter\bin\flutter.bat" run -d edge
set "run_exit_code=%errorlevel%"

echo.
if not "%run_exit_code%"=="0" (
  echo ERROR: Flutter could not start. See the message above.
) else (
  echo Flutter has stopped.
)
echo.
pause
exit /b %run_exit_code%

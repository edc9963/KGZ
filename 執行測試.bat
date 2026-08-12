@echo off
setlocal
cd /d "%~dp0"
if errorlevel 1 (
  echo ERROR: Cannot open the project folder.
  pause
  exit /b 1
)

set "PATH=C:\Windows\System32;C:\Windows\System32\WindowsPowerShell\v1.0;C:\Program Files\Git\cmd;C:\sdk\flutter\bin;%PATH%"

echo Running Flutter tests...
echo.

call "C:\sdk\flutter\bin\flutter.bat" test
set "test_exit_code=%errorlevel%"

echo.
if "%test_exit_code%"=="0" (
  echo All tests passed.
) else (
  echo ERROR: Tests failed. See the message above.
)
echo.
pause
exit /b %test_exit_code%

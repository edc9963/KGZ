@echo off
setlocal
cd /d "%~dp0"
if errorlevel 1 (
  echo ERROR: Cannot open the project folder.
  pause
  exit /b 1
)

set "PATH=C:\Windows\System32;C:\Windows\System32\WindowsPowerShell\v1.0;C:\Program Files\Git\cmd;C:\sdk\flutter\bin;%PATH%"

echo Starting Flutter Web server...
echo Keep this window open while testing the website.
echo.

rem Open the browser only after Flutter is listening. Using the web-server
rem device avoids Edge reusing an existing non-debuggable browser process.
start "" /b powershell.exe -NoProfile -WindowStyle Hidden -Command ^
  "$deadline = (Get-Date).AddMinutes(3); while ((Get-Date) -lt $deadline) { $client = [Net.Sockets.TcpClient]::new(); try { $client.Connect('127.0.0.1', 7357); $client.Dispose(); Start-Process 'http://localhost:7357'; exit 0 } catch { $client.Dispose(); Start-Sleep -Milliseconds 500 } }; exit 1"

call "C:\sdk\flutter\bin\flutter.bat" run -d web-server --release --web-hostname 127.0.0.1 --web-port 7357
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

@echo off
REM ============================================================
REM  School 24/7 watchdog - keeps the full stack alive.
REM  Started automatically (start-all.bat / Windows Startup).
REM  Every 60s checks: DB, mirror, backend :5000, tunnel, URL file.
REM  Restarts whatever is down. Logs to logs\watchdog.log
REM ============================================================
setlocal
set ROOT=C:\Users\WALTON\Desktop\school-system
set LOG=%ROOT%\logs\watchdog.log
set URLFILE=%ROOT%\backend\data\tunnel-url.txt

if not exist "%ROOT%\logs" mkdir "%ROOT%\logs"

:loop
timeout /t 60 /nobreak >nul 2>&1 || ping -n 61 127.0.0.1 >nul
echo [%date% %time%] check >> "%LOG%"

REM --- 0. keep the log from growing without bound ---
for %%A in ("%LOG%") do if %%~zA GTR 5242880 move /y "%LOG%" "%LOG%.1" >nul 2>&1

REM --- 1. MariaDB ---
"%ROOT%\runtime\mysql\bin\mysqladmin.exe" -uroot ping >nul 2>&1
if errorlevel 1 (
  >> "%LOG%" echo [%date% %time%] DB DOWN - restarting
  start "School24x7_DB" /min "%ROOT%\runtime\mysql\bin\mysqld.exe" --defaults-file="%ROOT%\db\my.ini" --console
  timeout /t 12 /nobreak >nul
)

REM --- 2. Supabase -> local mirror ---
set "MPID="
if exist "%ROOT%\logs\local_db_mirror.pid" set /p MPID=<"%ROOT%\logs\local_db_mirror.pid"
if defined MPID (
  tasklist /FI "PID eq %MPID%" 2>nul | find "%MPID%" >nul
  if errorlevel 1 set "MPID="
)
if not defined MPID (
  >> "%LOG%" echo [%date% %time%] mirror DOWN - restarting
  del "%ROOT%\logs\local_db_mirror.pid" >nul 2>&1
  start "School24x7_Mirror" /min cmd /c "cd /d %ROOT% && node scripts\local_db_mirror.js >nul 2>> %ROOT%\logs\local_db_mirror_error.log"
)

REM --- 3. Backend ---
REM NOTE: findstr treats a space-separated pattern as two OR-ed strings, which
REM made every LISTENING line match. Use /C: so each fragment is one literal.
netstat -ano | findstr /C:":5000 " | findstr /C:"LISTENING" >nul
if errorlevel 1 (
  >> "%LOG%" echo [%date% %time%] backend DOWN - restarting
  start "School24x7_API" /min cmd /c "cd /d %ROOT%\backend && set PORT=5000 && node server.js >> %ROOT%\logs\backend.log 2>&1"
  timeout /t 12 /nobreak >nul 2>&1 || ping -n 13 127.0.0.1 >nul
)

REM --- 4. Tunnel (ngrok static-domain tunnel; cloudflared kept as fallback) ---
tasklist /FI "IMAGENAME eq ngrok.exe" 2>nul | find /I "ngrok.exe" >nul
if errorlevel 1 (
  tasklist /FI "IMAGENAME eq ngrok" 2>nul | find /I "ngrok" >nul
  if errorlevel 1 (
    >> "%LOG%" echo [%date% %time%] ngrok DOWN - restarting
    start "School24x7_Tunnel" /min cmd /c "ngrok start --config C:\Users\WALTON\AppData\Local\ngrok\ngrok.yml school --log stdout >> %ROOT%\logs\ngrok.log 2>&1"
    timeout /t 20 /nobreak >nul 2>&1 || ping -n 21 127.0.0.1 >nul
  )
)

REM --- 5. Refresh published URL file ---
call "%ROOT%\backend\refresh-ngrok-url.bat" >nul 2>&1
if not exist "%URLFILE%" call "%ROOT%\backend\refresh-tunnel-url.bat" >nul 2>&1
goto loop
endlocal
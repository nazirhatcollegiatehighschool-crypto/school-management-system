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

REM --- absolute Windows tools: when the watchdog is launched from a shell that
REM has Git/MSYS on PATH, bare `find`/`tasklist`/`netstat` resolve to Unix
REM builds (GNU find rejects /I and /FI) and every check reports a false
REM "DOWN", spawning duplicate processes every cycle.
set "SYS=%SystemRoot%\System32"
set "TASKLIST=%SYS%\tasklist.exe"
set "FIND=%SYS%\find.exe"
set "FINDSTR=%SYS%\findstr.exe"
set "NETSTAT=%SYS%\NETSTAT.EXE"
set "PING=%SYS%\ping.exe"

:loop
timeout /t 60 /nobreak >nul 2>&1 || "%PING%" -n 61 127.0.0.1 >nul
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
REM Ask for an actual running mirror process instead of trusting the pid file:
REM the file can be deleted while the service keeps running, which used to
REM spawn a duplicate mirror every cycle.
set "MLIVE="
for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\mirror-alive.ps1"`) do set "MLIVE=%%P"
if not defined MLIVE (
  >> "%LOG%" echo [%date% %time%] mirror DOWN - restarting
  del "%ROOT%\logs\local_db_mirror.pid" >nul 2>&1
  start "School24x7_Mirror" /min cmd /c "cd /d %ROOT% && node scripts\local_db_mirror.js >nul 2>> %ROOT%\logs\local_db_mirror_error.log"
)

REM --- 3. Backend ---
REM NOTE: findstr treats a space-separated pattern as two OR-ed strings, which
REM made every LISTENING line match. Use /C: so each fragment is one literal.
"%NETSTAT%" -ano | "%FINDSTR%" /C:":5000 " | "%FINDSTR%" /C:"LISTENING" >nul
if errorlevel 1 (
  >> "%LOG%" echo [%date% %time%] backend DOWN - restarting
  start "School24x7_API" /min cmd /c "cd /d %ROOT%\backend && set PORT=5000 && node server.js >> %ROOT%\logs\backend.log 2>&1"
  timeout /t 12 /nobreak >nul 2>&1 || ping -n 13 127.0.0.1 >nul
)

REM --- 4. Tunnel (ngrok static-domain tunnel; cloudflared kept as fallback) ---
"%TASKLIST%" /FI "IMAGENAME eq ngrok.exe" /NH 2>nul | "%FIND%" /I "ngrok.exe" >nul
if errorlevel 1 (
  "%TASKLIST%" /FI "IMAGENAME eq ngrok" /NH 2>nul | "%FIND%" /I "ngrok" >nul
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
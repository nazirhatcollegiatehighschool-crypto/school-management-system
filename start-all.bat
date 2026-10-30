@echo off
REM ============================================================
REM  School 24/7 - one-shot auto-start
REM  Starts (in order, only if not already running):
REM    1) MariaDB (project data dir)
REM    2) Supabase -> local MariaDB mirror (immediate catch-up, then every 5 min)
REM    3) Node backend on 0.0.0.0:5000
REM    4) Public Cloudflare quick tunnel
REM    5) Watchdog (keeps the whole stack alive)
REM  Safe to run at every computer startup - it is idempotent.
REM ============================================================
setlocal
set ROOT=%~dp0
set MYSQLBIN=%ROOT%runtime\mysql\bin
cd /d "%ROOT%"

echo [1/4] MariaDB ...
"%MYSQLBIN%\mysqladmin.exe" -uroot ping >nul 2>&1
if errorlevel 1 (
  echo   - starting mysqld...
  start "School24x7_DB" /min "%MYSQLBIN%\mysqld.exe" --defaults-file="%ROOT%db\my.ini" --console
  timeout /t 12 /nobreak >nul
  "%MYSQLBIN%\mysqladmin.exe" -uroot ping >nul 2>&1
  if errorlevel 1 ( echo   !! DB failed to start - check db\my.ini & mysql error log & pause & exit /b 1 )
  echo   - DB ready.
) else (
  echo   - already running.
)

echo [2/5] Local mirror (Supabase -> MariaDB) ...
if not exist "%ROOT%logs" mkdir "%ROOT%logs"
start "School24x7_Mirror" /min cmd /c "cd /d %ROOT% && node scripts\local_db_mirror.js >nul 2>> %ROOT%logs\local_db_mirror_error.log"
timeout /t 4 /nobreak >nul
if exist "%ROOT%logs\local_db_mirror.pid" ( echo   - mirror service started; initial catch-up is running. ) else ( echo   - !! mirror not started yet - check logs\local_db_mirror.log )

echo [3/5] Backend :5000 ...
netstat -ano | findstr /R ":5000 .*LISTENING" >nul
if errorlevel 1 (
  start "School24x7_API" /min cmd /c "cd /d %ROOT%backend && set PORT=5000 && node server.js >> %ROOT%logs\backend.log 2>&1"
  timeout /t 8 /nobreak >nul
)
netstat -ano | findstr /R ":5000 .*LISTENING" >nul && echo   - API ready. || echo   !! API not listening yet - check logs\backend.log

echo [4/5] Public tunnel (ngrok static domain) ...
tasklist /FI "IMAGENAME eq ngrok.exe" 2>nul | find /I "ngrok.exe" >nul
if errorlevel 1 (
  tasklist /FI "IMAGENAME eq ngrok" 2>nul | find /I "ngrok" >nul
  if errorlevel 1 (
    start "School24x7_Tunnel" /min cmd /c "ngrok start --config C:\Users\WALTON\AppData\Local\ngrok\ngrok.yml school --log stdout >> %ROOT%logs\ngrok.log 2>&1"
    echo   - starting ngrok, waiting for URL...
  ) else (
    echo   - ngrok already running.
  )
) else (
  echo   - ngrok already running.
)

echo [5/5] Watchdog ...
tasklist /FI "WINDOWTITLE eq School24x7_Watchdog" 2>nul | find /I "cmd.exe" >nul
if errorlevel 1 (
  start "School24x7_Watchdog" /min "%ROOT%watchdog.bat"
  echo   - watchdog started.
) else (
  echo   - watchdog already running.
)

timeout /t 12 /nobreak >nul

REM Refresh the published tunnel URL file for the apps/admin.
call "%ROOT%backend\refresh-ngrok-url.bat" >nul 2>&1

echo.
echo All done. Public URL in backend\data\tunnel-url.txt
endlocal
@echo off
REM School 24/7 local server: MariaDB (project runtime + data dir) + Supabase mirror + Node backend on :5000
REM Everything lives inside the project folder — portable, no admin needed.
REM The backend still writes to Supabase; the mirror only refreshes the local
REM MariaDB copy so offline/local reporting can read current data.
setlocal
cd /d "%~dp0"
set ROOT=%~dp0..\
echo [1/3] Checking MariaDB...
"%ROOT%runtime\mysql\bin\mysqladmin.exe" -uroot ping >nul 2>&1
if errorlevel 1 (
  echo Starting MariaDB from project datadir...
  start "SchoolDB" /min "%ROOT%runtime\mysql\bin\mysqld.exe" --defaults-file="%ROOT%db\my.ini" --console
  timeout /t 12 >nul
  "%ROOT%runtime\mysql\bin\mysqladmin.exe" -uroot ping >nul 2>&1
  if errorlevel 1 ( echo DB FAILED to start & pause & exit /b 1 )
)
echo [2/3] Starting Supabase -> local MariaDB mirror (immediate catch-up)...
if not exist "%ROOT%logs" mkdir "%ROOT%logs"
start "School24x7_Mirror" /min cmd /c "cd /d %ROOT% && node scripts\local_db_mirror.js >nul 2>> %ROOT%logs\local_db_mirror_error.log"
timeout /t 4 >nul
if exist "%ROOT%logs\local_db_mirror.pid" ( echo   - mirror service started. ) else ( echo   - !! mirror not started - check logs\local_db_mirror.log )
echo [3/3] Starting backend on http://0.0.0.0:5000 ...
set PORT=5000
node server.js
endlocal

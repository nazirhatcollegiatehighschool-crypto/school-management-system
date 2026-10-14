@echo off
REM School 24/7 local server: MariaDB (project runtime + data dir) + Node backend on :5000
REM Everything lives inside the project folder — portable, no admin needed.
cd /d "%~dp0"
set ROOT=%~dp0..\
echo [1/2] Checking MariaDB...
"%ROOT%runtime\mysql\bin\mysqladmin.exe" -uroot ping >nul 2>&1
if errorlevel 1 (
  echo Starting MariaDB from project datadir...
  start "SchoolDB" /min "%ROOT%runtime\mysql\bin\mysqld.exe" --defaults-file="%ROOT%db\my.ini" --console
  timeout /t 12 >nul
  "%ROOT%runtime\mysql\bin\mysqladmin.exe" -uroot ping >nul 2>&1
  if errorlevel 1 ( echo DB FAILED to start & pause & exit /b 1 )
)
echo [2/2] Starting backend on http://0.0.0.0:5000 ...
set PORT=5000
node server.js

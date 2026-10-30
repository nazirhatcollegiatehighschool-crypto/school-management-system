@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\backup_database.ps1"
if errorlevel 1 exit /b 1
echo Backup completed successfully.

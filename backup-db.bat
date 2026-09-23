@echo off
REM Nightly database backup - keeps last 14 days
set BACKUP_DIR=C:\Users\WALTON\school-system\backups
if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%"
set STAMP=%date:~-4%%date:~3,2%%date:~0,2%_%time:~0,2%%time:~3,2%
set STAMP=%STAMP: =0%
"C:\Users\WALTON\mysql\mysql-8.0.37-winx64\bin\mysqldump.exe" -u root school_db > "%BACKUP_DIR%\school_db_%STAMP%.sql" 2>nul
forfiles /p "%BACKUP_DIR%" /m *.sql /d -14 /c "cmd /c del @path" 2>nul
echo [%date% %time%] backup done >> %BACKUP_DIR%\backup.log
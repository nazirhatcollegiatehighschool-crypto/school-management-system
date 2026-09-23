@echo off
REM Watchdog - checks every 5 minutes, restarts server if down
:loop
timeout /t 300 /nobreak >nul
curl -s -o nul http://127.0.0.1:5000/api/health
if errorlevel 1 (
    echo [%date% %time%] Server down - restarting >> C:\Users\WALTON\school-system\watchdog.log
    for /f "tokens=5" %%a in ('netstat -ano ^| findstr :5000 ^| findstr LISTENING') do taskkill /PID %%a /F >nul 2>&1
    cd /d C:\Users\WALTON\school-system\backend
    start "SchoolAPI" /min cmd /c "node server.js >> server.log 2>&1"
)
tasklist /FI "IMAGENAME eq ngrok.exe" | find /I "ngrok.exe" >nul
if errorlevel 1 (
    echo [%date% %time%] Tunnel down - restarting >> C:\Users\WALTON\school-system\watchdog.log
    start "" /min "C:\Users\WALTON\Desktop\transcript-generator\node_modules\ngrok\bin\ngrok.exe" http --domain=siberian-unnoticed-poser.ngrok-free.dev --authtoken=3I2tPnO0E6Dic2mJCMovJ1D6vMB_9LXWD3GYhkv3gf2yGDs8 5000
)
goto loop
@echo off
REM School backend + ngrok tunnel (ONE permanent public URL).
REM Public URL: https://alphabet-stardust-exceeding.ngrok-free.dev
REM Mobile apps already point at this URL by default - no rebuild needed.
REM Run once after every PC reboot. Leave the ngrok window open.
cd /d C:\Users\WALTON\Desktop\school-system\backend
echo [1/2] Starting backend on :5000 ...
start "school-backend" cmd /k "node server.js"
timeout /t 6 /nobreak >nul
echo [2/2] Starting ngrok tunnel ...
echo URL: https://alphabet-stardust-exceeding.ngrok-free.dev
ngrok http 5000

@echo off
REM Public tunnel for the school server via ngrok (static domain).
REM Uses the NEW ngrok account token saved in ngrok.yml.
REM Static domain gives a PERMANENT public URL that never rotates.
REM Logs to ..\logs\ngrok.log ; the URL is also saved to
REM backend\data\tunnel-url.txt by refresh-ngrok-url.bat / watchdog.
cd /d "%~dp0"
echo Starting ngrok tunnel to http://localhost:5000 ...
echo Keep this window OPEN. The https://....ngrok.app URL below is public & permanent.
ngrok http 5000 --log stdout >> "%~dp0..\logs\ngrok.log" 2>&1
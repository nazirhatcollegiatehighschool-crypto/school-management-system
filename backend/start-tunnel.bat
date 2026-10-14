@echo off
REM Public tunnel for the school server (Cloudflare Quick Tunnel).
REM URL changes on each start; the live URL is also saved to ..\logs\tunnel.log
REM and backend\data\tunnel-url.txt by the watchdog.
cd /d "%~dp0"
echo Starting Cloudflare tunnel to http://localhost:5000 ...
echo Keep this window OPEN. The https://....trycloudflare.com URL below is public.
"%~dp0..\bin\cloudflared.exe" tunnel --url http://localhost:5000 --no-autoupdate > "%~dp0..\logs\tunnel.log" 2>&1

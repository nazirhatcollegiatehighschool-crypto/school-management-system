@echo off
REM Extract the current live ngrok URL from logs\ngrok.log and publish it
REM to backend\data\tunnel-url.txt (used by the admin panel / docs / apps).
setlocal
set ROOT=%~dp0..\
set LOG=%ROOT%logs\ngrok.log
set URLFILE=%ROOT%backend\data\tunnel-url.txt

powershell -noprofile -command "$m=@((Select-String -Path '%LOG%' -Pattern 'https://[a-z0-9-]+\.(ngrok-free|ngrok)(\.app|\.io|\.dev)' -AllMatches | ForEach-Object { $_.Matches.Value })); if($m.Count -gt 0){ $u=[string]$m[$m.Count-1]; $u=$u.Trim(); Set-Content -Path '%URLFILE%' -Value $u -Encoding ascii; Write-Output ('URL='+$u) } else { Write-Output 'noneturl' }"
endlocal
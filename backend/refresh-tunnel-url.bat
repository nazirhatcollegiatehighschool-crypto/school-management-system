@echo off
REM Extract the current live tunnel URL from logs\tunnel.log and publish it
REM to backend\data\tunnel-url.txt (used by the admin panel / docs / apps).
setlocal
set ROOT=%~dp0..\
set LOG=%ROOT%logs\tunnel.log
set URLFILE=%ROOT%backend\data\tunnel-url.txt

powershell -noprofile -command "$m=(Select-String -Path '%LOG%' -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' -AllMatches | ForEach-Object { $_.Matches.Value }); if($m){ $u=$m[$m.Count-1].Trim(); $u | Out-File -Encoding ascii '%URLFILE%'; Write-Output ('URL='+$u) } else { Write-Output 'noneturl' }"
endlocal
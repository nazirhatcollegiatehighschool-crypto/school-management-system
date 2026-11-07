# Prints the PID of a running Supabase -> MariaDB mirror process (scripts/local_db_mirror.js).
# Exits 1 when no mirror is alive, so watchdog.bat can decide to restart it.
# Using the process command line (not the pid file) avoids false "DOWN" reports
# when the pid file was removed while the service kept running.
$proc = Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -and $_.CommandLine -match 'local_db_mirror\.js' } |
  Select-Object -First 1
if ($proc) {
  [Console]::Out.WriteLine($proc.ProcessId)
  exit 0
}
exit 1

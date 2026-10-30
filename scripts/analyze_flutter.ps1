$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$flutterCommand = Get-Command flutter -ErrorAction Stop
$flutterBin = Split-Path -Parent $flutterCommand.Source
$dartExe = Join-Path $flutterBin 'cache\dart-sdk\bin\dart.exe'
if (-not (Test-Path -LiteralPath $dartExe)) {
  throw "Dart SDK was not found beside Flutter at: $dartExe"
}

$apps = @('admin_app', 'teacher_app', 'guardian_app')
$failed = @()
foreach ($app in $apps) {
  $appPath = Join-Path $repoRoot "apps\$app"
  if (-not (Test-Path -LiteralPath (Join-Path $appPath 'pubspec.yaml'))) {
    $failed += "$app (pubspec.yaml missing)"
    continue
  }

  Write-Host "Analyzing $app..."
  Push-Location $appPath
  try {
    & $dartExe analyze lib
    if ($LASTEXITCODE -ne 0) { $failed += "$app (exit $LASTEXITCODE)" }
  } finally {
    Pop-Location
  }
}

if ($failed.Count) {
  Write-Error "Flutter analysis needs attention: $($failed -join ', ')"
  exit 1
}

Write-Host 'All three Flutter apps analyzed successfully.'

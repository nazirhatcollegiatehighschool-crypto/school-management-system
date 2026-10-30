param(
  [Parameter(Mandatory = $true)][string]$InPath,
  [Parameter(Mandatory = $true)][string]$OutPath
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
$raw = (Get-Content -LiteralPath $InPath -Raw).Trim()
$bytes = [Convert]::FromBase64String($raw)
$protected = [Security.Cryptography.ProtectedData]::Protect(
  $bytes,
  $null,
  [Security.Cryptography.DataProtectionScope]::CurrentUser
)
[IO.File]::WriteAllText($OutPath, ([Convert]::ToBase64String($protected) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))

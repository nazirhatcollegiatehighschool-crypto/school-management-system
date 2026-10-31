param(
    [string]$OutputDirectory = 'apps/release_builds/review_20261025_final'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$secretDirectory = Join-Path $repoRoot '.release-signing'
$keystorePath = Join-Path $secretDirectory 'school-system-release-2026.jks'
$encryptedPasswordPath = Join-Path $secretDirectory 'password-2026.dpapi'
$outputDirectory = Join-Path $repoRoot $OutputDirectory
$apps = @(
    @{ Directory = 'admin_app'; Artifact = 'admin-app-release.apk' },
    @{ Directory = 'teacher_app'; Artifact = 'teacher-app-release.apk' },
    @{ Directory = 'guardian_app'; Artifact = 'guardian-app-release.apk' }
)

if (!(Test-Path $keystorePath) -or !(Test-Path $encryptedPasswordPath)) {
    throw 'Local release signing files are missing. Do not create or commit a plaintext password file.'
}

if (Test-Path -LiteralPath $outputDirectory) {
    $existingArtifacts = @(
        $apps | ForEach-Object {
            Join-Path $outputDirectory $_.Artifact
        } | Where-Object { Test-Path -LiteralPath $_ }
    )
    if ($existingArtifacts.Count -gt 0) {
        throw 'Release APKs already exist in the output directory. Choose a new directory instead of overwriting them.'
    }
}

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$encryptedPassword = Get-Content -LiteralPath $encryptedPasswordPath -Raw
$securePassword = ConvertTo-SecureString $encryptedPassword
$passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)

try {
    $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
    $env:SCHOOL_RELEASE_KEYSTORE = $keystorePath
    $env:SCHOOL_RELEASE_STORE_PASSWORD = $password
    $env:SCHOOL_RELEASE_KEY_ALIAS = 'school-system-release'
    $env:SCHOOL_RELEASE_KEY_PASSWORD = $password

    foreach ($app in $apps) {
        $appDirectory = Join-Path $repoRoot ('apps/' + $app.Directory)
        Push-Location $appDirectory
        try {
            flutter build apk --release --no-pub
            if ($LASTEXITCODE -ne 0) {
                throw "Release build failed for $($app.Directory) (exit $LASTEXITCODE)."
            }
        }
        finally {
            Pop-Location
        }

        $apk = Join-Path $appDirectory 'build/app/outputs/flutter-apk/app-release.apk'
        if (!(Test-Path $apk)) {
            throw "Release APK output is missing for $($app.Directory)."
        }
        $destination = Join-Path $outputDirectory $app.Artifact
        Copy-Item -LiteralPath $apk -Destination $destination -Force
        $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        Write-Output "$($app.Directory): release APK built; SHA256 $hash"
    }
}
finally {
    Remove-Item Env:SCHOOL_RELEASE_KEYSTORE -ErrorAction SilentlyContinue
    Remove-Item Env:SCHOOL_RELEASE_STORE_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:SCHOOL_RELEASE_KEY_ALIAS -ErrorAction SilentlyContinue
    Remove-Item Env:SCHOOL_RELEASE_KEY_PASSWORD -ErrorAction SilentlyContinue
    if ($passwordPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    }
    $password = $null
    $securePassword = $null
}

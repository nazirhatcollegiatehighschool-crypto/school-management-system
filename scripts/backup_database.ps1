$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$backupDir = Join-Path $projectRoot 'database_backups'
$dumpExe = Join-Path $projectRoot 'runtime/mysql/bin/mysqldump.exe'
$adminExe = Join-Path $projectRoot 'runtime/mysql/bin/mysqladmin.exe'
if (-not (Test-Path -LiteralPath $dumpExe)) { throw "mysqldump not found: $dumpExe" }
if (-not (Test-Path -LiteralPath $adminExe)) { throw "mysqladmin not found: $adminExe" }
& $adminExe -h 127.0.0.1 -P 3306 -u root ping *> $null
if ($LASTEXITCODE -ne 0) { throw 'Local MariaDB is not reachable on 127.0.0.1:3306.' }
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$sql = Join-Path $backupDir "school_system_local_mariadb_$stamp.sql"
$archive = "$sql.gz"
$verify = Join-Path $env:TEMP "school_restore_verify_$stamp.sql"
try {
    & $dumpExe --host=127.0.0.1 --port=3306 --user=root --all-databases --single-transaction --routines --events --triggers --hex-blob --result-file=$sql
    if ($LASTEXITCODE -ne 0) { throw "mysqldump failed with exit code $LASTEXITCODE" }
    $source = [IO.File]::OpenRead($sql)
    try {
        $target = [IO.File]::Create($archive)
        try {
            $gzip = [IO.Compression.GzipStream]::new($target, [IO.Compression.CompressionLevel]::Optimal)
            try { $source.CopyTo($gzip) } finally { $gzip.Dispose() }
        } finally { $target.Dispose() }
    } finally { $source.Dispose() }
    # Full decompress (not just a header probe) so a truncated archive cannot be
    # reported as a usable backup.
    $compressed = [IO.File]::OpenRead($archive)
    try {
        $gunzip = [IO.Compression.GzipStream]::new($compressed, [IO.Compression.CompressionMode]::Decompress)
        try {
            $out = [IO.File]::Create($verify)
            try { $gunzip.CopyTo($out) } finally { $out.Dispose() }
        } finally { $gunzip.Dispose() }
    } finally { $compressed.Dispose() }
    $verifiedLength = (Get-Item -LiteralPath $verify).Length
    if ($verifiedLength -lt 1024) { throw 'Decompressed dump is unexpectedly small.' }
    $tail = Get-Content -LiteralPath $verify -Tail 4
    if (-not ($tail -match 'Dump completed')) { throw 'Decompressed dump has no completion marker.' }
    $tableCount = (Select-String -LiteralPath $verify -Pattern '^CREATE TABLE' -AllMatches).Count
    $insertCount = (Select-String -LiteralPath $verify -Pattern '^INSERT INTO' -AllMatches).Count
    if ($tableCount -lt 1) { throw 'Decompressed dump contains no tables.' }
    Remove-Item -LiteralPath $sql -Force
    $hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    $bytes = (Get-Item -LiteralPath $archive).Length
    $manifest = [ordered]@{
        format = 'MariaDB logical dump, gzip compressed'
        created_local = (Get-Date).ToString('o')
        archive = [IO.Path]::GetFileName($archive)
        archive_bytes = $bytes
        archive_sha256 = $hash
        decompressed_bytes = $verifiedLength
        create_table_statements = $tableCount
        insert_statements = $insertCount
        completion_marker_verified = $true
    }
    $manifest | ConvertTo-Json | Set-Content -LiteralPath "$archive.manifest.json" -Encoding UTF8
    "$hash  $([IO.Path]::GetFileName($archive))" | Set-Content -LiteralPath "$archive.sha256" -Encoding ASCII
    Write-Output "Backup created: $archive"
    Write-Output "Compressed bytes: $bytes"
    Write-Output "SHA256: $hash"
    Write-Output "Verified: fully decompressed ($verifiedLength bytes, $tableCount tables, $insertCount INSERT statements)."
    $cutoff = (Get-Date).AddDays(-30)
    Get-ChildItem -LiteralPath $backupDir -Filter 'school_system_local_mariadb_*.sql.gz' |
        Where-Object LastWriteTime -lt $cutoff |
        ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath "$($_.FullName).sha256" -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath "$($_.FullName).manifest.json" -Force -ErrorAction SilentlyContinue
        }
} catch {
    Remove-Item -LiteralPath $sql,$archive -Force -ErrorAction SilentlyContinue
    throw
} finally {
    Remove-Item -LiteralPath $verify -Force -ErrorAction SilentlyContinue
}

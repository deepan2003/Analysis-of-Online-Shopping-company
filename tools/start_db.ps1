# start_db.ps1 - start the portable MariaDB/MySQL-compatible server on port 3307
$root = Split-Path -Parent $PSScriptRoot
$mar  = Join-Path $root 'tools\mariadb-11.4.5-winx64'
$ini  = Join-Path $mar 'data\my.ini'
$mysqld = Join-Path $mar 'bin\mysqld.exe'
$mysqladmin = Join-Path $mar 'bin\mysqladmin.exe'

if (-not (Test-Path $mysqld)) {
    Write-Error "Server binaries not found at $mysqld. See tools/README_DB.md."
    exit 1
}

& $mysqladmin --port=3307 -u root -proot ping 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Database already running on port 3307."
    exit 0
}

Start-Process -FilePath $mysqld -ArgumentList "--defaults-file=`"$ini`"" -WindowStyle Hidden
for ($i = 0; $i -lt 45; $i++) {
    Start-Sleep -Seconds 1
    & $mysqladmin --port=3307 -u root -proot ping 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Database is up on 127.0.0.1:3307 (user root / password root)."
        exit 0
    }
}
Write-Error "Database did not start within 45 seconds. Check $mar\data\*.err"
exit 1

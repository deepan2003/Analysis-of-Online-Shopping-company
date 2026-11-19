# stop_db.ps1 - shut down the local analytics database cleanly
$root = Split-Path -Parent $PSScriptRoot
$mar  = Join-Path $root 'tools\mariadb-11.4.5-winx64'
& (Join-Path $mar 'bin\mysqladmin.exe') --port=3307 -u root -proot shutdown
Write-Host "Database stopped."

# run_all.ps1 - rebuild the whole project from the raw CSVs
# Usage:  powershell -ExecutionPolicy Bypass -File sql\run_all.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$mar  = Join-Path $root 'tools\mariadb-11.4.5-winx64\bin'
$mysql = Join-Path $mar 'mysql.exe'
$env:MYSQL_PWD = 'root'

function Invoke-Sql([string]$file, [switch]$local) {
    Write-Host "-- running $file"
    $extra = if ($local) { '--local-infile=1' } else { '' }
    cmd /c "`"$mysql`" --port=3307 -u root $extra < `"$file`""
    if ($LASTEXITCODE -ne 0) { throw "SQL failed: $file" }
}

& (Join-Path $PSScriptRoot '..\tools\start_db.ps1')

python (Join-Path $PSScriptRoot 'prep_reviews.py')
Invoke-Sql (Join-Path $PSScriptRoot '00_create_database.sql')
Invoke-Sql (Join-Path $PSScriptRoot '01_load_data.sql') -local
Invoke-Sql (Join-Path $PSScriptRoot '30_cohort_retention.sql')
Invoke-Sql (Join-Path $PSScriptRoot '40_logistics_delivery.sql')
Invoke-Sql (Join-Path $PSScriptRoot '50_views_for_bi.sql')

# analysis scripts write their result sets to exports/
foreach ($f in '10_revenue_by_month.sql','20_rfm_segmentation.sql','30_cohort_retention.sql','40_logistics_delivery.sql') {
    $name = [IO.Path]::GetFileNameWithoutExtension($f)
    Write-Host "-- result set -> exports\$name.txt"
    cmd /c "`"$mysql`" --port=3307 -u root -t < `"$(Join-Path $PSScriptRoot $f)`" > `"$(Join-Path $root "exports\$name.txt")`""
}

python (Join-Path $PSScriptRoot 'export_views.py')
python (Join-Path $root 'dashboard\build_dashboard.py')
python (Join-Path $root 'dashboard\screenshot.py')
Write-Host "Done. Open dashboard\page1.html or dashboard\Olist_Dashboard.pdf"
exit 0

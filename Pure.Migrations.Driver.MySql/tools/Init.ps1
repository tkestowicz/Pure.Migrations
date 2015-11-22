param($installPath, $toolsPath, $package, $project)

$packagesPath = Join-Path $installPath ".."
$corePackageDirectory = [System.IO.Directory]::EnumerateDirectories($packagesPath, "Pure.Migrations.Core*") | Sort-Object Name -Descending | Select-Object -First 1

$coreToolsPath = Join-Path $corePackageDirectory "tools"
$driverPath = Join-Path $toolsPath 'Pure.Migrations.Driver.Mysql.psd1'

Import-Module $coreToolsPath\Pure.Migrations.Core.Psd1 -ArgumentList @($driverPath, $coreToolsPath, $packagesPath) -Force -DisableNameChecking
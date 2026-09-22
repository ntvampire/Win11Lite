#Requires -Version 5.1
<#
.SYNOPSIS
    Универсальный онлайн-загрузчик Win11Lite для выполнения через:
    irm https://raw.githubusercontent.com/ntvampire/Win11Lite/main/start.ps1 | iex
#>

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$repoBase = "https://raw.githubusercontent.com/ntvampire/Win11Lite/main"
$tempDir = Join-Path -Path $env:TEMP -ChildPath "Win11Lite"

if (Test-Path $tempDir) {
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

$files = @(
    "Optimize-Windows.ps1",
    "Run-As-Admin.cmd",
    "README.md",
    "modules/Common.psm1",
    "modules/StorageAndHdd.psm1",
    "modules/MemoryAndServices.psm1",
    "modules/VisualAndGpu.psm1",
    "modules/BloatwareCleanup.psm1"
)

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " Загрузка Win11Lite (Оптимизация Windows 10/11 x64)...   " -ForegroundColor Yellow
Write-Host "=========================================================" -ForegroundColor Cyan

foreach ($file in $files) {
    $targetFile = Join-Path -Path $tempDir -ChildPath ($file -replace '/', '\')
    $parent = Split-Path -Path $targetFile -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $url = "$repoBase/$file"
    try {
        Invoke-RestMethod -Uri $url -OutFile $targetFile -ErrorAction Stop
    }
    catch {
        Write-Host "[-] Ошибка загрузки $url : $($_.Exception.Message)" -ForegroundColor Red
    }
}

$mainScript = Join-Path -Path $tempDir -ChildPath "Optimize-Windows.ps1"
if (Test-Path $mainScript) {
    & $mainScript @args
} else {
    Write-Host "[-] Ошибка: главный скрипт не найден." -ForegroundColor Red
}

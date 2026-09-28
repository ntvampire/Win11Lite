Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue
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
Write-Host " Win11Lite: Downloading optimization suite...           " -ForegroundColor Yellow
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
        Write-Host "[-] Download error: $url : $($_.Exception.Message)" -ForegroundColor Red
    }
}

Get-ChildItem -Path $tempDir -Recurse | Unblock-File -ErrorAction SilentlyContinue

$mainScript = Join-Path -Path $tempDir -ChildPath "Optimize-Windows.ps1"
if (Test-Path $mainScript) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$mainScript" @args
} else {
    Write-Host "[-] Error: main script not found." -ForegroundColor Red
}
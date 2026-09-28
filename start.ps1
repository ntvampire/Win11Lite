Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repoBase = "https://raw.githubusercontent.com/ntvampire/Win11Lite/main"
$tempDir = Join-Path -Path $env:TEMP -ChildPath "Win11Lite"

if (Test-Path $tempDir) {
    Get-ChildItem -Path $tempDir -Recurse | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
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
    $url = "$repoBase/$file?t=" + [DateTime]::UtcNow.Ticks
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Win11Lite-Loader")
        $bytes = $wc.DownloadData($url)
        if ($file -match '\.(ps1|psm1)$') {
            if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
                $bom = [byte[]]@(0xEF, 0xBB, 0xBF)
                $bytes = $bom + $bytes
            }
        }
        [System.IO.File]::WriteAllBytes($targetFile, $bytes)
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
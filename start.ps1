Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$zipUrl = "https://github.com/ntvampire/Win11Lite/archive/refs/heads/main.zip"
$tempBase = Join-Path -Path $env:TEMP -ChildPath "Win11Lite"
$zipFile = Join-Path -Path $env:TEMP -ChildPath "Win11Lite.zip"

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " Win11Lite: Downloading optimization suite...           " -ForegroundColor Yellow
Write-Host "=========================================================" -ForegroundColor Cyan

try {
    if (Test-Path $tempBase) {
        Remove-Item -Path $tempBase -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $zipFile) {
        Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
    }

    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "Win11Lite-Loader")
    $wc.DownloadFile($zipUrl, $zipFile)

    Expand-Archive -Path $zipFile -DestinationPath $tempBase -Force
    Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue

    $mainScript = (Get-ChildItem -Path $tempBase -Filter "Optimize-Windows.ps1" -Recurse | Select-Object -First 1).FullName

    if ($mainScript -and (Test-Path $mainScript)) {
        $scriptFolder = Split-Path -Path $mainScript -Parent
        Get-ChildItem -Path $scriptFolder -Recurse | Unblock-File -ErrorAction SilentlyContinue
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$mainScript" @args
    } else {
        Write-Host "[-] Error: Optimize-Windows.ps1 not found in archive." -ForegroundColor Red
    }
}
catch {
    Write-Host "[-] Failed to download or unpack Win11Lite: $($_.Exception.Message)" -ForegroundColor Red
}
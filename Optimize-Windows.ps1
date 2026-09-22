#Requires -Version 5.1
<#
.SYNOPSIS
    Главный скрипт комплексной оптимизации Windows 10/11 x64 после чистой установки.
.DESCRIPTION
    Специализирован для слабых ПК и ноутбуков с:
    - Механическим жестким диском (HDD 5400/7200 RPM)
    - 4 ГБ оперативной памяти
    - Интегрированной видеокартой (iGPU: Intel HD / AMD APU)
    
    Сохраняет Защитник Windows, Магазин приложений (Store) и стандартные утилиты (Калькулятор, Блокнот, Фото, Камера, Плеер).

.PARAMETER Unattended
    Автоматический режим: выполняет все этапы оптимизации без вывода интерактивного меню.
.PARAMETER SkipRestorePoint
    Пропустить создание контрольной точки восстановления системы.
.PARAMETER SkipStorage
    Пропустить оптимизацию дисковой подсистемы (HDD).
.PARAMETER SkipServices
    Пропустить оптимизацию служб и сжатия памяти.
.PARAMETER SkipVisuals
    Пропустить оптимизацию визуальных эффектов и DWM.
.PARAMETER SkipBloatware
    Пропустить очистку рекламных UWP-приложений.
.PARAMETER Restart
    Автоматически перезагрузить компьютер после успешного выполнения.

.EXAMPLE
    .\Optimize-Windows.ps1
    Запуск интерактивного консольного меню.

.EXAMPLE
    .\Optimize-Windows.ps1 -Unattended -Restart
    Полная автоматическая оптимизация с последующей перезагрузкой.
#>

[CmdletBinding()]
param(
    [switch]$Unattended,
    [switch]$SkipRestorePoint,
    [switch]$SkipStorage,
    [switch]$SkipServices,
    [switch]$SkipVisuals,
    [switch]$SkipBloatware,
    [switch]$Restart
)

# Разрешаем запуск неподписанных скриптов в рамках текущей сессии
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force -ErrorAction SilentlyContinue

$scriptDir = $PSScriptRoot

# Поддержка удаленного запуска через 'irm ... | iex' без предварительного скачивания
if ([string]::IsNullOrEmpty($scriptDir) -or (-not (Test-Path (Join-Path -Path $scriptDir -ChildPath 'modules\Common.psm1')))) {
    $tempDir = Join-Path -Path $env:TEMP -ChildPath "Win11Lite"
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    $repoBase = "https://raw.githubusercontent.com/ntvampire/Win11Lite/main"
    $filesToFetch = @(
        "Optimize-Windows.ps1",
        "Run-As-Admin.cmd",
        "modules/Common.psm1",
        "modules/StorageAndHdd.psm1",
        "modules/MemoryAndServices.psm1",
        "modules/VisualAndGpu.psm1",
        "modules/BloatwareCleanup.psm1"
    )

    Write-Host "[*] Удаленный запуск: загрузка модулей Win11Lite во временный каталог..." -ForegroundColor Cyan
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    foreach ($f in $filesToFetch) {
        $dest = Join-Path -Path $tempDir -ChildPath ($f -replace '/', '\')
        $folder = Split-Path -Path $dest -Parent
        if (-not (Test-Path $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
        }
        $url = "$repoBase/$f"
        try {
            Invoke-RestMethod -Uri $url -OutFile $dest -ErrorAction Stop
        }
        catch {
            Write-Host "[-] Ошибка загрузки $url : $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    $localEntry = Join-Path -Path $tempDir -ChildPath "Optimize-Windows.ps1"
    if (Test-Path $localEntry) {
        & $localEntry @PSBoundParameters
    } else {
        Write-Host "[-] Не удалось инициализировать запуск." -ForegroundColor Red
    }
    return
}

$modulesDir = Join-Path -Path $scriptDir -ChildPath 'modules'

# Импорт модулей
Import-Module (Join-Path -Path $modulesDir -ChildPath 'Common.psm1') -Force
Import-Module (Join-Path -Path $modulesDir -ChildPath 'StorageAndHdd.psm1') -Force
Import-Module (Join-Path -Path $modulesDir -ChildPath 'MemoryAndServices.psm1') -Force
Import-Module (Join-Path -Path $modulesDir -ChildPath 'VisualAndGpu.psm1') -Force
Import-Module (Join-Path -Path $modulesDir -ChildPath 'BloatwareCleanup.psm1') -Force

# Проверка прав администратора
if (-not (Test-IsAdmin)) {
    Write-OptLog "Скрипт требует прав Администратора!" 'ERROR'
    Write-OptLog "Пожалуйста, запустите PowerShell от имени Администратора (Run as Administrator)." 'WARN'
    
    # Попытка перезапуска от имени Администратора
    $relaunch = Read-Host "Попробовать перезапустить скрипт с правами Администратора? (Y/N)"
    if ($relaunch -eq 'Y' -or $relaunch -eq 'y') {
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    }
    Exit 1
}

# Получение сведений о системе
$sysInfo = Get-WindowsSystemInfo
Clear-Host
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " Win11Lite: Оптимизация Windows 10/11 x64 (HDD + 4GB RAM + iGPU) " -ForegroundColor Yellow
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "ОС: $($sysInfo.OSCaption) (Build: $($sysInfo.BuildNumber))" -ForegroundColor White
Write-Host "Редакция: $(if ($sysInfo.IsLTSC) { 'LTSC / LTSB' } else { 'Consumer / Standard' }) | Архитектура: $($sysInfo.Architecture)" -ForegroundColor White
Write-Host "Объем памяти (ОЗУ): $($sysInfo.RAMTotalGB) ГБ" -ForegroundColor White
Write-Host "Безопасность: Защитник Windows и Microsoft Store сохраняются!" -ForegroundColor Green
Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray

function Run-FullOptimization {
    if (-not $SkipRestorePoint) {
        New-SystemRestorePointSafe -Description "Win11Lite Clean Install Optimization"
    }

    if (-not $SkipStorage) {
        Invoke-AllStorageOptimizations
    }

    if (-not $SkipServices) {
        Invoke-AllMemoryAndServiceOptimizations
    }

    if (-not $SkipVisuals) {
        Invoke-AllVisualAndGpuOptimizations
    }

    if (-not $SkipBloatware) {
        Invoke-AllBloatwareCleanup
    }

    Write-OptLog "Все выбранные оптимизации успешно применены!" 'SUCCESS'
    
    if ($Restart) {
        Write-OptLog "Компьютер будет перезагружен через 10 секунд..." 'WARN'
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    }
    else {
        Write-Host "`nРекомендуется перезагрузить компьютер для применения всех изменений реестра и служб." -ForegroundColor Yellow
    }
}

# Если запуск в Unattended режиме
if ($Unattended) {
    Write-OptLog "Запуск в автоматическом режиме (Unattended)..." 'INFO'
    Run-FullOptimization
    Exit 0
}

# Интерактивное меню
do {
    Write-Host "`nВыберите действие:" -ForegroundColor Cyan
    Write-Host " [1] Полная комплексная оптимизация (Все модули: HDD, RAM, Графика, Bloatware)" -ForegroundColor Green
    Write-Host " [2] Оптимизация дисковой подсистемы (HDD, NTFS, Pagefile, WSearch, SysMain)" -ForegroundColor White
    Write-Host " [3] Оптимизация оперативной памяти и служб (4GB RAM, сжатие, телеметрия)" -ForegroundColor White
    Write-Host " [4] Оптимизация графики и интерфейса (iGPU, без прозрачности, с ClearType)" -ForegroundColor White
    Write-Host " [5] Очистить рекламные приложения (с сохранением Store, плеера, блокнота и др.)" -ForegroundColor White
    Write-Host " [6] Создать точку восстановления системы вручную" -ForegroundColor Gray
    Write-Host " [0] Выход" -ForegroundColor Red

    $choice = Read-Host "`nВведите номер пункта [0-6]"
    switch ($choice) {
        '1' {
            Run-FullOptimization
            break
        }
        '2' {
            if (-not $SkipRestorePoint) { New-SystemRestorePointSafe -Description "Win11Lite Before Storage Tweaks" }
            Invoke-AllStorageOptimizations
            break
        }
        '3' {
            if (-not $SkipRestorePoint) { New-SystemRestorePointSafe -Description "Win11Lite Before Memory Tweaks" }
            Invoke-AllMemoryAndServiceOptimizations
            break
        }
        '4' {
            Invoke-AllVisualAndGpuOptimizations
            break
        }
        '5' {
            Invoke-AllBloatwareCleanup
            break
        }
        '6' {
            New-SystemRestorePointSafe -Description "Win11Lite Manual Checkpoint"
        }
        '0' {
            Write-OptLog "Выход из программы." 'INFO'
            Exit 0
        }
        Default {
            Write-Host "Неверный выбор. Пожалуйста, введите цифру от 0 до 6." -ForegroundColor Yellow
        }
    }
} while ($choice -ne '0')

$rebootPrompt = Read-Host "`nПерезагрузить компьютер сейчас? (Y/N)"
if ($rebootPrompt -eq 'Y' -or $rebootPrompt -eq 'y') {
    Restart-Computer -Force
}

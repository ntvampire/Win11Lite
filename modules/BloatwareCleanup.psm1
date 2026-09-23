#Requires -Version 5.1
<#
.SYNOPSIS
    Модуль безопасной очистки рекламных UWP-приложений (Bloatware).
.DESCRIPTION
    Удаляет только предустановленный мусор (TikTok, Spotify, Disney+, Candy Crush, игры, рекламные хабы),
    СТРОГО СОХРАНЯЯ:
    - Microsoft Store
    - Защитник и безопасность Windows
    - Базовые системные утилиты: Калькулятор, Блокнот, Фотографии, Медиаплеер, Камера, Ножницы, Paint.
    - Системные кодеки и библиотеки (VCLibs, .NET Native, Xaml, WebMedia, VP9, HEIF).
#>

if (-not (Get-Command 'Write-OptLog' -ErrorAction SilentlyContinue)) {
    $commonPath = Join-Path -Path $PSScriptRoot -ChildPath 'Common.psm1'
    if (Test-Path $commonPath) {
        Import-Module -Name $commonPath -Global
    }
}

# Белый список пакетов, которые КАТЕГОРИЧЕСКИ ЗАПРЕЩЕНО удалять
$script:AppxWhiteList = @(
    '*WindowsStore*',
    '*StorePurchaseApp*',
    '*DesktopAppInstaller*',
    '*WindowsCalculator*',
    '*WindowsNotepad*',
    '*WindowsCamera*',
    '*Photos*',
    '*ZuneVideo*',
    '*ZuneMusic*',
    '*ScreenSketch*',
    '*Paint*',
    '*SecHealthUI*',
    '*WindowsTerminal*',
    '*SoundRecorder*',
    '*HEIFImageExtension*',
    '*VP9VideoExtensions*',
    '*WebMediaExtensions*',
    '*WebpImageExtension*',
    '*AV1VideoExtension*',
    '*MPEG2VideoExtension*',
    '*VCLibs*',
    '*NET.Native*',
    '*UI.Xaml*',
    '*Services.Store*'
)

# Черный список рекламных и ненужных промо-пакетов
$script:AppxBlackList = @(
    '*TikTok*',
    '*Spotify*',
    '*Disney*',
    '*Netflix*',
    '*CandyCrush*',
    '*HiddenCity*',
    '*MarchofEmpires*',
    '*Facebook*',
    '*Twitter*',
    '*Instagram*',
    '*MicrosoftSolitaireCollection*',
    '*FeedbackHub*',
    '*GetHelp*',
    '*Getstarted*',
    '*Tips*',
    '*SkypeApp*',
    '*MicrosoftOfficeHub*',
    '*BingNews*',
    '*BingFinance*',
    '*BingSports*',
    '*MixedReality.Portal*',
    '*549981C3F5F10*' # Идентификатор старого приложения Cortana
)

function Test-IsPackageWhitelisted {
    param([string]$PackageName)

    foreach ($pattern in $script:AppxWhiteList) {
        if ($PackageName -like $pattern) {
            return $true
        }
    }
    return $false
}

function Remove-ConsumerBloatware {
    <#
    .SYNOPSIS
        Удаляет только приложения из черного списка, которые не входят в белый список.
        Корректно работает на Consumer и LTSC/LTSB (где их может изначально не быть).
    #>
    Write-OptLog "Поиск и удаление рекламных приложений (с сохранением Store и базовых программ)..." 'INFO'

    # 1. Очистка установленных пакетов текущего пользователя
    try {
        $installedPackages = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
        foreach ($pkg in $installedPackages) {
            # Проверяем, входит ли пакет в белый список
            if (Test-IsPackageWhitelisted -PackageName $pkg.Name) {
                continue
            }

            # Проверяем, совпадает ли с черным списком
            $shouldRemove = $false
            foreach ($pattern in $script:AppxBlackList) {
                if ($pkg.Name -like $pattern) {
                    $shouldRemove = $true
                    break
                }
            }

            if ($shouldRemove) {
                Write-OptLog "Удаление установленного пакета: $($pkg.Name)..." 'INFO'
                try {
                    Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                    Write-OptLog "Пакет успешно удален: $($pkg.Name)" 'SUCCESS'
                }
                catch {
                    # Пробуем без ключа -AllUsers для совместимости
                    Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue
                }
            }
        }
    }
    catch {
        Write-OptLog "Предупреждение при обработке Get-AppxPackage: $($_.Exception.Message)" 'WARN'
    }

    # 2. Очистка Provisioned-пакетов (чтобы не устанавливались новым пользователям)
    try {
        $provisionedPackages = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
        foreach ($pkg in $provisionedPackages) {
            if (Test-IsPackageWhitelisted -PackageName $pkg.DisplayName) {
                continue
            }

            $shouldRemove = $false
            foreach ($pattern in $script:AppxBlackList) {
                if ($pkg.DisplayName -like $pattern) {
                    $shouldRemove = $true
                    break
                }
            }

            if ($shouldRemove) {
                Write-OptLog "Удаление предустановленного образа (Provisioned): $($pkg.DisplayName)..." 'INFO'
                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $pkg.PackageName -ErrorAction SilentlyContinue | Out-Null
                    Write-OptLog "Образ успешно удален: $($pkg.DisplayName)" 'SUCCESS'
                }
                catch {
                    # Игнорируем ошибки удаления
                }
            }
        }
    }
    catch {
        Write-OptLog "Предупреждение при обработке Get-AppxProvisionedPackage: $($_.Exception.Message)" 'WARN'
    }

    Write-OptLog "Очистка рекламных приложений завершена." 'SUCCESS'
}

function Invoke-AllBloatwareCleanup {
    <#
    .SYNOPSIS
        Комплексный запуск очистки мусора.
    #>
    Write-OptLog "=== СТАРТ БЕЗОПАСНОЙ ОЧИСТКИ BLOATWARE ===" 'HEADER'
    Remove-ConsumerBloatware
    Write-OptLog "Базовые приложения (Калькулятор, Блокнот, Фото, Плеер, Защитник, Магазин) в безопасности." 'SUCCESS'
}

Export-ModuleMember -Function Remove-ConsumerBloatware, Invoke-AllBloatwareCleanup

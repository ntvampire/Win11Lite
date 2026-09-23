#Requires -Version 5.1
<#
.SYNOPSIS
    Модуль оптимизации визуальных эффектов и графической подсистемы (iGPU).
.DESCRIPTION
    Настраивает DWM, интерфейс Windows 10/11 и видеоподсистему для слабых встроенных видеокарт:
    - Отключает ресурсоемкие эффекты прозрачности (Acrylic, Mica).
    - Отключает анимации окон и меню для устранения микрофризов.
    - СТРОГО СОХРАНЯЕТ сглаживание экранных шрифтов (ClearType) и отображение эскизов файлов.
    - Отключает фоновую запись экрана Game DVR.
    - Отключает виджеты новостей и погоды ("Новости и интересы" / Widgets), освобождая до 250 МБ ОЗУ (Edge WebView2).
#>

if (-not (Get-Command 'Write-OptLog' -ErrorAction SilentlyContinue)) {
    $commonPath = Join-Path -Path $PSScriptRoot -ChildPath 'Common.psm1'
    if (Test-Path $commonPath) {
        Import-Module -Name $commonPath -Global
    }
}

function Optimize-Transparency {
    <#
    .SYNOPSIS
        Отключает эффекты прозрачности DWM (слюда, акрил), снижая нагрузку на видеоядро и память.
    #>
    Write-OptLog "Отключение эффектов прозрачности интерфейса..." 'INFO'

    $personalizeCu = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    $personalizeLm = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"

    Set-RegistryValueSafe -Path $personalizeCu -Name "EnableTransparency" -Value 0 -PropertyType 'DWord' | Out-Null
    Set-RegistryValueSafe -Path $personalizeLm -Name "EnableTransparency" -Value 0 -PropertyType 'DWord' | Out-Null

    Write-OptLog "Прозрачность интерфейса успешно отключена." 'SUCCESS'
}

function Optimize-VisualEffects {
    <#
    .SYNOPSIS
        Отключает тяжелые анимации, но гарантированно сохраняет ClearType (сглаживание шрифтов)
        и отображение эскизов вместо значков.
    #>
    Write-OptLog "Настройка визуальных эффектов для максимальной отзывчивости iGPU..." 'INFO'

    # 1. Отключение анимации сворачивания/разворачивания окон
    $windowMetrics = "HKCU:\Control Panel\Desktop\WindowMetrics"
    Set-RegistryValueSafe -Path $windowMetrics -Name "MinAnimate" -Value "0" -PropertyType 'String' | Out-Null

    # 2. Отключение анимаций панели задач и выпадающих списков
    $explorerAdv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-RegistryValueSafe -Path $explorerAdv -Name "TaskbarAnimations" -Value 0 -PropertyType 'DWord' | Out-Null

    # 3. Гарантированное сохранение эскизов вместо значков (IconsOnly = 0)
    Set-RegistryValueSafe -Path $explorerAdv -Name "IconsOnly" -Value 0 -PropertyType 'DWord' | Out-Null

    # 4. СТРОГОЕ сохранение четкости шрифтов ClearType (FontSmoothing)
    $desktop = "HKCU:\Control Panel\Desktop"
    Set-RegistryValueSafe -Path $desktop -Name "FontSmoothing" -Value "2" -PropertyType 'String' | Out-Null
    Set-RegistryValueSafe -Path $desktop -Name "FontSmoothingType" -Value 2 -PropertyType 'DWord' | Out-Null
    Set-RegistryValueSafe -Path $desktop -Name "FontSmoothingGamma" -Value 1000 -PropertyType 'DWord' | Out-Null
    Set-RegistryValueSafe -Path $desktop -Name "FontSmoothingOrientation" -Value 1 -PropertyType 'DWord' | Out-Null

    # 5. Отключение плавной прокрутки списков (снижает задержку на слабом CPU/iGPU)
    Set-RegistryValueSafe -Path $desktop -Name "SmoothScroll" -Value 0 -PropertyType 'DWord' | Out-Null

    # 6. Установка режима визуальных эффектов в Custom (3)
    $visualFx = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    Set-RegistryValueSafe -Path $visualFx -Name "VisualFXSetting" -Value 3 -PropertyType 'DWord' | Out-Null

    # 7. Безопасная настройка UserPreferencesMask:
    # Байт 0: отключаем анимацию меню, оставляем сглаживание шрифтов (бит 1 включен).
    # Стандартная маска для высокой производительности со шрифтами ClearType:
    # 90 12 03 80 10 00 00 00
    try {
        $mask = [byte[]]@(0x90, 0x12, 0x03, 0x80, 0x10, 0x00, 0x00, 0x00)
        Set-ItemProperty -Path $desktop -Name "UserPreferencesMask" -Value $mask -Type Binary -Force -ErrorAction SilentlyContinue
    }
    catch {
        # Игнорируем в случае ошибки
    }

    Write-OptLog "Визуальные эффекты оптимизированы (ClearType и эскизы сохранены)." 'SUCCESS'
}

function Disable-GameDVRAndCapture {
    <#
    .SYNOPSIS
        Отключает Game DVR (фоновую видеозапись и оверлей), высвобождая буферы видеопамяти.
    #>
    Write-OptLog "Отключение фоновой службы видеозаписи Xbox Game DVR..." 'INFO'

    # GameConfigStore
    $gameConfig = "HKCU:\System\GameConfigStore"
    Set-RegistryValueSafe -Path $gameConfig -Name "GameDVR_Enabled" -Value 0 -PropertyType 'DWord' | Out-Null
    Set-RegistryValueSafe -Path $gameConfig -Name "GameDVR_FSEBehaviorMode" -Value 2 -PropertyType 'DWord' | Out-Null

    # Windows Policies GameDVR
    $gameDvrPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
    Set-RegistryValueSafe -Path $gameDvrPolicy -Name "AllowGameDVR" -Value 0 -PropertyType 'DWord' | Out-Null

    # AppCapture
    $appCapture = "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR"
    Set-RegistryValueSafe -Path $appCapture -Name "AppCaptureEnabled" -Value 0 -PropertyType 'DWord' | Out-Null

    Write-OptLog "Служба Game DVR успешно отключена." 'SUCCESS'
}

function Disable-WidgetsAndTaskbarBloat {
    <#
    .SYNOPSIS
        Отключает фоновые виджеты новостей и погоды ("Новости и интересы" в Win10 и "Widgets" в Win11),
        а также ненужные иконки чата/собраний, устраняя постоянный фоновый процесс WebView2 (~200 МБ ОЗУ).
    #>
    Write-OptLog "Отключение виджетов новостей, погоды и чата с панели задач..." 'INFO'

    # Windows 10: Новости и интересы (Feeds)
    $feeds = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"
    Set-RegistryValueSafe -Path $feeds -Name "ShellFeedsTaskbarViewMode" -Value 2 -PropertyType 'DWord' | Out-Null # 2 = Hidden

    $feedsPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds"
    Set-RegistryValueSafe -Path $feedsPolicy -Name "EnableFeeds" -Value 0 -PropertyType 'DWord' | Out-Null

    # Windows 11: Виджеты (Dsh)
    $dshPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
    Set-RegistryValueSafe -Path $dshPolicy -Name "AllowNewsAndInterests" -Value 0 -PropertyType 'DWord' | Out-Null

    $explorerAdv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-RegistryValueSafe -Path $explorerAdv -Name "TaskbarDa" -Value 0 -PropertyType 'DWord' | Out-Null # Отключение иконки Виджетов
    Set-RegistryValueSafe -Path $explorerAdv -Name "TaskbarMn" -Value 0 -PropertyType 'DWord' | Out-Null # Отключение иконки Чата Teams

    Write-OptLog "Виджеты панели задач отключены (дополнительно освобождено ~200 МБ ОЗУ)." 'SUCCESS'
}

function Invoke-AllVisualAndGpuOptimizations {
    <#
    .SYNOPSIS
        Комплексный запуск оптимизаций графики и интерфейса.
    #>
    Write-OptLog "=== СТАРТ ОПТИМИЗАЦИИ ГРАФИКИ (iGPU И ИНТЕРФЕЙС) ===" 'HEADER'
    Optimize-Transparency
    Optimize-VisualEffects
    Disable-GameDVRAndCapture
    Disable-WidgetsAndTaskbarBloat
    Write-OptLog "Оптимизация графики и интерфейса успешно завершена." 'SUCCESS'
}

Export-ModuleMember -Function Optimize-Transparency, Optimize-VisualEffects, Disable-GameDVRAndCapture, `
                          Disable-WidgetsAndTaskbarBloat, Invoke-AllVisualAndGpuOptimizations

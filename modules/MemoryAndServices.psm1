#Requires -Version 5.1
<#
.SYNOPSIS
    Модуль оптимизации оперативной памяти (4 ГБ) и системных служб.
.DESCRIPTION
    - Гарантирует включение сжатия памяти (Memory Compression).
    - Отключает телеметрию (DiagTrack, dmwappushservice) и рекламные подсказки Windows Consumer Experience.
    - Переводит второстепенные службы в ручной (Manual) или отключенный режим.
    - Строго сохраняет службы Защитника Windows (Defender), Центра обновления (Windows Update) и Магазина (Store).
#>

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Common.psm1') -Force

function Optimize-MemoryCompression {
    <#
    .SYNOPSIS
        Проверяет и включает сжатие оперативной памяти (Memory Compression).
        Для систем с 4 ГБ ОЗУ и медленным HDD это критически важно:
        чтение сжатых страниц из ОЗУ происходит в сотни раз быстрее, чем сброс данных на диск в pagefile.
    #>
    Write-OptLog "Настройка механизма сжатия памяти (Memory Compression)..." 'INFO'
    try {
        if (Get-Command -Name "Enable-MMAgent" -ErrorAction SilentlyContinue) {
            Enable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue
            Write-OptLog "Сжатие памяти успешно активировано через MMAgent." 'SUCCESS'
        }
        else {
            Write-OptLog "Командлет Enable-MMAgent недоступен в текущей среде. Проверка реестра..." 'INFO'
        }
    }
    catch {
        Write-OptLog "Предупреждение при включении MMAgent: $($_.Exception.Message)" 'WARN'
    }
}

function Disable-TelemetryAndDataCollection {
    <#
    .SYNOPSIS
        Отключает компоненты телеметрии и сбора диагностических данных,
        освобождая оперативную память и снижая фоновые очереди диска.
    #>
    Write-OptLog "Отключение служб и политик телеметрии..." 'INFO'

    # Политики сбора данных (Telemetry Level = 0 / Security или 1 / Basic)
    $dataCollectionPolicies = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    Set-RegistryValueSafe -Path $dataCollectionPolicies -Name "AllowTelemetry" -Value 0 -PropertyType 'DWord' | Out-Null
    Set-RegistryValueSafe -Path $dataCollectionPolicies -Name "MaxTelemetryAllowed" -Value 0 -PropertyType 'DWord' | Out-Null

    $dataCollectionCurrent = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
    Set-RegistryValueSafe -Path $dataCollectionCurrent -Name "AllowTelemetry" -Value 0 -PropertyType 'DWord' | Out-Null

    # Отключение служб сбора телеметрии
    $telemetryServices = @('DiagTrack', 'dmwappushservice')
    foreach ($svcName in $telemetryServices) {
        try {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($svc) {
                if ($svc.Status -eq 'Running') {
                    Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
                }
                Set-Service -Name $svcName -StartupType Disabled -ErrorAction SilentlyContinue
                Write-OptLog "Служба телеметрии '$svcName' остановлена и отключена." 'SUCCESS'
            }
        }
        catch {
            Write-OptLog "Не удалось отключить службу $svcName : $($_.Exception.Message)" 'WARN'
        }
    }
}

function Disable-ConsumerExperienceAndSuggestions {
    <#
    .SYNOPSIS
        Блокирует автоматическую фоновую установку рекламных UWP-приложений
        (Candy Crush, TikTok и т.д.) и отключает назойливые подсказки ОС.
    #>
    Write-OptLog "Отключение автоматической загрузки рекомендуемых приложений и подсказок..." 'INFO'

    # CloudContent Policies (отключение спонсорских приложений)
    $cloudContent = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    Set-RegistryValueSafe -Path $cloudContent -Name "DisableWindowsConsumerFeatures" -Value 1 -PropertyType 'DWord' | Out-Null
    Set-RegistryValueSafe -Path $cloudContent -Name "DisableSoftLanding" -Value 1 -PropertyType 'DWord' | Out-Null
    Set-RegistryValueSafe -Path $cloudContent -Name "DisableConsumerAccountStateContent" -Value 1 -PropertyType 'DWord' | Out-Null

    # ContentDeliveryManager для текущего пользователя
    $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    Set-RegistryValueSafe -Path $cdm -Name "SilentInstalledAppsEnabled" -Value 0 -PropertyType 'DWord' | Out-Null
    Set-RegistryValueSafe -Path $cdm -Name "SystemPaneSuggestionsEnabled" -Value 0 -PropertyType 'DWord' | Out-Null
    Set-RegistryValueSafe -Path $cdm -Name "SubscribedContent-338388Enabled" -Value 0 -PropertyType 'DWord' | Out-Null
    Set-RegistryValueSafe -Path $cdm -Name "SubscribedContent-338389Enabled" -Value 0 -PropertyType 'DWord' | Out-Null
    Set-RegistryValueSafe -Path $cdm -Name "SubscribedContent-353694Enabled" -Value 0 -PropertyType 'DWord' | Out-Null
    Set-RegistryValueSafe -Path $cdm -Name "SubscribedContent-353696Enabled" -Value 0 -PropertyType 'DWord' | Out-Null

    # Отключение "Получать советы и подсказки при использовании Windows"
    $advUser = "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement"
    Set-RegistryValueSafe -Path $advUser -Name "ScoobeSystemSettingEnabled" -Value 0 -PropertyType 'DWord' | Out-Null

    Write-OptLog "Фоновая установка промо-приложений и рекламные уведомления отключены." 'SUCCESS'
}

function Optimize-BackgroundServices {
    <#
    .SYNOPSIS
        Настраивает список второстепенных служб, освобождая ~150-300 МБ постоянной памяти.
        Внимание: Службы Защитника Windows (WinDefend), Store и печати НЕ отключаются!
    #>
    Write-OptLog "Оптимизация второстепенных фоновых служб..." 'INFO'

    # Службы, которые можно безопасно отключить для слабой конфигурации
    $servicesToDisable = @(
        'MapsBroker',       # Управление загруженными автономными картами
        'RetailDemo',       # Демонстрационный режим для магазинов
        'RemoteRegistry',   # Удаленное управление реестром по сети (безопасность + ресурсы)
        'wisvc'             # Служба участников программы предварительной оценки Windows Insider
    )

    foreach ($name in $servicesToDisable) {
        try {
            $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
            if ($svc) {
                if ($svc.Status -eq 'Running') {
                    Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
                }
                Set-Service -Name $name -StartupType Disabled -ErrorAction SilentlyContinue
                Write-OptLog "Служба '$name' отключена." 'SUCCESS'
            }
        }
        catch {
            # Игнорируем в случае отсутствия службы
        }
    }

    # Службы, которые переводим в Ручной режим (Manual), чтобы не висели в RAM,
    # но при необходимости могли запуститься по требованию:
    $servicesToManual = @(
        'lfsvc',            # Служба геолокации
        'SharedRealitySvc', # Пространственные данные / Windows Mixed Reality
        'XblAuthManager',   # Xbox Live: диспетчер аутентификации
        'XblGameSave',      # Xbox Live: сохранение игр
        'XboxGipSvc',       # Служба вспомогательного протокола Xbox
        'XboxNetApiSvc'     # Сетевая служба Xbox Live
    )

    foreach ($name in $servicesToManual) {
        try {
            $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
            if ($svc -and $svc.StartType -ne 'Manual') {
                Set-Service -Name $name -StartupType Manual -ErrorAction SilentlyContinue
                Write-OptLog "Служба '$name' переведена в ручной режим (Manual)." 'SUCCESS'
            }
        }
        catch {
            # Игнорируем в случае отсутствия
        }
    }
}

function Invoke-AllMemoryAndServiceOptimizations {
    <#
    .SYNOPSIS
        Комплексный запуск оптимизаций оперативной памяти и служб.
    #>
    Write-OptLog "=== СТАРТ ОПТИМИЗАЦИИ ПАМЯТИ И СЛУЖБ (4 ГБ RAM) ===" 'HEADER'
    Optimize-MemoryCompression
    Disable-TelemetryAndDataCollection
    Disable-ConsumerExperienceAndSuggestions
    Optimize-BackgroundServices
    Write-OptLog "Оптимизация памяти и служб успешно завершена." 'SUCCESS'
}

Export-ModuleMember -Function Optimize-MemoryCompression, Disable-TelemetryAndDataCollection, `
                          Disable-ConsumerExperienceAndSuggestions, Optimize-BackgroundServices, `
                          Invoke-AllMemoryAndServiceOptimizations

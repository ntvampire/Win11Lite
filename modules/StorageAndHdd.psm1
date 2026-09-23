#Requires -Version 5.1
<#
.SYNOPSIS
    Модуль оптимизации дисковой подсистемы для медленных жестких дисков (HDD).
.DESCRIPTION
    Устраняет узкие места механических накопителей (5400/7200 RPM):
    - Отключает обновление временных меток последнего доступа NTFS (DisableLastAccess).
    - Ограничивает раздачу P2P обновлений Windows Update (Delivery Optimization).
    - Настраивает фиксированный размер файла подкачки (pagefile.sys) во избежание фрагментации.
    - Оптимизирует параметры Prefetcher и службу SysMain (Superfetch).
    - Настраивает службу поиска Windows Search на щадящий отложенный режим без индексации сети.
    - Отключает фоновые задачи телеметрии диска (CompatTelRunner, CEIP), вызывающие 100% загрузку HDD.
#>

if (-not (Get-Command 'Write-OptLog' -ErrorAction SilentlyContinue)) {
    $commonPath = Join-Path -Path $PSScriptRoot -ChildPath 'Common.psm1'
    if (Test-Path $commonPath) {
        Import-Module -Name $commonPath -Global
    }
}

function Optimize-NtfsSettings {
    <#
    .SYNOPSIS
        Отключает обновление времени последнего доступа NTFS для уменьшения случайных записей на HDD.
    #>
    Write-OptLog "Настройка параметров файловой системы NTFS..." 'INFO'
    try {
        # 1 = User Managed, Last Access Updates Disabled
        $res = & fsutil behavior set disablelastaccess 1 2>&1
        Write-OptLog "Отключение времени последнего доступа NTFS (DisableLastAccess = 1): $res" 'SUCCESS'
    }
    catch {
        Write-OptLog "Не удалось настроить fsutil disablelastaccess: $($_.Exception.Message)" 'WARN'
    }
}

function Optimize-Pagefile {
    <#
    .SYNOPSIS
        Устанавливает стабильный размер файла подкачки для предотвращения постоянного ресайза и фрагментации на HDD.
    #>
    param(
        [int]$InitialSizeMB = 4096,
        [int]$MaximumSizeMB = 6144
    )

    Write-OptLog "Настройка файла подкачки (Pagefile.sys) под 4 ГБ ОЗУ..." 'INFO'
    try {
        $sys = Get-CimInstance -ClassName Win32_ComputerSystem
        if ($sys.AutomaticManagedPagefile) {
            Write-OptLog "Отключение автоматического управления файлом подкачки..." 'INFO'
            $sys.AutomaticManagedPagefile = $false
            Set-CimInstance -CimInstance $sys -ErrorAction Stop
        }

        # Получаем текущий диск с Windows (обычно C:)
        $systemDrive = $env:SystemDrive # 'C:'
        $pageFileSetting = Get-CimInstance -ClassName Win32_PageFileSetting -Filter "Name LIKE '$systemDrive%'" -ErrorAction SilentlyContinue

        if ($pageFileSetting) {
            $pageFileSetting.InitialSize = $InitialSizeMB
            $pageFileSetting.MaximumSize = $MaximumSizeMB
            Set-CimInstance -CimInstance $pageFileSetting -ErrorAction Stop
            Write-OptLog "Файл подкачки на $systemDrive успешно обновлен: $InitialSizeMB МБ - $MaximumSizeMB МБ" 'SUCCESS'
        }
        else {
            # Если запись отсутствует, создаем через Win32_PageFileSetting
            New-CimInstance -ClassName Win32_PageFileSetting -Property @{
                Name        = "$systemDrive\pagefile.sys"
                InitialSize = $InitialSizeMB
                MaximumSize = $MaximumSizeMB
            } -ErrorAction Stop | Out-Null
            Write-OptLog "Создана статическая конфигурация файла подкачки: $InitialSizeMB МБ - $MaximumSizeMB МБ" 'SUCCESS'
        }
    }
    catch {
        Write-OptLog "Не удалось изменить размер файла подкачки через WMI: $($_.Exception.Message)" 'WARN'
        Write-OptLog "Пробуем задать параметры подкачки через реестр..." 'INFO'
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
        $val = [string[]]@("$env:SystemDrive\pagefile.sys $InitialSizeMB $MaximumSizeMB")
        Set-ItemProperty -Path $regPath -Name "PagingFiles" -Value $val -Type MultiString -Force -ErrorAction SilentlyContinue
    }
}

function Optimize-DeliveryOptimization {
    <#
    .SYNOPSIS
        Отключает передачу обновлений по P2P в интернет, которая непрерывно читает HDD в фоне.
    #>
    Write-OptLog "Настройка службы оптимизации доставки (Delivery Optimization)..." 'INFO'
    $doRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
    # DODownloadMode:
    # 0 = HTTP only, no peer-to-peer (Отключает P2P полностью, скачивание напрямую с серверов MS)
    # 1 = P2P только в локальной сети (LAN)
    Set-RegistryValueSafe -Path $doRegPath -Name "DODownloadMode" -Value 0 -PropertyType 'DWord' | Out-Null

    # Отключаем фоновую загрузку в кэш
    $doConfigPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config"
    Set-RegistryValueSafe -Path $doConfigPath -Name "DODownloadMode" -Value 0 -PropertyType 'DWord' | Out-Null

    Write-OptLog "P2P раздача обновлений в интернет отключена (нагрузка на диск снята)." 'SUCCESS'
}

function Optimize-SysMainAndPrefetch {
    <#
    .SYNOPSIS
        Оптимизирует Prefetcher и SuperFetch (SysMain).
        На HDD с 4 ГБ ОЗУ дефолтный SysMain пытается кэшировать тяжелые приложения,
        вызывая 100% нагрузку диска на протяжении 15-30 минут после старта системы.
    #>
    Write-OptLog "Настройка параметров Prefetcher и SysMain..." 'INFO'
    $prefetchReg = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"

    # EnablePrefetcher:
    # 0 = Disabled, 1 = Application launch, 2 = Boot files only, 3 = Boot + App launch
    # Для 4 ГБ RAM + медленный HDD значение 2 (Boot only) предотвращает постоянный фоновый I/O в процессе работы,
    # сохраняя быструю загрузку ядра и драйверов Windows.
    Set-RegistryValueSafe -Path $prefetchReg -Name "EnablePrefetcher" -Value 2 -PropertyType 'DWord' | Out-Null
    Set-RegistryValueSafe -Path $prefetchReg -Name "EnableSuperfetch" -Value 2 -PropertyType 'DWord' | Out-Null

    # Переводим службу SysMain в режим отложенного запуска (Delayed Start),
    # чтобы при входе на рабочий стол диск не вставал в очередь 100%.
    try {
        $sysMain = Get-Service -Name "SysMain" -ErrorAction SilentlyContinue
        if ($sysMain) {
            Set-Service -Name "SysMain" -StartupType Automatic -ErrorAction SilentlyContinue
            # Настройка DelayedAutoStart = 1
            $svcReg = "HKLM:\SYSTEM\CurrentControlSet\Services\SysMain"
            Set-RegistryValueSafe -Path $svcReg -Name "DelayedAutoStart" -Value 1 -PropertyType 'DWord' | Out-Null
            Write-OptLog "Служба SysMain переведена в режим отложенного автозапуска (Delayed Start)." 'SUCCESS'
        }
    }
    catch {
        Write-OptLog "Не удалось скорректировать запуск SysMain: $($_.Exception.Message)" 'WARN'
    }
}

function Optimize-WindowsSearch {
    <#
    .SYNOPSIS
        Оптимизирует службу индексирования Windows Search:
        - Отключает веб-поиск Bing в меню Пуск.
        - Переводит службу в отложенный запуск.
        - Сохраняет быстрый локальный поиск программ и файлов, но отключает тяжелую фоновую индексацию содержимого.
    #>
    Write-OptLog "Оптимизация службы поиска (Windows Search)..." 'INFO'

    $searchPolicies = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
    # Отключаем поиск в интернете и Bing через панель поиска
    Set-RegistryValueSafe -Path $searchPolicies -Name "ConnectedSearchUseWeb" -Value 0 -PropertyType 'DWord' | Out-Null
    Set-RegistryValueSafe -Path $searchPolicies -Name "AllowIndexingEncryptedStoresOrItems" -Value 0 -PropertyType 'DWord' | Out-Null
    Set-RegistryValueSafe -Path $searchPolicies -Name "PreventIndexOnBattery" -Value 1 -PropertyType 'DWord' | Out-Null

    # Отключаем интеграцию поиска Bing для текущего пользователя
    $searchCu = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
    Set-RegistryValueSafe -Path $searchCu -Name "BingSearchEnabled" -Value 0 -PropertyType 'DWord' | Out-Null
    Set-RegistryValueSafe -Path $searchCu -Name "CortanaConsent" -Value 0 -PropertyType 'DWord' | Out-Null

    # Переводим WSearch в Delayed Auto Start, чтобы рабочий стол открывался плавно
    try {
        $wsearch = Get-Service -Name "WSearch" -ErrorAction SilentlyContinue
        if ($wsearch) {
            Set-Service -Name "WSearch" -StartupType Automatic -ErrorAction SilentlyContinue
            $svcReg = "HKLM:\SYSTEM\CurrentControlSet\Services\WSearch"
            Set-RegistryValueSafe -Path $svcReg -Name "DelayedAutoStart" -Value 1 -PropertyType 'DWord' | Out-Null
            Write-OptLog "Служба Windows Search оптимизирована (отложенный запуск, веб-поиск отключен)." 'SUCCESS'
        }
    }
    catch {
        Write-OptLog "Не удалось настроить службу WSearch: $($_.Exception.Message)" 'WARN'
    }
}

function Disable-DiskThrashingTasks {
    <#
    .SYNOPSIS
        Отключает запланированные задачи Microsoft, сканирующие файловую систему и диск в фоновом режиме.
    #>
    Write-OptLog "Отключение тяжелых фоновых задач сбора совместимости и телеметрии диска..." 'INFO'

    $tasksToDisable = @(
        # Сканирует все бинарные файлы на диске (CompatTelRunner.exe)
        @{ Path = '\Microsoft\Windows\Application Experience'; Name = 'Microsoft Compatibility Appraiser' },
        @{ Path = '\Microsoft\Windows\Application Experience'; Name = 'ProgramDataUpdater' },
        @{ Path = '\Microsoft\Windows\Application Experience'; Name = 'StartupAppTask' },
        # Сборщики информации об использовании устройств и дисков
        @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program'; Name = 'Consolidator' },
        @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program'; Name = 'UsbCeip' },
        @{ Path = '\Microsoft\Windows\DiskDiagnostic'; Name = 'Microsoft-Windows-DiskDiagnosticResolver' },
        @{ Path = '\Microsoft\Windows\DiskDiagnostic'; Name = 'Microsoft-Windows-DiskDiagnosticDataCollector' },
        @{ Path = '\Microsoft\Windows\Autochk'; Name = 'Proxy' },
        @{ Path = '\Microsoft\Windows\Feedback\Siuf'; Name = 'DmClient' },
        @{ Path = '\Microsoft\Windows\Feedback\Siuf'; Name = 'DmClientOnScenarioDownload' }
    )

    foreach ($task in $tasksToDisable) {
        try {
            $t = Get-ScheduledTask -TaskPath $task.Path -TaskName $task.Name -ErrorAction SilentlyContinue
            if ($t -and $t.State -ne 'Disabled') {
                Disable-ScheduledTask -TaskPath $task.Path -TaskName $task.Name -ErrorAction SilentlyContinue | Out-Null
                Write-OptLog "Отключена фоновая задача: $($task.Name)" 'SUCCESS'
            }
        }
        catch {
            # Игнорируем отсутствие задачи в старых сборках или LTSC
        }
    }
}

function Invoke-AllStorageOptimizations {
    <#
    .SYNOPSIS
        Запуск полного цикла оптимизации для HDD накопителя.
    #>
    Write-OptLog "=== СТАРТ ОПТИМИЗАЦИИ ДИСКА (HDD) ===" 'HEADER'
    Optimize-NtfsSettings
    Optimize-Pagefile
    Optimize-DeliveryOptimization
    Optimize-SysMainAndPrefetch
    Optimize-WindowsSearch
    Disable-DiskThrashingTasks
    Write-OptLog "Оптимизация дисковой подсистемы успешно завершена." 'SUCCESS'
}

Export-ModuleMember -Function Optimize-NtfsSettings, Optimize-Pagefile, Optimize-DeliveryOptimization, `
                          Optimize-SysMainAndPrefetch, Optimize-WindowsSearch, Disable-DiskThrashingTasks, `
                          Invoke-AllStorageOptimizations

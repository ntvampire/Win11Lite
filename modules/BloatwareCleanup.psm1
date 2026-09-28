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
    '*ZuneMusic*',          # Новый медиаплеер Windows / Groove Music
    '*ScreenSketch*',       # Ножницы (Snipping Tool)
    'Microsoft.Paint',      # Современный Paint Windows 11 (НЕ Paint 3D!)
    '*SecHealthUI*',        # Безопасность Windows
    '*WindowsTerminal*',
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

# Черный список рекламных и нежелательных пакетов
$script:AppxBlackList = @(
    # Реклама, соцсети и спонсорские игры
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
    '*549981C3F5F10*',            # Идентификатор старого приложения Cortana

    # Приложения по запросу пользователя:
    '*OneNote*',                   # OneNote
    '*Office.OneNote*',
    '*MSPaint*',                   # Paint 3D (Microsoft.MSPaint)
    '*Paint3D*',
    '*MicrosoftStickyNotes*',      # Заметки (Sticky Notes)
    '*Xbox*',                      # Xbox, Xbox Live, Game Bar и оверлеи
    '*GamingApp*',
    '*People*',                    # Люди (People)
    '*windowscommunicationsapps*', # Почта и Календарь
    '*WindowsAlarms*',             # Часы и будильники
    '*WindowsSoundRecorder*',      # Запись голоса
    '*SoundRecorder*',
    '*WindowsMaps*',               # Карты
    '*ZuneVideo*',                 # Кино и ТВ
    '*BingWeather*',               # Погода
    '*3DViewer*',                  # Средство 3D-просмотра
    '*Microsoft3DViewer*',
    '*Print3D*',
    '*Yandex*'                     # Яндекс Музыка и региональные промо-пакеты
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

function Remove-OneDrive {
    <#
    .SYNOPSIS
        Полное удаление Microsoft OneDrive:
        - Завершение процессов
        - Запуск штатного деинсталлятора
        - Удаление переменной среды пользователя 'OneDrive'
        - Удаление папки OneDrive из профиля пользователя
        - Очистка автозапуска, политик и проводника
    #>
    Write-OptLog "Удаление Microsoft OneDrive из системы..." 'INFO'

    # 1. Завершение запущенных процессов OneDrive
    try {
        Get-Process -Name "OneDrive", "OneDriveSetup" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    catch { }

    # 2. Поиск и запуск деинсталлятора
    $uninstallerPaths = @(
        "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
        "$env:SystemRoot\System32\OneDriveSetup.exe",
        "$env:LOCALAPPDATA\Microsoft\OneDrive\Update\OneDriveSetup.exe"
    )

    $extraSetup = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\OneDrive" -Filter "OneDriveSetup.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    if ($extraSetup) { $uninstallerPaths += $extraSetup }

    foreach ($exe in $uninstallerPaths) {
        if ($exe -and (Test-Path $exe)) {
            Write-OptLog "Запуск деинсталлятора: $exe /uninstall..." 'INFO'
            try {
                Start-Process -FilePath $exe -ArgumentList "/uninstall" -Wait -WindowStyle Hidden -ErrorAction Stop
                break
            }
            catch {
                Write-OptLog "Деинсталлятор завершился с предупреждением: $($_.Exception.Message)" 'WARN'
            }
        }
    }

    Start-Sleep -Seconds 2

    # 3. Удаление переменных среды пользователя
    Write-OptLog "Удаление переменной среды 'OneDrive'..." 'INFO'
    try {
        [Environment]::SetEnvironmentVariable("OneDrive", $null, [EnvironmentVariableTarget]::User)
        [Environment]::SetEnvironmentVariable("OneDrive", $null, [EnvironmentVariableTarget]::Process)
        [Environment]::SetEnvironmentVariable("OneDriveCommercial", $null, [EnvironmentVariableTarget]::User)
        [Environment]::SetEnvironmentVariable("OneDriveConsumer", $null, [EnvironmentVariableTarget]::User)

        Remove-ItemProperty -Path "HKCU:\Environment" -Name "OneDrive" -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKCU:\Environment" -Name "OneDriveCommercial" -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKCU:\Environment" -Name "OneDriveConsumer" -Force -ErrorAction SilentlyContinue
        Write-OptLog "Переменные среды OneDrive успешно удалены." 'SUCCESS'
    }
    catch {
        Write-OptLog "Предупреждение при удалении переменных среды: $($_.Exception.Message)" 'WARN'
    }

    # 4. Удаление папки OneDrive из профиля пользователя
    $oneDriveUserDir = Join-Path -Path $env:USERPROFILE -ChildPath "OneDrive"
    if (Test-Path $oneDriveUserDir) {
        Write-OptLog "Удаление папки OneDrive из профиля: $oneDriveUserDir..." 'INFO'
        try {
            & cmd.exe /c "attrib -r -s -h `"$oneDriveUserDir\*`" /s /d" 2>$null
            Remove-Item -Path $oneDriveUserDir -Recurse -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path $oneDriveUserDir)) {
                Write-OptLog "Папка OneDrive в профиле пользователя успешно удалена." 'SUCCESS'
            }
        }
        catch {
            Write-OptLog "Предупреждение при удалении папки $oneDriveUserDir : $($_.Exception.Message)" 'WARN'
        }
    }

    # 5. Очистка остаточных каталогов в LocalAppData / ProgramData
    $residualDirs = @(
        "$env:LOCALAPPDATA\Microsoft\OneDrive",
        "$env:ProgramData\Microsoft OneDrive"
    )
    foreach ($dir in $residualDirs) {
        if (Test-Path $dir) {
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # 6. Очистка автозапуска из реестра
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run" -Name "OneDrive" -Force -ErrorAction SilentlyContinue

    # 7. Отключение через групповые политики (предотвращает повторную фоновую установку)
    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
    Set-RegistryValueSafe -Path $policyPath -Name "DisableFileSyncNGSC" -Value 1 -PropertyType 'DWord' | Out-Null
    Set-RegistryValueSafe -Path $policyPath -Name "DisableFileSync" -Value 1 -PropertyType 'DWord' | Out-Null

    # 8. Скрытие значка OneDrive в панели навигации Проводника
    $clsidPaths = @(
        "HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}",
        "HKCR:\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"
    )
    foreach ($cp in $clsidPaths) {
        if (Test-Path $cp) {
            Set-RegistryValueSafe -Path $cp -Name "System.IsPinnedToNameSpaceTree" -Value 0 -PropertyType 'DWord' | Out-Null
        }
    }

    Write-OptLog "Удаление и очистка Microsoft OneDrive успешно завершены." 'SUCCESS'
}

function Invoke-AllBloatwareCleanup {
    <#
    .SYNOPSIS
        Комплексный запуск очистки мусора.
    #>
    Write-OptLog "=== СТАРТ БЕЗОПАСНОЙ ОЧИСТКИ BLOATWARE И ONEDRIVE ===" 'HEADER'
    Remove-ConsumerBloatware
    Remove-OneDrive
    Write-OptLog "Очистка завершена. Базовые приложения (Калькулятор, Блокнот, Фотографии, Камера, Музыка, Защитник, Магазин) сохранены." 'SUCCESS'
}

Export-ModuleMember -Function Remove-ConsumerBloatware, Remove-OneDrive, Invoke-AllBloatwareCleanup

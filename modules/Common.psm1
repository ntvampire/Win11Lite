#Requires -Version 5.1
<#
.SYNOPSIS
    Модуль общих вспомогательных функций для скрипта оптимизации Windows.
.DESCRIPTION
    Содержит функции логирования, проверки прав Администратора,
    определения версии и редакции ОС, создания точек восстановления и безопасного редактирования реестра.
#>

function Write-OptLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,

        [Parameter(Mandatory = $false, Position = 1)]
        [ValidateSet('INFO', 'SUCCESS', 'WARN', 'ERROR', 'HEADER')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'HH:mm:ss'
    switch ($Level) {
        'INFO' {
            Write-Host "[$timestamp] [i] $Message" -ForegroundColor Cyan
        }
        'SUCCESS' {
            Write-Host "[$timestamp] [+] $Message" -ForegroundColor Green
        }
        'WARN' {
            Write-Host "[$timestamp] [!] $Message" -ForegroundColor Yellow
        }
        'ERROR' {
            Write-Host "[$timestamp] [-] $Message" -ForegroundColor Red
        }
        'HEADER' {
            Write-Host "`n========================================================" -ForegroundColor Magenta
            Write-Host " $Message" -ForegroundColor White -BackgroundColor DarkMagenta
            Write-Host "========================================================" -ForegroundColor Magenta
        }
    }
}

function Test-IsAdmin {
    <#
    .SYNOPSIS
        Проверяет, запущен ли текущий процесс с правами локального администратора.
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WindowsSystemInfo {
    <#
    .SYNOPSIS
        Собирает сведения о версии Windows, редакции (LTSC/Consumer) и объеме RAM.
    #>
    try {
        $reg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue

        $caption = if ($os -and $os.Caption) { $os.Caption } elseif ($reg -and $reg.ProductName) { $reg.ProductName } else { "Windows 10/11" }
        $build = if ($os -and $os.BuildNumber) { [int]$os.BuildNumber } elseif ($reg -and $reg.CurrentBuildNumber) { [int]$reg.CurrentBuildNumber } else { 19045 }
        $editionId = if ($reg -and $reg.EditionID) { $reg.EditionID } else { '' }

        $isWin11 = $build -ge 22000
        $isLTSC = ($caption -match 'LTSC|LTSB|EnterpriseS') -or ($editionId -match 'EnterpriseS')

        $totalMem = if ($cs -and $cs.TotalPhysicalMemory) { $cs.TotalPhysicalMemory } else { 0 }
        $ramTotalGB = if ($totalMem -gt 0) { [math]::Round($totalMem / 1GB, 1) } else { 4.0 }

        $arch = if ($os -and $os.OSArchitecture) { $os.OSArchitecture } elseif ($env:PROCESSOR_ARCHITECTURE) { $env:PROCESSOR_ARCHITECTURE } else { "64-bit" }

        return [PSCustomObject]@{
            OSCaption     = $caption
            BuildNumber   = $build
            IsWindows11   = $isWin11
            IsLTSC        = $isLTSC
            RAMTotalGB    = $ramTotalGB
            Architecture  = $arch
            ComputerName  = $env:COMPUTERNAME
        }
    }
    catch {
        return [PSCustomObject]@{
            OSCaption     = "Windows"
            BuildNumber   = 0
            IsWindows11   = $false
            IsLTSC        = $false
            RAMTotalGB    = 4.0
            Architecture  = "64-bit"
            ComputerName  = $env:COMPUTERNAME
        }
    }
}

function New-SystemRestorePointSafe {
    <#
    .SYNOPSIS
        Безопасно создает точку восстановления системы перед началом оптимизации.
    #>
    param(
        [string]$Description = "Before Win11Lite HDD/RAM Optimization"
    )

    Write-OptLog "Проверка службы восстановления системы..." 'INFO'
    try {
        # Проверяем статус службы VSS и System Restore
        Set-Service -Name 'srservice' -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name 'srservice' -ErrorAction SilentlyContinue

        # Включаем защиту для системного диска C: если она была отключена
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue

        Write-OptLog "Создание контрольной точки восстановления: '$Description'..." 'INFO'
        # Разрешаем создание точек чаще, чем дефолтный лимит раз в 24 часа
        $regSr = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
        if (Test-Path $regSr) {
            Set-ItemProperty -Path $regSr -Name "SystemRestorePointCreationFrequency" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        }

        Checkpoint-Computer -Description $Description -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-OptLog "Контрольная точка восстановления успешно создана." 'SUCCESS'
        return $true
    }
    catch {
        Write-OptLog "Не удалось создать точку восстановления: $($_.Exception.Message)" 'WARN'
        Write-OptLog "В некоторых редакциях (LTSC/LTSB/Home) защита системы может быть отключена групповой политикой. Продолжаем выполнение." 'WARN'
        return $false
    }
}

function Set-RegistryValueSafe {
    <#
    .SYNOPSIS
        Безопасно создает ключ реестра при его отсутствии и устанавливает требуемое значение.
    #>
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Name,

        [Parameter(Mandatory = $true, Position = 2)]
        $Value,

        [Parameter(Mandatory = $false, Position = 3)]
        [ValidateSet('String', 'DWord', 'QWord', 'Binary', 'MultiString', 'ExpandString')]
        [string]$PropertyType = 'DWord'
    )

    try {
        if (-not (Test-Path -Path $Path)) {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $PropertyType -Force -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        Write-OptLog "Ошибка записи в реестр [$Path] $Name = $Value : $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

Export-ModuleMember -Function Write-OptLog, Test-IsAdmin, Get-WindowsSystemInfo, New-SystemRestorePointSafe, Set-RegistryValueSafe

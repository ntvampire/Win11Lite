@echo off
:: Проверка прав администратора
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [!] Требуются права Администратора. Запуск от имени Администратора...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

:: Запуск PowerShell скрипта оптимизации
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Optimize-Windows.ps1"
pause

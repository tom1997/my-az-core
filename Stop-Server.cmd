@echo off
chcp 65001 >nul
title AzerothCore Server - Stop
cd /d "%~dp0"
set "PWSH=pwsh.exe"
where pwsh.exe >nul 2>nul || set "PWSH=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe"
if not exist "%PWSH%" if "%PWSH%" neq "pwsh.exe" (
    echo PowerShell 7 was not found. Open this task in Codex once, then try again.
    echo.
    pause
    exit /b 1
)
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\stop.ps1" -IncludeMySql
echo.
pause

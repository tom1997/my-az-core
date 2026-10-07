@echo off
chcp 65001 >nul
title AzerothCore - 自动更新正式版
cd /d "%~dp0"
set "PWSH=pwsh.exe"
where pwsh.exe >nul 2>nul || set "PWSH=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe"
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\update-from-github.ps1" -Channel release -VisibleWorld
if errorlevel 1 (
    echo.
    echo 更新失败。请查看上面的具体原因；原有版本和备份不会被自动删除。
    echo.
    pause
)

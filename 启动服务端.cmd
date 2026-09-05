@echo off
chcp 65001 >nul
title AzerothCore - 启动服务端
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start.ps1"
if errorlevel 1 (
    echo.
    echo 启动失败，请把上面的错误发给 Codex。
) else (
    echo.
    echo 服务端已在后台启动，可以关闭本窗口。
    echo 停服时请双击「关闭服务端.cmd」。
)
echo.
pause

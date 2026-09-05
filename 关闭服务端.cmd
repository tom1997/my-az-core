@echo off
chcp 65001 >nul
title AzerothCore - 关闭服务端
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\stop.ps1" -IncludeMySql
if errorlevel 1 (
    echo.
    echo 关闭过程遇到错误，请把上面的错误发给 Codex。
) else (
    echo.
    echo World、Auth 和 MySQL 已全部关闭。
)
echo.
pause

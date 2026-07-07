@echo off
chcp 65001 >nul
title 网络重置工具
echo.
echo 网络重置工具
echo.
echo 此工具来自原 windows-utils/network-reset-tool
echo.
echo [1] 使用 BAT 脚本重置（无需 Python）
echo [2] 使用 Python GUI 重置
set /p choice=请选择: 

if "%choice%"=="1" (
    call tools\network-reset-tool\network-reset.bat
) else if "%choice%"=="2" (
    python tools\network-reset-tool\network_reset_gui.py
) else (
    echo 无效选择
)
pause

@echo off
chcp 65001 >nul
title 网络重置工具
echo.
echo 网络重置工具
echo.
echo 此工具来自原 windows-utils/network-reset-tool
echo.
call tools\network-reset-tool\network-reset.bat
pause

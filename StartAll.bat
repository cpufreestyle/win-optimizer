@echo off
chcp 65001 >nul 2>&1
title PC-Optimizer-7thGen - Windows 统一工具箱

REM ============================================================
REM  检查管理员权限
REM ============================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo   需要管理员权限！正在请求提权...
    echo.
    powershell -Command "Start-Process cmd -ArgumentList '/c %~dp0StartAll.bat' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

:MENU
cls
echo.
echo   ========================================
echo      Windows 统一工具箱 v2.0
echo      PC-Optimizer-7thGen
echo   ========================================
echo.
echo   [系统优化脚本]
echo     1. 系统信息检测
echo     2. 临时文件清理
echo     3. 服务优化
echo     4. 启动项优化
echo     5. 视觉效果优化
echo     6. 电源计划优化
echo     7. 磁盘优化
echo     8. 网络优化
echo     9. 一键全面优化
echo.
echo   [实用工具]
echo     C. C盘深度清理 (Python GUI)
echo     F. 剪贴板修复工具
echo     N. 网络重置工具
echo.
echo   [其他]
echo     G. 启动 GUI 图形界面
echo     R. 一键恢复所有设置
echo     Q. 退出
echo.
set /p choice=请选择: 

if "%choice%"=="1" goto SYSINFO
if "%choice%"=="2" goto CLEANTEMP
if "%choice%"=="3" goto SERVICES
if "%choice%"=="4" goto STARTUP
if "%choice%"=="5" goto VISUAL
if "%choice%"=="6" goto POWER
if "%choice%"=="7" goto DISK
if "%choice%"=="8" goto NETWORK
if "%choice%"=="9" goto FULLOPT
if /i "%choice%"=="C" goto CDRIVE
if /i "%choice%"=="F" goto CLIPBOARD
if /i "%choice%"=="N" goto NETRESET
if /i "%choice%"=="G" goto GUI
if /i "%choice%"=="R" goto RESTORE
if /i "%choice%"=="Q" exit /b 0
goto MENU

:SYSINFO
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\01-SystemInfo.ps1"
pause
goto MENU

:CLEANTEMP
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\02-CleanTemp.ps1"
pause
goto MENU

:SERVICES
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\03-DisableServices.ps1"
pause
goto MENU

:STARTUP
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\04-StartupOptimize.ps1"
pause
goto MENU

:VISUAL
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\05-VisualEffects.ps1"
pause
goto MENU

:POWER
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\06-PowerPlan.ps1"
pause
goto MENU

:DISK
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\07-DiskOptimize.ps1"
pause
goto MENU

:NETWORK
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\08-NetworkOptimize.ps1"
pause
goto MENU

:FULLOPT
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Optimize.ps1"
goto MENU

:CDRIVE
python "%~dp0tools\c-drive-cleaner\app.py"
if errorlevel 1 (
    echo.
    echo 运行失败，请确保已安装 Python 3.x
    echo 下载: https://www.python.org/downloads/
)
pause
goto MENU

:CLIPBOARD
python "%~dp0tools\clipboard-fixer\clipboard_fixer.py"
if errorlevel 1 (
    echo.
    echo 运行失败，请确保已安装 Python 3.x
)
pause
goto MENU

:NETRESET
call "%~dp0tools\network-reset-tool\network-reset.bat"
goto MENU

:GUI
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0OptimizeGUI.ps1"
goto MENU

:RESTORE
call "%~dp0RestoreAll.bat"
goto MENU

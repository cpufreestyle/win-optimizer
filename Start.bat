@echo off
chcp 65001 >nul 2>&1
title PC-Optimizer-7thGen - 7代CPU老电脑优化工具

REM ============================================================
REM  检查管理员权限
REM ============================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo ================================================================
    echo   需要管理员权限！正在请求提权...
    echo ================================================================
    echo.
    powershell -Command "Start-Process cmd -ArgumentList '/c %~dp0Start.bat' -Verb RunAs"
    exit /b
)

REM ============================================================
REM  检查 PowerShell 执行策略并设置
REM ============================================================
powershell -Command "if ((Get-ExecutionPolicy) -eq 'Restricted') { Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force }"

REM ============================================================
REM  选择启动模式
REM ============================================================
cd /d "%~dp0"
echo.
echo   ================================================================
echo     PC-Optimizer-7thGen  v1.0.0
echo     7代CPU老电脑 Windows 优化工具
echo   ================================================================
echo.

REM 检查 EXE 是否存在（优先使用最新版本）
set exe_path=
if exist "%~dp0PC-Optimizer.exe" set exe_path=%~dp0PC-Optimizer.exe
if exist "%~dp0PC-Optimizer-Debug.exe" if not defined exe_path set exe_path=%~dp0PC-Optimizer-Debug.exe
if exist "%~dp0PC-Optimizer-Final.exe" if not defined exe_path set exe_path=%~dp0PC-Optimizer-Final.exe
if exist "%~dp0PC-Optimizer-New.exe" if not defined exe_path set exe_path=%~dp0PC-Optimizer-New.exe

if defined exe_path (
echo   请选择启动模式:
echo.
echo     [1] EXE 程序 (推荐)
echo     [2] GUI 脚本模式
echo     [3] 命令行交互模式
echo     [4] 退出
echo.
set /p choice="请输入选项 (1/2/3/4): "
) else (
echo   请选择启动模式:
echo.
echo     [1] GUI 图形界面模式 (推荐)
echo     [2] 命令行交互模式
echo     [3] 退出
echo.
set /p choice="请输入选项 (1/2/3): "
)

if defined exe_path (
    if "%choice%"=="1" (
        echo.
        echo   正在启动 EXE 程序...
        start "" "%exe_path%"
        goto end
    )
    if "%choice%"=="2" (
        echo.
        echo   正在启动 GUI 脚本模式...
        powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0OptimizeGUI.ps1"
        goto end
    )
    if "%choice%"=="3" (
        echo.
        echo   正在启动命令行交互模式...
        powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Optimize.ps1"
        goto end
    )
    if "%choice%"=="4" (
        echo   再见！
        goto end_nopause
    )
    echo   无效选项，启动 EXE...
    start "" "%exe_path%"
    goto end
) else (
    if "%choice%"=="1" (
        echo.
        echo   正在启动 GUI 图形界面...
        powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0OptimizeGUI.ps1"
        goto end
    )
    if "%choice%"=="2" (
        echo.
        echo   正在启动命令行交互模式...
        powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Optimize.ps1"
        goto end
    )
    if "%choice%"=="3" (
        echo   再见！
        goto end_nopause
    )
    echo   无效选项，启动 GUI 模式...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0OptimizeGUI.ps1"
)

:end
pause
exit /b

:end_nopause
exit /b

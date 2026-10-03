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
set "APP_VER=3.11.0"
for /f "tokens=2 delims=:," %%v in ('findstr /i "version" "%~dp0config\optimization.json"') do set "APP_VER=%%v"
set "APP_VER=%APP_VER:"=%"
set "APP_VER=%APP_VER: =%"
echo.
echo   ================================================================
echo     PC-Optimizer-7thGen  v%APP_VER%
echo     7代CPU老电脑 Windows 优化工具
echo   ================================================================
echo.

REM 检查 EXE 是否存在（优先使用最新版本）
set exe_path=
if exist "%~dp0PC-Optimizer.exe" set exe_path=%~dp0PC-Optimizer.exe
if exist "%~dp0PC-Optimizer-Debug.exe" if not defined exe_path set exe_path=%~dp0PC-Optimizer-Debug.exe
if exist "%~dp0PC-Optimizer-Final.exe" if not defined exe_path set exe_path=%~dp0PC-Optimizer-Final.exe
if exist "%~dp0PC-Optimizer-New.exe" if not defined exe_path set exe_path=%~dp0PC-Optimizer-New.exe

REM 统一入口：新人只需回车（默认走一键向导），高级用户再选其它模式。
echo   请选择启动模式（直接回车 = 一键向导）:
echo.
echo     [1] 一键向导   （推荐）自动体检 → 给出方案 → 确认即优化 → 自动复检
echo     [2] 图形界面   （GUI）看得见每一步，可逐项点选
echo     [3] 命令行菜单 （高级）按编号逐项操作
if defined exe_path echo     [E] EXE 程序   （打包版，界面同 GUI）
echo     [Q] 退出
echo.
set "choice="
set /p choice="请输入选项 (回车=1): "
if not defined choice set "choice=1"

if "%choice%"=="1" (
    echo.
    echo   正在启动一键向导...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Optimize.ps1" -Guided
    goto end
)
if "%choice%"=="2" (
    echo.
    echo   正在启动图形界面...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0OptimizeGUI.ps1"
    goto end
)
if "%choice%"=="3" (
    echo.
    echo   正在启动命令行菜单...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Optimize.ps1"
    goto end
)
if /i "%choice%"=="E" (
    if defined exe_path (
        echo.
        echo   正在启动 EXE 程序...
        start "" "%exe_path%"
        goto end
    )
    echo   未找到 EXE，改为启动图形界面...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0OptimizeGUI.ps1"
    goto end
)
if /i "%choice%"=="Q" (
    echo   再见！
    goto end_nopause
)
echo   无效选项，改为启动一键向导...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Optimize.ps1" -Guided
goto end

:end
pause
exit /b

:end_nopause
exit /b

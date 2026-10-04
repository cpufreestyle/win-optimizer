@echo off
chcp 65001 >nul 2>&1
title PC-Optimizer-7thGen - 桌面快捷方式

REM ============================================================
REM  在桌面创建启动快捷方式（一键向导 + 图形界面）
REM  幂等：重复执行只刷新，不堆积
REM ============================================================
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-DesktopShortcuts.ps1"
set "RC=%errorlevel%"

echo.
if not "%RC%"=="0" (
    echo 创建失败，请检查上方错误信息。
    pause
    exit /b %RC%
)
echo 已在桌面创建：PC优化工具.lnk 与 PC优化工具-图形界面.lnk
echo.
pause
exit /b 0

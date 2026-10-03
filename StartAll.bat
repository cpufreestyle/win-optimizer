@echo off
chcp 65001 >nul 2>&1
title PC-Optimizer-7thGen - 启动器

REM ============================================================
REM  兼容入口：旧快捷方式/文档可能仍指向 StartAll.bat。
REM  为降低「到底该点哪个」的选择成本，这里不再维护第二套菜单，
REM  直接转发到唯一入口 Start.bat（内部已含提权与模式选择）。
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
call "%~dp0Start.bat"
exit /b %errorlevel%

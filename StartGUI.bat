@echo off
chcp 65001 >nul 2>&1
title PC-Optimizer-7thGen GUI

REM ============================================================
REM  检查管理员权限并自动提权
REM ============================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c %~dp0StartGUI.bat' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0OptimizeGUI.ps1"

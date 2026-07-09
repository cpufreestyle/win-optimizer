@echo off
:: PC-Optimizer-7thGen 启动器
:: 自动请求管理员权限并启动 GUI

>nul 2>&1 net session
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0OptimizeGUI.ps1"

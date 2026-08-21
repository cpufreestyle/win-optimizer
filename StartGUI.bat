@echo off
:: PC-Optimizer-7thGen launcher - request admin and start GUI

>nul 2>&1 net session
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0OptimizeGUI.ps1"

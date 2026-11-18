@echo off
:: PC-Optimizer-7thGen launcher - request admin and start GUI

set "PS=powershell.exe"
for /f "delims=" %%I in ('where pwsh.exe 2^>nul') do if not defined PWSH set "PWSH=%%I"
if defined PWSH set "PS=%PWSH%"

>nul 2>&1 net session
if %errorlevel% neq 0 (
    "%PS%" -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0OptimizeGUI.ps1"

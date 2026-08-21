@echo off
chcp 65001 >nul 2>&1
title 启用 .ps1 双击直接运行

REM ============================================================
REM  管理员权限自检（无则自动提权）
REM ============================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo 需要管理员权限，正在请求提权...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

echo.
echo ================================================================
echo   正在配置：双击 .ps1 文件直接运行（而非用编辑器打开）
echo ================================================================
echo.

REM 1) 设置 PowerShell 执行策略（当前用户，允许本地脚本）
powershell -NoProfile -Command "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force"
echo [OK] 已设置执行策略为 RemoteSigned

REM 2) 关联 .ps1 到 PowerShell 脚本类型
cmd /c "assoc .ps1=Microsoft.PowerShellScript.1"
echo [OK] 已关联 .ps1 文件类型

REM 3) 设置双击时用 powershell 直接执行（含自动提权包装）
REM    用 RunAs 方式启动，确保需要管理员的操作也能正常运行
set "RUNNER=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
cmd /c "ftype Microsoft.PowerShellScript.1=\"%RUNNER%\" -NoProfile -ExecutionPolicy Bypass -Command \"if (!(net session 2>nul)) { Start-Process '%RUNNER%' -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"\"%1\"\"' -Verb RunAs } else { & '%RUNNER%' -NoProfile -ExecutionPolicy Bypass -File \"\"%1\"\" }\""

echo [OK] 已设置双击运行方式（自动请求管理员权限）

REM 4) 清除可能存在的“用户选择默认程序”记录，避免被记事本劫持
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.ps1\UserChoice" /f >nul 2>&1

echo.
echo ================================================================
echo   配置完成！现在双击任意 .ps1 文件即可直接运行。
echo   注意：双击时会弹出 UAC 提权确认框（点“是”即可）。
echo ================================================================
echo.
pause

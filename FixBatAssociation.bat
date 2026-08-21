@echo off
chcp 65001 >nul 2>&1
title 修复 .bat 双击运行

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
echo   正在修复 .bat 文件双击运行（恢复系统默认关联）
echo ================================================================
echo.

REM 1) 恢复 .bat 关联到系统默认的 batfile 类型
cmd /c "assoc .bat=batfile"
echo [OK] 已重新关联 .bat=batfile

REM 2) 重建 batfile 的打开命令（系统默认：用 cmd.exe 执行）
reg add "HKLM\Software\Classes\batfile\shell\open\command" /ve /t REG_EXPAND_SZ /d "%%SystemRoot%%\System32\cmd.exe /c \"%%1\" %%*" /f >nul
echo [OK] 已重建 batfile 执行命令

REM 3) 清掉可能被编辑器“劫持”的用户默认程序记录
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.bat\UserChoice" /f >nul 2>&1
echo [OK] 已清除 .bat 用户默认程序记录

REM 4) 刷新资源管理器缓存，让关联立即生效
taskkill /f /im explorer.exe >nul 2>&1
start "" explorer.exe
echo [OK] 已刷新资源管理器

echo.
echo ================================================================
echo   修复完成！现在双击任意 .bat 文件即可直接运行。
echo   如果之前用记事本/IDE 打开过，请关闭重开资源管理器窗口。
echo ================================================================
echo.
pause

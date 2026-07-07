@echo off
chcp 65001 >nul
title 剪贴板修复工具
echo.
echo 剪贴板修复工具
echo.
echo 此工具来自原 windows-utils/clipboard-fixer
echo.
python tools\clipboard-fixer\clipboard_fixer.py
if errorlevel 1 (
    echo.
    echo 运行失败，请确保已安装 Python 3.x
    pause
)
pause

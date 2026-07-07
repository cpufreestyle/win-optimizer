@echo off
chcp 65001 >nul
title C盘深度清理工具
echo.
echo C盘深度清理工具
echo.
echo 此工具来自原 windows-utils/c-drive-cleaner
echo 需要 Python 3.x 和 tkinter 库
echo.
python tools\c-drive-cleaner\app.py
if errorlevel 1 (
    echo.
    echo 运行失败，请确保已安装 Python 3.x
    echo 下载: https://www.python.org/downloads/
    pause
)
pause

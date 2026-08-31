@echo off
chcp 65001 >nul 2>&1
setlocal
cd /d "%~dp0"
set "WEBUI=%~dp0webui"

REM 以管理员身份运行（部分优化需要管理员权限）
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [请求管理员权限...]
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo ================================================
echo   PC-Optimizer-7thGen WebUI
echo   访问地址: http://127.0.0.1:5000
echo   WebMCP   : http://127.0.0.1:5001/sse (需 pip install mcp)
echo ================================================
echo.
cd /d "%WEBUI%"
python app.py
pause

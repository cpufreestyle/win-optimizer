@echo off
chcp 65001 >nul 2>&1
setlocal
cd /d "%~dp0"

echo ================================================
echo   安装 WebMCP (MCP) Python 依赖
echo ================================================
echo.

python -m pip --version >nul 2>&1
if errorlevel 1 (
    echo [错误] 未找到 python，请先安装 Python 3.10+ 并加入 PATH
    pause
    exit /b 1
)

python -c "import mcp" >nul 2>&1
if not errorlevel 1 (
    echo [信息] mcp 已安装，跳过
    pause
    exit /b 0
)

echo [安装] 正在 pip install mcp ...
python -m pip install --upgrade pip
python -m pip install mcp
if errorlevel 1 (
    echo [失败] mcp 安装失败，请检查网络
    pause
    exit /b 1
)

python -c "from mcp.server.fastmcp import FastMCP; print('FastMCP OK')" >nul 2>&1
if errorlevel 1 (
    echo [警告] mcp 装好但 FastMCP 不可用，版本可能不兼容
) else (
    echo [成功] mcp + FastMCP 已就绪
)

echo.
echo ================================================
echo   现在运行 StartWebUI.bat 即可：
echo   - WebUI  : http://127.0.0.1:5000
echo   - MCP SSE: http://127.0.0.1:5001/sse
echo ================================================
pause

@echo off
setlocal
set GH="C:\Program Files\GitHub CLI\gh.exe"
set ROOT=%~dp0..

cd /d "%ROOT%"

echo ============================================
echo  PC-Optimizer v3.0.0 发布脚本
echo ============================================

echo.
echo [1/3] 登录 GitHub（将在浏览器中完成授权，请按提示操作）
echo      若已登录可跳过：直接关闭浏览器窗口后此步会报错，可注释掉下一行重跑。
%GH% auth login
if errorlevel 1 (
    echo 登录失败或已取消，请先手动运行: gh auth login
    pause
    exit /b 1
)

echo.
echo [2/3] 推送 main 分支与 v3.0.0 tag
git push origin main --tags --force

echo.
echo [3/3] 创建 GitHub Release 并上传 PC-Optimizer.exe
%GH% release create v3.0.0 "PC-Optimizer.exe" --title "v3.0.0" --notes-file "tools\release-notes-v3.0.0.md"

echo.
echo 发布完成。
pause

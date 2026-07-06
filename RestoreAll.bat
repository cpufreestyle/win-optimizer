@echo off
chcp 65001 >nul 2>&1
title PC-Optimizer-7thGen - 快速恢复所有设置

REM ============================================================
REM  检查管理员权限
REM ============================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo   需要管理员权限！正在请求提权...
    echo.
    powershell -Command "Start-Process cmd -ArgumentList '/c %~dp0RestoreAll.bat' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
echo.
echo   ================================================================
echo     PC-Optimizer-7thGen 一键恢复工具
echo   ================================================================
echo.
echo   此脚本将：
echo     1. 恢复默认电源方案
echo     2. 从备份恢复服务设置
echo     3. 从备份恢复视觉效果
echo     4. 恢复启动项
echo.
echo   请确保 backups 目录中有备份文件。
echo.
pause

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$backupDir = '%~dp0backups';" ^
    "Write-Host '正在恢复默认电源方案...' -ForegroundColor Yellow;" ^
    "powercfg /restoredefaultschemes 2>&1 | Out-Null;" ^
    "Write-Host '[完成] 默认电源方案已恢复' -ForegroundColor Green;" ^
    "$svcBackups = Get-ChildItem -Path $backupDir -Filter 'services_backup_*.csv' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending;" ^
    "if ($svcBackups) {" ^
    "  Write-Host '正在恢复服务设置...' -ForegroundColor Yellow;" ^
    "  $data = Import-Csv -Path $svcBackups[0].FullName -Encoding UTF8;" ^
    "  foreach ($row in $data) {" ^
    "    $svc = Get-Service -Name $row.Name -ErrorAction SilentlyContinue;" ^
    "    if ($svc) {" ^
    "      $st = switch ($row.StartType) { 'Auto' {'Automatic'} 'Manual' {'Manual'} 'Disabled' {'Disabled'} default {$row.StartType} };" ^
    "      Set-Service -Name $row.Name -StartupType $st -ErrorAction SilentlyContinue;" ^
    "      if ($row.Status -eq 'Running') { Start-Service -Name $row.Name -ErrorAction SilentlyContinue }" ^
    "    }" ^
    "  }" ^
    "  Write-Host '[完成] 服务设置已恢复' -ForegroundColor Green;" ^
    "} else { Write-Host '[跳过] 未找到服务备份' -ForegroundColor Gray };" ^
    "$visBackups = Get-ChildItem -Path $backupDir -Filter 'visual_backup_*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending;" ^
    "if ($visBackups) {" ^
    "  Write-Host '正在恢复视觉效果...' -ForegroundColor Yellow;" ^
    "  $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects';" ^
    "  if (Test-Path $key) { Set-ItemProperty -Path $key -Name 'VisualFXSetting' -Value 0 -ErrorAction SilentlyContinue }" ^
    "  Write-Host '[完成] 视觉效果已恢复为系统默认' -ForegroundColor Green;" ^
    "} else { Write-Host '[跳过] 未找到视觉备份' -ForegroundColor Gray };" ^
    "$startupDir = Join-Path $backupDir 'startup_items';" ^
    "if (Test-Path $startupDir) {" ^
    "  $files = Get-ChildItem -Path $startupDir -File -ErrorAction SilentlyContinue;" ^
    "  if ($files) {" ^
    "    Write-Host '正在恢复启动文件夹项...' -ForegroundColor Yellow;" ^
    "    $dest = \"$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\";" ^
    "    foreach ($f in $files) { Move-Item -Path $f.FullName -Destination $dest -Force -ErrorAction SilentlyContinue }" ^
    "    Write-Host '[完成] 启动文件夹项已恢复' -ForegroundColor Green;" ^
    "  }" ^
    "};" ^
    "Write-Host '';" ^
    "Write-Host '================================================' -ForegroundColor Cyan;" ^
    "Write-Host '  恢复完成！请重启电脑使所有更改生效。' -ForegroundColor Green;" ^
    "Write-Host '================================================' -ForegroundColor Cyan;"

echo.
pause

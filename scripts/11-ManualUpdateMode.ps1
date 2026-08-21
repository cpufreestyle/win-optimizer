<#
.SYNOPSIS
    仅改 Windows Update 为手动安装模式（不暂停更新）
.DESCRIPTION
    只把 Windows Update 设为 "通知下载并通知安装"（AUOptions=2），
    更新仍会下载并提示，但不会自动安装、不会强制重启弹窗。
    与 [10] 的"暂停更新"不同，本模块不改变暂停状态，
    适合想装更新但不想被强制重启的用户。
    注册表更改自动备份（.reg），可通过 [R] 一键恢复。
.NOTES
    需要以管理员身份运行（由 Optimize.ps1 入口统一校验）。
#>

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   手动安装模式（不暂停更新）" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# --- 备份 ---
$backupDir = Join-Path $PSScriptRoot "..\backups"
$backupDir = [System.IO.Path]::GetFullPath($backupDir)
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }

$auKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
$backupFile = Join-Path $backupDir "manual_update_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
Write-Host "`n[1/2] 备份当前自动更新设置..." -ForegroundColor Yellow
if (Test-Path $auKey) {
    & reg export $auKey $backupFile /y 2>$null
    Write-Host "  备份已保存: $backupFile" -ForegroundColor Green
} else {
    Write-Host "  当前无策略键，无需备份（将直接创建）。" -ForegroundColor Gray
}

# --- 用户确认 ---
Write-Host ""
Write-Host "  即将执行：" -ForegroundColor Yellow
Write-Host "   把 Windows Update 改为 '通知下载并通知安装'" -ForegroundColor Gray
Write-Host "   更新仍会下载并提示，但不自动安装/强制重启" -ForegroundColor Gray
$confirm = Read-Host "`n确认改为手动安装模式？(Y/N)"
if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-Host "  操作已取消。" -ForegroundColor Gray
    Write-Host "============================================" -ForegroundColor Cyan
    return
}

# --- 应用 ---
Write-Host "`n[2/2] 正在设置手动安装模式..." -ForegroundColor Yellow
try {
    if (-not (Test-Path $auKey)) { New-Item -Path $auKey -Force | Out-Null }
    Set-ItemProperty -Path $auKey -Name "NoAutoUpdate" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $auKey -Name "AUOptions" -Value 2 -Type DWord -Force
    Write-Host "  [已设置] 自动更新 = 通知下载并通知安装 (AUOptions=2)" -ForegroundColor Green
} catch {
    Write-Host "  [失败] $($_.Exception.Message)" -ForegroundColor Red
}

# 重启服务生效
foreach ($svc in @("wuauserv", "UsoSvc")) {
    try { Restart-Service -Name $svc -Force -ErrorAction SilentlyContinue; Write-Host "  [完成] $svc 已重启" -ForegroundColor Green } catch {}
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  已完成！" -ForegroundColor Green
Write-Host "  更新照常下载并提示，但不会自动安装或强制重启。" -ForegroundColor Gray
Write-Host "  想装时去 设置 -> Windows 更新 手动点即可。" -ForegroundColor Gray
Write-Host "  如需恢复自动更新：用 [R] 恢复本模块 .reg 备份。" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan

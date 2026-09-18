<#
.SYNOPSIS
    电源计划优化模块 — 切换高性能电源计划以提升 CPU 响应
.DESCRIPTION
    针对 7代及更老 CPU，优化电源设置：
    - 切换到高性能电源计划
    - 如有"卓越性能"计划则启用
    - 调整 CPU 最小/最大处理器状态
    - 禁用 USB 选择性挂起
    - 调整硬盘休眠时间
    - 调整无线适配器电源模式
#>

# 复用共享核心库（电源计划统一实现，与 GUI / WebUI 同源）
$coreLib = Join-Path $PSScriptRoot "..\lib\Optimize.Core.ps1"
if (Test-Path $coreLib) { . $coreLib }
if (-not (Get-Command Set-PowerPlan -ErrorAction SilentlyContinue)) {
    Write-Host "错误：未找到共享核心库 lib\Optimize.Core.ps1，无法应用电源计划。" -ForegroundColor Red
    return
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "         电源计划优化" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# --- 显示当前电源计划 ---
Write-Host "`n[1/3] 当前电源计划:" -ForegroundColor Yellow
$currentPlan = powercfg /getactivescheme
Write-Host "  $currentPlan" -ForegroundColor Gray

# 列出所有可用电源计划
Write-Host "`n  可用电源计划:" -ForegroundColor Gray
$plans = powercfg /list 2>&1
Write-Host "  $plans" -ForegroundColor Gray

# --- 备份（统一走共享库）---
$backupDir = Join-Path (Split-Path -Parent $PSScriptRoot) "backups"
$backupFile = Backup-PowerPlan -BackupDir $backupDir
Write-Host "`n  备份已保存: $backupFile" -ForegroundColor Green

# --- 显示选项 ---
Write-Host "`n[2/3] 选择优化方案:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  [1] 高性能模式 (推荐) — 最大化 CPU 性能，适合台式机/插电笔记本"
Write-Host "  [2] 卓越性能模式 — 比高性能更高，需先解锁"
Write-Host "  [3] 平衡优化模式 — 在平衡基础上优化，适合笔记本电池模式"
Write-Host "  [4] 自定义 CPU 频率 — 设置 CPU 最小频率百分比"
Write-Host "  [N] 取消"
$choice = Read-Host "选择 (1/2/3/4/N)"

if ($choice -eq "N" -or $choice -eq "n") {
    Write-Host "  操作已取消。" -ForegroundColor Gray
    Write-Host "============================================" -ForegroundColor Cyan
    return
}

if ($choice -notmatch "^[1234]$") {
    Write-Host "  无效选择，操作取消。" -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Cyan
    return
}

Write-Host "`n[3/3] 正在应用电源优化..." -ForegroundColor Yellow

$catalog = Get-PowerPlanCatalog

if ($choice -eq "4") {
    # 自定义 CPU 频率（统一走共享库）
    Write-Host ""
    $minFreq = Read-Host "输入 CPU 最小频率百分比 (1-100, 推荐: 5-100)"
    $maxFreq = Read-Host "输入 CPU 最大频率百分比 (1-100, 推荐: 100)"
    if ($minFreq -match "^\d+$" -and $maxFreq -match "^\d+$") {
        $r = Set-CpuThrottle -MinPercent ([int]$minFreq) -MaxPercent ([int]$maxFreq)
        if ($r.ok) {
            Write-Host "  [完成] CPU 频率: 最低$($r.min)% / 最高$($r.max)%" -ForegroundColor Green
        } else {
            Write-Host "  [错误] $($r.error)" -ForegroundColor Red
            Write-Host "============================================" -ForegroundColor Cyan
            return
        }
    } else {
        Write-Host "  [错误] 请输入有效数字" -ForegroundColor Red
        Write-Host "============================================" -ForegroundColor Cyan
        return
    }
} else {
    $profile = [int]$choice
    $plan = $catalog | Where-Object { $_.Value -eq $profile }
    if ($profile -eq 2) { Write-Host "  正在解锁卓越性能计划..." -ForegroundColor Yellow }

    # 统一走共享库（与 GUI / WebUI 同一份实现，含解锁失败回退）
    $params = @{
        Guid               = $plan.GUID
        BackupDir          = $backupDir
        SkipBackup         = $true   # 本脚本已在上面备份过
        UnlockUltimate     = ($profile -eq 2)
        FallbackToHighPerf = ($profile -eq 2)
    }
    switch ($profile) {
        1 { $params.MinPercent = 100; $params.MaxPercent = 100; $params.DiskIdleSeconds = 0;    $params.UsbSuspendOff = $true; $params.PciAspmOff = $true; $params.WirelessMaxPerf = $true }
        2 { $params.MinPercent = 100; $params.MaxPercent = 100; $params.DiskIdleSeconds = 0;    $params.UsbSuspendOff = $true; $params.PciAspmOff = $true }
        3 { $params.MinPercent = 5;   $params.MaxPercent = 100; $params.DiskIdleSeconds = 1800; $params.UsbSuspendOff = $true }
    }
    $r = Set-PowerPlan @params
    Write-Host "  [完成] 已切换到$(if ($r.fallback) { '高性能' } else { $plan.Title })电源计划" -ForegroundColor Green
    foreach ($d in $r.details) { Write-Host "  [完成] $d" -ForegroundColor Green }
    if ($r.fallback) { Write-Host "  注意: 卓越性能计划解锁失败，已回退高性能计划" -ForegroundColor Yellow }
}

# 显示当前活动计划
Write-Host "`n当前活动电源计划:" -ForegroundColor Yellow
$currentPlan = powercfg /getactivescheme
Write-Host "  $currentPlan" -ForegroundColor Green

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  电源计划优化完成！" -ForegroundColor Green
Write-Host "  备份文件: $backupFile" -ForegroundColor Gray
Write-Host "  提示: 笔记本电池模式下建议使用平衡模式以延长续航" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan

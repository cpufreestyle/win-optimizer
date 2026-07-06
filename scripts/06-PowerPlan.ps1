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

# --- 备份 ---
$backupFile = Join-Path $PSScriptRoot "..\backups\power_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$backupFile = [System.IO.Path]::GetFullPath($backupFile)
powercfg /query > $backupFile 2>&1
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

Write-Host "`n[3/3] 正在应用电源优化..." -ForegroundColor Yellow

switch ($choice) {
    "1" {
        # 高性能模式
        $highPerfGuid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
        powercfg /setactive $highPerfGuid 2>&1 | Out-Null
        Write-Host "  [完成] 已切换到高性能电源计划" -ForegroundColor Green

        # 优化高性能计划的具体设置
        # CPU 最小状态 100%，最大状态 100%
        powercfg /setacvalueindex $highPerfGuid SUB_PROCESSOR PROCTHROTTLEMIN 100 2>&1 | Out-Null
        powercfg /setacvalueindex $highPerfGuid SUB_PROCESSOR PROCTHROTTLEMAX 100 2>&1 | Out-Null
        Write-Host "  [完成] CPU 处理器状态: 最低100% / 最高100% (AC电源)" -ForegroundColor Green

        # 禁用 USB 选择性挂起
        powercfg /setacvalueindex $highPerfGuid SUB_USB USBSELSUSP 0 2>&1 | Out-Null
        Write-Host "  [完成] USB 选择性挂起: 已禁用" -ForegroundColor Green

        # 硬盘从不休眠
        powercfg /setacvalueindex $highPerfGuid SUB_DISK DISKIDLE 0 2>&1 | Out-Null
        Write-Host "  [完成] 硬盘休眠: 从不 (AC电源)" -ForegroundColor Green

        # 无线适配器: 最高性能
        powercfg /setacvalueindex $highPerfGuid SUB_NONE WIRELESS_PWRSAV 0 2>&1 | Out-Null
        Write-Host "  [完成] 无线适配器电源模式: 最高性能" -ForegroundColor Green

        # PCI Express 链接状态电源管理: 关闭
        powercfg /setacvalueindex $highPerfGuid SUB_PCIEXPRESS ASPM 0 2>&1 | Out-Null
        Write-Host "  [完成] PCI Express 电源管理: 关闭" -ForegroundColor Green

        # 应用设置
        powercfg /setactive $highPerfGuid 2>&1 | Out-Null
    }

    "2" {
        # 卓越性能模式 (需要先解锁)
        $ultimateGuid = "e9a42b02-d5df-448d-aa00-03f14749eb61"

        Write-Host "  正在解锁卓越性能计划..." -ForegroundColor Yellow
        powercfg /duplicatescheme $ultimateGuid 2>&1 | Out-Null

        # 检查是否成功
        $ultimatePlan = powercfg /list 2>&1 | Select-String "e9a42b02"
        if ($ultimatePlan) {
            powercfg /setactive $ultimateGuid 2>&1 | Out-Null
            Write-Host "  [完成] 已切换到卓越性能电源计划" -ForegroundColor Green

            # 同样优化设置
            powercfg /setacvalueindex $ultimateGuid SUB_PROCESSOR PROCTHROTTLEMIN 100 2>&1 | Out-Null
            powercfg /setacvalueindex $ultimateGuid SUB_PROCESSOR PROCTHROTTLEMAX 100 2>&1 | Out-Null
            powercfg /setacvalueindex $ultimateGuid SUB_USB USBSELSUSP 0 2>&1 | Out-Null
            powercfg /setacvalueindex $ultimateGuid SUB_DISK DISKIDLE 0 2>&1 | Out-Null
            powercfg /setacvalueindex $ultimateGuid SUB_PCIEXPRESS ASPM 0 2>&1 | Out-Null
            powercfg /setactive $ultimateGuid 2>&1 | Out-Null
            Write-Host "  [完成] 所有优化已应用" -ForegroundColor Green
        } else {
            Write-Host "  [失败] 卓越性能计划解锁失败，尝试使用高性能计划..." -ForegroundColor Yellow
            powercfg /setactive "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" 2>&1 | Out-Null
            Write-Host "  [完成] 已切换到高性能电源计划" -ForegroundColor Green
        }
    }

    "3" {
        # 平衡优化模式
        $balancedGuid = "381b4222-f694-41f0-9685-ff5bb260df2e"
        powercfg /setactive $balancedGuid 2>&1 | Out-Null
        Write-Host "  [完成] 已切换到平衡电源计划" -ForegroundColor Green

        # CPU 最小状态 5%，最大 100%
        powercfg /setacvalueindex $balancedGuid SUB_PROCESSOR PROCTHROTTLEMIN 5 2>&1 | Out-Null
        powercfg /setacvalueindex $balancedGuid SUB_PROCESSOR PROCTHROTTLEMAX 100 2>&1 | Out-Null
        Write-Host "  [完成] CPU 处理器状态: 最低5% / 最高100% (AC电源)" -ForegroundColor Green

        # 禁用 USB 选择性挂起
        powercfg /setacvalueindex $balancedGuid SUB_USB USBSELSUSP 0 2>&1 | Out-Null
        Write-Host "  [完成] USB 选择性挂起: 已禁用" -ForegroundColor Green

        # 硬盘休眠 30 分钟
        powercfg /setacvalueindex $balancedGuid SUB_DISK DISKIDLE 1800 2>&1 | Out-Null
        Write-Host "  [完成] 硬盘休眠: 30分钟" -ForegroundColor Green

        powercfg /setactive $balancedGuid 2>&1 | Out-Null
    }

    "4" {
        # 自定义 CPU 频率
        Write-Host ""
        $minFreq = Read-Host "输入 CPU 最小频率百分比 (1-100, 推荐: 5-100)"
        $maxFreq = Read-Host "输入 CPU 最大频率百分比 (1-100, 推荐: 100)"

        if ($minFreq -match "^\d+$" -and $maxFreq -match "^\d+$") {
            $minVal = [int]$minFreq
            $maxVal = [int]$maxFreq

            if ($minVal -lt 1 -or $minVal -gt 100 -or $maxVal -lt 1 -or $maxVal -gt 100) {
                Write-Host "  [错误] 值必须在 1-100 之间" -ForegroundColor Red
                Write-Host "============================================" -ForegroundColor Cyan
                return
            }

            $activeGuid = (powercfg /getactivescheme) -replace ".*GUID: ([a-f0-9-]+).*", '$1'
            powercfg /setacvalueindex $activeGuid SUB_PROCESSOR PROCTHROTTLEMIN $minVal 2>&1 | Out-Null
            powercfg /setacvalueindex $activeGuid SUB_PROCESSOR PROCTHROTTLEMAX $maxVal 2>&1 | Out-Null
            powercfg /setactive $activeGuid 2>&1 | Out-Null

            Write-Host "  [完成] CPU 频率: 最低${minVal}% / 最高${maxVal}%" -ForegroundColor Green
        } else {
            Write-Host "  [错误] 请输入有效数字" -ForegroundColor Red
            Write-Host "============================================" -ForegroundColor Cyan
            return
        }
    }

    default {
        Write-Host "  无效选择，操作取消。" -ForegroundColor Red
        Write-Host "============================================" -ForegroundColor Cyan
        return
    }
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

<#
.SYNOPSIS
    7代CPU老电脑 Windows 系统优化工具
.DESCRIPTION
    专为 7代及更老 CPU 的 Windows 10/11 电脑设计的系统优化脚本。
    包含临时文件清理、服务优化、启动项管理、视觉效果调整、电源计划优化、
    磁盘优化、网络优化等功能，并提供备份与恢复机制。
.NOTES
    需要以管理员身份运行 PowerShell
    作者: PC-Optimizer-7thGen
    日期: 2026-07-06
#>

#Requires -Version 5.1

# ============================================================
#  全局变量与初始化
# ============================================================
$script:ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ScriptsDir  = Join-Path $ProjectRoot "scripts"
$script:ConfigDir   = Join-Path $ProjectRoot "config"
$script:BackupDir   = Join-Path $ProjectRoot "backups"
$script:LogFile     = Join-Path $ProjectRoot "optimize.log"
$script:Version     = "1.0.0"

# ============================================================
#  工具函数
# ============================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    switch ($Level) {
        "ERROR"   { Write-Host $line -ForegroundColor Red }
        "WARN"    { Write-Host $line -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $line -ForegroundColor Green }
        default   { Write-Host $line -ForegroundColor Cyan }
    }
}

function Test-Administrator {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-ScriptModule {
    param([string]$ScriptName)
    $scriptPath = Join-Path $ScriptsDir $ScriptName
    if (Test-Path $scriptPath) {
        Write-Log "正在执行模块: $ScriptName ..."
        & $scriptPath
        Write-Log "模块 $ScriptName 执行完成。" "SUCCESS"
    } else {
        Write-Log "找不到模块文件: $scriptPath" "ERROR"
    }
    Write-Host ""
    Read-Host "按回车键返回主菜单"
}

function Show-Banner {
    Clear-Host
    $banner = @"
  ____  ____  ___  ____  _____    _    ____  
 |  _ \|  _ \/ _ \|  _ \| ____|  / \  / ___| 
 | |_) | |_) | | | | | | |  _|   / _ \| |    
 |  __/|  _ <| |_| | |_| | |___ / ___ \ |___ 
 |_|   |_| \_\\___/|____/|_____/_/   \_\____|
                                              
   7代CPU老电脑 Windows 优化工具 v$Version
   专为 Intel 7代及更老 CPU 打造 | Windows 10/11
"@
    Write-Host $banner -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor DarkGray
}

# ============================================================
#  主菜单
# ============================================================

function Show-Menu {
    while ($true) {
        Show-Banner

        # 显示当前系统简要信息
        $os = (Get-CimInstance Win32_OperatingSystem)
        $cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1)
        $totalMem = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $freeMem  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        $uptime   = (Get-Date) - $os.LastBootUpTime

        Write-Host " [系统概况]" -ForegroundColor Yellow
        Write-Host "   CPU      : $($cpu.Name)"
        Write-Host "   内存     : ${totalMem}GB (可用 ${freeMem}GB)"
        Write-Host "   系统     : $($os.Caption) Build $($os.BuildNumber)"
        Write-Host "   运行时间 : $($uptime.Days)天 $($uptime.Hours)小时"
        Write-Host ""

        Write-Host " [优化选项]" -ForegroundColor Yellow
        Write-Host "   [1]  系统信息检测        — 查看详细硬件与系统信息"
        Write-Host "   [2]  临时文件清理        — 清理系统/用户临时文件、缓存"
        Write-Host "   [3]  服务优化            — 禁用不必要的后台服务"
        Write-Host "   [4]  启动项优化          — 管理并禁用多余开机启动项"
        Write-Host "   [5]  视觉效果优化        — 降低视觉特效，提升响应速度"
        Write-Host "   [6]  电源计划优化        — 切换高性能电源计划"
        Write-Host "   [7]  磁盘优化            — 磁盘清理与碎片整理/SSD优化"
        Write-Host "   [8]  网络优化            — 优化DNS与网络参数"
        Write-Host "   [9]  一键全面优化        — 执行上述所有优化（推荐）"
        Write-Host ""
        Write-Host " [工具]" -ForegroundColor Yellow
        Write-Host "   [B]  备份当前系统设置"
        Write-Host "   [R]  恢复系统设置"
        Write-Host ""
        Write-Host "   [Q]  退出"
        Write-Host ("=" * 60) -ForegroundColor DarkGray

        $choice = Read-Host "请输入选项"

        switch ($choice) {
            "1" { Invoke-ScriptModule "01-SystemInfo.ps1" }
            "2" { Invoke-ScriptModule "02-CleanTemp.ps1" }
            "3" { Invoke-ScriptModule "03-DisableServices.ps1" }
            "4" { Invoke-ScriptModule "04-StartupOptimize.ps1" }
            "5" { Invoke-ScriptModule "05-VisualEffects.ps1" }
            "6" { Invoke-ScriptModule "06-PowerPlan.ps1" }
            "7" { Invoke-ScriptModule "07-DiskOptimize.ps1" }
            "8" { Invoke-ScriptModule "08-NetworkOptimize.ps1" }
            "9" { Invoke-FullOptimization }
            "b" { Invoke-ScriptModule "09-BackupRestore.ps1" }
            "B" { Invoke-ScriptModule "09-BackupRestore.ps1" }
            "r" { Invoke-ScriptModule "09-BackupRestore.ps1" }
            "R" { Invoke-ScriptModule "09-BackupRestore.ps1" }
            "q" { Write-Host "感谢使用，再见！" -ForegroundColor Green; return }
            "Q" { Write-Host "感谢使用，再见！" -ForegroundColor Green; return }
            default { Write-Host "无效选项，请重新输入。" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

function Invoke-FullOptimization {
    Write-Log "开始一键全面优化..." "WARN"
    Write-Host ""
    Write-Host "即将执行所有优化操作，这可能需要几分钟时间。" -ForegroundColor Yellow
    Write-Host "建议先执行备份 [B] 以便后续恢复。" -ForegroundColor Yellow
    $confirm = Read-Host "确认执行全面优化？(Y/N)"
    if ($confirm -ne "Y" -and $confirm -ne "y") {
        Write-Host "已取消。" -ForegroundColor Gray
        Read-Host "按回车键返回主菜单"
        return
    }

    $modules = @(
        "02-CleanTemp.ps1",
        "03-DisableServices.ps1",
        "04-StartupOptimize.ps1",
        "05-VisualEffects.ps1",
        "06-PowerPlan.ps1",
        "07-DiskOptimize.ps1",
        "08-NetworkOptimize.ps1"
    )

    $total = $modules.Count
    $current = 0
    foreach ($mod in $modules) {
        $current++
        Write-Host ""
        Write-Host "[$current/$total] " -NoNewline -ForegroundColor Yellow
        Invoke-ScriptModule $mod
    }

    Write-Host ""
    Write-Log "一键全面优化完成！建议重启电脑使所有更改生效。" "SUCCESS"
    Read-Host "按回车键返回主菜单"
}

# ============================================================
#  入口
# ============================================================

if (-not (Test-Administrator)) {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Red
    Write-Host "  错误：请以管理员身份运行此脚本！" -ForegroundColor Red
    Write-Host "  右键 PowerShell -> 以管理员身份运行" -ForegroundColor Red
    Write-Host "  然后执行: cd C:\PC-Optimizer-7thGen; .\Optimize.ps1" -ForegroundColor Red
    Write-Host "================================================" -ForegroundColor Red
    Write-Host ""
    pause
    exit 1
}

Write-Log "===== PC-Optimizer-7thGen v$Version 启动 ====="
Show-Menu
Write-Log "===== 程序退出 ====="

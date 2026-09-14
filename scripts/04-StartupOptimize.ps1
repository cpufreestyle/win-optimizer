<#
.SYNOPSIS
    启动项优化模块 — 管理并禁用多余的开机启动项
.DESCRIPTION
    列出所有开机启动项，让用户选择性地禁用不必要的程序，
    以加快开机速度并减少后台资源占用。
#>

# 复用共享核心库（启动项统一实现，与 GUI / WebUI 同源）
$coreLib = Join-Path $PSScriptRoot "..\lib\Optimize.Core.ps1"
if (Test-Path $coreLib) { . $coreLib }
if (-not (Get-Command Get-StartupItems -ErrorAction SilentlyContinue)) {
    Write-Host "错误：未找到共享核心库 lib\Optimize.Core.ps1，无法枚举启动项。" -ForegroundColor Red
    return
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "         启动项优化" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# --- 获取启动项 ---
Write-Host "`n[1/2] 正在扫描启动项...`n" -ForegroundColor Yellow

# 统一走共享库：5 个注册表项 + 2 个启动文件夹 + WMI 系统启动命令（去重、统一编号）
$startupItems = @(Get-StartupItems)

# --- 显示启动项 ---
if ($startupItems.Count -eq 0) {
    Write-Host "  未发现启动项。" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Cyan
    return
}

Write-Host "  发现 $($startupItems.Count) 个启动项:" -ForegroundColor Green
Write-Host ""
Write-Host "  $('序号'.PadLeft(4))  $('名称'.PadRight(35)) $('来源'.PadRight(12)) 范围" -ForegroundColor DarkGray
Write-Host "  $('-' * 80)" -ForegroundColor DarkGray

foreach ($item in $startupItems) {
    $displayName = if ($item.Name.Length -gt 33) { $item.Name.Substring(0, 30) + "..." } else { $item.Name }
    Write-Host "  $($item.Index.ToString().PadLeft(4))  $($displayName.PadRight(35)) $($item.Source.PadRight(12)) $($item.Scope)"
}

Write-Host ""
Write-Host "  常见可安全禁用的启动项:" -ForegroundColor Yellow
Write-Host "    - OneDrive, Skype, Teams (如不常使用)"
Write-Host "    - 各类更新检查程序 (Adobe Update, Java Update 等)"
Write-Host "    - 第三方软件自启动 (迅雷, 360, WPS 等)"
Write-Host ""

# --- 让用户选择 ---
Write-Host "[2/2] 选择要禁用的启动项" -ForegroundColor Yellow
Write-Host "  输入序号(用逗号分隔, 如 1,3,5) 禁用对应项"
Write-Host "  输入 A 禁用所有"
Write-Host "  输入 N 取消"
$input = Read-Host "选择"

$toDisable = @()
if ($input -eq "A" -or $input -eq "a") {
    $toDisable = $startupItems
} elseif ($input -eq "N" -or $input -eq "n") {
    Write-Host "  操作已取消。" -ForegroundColor Gray
    Write-Host "============================================" -ForegroundColor Cyan
    return
} else {
    # 统一解析 "1,3,5" 形式的选择器
    $toDisable = @(Select-StartupItems -Items $startupItems -Selector $input)
}

if ($toDisable.Count -eq 0) {
    Write-Host "  未选择任何项。" -ForegroundColor Gray
    Write-Host "============================================" -ForegroundColor Cyan
    return
}

# --- 备份 + 执行禁用（统一走共享库，与 GUI / WebUI 同逻辑、同备份格式）---
$backupDir = Join-Path (Split-Path -Parent $PSScriptRoot) "backups"

Write-Host "`n正在禁用启动项..." -ForegroundColor Yellow
$res = Disable-StartupItems -BackupDir $backupDir -Items $toDisable
$backupFile = $res.backup
Write-Host "`n  备份已保存: $backupFile" -ForegroundColor Green

$disabledCount = $res.disabled
$failedCount   = $res.failed
foreach ($d in $res.details) {
    if ($d.Result -like "已禁用*") {
        Write-Host "  [已禁用] $($d.Name) — $($d.Result)" -ForegroundColor Green
    } elseif ($d.Result -like "跳过*") {
        Write-Host "  [跳过] $($d.Name) — $($d.Result)" -ForegroundColor Yellow
    } else {
        Write-Host "  [失败] $($d.Name) — $($d.Result)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  启动项优化完成！" -ForegroundColor Green
Write-Host "  已禁用: $disabledCount 项" -ForegroundColor Green
Write-Host "  失败  : $failedCount 项" -ForegroundColor $(if ($failedCount -gt 0) { "Yellow" } else { "Gray" })
Write-Host "  备份文件: $backupFile" -ForegroundColor Gray
Write-Host "  注意: 部分启动项可能需要通过任务管理器->启动 选项卡禁用" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan

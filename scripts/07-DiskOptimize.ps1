<#
.SYNOPSIS
    磁盘优化模块 — 磁盘清理与碎片整理/SSD优化
.DESCRIPTION
    - 检测磁盘类型 (SSD/HDD)
    - SSD: 执行 TRIM 优化
    - HDD: 执行碎片整理
    - 清理系统组件 (WinSxS)
    - 压缩系统文件（默认关闭，需显式 -CompactOS）
    注意：本脚本不使用 Storage 模块 (Get-Volume/Get-PhysicalDisk/Optimize-Volume)，
          改用 WMI + defrag.exe + fsutil，以兼容 Storage 模块损坏的环境。
#>

param(
    # 压缩系统文件（CompactOS）默认关闭：耗时长、且回滚要再跑一次 Compact.exe /CompactOS:never。
    # 需要时显式加 -CompactOS；也可把 config/optimization.json 的 disk.compact_os_default 设为 true。
    # 与 GUI / WebUI 的默认值统一走 Get-CompactOSDefault（见 HANDOFF §7.1）。
    [switch]$CompactOS
)

# 复用共享核心库（磁盘统一实现，与 GUI / WebUI 同源）
# 统一走 WMI + defrag.exe + fsutil，不使用 Storage 模块，保证 Win7 兼容。
# 注：本文件原先就地定义了 Get-PhysicalDisksCompat / Get-FixedVolumesCompat，
# 现改为调用共享库，避免三份实现各自漂移。
$coreLib = Join-Path $PSScriptRoot "..\lib\Optimize.Core.ps1"
if (Test-Path $coreLib) { . $coreLib }
if (-not (Get-Command Invoke-DiskOptimization -ErrorAction SilentlyContinue)) {
    Write-Host "错误：未找到共享核心库 lib\Optimize.Core.ps1，无法执行磁盘优化。" -ForegroundColor Red
    return
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "         磁盘优化" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# --- 获取磁盘信息 ---
Write-Host "`n[1/3] 检测磁盘信息..." -ForegroundColor Yellow

$physicalDisks = @(Get-PhysicalDiskInfo)
$volumes = @(Get-FixedVolumeList)

# 盘符 -> 介质类型映射（共享库：逻辑盘 → 分区 → 物理盘，Win7 可用）
$driveMediaMap = Get-DriveMediaMap

Write-Host ""
Write-Host "  物理磁盘:" -ForegroundColor Gray
foreach ($disk in $physicalDisks) {
    $sizeGB = if ($disk.Size) { [math]::Round($disk.Size / 1GB, 0) } else { 0 }
    Write-Host "    磁盘$($disk.DeviceId): $($disk.FriendlyName) | $($disk.MediaType) | ${sizeGB}GB"
}

Write-Host ""
Write-Host "  逻辑卷:" -ForegroundColor Gray
foreach ($vol in $volumes) {
    $totalGB = if ($vol.Size) { [math]::Round($vol.Size / 1GB, 1) } else { 0 }
    $freeGB  = if ($vol.SizeRemaining) { [math]::Round($vol.SizeRemaining / 1GB, 1) } else { 0 }
    $usage   = if ($vol.Size -gt 0) { [math]::Round((1 - $vol.SizeRemaining / $vol.Size) * 100, 1) } else { 0 }
    Write-Host "    $($vol.DriveLetter): ${totalGB}GB 总计 | ${freeGB}GB 可用 | 已用 ${usage}%"
}

# --- 系统组件清理 ---
Write-Host "`n[2/3] 系统组件清理..." -ForegroundColor Yellow

Write-Host "  [处理] 分析 WinSxS 组件存储..." -ForegroundColor Yellow
try {
    Dism.exe /Online /Cleanup-Image /AnalyzeComponentStore 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
} catch {
    Write-Host "  [跳过] WinSxS 分析失败" -ForegroundColor Gray
}
Write-Host "  [完成] $(Invoke-WinSxSCleanup)" -ForegroundColor Green

# 压缩系统文件 (释放更多空间) —— 显式开关、默认关闭，与 GUI / WebUI 行为一致
$compactEnabled = if ($CompactOS) { $true } else { Get-CompactOSDefault }
Write-Host "`n  [处理] 压缩系统文件..." -ForegroundColor Yellow
if ($compactEnabled) {
    Write-Host "  [完成] $(Set-CompactOSState -Enable)" -ForegroundColor Green
} else {
    Write-Host "  [跳过] 默认关闭；如需压缩请执行: .\scripts\07-DiskOptimize.ps1 -CompactOS" -ForegroundColor Gray
}

# --- 磁盘优化/TRIM ---
Write-Host "`n[3/3] 磁盘优化..." -ForegroundColor Yellow

# 逐卷判定介质后择优优化：SSD→TRIM，HDD→碎片整理。
# 此前"未知一律按 HDD 处理"会对 SSD 执行碎片整理（无谓写入、损耗寿命）；
# 现改用共享库的多级判定：WMI 显式 SSD → defrag /A 分析 → fsutil → 兜底 HDD。
foreach ($vol in $volumes) {
    $mediaType = Get-VolumeMediaType -DriveLetter $vol.DriveLetter -MediaMap $driveMediaMap
    Write-Host ""
    Write-Host "  处理驱动器 $($vol.DriveLetter): ($mediaType)..." -ForegroundColor Yellow
    $r = Invoke-VolumeOptimization -DriveLetter $vol.DriveLetter -MediaType $mediaType -Trim -Defrag
    Write-Host "  [完成] $($r.drive) $($r.action)" -ForegroundColor Green
    if ($r.note) { Write-Host "         $($r.note)" -ForegroundColor Gray }
}

# --- 显示优化后磁盘状态 ---
Write-Host "`n优化后磁盘状态:" -ForegroundColor Yellow
$updatedVolumes = @(Get-FixedVolumeList)
foreach ($vol in $updatedVolumes) {
    $totalGB = if ($vol.Size) { [math]::Round($vol.Size / 1GB, 1) } else { 0 }
    $freeGB  = if ($vol.SizeRemaining) { [math]::Round($vol.SizeRemaining / 1GB, 1) } else { 0 }
    Write-Host "  $($vol.DriveLetter): ${totalGB}GB 总计 | ${freeGB}GB 可用"
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  磁盘优化完成！" -ForegroundColor Green
Write-Host "  SSD 已执行 TRIM | HDD 已执行碎片整理" -ForegroundColor Gray
if ($compactEnabled) {
    Write-Host "  系统组件已清理并压缩" -ForegroundColor Gray
} else {
    Write-Host "  系统组件已清理（未压缩系统文件）" -ForegroundColor Gray
}
Write-Host "============================================" -ForegroundColor Cyan

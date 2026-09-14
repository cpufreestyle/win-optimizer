<#
.SYNOPSIS
    视觉效果优化模块 — 降低视觉特效，提升系统响应速度
.DESCRIPTION
    针对 7代及更老 CPU/集显的电脑，关闭不必要的视觉效果：
    - 设置为"最佳性能"模式
    - 保留基本字体平滑（避免文字难看）
    - 禁用透明效果
    - 禁用动画控件
    - 调整菜单显示延迟
    所有更改会备份，可随时恢复。
#>

# 复用共享核心库（视觉效果统一实现，与 GUI / WebUI 同源）
$coreLib = Join-Path $PSScriptRoot "..\lib\Optimize.Core.ps1"
if (Test-Path $coreLib) { . $coreLib }
if (-not (Get-Command Set-VisualEffectProfile -ErrorAction SilentlyContinue)) {
    Write-Host "错误：未找到共享核心库 lib\Optimize.Core.ps1，无法应用视觉效果。" -ForegroundColor Red
    return
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "         视觉效果优化" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# --- 备份当前设置（统一走共享库）---
$backupDir = Join-Path (Split-Path -Parent $PSScriptRoot) "backups"

Write-Host "`n[1/3] 备份当前视觉效果设置..." -ForegroundColor Yellow
$backupFile = Backup-VisualEffects -BackupDir $backupDir
Write-Host "  备份已保存: $backupFile" -ForegroundColor Green

# --- 显示选项 ---
Write-Host "`n[2/3] 选择优化级别:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  [1] 最佳性能 (推荐老电脑) — 关闭所有特效，仅保留字体平滑"
Write-Host "  [2] 平衡模式 — 关闭大部分特效，保留基本动画"
Write-Host "  [3] 自定义 — 逐项选择"
Write-Host "  [N] 取消"
$choice = Read-Host "选择 (1/2/3/N)"

if ($choice -eq "N" -or $choice -eq "n") {
    Write-Host "  操作已取消。" -ForegroundColor Gray
    Write-Host "============================================" -ForegroundColor Cyan
    return
}

if ($choice -notmatch "^[123]$") {
    Write-Host "  无效选择，操作取消。" -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Cyan
    return
}

Write-Host "`n[3/3] 正在应用视觉效果设置..." -ForegroundColor Yellow

# 自定义模式：逐项选择（清单由共享库提供）
$toggles = $null
if ($choice -eq "3") {
    $options = Get-VisualEffectToggles
    Write-Host ""
    for ($i = 0; $i -lt $options.Count; $i++) {
        Write-Host "  [$($i+1)] $($options[$i].Name)"
    }
    Write-Host "  输入序号(逗号分隔)选择要应用的项, 或 A 全部应用"
    $sel = Read-Host "选择"

    $selected = @()
    if ($sel -eq "A" -or $sel -eq "a") {
        $selected = $options
    } else {
        $indices = $sel -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^\d+$" }
        foreach ($idx in $indices) {
            $i = [int]$idx - 1
            if ($i -ge 0 -and $i -lt $options.Count) { $selected += $options[$i] }
        }
    }
    $toggles = @($selected | ForEach-Object { $_.Key })
}

# 统一走共享库（与 GUI / WebUI 同一份实现）
$r = Set-VisualEffectProfile -Profile ([int]$choice) -Toggles $toggles -BackupDir $backupDir -SkipExplorerRestart
foreach ($d in $r.details) { Write-Host "  [完成] $d" -ForegroundColor Green }
if (-not $r.ok) { Write-Host "  部分设置写入失败（可能需要管理员权限），详见 optimize.log" -ForegroundColor Yellow }

# 刷新资源管理器以应用更改
Write-Host "`n正在刷新系统设置..." -ForegroundColor Yellow
if (Restart-Explorer) {
    Write-Host "  资源管理器已重启" -ForegroundColor Green
} else {
    Write-Host "  请手动重启资源管理器或重启电脑" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  视觉效果优化完成！" -ForegroundColor Green
Write-Host "  备份文件: $backupFile" -ForegroundColor Gray
Write-Host "  如需恢复，请使用 [B] 备份恢复功能" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan

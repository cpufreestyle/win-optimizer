<#
.SYNOPSIS
    系统体检（只读）— 生成体检报告并与上一次对比
.DESCRIPTION
    只读扫描服务 / 启动项 / 视觉 / 电源 / 磁盘 / 网络 六个方面，输出：
      - 体检分（0-100）与等级
      - 关键指标（内存、启动项数、自动启动服务数、可清理空间、分区占用等）
      - 问题清单（按 High/Medium/Low 分级，附建议）
    报告以 JSON 存于 backups\health\，并与上一次体检对比，
    展示分数变化、已解决问题、新增问题与关键指标差值。

    重要：本脚本全程只读，不修改任何系统设置。
#>

# 复用共享核心库（体检引擎的统一实现）
$coreLib = Join-Path $PSScriptRoot "..\lib\Optimize.Core.ps1"
if (Test-Path $coreLib) { . $coreLib }
if (-not (Get-Command Get-SystemHealthReport -ErrorAction SilentlyContinue)) {
    Write-Host "错误：未找到共享核心库 lib\Optimize.Core.ps1，无法执行体检。" -ForegroundColor Red
    return
}

$backupDir = Join-Path (Split-Path -Parent $PSScriptRoot) "backups"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "         系统体检（只读）" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  本功能只读取系统状态，不做任何修改。" -ForegroundColor DarkGray

# 在保存本次报告之前，先取上一次的报告，用于对比
$prev = Get-PreviousHealthReport -BackupDir $backupDir

Write-Host "`n正在扫描（统计可清理空间可能需要十几秒）..." -ForegroundColor Yellow
$report = Get-SystemHealthReport

# --- 体检分 ---
$scoreColor = if ($report.score -ge 90) { "Green" }
              elseif ($report.score -ge 75) { "Cyan" }
              elseif ($report.score -ge 60) { "Yellow" }
              else { "Red" }

Write-Host ""
Write-Host "  体检时间 : $($report.timestamp)" -ForegroundColor Gray
Write-Host "  体检得分 : " -NoNewline -ForegroundColor Gray
Write-Host "$($report.score) / 100  （$($report.grade)）" -ForegroundColor $scoreColor

# --- 关键指标 ---
$m = $report.metrics
Write-Host "`n  [关键指标]" -ForegroundColor Yellow
Write-Host ("    内存         : 可用 {0}MB / 共 {1}MB（{2}%）" -f $m.freeRamMB, $m.totalRamMB, $m.freeRamPct)
Write-Host ("    启动项       : {0} 项" -f $m.startupCount)
Write-Host ("    自动启动服务 : {0} / {1}（可优化）" -f $m.servicesStillAuto, $m.optimizableServices)
Write-Host ("    视觉特效     : 未关闭 {0} / {1}" -f $m.visualTogglesLeft, $m.visualTogglesTotal)
Write-Host ("    电源计划     : {0}" -f $m.powerPlanTitle)
if ($null -ne $m.cleanableMB) {
    Write-Host ("    可清理空间   : {0} MB" -f $m.cleanableMB)
}
Write-Host ("    活动网卡     : {0} 个" -f $m.activeAdapters)
foreach ($d in @($m.volumes)) {
    Write-Host ("    分区 {0}:      : 可用 {1}GB / 共 {2}GB（已用 {3}%）[{4}]" -f $d.drive, $d.freeGB, $d.totalGB, $d.usedPct, $d.media)
}

# --- 问题清单 ---
Write-Host "`n  [问题清单]" -ForegroundColor Yellow
if (@($report.issues).Count -eq 0) {
    Write-Host "    未发现明显问题，系统状态良好。" -ForegroundColor Green
} else {
    $order = @{ 'High' = 0; 'Medium' = 1; 'Low' = 2 }
    foreach ($i in ($report.issues | Sort-Object { $order[$_.severity] })) {
        $c = switch ($i.severity) { 'High' { 'Red' } 'Medium' { 'Yellow' } default { 'Gray' } }
        Write-Host ("    [{0}] {1}" -f $i.severity, $i.title) -ForegroundColor $c
        Write-Host ("         {0}" -f $i.detail) -ForegroundColor DarkGray
        Write-Host ("         建议: {0}" -f $i.suggestion) -ForegroundColor DarkGray
    }
}

# --- 保存本次报告 ---
$file = Save-HealthReport -Report $report -BackupDir $backupDir
Write-Host "`n  报告已保存: $file" -ForegroundColor Green

# --- 与上一次体检对比 ---
if (-not $prev) {
    Write-Host "  这是首次体检，暂无历史报告。优化后再跑一次即可看到前后变化。" -ForegroundColor Gray
} else {
    $cmp = Compare-HealthReports -Before $prev -After $report
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  与上一次体检对比" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ("  上次: {0} 分  ({1})" -f $cmp.beforeScore, $cmp.beforeTime) -ForegroundColor Gray
    Write-Host ("  本次: {0} 分  ({1})" -f $cmp.afterScore, $cmp.afterTime) -ForegroundColor Gray

    $sign = if ($cmp.scoreDelta -gt 0) { "+$($cmp.scoreDelta)" } else { "$($cmp.scoreDelta)" }
    $dc   = if ($cmp.scoreDelta -gt 0) { "Green" } elseif ($cmp.scoreDelta -lt 0) { "Red" } else { "Gray" }
    Write-Host ("  分数变化: {0}" -f $sign) -ForegroundColor $dc

    if (@($cmp.resolved).Count -gt 0) {
        Write-Host "`n  [已解决]" -ForegroundColor Green
        foreach ($i in $cmp.resolved) { Write-Host ("    + {0}" -f $i.title) -ForegroundColor Green }
    }
    if (@($cmp.new).Count -gt 0) {
        Write-Host "`n  [新增问题]" -ForegroundColor Red
        foreach ($i in $cmp.new) { Write-Host ("    - {0}" -f $i.title) -ForegroundColor Red }
    }
    if (@($cmp.resolved).Count -eq 0 -and @($cmp.new).Count -eq 0) {
        Write-Host "`n  问题清单无变化。" -ForegroundColor Gray
    }
    if (@($cmp.metricDeltas).Count -gt 0) {
        Write-Host "`n  [指标变化]" -ForegroundColor Yellow
        foreach ($d in $cmp.metricDeltas) {
            $ds = if ($d.delta -gt 0) { "+$($d.delta)" } else { "$($d.delta)" }
            Write-Host ("    {0}: {1} -> {2}  ({3})" -f $d.metric, $d.before, $d.after, $ds)
        }
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan

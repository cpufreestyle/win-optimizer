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

    重要：扫描过程全程只读。报告之后会给出『自动修复预览』清单，
    仅在输入 Y 确认后调用 lib 的 Invoke-HealthRemediation 执行修复，
    每步执行前自动备份；High 级高危项不在自动修复范围内。
#>
param(
    [switch]$InstallSchedule,    # 注册每日自动体检计划任务后退出（不执行体检）
    [switch]$UninstallSchedule,  # 删除计划任务后退出
    [switch]$Trend,              # 只打印体检趋势（字符 sparkline），不执行体检
    [string]$Time = '09:00',     # -InstallSchedule 的每日触发时间（HH:mm）
    [switch]$Export,            # 体检后导出前后对比报告（默认输出到桌面）
    [ValidateSet('Html', 'Markdown')][string]$Format = 'Html',  # 导出格式
    [string]$From,             # 对比起点：体检报告 JSON 路径（默认取上一次体检）
    [string]$To,               # 对比终点：体检报告 JSON 路径（默认取本次体检）
    [switch]$RestorePoint,        # 修复前先建系统还原点；省略时取 config 的 safety.create_restore_point
    [int]$TrendDays = 30         # -Trend 回溯天数
)

# 复用共享核心库（体检引擎的统一实现）
$coreLib = Join-Path $PSScriptRoot "..\lib\Optimize.Core.ps1"
if (Test-Path $coreLib) { . $coreLib }
if (-not (Get-Command Get-SystemHealthReport -ErrorAction SilentlyContinue)) {
    Write-Host "错误：未找到共享核心库 lib\Optimize.Core.ps1，无法执行体检。" -ForegroundColor Red
    return
}

$backupDir = Join-Path (Split-Path -Parent $PSScriptRoot) "backups"

# --- 子命令：计划任务注册/删除、只看趋势（不进入体检流程）---
function Show-HealthTrend {
    param([int]$Days)
    $trend = @(Get-HealthTrend -BackupDir $backupDir -Days $Days)
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  体检趋势（近 $Days 天）" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    if ($trend.Count -eq 0) {
        Write-Host "  暂无历史体检报告。多跑几次体检后即可看到趋势。" -ForegroundColor Gray
        return
    }
    $scores   = [double[]]@($trend | ForEach-Object { [double]$_.score })
    $minScore = ($scores | Measure-Object -Minimum).Minimum
    $maxScore = ($scores | Measure-Object -Maximum).Maximum
    Write-Host ("  分数: {0}   （{1} ~ {2} 分，共 {3} 次）" -f (Format-Sparkline -Values $scores), $minScore, $maxScore, $trend.Count) -ForegroundColor Green
    Write-Host ("  区间: {0:MM-dd} → {1:MM-dd}" -f $trend[0].time, $trend[-1].time) -ForegroundColor Gray
    Write-Host ""
    Write-Host "  最近记录（日期时间 / 分数 / 内存可用% / 可清理MB / 启动项 / 问题数）:" -ForegroundColor Yellow
    foreach ($p in @($trend | Select-Object -Last 10)) {
        Write-Host ("    {0:MM-dd HH:mm}  {1,3}  {2,7}%  {3,9}  {4,5}  {5}" -f `
            $p.time, $p.score, $p.freeRamPct, $p.cleanableMB, $p.startupCount, $p.issueCount)
    }
}

if ($UninstallSchedule) {
    $ru = Remove-HealthSchedule
    if ($ru.ok -and $ru.removed) { Write-Host "`n  已删除计划任务: $($ru.task)" -ForegroundColor Green }
    elseif ($ru.ok)              { Write-Host "`n  计划任务不存在，无需删除: $($ru.task)" -ForegroundColor Gray }
    else                         { Write-Host "`n  删除失败: $($ru.error)" -ForegroundColor Red }
    return
}

if ($InstallSchedule) {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  注册每日自动体检计划任务" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    $ri = Install-HealthSchedule -Time $Time -HealthScript $PSCommandPath
    if ($ri.ok) {
        Write-Host "  已注册: $($ri.task)（触发: $($ri.trigger)）" -ForegroundColor Green
        Write-Host "  任务内容: powershell -NoProfile -ExecutionPolicy Bypass -File \`"$PSCommandPath\`"" -ForegroundColor DarkGray
        if ($ri.warning) { Write-Host "  注意: $($ri.warning)" -ForegroundColor Yellow }
    } else {
        Write-Host "  注册失败: $($ri.error)" -ForegroundColor Red
    }
    return
}

if ($Trend) {
    Show-HealthTrend -Days $TrendDays
    return
}

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

# --- 智能降级建议（P2）：不只说「哪里有问题」，还指出「先动哪个最划算」---
# 复用本次报告里已经量好的体积，不重复扫盘；三端结论与文案同源。
$tipLines = @(Format-SmartRecommendations (Get-SmartRecommendations -Report $report -Top 3))
if ($tipLines.Count -gt 0) {
    Write-Host "`n  [智能建议]" -ForegroundColor Cyan
    foreach ($tipLine in $tipLines) { Write-Host $tipLine -ForegroundColor DarkGray }
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

# 导出报告（P1-2）：自包含单文件，方便发帖求助、留存优化前后证据
$wantExport = $Export
if (-not $wantExport -and $prev -and [Environment]::UserInteractive) {
    $ans = Read-Host '  是否导出前后对比报告到桌面? (Y/N)'
    $wantExport = ($ans -match '^[Yy]')
}
if ($wantExport) {
    $expArgs = @{ Format = $Format }
    if ($From) { $expArgs['From'] = $From } elseif ($prev)   { $expArgs['From'] = $prev }
    if ($To)   { $expArgs['To']   = $To }   elseif ($report) { $expArgs['To']   = $report }
    if ((-not $expArgs.ContainsKey('From')) -or (-not $expArgs.ContainsKey('To'))) {
        $expArgs['BackupDir'] = $backupDir
    }
    $exp = Export-HealthReport @expArgs
    if ($exp.ok) {
        Write-Host ('  对比报告已导出: ' + $exp.file) -ForegroundColor Green
    } else {
        Write-Host ('  导出失败: ' + $exp.error) -ForegroundColor Yellow
    }
}


# --- 体检趋势（字符 sparkline，与 GUI/WebUI 同源）---
$trendPoints = @(Get-HealthTrend -BackupDir $backupDir)
if ($trendPoints.Count -ge 2) {
    $spark = Format-Sparkline -Values ([double[]]@($trendPoints | ForEach-Object { [double]$_.score }))
    Write-Host ("`n  近期分数趋势: {0}  （共 {1} 次体检，{2} → {3} 分）" -f `
        $spark, $trendPoints.Count, $trendPoints[0].score, $trendPoints[-1].score) -ForegroundColor Cyan
    Write-Host "  查看详细趋势: powershell -File scripts\15-HealthCheck.ps1 -Trend" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
# --- 自动修复（只读先行：先出「将做什么」清单，确认后才执行）---
$remediationPlan = @(Get-HealthRemediationPlan -Report $report -SkipCleanScan)
$actionable = @($remediationPlan | Where-Object { $_.auto })

if ($actionable.Count -gt 0) {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  自动修复预览" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  以下问题可以一键修复（每步执行前会自动备份）:" -ForegroundColor DarkGray
    $n = 0
    foreach ($p in $actionable) {
        $n++
        $c = switch ($p.severity) { 'High' { 'Red' } 'Medium' { 'Yellow' } default { 'Gray' } }
        Write-Host ("    {0}. [{1}] {2}" -f $n, $p.severity, $p.title) -ForegroundColor $c
        Write-Host ("       动作  : {0} -> {1}" -f $p.action, $p.target) -ForegroundColor DarkGray
        Write-Host ("       影响  : {0}" -f $p.impact) -ForegroundColor DarkGray
    }
    $adviceOnly = @($remediationPlan | Where-Object { -not $_.auto })
    if ($adviceOnly.Count -gt 0) {
        Write-Host ""
        Write-Host "  以下问题只给建议，不会自动执行:" -ForegroundColor Gray
        foreach ($p in $adviceOnly) {
            Write-Host ("    - [{0}] {1}（{2}）" -f $p.severity, $p.title, $p.target) -ForegroundColor Gray
        }
    }

    $answer = ''
    if ([Environment]::UserInteractive) {
        $answer = Read-Host "`n  是否一键修复以上项目？输入 Y 确认，其它键跳过"
    } else {
        Write-Host "`n  非交互环境（如计划任务自动运行），已跳过自动修复。" -ForegroundColor Gray
    }
    if ($answer -eq 'Y' -or $answer -eq 'y') {
        Write-Host "`n  开始自动修复（High 级高危项不在本流程内）..." -ForegroundColor Yellow
        $rpOn = if ($RestorePoint) { $true } else { Get-RestorePointDefault }
        if ($rpOn) {
            if (-not (Test-IsAdmin)) {
                Write-Host "  [提示] 创建系统还原点需要管理员权限，本次将跳过。" -ForegroundColor Yellow
            } elseif (-not (Test-SystemRestoreEnabled)) {
                Write-Host "  [提示] 系统还原已关闭，跳过还原点。" -ForegroundColor Yellow
            }
        }
        $rr = Invoke-HealthRemediation -Report $report -MaxSeverity 'Medium' -BackupDir $backupDir `
                                       -SkipCleanScan -SkipExplorerRestart -CreateRestorePoint:$rpOn
        if ($rr.restorePoint) {
            if ($rr.restorePoint.ok) {
                Write-Host "  [还原点] 已创建: $($rr.restorePoint.name) ($($rr.restorePoint.method))" -ForegroundColor Green
            } else {
                Write-Host "  [还原点] 创建失败，继续修复: $($rr.restorePoint.error)" -ForegroundColor Yellow
            }
        }
        Write-Host ""
        foreach ($s in @($rr.results)) {
            $mark = if ($s.ok) { '[成功]' } else { '[失败]' }
            $color = if ($s.ok) { 'Green' } else { 'Red' }
            Write-Host ("    {0} {1} ({2}) {3}" -f $mark, $s.id, $s.domain, $s.summary) -ForegroundColor $color
            if ($s.backup) { Write-Host ("           备份: {0}" -f $s.backup) -ForegroundColor DarkGray }
            if ($s.error)  { Write-Host ("           错误: {0}" -f $s.error) -ForegroundColor DarkGray }
        }
        foreach ($s in @($rr.skipped)) {
            Write-Host ("    [跳过] {0} —— {1}" -f $s.id, $s.reason) -ForegroundColor Gray
        }
        Write-Host ""
        if ($rr.ok) {
            Write-Host "  修复完成。若切换了视觉效果，重启资源管理器后生效。" -ForegroundColor Green
            Write-Host "  建议重新运行一次体检查看前后对比。" -ForegroundColor Green
        } else {
            Write-Host "  部分项目修复失败，详见上方错误信息。" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  已跳过自动修复。" -ForegroundColor Gray
    }
}

# --- 定时体检（仅交互环境提示；计划任务自动运行时跳过）---
if ([Environment]::UserInteractive) {
    Write-Host ""
    $ansSchedule = Read-Host "  是否注册每日自动体检计划任务？输入 Y 注册（管理员=每日 09:00，非管理员=登录时），其它键跳过"
    if ($ansSchedule -eq 'Y' -or $ansSchedule -eq 'y') {
        $ri = Install-HealthSchedule -Time '09:00' -HealthScript $PSCommandPath
        if ($ri.ok) {
            Write-Host "  已注册: $($ri.task)（触发: $($ri.trigger)）" -ForegroundColor Green
            if ($ri.warning) { Write-Host "  注意: $($ri.warning)" -ForegroundColor Yellow }
        } else {
            Write-Host "  注册失败: $($ri.error)" -ForegroundColor Red
        }
    }
}

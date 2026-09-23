<#
.SYNOPSIS
    备份与恢复 — 优化时间线 / 一键回滚 / 按备份恢复
.DESCRIPTION
    - 优化时间线：聚合 backups 下的备份元数据，按时间倒序展示「到底改过什么」
    - 一键回滚：按固定顺序（服务→启动项→视觉→电源→网络→遥测→更新）还原，
      还原前先把当前状态再备份一遍（后悔药）
    - 按备份恢复：只恢复选中的某一份备份（单域）
    所有还原逻辑统一走 lib/Optimize.Core.ps1，CLI / GUI / WebUI 三端零漂移。
.NOTES
    旧备份没有 manifest 元数据时同样可用：按文件名推断域、按文件时间排序，
    并在时间线中标注「元数据缺失」。
#>

# --- 加载共享函数库（时间线 / 回滚 / 各域还原均为 lib 单一实现）---
$coreLib = Join-Path $PSScriptRoot "..\lib\Optimize.Core.ps1"
if (Test-Path $coreLib) { . $coreLib }
if (-not (Get-Command Get-OptimizationTimeline -ErrorAction SilentlyContinue)) {
    Write-Host "错误：未找到共享核心库 lib\Optimize.Core.ps1，无法执行备份恢复。" -ForegroundColor Red
    return
}

$backupDir = Join-Path (Split-Path -Parent $PSScriptRoot) "backups"
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }

# 回滚涉及的域（与 lib 的固定顺序一致）
$rollbackDomains = @('services', 'startup', 'visual', 'power', 'network', 'telemetry', 'update')

# --- 内部：渲染单个域的还原结果 ---
function Show-RestoreReport {
    param([string]$Label, $Result)
    if (-not $Result) { Write-Host "    [失败] $Label : 未返回结果" -ForegroundColor Red; return }
    foreach ($d in @($Result.details)) {
        if ($d -is [string]) {
            Write-Host "    $d" -ForegroundColor DarkGray
        } else {
            $text = [string]$d.result
            $color = 'Green'
            if ($text -like '失败*') { $color = 'Red' }
            elseif ($text -like '跳过*' -or $text -like '已存在*' -or $text -like '已处于*') { $color = 'Gray' }
            Write-Host ("    {0} : {1}" -f $d.name, $text) -ForegroundColor $color
        }
    }
    if ($Result.error) {
        Write-Host "    [失败] $Label : $($Result.error)" -ForegroundColor Red
    } else {
        Write-Host ("    [完成] {0}（还原 {1} 项）" -f $Label, $Result.restored) -ForegroundColor Green
    }
}

# --- 内部：渲染一键回滚结果 ---
function Show-RollbackReport {
    param($Result)
    if (-not $Result) { Write-Host "  回滚未返回结果。" -ForegroundColor Red; return }
    if (-not $Result.ok -and @($Result.results).Count -eq 0) {
        Write-Host "  [失败] $($Result.error)" -ForegroundColor Red
        return
    }
    Write-Host ""
    Write-Host ("  回滚方式 : {0}" -f $(if ($Result.mode -eq 'file') { '单个备份' } else { '回到时间点' })) -ForegroundColor Cyan
    Write-Host ("  目标时点 : {0}" -f $Result.since) -ForegroundColor Cyan
    foreach ($s in @($Result.results)) {
        $mark  = if ($s.ok) { '[成功]' } else { '[失败]' }
        $color = if ($s.ok) { 'Green' } else { 'Red' }
        Write-Host ("  {0} {1} ← {2}" -f $mark, $s.domainLabel, $s.file) -ForegroundColor $color
        if ($s.summary)     { Write-Host "        $($s.summary)" -ForegroundColor DarkGray }
        if ($s.safetyBackup){ Write-Host "        回滚前已备份当前状态: $(Split-Path -Leaf $s.safetyBackup)" -ForegroundColor DarkGray }
        if ($s.error)       { Write-Host "        错误: $($s.error)" -ForegroundColor Red }
    }
    foreach ($s in @($Result.skipped)) {
        Write-Host ("  [跳过] {0} ← {1}：{2}" -f $s.domainLabel, $s.file, $s.reason) -ForegroundColor Gray
    }
    if (@($Result.safetyBackups).Count -gt 0) {
        Write-Host "  如需再次反悔，可从上面这些「当前状态备份」中恢复。" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "         备份与恢复（优化时间线）" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

$timeline = @(Get-OptimizationTimeline -BackupDir $backupDir -Max 60)

if ($timeline.Count -eq 0) {
    Write-Host ""
    Write-Host "  暂无备份文件。" -ForegroundColor Yellow
    Write-Host "  各优化步骤默认会自动备份，备份后即可在这里恢复或回滚。" -ForegroundColor Gray
    Write-Host "============================================" -ForegroundColor Cyan
    return
}

# --- 优化时间线 ---
Write-Host ""
Write-Host "  [优化时间线] 共 $($timeline.Count) 条（新 → 旧）" -ForegroundColor Yellow
$n = 0
foreach ($e in $timeline) {
    $n++
    $items = if ($e.metadataMissing) { '?' } else { "$($e.items)" }
    $flag  = if ($e.metadataMissing) { '  ← 元数据缺失（旧备份）' } else { '' }
    $color = if ($e.metadataMissing) { 'DarkGray' } else { 'Gray' }
    Write-Host ("    [{0,2}] {1}  {2}（{3} 项）{4}" -f $n, $e.timeText, $e.domainLabel, $items, $flag) -ForegroundColor $color
}

Write-Host ""
Write-Host "  [编号] 只恢复该条备份（单域，恢复前先备份当前状态）" -ForegroundColor DarkGray
Write-Host "  [A]    恢复所有类型（取每个域最近的备份）" -ForegroundColor DarkGray
Write-Host "  [Z]    一键回滚向导（回到某个时间点 / 回退最近 N 条）" -ForegroundColor DarkGray
if (Test-Path (Join-Path $backupDir 'startup_items')) {
    Write-Host "  [R]    恢复所有启动文件夹项" -ForegroundColor DarkGray
}
Write-Host "  [N]    取消" -ForegroundColor DarkGray
$input = (Read-Host "请选择").Trim()

if ($input -eq 'N' -or $input -eq 'n') {
    Write-Host "  已取消。" -ForegroundColor Gray
    Write-Host "============================================" -ForegroundColor Cyan
    return
}

if ($input -eq 'A' -or $input -eq 'a') {
    # 恢复所有类型 = 每个域取最近的一份备份；Invoke-Rollback 会先备份当前状态
    Write-Host ""
    Write-Host "  将从每个域最近的备份恢复（还原前先备份当前状态）..." -ForegroundColor Yellow
    $rb = Invoke-Rollback -BackupDir $backupDir
    Show-RollbackReport -Result $rb
}
elseif ($input -eq 'Z' -or $input -eq 'z') {
    # --- 一键回滚向导 ---
    Write-Host ""
    Write-Host "  [一键回滚向导]" -ForegroundColor Cyan
    Write-Host "    1) 回到指定时间点之前的状态"
    Write-Host "    2) 回退最近 N 条备份"
    $mode = (Read-Host "  选择方式 (1/2)").Trim()

    $rbArgs = @{ BackupDir = $backupDir }
    if ($mode -eq '1') {
        $t = (Read-Host "  时间点（格式 yyyy-MM-dd HH:mm）").Trim()
        $dt = [datetime]::MinValue
        if (-not [datetime]::TryParse($t, [ref]$dt)) {
            Write-Host "  时间格式无法识别，已取消。" -ForegroundColor Red
            Write-Host "============================================" -ForegroundColor Cyan
            return
        }
        $rbArgs['Since'] = $dt
    }
    elseif ($mode -eq '2') {
        $nStr = (Read-Host "  回退几条备份？").Trim()
        $cnt = 0
        if (-not [int]::TryParse($nStr, [ref]$cnt) -or $cnt -lt 1) {
            Write-Host "  数量无效，已取消。" -ForegroundColor Red
            Write-Host "============================================" -ForegroundColor Cyan
            return
        }
        $rbArgs['Last'] = $cnt
    }
    else {
        Write-Host "  已取消。" -ForegroundColor Gray
        Write-Host "============================================" -ForegroundColor Cyan
        return
    }

    # 只读先出清单，确认后才执行
    $planArgs = @{}
    foreach ($k in $rbArgs.Keys) { $planArgs[$k] = $rbArgs[$k] }
    $plan = Get-RollbackPlan @planArgs
    if (-not $plan.ok) {
        Write-Host "  $($plan.error)" -ForegroundColor Red
        Write-Host "============================================" -ForegroundColor Cyan
        return
    }

    Write-Host ""
    Write-Host "  [将回滚到] $($plan.since)" -ForegroundColor Yellow
    foreach ($e in @($plan.entries)) {
        $items = if ($e.metadataMissing) { '?' } else { "$($e.items)" }
        Write-Host ("    {0} ← {1}（{2} 项）" -f $e.domainLabel, $e.file, $items) -ForegroundColor Gray
    }
    Write-Host "  说明：每个域还原前会先把当前状态备份一遍，可再次反悔。" -ForegroundColor DarkGray
    $ans = Read-Host "  确认执行回滚？输入 Y 确认，其它键取消"
    if ($ans -ne 'Y' -and $ans -ne 'y') {
        Write-Host "  已取消。" -ForegroundColor Gray
        Write-Host "============================================" -ForegroundColor Cyan
        return
    }

    $rb = Invoke-Rollback @rbArgs
    Show-RollbackReport -Result $rb
}
elseif ($input -eq 'R' -or $input -eq 'r') {
    # 恢复启动文件夹项（此前被移动到 backups\startup_items）
    $startupItemDir = Join-Path $backupDir 'startup_items'
    $startupFolder  = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    if (-not (Test-Path $startupItemDir)) {
        Write-Host "  没有启动文件夹备份项。" -ForegroundColor Gray
    } else {
        foreach ($f in (Get-ChildItem -Path $startupItemDir -File)) {
            if (-not (Test-Path $startupFolder)) { New-Item -ItemType Directory -Path $startupFolder -Force | Out-Null }
            Move-Item -LiteralPath $f.FullName -Destination (Join-Path $startupFolder $f.Name) -Force -ErrorAction SilentlyContinue
            Write-Host "  [恢复] $($f.Name) -> 启动文件夹" -ForegroundColor Green
        }
    }
}
else {
    # 恢复指定的一条备份（单域）
    $idx = 0
    if (-not [int]::TryParse($input, [ref]$idx) -or $idx -lt 1 -or $idx -gt $timeline.Count) {
        Write-Host "  无效选择。" -ForegroundColor Red
        Write-Host "============================================" -ForegroundColor Cyan
        return
    }
    $e   = $timeline[$idx - 1]
    $dom = $e.domain
    if ($rollbackDomains -notcontains $dom) {
        Write-Host "  $($e.domainLabel) 不支持自动还原，请手动处理。" -ForegroundColor Yellow
        Write-Host "============================================" -ForegroundColor Cyan
        return
    }

    # 修改必备份：先备份当前状态，再还原（后悔药）
    $sb = Backup-DomainState -Domain $dom -BackupDir $backupDir
    if ($sb) { Write-Host "  已备份当前$($e.domainLabel)状态: $(Split-Path -Leaf $sb)" -ForegroundColor DarkGray }
    else     { Write-Host "  警告：无法备份当前$($e.domainLabel)状态。" -ForegroundColor Yellow }

    Write-Host "  正在恢复: $($e.file)" -ForegroundColor Yellow
    # 分发统一走 lib（与 GUI / WebUI 同一个入口）
    $r = Restore-DomainState -Domain $dom -File $e.path -BackupDir $backupDir
    Show-RestoreReport -Label $e.domainLabel -Result $r
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  操作完成！" -ForegroundColor Green
Write-Host "  建议重启电脑使所有更改生效" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan

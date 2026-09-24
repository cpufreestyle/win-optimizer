<#
.SYNOPSIS
    优化组合包（Profiles）— 按场景一键执行多域优化
.DESCRIPTION
    - 组合包清单来自 config/optimization.json 的 profiles（config 驱动，社区可直接贡献）；
      配置缺失时回退 lib 内置默认，三端永远有可用项。
    - 只读先行：先打印「将做什么」清单（域 / 动作 / 目标 / 预估影响 / 风险级别），确认后才执行。
    - 纯编排：每一步都调用已存在的域函数（服务/启动项/视觉/电源/网络/遥测/磁盘），
      不新增任何系统操作面，因此每个域执行前都会自动备份。
    - 风险闸门：high 级步骤（禁用全部启动项、磁盘优化含 CompactOS）需显式 -Force；
      low / medium 级步骤在选择组合包后即可执行。
    - 单步失败不中断（续跑），结束后汇总成功/失败/跳过。
.NOTES
    所有还原逻辑与时间线见 09-BackupRestore.ps1；组合包只负责「 forward 优化」。
#>

# --- 加载共享函数库（组合包计划与执行均为 lib 单一实现）---
$coreLib = Join-Path $PSScriptRoot "..\lib\Optimize.Core.ps1"
if (Test-Path $coreLib) { . $coreLib }
if (-not (Get-Command Get-Profiles -ErrorAction SilentlyContinue)) {
    Write-Host "错误：未找到共享核心库 lib\Optimize.Core.ps1，无法执行组合包。" -ForegroundColor Red
    return
}

$backupDir = Join-Path (Split-Path -Parent $PSScriptRoot) "backups"
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }

function Show-ProfilePlan {
    param($Plan)
    Write-Host ""
    Write-Host ("  组合包: {0}（{1}）" -f $Plan.title, $Plan.name) -ForegroundColor Cyan
    if ($Plan.desc) { Write-Host ("  说明  : {0}" -f $Plan.desc) -ForegroundColor DarkGray }
    Write-Host ""
    if (@($Plan.steps).Count -eq 0) {
        Write-Host "  该组合包没有任何步骤（所有域都设置为不改动）。" -ForegroundColor Yellow
        return
    }
    $n = 0
    foreach ($s in @($Plan.steps)) {
        $n++
        $risk = $(switch ($s.risk) {
            'high'   { '高' }
            'medium' { '中' }
            'low'    { '低' }
            default  { '无' }
        })
        $auto = if ($s.auto) { '' } else { '（需人工确认）' }
        Write-Host ("    [{0}] {1} - {2}" -f $n, $s.domain, $s.action) -ForegroundColor Gray
        Write-Host ("         目标: {0}" -f $s.target) -ForegroundColor DarkGray
        Write-Host ("         影响: {0}" -f $s.impact) -ForegroundColor DarkGray
        Write-Host ("         风险: {0}{1}" -f $risk, $auto) -ForegroundColor DarkGray
    }
}

function Show-ProfileResult {
    param($Result)
    if (-not $Result) { Write-Host "  组合包未返回结果。" -ForegroundColor Red; return }
    if (@($Result.results).Count -eq 0 -and @($Result.skipped).Count -eq 0) {
        Write-Host "  [失败] $($Result.error)" -ForegroundColor Red
        return
    }
    Write-Host ""
    foreach ($r in @($Result.results)) {
        $mark  = if ($r.ok) { '[成功]' } else { '[失败]' }
        $color = if ($r.ok) { 'Green' } else { 'Red' }
        Write-Host ("  {0} {1} - {2}" -f $mark, $r.domain, $r.action) -ForegroundColor $color
        if ($r.summary) { Write-Host "        $($r.summary)" -ForegroundColor DarkGray }
        if ($r.backup)  { Write-Host "        备份: $(Split-Path -Leaf $r.backup)" -ForegroundColor DarkGray }
        if ($r.error)   { Write-Host "        错误: $($r.error)" -ForegroundColor Red }
    }
    foreach ($s in @($Result.skipped)) {
        Write-Host ("  [跳过] {0} - {1}（{2}）" -f $s.domain, $s.action, $s.reason) -ForegroundColor Gray
    }
    $okCount = @($Result.results | Where-Object { $_.ok }).Count
    $failCount = @($Result.results | Where-Object { -not $_.ok }).Count
    Write-Host ("  合计: 成功 {0} 步，失败 {1} 步，跳过 {2} 步" -f $okCount, $failCount, @($Result.skipped).Count) -ForegroundColor $(if ($failCount -eq 0) { 'Green' } else { 'Yellow' })
    if ($Result.dryRun) { Write-Host "  （预演模式，未修改任何设置）" -ForegroundColor DarkGray }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "         优化组合包（Profiles）" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

$profiles = @(Get-Profiles)
if ($profiles.Count -eq 0) {
    Write-Host ""
    Write-Host "  未找到任何组合包（config 的 profiles 为空）。" -ForegroundColor Yellow
    Write-Host "============================================" -ForegroundColor Cyan
    return
}

Write-Host ""
Write-Host "  [可用组合包]" -ForegroundColor Yellow
$i = 0
foreach ($p in $profiles) {
    $i++
    $plan = Get-ProfilePlan -Name $p.name
    $stepCount = @($plan.steps).Count
    $highCount = @($plan.steps | Where-Object { $_.risk -eq 'high' }).Count
    $flag = if ($highCount -gt 0) { "  ← 含高风险步骤 $highCount 个" } else { '' }
    Write-Host ("    [{0}] {1}（{2} 步）{3}" -f $i, $p.title, $stepCount, $flag) -ForegroundColor Gray
    if ($p.desc) { Write-Host ("        {0}" -f $p.desc) -ForegroundColor DarkGray }
}
Write-Host ""
Write-Host "  [N] 取消" -ForegroundColor DarkGray
$input = (Read-Host "请选择组合包编号").Trim()

if ($input -eq 'N' -or $input -eq 'n') {
    Write-Host "  已取消。" -ForegroundColor Gray
    Write-Host "============================================" -ForegroundColor Cyan
    return
}

$idx = 0
if (-not [int]::TryParse($input, [ref]$idx) -or $idx -lt 1 -or $idx -gt $profiles.Count) {
    Write-Host "  无效选择。" -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Cyan
    return
}

$chosen = $profiles[$idx - 1]
$plan   = Get-ProfilePlan -Name $chosen.name
Show-ProfilePlan -Plan $plan

$needForce = @(@($plan.steps | Where-Object { $_.risk -eq 'high' }).Count -gt 0) -or
              @(@($plan.steps | Where-Object { -not $_.auto }).Count -gt 0)

Write-Host ""
Write-Host "  [1] 预演（只列将做什么，不修改任何设置）" -ForegroundColor DarkGray
Write-Host "  [2] 确认执行" -ForegroundColor DarkGray
Write-Host "  [N] 取消" -ForegroundColor DarkGray
$act = (Read-Host "请选择操作").Trim()

if ($act -eq '1') {
    $rbArgs = @{ Name = $chosen.name; BackupDir = $backupDir; WhatIf = $true }
    if ($needForce) { $rbArgs['Force'] = $true }
    $r = Invoke-Profile @rbArgs
    Show-ProfileResult -Result $r
    Write-Host "============================================" -ForegroundColor Cyan
    return
}
if ($act -ne '2') {
    Write-Host "  已取消。" -ForegroundColor Gray
    Write-Host "============================================" -ForegroundColor Cyan
    return
}

if ($needForce) {
    Write-Host ""
    Write-Host "  该组合包含高风险步骤（禁用全部启动项 / 磁盘优化），执行后需逐个确认效果。" -ForegroundColor Yellow
    $c = (Read-Host "  仍要执行？输入 Y 确认").Trim()
    if ($c -ne 'Y' -and $c -ne 'y') {
        Write-Host "  已取消。" -ForegroundColor Gray
        Write-Host "============================================" -ForegroundColor Cyan
        return
    }
}

$rbArgs = @{ Name = $chosen.name; BackupDir = $backupDir; Force = $true }
$r = Invoke-Profile @rbArgs
Show-ProfileResult -Result $r

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  操作完成！" -ForegroundColor Green
Write-Host "  建议重启电脑使所有更改生效" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan

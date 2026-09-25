<#
.SYNOPSIS
    WebUI 系统体检 — 只读扫描、修复预览、一键修复，返回 JSON
.DESCRIPTION
    -Action scan     : 执行只读体检，保存报告，与上一次对比后返回（附带修复预览）
    -Action plan     : 只返回「将做什么」修复清单，不执行任何修改
    -Action remediate: 执行自动修复（每步前自动备份）
        -IssueCode    只修指定 issue id；省略表示全部
        -MaxSeverity  允许自动执行的最高严重级别，默认 Medium
        -DnsOption    DNS 选项编号，默认 1 = Cloudflare
        -PowerPlanGuid 电源计划目标 GUID，默认高性能
        -WhatIf       只预览
        -Force        允许自动执行 High 级问题（需配合 -MaxSeverity High）
    -Action apply-tips: 按智能建议一键禁用启动项（每步前自动备份；清理类不自动执行）
        -Top             应用前 N 条建议，默认 3
        -WhatIf          只预览不执行
    -Action tips     : 只返回智能降级建议（最值得禁用的启动项 / 最值得清理的目录），不改动任何设置
    -Action export   : 将前后两次体检导出为自包含单文件（Html / Markdown）
        -Format       导出格式 html / md（Markdown），默认 html
        -From / -To  对比两端：体检报告 JSON 路径，省略时自动取历史最新两份
    逻辑复用共享库 lib/Optimize.Core.ps1，与 CLI / GUI 行为一致。
#>
param(
    [ValidateSet("scan", "plan", "remediate", "trend", "export", "tips", "apply-tips")]$Action = "scan",
    [string[]]$IssueCode = @(),
    [ValidateSet("High", "Medium", "Low")]$MaxSeverity = "Medium",
    [switch]$SkipBench,
    [int]$DnsOption = 1,
    [string]$PowerPlanGuid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c",
    [int]$Top = 3,
    [int]$Days = 30,
    [ValidateSet("html", "md", "Html", "Markdown")][string]$Format = "html",
    [string]$From = "",
    [string]$To = "",
    [switch]$WhatIf,
    [switch]$Force,
    # 修复前先建系统还原点（P1-3）；auto / true / false，默认 auto（取 config 的 safety.create_restore_point）。
    # 用字符串而不是 [bool]：这里通过 powershell -File 调用，[bool] 绑定不了“false”。
    [string]$CreateRestorePoint = "auto"
)


# 统一 stdout 为 UTF-8（让 Python subprocess.run 按 utf-8 解码时不乱码；与 OptimizeGUI 同款）
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
function Out-Json {
    param($obj)
    $obj | ConvertTo-Json -Depth 8 -Compress
}

$ErrorActionPreference = "Stop"
$backupDir = Join-Path $PSScriptRoot "..\..\backups"
$backupDir = [System.IO.Path]::GetFullPath($backupDir)

# 复用共享核心库（体检引擎与自动修复，与 CLI / GUI 同源）
$libPath = Join-Path $PSScriptRoot "..\..\lib\Optimize.Core.ps1"
if (Test-Path $libPath) { . $libPath }

try {
    if ($Action -eq "scan") {
        # 在保存本次报告之前先取上一次的，用于对比
        $prev = Get-PreviousHealthReport -BackupDir $backupDir

        $report = Get-SystemHealthReport -SkipBench:$SkipBench
        $file   = Save-HealthReport -Report $report -BackupDir $backupDir

        $cmp = $null
        if ($prev) { $cmp = Compare-HealthReports -Before $prev -After $report }

        # 修复预览：只读，保证三端文案一致
        $plan = @(Get-HealthRemediationPlan -Report $report -SkipCleanScan)

        Out-Json ([PSCustomObject]@{
            ok         = $true
            report     = $report
            comparison = $cmp
            file       = $file
            plan       = $plan
            tips       = (Get-SmartRecommendations -Report $report -Top 3)
            trend      = @(Get-HealthTrend -BackupDir $backupDir)
        })
    }
    elseif ($Action -eq "plan") {
        $plan = @(Get-HealthRemediationPlan -SkipCleanScan -DnsOption $DnsOption -PowerPlanGuid $PowerPlanGuid)
        Out-Json ([PSCustomObject]@{
            ok          = $true
            plan        = $plan
            actionable  = @($plan | Where-Object { $_.auto }).Count
            adviceOnly  = @($plan | Where-Object { -not $_.auto }).Count
        })
    }
    elseif ($Action -eq "remediate") {
        if ($IssueCode -and $IssueCode.Count -gt 0) {
            $r = Invoke-HealthRemediation -IssueCode $IssueCode -BackupDir $backupDir -MaxSeverity $MaxSeverity `
                                          -DnsOption $DnsOption -PowerPlanGuid $PowerPlanGuid `
                                          -SkipCleanScan -WhatIf:$WhatIf -Force:$Force
        } else {
            $rpOn = switch ("$CreateRestorePoint".Trim().ToLower()) {
                'true'  { $true }
                'false' { $false }
                default { Get-RestorePointDefault }
            }
            $r = Invoke-HealthRemediation -BackupDir $backupDir -MaxSeverity $MaxSeverity `
                                          -DnsOption $DnsOption -PowerPlanGuid $PowerPlanGuid `
                                          -SkipCleanScan -WhatIf:$WhatIf -Force:$Force `
                                          -CreateRestorePoint:$rpOn
        }
        # 还原点状态单独带出，前端可直接弹提示
        Out-Json ([PSCustomObject]@{
            ok           = $r.ok
            whatIf       = $r.whatIf
            executed     = $r.executed
            skipped      = $r.skipped
            results      = $r.results
            restorePoint = $r.restorePoint
            error        = $r.error
        })
    }
    elseif ($Action -eq "tips") {
        # 智能降级建议（P2）：优先复用最近一次体检报告判断该不该给建议，
        # 没有历史报告时才临时扫一次（跳过慢的可清理空间统计）。
        $tipsReport = Get-PreviousHealthReport -BackupDir $backupDir
        if (-not $tipsReport) { $tipsReport = Get-SystemHealthReport -SkipCleanScan }
        $tips = Get-SmartRecommendations -Report $tipsReport -Top 3
        Out-Json ([PSCustomObject]@{
            ok      = $true
            startup = @($tips.startup)
            clean   = @($tips.clean)
        })
    }
    elseif ($Action -eq "apply-tips") {
        # 智能建议一键应用（P3-1）：只应用启动项类建议，清理类保持只读手动
        $rpOn = switch ("$CreateRestorePoint".Trim().ToLower()) {
            'true'  { $true }
            'false' { $false }
            default { Get-RestorePointDefault }
        }
        # 与 -Action tips 同源：优先用最近一次体检报告判断该不该给建议
        $tipsReport = Get-PreviousHealthReport -BackupDir $backupDir
        if (-not $tipsReport) { $tipsReport = Get-SystemHealthReport -SkipCleanScan }
        $r = Invoke-SmartRecommendations -Report $tipsReport -Top $Top -BackupDir $backupDir `
                                          -WhatIf:$WhatIf -CreateRestorePoint:$rpOn
        Out-Json ([PSCustomObject]@{
            ok           = $r.ok
            whatIf       = $r.whatIf
            applied      = @($r.applied)
            failed       = @($r.failed | ForEach-Object { [PSCustomObject]@{ name = $_.name; reason = $_.reason } })
            backup       = $r.backup
            restorePoint = $r.restorePoint
            error        = $r.error
        })
    }
    elseif ($Action -eq "export") {
        $fmt = if ($Format -eq "md") { "Markdown" } else { "Html" }
        $expArgs = @{ Format = $fmt }
        if ($From) { $expArgs['From'] = $From } else { $expArgs['BackupDir'] = $backupDir }
        if ($To)   { $expArgs['To']   = $To }
        $exp = Export-HealthReport @expArgs
        if ($exp.ok) {
            Out-Json ([PSCustomObject]@{
                ok         = $true
                format     = $exp.format
                file       = $exp.file
                comparison = $exp.comparison
            })
        } else {
            Out-Json ([PSCustomObject]@{ ok = $false; error = $exp.error })
        }
    }
    elseif ($Action -eq "trend") {
        Out-Json ([PSCustomObject]@{
            ok    = $true
            days  = $Days
            trend = @(Get-HealthTrend -BackupDir $backupDir -Days $Days)
        })
    }
} catch {
    Out-Json ([PSCustomObject]@{ ok = $false; error = $_.Exception.Message })
}

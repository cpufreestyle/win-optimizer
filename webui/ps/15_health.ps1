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
    逻辑复用共享库 lib/Optimize.Core.ps1，与 CLI / GUI 行为一致。
#>
param(
    [ValidateSet("scan", "plan", "remediate")]$Action = "scan",
    [string[]]$IssueCode = @(),
    [ValidateSet("High", "Medium", "Low")]$MaxSeverity = "Medium",
    [int]$DnsOption = 1,
    [string]$PowerPlanGuid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c",
    [switch]$WhatIf,
    [switch]$Force
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

        $report = Get-SystemHealthReport
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
            $r = Invoke-HealthRemediation -BackupDir $backupDir -MaxSeverity $MaxSeverity `
                                          -DnsOption $DnsOption -PowerPlanGuid $PowerPlanGuid `
                                          -SkipCleanScan -WhatIf:$WhatIf -Force:$Force
        }
        Out-Json $r
    }
} catch {
    Out-Json ([PSCustomObject]{ ok = $false; error = $_.Exception.Message })
}

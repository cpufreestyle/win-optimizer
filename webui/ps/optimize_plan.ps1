<#
.SYNOPSIS
    完整优化预览（只读 dry-run）— 返回「一键全面优化」将做什么
.DESCRIPTION
    列出清理 / 服务 / 启动项 / 视觉 / 电源 / 磁盘 / 网络 / 遥测 /
    组合包每一步的目标、明细、预估影响与风险等级；不执行任何修改。
    -Action plan     : 返回完整优化预览（当前唯一动作，仅此一个）
        -Profile       附加上优化组合包步骤预览（old_balanced/gaming/quiet_saver/minimal）
        -SkipCleanScan 跳过可清理体积统计（省十几秒，清理步骤将没有体积数据）
    逻辑复用共享库 lib/Optimize.Core.ps1 的 Get-OptimizePlan，
    与 CLI（Optimize.ps1 -Plan）完全同源。
#>
param(
    [ValidateSet("plan")]$Action = "plan",
    [string]$Profile = "",
    [switch]$SkipCleanScan
)


# 统一 stdout 为 UTF-8（让 Python subprocess.run 按 utf-8 解码时不乱码；与 15_health.ps1 同款）
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

function Out-Json {
    param($obj)
    $obj | ConvertTo-Json -Depth 8 -Compress
}

$ErrorActionPreference = "Stop"

# 复用共享核心库（优化预览引擎，与 CLI / GUI 同源）
$libPath = Join-Path $PSScriptRoot "..\..\lib\Optimize.Core.ps1"
if (-not (Test-Path $libPath)) {
    Out-Json ([PSCustomObject]@{ ok = $false; error = "未找到共享核心库: $libPath" })
    return
}
. $libPath

try {
    $planArgs = @{}
    if ($Profile) { $planArgs['ProfileName'] = $Profile }
    if ($SkipCleanScan) { $planArgs['SkipCleanScan'] = $true }
    $plan = Get-OptimizePlan @planArgs

    # 纯文本版同时给出，便于前端直接贴日志或 CLI 直接打印
    $lines = @(Format-OptimizePlan $plan)

    Out-Json ([PSCustomObject]@{
        ok          = $true
        version     = $plan.version
        generatedAt = $plan.generatedAt
        powerPlan   = $plan.powerPlan
        dns         = $plan.dns
        steps       = $plan.steps
        summary     = $plan.summary
        lines       = $lines
    })
} catch {
    Out-Json ([PSCustomObject]@{ ok = $false; error = $_.Exception.Message })
}

<#
.SYNOPSIS
    WebUI 优化组合包（Profiles）— 清单 / 只读预览 / 执行，返回 JSON
.DESCRIPTION
    -Action list : 列出 config 中的组合包（含每包的标题、说明与步骤数）
    -Action plan : 只读预览指定组合包将做什么（域 / 动作 / 目标 / 影响 / 风险级别）
    -Action apply: 执行组合包；-DryRun 只出计划不修改，-Force 放行 high 级步骤
    逻辑复用共享库 lib/Optimize.Core.ps1，与 CLI / GUI 行为一致。
#>
param(
    [ValidateSet("list", "plan", "apply")]$Action = "list",
    [string]$Name = "",
    [switch]$DryRun,
    # 优化前还原点（P1-3）：auto / true / false，默认 auto（取 config 的 safety.create_restore_point）。
    # 字符串三态：通过 powershell -File 调用，[bool] 绑定不了“false”。
    [string]$CreateRestorePoint = "auto",
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

$libPath = Join-Path $PSScriptRoot "..\..\lib\Optimize.Core.ps1"
if (Test-Path $libPath) { . $libPath }
if (-not (Get-Command Get-Profiles -ErrorAction SilentlyContinue)) {
    Out-Json ([PSCustomObject]@{ ok = $false; error = "未找到共享核心库 lib\Optimize.Core.ps1" })
    exit
}

if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }

try {
    if ($Action -eq "list") {
        $rows = @()
        foreach ($p in @(Get-Profiles)) {
            $plan = Get-ProfilePlan -Name $p.name
            $rows += [PSCustomObject]@{
                name      = $p.name
                title     = $p.title
                desc      = $p.desc
                steps     = @($plan.steps).Count
                highRisk  = @($plan.steps | Where-Object { $_.risk -eq 'high' }).Count
                needForce = (@($plan.steps | Where-Object { $_.risk -eq 'high' -or -not $_.auto }).Count -gt 0)
                spec      = [PSCustomObject]@{
                    services  = $p.services
                    startup   = $p.startup
                    visual    = $p.visual
                    power     = $p.power
                    dns       = $p.dns
                    telemetry = $p.telemetry
                    disk      = $p.disk
                    compactOs = $p.compactOs
                }
            }
        }
        Out-Json ([PSCustomObject]@{ ok = $true; count = $rows.Count; profiles = $rows })
    }
    elseif ($Action -eq "plan") {
        if (-not $Name) { Out-Json ([PSCustomObject]@{ ok = $false; error = "缺少 -Name 参数" }); exit }
        $p = Get-ProfilePlan -Name $Name
        if (-not $p.ok) { Out-Json ([PSCustomObject]@{ ok = $false; error = $p.error }); exit }
        Out-Json ([PSCustomObject]@{
            ok = $true; name = $p.name; title = $p.title; desc = $p.desc; steps = @($p.steps)
        })
    }
    elseif ($Action -eq "apply") {
        if (-not $Name) { Out-Json ([PSCustomObject]@{ ok = $false; error = "缺少 -Name 参数" }); exit }
        # 优化前还原点（P1-3）：未显式传入时取 config 默认值
        $rp = switch ("$CreateRestorePoint".Trim().ToLower()) {
            'true'  { $true }
            'false' { $false }
            default { Get-RestorePointDefault }
        }
        $r = Invoke-Profile -Name $Name -BackupDir $backupDir -WhatIf:$DryRun -Force:$Force -CreateRestorePoint:$rp
        Out-Json ([PSCustomObject]@{
            ok           = $r.ok
            name         = $r.name
            title        = $r.title
            desc         = $r.desc
            dryRun       = $r.dryRun
            forced       = $r.forced
            steps        = $r.steps
            results      = $r.results
            skipped      = $r.skipped
            restorePoint = $r.restorePoint
            error        = $r.error
        })
    }
} catch {
    Out-Json ([PSCustomObject]@{ ok = $false; error = $_.Exception.Message })
}

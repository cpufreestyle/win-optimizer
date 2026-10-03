<#
.SYNOPSIS
    WebUI 一键向导 — 只读计划 / 执行（体检 -> 推荐 -> 预览 -> 执行 -> 复检），返回 JSON
.DESCRIPTION
    -Action plan  : 只读体检并给出向导计划（推荐组合包 / 步骤 / 需人工确认项 / 前后对比快照），不改动系统
    -Action apply : 按推荐的组合包执行优化；执行前自动备份，默认不执行高风险步骤
        -Profile     指定组合包名（省略时用体检推荐）
        -DryRun      只出计划与步骤结果，不修改任何设置
        -Force       放行高风险 / 需人工确认的步骤
        -CreateRestorePoint  执行前建系统还原点（auto / true / false）
    -Action rerun : 优化完成后重新体检，与 plan 返回的 report 做前后对比
        -From        优化前的体检报告（plan 返回的 report 对象，JSON 字符串）
        -FromB64     同上，但为 Base64(UTF-8) 编码；供 WebUI 调用，避免命令行引号转义问题
    逻辑复用共享库 lib/Optimize.Core.ps1 的 Get-GuidedPlan / Format-GuidedPlan / Invoke-Profile /
    Compare-HealthReports，与 CLI `Optimize.ps1 -Guided` 完全同源。
#>
param(
    [ValidateSet("plan", "apply", "rerun", "export", "dismiss_onboarding")]$Action = "plan",
    [ValidateSet("html", "markdown")]$Format = "html",
    [string]$Before = "",
    [string]$BeforeB64 = "",
    [string]$After = "",
    [string]$AfterB64 = "",
    [string]$Profile = "",
    [switch]$SkipCleanScan,
    [switch]$DryRun,
    [switch]$Force,
    [string]$CreateRestorePoint = "auto",
    [string]$From = "",
    [string]$FromB64 = ""
)


# 统一 stdout 为 UTF-8（让 Python subprocess.run 按 utf-8 解码时不乱码；与 15_health.ps1 同款）
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
function Out-Json {
    param($obj)
    $obj | ConvertTo-Json -Depth 10 -Compress
}

$ErrorActionPreference = "Stop"
$backupDir = Join-Path $PSScriptRoot "..\..\backups"
$backupDir = [System.IO.Path]::GetFullPath($backupDir)
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }

# 复用共享核心库（向导编排与组合包执行，与 CLI / GUI 同源）
$libPath = Join-Path $PSScriptRoot "..\..\lib\Optimize.Core.ps1"
if (Test-Path $libPath) { . $libPath }
if (-not (Get-Command Get-GuidedPlan -ErrorAction SilentlyContinue)) {
    Out-Json ([PSCustomObject]@{ ok = $false; error = "未找到共享核心库 lib\Optimize.Core.ps1" })
    exit
}

try {
    if ($Action -eq "plan") {
        $planArgs = @{}
        if ($Profile) { $planArgs['ProfileName'] = $Profile }
        if ($SkipCleanScan) { $planArgs['SkipCleanScan'] = $true }
        $g = Get-GuidedPlan @planArgs
        $lines = @(Format-GuidedPlan -Plan $g)
        Out-Json ([PSCustomObject]@{
            ok              = [bool]$g.ok
            error           = $g.error
            version         = $g.version
            generatedAt     = $g.generatedAt
            profile         = $g.profile
            score           = $g.score
            grade           = $g.grade
            beforeScore     = $g.beforeScore
            beforeTime      = $g.beforeTime
            issues          = @($g.issues)
            steps           = @($g.steps)
            manual          = @($g.manual)
            recommendations = @($g.recommendations)
            summary         = $g.summary
            powerPlan       = $g.powerPlan
            dns             = $g.dns
            report          = $g.report
            lines           = $lines
           onboarding      = $g.onboarding
        })
    }
    elseif ($Action -eq "apply") {
        # 与 CLI 一致：未指定组合包时先体检拿推荐，再执行；默认不传 -Force，高风险步骤自动跳过
        $name = $Profile
        if (-not $name) {
            $g = Get-GuidedPlan -SkipCleanScan:$SkipCleanScan
            if (-not $g.ok) { Out-Json ([PSCustomObject]@{ ok = $false; error = $g.error }); exit }
            if (-not $g.profile.matched) { Out-Json ([PSCustomObject]@{ ok = $false; error = ("推荐组合包不可用: " + $g.profile.name) }); exit }
            $name = [string]$g.profile.name
        }
        $rp = switch ("$CreateRestorePoint".Trim().ToLower()) {
            'true'  { $true }
            'false' { $false }
            default { Get-RestorePointDefault }
        }
        $r = Invoke-Profile -Name $name -BackupDir $backupDir -WhatIf:$DryRun -Force:$Force -CreateRestorePoint:$rp
        Out-Json ([PSCustomObject]@{
            ok           = [bool]$r.ok
            name         = $r.name
            title        = $r.title
            desc         = $r.desc
            dryRun       = [bool]$r.dryRun
            forced       = [bool]$r.forced
            steps        = @($r.steps)
            results      = @($r.results)
            skipped      = @($r.skipped)
            restorePoint = $r.restorePoint
            error        = $r.error
        })
    }
    elseif ($Action -eq "rerun") {
        # 优化后复检并与优化前报告对比；-From / -FromB64 为 plan 返回的 report
        $raw = $From
        if (-not $raw -and $FromB64) {
            try { $raw = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($FromB64)) } catch { $raw = "" }
        }
        $before = $null
        if ($raw) {
            try { $before = $raw | ConvertFrom-Json } catch { $before = $null }
        }
        $after = Get-SystemHealthReport
        if (-not $after) { Out-Json ([PSCustomObject]@{ ok = $false; error = "复检失败" }); exit }
        $cmp = $null
        if ($before) { $cmp = Compare-HealthReports -Before $before -After $after }
        try { $saved = Save-HealthReport -Report $after -BackupDir $backupDir } catch { $saved = $null }
        Out-Json ([PSCustomObject]@{
            ok         = $true
            afterScore = $after.score
            afterGrade = $after.grade
            afterTime  = $after.timestamp
            report     = $after
            saved      = $saved
            compare    = $(if ($cmp) {
                [PSCustomObject]@{
                    beforeScore = $cmp.beforeScore
                    afterScore  = $cmp.afterScore
                    scoreDelta  = $cmp.scoreDelta
                    resolved    = @($cmp.resolved)
                    new         = @($cmp.new)
                }
            } else { $null })
        })
    }
    elseif ($Action -eq "dismiss_onboarding") {
        # 用户点了「知道了」：把一次性说明标记为已读，之后 plan 不再返回它
        $done = Set-OnboardingHintShown
        Out-Json ([PSCustomObject]@{ ok = [bool]$done })
    }
    elseif ($Action -eq "export") {
        # 把前后两份体检报告导出成可分享的对比报告，复用 lib 的 Export-HealthReport
        $bRaw = $Before
        if (-not $bRaw -and $BeforeB64) {
            try { $bRaw = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($BeforeB64)) } catch { $bRaw = "" }
        }
        $aRaw = $After
        if (-not $aRaw -and $AfterB64) {
            try { $aRaw = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($AfterB64)) } catch { $aRaw = "" }
        }
        $bObj = $null; $aObj = $null
        try { if ($bRaw) { $bObj = $bRaw | ConvertFrom-Json } } catch { $bObj = $null }
        try { if ($aRaw) { $aObj = $aRaw | ConvertFrom-Json } } catch { $aObj = $null }
        if (-not $bObj -or -not $aObj) {
            Out-Json ([PSCustomObject]@{ ok = $false; error = "需要前后两份体检报告才能导出对比" })
            exit
        }
        $exp = Export-HealthReport -From $bObj -To $aObj -Format $Format
        Out-Json ([PSCustomObject]@{
            ok    = [bool]$exp.ok
            error = $exp.error
            file  = $exp.file
            format = $exp.format
            scoreDelta = $(if ($exp.comparison) { $exp.comparison.scoreDelta } else { $null })
        })
    }
} catch {
    Out-Json ([PSCustomObject]@{ ok = $false; error = $_.Exception.Message })
}

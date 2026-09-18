<#
.SYNOPSIS
    WebUI 视觉效果优化 — 列出/应用，返回 JSON
.DESCRIPTION
    -Action list : 列出可选模式（最佳性能/平衡/自定义）及当前设置
    -Action apply: 应用指定模式（value=1 最佳性能 / 2 平衡 / 3 自定义）
#>
param(
    [ValidateSet("list", "apply")]$Action = "list",
    [int]$Value = 1
)


# 统一 stdout 为 UTF-8（让 Python subprocess.run 按 utf-8 解码时不乱码；与 OptimizeGUI 同款）
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
function Out-Json {
    param($obj)
    $obj | ConvertTo-Json -Depth 4 -Compress
}

# 复用共享核心库（视觉效果统一实现，与 CLI / GUI 同源）
$libPath = Join-Path $PSScriptRoot "..\..\lib\Optimize.Core.ps1"
if (Test-Path $libPath) { . $libPath }
$backupDir = Join-Path $PSScriptRoot "..\..\backups"
$backupDir = [System.IO.Path]::GetFullPath($backupDir)

$ErrorActionPreference = "Stop"

# 模式清单与当前状态统一由共享库提供
$modes = Get-VisualEffectProfiles

try {
    if ($Action -eq "list") {
        $cur = Get-VisualEffectState
        $list = @()
        foreach ($m in $modes) {
            $list += [PSCustomObject]@{
                value = $m.Value
                title = $m.Title
                desc  = $m.Desc
                safe  = $m.Safe
            }
        }
        Out-Json ([PSCustomObject]@{
            ok = $true
            modes = $list
            current = $cur
        })
    }
    elseif ($Action -eq "apply") {
        $target = $modes | Where-Object { $_.Value -eq $Value }
        if (-not $target) { Out-Json ([PSCustomObject]@{ ok=$false; error="无效模式: $Value" }); exit }

        # 统一走共享库：会先备份再应用。
        # 此前 WebUI 完全没有备份，且「最佳性能」缺 UserPreferencesMask 等关键项——一并修复。
        $r = Set-VisualEffectProfile -Profile $Value -BackupDir $backupDir
        Out-Json ([PSCustomObject]@{ ok = $r.ok; applied = ($r.details -join "、"); value = $Value; backup = $r.backup })
    }
} catch {
    Out-Json ([PSCustomObject]@{ ok = $false; error = $_.Exception.Message })
}

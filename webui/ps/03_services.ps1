<#
.SYNOPSIS
    WebUI 服务优化 — 列出/禁用/恢复，返回 JSON
.DESCRIPTION
    -Action list   : 列出可优化服务及其当前状态
    -Action apply  : 禁用（mode=all 全部 / mode=safe 仅安全禁用）
    -Action restore: 从最近备份 CSV 恢复
    逻辑复用共享库 lib/Optimize.Core.ps1，保证与 CLI/GUI 行为一致。
#>
param(
    [ValidateSet("list", "apply", "restore")]$Action = "list",
    [ValidateSet("all", "safe")]$Mode = "safe"
)

function Out-Json {
    param($obj)
    $obj | ConvertTo-Json -Depth 4 -Compress
}

$ErrorActionPreference = "Stop"
$backupDir = Join-Path $PSScriptRoot "..\..\backups"
$backupDir = [System.IO.Path]::GetFullPath($backupDir)

# 加载共享库
$libPath = Join-Path $PSScriptRoot "..\..\lib\Optimize.Core.ps1"
if (Test-Path $libPath) { . $libPath }

# Web 层使用 safe/suggest 作为 level 输出字段，lib 返回 安全禁用/建议禁用
function Convert-Level {
    param([string]$l)
    if ($l -eq "安全禁用") { return "safe" } else { return "suggest" }
}

try {
    if ($Action -eq "list") {
        $list = @()
        foreach ($svc in (Get-ServiceList)) {
            $st = Get-ServiceStartType $svc.Name
            $list += [PSCustomObject]@{
                name      = $svc.Name
                desc      = $svc.Desc
                level     = Convert-Level $svc.Level
                startType = $st
                disabled  = ($st -eq "Disabled")
            }
        }
        Out-Json ([PSCustomObject]@{ ok = $true; services = $list })
    }
    elseif ($Action -eq "apply") {
        $services = Get-ServiceList
        $backupFile = Backup-ServiceStates -BackupDir $backupDir -Services $services
        $result = Disable-Services -Services $services -Mode $Mode
        Out-Json ([PSCustomObject]@{
            ok       = $true
            disabled = $result.disabled
            skipped  = $result.skipped
            backup   = $backupFile
            details  = $result.details
        })
    }
    elseif ($Action -eq "restore") {
        $result = Restore-Services -BackupDir $backupDir
        if ($result.error) {
            Out-Json ([PSCustomObject]@{ ok = $false; error = $result.error })
        } else {
            Out-Json ([PSCustomObject]@{
                ok       = $true
                restored = $result.restored
                backup   = $result.backup
                details  = $result.details
            })
        }
    }
} catch {
    Out-Json ([PSCustomObject]@{ ok = $false; error = $_.Exception.Message })
}

<#
.SYNOPSIS
    WebUI 启动项优化 — 列出/禁用，返回 JSON
.DESCRIPTION
    -Action list   : 列出所有启动项
    -Action disable: 禁用指定索引（items=1,3 或 all）
#>
param(
    [ValidateSet("list", "disable")]$Action = "list",
    [string]$Items = "all"
)


# 统一 stdout 为 UTF-8（让 Python subprocess.run 按 utf-8 解码时不乱码；与 OptimizeGUI 同款）
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
function Out-Json {
    param($obj)
    $obj | ConvertTo-Json -Depth 4 -Compress
}

# 复用共享核心库（启动项统一实现，与 CLI / GUI 同源）
$libPath = Join-Path $PSScriptRoot "..\..\lib\Optimize.Core.ps1"
if (Test-Path $libPath) { . $libPath }

$ErrorActionPreference = "Stop"
$backupDir = Join-Path $PSScriptRoot "..\..\backups"
$backupDir = [System.IO.Path]::GetFullPath($backupDir)

# 前端沿用小写字段名，这里只做字段投影；枚举 / 去重逻辑统一走共享库
function ConvertTo-StartupJson {
    param($items)
    $out = @()
    foreach ($it in $items) {
        $out += [PSCustomObject]@{
            index  = $it.Index
            name   = $it.Name
            value  = $it.Value
            scope  = $it.Scope
            source = $it.Source
            path   = $it.Path
        }
    }
    return $out
}

try {
    if ($Action -eq "list") {
        $items = Get-StartupItems
        Out-Json ([PSCustomObject]@{ ok = $true; items = (ConvertTo-StartupJson $items); count = $items.Count })
    }
    elseif ($Action -eq "disable") {
        $items = Get-StartupItems
        $targets = @(Select-StartupItems -Items $items -Selector $Items)
        # 备份 CSV 列名由共享库统一，保证 CLI / GUI 的恢复流程能正确读取
        $res = Disable-StartupItems -BackupDir $backupDir -Items $targets
        $details = @()
        foreach ($d in $res.details) { $details += [PSCustomObject]@{ name = $d.Name; result = $d.Result } }
        Out-Json ([PSCustomObject]@{ ok = $true; disabled = $res.disabled; failed = $res.failed; backup = $res.backup; details = $details })
    }
} catch {
    Out-Json ([PSCustomObject]@{ ok = $false; error = $_.Exception.Message })
}

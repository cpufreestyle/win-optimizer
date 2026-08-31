<#
.SYNOPSIS
    WebUI 恢复 Windows 自动更新 — 返回 JSON
.DESCRIPTION
    将 Windows Update 服务恢复为自动启动，重新启用更新相关计划任务，
    撤销手动更新模式 / 更新屏蔽设置的限制。
    业务逻辑复用共享库 lib\Optimize.Core.ps1 的 Restore-AutoUpdate。
#>
param()


# 统一 stdout 为 UTF-8（让 Python subprocess.run 按 utf-8 解码时不乱码；与 OptimizeGUI 同款）
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
function Out-Json {
    param($obj)
    $obj | ConvertTo-Json -Depth 4 -Compress
}

$ErrorActionPreference = "Stop"

# 复用共享核心库
$libPath = Join-Path $PSScriptRoot "..\..\lib\Optimize.Core.ps1"
if (Test-Path $libPath) { . $libPath }

try {
    $r = Restore-AutoUpdate
    if ($r.ok) {
        Out-Json ([PSCustomObject]@{
            ok      = $true
            message = "Windows 自动更新已恢复"
            details = @($r.details)
        })
    } else {
        Out-Json ([PSCustomObject]@{
            ok      = $false
            error   = $r.error
            details = @($r.details)
        })
    }
} catch {
    Out-Json ([PSCustomObject]@{ ok = $false; error = $_.Exception.Message; details = @() })
}

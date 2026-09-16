<#
.SYNOPSIS
    WebUI 系统体检 — 只读扫描并返回体检报告与前后对比
.DESCRIPTION
    -Action scan : 执行只读体检，保存报告，并与上一次体检对比后返回
#>
param(
    [ValidateSet("scan")]$Action = "scan"
)


# 统一 stdout 为 UTF-8（让 Python subprocess.run 按 utf-8 解码时不乱码；与 OptimizeGUI 同款）
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
function Out-Json {
    param($obj)
    $obj | ConvertTo-Json -Depth 8 -Compress
}

# 复用共享核心库（体检引擎，与 CLI / GUI 同源）
$libPath = Join-Path $PSScriptRoot "..\..\lib\Optimize.Core.ps1"
if (Test-Path $libPath) { . $libPath }
$backupDir = Join-Path $PSScriptRoot "..\..\backups"
$backupDir = [System.IO.Path]::GetFullPath($backupDir)

try {
    # 在保存本次报告之前先取上一次的，用于对比
    $prev = Get-PreviousHealthReport -BackupDir $backupDir

    $report = Get-SystemHealthReport
    $file   = Save-HealthReport -Report $report -BackupDir $backupDir

    $cmp = $null
    if ($prev) { $cmp = Compare-HealthReports -Before $prev -After $report }

    Out-Json ([PSCustomObject]@{
        ok         = $true
        report     = $report
        comparison = $cmp
        file       = $file
    })
} catch {
    Out-Json ([PSCustomObject]@{ ok = $false; error = $_.Exception.Message })
}

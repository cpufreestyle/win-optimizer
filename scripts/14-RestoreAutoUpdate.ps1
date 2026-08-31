#Requires -RunAsAdministrator
<#
.SYNOPSIS
    恢复 Windows 自动更新（wuauserv）服务。
.DESCRIPTION
    将 Windows Update 服务恢复为自动启动，并重新启用与更新相关的计划任务，
    撤销 11-ManualUpdateMode.ps1 / 10-BlockWin1124H2.ps1 所设置的限制。
    业务逻辑复用共享库 lib\Optimize.Core.ps1 的 Restore-AutoUpdate。
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"

Add-Type -AssemblyName System.Windows.Forms

# 复用共享核心库
$coreLib = Join-Path $PSScriptRoot "..\lib\Optimize.Core.ps1"
if (Test-Path $coreLib) { . $coreLib }

function Write-Log {
    param([string]$Msg, [string]$Level = "INFO")
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Msg"
    Write-Host $line
    $logFile = Join-Path $PSScriptRoot "..\optimize.log"
    Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue
}

Write-Log "正在恢复 Windows 自动更新..."

$r = Restore-AutoUpdate
foreach ($d in $r.details) { Write-Log $d $(if ($r.ok) { "SUCCESS" } else { "INFO" }) }

if ($r.ok) {
    Write-Log "Windows 自动更新已恢复" "SUCCESS"
    [System.Windows.Forms.MessageBox]::Show("Windows 自动更新已恢复。", "完成",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
} else {
    Write-Log "恢复自动更新失败: $($r.error)" "ERROR"
    [System.Windows.Forms.MessageBox]::Show("恢复失败: $($r.error)", "错误",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
}

#Requires -RunAsAdministrator
<#
.SYNOPSIS
    恢复 Windows 自动更新（wuauserv）服务。
.DESCRIPTION
    将 Windows Update 服务恢复为自动启动，并重新启用与更新相关的计划任务，
    撤销 11-ManualUpdateMode.ps1 所设置的手动更新模式。
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"

function Write-Log {
    param([string]$Msg, [string]$Level = "INFO")
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Msg"
    Write-Host $line
    $logFile = Join-Path $PSScriptRoot "..\optimize.log"
    Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue
}

Write-Log "正在恢复 Windows 自动更新..."

try {
    # 1. 恢复 Windows Update 服务为自动
    $svc = Get-Service -Name wuauserv -ErrorAction Stop
    if ($svc.StartType -ne 'Automatic') {
        Set-Service -Name wuauserv -StartupType Automatic -ErrorAction Stop
        Write-Log "已将 wuauserv 启动类型设为 自动" "SUCCESS"
    } else {
        Write-Log "wuauserv 已经是 自动 启动" "INFO"
    }

    if ($svc.Status -ne 'Running') {
        Start-Service -Name wuauserv -ErrorAction Stop
        Write-Log "已启动 wuauserv 服务" "SUCCESS"
    } else {
        Write-Log "wuauserv 服务正在运行" "INFO"
    }

    # 2. 重新启用与 Windows Update 相关的计划任务
    $tasks = @(
        "\Microsoft\Windows\WindowsUpdate\Scheduled Start",
        "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan",
        "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan Static Task",
        "\Microsoft\Windows\UpdateOrchestrator\USO_UxBroker"
    )
    foreach ($task in $tasks) {
        try {
            $t = Get-ScheduledTask -TaskName $task -ErrorAction Stop
            if ($t.State -eq 'Disabled') {
                Enable-ScheduledTask -TaskName $task -ErrorAction Stop | Out-Null
                Write-Log "已启用计划任务: $task" "SUCCESS"
            } else {
                Write-Log "计划任务已启用: $task" "INFO"
            }
        } catch {
            Write-Log "计划任务 $task 不存在或无法启用: $($_.Exception.Message)" "WARNING"
        }
    }

    # 3. 删除手动更新模式留下的 AUOptions 限制（如果存在）
    $auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    if (Test-Path $auPath) {
        $auOption = Get-ItemProperty -Path $auPath -Name AUOptions -ErrorAction SilentlyContinue
        if ($auOption -and ($auOption.AUOptions -eq 2 -or $auOption.AUOptions -eq 3)) {
            Remove-ItemProperty -Path $auPath -Name AUOptions -Force -ErrorAction SilentlyContinue
            Write-Log "已删除 AUOptions 限制，恢复自动安装" "SUCCESS"
        }
    }

    Write-Log "Windows 自动更新已恢复" "SUCCESS"
    [System.Windows.Forms.MessageBox]::Show("Windows 自动更新已恢复。", "完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
} catch {
    Write-Log "恢复自动更新失败: $($_.Exception.Message)" "ERROR"
    [System.Windows.Forms.MessageBox]::Show("恢复失败: $($_.Exception.Message)", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}

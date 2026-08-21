<#
.SYNOPSIS
    WebUI 手动更新模式 — 应用/恢复，返回 JSON
.DESCRIPTION
    -Action apply   : 设为"通知下载并通知安装"(AUOptions=2)，不暂停更新
    -Action restore : 从 .reg 备份恢复
    -Action status  : 查看当前状态
#>
param(
    [ValidateSet("apply", "restore", "status")]$Action = "status"
)

function Out-Json {
    param($obj)
    $obj | ConvertTo-Json -Depth 4 -Compress
}

$ErrorActionPreference = "Stop"
$backupDir = Join-Path $PSScriptRoot "..\..\backups"
$backupDir = [System.IO.Path]::GetFullPath($backupDir)
$auKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

try {
    if ($Action -eq "status") {
        $v = Get-ItemProperty $auKey -ErrorAction SilentlyContinue
        $mode = if ($v) {
            if ($v.NoAutoUpdate -eq 1) { "已暂停/屏蔽" }
            elseif ($v.AUOptions -eq 2) { "手动安装(通知)" }
            else { "自动(默认)" }
        } else { "自动(默认)" }
        Out-Json ([PSCustomObject]@{ ok = $true; mode = $mode })
        exit
    }
    if ($Action -eq "apply") {
        if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
        $backupFile = Join-Path $backupDir "manual_update_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
        if (Test-Path $auKey) { & reg export $auKey $backupFile /y 2>$null }
        if (-not (Test-Path $auKey)) { New-Item -Path $auKey -Force | Out-Null }
        Set-ItemProperty $auKey -Name "NoAutoUpdate" -Value 0 -Type DWord -Force
        Set-ItemProperty $auKey -Name "AUOptions" -Value 2 -Type DWord -Force
        foreach ($svc in @("wuauserv", "UsoSvc")) {
            try { Restart-Service -Name $svc -Force -ErrorAction SilentlyContinue } catch {}
        }
        Out-Json ([PSCustomObject]@{ ok = $true; mode = "手动安装(通知)"; backup = $backupFile })
    }
    elseif ($Action -eq "restore") {
        $reg = Get-ChildItem -Path $backupDir -Filter "manual_update_*.reg" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $reg) { Out-Json ([PSCustomObject]@{ ok = $false; error = "未找到手动模式备份" }); exit }
        & reg import $reg.FullName 2>$null
        Out-Json ([PSCustomObject]@{ ok = $true; restored = $reg.FullName })
    }
} catch {
    Out-Json ([PSCustomObject]@{ ok = $false; error = $_.Exception.Message })
}

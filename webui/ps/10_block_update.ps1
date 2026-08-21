<#
.SYNOPSIS
    WebUI 屏蔽 Windows 更新 — 应用/恢复，返回 JSON
.DESCRIPTION
    -Action apply   : 硬锁当前版本 + 高优先级通道（含隐藏 24H2 升级项）
    -Action restore : 从最近 .reg 备份恢复
    -Action status  : 查看当前屏蔽状态
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
$regKeys = @(
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate",
    "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings",
    "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\Settings"
)

try {
    if ($Action -eq "status") {
        $blocked = $false
        try { $v = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -ErrorAction SilentlyContinue; if ($v.NoAutoUpdate -eq 1) { $blocked = $true } } catch {}
        $targetVer = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "FragmentTargetVersion" -ErrorAction SilentlyContinue).FragmentTargetVersion
        Out-Json ([PSCustomObject]@{ ok = $true; blocked = $blocked; targetVersion = $targetVer })
        exit
    }

    if ($Action -eq "apply") {
        if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
        $backupFile = Join-Path $backupDir "winupdate_block_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
        $bkOk = $true
        foreach ($k in $regKeys) {
            if (Test-Path $k) {
                & reg export $k $backupFile /y 2>$null
                if ($LASTEXITCODE -ne 0) { $bkOk = $false }
            }
        }

        $dv = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion" -Name "DisplayVersion" -ErrorAction SilentlyContinue).DisplayVersion
        if (-not $dv) { $dv = (Get-CimInstance Win32_OperatingSystem).BuildNumber }

        $ux = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
        if (-not (Test-Path $ux)) { New-Item -Path $ux -Force | Out-Null }
        Set-ItemProperty $ux -Name "FragmentTargetVersion" -Value $dv -Type String -Force
        Set-ItemProperty $ux -Name "TargetReleaseVersion" -Value 1 -Type DWord -Force
        Set-ItemProperty $ux -Name "TargetReleaseVersionInfo" -Value $dv -Type String -Force

        $wu = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
        $au = "$wu\AU"
        if (-not (Test-Path $wu)) { New-Item -Path $wu -Force | Out-Null }
        if (-not (Test-Path $au)) { New-Item -Path $au -Force | Out-Null }
        Set-ItemProperty $au -Name "NoAutoUpdate" -Value 1 -Type DWord -Force
        Set-ItemProperty $au -Name "AUOptions" -Value 2 -Type DWord -Force

        $pol = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\Settings"
        if (-not (Test-Path $pol)) { New-Item -Path $pol -Force | Out-Null }
        Set-ItemProperty $pol -Name "PauseDeferrals" -Value 1 -Type DWord -Force
        Set-ItemProperty $pol -Name "DeferFeatureUpdatesPeriodInDays" -Value 365 -Type DWord -Force
        Set-ItemProperty $pol -Name "DeferQualityUpdatesPeriodInDays" -Value 30 -Type DWord -Force

        $hidden = 0
        try {
            $session = New-Object -ComObject Microsoft.Update.Session
            $searcher = $session.CreateUpdateSearcher()
            $updates = $searcher.Search("IsInstalled=0 AND Type='Software'").Updates
            foreach ($u in $updates) {
                if ($u.Title -match "24H2|Feature Update|功能更新|升级") {
                    try { $u.IsHidden = $true; $hidden++ } catch {}
                }
            }
        } catch {}

        foreach ($svc in @("wuauserv", "UsoSvc")) {
            try { Restart-Service -Name $svc -Force -ErrorAction SilentlyContinue } catch {}
        }

        Out-Json ([PSCustomObject]@{
            ok = $true
            backup = if ($bkOk) { $backupFile } else { "部分失败" }
            lockedVersion = $dv
            hiddenUpgrades = $hidden
        })
    }
    elseif ($Action -eq "restore") {
        $reg = Get-ChildItem -Path $backupDir -Filter "winupdate_block_*.reg" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $reg) { Out-Json ([PSCustomObject]@{ ok = $false; error = "未找到屏蔽备份" }); exit }
        & reg import $reg.FullName 2>$null
        Out-Json ([PSCustomObject]@{ ok = $true; restored = $reg.FullName })
    }
} catch {
    Out-Json ([PSCustomObject]@{ ok = $false; error = $_.Exception.Message })
}

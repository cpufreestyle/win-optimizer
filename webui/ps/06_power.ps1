<#
.SYNOPSIS
    WebUI 电源计划优化 — 列出/应用/查询当前，返回 JSON
.DESCRIPTION
    -Action list    : 列出可选计划（高性能/卓越性能/平衡优化）及其 GUID
    -Action current : 返回当前生效计划
    -Action apply   : 应用指定 GUID（value=1/2/3 对应列表顺序；可额外带 Usb/PCI 选项）
#>
param(
    [ValidateSet("list", "current", "apply")]$Action = "list",
    [int]$Value = 1,
    [bool]$Usb = $true,
    [bool]$Pci = $true
)


# 统一 stdout 为 UTF-8（让 Python subprocess.run 按 utf-8 解码时不乱码；与 OptimizeGUI 同款）
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
function Out-Json {
    param($obj)
    $obj | ConvertTo-Json -Depth 4 -Compress
}

# 复用共享核心库（电源计划统一实现，与 CLI / GUI 同源）
$libPath = Join-Path $PSScriptRoot "..\..\lib\Optimize.Core.ps1"
if (Test-Path $libPath) { . $libPath }
$backupDir = Join-Path $PSScriptRoot "..\..\backups"
$backupDir = [System.IO.Path]::GetFullPath($backupDir)

$ErrorActionPreference = "Stop"

# 计划清单统一由共享库提供
$plans = Get-PowerPlanCatalog

try {
    if ($Action -eq "list") {
        $list = @()
        foreach ($p in $plans) {
            $list += [PSCustomObject]@{
                value = $p.Value
                title = $p.Title
                desc  = $p.Desc
                guid  = $p.GUID
            }
        }
        Out-Json ([PSCustomObject]@{
            ok = $true
            plans = $list
            current = Get-ActivePowerPlan
        })
    }
    elseif ($Action -eq "current") {
        Out-Json ([PSCustomObject]@{ ok = $true; current = Get-ActivePowerPlan })
    }
    elseif ($Action -eq "apply") {
        $target = $plans | Where-Object { $_.Value -eq $Value }
        if (-not $target) { Out-Json ([PSCustomObject]@{ ok=$false; error="无效计划: $Value" }); exit }
        $guid = $target.GUID

        # 统一走共享库：先备份，支持卓越性能解锁与失败回退。
        # 三种模式都设置 CPU 上下限与 DISKIDLE（此前只有 value=1 设置 CPU，且完全没有备份与回退）。
        $params = @{
            Guid               = $guid
            UsbSuspendOff      = [bool]$Usb
            PciAspmOff         = [bool]$Pci
            BackupDir          = $backupDir
            UnlockUltimate     = ($Value -eq 2)
            FallbackToHighPerf = ($Value -eq 2)
        }
        switch ($Value) {
            1 { $params.MinPercent = 100; $params.MaxPercent = 100; $params.DiskIdleSeconds = 0 }
            2 { $params.MinPercent = 100; $params.MaxPercent = 100; $params.DiskIdleSeconds = 0 }
            3 { $params.MinPercent = 5;   $params.MaxPercent = 100; $params.DiskIdleSeconds = 1800 }
        }
        $r = Set-PowerPlan @params
        Out-Json ([PSCustomObject]@{ ok = $r.ok; applied = $target.Title; guid = $r.appliedGuid; backup = $r.backup; fallback = $r.fallback })
    }
} catch {
    Out-Json ([PSCustomObject]@{ ok = $false; error = $_.Exception.Message })
}

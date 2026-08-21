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

function Out-Json {
    param($obj)
    $obj | ConvertTo-Json -Depth 4 -Compress
}

$ErrorActionPreference = "Stop"

$plans = @(
    @{Value=1; Title="高性能模式";  Desc="最大化 CPU 性能，CPU 始终保持最高频率。适合台式机或插电笔记本。"; GUID="8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"}
    @{Value=2; Title="卓越性能模式"; Desc="比高性能更高，需解锁后可用。极限性能优先。"; GUID="e9a42b02-d5df-448d-aa00-03f14749eb61"}
    @{Value=3; Title="平衡优化模式"; Desc="平衡基础上优化，禁用 USB 挂起。适合笔记本电池模式。"; GUID="381b4222-f694-41f0-9685-ff5bb260df2e"}
)

function Get-ActivePlan {
    try {
        $out = @(powercfg /getactivescheme 2>&1) -join ' '
        if ($out -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
            return $matches[1]
        }
    } catch {}
    return $null
}

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
            current = Get-ActivePlan
        })
    }
    elseif ($Action -eq "current") {
        Out-Json ([PSCustomObject]@{ ok = $true; current = Get-ActivePlan })
    }
    elseif ($Action -eq "apply") {
        $target = $plans | Where-Object { $_.Value -eq $Value }
        if (-not $target) { Out-Json ([PSCustomObject]@{ ok=$false; error="无效计划: $Value" }); exit }
        $guid = $target.GUID

        if ($Value -eq 2) {
            # 卓越性能需先解锁
            powercfg /duplicatescheme $guid 2>&1 | Out-Null
        }
        powercfg /setactive $guid 2>&1 | Out-Null

        if ($Value -eq 1) {
            powercfg /setacvalueindex $guid SUB_PROCESSOR PROCTHROTTLEMIN 100 2>&1 | Out-Null
            powercfg /setacvalueindex $guid SUB_PROCESSOR PROCTHROTTLEMAX 100 2>&1 | Out-Null
        }
        if ($Usb) {
            powercfg /setacvalueindex $guid SUB_USB USBSELSUSP 0 2>&1 | Out-Null
        }
        if ($Pci) {
            powercfg /setacvalueindex $guid SUB_PCIEXPRESS ASPM 0 2>&1 | Out-Null
        }
        powercfg /setactive $guid 2>&1 | Out-Null

        Out-Json ([PSCustomObject]@{ ok = $true; applied = $target.Title; guid = $guid })
    }
} catch {
    Out-Json ([PSCustomObject]@{ ok = $false; error = $_.Exception.Message })
}

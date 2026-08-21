<#
.SYNOPSIS
    WebUI Windows 可选功能 — 列出/启用/已启用，返回 JSON
.DESCRIPTION
    -Action list      : 列出未启用、可启用的功能
    -Action enabled   : 列出已启用的功能
    -Action enable    : 启用指定序号(items=1,3 或 all)，需联网获取组件
#>
param(
    [ValidateSet("list", "enabled", "enable")]$Action = "list",
    [string]$Items = "all"
)

function Out-Json {
    param($obj)
    $obj | ConvertTo-Json -Depth 4 -Compress
}

$ErrorActionPreference = "Stop"

try {
    if ($Action -eq "list") {
        $feats = Get-WindowsOptionalFeature -Online -ErrorAction Stop | Where-Object { $_.State -ne "Enabled" }
        $list = @()
        $i = 0
        foreach ($f in $feats) { $i++; $list += [PSCustomObject]@{ index = $i; name = $f.FeatureName; state = $f.State } }
        Out-Json ([PSCustomObject]@{ ok = $true; features = $list; count = $list.Count })
    }
    elseif ($Action -eq "enabled") {
        $feats = Get-WindowsOptionalFeature -Online -ErrorAction Stop | Where-Object { $_.State -eq "Enabled" }
        $list = @()
        $i = 0
        foreach ($f in $feats) { $i++; $list += [PSCustomObject]@{ index = $i; name = $f.FeatureName } }
        Out-Json ([PSCustomObject]@{ ok = $true; features = $list; count = $list.Count })
    }
    elseif ($Action -eq "enable") {
        $feats = Get-WindowsOptionalFeature -Online -ErrorAction Stop | Where-Object { $_.State -ne "Enabled" }
        $targets = @()
        if ($Items -eq "all") { $targets = $feats } else {
            $idxs = $Items -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^\d+$" }
            $i = 0
            foreach ($f in $feats) { $i++; if ($idxs -contains [string]$i) { $targets += $f } }
        }
        $done = 0; $needReboot = $false; $details = @()
        foreach ($f in $targets) {
            try {
                $r = Enable-WindowsOptionalFeature -Online -FeatureName $f.FeatureName -All -NoRestart -ErrorAction Stop
                $done++
                if ($r.RestartNeeded) { $needReboot = $true }
                $details += [PSCustomObject]@{ name = $f.FeatureName; result = "已启用" }
            } catch {
                $details += [PSCustomObject]@{ name = $f.FeatureName; result = "失败: $($_.Exception.Message)" }
            }
        }
        Out-Json ([PSCustomObject]@{ ok = $true; enabled = $done; needReboot = $needReboot; details = $details })
    }
} catch {
    Out-Json ([PSCustomObject]@{ ok = $false; error = $_.Exception.Message })
}

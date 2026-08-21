<#
.SYNOPSIS
    WebUI 隐藏/恢复指定 Windows 更新 — 返回 JSON
.DESCRIPTION
    -Action list         : 列出待安装更新（可隐藏）
    -Action list-hidden  : 列出已隐藏更新
    -Action hide         : 隐藏指定序号(items=1,3 或 all)
    -Action show         : 恢复显示指定序号(items=1,3 或 all)
#>
param(
    [ValidateSet("list", "list-hidden", "hide", "show")]$Action = "list",
    [string]$Items = "all"
)

function Out-Json {
    param($obj)
    $obj | ConvertTo-Json -Depth 4 -Compress
}

$ErrorActionPreference = "Stop"

function Get-WUUpdates {
    param([bool]$IncludeHidden = $false)
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $criteria = if ($IncludeHidden) { "Type='Software'" } else { "IsInstalled=0 AND Type='Software'" }
    return $searcher.Search($criteria).Updates
}

try {
    if ($Action -eq "list") {
        $ups = Get-WUUpdates -IncludeHidden $false
        $list = @()
        $i = 0
        foreach ($u in $ups) { $i++; $list += [PSCustomObject]@{ index = $i; title = $u.Title; hidden = $false } }
        Out-Json ([PSCustomObject]@{ ok = $true; updates = $list; count = $list.Count })
    }
    elseif ($Action -eq "list-hidden") {
        $ups = Get-WUUpdates -IncludeHidden $true | Where-Object { $_.IsHidden }
        $list = @()
        $i = 0
        foreach ($u in $ups) { $i++; $list += [PSCustomObject]@{ index = $i; title = $u.Title; hidden = $true } }
        Out-Json ([PSCustomObject]@{ ok = $true; updates = $list; count = $list.Count })
    }
    elseif ($Action -eq "hide" -or $Action -eq "show") {
        $includeHidden = ($Action -eq "show")
        $ups = Get-WUUpdates -IncludeHidden $includeHidden
        if ($Action -eq "show") { $ups = $ups | Where-Object { $_.IsHidden } }
        $targets = @()
        if ($Items -eq "all") { $targets = $ups } else {
            $idxs = $Items -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^\d+$" }
            $i = 0
            foreach ($u in $ups) { $i++; if ($idxs -contains [string]$i) { $targets += $u } }
        }
        $cnt = 0; $details = @()
        foreach ($t in $targets) {
            try {
                if ($Action -eq "hide") { $t.IsHidden = $true; $details += [PSCustomObject]@{ title = $t.Title; result = "已隐藏" } }
                else { $t.IsHidden = $false; $details += [PSCustomObject]@{ title = $t.Title; result = "已恢复" } }
                $cnt++
            } catch { $details += [PSCustomObject]@{ title = $t.Title; result = "失败: $($_.Exception.Message)" } }
        }
        Out-Json ([PSCustomObject]@{ ok = $true; count = $cnt; details = $details })
    }
} catch {
    Out-Json ([PSCustomObject]@{ ok = $false; error = $_.Exception.Message })
}

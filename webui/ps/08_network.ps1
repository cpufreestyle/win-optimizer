<#
.SYNOPSIS
    WebUI 网络优化 — 列出 DNS/应用优化，返回 JSON
.DESCRIPTION
    -Action list : 返回当前各适配器 DNS
    -Action apply: 按选项设置 DNS、TCP 自动调优、RSS、RSC、刷新 DNS 缓存
#>
param(
    [ValidateSet("list", "apply")]$Action = "list",
    [int]$Dns = 0,           # 0=保持 1=Cloudflare 2=Google 3=阿里 4=114
    [bool]$Tcp = $true,
    [bool]$Rss = $true,
    [bool]$Rsc = $true,
    [bool]$DnsCache = $true
)

function Out-Json {
    param($obj)
    $obj | ConvertTo-Json -Depth 4 -Compress
}

$ErrorActionPreference = "Stop"

$dnsServers = @{
    1 = @("1.1.1.1", "1.0.0.1")
    2 = @("8.8.8.8", "8.8.4.4")
    3 = @("223.5.5.5", "223.6.6.6")
    4 = @("114.114.114.114", "114.114.115.115")
}

try {
    if ($Action -eq "list") {
        $adapters = @()
        try {
            $nets = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" }
            if ($nets) {
                foreach ($n in $nets) {
                    $addr = @()
                    try {
                        $addr = (Get-DnsClientServerAddress -InterfaceIndex $n.InterfaceIndex -ErrorAction SilentlyContinue | ForEach-Object { $_.ServerAddresses }) -join ', '
                    } catch {}
                    $adapters += [PSCustomObject]@{
                        name = $n.Name
                        dns = $addr
                    }
                }
            }
        } catch {}
        Out-Json ([PSCustomObject]@{ ok = $true; adapters = $adapters })
    }
    elseif ($Action -eq "apply") {
        $log = @()
        if ($Dns -gt 0 -and $dnsServers.ContainsKey($Dns)) {
            $servers = $dnsServers[$Dns]
            try {
                $nets = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" }
                foreach ($n in $nets) {
                    try {
                        Set-DnsClientServerAddress -InterfaceIndex $n.InterfaceIndex -ServerAddresses $servers -ErrorAction Stop
                        $log += "DNS [$n.Name] -> $($servers -join ', ')"
                    } catch { $log += "DNS [$n.Name] 失败: $($_.Exception.Message)" }
                }
            } catch { $log += "设置 DNS 失败: $($_.Exception.Message)" }
        } else {
            $log += "DNS 保持当前设置"
        }

        if ($Tcp) {
            try { netsh int tcp set global autotuninglevel=normal 2>&1 | Out-Null; $log += "TCP 自动调优已启用" }
            catch { $log += "TCP 自动调优失败" }
        }
        if ($Rss) {
            try { Enable-NetAdapterRss -Name (Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" }).Name -ErrorAction SilentlyContinue; $log += "RSS 接收端缩放已启用" }
            catch { $log += "RSS 启用失败" }
        }
        if ($Rsc) {
            try { Enable-NetAdapterRsc -Name (Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" }).Name -ErrorAction SilentlyContinue; $log += "RSC 接收段合并已启用" }
            catch { $log += "RSC 启用失败" }
        }
        if ($DnsCache) {
            try { Clear-DnsClientCache -ErrorAction SilentlyContinue; $log += "DNS 缓存已刷新" }
            catch { $log += "DNS 缓存刷新失败" }
        }

        Out-Json ([PSCustomObject]@{ ok = $true; log = $log })
    }
} catch {
    Out-Json ([PSCustomObject]@{ ok = $false; error = $_.Exception.Message })
}

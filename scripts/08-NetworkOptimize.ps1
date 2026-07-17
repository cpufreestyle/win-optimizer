<#
.SYNOPSIS
    网络优化模块 — 优化 DNS 与网络参数以提升网络响应速度
.DESCRIPTION
    - 设置公共快速 DNS (可选多个)
    - 启用 TCP 自动调优
    - 禁用 TCP 自动调优限制 (提升下载速度)
    - 优化网络适配器 RSS (接收端缩放)
    - 清除 DNS 缓存
    - 重置网络栈 (可选)
#>

. "$PSScriptRoot\Common.ps1"
Show-ModuleBanner "网络优化"

$config = Get-OptimizationConfig -ConfigPath (Join-Path $PSScriptRoot "..\config\optimization.json")

# --- 显示当前网络设置 ---
Write-Host "`n[1/4] 当前网络信息:" -ForegroundColor Yellow

$activeAdapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
if ($activeAdapter) {
    Write-Host "  活动适配器: $($activeAdapter.Name)" -ForegroundColor Gray
    Write-Host "  描述      : $($activeAdapter.InterfaceDescription)" -ForegroundColor Gray
    Write-Host "  链接速度  : $($activeAdapter.LinkSpeed)" -ForegroundColor Gray
    Write-Host "  MAC地址   : $($activeAdapter.MacAddress)" -ForegroundColor Gray
} else {
    Write-Host "  未检测到活动网络适配器" -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Cyan
    return
}

# 当前 DNS
$dnsServers = (Get-DnsClientServerAddress -InterfaceIndex $activeAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
Write-Host "  当前DNS   : $($dnsServers -join ', ')" -ForegroundColor Gray

# TCP 全局设置
Write-Host "`n  TCP 全局设置:" -ForegroundColor Gray
$tcpGlobal = Get-NetTCPSetting -SettingName Internet -ErrorAction SilentlyContinue
if ($tcpGlobal) {
    Write-Host "    自动调优   : $($tcpGlobal.AutoTuningLevelLocal)" -ForegroundColor Gray
    Write-Host "    RSS        : $($tcpGlobal.RSSProfile)" -ForegroundColor Gray
    Write-Host "    拥塞控制   : $($tcpGlobal.CongestionProvider)" -ForegroundColor Gray
}

$dnsPrimary = $null
$dnsSecondary = $null

# --- 选择 DNS ---
Write-Host "`n[2/4] 选择 DNS 服务器:" -ForegroundColor Yellow
Write-Host ""

if (-not $config) {
    Write-Host "  [错误] 配置文件缺失，跳过 DNS 设置。" -ForegroundColor Red
} else {
    $dns = $config.dns_options
    $menu = @(
        @{ Key = "aliyun";     Label = "阿里 DNS";       Note = "国内推荐" }
        @{ Key = "tencent";    Label = "腾讯 DNS";       Note = "国内推荐" }
        @{ Key = "114";        Label = "114 DNS";        Note = "" }
        @{ Key = "google";     Label = "Google DNS";     Note = "需翻墙" }
        @{ Key = "cloudflare"; Label = "Cloudflare DNS"; Note = "需翻墙" }
    )
    $idx = 1
    foreach ($m in $menu) {
        $servers = ($dns.$($m.Key) -join " / ")
        $note = if ($m.Note) { "— $($m.Note)" } else { "" }
        Write-Host "  [$idx] $($m.Label)  ($servers)  $note"
        $idx++
    }
    Write-Host "  [6] 阿里+Cloudflare  ($(($dns.aliyun)[0]) / $(($dns.cloudflare)[0]))  — 混合"
    Write-Host "  [0] 跳过 DNS 设置"
    $dnsChoice = Read-Host "选择 (0-6)"

    switch ($dnsChoice) {
        "1" { $dnsPrimary = ($dns.aliyun)[0];      $dnsSecondary = ($dns.aliyun)[1] }
        "2" { $dnsPrimary = ($dns.tencent)[0];     $dnsSecondary = ($dns.tencent)[1] }
        "3" { $dnsPrimary = ($dns.'114')[0];       $dnsSecondary = ($dns.'114')[1] }
        "4" { $dnsPrimary = ($dns.google)[0];      $dnsSecondary = ($dns.google)[1] }
        "5" { $dnsPrimary = ($dns.cloudflare)[0];  $dnsSecondary = ($dns.cloudflare)[1] }
        "6" { $dnsPrimary = ($dns.aliyun)[0];      $dnsSecondary = ($dns.cloudflare)[0] }
        "0" { Write-Host "  跳过 DNS 设置" -ForegroundColor Gray }
        default { Write-Host "  无效选择，跳过 DNS 设置" -ForegroundColor Yellow }
    }
}

if ($dnsPrimary) {
    Write-Host "`n  正在设置 DNS..." -ForegroundColor Yellow
    try {
        Set-DnsClientServerAddress -InterfaceIndex $activeAdapter.ifIndex -ServerAddresses @($dnsPrimary, $dnsSecondary) -ErrorAction Stop
        Write-Host "  [完成] DNS 已设置为: $dnsPrimary, $dnsSecondary" -ForegroundColor Green
    } catch {
        Write-Host "  [失败] DNS 设置失败: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- TCP 网络参数优化 ---
Write-Host "`n[3/4] TCP 网络参数优化..." -ForegroundColor Yellow

# 启用 TCP 自动调优 (提升网络吞吐量)
Write-Host "  [处理] TCP 自动调优..." -ForegroundColor Gray
try {
    Set-NetTCPSetting -SettingName Internet -AutoTuningLevelLocal Normal -ErrorAction SilentlyContinue
    Write-Host "  [完成] TCP 自动调优: Normal" -ForegroundColor Green
} catch {
    Write-Host "  [跳过] TCP 自动调优设置失败" -ForegroundColor Yellow
}

# 启用 RSS (接收端缩放) — 多核 CPU 网络处理优化
Write-Host "  [处理] 接收端缩放 (RSS)..." -ForegroundColor Gray
try {
    $rssCapable = Get-NetAdapterRss -Name $activeAdapter.Name -ErrorAction SilentlyContinue
    if ($rssCapable) {
        Enable-NetAdapterRss -Name $activeAdapter.Name -ErrorAction SilentlyContinue
        Write-Host "  [完成] RSS 已启用" -ForegroundColor Green
    } else {
        Write-Host "  [跳过] 网卡不支持 RSS" -ForegroundColor Gray
    }
} catch {
    Write-Host "  [跳过] RSS 设置失败" -ForegroundColor Yellow
}

# 启用 RSC (接收段合并) — 减少 CPU 中断
Write-Host "  [处理] 接收段合并 (RSC)..." -ForegroundColor Gray
try {
    $rscCapable = Get-NetAdapterRsc -Name $activeAdapter.Name -ErrorAction SilentlyContinue
    if ($rscCapable) {
        Enable-NetAdapterRsc -Name $activeAdapter.Name -ErrorAction SilentlyContinue
        Write-Host "  [完成] RSC 已启用" -ForegroundColor Green
    } else {
        Write-Host "  [跳过] 网卡不支持 RSC" -ForegroundColor Gray
    }
} catch {
    Write-Host "  [跳过] RSC 设置失败" -ForegroundColor Yellow
}

# 设置网卡中断裁决 (减少 CPU 中断)
Write-Host "  [处理] 网卡高级属性优化..." -ForegroundColor Gray
try {
    # 启用大型发送卸载 (LSO) — 减少 CPU 负载
    Set-NetAdapterAdvancedProperty -Name $activeAdapter.Name -RegistryKeyword "*LSO" -RegistryValue 1 -ErrorAction SilentlyContinue
    Write-Host "  [完成] LSO (大型发送卸载): 已启用" -ForegroundColor Green
} catch {
    Write-Host "  [跳过] LSO 设置" -ForegroundColor Gray
}

try {
    # 启用节能以太网 (EEE) — 某些网卡可降低功耗但对性能有影响
    # 对于老电脑追求性能，禁用 EEE
    Set-NetAdapterAdvancedProperty -Name $activeAdapter.Name -RegistryKeyword "*EEE" -RegistryValue 0 -ErrorAction SilentlyContinue
    Write-Host "  [完成] EEE (节能以太网): 已禁用 (优先性能)" -ForegroundColor Green
} catch {
    Write-Host "  [跳过] EEE 设置" -ForegroundColor Gray
}

# --- 清除 DNS 缓存并重置 ---
Write-Host "`n[4/4] 清除 DNS 缓存..." -ForegroundColor Yellow
try {
    ipconfig /flushdns | Out-Null
    Write-Host "  [完成] DNS 缓存已清除" -ForegroundColor Green
} catch {
    Write-Host "  [跳过] DNS 缓存清除失败" -ForegroundColor Yellow
}

# 可选: 重置 Winsock 和 IP 栈
Write-Host ""
$resetChoice = Read-Host "是否重置网络栈 (Winsock/IP)? 可修复网络问题但会断开连接 (Y/N)"
if ($resetChoice -eq "Y" -or $resetChoice -eq "y") {
    Write-Host "  [处理] 重置 Winsock..." -ForegroundColor Yellow
    netsh winsock reset 2>&1 | Out-Null
    Write-Host "  [处理] 重置 TCP/IP 栈..." -ForegroundColor Yellow
    netsh int ip reset 2>&1 | Out-Null
    Write-Host "  [处理] 释放并重新获取 IP..." -ForegroundColor Yellow
    ipconfig /release 2>&1 | Out-Null
    ipconfig /renew 2>&1 | Out-Null
    Write-Host "  [完成] 网络栈已重置，需要重启电脑生效" -ForegroundColor Green
}

# --- 验证 ---
Write-Host "`n优化后网络状态:" -ForegroundColor Yellow
$updatedDns = (Get-DnsClientServerAddress -InterfaceIndex $activeAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
Write-Host "  DNS: $($updatedDns -join ', ')" -ForegroundColor Green

# 测试 DNS 响应
Write-Host "`n  DNS 响应测试:" -ForegroundColor Gray
$testDomains = @("www.baidu.com", "www.bing.com")
foreach ($domain in $testDomains) {
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Resolve-DnsName -Name $domain -ErrorAction Stop | Select-Object -First 1
        $sw.Stop()
        Write-Host "    $domain -> $($result.IPAddress) ($([math]::Round($sw.Elapsed.TotalMilliseconds, 0))ms)" -ForegroundColor Green
    } catch {
        Write-Host "    $domain -> 解析失败" -ForegroundColor Red
    }
}

Show-ModuleFooter "网络优化完成！" -Lines @(
    "  如更改了网络栈，请重启电脑使所有更改生效"
)

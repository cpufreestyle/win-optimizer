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

# 复用共享核心库（网络统一实现，与 GUI / WebUI 同源）
$coreLib = Join-Path $PSScriptRoot "..\lib\Optimize.Core.ps1"
if (Test-Path $coreLib) { . $coreLib }
if (-not (Get-Command Invoke-NetworkOptimization -ErrorAction SilentlyContinue)) {
    Write-Host "错误：未找到共享核心库 lib\Optimize.Core.ps1，无法执行网络优化。" -ForegroundColor Red
    return
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "         网络优化" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# --- 显示当前网络设置 ---
Write-Host "`n[1/4] 当前网络信息:" -ForegroundColor Yellow

# 统一走共享库：自动排除虚拟/隧道类网卡（避免误改 VPN 导致断网），
# 并在无 NetAdapter cmdlet 的老系统上回退 CIM。
$adapters = @(Get-ActiveNetAdapters)
if ($adapters.Count -eq 0) {
    Write-Host "  未检测到活动网络适配器" -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Cyan
    return
}
$activeAdapter = $adapters[0]

foreach ($a in $adapters) {
    Write-Host "  活动适配器: $($a.Name)" -ForegroundColor Gray
    Write-Host "  描述      : $($a.Description)" -ForegroundColor Gray
    Write-Host "  链接速度  : $($a.LinkSpeed)" -ForegroundColor Gray
    Write-Host "  MAC地址   : $($a.MacAddress)" -ForegroundColor Gray
    Write-Host "  当前DNS   : $((@(Get-AdapterDns -IfIndex $a.IfIndex -Name $a.Name)) -join ', ')" -ForegroundColor Gray
}

# TCP 全局设置
Write-Host "`n  TCP 全局设置:" -ForegroundColor Gray
$tcpGlobal = Get-NetTCPSetting -SettingName Internet -ErrorAction SilentlyContinue
if ($tcpGlobal) {
    Write-Host "    自动调优   : $($tcpGlobal.AutoTuningLevelLocal)" -ForegroundColor Gray
    Write-Host "    RSS        : $($tcpGlobal.RSSProfile)" -ForegroundColor Gray
    Write-Host "    拥塞控制   : $($tcpGlobal.CongestionProvider)" -ForegroundColor Gray
}

# --- 选择 DNS ---
Write-Host "`n[2/4] 选择 DNS 服务器:" -ForegroundColor Yellow
Write-Host ""

# DNS 选项统一由共享库提供。
# 编号保持稳定（1=Cloudflare / 2=Google / 3=阿里 / 4=114 / 5=腾讯）——WebUI 前端硬编码了编号，
# 改动会直接破坏界面；config/optimization.json 的 dns_options 只覆盖"地址"，不改编号。
$dnsOptions = @(Get-DnsOptions)

foreach ($o in $dnsOptions) {
    Write-Host ("  [{0}] {1,-16} ({2} / {3})" -f $o.Value, $o.Label, $o.Primary, $o.Secondary)
}
Write-Host "  [0] 跳过 DNS 设置"
$dnsChoice = Read-Host "选择 (0-$($dnsOptions.Count))"

# 规范化为整数：0=保持当前，1..N=对应选项；无效输入一律当作"保持当前"
if ($dnsChoice -notmatch '^\d+$') {
    $dnsChoice = 0
} else {
    $dnsChoice = [int]$dnsChoice
    if ($dnsChoice -gt $dnsOptions.Count) { $dnsChoice = 0 }
}
if ($dnsChoice -eq 0) { Write-Host "  跳过 DNS 设置" -ForegroundColor Gray }

# --- 备份 + 应用网络优化（统一走共享库，与 GUI / WebUI 同一份实现）---
# 此前 CLI 只改"第一个"活动适配器，GUI/WebUI 改全部；现统一为全部活动物理网卡
# （虚拟/隧道类网卡由共享库自动排除，避免误改 VPN 导致断网）。
$netBackupDir = Join-Path (Split-Path -Parent $PSScriptRoot) "backups"

Write-Host "`n[3/4] 应用网络优化..." -ForegroundColor Yellow
$r = Invoke-NetworkOptimization -BackupDir $netBackupDir -DnsOption $dnsChoice
foreach ($d in $r.details) { Write-Host "  [完成] $d" -ForegroundColor Green }
if ($r.backup) { Write-Host "  [备份] 网络设置已备份: $($r.backup)" -ForegroundColor DarkGray }
if (-not $r.ok) { Write-Host "  部分设置失败（可能需要管理员权限）" -ForegroundColor Yellow }

# 网卡高级属性（LSO / EEE）为 CLI 侧附加项，逐适配器应用
Write-Host "  [处理] 网卡高级属性优化..." -ForegroundColor Gray
foreach ($a in $adapters) {
    try {
        # 启用大型发送卸载 (LSO) — 减少 CPU 负载
        Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword "*LSO" -RegistryValue 1 -ErrorAction SilentlyContinue
        Write-Host "  [完成] LSO (大型发送卸载): $($a.Name)" -ForegroundColor Green
    } catch {
        Write-Host "  [跳过] LSO 设置 ($($a.Name))" -ForegroundColor Gray
    }
    try {
        # 禁用节能以太网 (EEE) — 老电脑优先性能
        Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword "*EEE" -RegistryValue 0 -ErrorAction SilentlyContinue
        Write-Host "  [完成] EEE (节能以太网): 已禁用 $($a.Name)" -ForegroundColor Green
    } catch {
        Write-Host "  [跳过] EEE 设置 ($($a.Name))" -ForegroundColor Gray
    }
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

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  网络优化完成！" -ForegroundColor Green
Write-Host "  如更改了网络栈，请重启电脑使所有更改生效" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan

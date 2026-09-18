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


# 统一 stdout 为 UTF-8（让 Python subprocess.run 按 utf-8 解码时不乱码；与 OptimizeGUI 同款）
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
function Out-Json {
    param($obj)
    $obj | ConvertTo-Json -Depth 4 -Compress
}

$ErrorActionPreference = "Stop"

# 复用共享核心库（网络统一实现，与 CLI / GUI 同源）
$libPath = Join-Path $PSScriptRoot "..\..\lib\Optimize.Core.ps1"
if (Test-Path $libPath) { . $libPath }
$backupDir = Join-Path $PSScriptRoot "..\..\backups"
$backupDir = [System.IO.Path]::GetFullPath($backupDir)

try {
    if ($Action -eq "list") {
        $adapters = @()
        foreach ($n in (Get-ActiveNetAdapters)) {
            $addr = (@(Get-AdapterDns -IfIndex $n.IfIndex -Name $n.Name)) -join ', '
            $adapters += [PSCustomObject]@{
                name = $n.Name
                dns  = $addr
            }
        }
        Out-Json ([PSCustomObject]@{ ok = $true; adapters = $adapters })
    }
    elseif ($Action -eq "apply") {
        # 统一走共享库：先备份再应用。
        # 此前 WebUI 改 DNS 完全没有备份（改坏无法恢复），且把活动适配器数组直接传给
        # Enable-NetAdapterRss -Name（多网卡时行为不可预期）——一并修复。
        $r = Invoke-NetworkOptimization -BackupDir $backupDir -DnsOption $Dns `
                                        -Tcp $Tcp -Rss $Rss -Rsc $Rsc -DnsCache $DnsCache
        $log = @($r.details)
        # error 字段此前从未回传：无活动网卡时前端只会收到空日志
        if ($r.error) { $log += $r.error }
        if ($r.backup) { $log += "备份: $($r.backup)" }
        Out-Json ([PSCustomObject]@{ ok = $r.ok; log = $log; backup = $r.backup })
    }
} catch {
    Out-Json ([PSCustomObject]@{ ok = $false; error = $_.Exception.Message })
}

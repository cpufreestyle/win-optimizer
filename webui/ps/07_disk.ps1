<#
.SYNOPSIS
    WebUI 磁盘优化 — 列出磁盘/优化，返回 JSON
.DESCRIPTION
    -Action list    : 列出物理磁盘及类型（SSD/HDD）
    -Action optimize: 按选项执行 TRIM / 碎片整理 / 清理 WinSxS / CompactOS
#>
param(
    [ValidateSet("list", "optimize")]$Action = "list",
    [bool]$Trim = $true,
    [bool]$Defrag = $true,
    [bool]$WinSxS = $true,
    [bool]$Compact = $false
)


# 统一 stdout 为 UTF-8（让 Python subprocess.run 按 utf-8 解码时不乱码；与 OptimizeGUI 同款）
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
function Out-Json {
    param($obj)
    $obj | ConvertTo-Json -Depth 4 -Compress
}

$ErrorActionPreference = "Stop"

# 复用共享核心库（磁盘统一实现，与 CLI / GUI 同源）
$libPath = Join-Path $PSScriptRoot "..\..\lib\Optimize.Core.ps1"
if (Test-Path $libPath) { . $libPath }

try {
    if ($Action -eq "list") {
        $disks = @()
        foreach ($d in (Get-PhysicalDiskInfo)) {
            $disks += [PSCustomObject]@{
                name   = $d.FriendlyName
                type   = $d.MediaType
                sizeGB = if ($d.Size) { [math]::Round([double]$d.Size / 1GB, 0) } else { 0 }
            }
        }
        Out-Json ([PSCustomObject]@{ ok = $true; disks = $disks })
    }
    elseif ($Action -eq "optimize") {
        # CompactOS 默认值与 CLI / GUI 同源：config 的 disk.compact_os_default（默认 false）。
        # 前端传 compact=true 才压缩；未传时按配置默认（而非硬编码 true）。
        $compactEnabled = if ($Compact) { $true } else { Get-CompactOSDefault }
        # 统一走共享库：
        #  - 此前用 Storage 模块（Get-Volume / Optimize-Volume），该模块在 Win7 上不存在；
        #  - 且对每个卷同时执行 TRIM 和碎片整理，不区分 SSD/HDD（对 SSD 整理会损耗寿命）。
        # 现在统一为 WMI + defrag.exe（Win7 兼容），并按介质分流：SSD→TRIM，HDD→碎片整理。
        $r = Invoke-DiskOptimization -Trim $Trim -Defrag $Defrag -WinSxS $WinSxS -Compact $compactEnabled
        Out-Json ([PSCustomObject]@{ ok = $r.ok; log = @($r.details) })
    }
} catch {
    Out-Json ([PSCustomObject]@{ ok = $false; error = $_.Exception.Message })
}

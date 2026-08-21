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

function Out-Json {
    param($obj)
    $obj | ConvertTo-Json -Depth 4 -Compress
}

$ErrorActionPreference = "Stop"

try {
    if ($Action -eq "list") {
        $disks = @()
        try {
            $pd = Get-PhysicalDisk -ErrorAction SilentlyContinue
            if ($pd) {
                foreach ($d in $pd) {
                    $sizeGB = if ($d.Size) { [math]::Round([double]$d.Size / 1GB, 0) } else { 0 }
                    $disks += [PSCustomObject]@{
                        name = $d.FriendlyName
                        type = [string]$d.MediaType
                        sizeGB = $sizeGB
                    }
                }
            }
        } catch {}
        Out-Json ([PSCustomObject]@{ ok = $true; disks = $disks })
    }
    elseif ($Action -eq "optimize") {
        $log = @()
        # 收集卷
        $volumes = @()
        try {
            $vols = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter }
            if ($vols) { $volumes = $vols }
        } catch {}

        if ($Trim -or $Defrag) {
            foreach ($vol in $volumes) {
                $drive = "$($vol.DriveLetter):"
                try {
                    if ($Trim) {
                        Optimize-Volume -DriveLetter $vol.DriveLetter -ReTrim -ErrorAction Stop
                        $log += "TRIM $drive 完成"
                    }
                } catch { $log += "TRIM $drive 跳过: $($_.Exception.Message)" }
                try {
                    if ($Defrag) {
                        Optimize-Volume -DriveLetter $vol.DriveLetter -Defrag -ErrorAction Stop
                        $log += "碎片整理 $drive 完成"
                    }
                } catch { $log += "碎片整理 $drive 跳过: $($_.Exception.Message)" }
            }
        }

        if ($WinSxS) {
            try {
                $out = Dism.exe /Online /Cleanup-Image /StartComponentCleanup 2>&1 | Out-String
                $log += "WinSxS 组件清理完成"
            } catch { $log += "WinSxS 清理失败: $($_.Exception.Message)" }
        }

        if ($Compact) {
            try {
                Compact.exe /CompactOS:always 2>&1 | Out-Null
                $log += "系统文件压缩完成"
            } catch { $log += "系统压缩失败: $($_.Exception.Message)" }
        }

        Out-Json ([PSCustomObject]@{ ok = $true; log = $log })
    }
} catch {
    Out-Json ([PSCustomObject]@{ ok = $false; error = $_.Exception.Message })
}

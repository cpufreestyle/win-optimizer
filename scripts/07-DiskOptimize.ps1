<#
.SYNOPSIS
    磁盘优化模块 — 磁盘清理与碎片整理/SSD优化
.DESCRIPTION
    - 检测磁盘类型 (SSD/HDD)
    - SSD: 执行 TRIM 优化
    - HDD: 执行碎片整理
    - 清理系统组件 (WinSxS)
    - 压缩系统文件
    注意：本脚本不使用 Storage 模块 (Get-Volume/Get-PhysicalDisk/Optimize-Volume)，
          改用 WMI + defrag.exe + fsutil，以兼容 Storage 模块损坏的环境。
#>

# --- 兼容辅助函数（不使用 Storage 模块）---
function Get-PhysicalDisksCompat {
    $disks = @()
    try {
        $drives = @(Get-WmiObject -Class Win32_DiskDrive -ErrorAction SilentlyContinue)
        foreach ($d in $drives) {
            $media = "Unknown"
            if ($d.MediaType -match "SSD|Solid State") { $media = "SSD" }
            elseif ($d.MediaType -match "Fixed|Hard|HDD") { $media = "HDD" }
            $disks += [PSCustomObject]@{
                DeviceId     = $d.Index
                FriendlyName = $d.Model
                MediaType    = $media
                Size         = $d.Size
                BusType      = "N/A"
            }
        }
    } catch {}
    return $disks
}

function Get-FixedVolumesCompat {
    $vols = @()
    try {
        $lds = @(Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue)
        foreach ($ld in $lds) {
            $vols += [PSCustomObject]@{
                DriveLetter    = $ld.DeviceID.Substring(0, 1)
                Size           = $ld.Size
                SizeRemaining  = $ld.FreeSpace
            }
        }
    } catch {}
    return $vols
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "         磁盘优化" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# --- 获取磁盘信息 ---
Write-Host "`n[1/3] 检测磁盘信息..." -ForegroundColor Yellow

$physicalDisks = Get-PhysicalDisksCompat
$volumes = Get-FixedVolumesCompat

# 构建 盘符 -> 磁盘类型 映射（通过 Win32_LogicalDiskToPartition -> DiskDrive）
$driveMediaMap = @{}
try {
    $assoc = @(Get-WmiObject -Class Win32_LogicalDiskToPartition -ErrorAction SilentlyContinue)
    $parts = @(Get-WmiObject -Class Win32_DiskDriveToDiskPartition -ErrorAction SilentlyContinue)
    foreach ($a in $assoc) {
        $ld = $a.Dependent.Split('=')[1].Trim('"')
        $part = $a.Antecedent
        $partName = ($part -split '"')[1]
        foreach ($p in $parts) {
            if ($p.Antecedent -match [regex]::Escape($partName)) {
                $diskIdx = ($p.Dependent -split '"')[1] -replace '.*#(\d+)$', '$1'
                $disk = $physicalDisks | Where-Object { "$($_.DeviceId)" -eq $diskIdx }
                if ($disk) { $driveMediaMap[$ld.Substring(0,1)] = $disk.MediaType }
            }
        }
    }
} catch {}

Write-Host ""
Write-Host "  物理磁盘:" -ForegroundColor Gray
foreach ($disk in $physicalDisks) {
    $sizeGB = if ($disk.Size) { [math]::Round($disk.Size / 1GB, 0) } else { 0 }
    Write-Host "    磁盘$($disk.DeviceId): $($disk.FriendlyName) | $($disk.MediaType) | ${sizeGB}GB"
}

Write-Host ""
Write-Host "  逻辑卷:" -ForegroundColor Gray
foreach ($vol in $volumes) {
    $totalGB = if ($vol.Size) { [math]::Round($vol.Size / 1GB, 1) } else { 0 }
    $freeGB  = if ($vol.SizeRemaining) { [math]::Round($vol.SizeRemaining / 1GB, 1) } else { 0 }
    $usage   = if ($vol.Size -gt 0) { [math]::Round((1 - $vol.SizeRemaining / $vol.Size) * 100, 1) } else { 0 }
    Write-Host "    $($vol.DriveLetter): ${totalGB}GB 总计 | ${freeGB}GB 可用 | 已用 ${usage}%"
}

# --- 系统组件清理 ---
Write-Host "`n[2/3] 系统组件清理..." -ForegroundColor Yellow

# 清理 WinSxS 组件存储
Write-Host "  [处理] 分析 WinSxS 组件存储..." -ForegroundColor Yellow
try {
    $analysis = Dism.exe /Online /Cleanup-Image /AnalyzeComponentStore 2>&1
    $analysis | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

    Write-Host "  [处理] 清理 WinSxS 组件存储..." -ForegroundColor Yellow
    Dism.exe /Online /Cleanup-Image /StartComponentCleanup 2>&1 | ForEach-Object {
        Write-Host "    $_" -ForegroundColor DarkGray
    }
    Write-Host "  [完成] WinSxS 组件存储清理完成" -ForegroundColor Green
} catch {
    Write-Host "  [跳过] WinSxS 清理失败" -ForegroundColor Gray
}

# 压缩系统文件 (释放更多空间)
Write-Host "`n  [处理] 压缩系统文件..." -ForegroundColor Yellow
try {
    Compact.exe /CompactOS:always 2>&1 | ForEach-Object {
        Write-Host "    $_" -ForegroundColor DarkGray
    }
    Write-Host "  [完成] 系统文件压缩完成" -ForegroundColor Green
} catch {
    Write-Host "  [跳过] 系统文件压缩失败" -ForegroundColor Gray
}

# --- 磁盘优化/TRIM ---
Write-Host "`n[3/3] 磁盘优化..." -ForegroundColor Yellow

foreach ($vol in $volumes) {
    $driveLetter = "$($vol.DriveLetter):"

    # 判断磁盘类型：优先用 WMI 关联结果，未知时尝试用 defrag 报告的媒体类型
    $mediaType = $driveMediaMap[$vol.DriveLetter]
    if (-not $mediaType -or $mediaType -eq "Unknown") {
        # 用 defrag /A 输出推断（SSD 通常包含 "已优化"/"无需"/媒体类型提示）
        try {
            $info = defrag.exe $driveLetter /I /U /V 2>&1 | Out-String
            if ($info -match "SSD|固态") { $mediaType = "SSD" }
            elseif ($info -match "HDD|硬盘|机械") { $mediaType = "HDD" }
            else { $mediaType = "HDD" }  # 保守默认按 HDD 处理（碎片整理无害）
        } catch { $mediaType = "HDD" }
    }

    Write-Host ""
    Write-Host "  处理驱动器 $driveLetter ($mediaType)..." -ForegroundColor Yellow

    if ($mediaType -eq "SSD") {
        Write-Host "    SSD 检测到，执行 TRIM 优化..." -ForegroundColor Gray
        try {
            defrag.exe $driveLetter /L /O /U /V 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
            Write-Host "  [完成] $driveLetter TRIM 优化完成" -ForegroundColor Green
        } catch {
            Write-Host "  [跳过] $driveLetter TRIM 优化失败" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "    HDD 检测到，执行碎片整理..." -ForegroundColor Gray
        try {
            Write-Host "    [分析] $driveLetter ..." -ForegroundColor Gray
            defrag.exe $driveLetter /A /U /V 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
            Write-Host "    [整理] $driveLetter ..." -ForegroundColor Gray
            defrag.exe $driveLetter /U /V 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
            Write-Host "  [完成] $driveLetter 碎片整理完成" -ForegroundColor Green
        } catch {
            Write-Host "  [跳过] $driveLetter 碎片整理失败" -ForegroundColor Yellow
        }
    }
}

# --- 显示优化后磁盘状态 ---
Write-Host "`n优化后磁盘状态:" -ForegroundColor Yellow
$updatedVolumes = Get-FixedVolumesCompat
foreach ($vol in $updatedVolumes) {
    $totalGB = if ($vol.Size) { [math]::Round($vol.Size / 1GB, 1) } else { 0 }
    $freeGB  = if ($vol.SizeRemaining) { [math]::Round($vol.SizeRemaining / 1GB, 1) } else { 0 }
    Write-Host "  $($vol.DriveLetter): ${totalGB}GB 总计 | ${freeGB}GB 可用"
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  磁盘优化完成！" -ForegroundColor Green
Write-Host "  SSD 已执行 TRIM | HDD 已执行碎片整理" -ForegroundColor Gray
Write-Host "  系统组件已清理并压缩" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan

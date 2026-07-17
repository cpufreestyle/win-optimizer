<#
.SYNOPSIS
    磁盘优化模块 — 磁盘清理与碎片整理/SSD优化
.DESCRIPTION
    - 检测磁盘类型 (SSD/HDD)
    - SSD: 执行 TRIM 优化
    - HDD: 执行碎片整理
    - 清理系统组件 (WinSxS)
    - 压缩系统文件
#>

. "$PSScriptRoot\Common.ps1"
Show-ModuleBanner "磁盘优化"

# --- 获取磁盘信息 ---
Write-Host "`n[1/3] 检测磁盘信息..." -ForegroundColor Yellow

try {
    $physicalDisks = Get-PhysicalDisk -ErrorAction Stop | Select-Object DeviceId, FriendlyName, MediaType, Size, BusType
} catch {
    Write-Host "    无法获取物理磁盘信息（需要 Storage 模块或管理员权限），将按未知类型处理。" -ForegroundColor Gray
    $physicalDisks = @()
}
$volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq "Fixed" }

Write-Host ""
Write-Host "  物理磁盘:" -ForegroundColor Gray
foreach ($disk in $physicalDisks) {
    $sizeGB = [math]::Round($disk.Size / 1GB, 0)
    Write-Host "    磁盘$($disk.DeviceId): $($disk.FriendlyName) | $($disk.MediaType) | ${sizeGB}GB | $($disk.BusType)"
}

Write-Host ""
Write-Host "  逻辑卷:" -ForegroundColor Gray
foreach ($vol in $volumes) {
    $totalGB = [math]::Round($vol.Size / 1GB, 1)
    $freeGB  = [math]::Round($vol.SizeRemaining / 1GB, 1)
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

    # 查找对应的物理磁盘类型
    $partition = Get-Partition -DriveLetter $vol.DriveLetter -ErrorAction SilentlyContinue
    if ($partition) {
        $diskNumber = $partition.DiskNumber
        $physicalDisk = $physicalDisks | Where-Object { $_.DeviceId -eq $diskNumber }
        $mediaType = $physicalDisk.MediaType
    } else {
        $mediaType = "Unknown"
    }

    Write-Host ""
    Write-Host "  处理驱动器 $driveLetter ($mediaType)..." -ForegroundColor Yellow

    if ($mediaType -eq "SSD") {
        # SSD: 执行 TRIM (Retrim)
        Write-Host "    SSD 检测到，执行 TRIM 优化..." -ForegroundColor Gray
        try {
            Optimize-Volume -DriveLetter $vol.DriveLetter -ReTrim -Verbose -ErrorAction Stop 2>&1 | ForEach-Object {
                Write-Host "    $_" -ForegroundColor DarkGray
            }
            Write-Host "  [完成] $driveLetter TRIM 优化完成" -ForegroundColor Green
        } catch {
            Write-Host "  [跳过] $driveLetter TRIM 优化失败" -ForegroundColor Yellow
        }
    }
    elseif ($mediaType -eq "HDD") {
        # HDD: 碎片整理
        Write-Host "    HDD 检测到，执行碎片整理..." -ForegroundColor Gray
        try {
            # 先分析
            $defragAnalysis = Optimize-Volume -DriveLetter $vol.DriveLetter -Analyze -Verbose -ErrorAction Stop 2>&1
            $defragAnalysis | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

            # 执行碎片整理
            Optimize-Volume -DriveLetter $vol.DriveLetter -Defrag -Verbose -ErrorAction Stop 2>&1 | ForEach-Object {
                Write-Host "    $_" -ForegroundColor DarkGray
            }
            Write-Host "  [完成] $driveLetter 碎片整理完成" -ForegroundColor Green
        } catch {
            Write-Host "  [跳过] $driveLetter 碎片整理失败" -ForegroundColor Yellow
        }
    }
    else {
        # 未知类型，尝试常规优化
        Write-Host "    磁盘类型未知，执行常规优化..." -ForegroundColor Gray
        try {
            Optimize-Volume -DriveLetter $vol.DriveLetter -Verbose -ErrorAction SilentlyContinue 2>&1 | ForEach-Object {
                Write-Host "    $_" -ForegroundColor DarkGray
            }
            Write-Host "  [完成] $driveLetter 优化完成" -ForegroundColor Green
        } catch {
            Write-Host "  [跳过] $driveLetter 优化失败" -ForegroundColor Yellow
        }
    }
}

# --- 显示优化后磁盘状态 ---
Write-Host "`n优化后磁盘状态:" -ForegroundColor Yellow
$updatedVolumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq "Fixed" }
foreach ($vol in $updatedVolumes) {
    $totalGB = [math]::Round($vol.Size / 1GB, 1)
    $freeGB  = [math]::Round($vol.SizeRemaining / 1GB, 1)
    Write-Host "  $($vol.DriveLetter): ${totalGB}GB 总计 | ${freeGB}GB 可用"
}

Show-ModuleFooter "磁盘优化完成！" -Lines @(
    "  SSD 已执行 TRIM | HDD 已执行碎片整理"
    "  系统组件已清理并压缩"
)

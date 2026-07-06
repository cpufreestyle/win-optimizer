<#
.SYNOPSIS
    临时文件清理模块 — 清理系统/用户临时文件、缓存、日志
.DESCRIPTION
    清理以下内容：
    - Windows 临时文件夹
    - 用户临时文件夹
    - Windows 更新缓存
    - 预读取文件
    - 缩略图缓存
    - Windows 日志（旧）
    - 回收站
    - DNS 缓存
    - 内存转储文件
#>

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "         临时文件清理" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

$totalFreed = 0
$filesDeleted = 0

function Get-FolderSize {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    try {
        $size = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($null -eq $size) { return 0 }
        return $size
    } catch { return 0 }
}

function Clean-Folder {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path $Path)) {
        Write-Host "  [跳过] $Label (路径不存在)" -ForegroundColor Gray
        return
    }
    $beforeSize = Get-FolderSize $Path
    try {
        Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                $script:filesDeleted++
            } catch {}
        }
        $afterSize = Get-FolderSize $Path
        $freed = $beforeSize - $afterSize
        $script:totalFreed += $freed
        $freedMB = [math]::Round($freed / 1MB, 2)
        Write-Host "  [完成] $Label : 释放 ${freedMB} MB" -ForegroundColor Green
    } catch {
        Write-Host "  [错误] $Label : $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n正在清理临时文件，请稍候...`n" -ForegroundColor Yellow

# 1. Windows 临时文件夹 (系统级)
Clean-Folder "C:\Windows\Temp" "Windows Temp (系统)"

# 2. 用户临时文件夹
$userTemp = $env:TEMP
Clean-Folder $userTemp "用户 Temp"

# 3. 预读取文件
Clean-Folder "C:\Windows\Prefetch" "Prefetch 预读取"

# 4. Windows 更新下载缓存 (SoftwareDistribution\Download)
Write-Host "  [处理] Windows 更新缓存..." -ForegroundColor Yellow
try {
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    Clean-Folder "C:\Windows\SoftwareDistribution\Download" "Windows Update 下载缓存"
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue
} catch {
    Write-Host "  [跳过] Windows Update 缓存 (服务无法停止)" -ForegroundColor Gray
}

# 5. Windows 旧版日志
Clean-Folder "C:\Windows\Logs\CBS" "CBS 日志"

# 6. 缩略图缓存
$thumbCachePath = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Explorer"
if (Test-Path $thumbCachePath) {
    $beforeSize = Get-FolderSize $thumbCachePath
    Get-ChildItem -Path $thumbCachePath -Filter "thumbcache_*.db" -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
    }
    Get-ChildItem -Path $thumbCachePath -Filter "iconcache_*.db" -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
    }
    $afterSize = Get-FolderSize $thumbCachePath
    $freed = $beforeSize - $afterSize
    $script:totalFreed += $freed
    Write-Host "  [完成] 缩略图缓存 : 释放 $([math]::Round($freed / 1MB, 2)) MB" -ForegroundColor Green
}

# 7. 清空回收站
Write-Host "  [处理] 清空回收站..." -ForegroundColor Yellow
try {
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Write-Host "  [完成] 回收站已清空" -ForegroundColor Green
} catch {
    Write-Host "  [跳过] 回收站清空" -ForegroundColor Gray
}

# 8. 清除 DNS 缓存
Write-Host "  [处理] 清除 DNS 缓存..." -ForegroundColor Yellow
try {
    ipconfig /flushdns | Out-Null
    Write-Host "  [完成] DNS 缓存已清除" -ForegroundColor Green
} catch {
    Write-Host "  [跳过] DNS 缓存" -ForegroundColor Gray
}

# 9. 内存转储文件
Write-Host "  [处理] 内存转储文件..." -ForegroundColor Yellow
$dumpFiles = @("C:\Windows\MEMORY.DMP")
$dumpFiles += (Get-ChildItem "C:\Windows\Minidump" -ErrorAction SilentlyContinue).FullName
foreach ($dump in $dumpFiles) {
    if ($dump -and (Test-Path $dump)) {
        $size = (Get-Item $dump).Length
        Remove-Item $dump -Force -ErrorAction SilentlyContinue
        $script:totalFreed += $size
        Write-Host "  [完成] 删除转储文件: $(Split-Path $dump -Leaf)" -ForegroundColor Green
    }
}

# 10. Windows 错误报告
Clean-Folder (Join-Path $env:PROGRAMDATA "Microsoft\Windows\WER") "Windows 错误报告"

# 11. 传递优化文件 (Delivery Optimization)
Clean-Folder (Join-Path $env:WINDIR "SoftwareDistribution\DeliveryOptimization") "传递优化缓存"

# 12. 旧版 Windows 更新文件
try {
    $oldWin = "C:\Windows.old"
    if (Test-Path $oldWin) {
        $oldSize = Get-FolderSize $oldWin
        Write-Host "  [发现] C:\Windows.old 占用 $([math]::Round($oldSize / 1GB, 2)) GB" -ForegroundColor Yellow
        Write-Host "         如需删除，请运行: 系统设置 -> 存储 -> 临时文件 -> 删除以前版本的 Windows" -ForegroundColor Gray
    }
} catch {}

# --- 总结 ---
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
$totalMB = [math]::Round($script:totalFreed / 1MB, 2)
$totalGB = [math]::Round($script:totalFreed / 1GB, 2)
if ($totalGB -ge 1) {
    Write-Host "  清理完成！共释放 ${totalGB} GB 空间" -ForegroundColor Green
} else {
    Write-Host "  清理完成！共释放 ${totalMB} MB 空间" -ForegroundColor Green
}
Write-Host "  删除文件数: $script:filesDeleted" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan

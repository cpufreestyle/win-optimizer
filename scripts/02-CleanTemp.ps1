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
$filesFailed = 0
$script:CleanFailedPaths = [System.Collections.Generic.List[string]]::new()
$script:CleanFailedFolders = @{}

# 复用共享核心库（Get-FolderSize / Remove-FolderContent 等）
$coreLib = Join-Path $PSScriptRoot "..\lib\Optimize.Core.ps1"
if (Test-Path $coreLib) { . $coreLib }

function Clean-Folder {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path $Path)) {
        Write-Host "  [跳过] $Label (路径不存在)" -ForegroundColor Gray
        return
    }
    $r = Remove-FolderContent -Path $Path
    $script:filesDeleted += $r.deleted
    $script:filesFailed += $r.failed
    $script:totalFreed += $r.bytes
    if ($r.failed -gt 0 -and $r.failedPaths) {
        foreach ($fp in @($r.failedPaths)) { $script:CleanFailedPaths.Add($fp) | Out-Null }
        if (-not $script:CleanFailedFolders.ContainsKey($Path)) {
            $script:CleanFailedFolders[$Path] = @{ label = $Label; failed = 0 }
        }
        $script:CleanFailedFolders[$Path].failed += $r.failed
    }
    $freedMB = [math]::Round($r.bytes / 1MB, 2)
    if ($r.error) {
        Write-Host "  [错误] $Label : $($r.error)" -ForegroundColor Red
    } elseif ($r.failed -gt 0) {
        Write-Host "  [部分] $Label : 释放 ${freedMB} MB，$($r.failed) 个文件被占用未能删除" -ForegroundColor Yellow
    } else {
        Write-Host "  [完成] $Label : 释放 ${freedMB} MB" -ForegroundColor Green
    }
}

Write-Host "`n正在清理临时文件，请稍候...`n" -ForegroundColor Yellow

# 通用文件夹清理目标（来自 config/optimization.json，经核心库 Get-CleanTargets 解析）
# CLI 与 WebUI 共用同一份数据源，消除两边重复维护的清单。
$cleanTargets = Get-CleanTargets -All
foreach ($t in $cleanTargets) {
    if ($t.key -eq 'thumb') { continue }  # 缩略图走下方专属保守清理，避免误删其它 Explorer 缓存
    if ($t.key -eq 'wsus') {
        # Windows 更新下载缓存：清理前停止服务、清理后重启，避免文件占用
        try {
            Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
            Clean-Folder $t.path $t.name
            Start-Service -Name wuauserv -ErrorAction SilentlyContinue
        } catch {
            Write-Host "  [跳过] Windows Update 缓存 (服务无法停止)" -ForegroundColor Gray
        }
    } else {
        Clean-Folder $t.path $t.name
    }
}

# 缩略图缓存（仅删除 thumbcache_*.db / iconcache_*.db，保留其它 Explorer 缓存）
$_laRoot = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { "$env:SystemDrive\Users\Public\AppData\Local" } else { $env:LOCALAPPDATA }
$thumbCachePath = Join-Path $_laRoot "Microsoft\Windows\Explorer"
if ([string]::IsNullOrWhiteSpace($thumbCachePath)) { $thumbCachePath = "" }
if (-not [string]::IsNullOrWhiteSpace($thumbCachePath) -and (Test-Path -LiteralPath $thumbCachePath)) {
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

# Windows 旧版日志 (CBS)
Clean-Folder "C:\Windows\Logs\CBS" "CBS 日志"

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

# 10. Windows 错误报告（已并入上方共享清理列表 Get-CleanTargets -All 的 wer 项，此处不再重复）

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

# --- 被占用文件：询问是否自动关闭占用程序后重试（与 GUI 清理页同一核心逻辑） ---
if ($script:CleanFailedPaths.Count -gt 0) {
    $lockPaths = @($script:CleanFailedPaths | Select-Object -Unique)
    $probe = Close-CleanLockOwners -LockPaths $lockPaths -WhatIf
    $willClose = @($probe.closed)
    if ($willClose.Count -gt 0) {
        Write-Host ""
        Write-Host "  检测到 $($lockPaths.Count) 个文件被占用，可关闭以下程序后重试：" -ForegroundColor Yellow
        Write-Host ("    " + ($willClose -join '、')) -ForegroundColor Yellow
        $answer = Read-Host "  自动关闭这些程序并重试清理？(Y=是 / N=否)"
        if ($answer -match '^[Yy]') {
            $kill = Close-CleanLockOwners -LockPaths $lockPaths -Confirm
            if (@($kill.closed).Count -gt 0) {
                Start-Sleep -Milliseconds 1500
                foreach ($entry in $script:CleanFailedFolders.GetEnumerator()) {
                    $rres = Remove-FolderContent -Path $entry.Key
                    $script:filesFailed = [math]::Max(0, $script:filesFailed - $entry.Value.failed + $rres.failed)
                    $script:filesDeleted += $rres.deleted
                    $script:totalFreed += $rres.bytes
                    Write-Host "  [重试] $($entry.Value.label) : 补删 $($rres.deleted) 个，释放 $([math]::Round($rres.bytes / 1MB, 2)) MB，仍失败 $($rres.failed) 个" -ForegroundColor Green
                }
            } else {
                Write-Host ("  [跳过] 占用程序结束失败：" + (@($kill.refused) -join '、')) -ForegroundColor Yellow
            }
        } else {
            Write-Host "  [跳过] 用户取消自动关闭占用程序" -ForegroundColor Gray
        }
    } else {
        Write-Host "  [提示] 被占用文件由系统关键程序持有或无主，无法自动关闭，可稍后手动重试" -ForegroundColor Gray
    }
}

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
if ($script:filesFailed -gt 0) {
    Write-Host "  未能删除（被占用/无权限）: $script:filesFailed" -ForegroundColor Yellow
}
Write-Host "============================================" -ForegroundColor Cyan

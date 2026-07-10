﻿<#
.SYNOPSIS
    启动项优化模块 — 管理并禁用多余的开机启动项
.DESCRIPTION
    列出所有开机启动项，让用户选择性地禁用不必要的程序，
    以加快开机速度并减少后台资源占用。
#>

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "         启动项优化" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# --- 获取启动项 ---
Write-Host "`n[1/2] 正在扫描启动项...`n" -ForegroundColor Yellow

$startupItems = @()

# 1. 注册表 - 当前用户
$regPaths = @(
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Run";              Scope="当前用户"}
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce";          Scope="当前用户"}
    @{Path="HKLM:\Software\Microsoft\Windows\CurrentVersion\Run";              Scope="所有用户"}
    @{Path="HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce";          Scope="所有用户"}
    @{Path="HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run";   Scope="所有用户(32位)"}
)

foreach ($reg in $regPaths) {
    if (Test-Path $reg.Path) {
        $properties = Get-ItemProperty -Path $reg.Path -ErrorAction SilentlyContinue
        if ($properties) {
            $properties.PSObject.Properties | Where-Object {
                $_.Name -notlike "PS*" -and $_.Value
            } | ForEach-Object {
                $startupItems += [PSCustomObject]@{
                    Index  = $startupItems.Count + 1
                    Name   = $_.Name
                    Value  = $_.Value
                    Scope  = $reg.Scope
                    Source = "注册表"
                    Path   = $reg.Path
                }
            }
        }
    }
}

# 2. 启动文件夹
$startupFolders = @(
    @{Path="$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup";        Scope="当前用户"}
    @{Path="$env:PROGRAMDATA\Microsoft\Windows\Start Menu\Programs\Startup";    Scope="所有用户"}
)
foreach ($folder in $startupFolders) {
    if (Test-Path $folder.Path) {
        Get-ChildItem -Path $folder.Path -ErrorAction SilentlyContinue | ForEach-Object {
            $startupItems += [PSCustomObject]@{
                Index  = $startupItems.Count + 1
                Name   = $_.Name
                Value  = $_.FullName
                Scope  = $folder.Scope
                Source = "启动文件夹"
                Path   = $folder.Path
            }
        }
    }
}

# 3. 任务管理器启动项 (通过 Get-CimInstance)
try {
    $startupApps = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue
    foreach ($app in $startupApps) {
        # 避免重复
        if ($startupItems.Name -notcontains $app.Name) {
            $startupItems += [PSCustomObject]@{
                Index  = $startupItems.Count + 1
                Name   = $app.Name
                Value  = $app.Command
                Scope  = $app.Location
                Source = "系统启动命令"
                Path   = $app.Location
            }
        }
    }
} catch {}

# --- 显示启动项 ---
if ($startupItems.Count -eq 0) {
    Write-Host "  未发现启动项。" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Cyan
    return
}

Write-Host "  发现 $($startupItems.Count) 个启动项:" -ForegroundColor Green
Write-Host ""
Write-Host "  $('序号'.PadLeft(4))  $('名称'.PadRight(35)) $('来源'.PadRight(12)) 范围" -ForegroundColor DarkGray
Write-Host "  $('-' * 80)" -ForegroundColor DarkGray

foreach ($item in $startupItems) {
    $displayName = if ($item.Name.Length -gt 33) { $item.Name.Substring(0, 30) + "..." } else { $item.Name }
    Write-Host "  $($item.Index.ToString().PadLeft(4))  $($displayName.PadRight(35)) $($item.Source.PadRight(12)) $($item.Scope)"
}

Write-Host ""
Write-Host "  常见可安全禁用的启动项:" -ForegroundColor Yellow
Write-Host "    - OneDrive, Skype, Teams (如不常使用)"
Write-Host "    - 各类更新检查程序 (Adobe Update, Java Update 等)"
Write-Host "    - 第三方软件自启动 (迅雷, 360, WPS 等)"
Write-Host ""

# --- 让用户选择 ---
Write-Host "[2/2] 选择要禁用的启动项" -ForegroundColor Yellow
Write-Host "  输入序号(用逗号分隔, 如 1,3,5) 禁用对应项"
Write-Host "  输入 A 禁用所有"
Write-Host "  输入 N 取消"
$input = Read-Host "选择"

$toDisable = @()
switch -Wildcard ($input) {
    { $_ -eq "A" -or $_ -eq "a" } { $toDisable = $startupItems }
    { $_ -eq "N" -or $_ -eq "n" } { Write-Host "  操作已取消。" -ForegroundColor Gray; Write-Host "============================================" -ForegroundColor Cyan; return }
    default {
        $indices = $input -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^\d+$" }
        foreach ($idx in $indices) {
            $item = $startupItems | Where-Object { $_.Index -eq [int]$idx }
            if ($item) { $toDisable += $item }
        }
    }
}

if ($toDisable.Count -eq 0) {
    Write-Host "  未选择任何项。" -ForegroundColor Gray
    Write-Host "============================================" -ForegroundColor Cyan
    return
}

# --- 备份 ---
$backupFile = Join-Path $PSScriptRoot "..\backups\startup_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$backupFile = [System.IO.Path]::GetFullPath($backupFile)
$toDisable | Select-Object Name, Value, Scope, Source, Path | Export-Csv -Path $backupFile -NoTypeInformation -Encoding UTF8
Write-Host "`n  备份已保存: $backupFile" -ForegroundColor Green

# --- 执行禁用 ---
Write-Host "`n正在禁用启动项..." -ForegroundColor Yellow
$disabledCount = 0
$failedCount = 0

foreach ($item in $toDisable) {
    try {
        if ($item.Source -eq "注册表") {
            # 从注册表删除（先备份值）
            $regKey = Get-Item -Path $item.Path -ErrorAction SilentlyContinue
            if ($regKey) {
                Remove-ItemProperty -Path $item.Path -Name $item.Name -ErrorAction Stop
                Write-Host "  [已禁用] $($item.Name) (注册表)" -ForegroundColor Green
                $disabledCount++
            }
        }
        elseif ($item.Source -eq "启动文件夹") {
            # 移动到备份文件夹而非删除
            $backupStartupDir = Join-Path $PSScriptRoot "..\backups\startup_items"
            if (-not (Test-Path $backupStartupDir)) {
                New-Item -ItemType Directory -Path $backupStartupDir -Force | Out-Null
            }
            $destPath = Join-Path $backupStartupDir (Split-Path $item.Value -Leaf)
            Move-Item -Path $item.Value -Destination $destPath -Force -ErrorAction Stop
            Write-Host "  [已禁用] $($item.Name) (启动文件夹->已备份)" -ForegroundColor Green
            $disabledCount++
        }
        else {
            Write-Host "  [跳过] $($item.Name) — 无法自动禁用此类型" -ForegroundColor Yellow
            $failedCount++
        }
    } catch {
        Write-Host "  [失败] $($item.Name) — $($_.Exception.Message)" -ForegroundColor Red
        $failedCount++
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  启动项优化完成！" -ForegroundColor Green
Write-Host "  已禁用: $disabledCount 项" -ForegroundColor Green
Write-Host "  失败  : $failedCount 项" -ForegroundColor $(if ($failedCount -gt 0) { "Yellow" } else { "Gray" })
Write-Host "  备份文件: $backupFile" -ForegroundColor Gray
Write-Host "  注意: 部分启动项可能需要通过任务管理器->启动 选项卡禁用" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan

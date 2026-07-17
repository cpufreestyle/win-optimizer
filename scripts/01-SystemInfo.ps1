﻿<#
.SYNOPSIS
    系统信息检测模块 — 展示详细的硬件与系统信息
#>

. "$PSScriptRoot\Common.ps1"
Show-ModuleBanner "系统信息检测"

# --- 操作系统信息 ---
Write-Host "`n[操作系统]" -ForegroundColor Yellow
$os = Get-CimInstance Win32_OperatingSystem
Write-Host "  系统        : $($os.Caption)"
Write-Host "  版本        : Build $($os.BuildNumber)"
Write-Host "  安装日期    : $($os.InstallDate)"
$uptime = (Get-Date) - $os.LastBootUpTime
Write-Host "  已运行      : $($uptime.Days) 天 $($uptime.Hours) 小时 $($uptime.Minutes) 分钟"

# --- CPU 信息 ---
Write-Host "`n[CPU]" -ForegroundColor Yellow
$cpus = Get-CimInstance Win32_Processor
foreach ($cpu in $cpus) {
    Write-Host "  名称        : $($cpu.Name)"
    Write-Host "  核心数      : $($cpu.NumberOfCores)"
    Write-Host "  线程数      : $($cpu.NumberOfLogicalProcessors)"
    Write-Host "  最大频率    : $([math]::Round($cpu.MaxClockSpeed / 1000, 2)) GHz"
    Write-Host "  当前负载    : $($cpu.LoadPercentage)%"
}

# 判断 CPU 代数
$cpuName = $cpus[0].Name
if ($cpuName -match "i[3579]-(\d)") {
    $gen = $matches[1]
    Write-Host "  CPU 代数    : 第 ${gen} 代" -ForegroundColor $(if ([int]$gen -le 7) { "Green" } else { "Gray" })
    if ([int]$gen -le 7) {
        Write-Host "  >>> 检测到 7代或更早 CPU，本工具可显著提升性能 <<<" -ForegroundColor Green
    }
}

# --- 内存信息 ---
Write-Host "`n[内存]" -ForegroundColor Yellow
$totalMem = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
$freeMem  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
$usedMem  = [math]::Round($totalMem - $freeMem, 1)
$memUsage = [math]::Round(($usedMem / $totalMem) * 100, 1)
Write-Host "  总内存      : ${totalMem} GB"
Write-Host "  已使用      : ${usedMem} GB (${memUsage}%)"
Write-Host "  可用        : ${freeMem} GB"

# 内存条详情
Write-Host "  内存条详情  :"
$ramSticks = Get-CimInstance Win32_PhysicalMemory | Where-Object { $_.Capacity -gt 0 }
foreach ($stick in $ramSticks) {
    $cap = [math]::Round($stick.Capacity / 1GB, 0)
    $speed = if ($stick.Speed) { "$($stick.Speed) MHz" } else { "未知" }
    Write-Host "    - ${cap}GB  $speed  ($($stick.Manufacturer))"
}

# --- 磁盘信息 ---
Write-Host "`n[磁盘]" -ForegroundColor Yellow
$disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
foreach ($disk in $disks) {
    $total = [math]::Round($disk.Size / 1GB, 1)
    $free  = [math]::Round($disk.FreeSpace / 1GB, 1)
    $used  = [math]::Round($total - $free, 1)
    $usage = if ($total -gt 0) { [math]::Round(($used / $total) * 100, 1) } else { 0 }
    $bar = "=" * [math]::Floor($usage / 5) + " " * (20 - [math]::Floor($usage / 5))
    Write-Host "  $($disk.DeviceID) 总计 ${total}GB | 已用 ${used}GB (${usage}%) [$bar]"
}

# 检测 SSD/HDD
Write-Host "  磁盘类型    :"
try {
    $physicalDisks = Get-PhysicalDisk -ErrorAction Stop | Select-Object FriendlyName, MediaType, Size
    foreach ($pd in $physicalDisks) {
        $sizeGB = [math]::Round($pd.Size / 1GB, 0)
        Write-Host "    - $($pd.FriendlyName): $($pd.MediaType) ${sizeGB}GB"
    }
} catch {
    Write-Host "    无法获取物理磁盘类型（需要 Storage 模块或管理员权限）" -ForegroundColor Gray
}

# --- 显卡信息 ---
Write-Host "`n[显卡]" -ForegroundColor Yellow
$gpus = Get-CimInstance Win32_VideoController
foreach ($gpu in $gpus) {
    $vram = if ($gpu.AdapterRAM) { [math]::Round($gpu.AdapterRAM / 1MB, 0) } else { "未知" }
    Write-Host "  $($gpu.Name)  (VRAM: ${vram}MB)"
    Write-Host "  驱动版本    : $($gpu.DriverVersion)"
}

# --- 主板信息 ---
Write-Host "`n[主板]" -ForegroundColor Yellow
$board = Get-CimInstance Win32_BaseBoard
Write-Host "  制造商      : $($board.Manufacturer)"
Write-Host "  型号        : $($board.Product)"
$bios = Get-CimInstance Win32_BIOS
Write-Host "  BIOS版本    : $($bios.SMBIOSBIOSVersion)"
Write-Host "  BIOS日期    : $($bios.ReleaseDate)"

# --- 网络信息 ---
Write-Host "`n[网络]" -ForegroundColor Yellow
$netAdapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object Name, InterfaceDescription, LinkSpeed
foreach ($adapter in $netAdapters) {
    Write-Host "  $($adapter.Name): $($adapter.LinkSpeed)"
    Write-Host "    $($adapter.InterfaceDescription)"
}

# --- 温度 (如果可用) ---
Write-Host "`n[温度监控]" -ForegroundColor Yellow
try {
    $temps = Get-CimInstance -Namespace "root/wmi" -Class MSAcpi_ThermalZoneTemperature -ErrorAction Stop
    foreach ($t in $temps) {
        $tempC = [math]::Round(($t.CurrentTemperature - 2732) / 10.0, 1)
        $tempColor = if ($tempC -gt 80) { "Red" } elseif ($tempC -gt 65) { "Yellow" } else { "Green" }
        Write-Host "  温度: ${tempC}°C" -ForegroundColor $tempColor
    }
} catch {
    Write-Host "  温度信息不可用 (需要硬件支持 ACPI 热区)" -ForegroundColor Gray
}

# --- 优化建议 ---
Write-Host "`n[优化建议]" -ForegroundColor Yellow
if ($memUsage -gt 75) {
    Write-Host "  ! 内存使用率过高 (${memUsage}%)，建议关闭不必要程序或增加内存" -ForegroundColor Yellow
}
foreach ($disk in $disks) {
    $total = $disk.Size
    $free = $disk.FreeSpace
    if ($total -gt 0 -and ($free / $total) -lt 0.15) {
        Write-Host "  ! 磁盘 $($disk.DeviceID) 空间不足，建议清理临时文件" -ForegroundColor Yellow
    }
}
if ($uptime.Days -gt 7) {
    Write-Host "  ! 系统已运行 $($uptime.Days) 天，建议重启以释放资源" -ForegroundColor Yellow
}

Show-ModuleFooter "检测完成"

<#
.SYNOPSIS
    WebUI 系统概览 — 返回 JSON
.DESCRIPTION
    收集 CPU / 内存 / 磁盘 / 显卡 / 运行时间 信息，输出 JSON。
    供 webui/app.py 通过 subprocess 调用。

    容错：每个数据分组独立 try/catch。个别分组失败（例如某块磁盘被
    BitLocker 锁定、显卡驱动异常、WMI 命名空间临时不可用）只清空该分组
    或降级该字段，不再让单点异常拖垮整个概览页。
#>
param(
    [switch]$AsJson
)

# 统一 stdout 为 UTF-8（让 Python subprocess.run 按 utf-8 解码时不乱码；与 OptimizeGUI 同款）
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
function Out-Json {
    param($obj)
    $obj | ConvertTo-Json -Depth 4 -Compress
}

$errors = New-Object System.Collections.ArrayList

# ---------- 操作系统 / 内存 / 运行时间 ----------
$osName = ""; $build = ""; $memTotal = 0; $memUsed = 0; $memFree = 0; $memPct = 0
$uptimeDays = 0; $uptimeHours = 0; $uptimeMins = 0
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $osName = $os.Caption
    $build  = $os.BuildNumber
    $memTotal = [math]::Round([double]$os.TotalVisibleMemorySize / 1MB, 1)
    $memFree  = [math]::Round([double]$os.FreePhysicalMemory / 1MB, 1)
    $memUsed  = [math]::Round($memTotal - $memFree, 1)
    $memPct   = if ($memTotal -gt 0) { [math]::Round(($memUsed / $memTotal) * 100, 0) } else { 0 }
    try {
        $boot = $os.LastBootUpTime
        if ($boot -is [string]) { $boot = [System.Management.ManagementDateTimeConverter]::ToDateTime($boot) }
        $uptime = (Get-Date) - $boot
        $uptimeDays = $uptime.Days; $uptimeHours = $uptime.Hours; $uptimeMins = $uptime.Minutes
    } catch { [void]$errors.Add("uptime: " + $_.Exception.Message) }
} catch {
    [void]$errors.Add("os: " + $_.Exception.Message)
}

# ---------- CPU ----------
$cpuName = ""; $cpuCores = 0; $cpuThreads = 0; $cpuClock = 0; $cpuLoad = 0; $cpuGen = ""
try {
    $cpu = @(Get-CimInstance Win32_Processor -ErrorAction Stop)[0]
    $cpuName    = $cpu.Name
    $cpuCores   = $cpu.NumberOfCores
    $cpuThreads = $cpu.NumberOfLogicalProcessors
    $cpuClock   = [math]::Round($cpu.MaxClockSpeed / 1000, 2)
    $cpuLoad    = $cpu.LoadPercentage
    if ($cpu.Name -match "i[3579]-(\d)") {
        $gen = [int]$matches[1]
        # 用半角括号与英文/简中混合，避免某些字体回退对全角括号/长中文渲染异常
        $cpuGen = "i" + $matches[0][1] + " 第 " + $gen + " 代"
        if ($gen -le 7) { $cpuGen += " [优化目标]" }
    }
} catch {
    [void]$errors.Add("cpu: " + $_.Exception.Message)
}

# ---------- 磁盘 ----------
$disks = @()
try {
    $disks = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop) | ForEach-Object {
        $total = [math]::Round([double]$_.Size / 1GB, 1)
        $free  = [math]::Round([double]$_.FreeSpace / 1GB, 1)
        $used  = [math]::Round($total - $free, 1)
        $pct   = if ($total -gt 0) { [math]::Round(($used / $total) * 100, 0) } else { 0 }
        [PSCustomObject]@{
            drive = $_.DeviceID
            totalGB = $total
            freeGB  = $free
            usedGB  = $used
            pct     = $pct
        }
    }
} catch {
    [void]$errors.Add("disks: " + $_.Exception.Message)
}

# ---------- 显卡 ----------
$gpus = @()
try {
    $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction Stop) | Select-Object -First 4 | ForEach-Object {
        if ($_.Name) { $_.Name }
    }
} catch {
    [void]$errors.Add("gpus: " + $_.Exception.Message)
}

$result = [PSCustomObject]@{
    osName    = $osName
    build     = $build
    cpuName   = $cpuName
    cpuCores  = $cpuCores
    cpuThreads= $cpuThreads
    cpuClock  = $cpuClock
    cpuLoad   = $cpuLoad
    cpuGen    = $cpuGen
    memTotal  = $memTotal
    memUsed   = $memUsed
    memFree   = $memFree
    memPct    = $memPct
    uptimeDays   = $uptimeDays
    uptimeHours  = $uptimeHours
    uptimeMins   = $uptimeMins
    disks     = @($disks)
    gpus      = @($gpus)
    ok        = ($errors.Count -eq 0)
}
if ($errors.Count -gt 0) {
    $result | Add-Member -NotePropertyName errors -NotePropertyValue @($errors)
}
Out-Json $result


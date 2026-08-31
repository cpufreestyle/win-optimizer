<#
.SYNOPSIS
    WebUI 系统概览 — 返回 JSON
.DESCRIPTION
    收集 CPU / 内存 / 磁盘 / 显卡 / 运行时间 信息，输出 JSON。
    供 webui/app.py 通过 subprocess 调用。
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

try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $cpu = @(Get-CimInstance Win32_Processor -ErrorAction Stop)[0]
    $totalMemGB = [math]::Round([double]$os.TotalVisibleMemorySize / 1MB, 1)
    $freeMemGB  = [math]::Round([double]$os.FreePhysicalMemory / 1MB, 1)
    $usedMemGB  = [math]::Round($totalMemGB - $freeMemGB, 1)
    $memPct     = if ($totalMemGB -gt 0) { [math]::Round(($usedMemGB / $totalMemGB) * 100, 0) } else { 0 }

    $boot = $os.LastBootUpTime
    if ($boot -is [string]) { $boot = [System.Management.ManagementDateTimeConverter]::ToDateTime($boot) }
    $uptime = (Get-Date) - $boot

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

    $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction Stop) | Select-Object -First 4 | ForEach-Object {
        if ($_.Name) { $_.Name }
    }

    $cpuGen = ""
    if ($cpu.Name -match "i[3579]-(\d)") {
        $gen = [int]$matches[1]
        # 用半角括号与英文/简中混合，避免某些字体回退对全角括号/长中文渲染异常
        $cpuGen = "i$($matches[0][1]) 第 $gen 代"
        if ($gen -le 7) { $cpuGen += " [优化目标]" }
    }

    $result = [PSCustomObject]@{
        osName    = $os.Caption
        build     = $os.BuildNumber
        cpuName   = $cpu.Name
        cpuCores  = $cpu.NumberOfCores
        cpuThreads= $cpu.NumberOfLogicalProcessors
        cpuClock  = [math]::Round($cpu.MaxClockSpeed / 1000, 2)
        cpuLoad   = $cpu.LoadPercentage
        cpuGen    = $cpuGen
        memTotal  = $totalMemGB
        memUsed   = $usedMemGB
        memFree   = $freeMemGB
        memPct    = $memPct
        uptimeDays   = $uptime.Days
        uptimeHours  = $uptime.Hours
        uptimeMins   = $uptime.Minutes
        disks     = $disks
        gpus      = $gpus
        ok        = $true
    }
    Out-Json $result
} catch {
    Out-Json ([PSCustomObject]@{ ok = $false; error = $_.Exception.Message })
}

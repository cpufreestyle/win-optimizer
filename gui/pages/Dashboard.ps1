function Build-Dashboard {
    $page = $script:Pages["Dashboard"]
    $page.Controls.Clear()

    # 获取系统信息（使用兼容函数，避免多CPU/多OS返回数组）
    $os = @(Get-CimData Win32_OperatingSystem)[0]
    $cpu = @(Get-CimData Win32_Processor)[0]
    $totalMem = [math]::Round([double]$os.TotalVisibleMemorySize / 1MB, 1)
    $freeMem  = [math]::Round([double]$os.FreePhysicalMemory / 1MB, 1)
    $usedMem  = [math]::Round($totalMem - $freeMem, 1)
    $memPct   = if ($totalMem -gt 0) { [math]::Round(($usedMem / $totalMem) * 100, 0) } else { 0 }
    # Win7 WMI LastBootUpTime 是字符串，需转换
    $bootTime = $os.LastBootUpTime
    if ($bootTime -is [string]) { $bootTime = [System.Management.ManagementDateTimeConverter]::ToDateTime($bootTime) }
    $uptime   = (Get-Date) - $bootTime

    # CPU 代数检测
    $cpuGen = ""
    $cpuColor = $Theme.TextMain
    if ($cpu.Name -match "i[3579]-(\d)") {
        $gen = [int]$matches[1]
        $cpuGen = "第 $gen 代"
        if ($gen -le 7) {
            $cpuGen += " (本工具优化目标)"
            $cpuColor = $Theme.Success
        }
    }

    # --- CPU 卡片 ---
    $cardCPU = New-Object System.Windows.Forms.Panel
    $cardCPU.Location = New-Object System.Drawing.Point(20, 60)
    $cardCPU.Size = New-Object System.Drawing.Size(370, 145)
    $cardCPU.BackColor = $Theme.BgCard
    $page.Controls.Add($cardCPU)

    $cardCPU.Controls.Add((New-Label "CPU 处理器" 16 10 340 26 $Fonts.Header $Theme.Accent))
    $cardCPU.Controls.Add((New-Label $cpu.Name 16 40 340 24 $Fonts.Body $Theme.TextBright))
    $cardCPU.Controls.Add((New-Label "核心: $($cpu.NumberOfCores)  线程: $($cpu.NumberOfLogicalProcessors)  频率: $([math]::Round($cpu.MaxClockSpeed/1000,2)) GHz" 16 66 340 22 $Fonts.Small $Theme.TextDim))
    $cardCPU.Controls.Add((New-Label "当前负载: $($cpu.LoadPercentage)%" 16 88 340 22 $Fonts.Small $Theme.Warning))

    if ($cpuGen) {
        $cardCPU.Controls.Add((New-Label $cpuGen 16 108 340 22 $Fonts.Small $cpuColor))
    }

    # --- 内存卡片 ---
    $cardMem = New-Object System.Windows.Forms.Panel
    $cardMem.Location = New-Object System.Drawing.Point(410, 60)
    $cardMem.Size = New-Object System.Drawing.Size(370, 145)
    $cardMem.BackColor = $Theme.BgCard
    $page.Controls.Add($cardMem)

    $cardMem.Controls.Add((New-Label "内存" 16 10 340 26 $Fonts.Header $Theme.Accent))

    $lblMemTotal = New-Label "总内存: ${totalMem} GB" 16 40 340 22 $Fonts.Body $Theme.TextBright
    $cardMem.Controls.Add($lblMemTotal)

    $lblMemUsed = New-Label "已使用: ${usedMem} GB / ${totalMem} GB (${memPct}%)" 16 64 340 22 $Fonts.Small $Theme.TextDim
    $cardMem.Controls.Add($lblMemUsed)

    # 内存进度条
    $memBar = New-Object System.Windows.Forms.ProgressBar
    $memBar.Location = New-Object System.Drawing.Point(16, 90)
    $memBar.Size = New-Object System.Drawing.Size(340, 16)
    $memBar.Value = $memPct
    $memBar.ForeColor = if ($memPct -gt 80) { $Theme.Error } elseif ($memPct -gt 60) { $Theme.Warning } else { $Theme.Success }
    $memBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $cardMem.Controls.Add($memBar)

    $lblMemFree = New-Label "可用: ${freeMem} GB" 16 110 340 18 $Fonts.Small $Theme.TextDim
    $cardMem.Controls.Add($lblMemFree)

    # --- 磁盘卡片 ---
    $disks = @(Get-CimData Win32_LogicalDisk -Filter "DriveType=3")
    $yDisk = $cardCPU.Bottom + 10
    foreach ($disk in $disks) {
        $total = [math]::Round([double]$disk.Size / 1GB, 1)
        $free  = [math]::Round([double]$disk.FreeSpace / 1GB, 1)
        $used  = [math]::Round($total - $free, 1)
        $pct   = if ($total -gt 0) { [math]::Round(($used / $total) * 100, 0) } else { 0 }

        $cardDisk = New-Object System.Windows.Forms.Panel
        $cardDisk.Location = New-Object System.Drawing.Point(20, $yDisk)
        $cardDisk.Size = New-Object System.Drawing.Size(760, 56)
        $cardDisk.BackColor = $Theme.BgCard
        $page.Controls.Add($cardDisk)

        $lblDiskName = New-Label "$($disk.DeviceID) 总计 ${total}GB" 16 6 200 22 $Fonts.Body $Theme.TextBright
        $cardDisk.Controls.Add($lblDiskName)

        $lblDiskUse = New-Label "已用 ${used}GB / 可用 ${free}GB (${pct}%)" 220 8 300 18 $Fonts.Small $Theme.TextDim
        $cardDisk.Controls.Add($lblDiskUse)

        $diskBar = New-Object System.Windows.Forms.ProgressBar
        $diskBar.Location = New-Object System.Drawing.Point(530, 16)
        $diskBar.Size = New-Object System.Drawing.Size(210, 14)
        $diskBar.Value = $pct
        $diskBar.ForeColor = if ($pct -gt 85) { $Theme.Error } elseif ($pct -gt 70) { $Theme.Warning } else { $Theme.Success }
        $diskBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
        $cardDisk.Controls.Add($diskBar)

        $yDisk += 64
    }

    # --- 系统信息 ---
    $sysInfo = "系统: $($os.Caption) Build $($os.BuildNumber)`n"
    $sysInfo += "运行时间: $($uptime.Days) 天 $($uptime.Hours) 小时 $($uptime.Minutes) 分钟`n"

    # 显卡（最多显示 4 块）
    $gpus = @(Get-CimData Win32_VideoController) | Select-Object -First 4
    foreach ($gpu in $gpus) {
        if ($gpu.Name) { $sysInfo += "显卡: $($gpu.Name)`n" }
    }

    # 根据行数动态计算卡片高度（每行 22px + 标题区 38px + 边距）
    $sysLines = ($sysInfo.Split("`n") | Where-Object { $_ -ne "" }).Count
    $sysInfoHeight = [math]::Max(60, $sysLines * 22 + 14)
    $cardSysHeight = 38 + $sysInfoHeight + 14

    $cardSys = New-Object System.Windows.Forms.Panel
    $cardSys.Location = New-Object System.Drawing.Point(20, [int]($yDisk + 4))
    $cardSys.Size = New-Object System.Drawing.Size(760, $cardSysHeight)
    $cardSys.BackColor = $Theme.BgCard
    $page.Controls.Add($cardSys)

    $lblSysTitle = New-Label "系统信息" 16 8 400 26 $Fonts.Header $Theme.Accent
    $cardSys.Controls.Add($lblSysTitle)

    $lblSysInfo = New-Object System.Windows.Forms.Label
    $lblSysInfo.Location = New-Object System.Drawing.Point(16, 38)
    $lblSysInfo.AutoSize = $true
    $lblSysInfo.MaximumSize = New-Object System.Drawing.Size(728, 0)
    $lblSysInfo.Text = $sysInfo
    $lblSysInfo.Font = $Fonts.Small
    $lblSysInfo.ForeColor = $Theme.TextDim
    $lblSysInfo.BackColor = [System.Drawing.Color]::Transparent
    $cardSys.Controls.Add($lblSysInfo)

    # --- 刷新按钮 ---
    $btnRefresh = New-Button "刷新信息" 20 ([int]($yDisk + 4 + $cardSysHeight + 12)) 120 36 $Theme.AccentDark 10
    $btnRefresh.Add_Click({ Build-Dashboard })
    $page.Controls.Add($btnRefresh)

    # --- 一键优化按钮 ---
    $btnFull = New-Button "一键全面优化" 640 ([int]($yDisk + 112)) 140 36 $Theme.Success 10
    $btnFull.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $btnFull.Add_Click({
        $result = [System.Windows.Forms.MessageBox]::Show(
            "即将执行所有优化操作，可能需要几分钟时间。`n`n建议先进行备份。`n`n确认继续？",
            "一键全面优化",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($result -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        $modules = @(
            "02-CleanTemp.ps1",
            "03-DisableServices.ps1",
            "04-StartupOptimize.ps1",
            "05-VisualEffects.ps1",
            "06-PowerPlan.ps1",
            "07-DiskOptimize.ps1",
            "08-NetworkOptimize.ps1"
        )

        $this.Enabled = $false
        $this.Text = "优化中..."
        $MainForm.Refresh()
        try {
            foreach ($mod in $modules) {
                Write-Log "执行模块: $mod"
                $scriptPath = Join-Path $script:ScriptsDir $mod
                if (Test-Path $scriptPath) {
                    try { & $scriptPath } catch { Write-Log "模块 $mod 出错: $($_.Exception.Message)" "ERROR" }
                    Write-Log "模块 $mod 完成" "SUCCESS"
                } else {
                    Write-Log "找不到模块文件: $scriptPath" "ERROR"
                }
            }

            Write-Log "一键全面优化完成！建议重启电脑使所有更改生效。" "SUCCESS"
            [System.Windows.Forms.MessageBox]::Show("全面优化完成！`n建议重启电脑使所有更改生效。", "完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            Write-Log "一键全面优化异常: $($_.Exception.Message)" "ERROR"
            [System.Windows.Forms.MessageBox]::Show("优化过程出现异常：$($_.Exception.Message)", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        } finally {
            $this.Enabled = $true
            $this.Text = "一键全面优化"
        }
    })
    $page.Controls.Add($btnFull)
}

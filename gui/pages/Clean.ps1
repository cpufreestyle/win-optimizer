function Build-CleanPage {
    $page = $script:Pages["Clean"]
    $page.Controls.Clear()

    $lblTitle = New-Label "垃圾文件清理" 20 56 500 30 $Fonts.Header $Theme.TextBright
    $page.Controls.Add($lblTitle)

    $lblDesc = New-Label "清理系统临时文件、更新缓存、缩略图缓存、回收站等，释放磁盘空间" 20 90 760 24 $Fonts.Small $Theme.TextDim
    $lblDesc.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $page.Controls.Add($lblDesc)

    # 扫描结果
    $lblScan = New-Label "可清理项目:" 20 126 760 24 $Fonts.Sub $Theme.Accent
    $lblScan.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $page.Controls.Add($lblScan)

    # 用 script 作用域保存变量供事件处理器使用
    # 环境变量兜底：PS2EXE 编译 EXE 或某些 session 下 $env:TEMP/LOCALAPPDATA/PROGRAMDATA 可能为空，会导致后续 Get-FolderSize 抛"无法将参数绑定到 Path"
    $_t = if ([string]::IsNullOrWhiteSpace($env:TEMP))         { "C:\Users\Public" } else { $env:TEMP }
    $_la = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { "$env:SystemDrive\Users\Public\AppData\Local" } else { $env:LOCALAPPDATA }
    $_pd = if ([string]::IsNullOrWhiteSpace($env:PROGRAMDATA))  { "$env:SystemDrive\Users\Public\AppData\Roaming" }  else { $env:PROGRAMDATA }
    $script:CleanItems = @(
        @{Path="C:\Windows\Temp";                    Name="Windows 系统临时文件"}
        @{Path=$_t;                                    Name="用户临时文件"}
        @{Path="C:\Windows\Prefetch";                Name="预读取文件"}
        @{Path="C:\Windows\SoftwareDistribution\Download"; Name="Windows Update 下载缓存"}
        @{Path="$_la\Microsoft\Windows\Explorer";     Name="缩略图缓存"}
        @{Path="$_pd\Microsoft\Windows\WER";          Name="Windows 错误报告"}
    )

    $script:CleanListBox = New-Object System.Windows.Forms.CheckedListBox
    $script:CleanListBox.Location = New-Object System.Drawing.Point(20, 156)
    # 高度固定为「列表首行 156 -> 操作区 340」之间的可用空间，避免列表盖住下方复选框/按钮
    # 锚定只保留 Top|Left|Right（不要 Bottom）。原因：Reposition-PageControls 每次重排都会把
    # 「靠左且宽度 >= 400」的控件宽度改成 $maxW，而 WinForms 会把锚定 Bottom 控件的这次宽度
    # 变化当成一次纵向缩放，Height 随每次 Resize 累加（实测 830 -> 1814 -> 2552px），最终吞掉
    # 下方复选框与按钮。去掉 Bottom 后高度只由本行数值决定。
    $script:CleanListBox.Size = New-Object System.Drawing.Size(760, 182)
    $script:CleanListBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $script:CleanListBox.BackColor = $Theme.BgInput
    $script:CleanListBox.ForeColor = $Theme.TextMain
    $script:CleanListBox.Font = $Fonts.Body
    $script:CleanListBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $script:CleanListBox.CheckOnClick = $true
    $script:CleanListBox.IntegralHeight = $false
    # 先用占位文本建列表（体积统计要遍历目录，放到界面显示后再算，避免拖慢启动）
    foreach ($item in $script:CleanItems) {
        $script:CleanListBox.Items.Add("$($item.Name) — 计算中…", $true) | Out-Null
    }
    $page.Controls.Add($script:CleanListBox)

    # 额外选项
    # 这里只写 96 DPI 设计值，实际像素由 OptimizeGUI.ps1 的 Invoke-UiScalePass 统一放大，
    # 避免页面内再做一次局部 DPI 计算导致控件间距被重复放大。
    $chkH = 24
    $btnH = 44
    $lblH = 24
    $listBottom = $script:CleanListBox.Bottom
    $chkTop = $listBottom + 14
    $agedTop = $chkTop + $chkH + 8
    $btnTop = $agedTop + $chkH + 16
    $lblTop = $btnTop + $btnH + 12

    $script:ChkRecycle = New-Object System.Windows.Forms.CheckBox
    $script:ChkRecycle.Location = New-Object System.Drawing.Point(20, $chkTop)
    $script:ChkRecycle.Size = New-Object System.Drawing.Size(200, $chkH)
    $script:ChkRecycle.Text = "清空回收站"
    $script:ChkRecycle.Checked = $true
    $script:ChkRecycle.Font = $Fonts.Body
    $script:ChkRecycle.ForeColor = $Theme.TextMain
    $script:ChkRecycle.BackColor = $Theme.BgDark
    $page.Controls.Add($script:ChkRecycle)

    $script:ChkDNS = New-Object System.Windows.Forms.CheckBox
    $script:ChkDNS.Location = New-Object System.Drawing.Point(230, $chkTop)
    $script:ChkDNS.Size = New-Object System.Drawing.Size(200, $chkH)
    $script:ChkDNS.Text = "清除 DNS 缓存"
    $script:ChkDNS.Checked = $true
    $script:ChkDNS.Font = $Fonts.Body
    $script:ChkDNS.ForeColor = $Theme.TextMain
    $script:ChkDNS.BackColor = $Theme.BgDark
    $page.Controls.Add($script:ChkDNS)

    $script:ChkDump = New-Object System.Windows.Forms.CheckBox
    $script:ChkDump.Location = New-Object System.Drawing.Point(440, $chkTop)
    $script:ChkDump.Size = New-Object System.Drawing.Size(200, $chkH)
    $script:ChkDump.Text = "删除内存转储文件"
    $script:ChkDump.Tag = 'pin-right'
    $script:ChkDump.Checked = $true
    $script:ChkDump.Font = $Fonts.Body
    $script:ChkDump.ForeColor = $Theme.TextMain
    $script:ChkDump.BackColor = $Theme.BgDark
    $page.Controls.Add($script:ChkDump)

    $script:ChkAgedOnly = New-Object System.Windows.Forms.CheckBox
    $script:ChkAgedOnly.Location = New-Object System.Drawing.Point(20, $agedTop)
    $script:ChkAgedOnly.Size = New-Object System.Drawing.Size(420, $chkH)
    $script:ChkAgedOnly.Text = "只清理 7 天前的旧文件（保留最近写入的文件）"
    $script:ChkAgedOnly.Checked = $false
    $script:ChkAgedOnly.Font = $Fonts.Body
    $script:ChkAgedOnly.ForeColor = $Theme.TextMain
    $script:ChkAgedOnly.BackColor = $Theme.BgDark
    $script:ChkAgedOnly.Add_CheckedChanged({ Update-CleanSizes })
    $page.Controls.Add($script:ChkAgedOnly)

    # 执行按钮
    $script:BtnClean = New-Button "开始清理" 20 $btnTop 200 $btnH $Theme.Success 11
    # 取消按钮：仅在清理进行中可用，解决大目录清理时界面长时间无响应且无法中断的问题
    $script:BtnCancelClean = New-Button "取消" 240 $btnTop 120 $btnH $Theme.Accent 11
    $script:BtnCancelClean.Enabled = $false
    $script:CleanCancel = $false
    $script:BtnCancelClean.Add_Click({
        $script:CleanCancel = $true
        $script:LblCleanProgress.Text = "正在取消，等待当前项目收尾..."
    })
    # 进度提示：整体项目进度 [n/m] + 当前项目的百分比
    $script:LblCleanProgress = New-Label "就绪" 20 $lblTop 760 $lblH $Fonts.Small $Theme.TextDim
    $script:LblCleanProgress.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

    $script:BtnClean.Add_Click({
        try {
        $this.Enabled = $false
        $this.Text = "正在清理..."
        $script:CleanCancel = $false
        $script:BtnCancelClean.Enabled = $true
        $script:LblCleanProgress.Text = "准备中..."
        Invoke-UIRefresh

        $totalFreed = 0
        $filesDeleted = 0
        $filesFailed = 0
        $ageDays = if ($script:ChkAgedOnly.Checked) { 7 } else { 0 }
        $cancelled = $false

        # 先统计本次勾选的项目，用于整体进度 [n/m]
        $checkedIdx = @()
        for ($k = 0; $k -lt $script:CleanItems.Count; $k++) {
            if ($script:CleanListBox.GetItemChecked($k)) { $checkedIdx += $k }
        }
        $totalItems = $checkedIdx.Count
        $doneItems = 0

        foreach ($i in $checkedIdx) {
            if ($script:CleanCancel) { $cancelled = $true; break }
            $doneItems++
            $item = $script:CleanItems[$i]
            $script:LblCleanProgress.Text = "[$doneItems/$totalItems] 正在统计 $($item.Name) ..."
            Invoke-UIRefresh

            $tick = {
                param($done, $total)
                $pct = if ($total -gt 0) { [math]::Round(($done / $total) * 100) } else { 100 }
                $script:LblCleanProgress.Text = "[$doneItems/$totalItems] $($item.Name)：$done/$total（$pct%）"
                Invoke-UIRefresh
                return (-not $script:CleanCancel)
            }
            $res = Remove-FolderContent -Path $item.Path -OlderThanDays $ageDays -Tick $tick
            $filesDeleted += $res.deleted
            $filesFailed += $res.failed
            $totalFreed += $res.bytes
            if ($res.cancelled) { $cancelled = $true; break }
            Write-Log "[清理] $($item.Name): 释放 $([math]::Round($res.bytes/1MB,2)) MB，删除 $($res.deleted) 个，失败 $($res.failed) 个" "SUCCESS"
            Invoke-UIRefresh
        }

        $script:BtnCancelClean.Enabled = $false

        if ($cancelled) {
            $script:LblCleanProgress.Text = "已取消（已删除 $filesDeleted 个文件）"
            Write-Log "[清理] 用户取消，本次已删除 $filesDeleted 个文件" "WARN"
            $this.Enabled = $true
            $this.Text = "开始清理"
            return
        }

        if ($script:ChkRecycle.Checked) {
            Clear-RecycleBinCompat
            Write-Log "[清理] 回收站已清空" "SUCCESS"
        }
        if ($script:ChkDNS.Checked) {
            try { ipconfig /flushdns | Out-Null; Write-Log "[清理] DNS 缓存已清除" "SUCCESS" } catch {}
        }
        if ($script:ChkDump.Checked) {
            $dumpFiles = @("C:\Windows\MEMORY.DMP")
            $dumpFiles += (Get-ChildItem "C:\Windows\Minidump" -ErrorAction SilentlyContinue).FullName
            foreach ($dump in $dumpFiles) {
                if ($dump -and (Test-Path $dump)) {
                    $totalFreed += (Get-Item $dump).Length
                    Remove-Item $dump -Force -ErrorAction SilentlyContinue
                    Write-Log "[清理] 删除转储文件: $(Split-Path $dump -Leaf)" "SUCCESS"
                }
            }
        }

        $totalMB = [math]::Round($totalFreed / 1MB, 2)
        $totalGB = [math]::Round($totalFreed / 1GB, 2)
        $msg = if ($totalGB -ge 1) { "共释放 ${totalGB} GB 空间" } else { "共释放 ${totalMB} MB 空间" }
        $failedNote = if ($filesFailed -gt 0) { "，$filesFailed 个被占用未能删除" } else { "" }
        Write-Log "清理完成！$msg，删除 $filesDeleted 个文件$failedNote" "SUCCESS"
        $script:LblCleanProgress.Text = "清理完成"

        $this.Enabled = $true
        $this.Text = "开始清理"

        [System.Windows.Forms.MessageBox]::Show("清理完成！`n$msg`n删除 $filesDeleted 个文件$failedNote", "完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            Write-Log "清理出错: $($_.Exception.Message)" "ERROR"
            $script:BtnCancelClean.Enabled = $false
            $this.Enabled = $true
            $this.Text = "开始清理"
            [System.Windows.Forms.MessageBox]::Show("清理出错: $($_.Exception.Message)", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })
    $page.Controls.Add($script:BtnClean)
    $page.Controls.Add($script:BtnCancelClean)
    $page.Controls.Add($script:LblCleanProgress)

    # 列表显示后再统计各目录体积：启动阶段不再遍历磁盘，避免老机械盘上卡住几秒
    if ($null -ne $script:CleanSizeTimer) {
        try { $script:CleanSizeTimer.Stop(); $script:CleanSizeTimer.Dispose() } catch { }
        $script:CleanSizeTimer = $null
    }
    $script:CleanSizeTimer = New-Object System.Windows.Forms.Timer
    $script:CleanSizeTimer.Interval = 250
    $script:CleanSizeTimer.Add_Tick({
        param($Sender, $e)
        try { $Sender.Stop(); $Sender.Dispose() } catch { }
        $script:CleanSizeTimer = $null
        Update-CleanSizes
    })
    $script:CleanSizeTimer.Start()
}

# 刷新清理列表里的目录体积（保留勾选状态）
function Update-CleanSizes {
    if ($null -eq $script:CleanListBox -or $null -eq $script:CleanItems) { return }
    $checked = @()
    for ($i = 0; $i -lt $script:CleanListBox.Items.Count; $i++) {
        $checked += [bool]$script:CleanListBox.GetItemChecked($i)
    }
    for ($i = 0; $i -lt $script:CleanItems.Count; $i++) {
        if ($i -ge $script:CleanListBox.Items.Count) { break }
        try {
        $ageDays = if ($script:ChkAgedOnly -and $script:ChkAgedOnly.Checked) { 7 } else { 0 }
        $size = (Remove-FolderContent -Path $script:CleanItems[$i].Path -OlderThanDays $ageDays -WhatIf).bytes
            $sizeMB = [math]::Round($size / 1MB, 2)
            $script:CleanListBox.Items[$i] = "$($script:CleanItems[$i].Name) — ${sizeMB} MB"
        } catch {
            $script:CleanListBox.Items[$i] = "$($script:CleanItems[$i].Name) — 未知"
        }
    }
    for ($i = 0; $i -lt $script:CleanListBox.Items.Count; $i++) {
        if ($i -lt $checked.Count) { $script:CleanListBox.SetItemChecked($i, $checked[$i]) }
    }
}

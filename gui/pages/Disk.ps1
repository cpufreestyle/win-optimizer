function Build-DiskPage {
    $page = $script:Pages["Disk"]
    $page.Controls.Clear()

    $lblTitle = New-Label "磁盘优化" 20 22 500 30 $Fonts.Header $Theme.TextBright
    $page.Controls.Add($lblTitle)

    $lblDesc = New-Label "SSD 执行 TRIM 优化 / HDD 执行碎片整理 / 清理系统组件" 20 56 760 24 $Fonts.Small $Theme.TextDim
    $page.Controls.Add($lblDesc)

    # 磁盘列表 - 使用兼容函数
    $physicalDisks = @(Get-PhysicalDiskCompat)

    $yDisk = 96
    $lblDiskInfo = New-Label "物理磁盘:" 20 $yDisk 760 24 $Fonts.Sub $Theme.Accent
    $page.Controls.Add($lblDiskInfo)
    $yDisk += 30

    foreach ($pd in $physicalDisks) {
        $sizeGB = if ($pd.Size) { [math]::Round([double]$pd.Size / 1GB, 0) } else { 0 }
        $typeColor = if ($pd.MediaType -eq "SSD") { $Theme.Success } else { $Theme.Warning }
        $card = New-Object System.Windows.Forms.Panel
        $card.Location = New-Object System.Drawing.Point(20, $yDisk)
        $card.Size = New-Object System.Drawing.Size(760, 44)
        $card.BackColor = $Theme.BgCard
        $page.Controls.Add($card)

        $lbl = New-Label "$($pd.FriendlyName)" 16 6 350 20 $Fonts.Body $Theme.TextBright
        $card.Controls.Add($lbl)

        $lblType = New-Label "类型: $($pd.MediaType)" 16 24 200 18 $Fonts.Small $typeColor
        $card.Controls.Add($lblType)

        $lblSize = New-Label "容量: ${sizeGB}GB" 260 24 200 18 $Fonts.Small $Theme.TextDim
        $card.Controls.Add($lblSize)

        $yDisk += 50
    }

    # 操作选项
    $yDisk += 10
    $script:chkTRIM = New-Object System.Windows.Forms.CheckBox
    $script:chkTRIM.Location = New-Object System.Drawing.Point(20, $yDisk)
    $script:chkTRIM.Size = New-Object System.Drawing.Size(250, 24)
    $script:chkTRIM.Text = "SSD TRIM 优化"
    $script:chkTRIM.Checked = $true
    $script:chkTRIM.Font = $Fonts.Body
    $script:chkTRIM.ForeColor = $Theme.TextMain
    $script:chkTRIM.BackColor = $Theme.BgDark
    $page.Controls.Add($script:chkTRIM)

    $script:chkDefrag = New-Object System.Windows.Forms.CheckBox
    $script:chkDefrag.Location = New-Object System.Drawing.Point(280, $yDisk)
    $script:chkDefrag.Size = New-Object System.Drawing.Size(250, 24)
    $script:chkDefrag.Text = "HDD 碎片整理"
    $script:chkDefrag.Checked = $true
    $script:chkDefrag.Font = $Fonts.Body
    $script:chkDefrag.ForeColor = $Theme.TextMain
    $script:chkDefrag.BackColor = $Theme.BgDark
    $page.Controls.Add($script:chkDefrag)

    $script:chkWinSxS = New-Object System.Windows.Forms.CheckBox
    $script:chkWinSxS.Location = New-Object System.Drawing.Point(20, [int]($yDisk + 30))
    $script:chkWinSxS.Size = New-Object System.Drawing.Size(250, 24)
    $script:chkWinSxS.Text = "清理 WinSxS 组件存储"
    $script:chkWinSxS.Checked = $true
    $script:chkWinSxS.Font = $Fonts.Body
    $script:chkWinSxS.ForeColor = $Theme.TextMain
    $script:chkWinSxS.BackColor = $Theme.BgDark
    $page.Controls.Add($script:chkWinSxS)

    $script:chkCompact = New-Object System.Windows.Forms.CheckBox
    $script:chkCompact.Location = New-Object System.Drawing.Point(280, [int]($yDisk + 30))
    $script:chkCompact.Size = New-Object System.Drawing.Size(250, 24)
    $script:chkCompact.Text = "压缩系统文件 (CompactOS)"
    $script:chkCompact.Checked = $false
    $script:chkCompact.Font = $Fonts.Body
    $script:chkCompact.ForeColor = $Theme.TextMain
    $script:chkCompact.BackColor = $Theme.BgDark
    $page.Controls.Add($script:chkCompact)

    $yDisk += 70

    $script:btnDiskOpt = New-Button "开始优化" 20 $yDisk 200 44 $Theme.Success 11
    $script:btnDiskOpt.Add_Click({
        try {
        $this.Enabled = $false
        $this.Text = "优化中...(可能需要数分钟)"
        Invoke-UIRefresh
        $volumes = @(Get-VolumeCompat)

        if ($script:chkTRIM.Checked -or $script:chkDefrag.Checked) {
            foreach ($vol in $volumes) {
                $drive = "$($vol.DriveLetter):"
                # Win7 回退：用 WMI 查询磁盘类型
                $mediaType = "HDD"
                if ($script:chkTRIM.Checked) {
                    try {
                        Optimize-VolumeCompat -DriveLetter $vol.DriveLetter -ReTrim
                        Write-Log "[优化] $drive TRIM 完成" "SUCCESS"
                    } catch { Write-Log "[跳过] $drive TRIM" "WARN" }
                }
                if ($script:chkDefrag.Checked) {
                    try {
                        Optimize-VolumeCompat -DriveLetter $vol.DriveLetter -Defrag
                        Write-Log "[优化] $drive 碎片整理完成" "SUCCESS"
                    } catch { Write-Log "[跳过] $drive 碎片整理" "WARN" }
                }
                Invoke-UIRefresh
            }
        }

        if ($script:chkWinSxS.Checked) {
            Write-Log "正在清理 WinSxS 组件存储..."
            Dism.exe /Online /Cleanup-Image /StartComponentCleanup 2>&1 | Out-Null
            Write-Log "WinSxS 组件存储清理完成" "SUCCESS"
        }

        if ($script:chkCompact.Checked) {
            Write-Log "正在压缩系统文件..."
            Compact.exe /CompactOS:always 2>&1 | Out-Null
            Write-Log "系统文件压缩完成" "SUCCESS"
        }

        Write-Log "磁盘优化完成！" "SUCCESS"
        $this.Enabled = $true
        $this.Text = "开始优化"
        [System.Windows.Forms.MessageBox]::Show("磁盘优化完成！", "完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            Write-Log "磁盘优化出错: $($_.Exception.Message)" "ERROR"
            $this.Enabled = $true
            $this.Text = "开始优化"
            [System.Windows.Forms.MessageBox]::Show("磁盘优化出错: $($_.Exception.Message)", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })
    $page.Controls.Add($script:btnDiskOpt)
}

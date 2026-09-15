function Build-DiskPage {
    $page = $script:Pages["Disk"]
    $page.Controls.Clear()

    $lblTitle = New-Label "磁盘优化" 20 22 500 30 $Fonts.Header $Theme.TextBright
    $page.Controls.Add($lblTitle)

    $lblDesc = New-Label "SSD 执行 TRIM 优化 / HDD 执行碎片整理 / 清理系统组件" 20 56 760 24 $Fonts.Small $Theme.TextDim
    $page.Controls.Add($lblDesc)

    # 磁盘列表 — 统一走共享库（WMI，Win7 可用）
    # 此前用 Get-PhysicalDiskCompat，它把 WMI 的 "Fixed hard disk media" 一律判成 HDD，
    # 导致 SSD 也被标成 HDD。
    $physicalDisks = @(Get-PhysicalDiskInfo)

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
        # 统一走共享库：先逐卷判定介质（SSD/HDD），再分流优化。
        # 此前 GUI 对每个卷同时执行 TRIM 和碎片整理，且不区分介质 ——
        # 对 SSD 做碎片整理是无谓写入、损耗寿命；现在 SSD→TRIM、HDD→碎片整理。
        $r = Invoke-DiskOptimization -Trim $script:chkTRIM.Checked -Defrag $script:chkDefrag.Checked `
                -WinSxS $script:chkWinSxS.Checked -Compact $script:chkCompact.Checked
        foreach ($d in $r.details) { Write-Log "[磁盘] $d" }
        if (-not $r.ok) { Write-Log "[磁盘] 部分操作失败（可能需要管理员权限）" "WARN" }

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

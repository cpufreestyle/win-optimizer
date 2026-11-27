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
        # 只有真正需要关注的状态才用告警色；RAID/虚拟盘读到的 Unspecified 属于正常情况
        $mediaType = [string]$pd.MediaType
        $typeColor = switch ($mediaType) {
            "SSD" { $Theme.Success }
            "HDD" { $Theme.TextMain }
            default { $Theme.TextDim }
        }
        $typeText = switch ($mediaType) {
            "SSD" { "SSD" }
            "HDD" { "机械硬盘 (HDD)" }
            "SCM" { "存储级内存 (SCM)" }
            ""    { "未知（RAID / 虚拟盘）" }
            default {
                if ($mediaType -match '(?i)^(unspecified|unknown)$') { "未知（RAID / 虚拟盘）" } else { $mediaType }
            }
        }
        $card = New-Object System.Windows.Forms.Panel
        $card.Location = New-Object System.Drawing.Point(20, $yDisk)
        $card.Size = New-Object System.Drawing.Size(760, 50)
        $card.BackColor = $Theme.BgCard
        $page.Controls.Add($card)

        $lbl = New-Label "$($pd.FriendlyName)" 16 3 350 22 $Fonts.Body $Theme.TextBright
        $card.Controls.Add($lbl)

        $lblType = New-Label "类型: $typeText" 16 26 240 20 $Fonts.Small $typeColor
        $card.Controls.Add($lblType)

        $lblSize = New-Label "容量: ${sizeGB}GB" 260 26 200 20 $Fonts.Small $Theme.TextDim
        $card.Controls.Add($lblSize)

        $yDisk += 54
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
    # 默认值与 CLI / WebUI 同源：config 的 disk.compact_os_default（默认 false）
    $script:chkCompact.Checked = (Get-CompactOSDefault)
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

    # ==================== C 盘程序迁移到 D 盘 ====================
    # 上方「开始优化」按钮高 44，标题必须落在按钮底边之下（此前只 +20，标题压住按钮）
    $yDisk += 64
    $script:lblMigTitle = New-Label "C 盘程序迁移到 D 盘" 20 $yDisk 760 24 $Fonts.Sub $Theme.Accent
    $page.Controls.Add($script:lblMigTitle)
    $yDisk += 26
    $script:lblMigDesc = New-Label "扫描 C:\Program Files* 下的大型程序，复制到 D 盘并在原位建立目录联接；原路径继续有效、注册表无需改动。" 20 $yDisk 760 24 $Fonts.Small $Theme.TextDim
    $page.Controls.Add($script:lblMigDesc)
    $yDisk += 30
    # 勾选列表：单击即勾选（普通 ListBox 无法多选，也无法「全选」）
    $script:lstMigratable = New-Object System.Windows.Forms.CheckedListBox
    $script:lstMigratable.Location = New-Object System.Drawing.Point(20, $yDisk)
    $script:lstMigratable.Size = New-Object System.Drawing.Size(720, 130)
    $script:lstMigratable.Font = $Fonts.Body
    $script:lstMigratable.CheckOnClick = $true
    $script:lstMigratable.IntegralHeight = $false
    $script:lstMigratable.HorizontalScrollbar = $true
    $page.Controls.Add($script:lstMigratable)
    $yDisk += 140

    # 与列表行一一对应的数据：@{ Kind = 'cand'（可迁移）| 'migrated'（已迁移，可还原）; Data = 扫描对象 }
    # 迁移/还原直接按勾选行号取对象，不再从显示文字反解程序名
    # （此前大小带小数如 9798.06 MB，正则只认整数，导致「找不到该程序的扫描信息」）
    $script:MigItems = @()
    $script:RefreshMigList = {
        $items = @()
        $script:lstMigratable.BeginUpdate()
        try {
            $script:lstMigratable.Items.Clear()
            foreach ($m in @(Get-MigratedPrograms -TargetDrive "D:" | Where-Object { $_.IsJunction })) {
                $items += [PSCustomObject]@{ Kind = 'migrated'; Data = $m }
                $script:lstMigratable.Items.Add(("[已迁移] {0}  ({1} MB)  → {2}" -f $m.Name, $m.SizeMB, $m.JunctionTarget)) | Out-Null
            }
            foreach ($c in @(Get-MigratablePrograms)) {
                $items += [PSCustomObject]@{ Kind = 'cand'; Data = $c }
                $script:lstMigratable.Items.Add(("{0}  ({1} MB)" -f $c.Name, $c.SizeMB)) | Out-Null
            }
        } finally {
            $script:lstMigratable.EndUpdate()
        }
        $script:MigItems = $items
        $script:BtnMigAll.Text = "全选"
        Write-Log ("[迁移] 扫描完成：可迁移 {0} 个，已迁移 {1} 个" -f @($items | Where-Object { $_.Kind -eq 'cand' }).Count, @($items | Where-Object { $_.Kind -eq 'migrated' }).Count) "INFO"
    }
    # 取勾选行中指定类型的扫描对象
    $script:GetCheckedMig = {
        param([string]$Kind)
        foreach ($idx in @($script:lstMigratable.CheckedIndices)) {
            if ($idx -lt $script:MigItems.Count -and $script:MigItems[$idx].Kind -eq $Kind) { $script:MigItems[$idx].Data }
        }
    }

    $script:BtnScanMig = New-Button "扫描可迁移程序" 20 $yDisk 165 44 $Theme.Accent 10
    $script:BtnScanMig.Add_Click({
        try {
            $this.Enabled = $false
            $this.Text = "扫描中..."
            Invoke-UIRefresh
            & $script:RefreshMigList
        } catch {
            [System.Windows.Forms.MessageBox]::Show("扫描失败: $($_.Exception.Message)", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        } finally {
            $this.Enabled = $true
            $this.Text = "扫描可迁移程序"
        }
    })
    $page.Controls.Add($script:BtnScanMig)

    $script:BtnMigAll = New-Button "全选" 200 $yDisk 100 44 $Theme.AccentDark 10
    $script:BtnMigAll.Add_Click({
        $n = $script:lstMigratable.Items.Count
        if ($n -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("列表为空，请先点击「扫描可迁移程序」。", "提示", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }
        # 未全部勾选 → 全选；已全部勾选 → 取消全选
        $check = ($script:lstMigratable.CheckedIndices.Count -lt $n)
        for ($i = 0; $i -lt $n; $i++) { $script:lstMigratable.SetItemChecked($i, $check) }
        $this.Text = if ($check) { "取消全选" } else { "全选" }
    })
    $page.Controls.Add($script:BtnMigAll)

    $script:BtnMigrate = New-Button "迁移勾选到 D 盘" 315 $yDisk 180 44 $Theme.Success 10
    $script:BtnMigrate.Add_Click({
        $sel = @(& $script:GetCheckedMig 'cand')
        if ($sel.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("请先勾选要迁移的程序（「[已迁移]」项只能还原）。", "提示", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }
        $totalMB = [math]::Round([double](@($sel | Measure-Object -Property SizeMB -Sum).Sum), 2)
        $names = (@($sel | Select-Object -First 10) | ForEach-Object { "· {0}  ({1} MB)" -f $_.Name, $_.SizeMB }) -join "`n"
        if ($sel.Count -gt 10) { $names += "`n……共 $($sel.Count) 个" }
        $yes = [System.Windows.Forms.MessageBox]::Show(
            ("将把以下 {0} 个程序（约 {1} MB）迁移到 D 盘，并在原位置建立目录联接，原路径继续有效：`n{2}`n`n请先退出这些程序。继续吗？" -f $sel.Count, $totalMB, $names),
            "迁移到 D 盘",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($yes -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        $btnText = $this.Text
        $this.Enabled = $false
        $okCount = 0; $freed = 0; $fails = @(); $leftovers = @()
        try {
            for ($k = 0; $k -lt $sel.Count; $k++) {
                $c = $sel[$k]
                $this.Text = ("迁移中 {0}/{1}" -f ($k + 1), $sel.Count)
                Invoke-UIRefresh
                try {
                    $r = Move-ProgramToDrive -SourcePath $c.Path -TargetDrive "D:" -Confirm
                    if ($r.ok -and $r.moved) {
                        $okCount++
                        $freed += $r.freedMB
                        if ($r.leftover) { $leftovers += $r.leftover }
                        Write-Log ("[迁移] {0} -> {1}，释放约 {2} MB" -f $c.Path, $r.junction, $r.freedMB) "SUCCESS"
                    } else {
                        $why = if ($r.error) { $r.error } else { $r.reason }
                        $fails += ("{0}：{1}" -f $c.Name, $why)
                        Write-Log ("[迁移] 未迁移 {0}：{1}" -f $c.Path, $why) "WARN"
                    }
                } catch {
                    $fails += ("{0}：{1}" -f $c.Name, $_.Exception.Message)
                    Write-Log ("[迁移] 迁移出错 {0}：{1}" -f $c.Path, $_.Exception.Message) "ERROR"
                }
            }
        } finally {
            $this.Text = $btnText
            $this.Enabled = $true
        }
        $msg = "迁移结束：成功 {0} 个，未迁移 {1} 个，C 盘释放约 {2} MB" -f $okCount, $fails.Count, [math]::Round($freed, 2)
        if ($fails.Count -gt 0) { $msg += "`n`n未迁移：`n" + ((@($fails | Select-Object -First 8)) -join "`n") }
        if ($leftovers.Count -gt 0) { $msg += "`n`n以下旧目录未删干净，重启后可手动删除：`n" + ($leftovers -join "`n") }
        $icon = if ($fails.Count -gt 0) { [System.Windows.Forms.MessageBoxIcon]::Warning } else { [System.Windows.Forms.MessageBoxIcon]::Information }
        [System.Windows.Forms.MessageBox]::Show($msg, "迁移结果", [System.Windows.Forms.MessageBoxButtons]::OK, $icon) | Out-Null
        try { & $script:RefreshMigList } catch {}
    })
    $page.Controls.Add($script:BtnMigrate)

    $script:BtnRestore = New-Button "还原勾选到 C 盘" 510 $yDisk 180 44 $Theme.Warning 10
    $script:BtnRestore.Add_Click({
        $sel = @(& $script:GetCheckedMig 'migrated')
        if ($sel.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("请先勾选列表中「[已迁移]」开头的项目再还原。", "提示", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }
        $names = (@($sel | Select-Object -First 10) | ForEach-Object { "· {0}  ({1} MB)" -f $_.Name, $_.SizeMB }) -join "`n"
        $yes = [System.Windows.Forms.MessageBox]::Show(
            ("将把以下 {0} 个程序从 D 盘拷回 C 盘原路径，复制成功后才删除目录联接（D 盘副本保留，可手动删除）：`n{1}`n`n继续吗？" -f $sel.Count, $names),
            "还原到 C 盘",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($yes -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        $btnText = $this.Text
        $this.Enabled = $false
        $okCount = 0; $fails = @()
        try {
            for ($k = 0; $k -lt $sel.Count; $k++) {
                $m = $sel[$k]
                $this.Text = ("还原中 {0}/{1}" -f ($k + 1), $sel.Count)
                Invoke-UIRefresh
                try {
                    $r = Restore-MigratedProgram -JunctionPath $m.Junction -TargetDrive "D:" -Confirm
                    if ($r.ok -and $r.restored) {
                        $okCount++
                        Write-Log ("[迁移] 已还原 {0}" -f $m.Junction) "SUCCESS"
                    } else {
                        $why = if ($r.error) { $r.error } else { $r.reason }
                        $fails += ("{0}：{1}" -f $m.Name, $why)
                        Write-Log ("[迁移] 未还原 {0}：{1}" -f $m.Junction, $why) "WARN"
                    }
                } catch {
                    $fails += ("{0}：{1}" -f $m.Name, $_.Exception.Message)
                    Write-Log ("[迁移] 还原出错 {0}：{1}" -f $m.Junction, $_.Exception.Message) "ERROR"
                }
            }
        } finally {
            $this.Text = $btnText
            $this.Enabled = $true
        }
        $msg = "还原结束：成功 {0} 个，未还原 {1} 个" -f $okCount, $fails.Count
        if ($fails.Count -gt 0) { $msg += "`n`n未还原：`n" + ((@($fails | Select-Object -First 8)) -join "`n") }
        $icon = if ($fails.Count -gt 0) { [System.Windows.Forms.MessageBoxIcon]::Warning } else { [System.Windows.Forms.MessageBoxIcon]::Information }
        [System.Windows.Forms.MessageBox]::Show($msg, "还原结果", [System.Windows.Forms.MessageBoxButtons]::OK, $icon) | Out-Null
        try { & $script:RefreshMigList } catch {}
    })
    $page.Controls.Add($script:BtnRestore)
}

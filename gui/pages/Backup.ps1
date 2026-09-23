# 渲染单个域的还原结果（与 CLI 的 Show-RestoreReport 同款文案）
function Show-BackupRestoreReport {
    param([string]$Label, $Result)
    if (-not $Result) { Write-Log "    [失败] $Label : 未返回结果" "ERROR"; return }
    foreach ($d in @($Result.details)) {
        if ($d -is [string]) {
            Write-Log "    $d"
        } else {
            Write-Log "    $($d.name) : $($d.result)"
        }
    }
    if ($Result.error) {
        Write-Log "    [失败] $Label : $($Result.error)" "ERROR"
    } else {
        Write-Log "    [完成] $Label（还原 $($Result.restored) 项）" "SUCCESS"
    }
}

# 渲染一键回滚结果
function Show-BackupRollbackReport {
    param($Result)
    if (-not $Result) { Write-Log "回滚未返回结果。" "ERROR"; return }
    if (-not $Result.ok -and @($Result.results).Count -eq 0) {
        Write-Log "回滚失败: $($Result.error)" "ERROR"
        return
    }
    $modeText = if ($Result.mode -eq 'file') { '单个备份' } else { '回到时间点' }
    Write-Log "回滚方式: $modeText；目标时点: $($Result.since)"
    foreach ($s in @($Result.results)) {
        $mark = if ($s.ok) { '[成功]' } else { '[失败]' }
        $lvl  = if ($s.ok) { "SUCCESS" } else { "ERROR" }
        Write-Log ("  {0} {1} ← {2}" -f $mark, $s.domainLabel, $s.file) $lvl
        if ($s.summary)      { Write-Log "        $($s.summary)" }
        if ($s.safetyBackup) { Write-Log "        回滚前已备份当前状态: $(Split-Path -Leaf $s.safetyBackup)" }
        if ($s.error)        { Write-Log "        错误: $($s.error)" "ERROR" }
    }
    foreach ($s in @($Result.skipped)) {
        Write-Log "  [跳过] $($s.domainLabel) ：$($s.reason)" "WARN"
    }
    if (@($Result.safetyBackups).Count -gt 0) {
        Write-Log "如需再次反悔，可从上面这些「当前状态备份」中恢复。"
    }
}
function Build-BackupPage {
    $page = $script:Pages["Backup"]
    $page.Controls.Clear()
    $lblTitle = New-Label "备份恢复" 20 22 500 30 $Fonts.Header $Theme.TextBright
    $page.Controls.Add($lblTitle)
    $lblDesc = New-Label "查看优化时间线，可恢复单个域，或一键回滚到某个时间点" 20 56 760 24 $Fonts.Small $Theme.TextDim
    $page.Controls.Add($lblDesc)
    $script:BackupDir = Join-Path $script:ProjectRoot "backups"
    if (-not (Test-Path $script:BackupDir)) {
        New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null
    }
    $y = 100
    # --- 创建备份（全部域，统一走 lib，与 CLI / WebUI 同源）---
    $btnCreate = New-Button "创建备份" 20 $y 160 44 $Theme.Success 11
    $btnCreate.Add_Click({
        $this.Enabled = $false
        $this.Text = "备份中..."
        Invoke-UIRefresh
        try {
            $ok = 0; $fail = 0; $lines = @()
            foreach ($dom in @('services', 'startup', 'visual', 'power', 'network', 'telemetry')) {
                $f = Backup-DomainState -Domain $dom -BackupDir $script:BackupDir
                if ($f) {
                    $ok++
                    $lines += ("  {0} ← {1}" -f (Get-BackupDomainLabel $dom), (Split-Path -Leaf $f))
                } else {
                    $fail++
                    $lines += ("  {0} ← 备份失败" -f (Get-BackupDomainLabel $dom))
                }
            }
            Write-Log ("备份完成：成功 {0} 项，失败 {1} 项`n{2}" -f $ok, $fail, ($lines -join "`n")) $(if ($fail -eq 0) { "SUCCESS" } else { "WARN" })
            [System.Windows.Forms.MessageBox]::Show(
                ("备份完成：成功 {0} 项，失败 {1} 项`n`n{2}" -f $ok, $fail, ($lines -join "`n")),
                "备份", [System.Windows.Forms.MessageBoxButtons]::OK,
                $(if ($fail -eq 0) { [System.Windows.Forms.MessageBoxIcon]::Information } else { [System.Windows.Forms.MessageBoxIcon]::Warning })) | Out-Null
            Build-BackupPage
        } catch {
            Write-Log "备份创建失败: $($_.Exception.Message)" "ERROR"
            [System.Windows.Forms.MessageBox]::Show("备份创建失败: $($_.Exception.Message)", "错误",
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        } finally {
            $this.Enabled = $true
            $this.Text = "创建备份"
        }
    })
    $page.Controls.Add($btnCreate)
    # --- 恢复最近备份：每个域取最近一份备份（lib 会先备份当前状态）---
    $btnRestore = New-Button "恢复最近备份" 195 $y 160 44 $Theme.Warning 11
    $btnRestore.Add_Click({
        $ans = [System.Windows.Forms.MessageBox]::Show(
            "将从每个域最近的备份恢复。`n`n还原前会先把当前状态备份一遍（可再次反悔），确认继续？",
            "确认恢复", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        Write-Log "开始从最近备份恢复..."
        try {
            $rb = Invoke-Rollback -BackupDir $script:BackupDir
            Show-BackupRollbackReport -Result $rb
            Build-BackupPage
        } catch {
            Write-Log "恢复失败: $($_.Exception.Message)" "ERROR"
        }
    })
    $page.Controls.Add($btnRestore)
    # --- 一键回滚向导 ---
    $btnRollback = New-Button "一键回滚向导" 370 $y 160 44 $Theme.Accent 11
    $btnRollback.Add_Click({
        try { Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue } catch { }
        if (-not ('Microsoft.VisualBasic.Interaction' -as [type])) {
            [System.Windows.Forms.MessageBox]::Show("当前环境不支持输入框，请使用「恢复最近备份」。", "提示",
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }
        $mode = [Microsoft.VisualBasic.Interaction]::InputBox(
            "回滚方式：`n1 = 回到指定时间点之前`n2 = 回退最近 N 条备份`n`n请输入 1 或 2", "一键回滚向导", "2")
        if ([string]::IsNullOrWhiteSpace($mode)) { return }
        $rbArgs = @{ BackupDir = $script:BackupDir }
        if ($mode -eq '1') {
            $t = [Microsoft.VisualBasic.Interaction]::InputBox(
                "时间点（yyyy-MM-dd HH:mm:ss）", "一键回滚向导", (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
            $dt = [datetime]::MinValue
            if (-not [datetime]::TryParse($t, [ref]$dt)) {
                Write-Log "时间格式无法识别，已取消。" "WARN"
                return
            }
            $rbArgs['Since'] = $dt
        } elseif ($mode -eq '2') {
            $nStr = [Microsoft.VisualBasic.Interaction]::InputBox("回退几条备份？", "一键回滚向导", "2")
            $cnt = 0
            if (-not [int]::TryParse($nStr, [ref]$cnt) -or $cnt -lt 1) {
                Write-Log "数量无效，已取消。" "WARN"
                return
            }
            $rbArgs['Last'] = $cnt
        } else {
            Write-Log "已取消回滚。" "WARN"
            return
        }
        try {
            $plan = Get-RollbackPlan @rbArgs
            if (-not $plan.ok) {
                Write-Log "无法生成回滚计划: $($plan.error)" "ERROR"
                return
            }
            $txt = @()
            $txt += ("目标时点: {0}" -f $plan.since)
            foreach ($e in @($plan.entries)) {
                $items = if ($e.metadataMissing) { '?' } else { "$($e.items)" }
                $txt += ("  {0} ← {1}（{2} 项）" -f $e.domainLabel, $e.file, $items)
            }
            foreach ($e in @($plan.skipped)) {
                $txt += ("  [跳过] {0}：{1}" -f $e.domainLabel, $e.reason)
            }
            $txt += ""
            $txt += "每个域还原前会先把当前状态备份一遍，可再次反悔。"
            $ans = [System.Windows.Forms.MessageBox]::Show(
                (($txt -join "`n") + "`n`n确认执行回滚？"), "回滚预览",
                [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) {
                Write-Log "已取消回滚。" "WARN"
                return
            }
            $rb = Invoke-Rollback @rbArgs
            Show-BackupRollbackReport -Result $rb
            Build-BackupPage
        } catch {
            Write-Log "回滚失败: $($_.Exception.Message)" "ERROR"
        }
    })
    $page.Controls.Add($btnRollback)
    $btnRefresh = New-Button "刷新列表" 545 $y 120 44 $Theme.AccentDark 10
    $btnRefresh.Add_Click({ Build-BackupPage })
    $page.Controls.Add($btnRefresh)
    $y += 62
    $lblTimeline = New-Label "优化时间线（新 → 旧）:" 20 $y 760 24 $Fonts.Body $Theme.TextBright
    $page.Controls.Add($lblTimeline)
    $y += 26
    $dgv = New-Object System.Windows.Forms.DataGridView
    $dgv.Location = New-Object System.Drawing.Point(20, $y)
    $dgv.Size = New-Object System.Drawing.Size(760, 250)
    $dgv.BackgroundColor = $Theme.BgPanel
    $dgv.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dgv.AllowUserToAddRows = $false
    $dgv.AllowUserToDeleteRows = $false
    $dgv.AllowUserToResizeRows = $false
    $dgv.ReadOnly = $true
    $dgv.RowHeadersVisible = $false
    $dgv.MultiSelect = $false
    $dgv.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $dgv.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $dgv.DefaultCellStyle.BackColor = $Theme.BgPanel
    $dgv.DefaultCellStyle.ForeColor = $Theme.TextMain
    $dgv.DefaultCellStyle.SelectionBackColor = $Theme.AccentDark
    $dgv.DefaultCellStyle.SelectionForeColor = $Theme.TextBright
    $dgv.ColumnHeadersDefaultCellStyle.BackColor = $Theme.BgCard
    $dgv.ColumnHeadersDefaultCellStyle.ForeColor = $Theme.TextBright
    $dgv.EnableHeadersVisualStyles = $false
    $dgv.Columns.Add("Time",  "时间")   | Out-Null
    $dgv.Columns.Add("Domain","域")     | Out-Null
    $dgv.Columns.Add("Items", "条目")   | Out-Null
    $dgv.Columns.Add("File",  "备份文件") | Out-Null
    $dgv.Columns.Add("Flag",  "标记")   | Out-Null
    $timeline = @(Get-OptimizationTimeline -BackupDir $script:BackupDir -Max 100)
    foreach ($e in $timeline) {
        $items = if ($e.metadataMissing) { '?' } else { "$($e.items)" }
        $flag  = if ($e.metadataMissing) { '元数据缺失' } else { '' }
        $row = $dgv.Rows.Add($e.timeText, $e.domainLabel, $items, $e.file, $flag)
        $dgv.Rows[$row].Tag = $e
    }
    $page.Controls.Add($dgv)
    $script:BkTimeline = $timeline
    if ($timeline.Count -eq 0) {
        $lblEmpty = New-Label "暂无备份。各优化步骤默认会自动备份，备份后即可在这里恢复或回滚。" 20 ($y + 258) 760 24 $Fonts.Small $Theme.TextDim
        $page.Controls.Add($lblEmpty)
    }
    $y += 262
    $btnRestoreSel = New-Button "恢复选中备份" 20 $y 160 44 $Theme.Warning 11
    $btnRestoreSel.Enabled = ($timeline.Count -gt 0)
    $btnRestoreSel.Add_Click({
        if ($dgv.SelectedRows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("请先在上方时间线中选择一条备份。", "提示",
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }
        $e = $dgv.SelectedRows[0].Tag
        if (-not $e) { return }
        $ans = [System.Windows.Forms.MessageBox]::Show(
            ("确定要恢复「{0}」的备份吗？`n`n{1}`n`n还原前会先备份该域当前状态。" -f $e.domainLabel, $e.file),
            "确认恢复", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        Write-Log "正在恢复: $($e.file)"
        try {
            # 修改必备份：先备份当前状态，再还原（后悔药）
            $sb = Backup-DomainState -Domain $e.domain -BackupDir $script:BackupDir
            if ($sb) { Write-Log "已备份当前$($e.domainLabel)状态: $(Split-Path -Leaf $sb)" }
            else     { Write-Log "警告：无法备份当前$($e.domainLabel)状态。" "WARN" }
            $r = Restore-DomainState -Domain $e.domain -File $e.path -BackupDir $script:BackupDir
            if (-not $r) {
                Write-Log "该域不支持自动还原，请手动处理。" "WARN"
                return
            }
            if ($r.error) {
                Write-Log "恢复失败: $($r.error)" "ERROR"
            } else {
                Write-Log "$($e.domainLabel) 已还原 $($r.restored) 项" "SUCCESS"
            }
            foreach ($d in @($r.details)) {
                if ($d -is [string]) { Write-Log "    $d" }
                else { Write-Log "    $($d.name) : $($d.result)" }
            }
            Build-BackupPage
        } catch {
            Write-Log "恢复失败: $($_.Exception.Message)" "ERROR"
        }
    })
    $page.Controls.Add($btnRestoreSel)
    $lblTip = New-Label "提示：还原只影响被还原的域；每个域还原前都会先备份当前状态。" 195 $y 580 24 $Fonts.Small $Theme.TextDim
    $page.Controls.Add($lblTip)
}
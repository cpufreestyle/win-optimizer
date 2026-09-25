function Build-HealthPage {
    $page = $script:Pages["Health"]
    $page.Controls.Clear()

    $lblTitle = New-Label "系统体检" 20 22 500 30 $Fonts.Header $Theme.TextBright
    $page.Controls.Add($lblTitle)

    $lblDesc = New-Label "只读扫描并给出体检分与建议；优化后可再次体检查看前后对比（不会修改任何设置）" 20 56 760 24 $Fonts.Small $Theme.TextDim
    $page.Controls.Add($lblDesc)

    # 体检分
    $script:LblHealthScore = New-Label "—" 20 96 260 48 $Fonts.Title $Theme.Accent
    $page.Controls.Add($script:LblHealthScore)

    $script:LblHealthGrade = New-Label "尚未体检" 300 112 300 28 $Fonts.Sub $Theme.TextDim
    $page.Controls.Add($script:LblHealthGrade)

    # 关键指标
    $lblMetrics = New-Label "关键指标" 20 160 300 24 $Fonts.Sub $Theme.Accent
    $page.Controls.Add($lblMetrics)

    $script:TxtHealthMetrics = New-Object System.Windows.Forms.TextBox
    $script:TxtHealthMetrics.Location = New-Object System.Drawing.Point(20, 190)
    $script:TxtHealthMetrics.Size = New-Object System.Drawing.Size(760, 150)
    $script:TxtHealthMetrics.Font = $Fonts.Mono
    $script:TxtHealthMetrics.ForeColor = $Theme.TextMain
    $script:TxtHealthMetrics.BackColor = $Theme.BgCard
    $script:TxtHealthMetrics.Multiline = $true
    $script:TxtHealthMetrics.ReadOnly = $true
    $script:TxtHealthMetrics.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $script:TxtHealthMetrics.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $script:TxtHealthMetrics.Text = "点击「开始体检」以扫描。"
    $script:TxtHealthMetrics.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $page.Controls.Add($script:TxtHealthMetrics)

    # 问题清单
    $lblIssues = New-Label "问题清单" 20 356 300 24 $Fonts.Sub $Theme.Accent
    $page.Controls.Add($lblIssues)

    $script:TxtHealthIssues = New-Object System.Windows.Forms.TextBox
    $script:TxtHealthIssues.Location = New-Object System.Drawing.Point(20, 386)
    $script:TxtHealthIssues.Size = New-Object System.Drawing.Size(760, 140)
    $script:TxtHealthIssues.Font = $Fonts.Body
    $script:TxtHealthIssues.ForeColor = $Theme.TextMain
    $script:TxtHealthIssues.BackColor = $Theme.BgCard
    $script:TxtHealthIssues.Multiline = $true
    $script:TxtHealthIssues.ReadOnly = $true
    $script:TxtHealthIssues.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $script:TxtHealthIssues.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $script:TxtHealthIssues.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $page.Controls.Add($script:TxtHealthIssues)

    # 自动修复预览（只读：只展示「将做什么」，不执行）
    $lblRemediation = New-Label "自动修复预览" 20 540 300 24 $Fonts.Sub $Theme.Accent
    $page.Controls.Add($lblRemediation)

    $script:TxtHealthRemediation = New-Object System.Windows.Forms.TextBox
    $script:TxtHealthRemediation.Location = New-Object System.Drawing.Point(20, 570)
    $script:TxtHealthRemediation.Size = New-Object System.Drawing.Size(760, 130)
    $script:TxtHealthRemediation.Font = $Fonts.Small
    $script:TxtHealthRemediation.ForeColor = $Theme.TextMain
    $script:TxtHealthRemediation.BackColor = $Theme.BgCard
    $script:TxtHealthRemediation.Multiline = $true
    $script:TxtHealthRemediation.ReadOnly = $true
    $script:TxtHealthRemediation.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $script:TxtHealthRemediation.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $script:TxtHealthRemediation.Text = "体检后这里会列出可一键修复的项目、目标与预估影响。"
    $script:TxtHealthRemediation.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $page.Controls.Add($script:TxtHealthRemediation)

    # 执行按钮
    $script:BtnHealthScan = New-Button "开始体检" 20 716 150 40 $Theme.Success 11
    $script:BtnHealthScan.Add_Click({
        try {
            $this.Enabled = $false
            $this.Text = "体检中..."
            $script:LblHealthScore.Text = "..."
            $script:LblHealthGrade.Text = "扫描中"
            $script:TxtHealthMetrics.Text = ""
            $script:TxtHealthIssues.Text = ""
            $script:TxtHealthRemediation.Text = ""
            Invoke-UIRefresh

            # 先取上一次报告（在保存本次之前），用于对比
            $prev = Get-PreviousHealthReport -BackupDir $script:BackupDir
            $r = Get-SystemHealthReport
            $null = Save-HealthReport -Report $r -BackupDir $script:BackupDir
            # 供「一键修复」复用本次报告，避免重复扫描
            $script:HealthReport = $r

            $color = if ($r.score -ge 90) { $Theme.Success }
                     elseif ($r.score -ge 75) { $Theme.Accent }
                     else { $Theme.Warning }
            $script:LblHealthScore.Text = "$($r.score) / 100"
            $script:LblHealthScore.ForeColor = $color
            $script:LblHealthGrade.Text = $r.grade

            # --- 关键指标 ---
            $m = $r.metrics
            $lines = @()
            $lines += ("内存         : 可用 {0}MB / 共 {1}MB（{2}%）" -f $m.freeRamMB, $m.totalRamMB, $m.freeRamPct)
            $lines += ("启动项       : {0} 项" -f $m.startupCount)
            $lines += ("自动启动服务 : {0} / {1}（可优化）" -f $m.servicesStillAuto, $m.optimizableServices)
            $lines += ("视觉特效     : 未关闭 {0} / {1}" -f $m.visualTogglesLeft, $m.visualTogglesTotal)
            $lines += ("电源计划     : {0}" -f $m.powerPlanTitle)
            if ($null -ne $m.cleanableMB) { $lines += ("可清理空间   : {0} MB" -f $m.cleanableMB) }
            $lines += ("活动网卡     : {0} 个" -f $m.activeAdapters)
            foreach ($d in @($m.volumes)) {
                $lines += ("分区 {0}:     : 可用 {1}GB / 共 {2}GB（已用 {3}%）[{4}]" -f $d.drive, $d.freeGB, $d.totalGB, $d.usedPct, $d.media)
            }
            # --- 体检趋势（迷你 sparkline，与 CLI/WebUI 同源数据）---
            $trendPoints = @(Get-HealthTrend -BackupDir $script:BackupDir -Days 30)
            if ($trendPoints.Count -ge 2) {
                $spark    = Format-Sparkline -Values ([double[]]@($trendPoints | ForEach-Object { [double]$_.score }))
                $minScore = (@($trendPoints.score) | Measure-Object -Minimum).Minimum
                $maxScore = (@($trendPoints.score) | Measure-Object -Maximum).Maximum
                $lines += ("体检趋势     : {0}（近30天 {1} 次，{2} → {3} 分，最低 {4} 最高 {5}）" -f $spark, $trendPoints.Count, $trendPoints[0].score, $trendPoints[-1].score, $minScore, $maxScore)
            }
            $script:TxtHealthMetrics.Lines = $lines

            # --- 问题清单 ---
            if (@($r.issues).Count -eq 0) {
                $script:TxtHealthIssues.Lines = @("未发现明显问题，系统状态良好。")
            } else {
                $order = @{ 'High' = 0; 'Medium' = 1; 'Low' = 2 }
                $out = @()
                foreach ($i in ($r.issues | Sort-Object { $order[$_.severity] })) {
                    $out += "[$($i.severity)] $($i.title)"
                    $out += "    $($i.detail)"
                    $out += "    建议: $($i.suggestion)"
                    $out += ""
                }
                $script:TxtHealthIssues.Lines = $out
            }

            # --- 自动修复预览（只读，来源与 CLI/WebUI 完全一致）---
            $plan = @(Get-HealthRemediationPlan -Report $r -SkipCleanScan)
            $script:HealthPlan = $plan
            $script:BtnHealthFix.Enabled = (@($plan | Where-Object { $_.auto }).Count -gt 0)
            $pl = @()
            foreach ($p in $plan) {
                $flag = if ($p.auto) { '[可修复]' } else { '[仅建议]' }
                $pl += ("{0} [{1}] {2}" -f $flag, $p.severity, $p.title)
                $pl += ("    动作: {0} -> {1}" -f $p.action, $p.target)
                $pl += ("    影响: {0}" -f $p.impact)
                $pl += ""
            }
            if ($pl.Count -eq 0) { $pl = @("未发现可自动修复的项目。") }
            else {
                $pl += "说明: 每步执行前会自动备份；High 级高危项不会自动执行。"
            }
            $script:TxtHealthRemediation.Lines = $pl

            # --- 与上次对比 ---
            $script:LblHealthCompare.Text = if ($prev) {
                $c = Compare-HealthReports -Before $prev -After $r
                $sign = if ($c.scoreDelta -gt 0) { "+$($c.scoreDelta)" } else { "$($c.scoreDelta)" }
                $txt = "上次 $($c.beforeScore) 分 → 本次 $($c.afterScore) 分（变化 $sign）"
                if (@($c.resolved).Count -gt 0) { $txt += "；已解决 $(@($c.resolved).Count) 项" }
                if (@($c.new).Count -gt 0) { $txt += "；新增 $(@($c.new).Count) 项" }
                if (@($c.resolved).Count -eq 0 -and @($c.new).Count -eq 0) { $txt += "；问题清单无变化" }
                $txt
            } else {
                "首次体检已记录；优化后再体检即可对比。"
            }

            Write-Log "体检完成: $($r.score) 分（$($r.grade)）" "SUCCESS"
            $this.Enabled = $true
            $this.Text = "开始体检"
        } catch {
            Write-Log "体检出错: $($_.Exception.Message)" "ERROR"
            $script:LblHealthGrade.Text = "体检失败"
            $this.Enabled = $true
            $this.Text = "开始体检"
        }
    })
    $page.Controls.Add($script:BtnHealthScan)

    # 一键修复按钮：确认后执行，每步前自动备份
    $script:BtnHealthFix = New-Button "一键修复" 180 716 150 40 $Theme.Warning 11
    $script:BtnHealthFix.Enabled = $false

    # 执行前先建系统还原点（P1-3）；默认值与 CLI / WebUI 同源（config 的 safety.create_restore_point）
    $script:chkHealthRp = New-Object System.Windows.Forms.CheckBox
    $script:chkHealthRp.Location = New-Object System.Drawing.Point(515, 722)
    $script:chkHealthRp.Size = New-Object System.Drawing.Size(265, 24)
    $script:chkHealthRp.Text = "执行前先建系统还原点"
    $script:chkHealthRp.Checked = (Get-RestorePointDefault)
    $script:chkHealthRp.Font = $Fonts.Body
    $script:chkHealthRp.ForeColor = $Theme.TextMain
    $script:chkHealthRp.BackColor = $Theme.BgDark
    $script:chkHealthRp.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $page.Controls.Add($script:chkHealthRp)

    $script:BtnHealthFix.Add_Click({
        try {
            if (-not $script:HealthReport) {
                [System.Windows.Forms.MessageBox]::Show("请先点击「开始体检」。", "提示", `
                    [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                return
            }
            $plan = @($script:HealthPlan | Where-Object { $_.auto })
            if ($plan.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show("当前没有可自动修复的项目。", "提示", `
                    [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                return
            }
            $preview = ""
            foreach ($p in $plan) { $preview += ("[{0}] {1}`n    {2} -> {3}`n" -f $p.severity, $p.title, $p.action, $p.target) }
            $ans = [System.Windows.Forms.MessageBox]::Show(
                "将执行以下修复（每步前自动备份）:`n`n$preview`n是否继续？",
                "确认一键修复",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }

            $this.Enabled = $false
            $this.Text = "修复中..."
            Invoke-UIRefresh

            $rr = Invoke-HealthRemediation -Report $script:HealthReport -MaxSeverity 'Medium' `
                                           -BackupDir $script:BackupDir -SkipCleanScan `
                                           -CreateRestorePoint $script:chkHealthRp.Checked
            foreach ($s in @($rr.results)) {
                if ($s.ok) { Write-Log "修复 [$($s.domain)] $($s.id)：$($s.summary)" "SUCCESS" }
                else { Write-Log "修复 [$($s.domain)] $($s.id) 失败：$($s.error)" "ERROR" }
                if ($s.backup) { Write-Log "  备份: $($s.backup)" "INFO" }
            }
            foreach ($s in @($rr.skipped)) { Write-Log "跳过 $($s.id)：$($s.reason)" "INFO" }

            $rpTxt = ''
            if ($rr.restorePoint) {
                if ($rr.restorePoint.ok) {
                    $rpTxt = "`n`n[系统还原点已创建] $($rr.restorePoint.name) ($($rr.restorePoint.method))"
                    Write-Log "系统还原点已创建: $($rr.restorePoint.name)" "SUCCESS"
                } else {
                    $rpTxt = "`n`n[还原点创建失败] $($rr.restorePoint.error)（已继续执行修复）"
                    Write-Log "系统还原点创建失败: $($rr.restorePoint.error)" "WARNING"
                }
            }
            $doneTxt = if ($rr.ok) { "修复完成，建议重新体检查看前后对比。" }
                       else { "部分项目修复失败，详情见日志。" }
            [System.Windows.Forms.MessageBox]::Show(($doneTxt + $rpTxt), "一键修复", `
                [System.Windows.Forms.MessageBoxButtons]::OK, `
                [System.Windows.Forms.MessageBoxIcon]::Information)

            $this.Enabled = $true
            $this.Text = "一键修复"
            # 修复后自动重新体检，让分数与预览立即刷新
            $script:BtnHealthScan.PerformClick()
        } catch {
            Write-Log "自动修复出错: $($_.Exception.Message)" "ERROR"
            $this.Enabled = $true
            $this.Text = "一键修复"
        }
    })
    $page.Controls.Add($script:BtnHealthFix)

    # 导出前后对比报告（自包含 HTML / Markdown，默认输出到桌面）
    $script:BtnHealthExport = New-Button "导出对比报告" 350 716 150 40 $Theme.Success 11
    $script:BtnHealthExport.Add_Click({
        try {
            $pick = [System.Windows.Forms.MessageBox]::Show(
                "是否导出前后对比报告？`n`n[是] HTML（单文件，可直接发帖）`n[否] Markdown（纯文本，贴吧友好）`n[取消] 不导出`n`n文件默认输出到桌面。",
                "导出对比报告",
                [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
                [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($pick -eq [System.Windows.Forms.DialogResult]::Cancel) { return }
            $fmt = if ($pick -eq [System.Windows.Forms.DialogResult]::No) { 'Markdown' } else { 'Html' }
            $exp = Export-HealthReport -Format $fmt -BackupDir $script:BackupDir
            if ($exp.ok) {
                Write-Log "对比报告已导出: $($exp.file)" "SUCCESS"
                [System.Windows.Forms.MessageBox]::Show(
                    "对比报告已导出：`n$($exp.file)`n`n可直接作为附件发帖求助。",
                    "导出成功",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information)
            } else {
                Write-Log "对比报告导出失败: $($exp.error)" "ERROR"
                [System.Windows.Forms.MessageBox]::Show(
                    "导出失败：$($exp.error)`n`n需要至少两次体检历史记录才能对比。",
                    "导出失败",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning)
            }
        } catch {
            Write-Log "导出报告异常: $($_.Exception.Message)" "ERROR"
        }
    })
    $page.Controls.Add($script:BtnHealthExport)

    # 对比结果提示
    $script:LblHealthCompare = New-Label "点击「开始体检」后，这里会显示与上一次体检的对比。" 340 726 440 24 $Fonts.Small $Theme.TextDim
    $script:LblHealthCompare.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $page.Controls.Add($script:LblHealthCompare)
}

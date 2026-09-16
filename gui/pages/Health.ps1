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
    $script:TxtHealthIssues.Size = New-Object System.Drawing.Size(760, 180)
    $script:TxtHealthIssues.Font = $Fonts.Body
    $script:TxtHealthIssues.ForeColor = $Theme.TextMain
    $script:TxtHealthIssues.BackColor = $Theme.BgCard
    $script:TxtHealthIssues.Multiline = $true
    $script:TxtHealthIssues.ReadOnly = $true
    $script:TxtHealthIssues.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $script:TxtHealthIssues.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $script:TxtHealthIssues.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $page.Controls.Add($script:TxtHealthIssues)

    # 执行按钮
    $script:BtnHealthScan = New-Button "开始体检" 20 586 160 40 $Theme.Success 11
    $script:BtnHealthScan.Add_Click({
        try {
            $this.Enabled = $false
            $this.Text = "体检中..."
            $script:LblHealthScore.Text = "..."
            $script:LblHealthGrade.Text = "扫描中"
            $script:TxtHealthMetrics.Text = ""
            $script:TxtHealthIssues.Text = ""
            Invoke-UIRefresh

            # 先取上一次报告（在保存本次之前），用于对比
            $prev = Get-PreviousHealthReport -BackupDir $script:BackupDir
            $r = Get-SystemHealthReport
            $null = Save-HealthReport -Report $r -BackupDir $script:BackupDir

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

    # 对比结果提示
    $script:LblHealthCompare = New-Label "点击「开始体检」后，这里会显示与上一次体检的对比。" 200 596 580 24 $Fonts.Small $Theme.TextDim
    $script:LblHealthCompare.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $page.Controls.Add($script:LblHealthCompare)
}

function Show-GuidedStepRisk {
    param($Step)
    if (-not $Step) { return '' }
    $auto = $true
    if ($Step.PSObject.Properties.Name -contains 'auto') { $auto = [bool]$Step.auto }
    if ((-not $auto) -or ($Step.risk -eq 'high')) { return '默认跳过' }
    if ($Step.risk -eq 'medium') { return '中风险' }
    return '安全'
}

function Build-GuidedPage {
    param([switch]$KeepPlan)

    <#
    一键向导页（GUI 专用向导页，替代原来的 MessageBox 弹窗流程）。
    与 CLI `Optimize.ps1 -Guided`、WebUI「一键向导」页同源：数据全部来自 lib 的 Get-GuidedPlan，
    执行仍走 Invoke-Profile（不传 -Force），对比走 Compare-HealthReports。
    #>
    $page = $script:Pages["Guided"]
    $page.Controls.Clear()

    $lblTitle = New-Label "一键向导" 20 22 500 30 $Fonts.Header $Theme.TextBright
    $page.Controls.Add($lblTitle)

    $lblDesc = New-Label "不用挑功能：先体检，按结果推荐一套方案，你看一眼再决定。每步执行前自动备份，可随时回滚" 20 56 760 24 $Fonts.Small $Theme.TextDim
    $page.Controls.Add($lblDesc)

    # --- 体检结果卡 ---
    $cardScore = New-Object System.Windows.Forms.Panel
    $cardScore.Location = New-Object System.Drawing.Point(20, 92)
    $cardScore.Size = New-Object System.Drawing.Size(760, 92)
    $cardScore.BackColor = $Theme.BgCard
    $page.Controls.Add($cardScore)

    if ($KeepPlan -and $script:GuidedPlan) {
        $p = $script:GuidedPlan.profile
        $cardScore.Controls.Add((New-Label ("体检得分  " + $script:GuidedPlan.score + " 分") 16 12 300 40 $Fonts.Title $Theme.Accent))
        $cardScore.Controls.Add((New-Label ("等级：" + $script:GuidedPlan.grade) 330 22 260 24 $Fonts.Sub $Theme.TextBright))
        $planText = "尚未生成方案"
        if ($p) { $planText = $p.title }
        $cardScore.Controls.Add((New-Label ("推荐方案：" + $planText) 330 52 380 24 $Fonts.Small $Theme.TextDim))
    } else {
        $cardScore.Controls.Add((New-Label "尚未体检" 16 12 300 40 $Fonts.Title $Theme.TextDim))
        $cardScore.Controls.Add((New-Label "点击下方「开始体检并推荐」按钮，向导会自动挑选适合这台电脑的方案" 16 56 700 24 $Fonts.Small $Theme.TextDim))
    }

    $y = 200

    # --- 推荐理由 / 环境信息 ---
    if ($KeepPlan -and $script:GuidedPlan) {
        $txtInfo = @()
        $p = $script:GuidedPlan.profile
        if ($p -and $p.reason) { $txtInfo += ("推荐理由：" + $p.reason) }
        if ($script:GuidedPlan.powerPlan) { $txtInfo += ("电源计划：" + $script:GuidedPlan.powerPlan) }
        if ($script:GuidedPlan.dns) { $txtInfo += ("DNS：" + $script:GuidedPlan.dns) }
        $script:TxtGuidedInfo = New-Object System.Windows.Forms.TextBox
        $script:TxtGuidedInfo.Location = New-Object System.Drawing.Point(20, $y)
        $script:TxtGuidedInfo.Size = New-Object System.Drawing.Size(760, 60)
        $script:TxtGuidedInfo.Font = $Fonts.Body
        $script:TxtGuidedInfo.ForeColor = $Theme.TextMain
        $script:TxtGuidedInfo.BackColor = $Theme.BgCard
        $script:TxtGuidedInfo.Multiline = $true
        $script:TxtGuidedInfo.ReadOnly = $true
        $script:TxtGuidedInfo.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
        $script:TxtGuidedInfo.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $script:TxtGuidedInfo.Text = ($txtInfo -join "`r`n")
        $script:TxtGuidedInfo.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
        $page.Controls.Add($script:TxtGuidedInfo)
        $y += 76
    }

    # --- 步骤表 ---
    $steps = @()
    if ($KeepPlan -and $script:GuidedPlan) { $steps = @($script:GuidedPlan.steps) }
    $page.Controls.Add((New-Label ("将执行的步骤（" + $steps.Count + " 项）") 20 $y 400 24 $Fonts.Sub $Theme.Accent))
    $y += 30

    $dgv = New-Object System.Windows.Forms.DataGridView
    $dgv.Location = New-Object System.Drawing.Point(20, $y)
    $dgv.Size = New-Object System.Drawing.Size(760, 150)
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
    $dgv.DefaultCellStyle.SelectionForeColor = $Theme.ButtonText
    $dgv.ColumnHeadersDefaultCellStyle.BackColor = $Theme.BgCard
    $dgv.ColumnHeadersDefaultCellStyle.ForeColor = $Theme.TextMain
    $dgv.EnableHeadersVisualStyles = $false
    $dgv.Columns.Add("Action", "将要做什么") | Out-Null
    $dgv.Columns.Add("Target", "目标")       | Out-Null
    $dgv.Columns.Add("Risk",   "风险")       | Out-Null
    foreach ($s in $steps) {
        $row = $dgv.Rows.Add($s.action, $s.target, (Show-GuidedStepRisk $s))
        $dgv.Rows[$row].Tag = $s
    }
    $page.Controls.Add($dgv)
    $y += 160

    # --- 需人工确认项 ---
    $manual = @()
    if ($KeepPlan -and $script:GuidedPlan) { $manual = @($script:GuidedPlan.manual) }
    $page.Controls.Add((New-Label ("需要你自己处理的（" + $manual.Count + " 项，向导不会动）") 20 $y 500 24 $Fonts.Sub $Theme.Warning))
    $y += 30

    $txtManual = New-Object System.Windows.Forms.TextBox
    $txtManual.Location = New-Object System.Drawing.Point(20, $y)
    $txtManual.Size = New-Object System.Drawing.Size(760, 70)
    $txtManual.Font = $Fonts.Small
    $txtManual.ForeColor = $Theme.TextMain
    $txtManual.BackColor = $Theme.BgCard
    $txtManual.Multiline = $true
    $txtManual.ReadOnly = $true
    $txtManual.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $txtManual.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    if ($manual.Count -gt 0) {
        $lines = @()
        foreach ($m in $manual) { $lines += ("· " + $m.action + "（主菜单对应编号可手动处理）") }
        $txtManual.Text = ($lines -join "`r`n")
    } else {
        $txtManual.Text = "没有需要你手动处理的项目。"
    }
    $txtManual.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $page.Controls.Add($txtManual)
    $y += 82

    # --- 操作按钮 ---
    if ($KeepPlan -and $script:GuidedPlan) {
        $btnRun = New-Button "按方案执行优化" 20 $y 190 42 $Theme.Success 10
    } else {
        $btnRun = New-Button "开始体检并推荐" 20 $y 190 42 $Theme.Success 10
    }
    $btnRun.Add_Click({
        if ($script:GuidedPlan -and $script:GuidedPlan.ok) { Invoke-GuidedRun } else { Invoke-GuidedScan }
    })
    $page.Controls.Add($btnRun)

    $btnRescan = New-Button "重新体检" 220 $y 130 42 $Theme.AccentDark 10
    $btnRescan.Add_Click({ Invoke-GuidedScan })
    $page.Controls.Add($btnRescan)

    $script:GuidedBackBtn = $btnRescan
    $page.Controls.Add((New-Label "执行过程中请耐心等待，界面可能短暂无响应，这属于正常现象" 370 ($y + 10) 400 24 $Fonts.Small $Theme.TextDim))
}

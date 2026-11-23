function Build-StartupPage {
    $page = $script:Pages["Startup"]
    $page.Controls.Clear()

    $lblTitle = New-Label "启动项管理" 20 22 500 30 $Fonts.Header $Theme.TextBright
    $page.Controls.Add($lblTitle)

    $lblDesc = New-Label "管理开机启动项，禁用不必要的程序以加快开机速度" 20 56 760 24 $Fonts.Small $Theme.TextDim
    $page.Controls.Add($lblDesc)

    # 扫描启动项 - 用 script 作用域保存
    # 统一走共享库：与 CLI / WebUI 同一份枚举逻辑
    # （此前 GUI 只有 3 个注册表路径且缺 WMI 系统启动命令源，现一并补齐）
    $script:StartupItems = @(Get-StartupItems)

    $script:DgvStartup = New-Object System.Windows.Forms.DataGridView
    $script:DgvStartup.Location = New-Object System.Drawing.Point(20, 96)
    # 高度收到 312：底边 408 必须留出按钮行（y=446）的空间
    $script:DgvStartup.Size = New-Object System.Drawing.Size(760, 312)
    $script:DgvStartup.BackgroundColor = $Theme.BgPanel
    $script:DgvStartup.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $script:DgvStartup.DefaultCellStyle.BackColor = $Theme.BgInput
    $script:DgvStartup.DefaultCellStyle.ForeColor = $Theme.TextMain
    $script:DgvStartup.DefaultCellStyle.Font = $Fonts.Small
    $script:DgvStartup.DefaultCellStyle.SelectionBackColor = $Theme.Accent
    $script:DgvStartup.DefaultCellStyle.SelectionForeColor = $Theme.ButtonText
    $script:DgvStartup.ColumnHeadersDefaultCellStyle.BackColor = $Theme.BgPanel
    $script:DgvStartup.ColumnHeadersDefaultCellStyle.ForeColor = $Theme.TextMain
    $script:DgvStartup.ColumnHeadersDefaultCellStyle.Font = $Fonts.Body
    $script:DgvStartup.EnableHeadersVisualStyles = $false
    $script:DgvStartup.AllowUserToAddRows = $false
    $script:DgvStartup.ReadOnly = $true
    $script:DgvStartup.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $script:DgvStartup.RowTemplate.Height = 28

    $dtStartup = New-Object System.Data.DataTable
    $dtStartup.Columns.Add("名称") | Out-Null
    $dtStartup.Columns.Add("来源") | Out-Null
    $dtStartup.Columns.Add("范围") | Out-Null
    $dtStartup.Columns.Add("命令") | Out-Null

    # 显式建列：页面构建时表格还没挂到窗体上，AutoGenerateColumns 拿不到列，
    # 之前直接改 Columns[i].Width 会被静默跳过；这里改用 FillWeight 固定列宽比例。
    $script:DgvStartup.AutoGenerateColumns = $false
    foreach ($spec in @(
            @{ Name = "名称"; Weight = 26 },
            @{ Name = "来源"; Weight = 16 },
            @{ Name = "范围"; Weight = 16 },
            @{ Name = "命令"; Weight = 42 })) {
        $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $col.Name = $spec.Name
        $col.HeaderText = $spec.Name
        $col.DataPropertyName = $spec.Name
        $col.FillWeight = $spec.Weight
        $col.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
        $script:DgvStartup.Columns.Add($col) | Out-Null
    }

    # 长文本按列宽截断（完整内容走悬停提示），避免文字顶到相邻列
    $nameMax = Get-GridTextBudget -FillWeight 26 -TotalWeight 100
    # 来源/范围 内容都是短语，权重虽小但实际只需要几十像素，放宽一档避免无谓截断
    $sourceMax = Get-GridTextBudget -FillWeight 16 -TotalWeight 100 -Factor 0.75
    $scopeMax = Get-GridTextBudget -FillWeight 16 -TotalWeight 100 -Factor 0.75
    $cmdMax = Get-GridTextBudget -FillWeight 42 -TotalWeight 100
    $startupTips = @{ "名称" = @(); "来源" = @(); "范围" = @(); "命令" = @() }
    foreach ($item in $script:StartupItems) {
        $cmdText = [string]$item.Value
        $nameShown = Get-UiEllipsisText -Text ([string]$item.Name) -Font $Fonts.Small -MaxWidth $nameMax
        $sourceShown = Get-UiEllipsisText -Text ([string]$item.Source) -Font $Fonts.Small -MaxWidth $sourceMax
        $scopeShown = Get-UiEllipsisText -Text ([string]$item.Scope) -Font $Fonts.Small -MaxWidth $scopeMax
        $cmdShown = Get-UiEllipsisText -Text $cmdText -Font $Fonts.Small -MaxWidth $cmdMax
        $dtStartup.Rows.Add($nameShown, $sourceShown, $scopeShown, $cmdShown) | Out-Null
        $startupTips["名称"] += [string]$item.Name
        $startupTips["来源"] += [string]$item.Source
        $startupTips["范围"] += [string]$item.Scope
        $startupTips["命令"] += $cmdText
    }
    $script:DgvStartup.DataSource = $dtStartup
    Enable-GridCellTips -Grid $script:DgvStartup -FullTextMap $startupTips
    $page.Controls.Add($script:DgvStartup)

    # 僵尸启动项：目标文件已不存在，禁用零风险；签名厂商仍按共享库的护栏跳过
    $script:ZeroRiskStartup = @()
    foreach ($item in $script:StartupItems) {
        $target = Get-StartupTargetPath -Item $item
        if (-not $target) { continue }
        if (Test-Path -LiteralPath $target) { continue }
        $script:ZeroRiskStartup += $item
    }
    $script:LblZeroRiskStartup = New-Label "检测到 $($script:ZeroRiskStartup.Count) 个目标文件已不存在的僵尸启动项（禁用零风险）" 20 414 760 20 $Fonts.Small $Theme.TextDim
    $page.Controls.Add($script:LblZeroRiskStartup)
    $script:BtnZeroRiskStartup = New-Button "禁用僵尸项" 20 440 160 36 $Theme.Warning 10
    $script:BtnZeroRiskStartup.Enabled = ($script:ZeroRiskStartup.Count -gt 0)
    $script:BtnZeroRiskStartup.Add_Click({
        try {
            if ($script:ZeroRiskStartup.Count -eq 0) { return }
            $ans = [System.Windows.Forms.MessageBox]::Show(
                "将禁用 $($script:ZeroRiskStartup.Count) 个目标文件已不存在的启动项（执行前自动备份）。是否继续？",
                "确认禁用僵尸启动项",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }
            $res = Disable-StartupItems -BackupDir $script:BackupDir -Items $script:ZeroRiskStartup
            Write-Log "僵尸启动项备份: $($res.backup)"
            foreach ($d in $res.details) { Write-Log "[$($d.Result)] $($d.Name)" }
            Write-Log "僵尸启动项处理完成：禁用 $($res.disabled) 项，失败 $($res.failed) 项" "SUCCESS"
            [System.Windows.Forms.MessageBox]::Show("已禁用 $($res.disabled) 个僵尸启动项。", "完成", `
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            Build-StartupPage
        } catch {
            Write-Log "禁用僵尸启动项出错: $($_.Exception.Message)" "ERROR"
            [System.Windows.Forms.MessageBox]::Show("禁用僵尸启动项出错: $($_.Exception.Message)", "错误", `
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })
    $page.Controls.Add($script:BtnZeroRiskStartup)

    $script:btnDisableStartup = New-Button "禁用选中项" 200 440 160 36 $Theme.Success 10
    $script:btnDisableStartup.Add_Click({
        try {
        if ($script:DgvStartup.SelectedRows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("请先选择要禁用的启动项（点击行左侧选择整行）", "提示", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            return
        }

        $toRemove = @()
        foreach ($row in $script:DgvStartup.SelectedRows) {
            $idx = $row.Index
            $toRemove += $script:StartupItems[$idx]
        }

        # 统一走共享库：备份 CSV 列名与 CLI / WebUI 一致。
        # 此前 GUI 导出的是 Name,Command,Scope,Source（缺 Path 列），
        # 导致 GUI 产生的启动项备份无法被 CLI 的恢复流程读取——本次一并修复。
        $res = Disable-StartupItems -BackupDir $script:BackupDir -Items $toRemove
        Write-Log "启动项备份: $($res.backup)"
        foreach ($d in $res.details) {
            if ($d.Result -like "已禁用*") {
                Write-Log "[禁用] $($d.Name) — $($d.Result)" "SUCCESS"
            } else {
                Write-Log "[$($d.Result)] $($d.Name)" "ERROR"
            }
            Invoke-UIRefresh
        }

        $count = $res.disabled
        Write-Log "启动项优化完成！已禁用 $count 项（失败 $($res.failed) 项）" "SUCCESS"
        [System.Windows.Forms.MessageBox]::Show("已禁用 $count 个启动项`n`n部分项需通过任务管理器->启动 禁用", "完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        Build-StartupPage
        } catch {
            Write-Log "启动项优化出错: $($_.Exception.Message)" "ERROR"
            [System.Windows.Forms.MessageBox]::Show("启动项优化出错: $($_.Exception.Message)", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })
    $page.Controls.Add($script:btnDisableStartup)

    $btnRefreshStartup = New-Button "刷新列表" 380 440 120 36 $Theme.AccentDark 10
    $btnRefreshStartup.Add_Click({ Build-StartupPage })
    $page.Controls.Add($btnRefreshStartup)
}

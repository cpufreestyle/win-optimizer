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
    $script:DgvStartup.Size = New-Object System.Drawing.Size(760, 360)
    $script:DgvStartup.BackgroundColor = $Theme.BgPanel
    $script:DgvStartup.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $script:DgvStartup.DefaultCellStyle.BackColor = $Theme.BgInput
    $script:DgvStartup.DefaultCellStyle.ForeColor = $Theme.TextMain
    $script:DgvStartup.DefaultCellStyle.Font = $Fonts.Small
    $script:DgvStartup.DefaultCellStyle.SelectionBackColor = $Theme.Accent
    $script:DgvStartup.DefaultCellStyle.SelectionForeColor = $Theme.TextBright
    $script:DgvStartup.ColumnHeadersDefaultCellStyle.BackColor = $Theme.BgPanel
    $script:DgvStartup.ColumnHeadersDefaultCellStyle.ForeColor = $Theme.TextBright
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

    foreach ($item in $script:StartupItems) {
        $cmdText = [string]$item.Value
        $cmd = if ($cmdText.Length -gt 60) { $cmdText.Substring(0, 57) + "..." } else { $cmdText }
        $dtStartup.Rows.Add($item.Name, $item.Source, $item.Scope, $cmd) | Out-Null
    }
    $script:DgvStartup.DataSource = $dtStartup
    $page.Controls.Add($script:DgvStartup)

    $script:btnDisableStartup = New-Button "禁用选中项" 20 446 160 40 $Theme.Success 10
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

    $btnRefreshStartup = New-Button "刷新列表" 190 446 120 40 $Theme.AccentDark 10
    $btnRefreshStartup.Add_Click({ Build-StartupPage })
    $page.Controls.Add($btnRefreshStartup)
}

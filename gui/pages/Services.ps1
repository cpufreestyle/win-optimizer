function Build-ServicesPage {
    $page = $script:Pages["Services"]
    $page.Controls.Clear()

    $lblTitle = New-Label "服务优化" 20 22 500 30 $Fonts.Header $Theme.TextBright
    $page.Controls.Add($lblTitle)

    $lblDesc = New-Label "禁用不必要的后台服务以释放 CPU 和内存资源" 20 56 760 24 $Fonts.Small $Theme.TextDim
    $page.Controls.Add($lblDesc)

    # 服务列表统一从共享库 Get-ServiceList 读取（单一数据源，优先 config/optimization.json）
    $servicesList = Get-ServiceList

    # DataGridView
    $dgv = New-Object System.Windows.Forms.DataGridView
    $dgv.Location = New-Object System.Drawing.Point(20, 96)
    $dgv.Size = New-Object System.Drawing.Size(760, 280)
    $dgv.BackgroundColor = $Theme.BgPanel
    $dgv.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dgv.DefaultCellStyle.BackColor = $Theme.BgInput
    $dgv.DefaultCellStyle.ForeColor = $Theme.TextMain
    $dgv.DefaultCellStyle.Font = $Fonts.Small
    $dgv.DefaultCellStyle.SelectionBackColor = $Theme.Accent
    $dgv.DefaultCellStyle.SelectionForeColor = $Theme.TextBright
    $dgv.ColumnHeadersDefaultCellStyle.BackColor = $Theme.BgPanel
    $dgv.ColumnHeadersDefaultCellStyle.ForeColor = $Theme.TextBright
    $dgv.ColumnHeadersDefaultCellStyle.Font = $Fonts.Body
    $dgv.EnableHeadersVisualStyles = $false
    $dgv.AllowUserToAddRows = $false
    $dgv.AllowUserToDeleteRows = $false
    $dgv.ReadOnly = $false
    $dgv.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $dgv.RowTemplate.Height = 28

    $dt = New-Object System.Data.DataTable
    $dt.Columns.Add("选择", [System.Type]::GetType("System.Boolean")) | Out-Null
    $dt.Columns.Add("服务名称") | Out-Null
    $dt.Columns.Add("描述") | Out-Null
    $dt.Columns.Add("级别") | Out-Null
    $dt.Columns.Add("状态") | Out-Null

    foreach ($svc in $servicesList) {
        $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        $status = if ($service) { $service.Status.ToString() } else { "未安装" }
        $check = $svc.Level -eq "安全禁用"
        $dt.Rows.Add($check, $svc.Name, $svc.Desc, $svc.Level, $status) | Out-Null
    }
    $dgv.DataSource = $dt

    # 设置列样式
    $dgv.AutoGenerateColumns = $true
    if ($dgv.Columns.Count -gt 0) {
        $dgv.Columns[0].Width = 50
        $dgv.Columns[0].ReadOnly = $false
        $dgv.Columns[1].Width = 150
        $dgv.Columns[1].ReadOnly = $true
        $dgv.Columns[2].AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
        $dgv.Columns[2].ReadOnly = $true
        if ($dgv.Columns.Count -gt 3) {
            $dgv.Columns[3].Width = 80
            $dgv.Columns[3].ReadOnly = $true
        }
        if ($dgv.Columns.Count -gt 4) {
            $dgv.Columns[4].Width = 70
            $dgv.Columns[4].ReadOnly = $true
        }
    }
    $page.Controls.Add($dgv)

    # 遥测任务
    $script:chkTelemetry = New-Object System.Windows.Forms.CheckBox
    $script:chkTelemetry.Location = New-Object System.Drawing.Point(20, 366)
    $script:chkTelemetry.Size = New-Object System.Drawing.Size(400, 24)
    $script:chkTelemetry.Text = "同时禁用遥测相关计划任务"
    $script:chkTelemetry.Checked = $true
    $script:chkTelemetry.Font = $Fonts.Body
    $script:chkTelemetry.ForeColor = $Theme.TextMain
    $script:chkTelemetry.BackColor = $Theme.BgDark
    $page.Controls.Add($script:chkTelemetry)

    # 按钮
    # 保存 DataTable 到 script 作用域
    $script:SvcDataTable = $dt

    $btnSafe = New-Button "仅安全禁用" 20 400 140 40 $Theme.Accent 10
    $btnSafe.Add_Click({
        for ($i = 0; $i -lt $script:SvcDataTable.Rows.Count; $i++) {
            $script:SvcDataTable.Rows[$i]["选择"] = ($script:SvcDataTable.Rows[$i]["级别"] -eq "安全禁用")
        }
    })
    $page.Controls.Add($btnSafe)

    $btnAll = New-Button "全选" 170 400 100 40 $Theme.AccentDark 10
    $btnAll.Add_Click({
        for ($i = 0; $i -lt $script:SvcDataTable.Rows.Count; $i++) { $script:SvcDataTable.Rows[$i]["选择"] = $true }
    })
    $page.Controls.Add($btnAll)

    $script:btnDisable = New-Button "执行禁用" 640 400 140 40 $Theme.Success 10
    $script:btnDisable.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $script:btnDisable.Add_Click({
        try {
        $this.Enabled = $false
        $this.Text = "处理中..."
        Invoke-UIRefresh

        # 备份与禁用统一走 lib（P3-1）：获得服务依赖护栏——被运行中服务依赖的服务
        # 默认跳过（details 里说明原因），避免连带故障；同时备份带 manifest，可回滚
        $picked = @()
        for ($i = 0; $i -lt $script:SvcDataTable.Rows.Count; $i++) {
            if ($script:SvcDataTable.Rows[$i]["选择"] -eq $true) {
                $picked += [PSCustomObject]@{
                    Name = [string]$script:SvcDataTable.Rows[$i]["服务名称"]
                    Level = "安全禁用"   # Mode=all，级别仅作展示语义保留
                    Desc  = [string]$script:SvcDataTable.Rows[$i]["描述"]
                }
            }
            Invoke-UIRefresh
        }
        $backupFile = Backup-ServiceStates -BackupDir $script:BackupDir -Services @(Get-ServiceList)
        Write-Log "服务备份已保存: $backupFile"

        $disabledCount = 0
        $r = Disable-Services -Services $picked -Mode "all"
        foreach ($d in $r.details) {
            $res = [string]$d.result
            if ($res -like "已禁用") {
                Write-Log "[禁用] $($d.name)" "SUCCESS"
                $disabledCount++
                for ($i = 0; $i -lt $script:SvcDataTable.Rows.Count; $i++) {
                    if ($script:SvcDataTable.Rows[$i]["服务名称"] -eq $d.name) {
                        $script:SvcDataTable.Rows[$i]["状态"] = "Stopped"
                    }
                }
            }
            elseif ($res -like "失败*") {
                Write-Log "[失败] $($d.name) —— $res" "ERROR"
            }
            else {
                Write-Log "[跳过] $($d.name) —— $res" "WARNING"
            }
            Invoke-UIRefresh
        }

        # 遥测任务
        if ($script:chkTelemetry.Checked) {
            $telemetry = Disable-TelemetryTasks -BackupDir $script:BackupDir
            foreach ($d in $telemetry.details) {
                if ($d.result -like "已禁用") { Write-Log "[禁用] 计划任务: $($d.name)" "SUCCESS" }
                elseif ($d.result -like "失败*") { Write-Log "[失败] 计划任务: $($d.name)" "ERROR" }
            }
            Write-Log "遥测计划任务：已禁用 $($telemetry.disabled) 个，跳过 $($telemetry.skipped) 个" "INFO"
            if ($telemetry.backup) { Write-Log "遥测任务备份: $($telemetry.backup)" "INFO" }
        }

        Write-Log "服务优化完成！已禁用 $disabledCount 个服务" "SUCCESS"
        $this.Enabled = $true
        $this.Text = "执行禁用"
        [System.Windows.Forms.MessageBox]::Show("服务优化完成！`n已禁用 $disabledCount 个服务`n`n备份文件: $backupFile", "完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            Write-Log "服务优化出错: $($_.Exception.Message)" "ERROR"
            $this.Enabled = $true
            $this.Text = "执行禁用"
            [System.Windows.Forms.MessageBox]::Show("服务优化出错: $($_.Exception.Message)", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })
    $page.Controls.Add($script:btnDisable)
}

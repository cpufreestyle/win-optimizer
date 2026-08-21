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

        # 备份
        if (-not (Test-Path $script:BackupDir)) { New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null }
        $backupFile = Join-Path $script:BackupDir "services_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $backupData = @()
        for ($i = 0; $i -lt $script:SvcDataTable.Rows.Count; $i++) {
            $svcName = $script:SvcDataTable.Rows[$i]["服务名称"]
            $service = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($service) {
                $svcWmi = @(Get-CimData Win32_Service -Filter "Name='$svcName'")[0]
                $startMode = if ($svcWmi) { $svcWmi.StartMode } else { "Unknown" }
                $backupData += [PSCustomObject]@{ Name=$svcName; Status=$service.Status; StartType=$startMode; Date=(Get-Date -Format "yyyy-MM-dd HH:mm:ss") }
            }
            Invoke-UIRefresh
        }
        $backupData | Export-Csv -Path $backupFile -NoTypeInformation -Encoding UTF8
        Write-Log "服务备份已保存: $backupFile"

        $disabledCount = 0
        for ($i = 0; $i -lt $script:SvcDataTable.Rows.Count; $i++) {
            if ($script:SvcDataTable.Rows[$i]["选择"] -eq $true) {
                $svcName = $script:SvcDataTable.Rows[$i]["服务名称"]
                $service = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                if ($service) {
                    try {
                        if ($service.Status -eq "Running") {
                            Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
                            Start-Sleep -Milliseconds 300
                        }
                        Set-Service -Name $svcName -StartupType Disabled -ErrorAction Stop
                        Write-Log "[禁用] $svcName" "SUCCESS"
                        $disabledCount++
                        $script:SvcDataTable.Rows[$i]["状态"] = "Stopped"
                    } catch {
                        Write-Log "[失败] $svcName — $($_.Exception.Message)" "ERROR"
                    }
                }
            }
            Invoke-UIRefresh
        }

        # 遥测任务
        if ($script:chkTelemetry.Checked) {
            $telemetryTasks = @(
                @{Path="\Microsoft\Windows\Application Experience\"; Name="Microsoft Compatibility Appraiser"},
                @{Path="\Microsoft\Windows\Application Experience\"; Name="ProgramDataUpdater"},
                @{Path="\Microsoft\Windows\Customer Experience Improvement Program\"; Name="Consolidator"},
                @{Path="\Microsoft\Windows\Customer Experience Improvement Program\"; Name="UsbCeip"}
            )
            foreach ($task in $telemetryTasks) {
                try {
                    $result = Disable-ScheduledTaskCompat -TaskPath $task.Path -TaskName $task.Name
                    if ($result) { Write-Log "[禁用] 计划任务: $($task.Name)" "SUCCESS" }
                } catch {}
            }
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

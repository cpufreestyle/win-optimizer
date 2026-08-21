function Build-BackupPage {
    $page = $script:Pages["Backup"]
    $page.Controls.Clear()

    $lblTitle = New-Label "备份恢复" 20 22 500 30 $Fonts.Header $Theme.TextBright
    $page.Controls.Add($lblTitle)

    $lblDesc = New-Label "管理优化操作的备份，可随时恢复" 20 56 760 24 $Fonts.Small $Theme.TextDim
    $page.Controls.Add($lblDesc)

    $y = 100

    $btnBackup = New-Button "创建备份" 20 $y 160 44 $Theme.Success 11
    $btnBackup.Add_Click({
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $script:BackupDir = Join-Path $script:ProjectRoot "backups"

        if (-not (Test-Path $script:BackupDir)) {
            New-Item -Path $script:BackupDir -ItemType Directory -Force | Out-Null
        }

        Write-Log "正在创建系统备份..."
        try {
            $startupFile = Join-Path $script:BackupDir "startup_$timestamp.csv"
            Get-CimData Win32_StartupCommand | Export-Csv $startupFile -NoTypeInformation -ErrorAction SilentlyContinue

            $svcFile = Join-Path $script:BackupDir "services_$timestamp.csv"
            Get-CimData Win32_Service | Select-Object Name, DisplayName, StartMode, State | Export-Csv $svcFile -NoTypeInformation

            $powerFile = Join-Path $script:BackupDir "power_$timestamp.txt"
            powercfg /list | Out-File $powerFile -Encoding UTF8

            $visFile = Join-Path $script:BackupDir "visual_$timestamp.txt"
            Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" | Out-File $visFile -Encoding UTF8

            Write-Log "备份已创建" "SUCCESS"
            [System.Windows.Forms.MessageBox]::Show("备份已创建成功！", "完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            Build-BackupPage
        } catch {
            Write-Log "备份创建失败: $_" "ERROR"
            [System.Windows.Forms.MessageBox]::Show("备份创建失败: $_", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })
    $page.Controls.Add($btnBackup)

    $btnRestore = New-Button "恢复最近备份" 200 $y 160 44 $Theme.Warning 11
    $btnRestore.Add_Click({
        $result = [System.Windows.Forms.MessageBox]::Show(
            "确定要从最近备份恢复吗？`n`n这将恢复服务、启动项和电源设置。",
            "确认恢复",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($result -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        $script:BackupDir = Join-Path $script:ProjectRoot "backups"
        if (-not (Test-Path $script:BackupDir)) {
            [System.Windows.Forms.MessageBox]::Show("未找到备份目录", "提示", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            return
        }

        Write-Log "开始从备份恢复..."
        $restored = 0

        $svcBackups = Get-ChildItem $script:BackupDir -Filter "services_*.csv" -ErrorAction SilentlyContinue | Sort-Object Name -Descending
        if ($svcBackups) {
            try {
                $svcs = Import-Csv $svcBackups[0].FullName
                foreach ($svc in $svcs) {
                    try {
                        if ($svc.StartMode -eq "Auto") {
                            Set-Service -Name $svc.Name -StartupType Automatic -ErrorAction SilentlyContinue
                        } elseif ($svc.StartMode -eq "Manual") {
                            Set-Service -Name $svc.Name -StartupType Manual -ErrorAction SilentlyContinue
                        } elseif ($svc.StartMode -eq "Disabled") {
                            Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction SilentlyContinue
                        }
                    } catch {}
                }
                Write-Log "服务状态已恢复" "SUCCESS"
                $restored++
            } catch { Write-Log "服务恢复失败" "WARN" }
        }

        $startupBackups = Get-ChildItem $script:BackupDir -Filter "startup_*.csv" -ErrorAction SilentlyContinue | Sort-Object Name -Descending
        if ($startupBackups) {
            try {
                $items = Import-Csv $startupBackups[0].FullName
                foreach ($item in $items) {
                    try {
                        $regPath = Split-Path $item.Location -Parent
                        $regName = Split-Path $item.Location -Leaf
                        if (Test-Path $regPath) {
                            New-ItemProperty -Path $regPath -Name $regName -Value $item.Command -Force -ErrorAction SilentlyContinue | Out-Null
                        }
                    } catch {}
                }
                Write-Log "启动项已恢复" "SUCCESS"
                $restored++
            } catch { Write-Log "启动项恢复失败" "WARN" }
        }

        if ($restored -gt 0) {
            Write-Log "恢复完成！恢复了 $restored 项" "SUCCESS"
        } else {
            Write-Log "未找到可恢复的备份" "WARN"
        }

        [System.Windows.Forms.MessageBox]::Show("恢复完成！请重启电脑使所有更改生效。", "完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    })
    $page.Controls.Add($btnRestore)

    $y += 56

    $lblBackupList = New-Label "备份列表:" 20 $y 760 24 $Fonts.Body $Theme.TextBright
    $page.Controls.Add($lblBackupList)

    $y += 26

    $dgvBackups = New-Object System.Windows.Forms.DataGridView
    $dgvBackups.Location = New-Object System.Drawing.Point(20, $y)
    $dgvBackups.Size = New-Object System.Drawing.Size(760, 250)
    $dgvBackups.BackgroundColor = $Theme.BgPanel
    $dgvBackups.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dgvBackups.AllowUserToAddRows = $false
    $dgvBackups.AllowUserToDeleteRows = $false
    $dgvBackups.AllowUserToResizeRows = $false
    $dgvBackups.ReadOnly = $true
    $dgvBackups.RowHeadersVisible = $false
    $dgvBackups.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $dgvBackups.DefaultCellStyle.BackColor = $Theme.BgPanel
    $dgvBackups.DefaultCellStyle.ForeColor = $Theme.TextMain
    $dgvBackups.DefaultCellStyle.SelectionBackColor = $Theme.AccentDark
    $dgvBackups.DefaultCellStyle.SelectionForeColor = $Theme.TextBright
    $dgvBackups.ColumnHeadersDefaultCellStyle.BackColor = $Theme.BgCard
    $dgvBackups.ColumnHeadersDefaultCellStyle.ForeColor = $Theme.TextBright
    $dgvBackups.EnableHeadersVisualStyles = $false

    $dgvBackups.Columns.Add("Name", "备份文件") | Out-Null
    $dgvBackups.Columns.Add("Date", "日期") | Out-Null
    $dgvBackups.Columns.Add("Type", "类型") | Out-Null
    $dgvBackups.Columns.Add("Size", "大小") | Out-Null

    $script:BackupDir = Join-Path $script:ProjectRoot "backups"
    if (Test-Path $script:BackupDir) {
        $backupFiles = Get-ChildItem $script:BackupDir -File | Sort-Object LastWriteTime -Descending | Select-Object -First 50
        foreach ($b in $backupFiles) {
            $type = if ($b.Name -like "services_*") { "服务备份" }
                    elseif ($b.Name -like "startup_*") { "启动项备份" }
                    elseif ($b.Name -like "power_*") { "电源计划备份" }
                    elseif ($b.Name -like "visual_*") { "视觉效果备份" }
                    else { "其他" }
            $size = if ($b.Length -gt 1KB) { "$([math]::Round($b.Length/1KB, 1)) KB" } else { "$($b.Length) B" }
            $dgvBackups.Rows.Add($b.Name, $b.LastWriteTime.ToString("yyyy-MM-dd HH:mm"), $type, $size) | Out-Null
        }
    }

    $page.Controls.Add($dgvBackups)

    $y += 260

    $btnRestoreSel = New-Button "恢复选中备份" 20 $y 160 44 $Theme.Warning 11
    $btnRestoreSel.Add_Click({
        if ($dgvBackups.SelectedRows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("请先选择一行备份", "提示", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            return
        }
        $selectedFile = $dgvBackups.SelectedRows[0].Cells["Name"].Value
        $selectedPath = Join-Path $script:BackupDir $selectedFile

        if (-not (Test-Path $selectedPath)) {
            [System.Windows.Forms.MessageBox]::Show("备份文件不存在", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }

        $result = [System.Windows.Forms.MessageBox]::Show(
            "确定要恢复备份: $selectedFile 吗？",
            "确认恢复",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($result -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        Write-Log "正在恢复: $selectedFile"

        if ($selectedFile -like "services_*.csv") {
            try {
                $svcs = Import-Csv $selectedPath
                foreach ($svc in $svcs) {
                    try {
                        if ($svc.StartMode -eq "Auto") {
                            Set-Service -Name $svc.Name -StartupType Automatic -ErrorAction SilentlyContinue
                        } elseif ($svc.StartMode -eq "Manual") {
                            Set-Service -Name $svc.Name -StartupType Manual -ErrorAction SilentlyContinue
                        } elseif ($svc.StartMode -eq "Disabled") {
                            Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction SilentlyContinue
                        }
                    } catch {}
                }
                Write-Log "服务已从备份恢复" "SUCCESS"
            } catch { Write-Log "服务恢复失败" "ERROR" }
        }
        elseif ($selectedFile -like "startup_*.csv") {
            try {
                $items = Import-Csv $selectedPath
                foreach ($item in $items) {
                    try {
                        $regPath = Split-Path $item.Location -Parent
                        $regName = Split-Path $item.Location -Leaf
                        if (Test-Path $regPath) {
                            New-ItemProperty -Path $regPath -Name $regName -Value $item.Command -Force -ErrorAction SilentlyContinue | Out-Null
                        }
                    } catch {}
                }
                Write-Log "启动项已从备份恢复" "SUCCESS"
            } catch { Write-Log "启动项恢复失败" "ERROR" }
        }

        [System.Windows.Forms.MessageBox]::Show("恢复完成！请重启电脑使所有更改生效。", "完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    })
    $page.Controls.Add($btnRestoreSel)

    $btnRefreshBackup = New-Button "刷新列表" 200 $y 120 44 $Theme.AccentDark 10
    $btnRefreshBackup.Add_Click({ Build-BackupPage })
    $page.Controls.Add($btnRefreshBackup)
}

function Build-StartupPage {
    $page = $script:Pages["Startup"]
    $page.Controls.Clear()

    $lblTitle = New-Label "启动项管理" 20 22 500 30 $Fonts.Header $Theme.TextBright
    $page.Controls.Add($lblTitle)

    $lblDesc = New-Label "管理开机启动项，禁用不必要的程序以加快开机速度" 20 56 760 24 $Fonts.Small $Theme.TextDim
    $page.Controls.Add($lblDesc)

    # 扫描启动项 - 用 script 作用域保存
    $script:StartupItems = @()
    $regPaths = @(
        @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"; Scope="当前用户"}
        @{Path="HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"; Scope="所有用户"}
        @{Path="HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; Scope="所有用户(32位)"}
    )
    foreach ($reg in $regPaths) {
        if (Test-Path $reg.Path) {
            $props = Get-ItemProperty -Path $reg.Path -ErrorAction SilentlyContinue
            if ($props) {
                $props.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" -and $_.Value } | ForEach-Object {
                    $script:StartupItems += [PSCustomObject]@{ Name=$_.Name; Command=$_.Value; Scope=$reg.Scope; Source="注册表"; RegPath=$reg.Path }
                }
            }
        }
    }

    # 启动文件夹
    $startupFolders = @(
        @{Path="$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Scope="当前用户"}
        @{Path="$env:PROGRAMDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Scope="所有用户"}
    )
    foreach ($folder in $startupFolders) {
        if (Test-Path $folder.Path) {
            Get-ChildItem -Path $folder.Path -ErrorAction SilentlyContinue | ForEach-Object {
                $script:StartupItems += [PSCustomObject]@{ Name=$_.Name; Command=$_.FullName; Scope=$folder.Scope; Source="启动文件夹"; RegPath=$folder.Path }
            }
        }
    }

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
        $cmd = if ($item.Command.Length -gt 60) { $item.Command.Substring(0, 57) + "..." } else { $item.Command }
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

        if (-not (Test-Path $script:BackupDir)) { New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null }
        $backupFile = Join-Path $script:BackupDir "startup_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $toRemove = @()
        foreach ($row in $script:DgvStartup.SelectedRows) {
            $idx = $row.Index
            $toRemove += $script:StartupItems[$idx]
        }
        $toRemove | Select-Object Name, Command, Scope, Source | Export-Csv -Path $backupFile -NoTypeInformation -Encoding UTF8
        Write-Log "启动项备份: $backupFile"

        $count = 0
        foreach ($item in $toRemove) {
            try {
                if ($item.Source -eq "注册表") {
                    Remove-ItemProperty -Path $item.RegPath -Name $item.Name -ErrorAction Stop
                    Write-Log "[禁用] $($item.Name) (注册表)" "SUCCESS"
                    $count++
                } elseif ($item.Source -eq "启动文件夹") {
                    $backupDir2 = Join-Path $script:BackupDir "startup_items"
                    if (-not (Test-Path $backupDir2)) { New-Item -ItemType Directory -Path $backupDir2 -Force | Out-Null }
                    Move-Item -Path $item.Command -Destination (Join-Path $backupDir2 (Split-Path $item.Command -Leaf)) -Force -ErrorAction Stop
                    Write-Log "[禁用] $($item.Name) (启动文件夹)" "SUCCESS"
                    $count++
                }
            } catch {
                Write-Log "[失败] $($item.Name)" "ERROR"
            }
            Invoke-UIRefresh
        }

        Write-Log "启动项优化完成！已禁用 $count 项" "SUCCESS"
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

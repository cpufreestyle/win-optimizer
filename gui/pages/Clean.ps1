function Build-CleanPage {
    $page = $script:Pages["Clean"]
    $page.Controls.Clear()

    $lblTitle = New-Label "垃圾文件清理" 20 56 500 30 $Fonts.Header $Theme.TextBright
    $page.Controls.Add($lblTitle)

    $lblDesc = New-Label "清理系统临时文件、更新缓存、缩略图缓存、回收站等，释放磁盘空间" 20 90 760 24 $Fonts.Small $Theme.TextDim
    $lblDesc.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $page.Controls.Add($lblDesc)

    # 扫描结果
    $lblScan = New-Label "可清理项目:" 20 126 760 24 $Fonts.Sub $Theme.Accent
    $lblScan.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $page.Controls.Add($lblScan)

    # 用 script 作用域保存变量供事件处理器使用
    $script:CleanItems = @(
        @{Path="C:\Windows\Temp";                    Name="Windows 系统临时文件"}
        @{Path=$env:TEMP;                             Name="用户临时文件"}
        @{Path="C:\Windows\Prefetch";                Name="预读取文件"}
        @{Path="C:\Windows\SoftwareDistribution\Download"; Name="Windows Update 下载缓存"}
        @{Path="$env:LOCALAPPDATA\Microsoft\Windows\Explorer"; Name="缩略图缓存"}
        @{Path="$env:PROGRAMDATA\Microsoft\Windows\WER"; Name="Windows 错误报告"}
    )

    $script:CleanListBox = New-Object System.Windows.Forms.CheckedListBox
    $script:CleanListBox.Location = New-Object System.Drawing.Point(20, 156)
    $script:CleanListBox.Size = New-Object System.Drawing.Size(760, 200)
    # 跟随页面宽高变化自适应
    $script:CleanListBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
    $script:CleanListBox.BackColor = $Theme.BgInput
    $script:CleanListBox.ForeColor = $Theme.TextMain
    $script:CleanListBox.Font = $Fonts.Body
    $script:CleanListBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $script:CleanListBox.CheckOnClick = $true
    $script:CleanListBox.IntegralHeight = $false
    foreach ($item in $script:CleanItems) {
        $size = Get-FolderSize $item.Path
        $sizeMB = [math]::Round($size / 1MB, 2)
        $display = "$($item.Name) — ${sizeMB} MB"
        $script:CleanListBox.Items.Add($display, $true) | Out-Null
    }
    $page.Controls.Add($script:CleanListBox)

    # 额外选项
    $script:ChkRecycle = New-Object System.Windows.Forms.CheckBox
    $script:ChkRecycle.Location = New-Object System.Drawing.Point(20, 348)
    $script:ChkRecycle.Size = New-Object System.Drawing.Size(200, 24)
    $script:ChkRecycle.Text = "清空回收站"
    $script:ChkRecycle.Checked = $true
    $script:ChkRecycle.Font = $Fonts.Body
    $script:ChkRecycle.ForeColor = $Theme.TextMain
    $script:ChkRecycle.BackColor = $Theme.BgDark
    $page.Controls.Add($script:ChkRecycle)

    $script:ChkDNS = New-Object System.Windows.Forms.CheckBox
    $script:ChkDNS.Location = New-Object System.Drawing.Point(230, 348)
    $script:ChkDNS.Size = New-Object System.Drawing.Size(200, 24)
    $script:ChkDNS.Text = "清除 DNS 缓存"
    $script:ChkDNS.Checked = $true
    $script:ChkDNS.Font = $Fonts.Body
    $script:ChkDNS.ForeColor = $Theme.TextMain
    $script:ChkDNS.BackColor = $Theme.BgDark
    $page.Controls.Add($script:ChkDNS)

    $script:ChkDump = New-Object System.Windows.Forms.CheckBox
    $script:ChkDump.Location = New-Object System.Drawing.Point(440, 348)
    $script:ChkDump.Size = New-Object System.Drawing.Size(200, 24)
    $script:ChkDump.Text = "删除内存转储文件"
    $script:ChkDump.Checked = $true
    $script:ChkDump.Font = $Fonts.Body
    $script:ChkDump.ForeColor = $Theme.TextMain
    $script:ChkDump.BackColor = $Theme.BgDark
    $page.Controls.Add($script:ChkDump)

    # 执行按钮
    $script:BtnClean = New-Button "开始清理" 20 386 200 44 $Theme.Success 11
    $script:BtnClean.Add_Click({
        try {
        $this.Enabled = $false
        $this.Text = "正在清理..."
        Invoke-UIRefresh

        $totalFreed = 0
        $filesDeleted = 0

        for ($i = 0; $i -lt $script:CleanItems.Count; $i++) {
            if ($script:CleanListBox.GetItemChecked($i)) {
                $item = $script:CleanItems[$i]
                $before = Get-FolderSize $item.Path
                if (Test-Path $item.Path) {
                    Get-ChildItem -Path $item.Path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                        try { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue; $filesDeleted++ } catch {}
                    }
                    $after = Get-FolderSize $item.Path
                    $freed = $before - $after
                    $totalFreed += $freed
                    Write-Log "[清理] $($item.Name): 释放 $([math]::Round($freed/1MB,2)) MB" "SUCCESS"
                }
            }
            Invoke-UIRefresh
        }

        if ($script:ChkRecycle.Checked) {
            Clear-RecycleBinCompat
            Write-Log "[清理] 回收站已清空" "SUCCESS"
        }
        if ($script:ChkDNS.Checked) {
            try { ipconfig /flushdns | Out-Null; Write-Log "[清理] DNS 缓存已清除" "SUCCESS" } catch {}
        }
        if ($script:ChkDump.Checked) {
            $dumpFiles = @("C:\Windows\MEMORY.DMP")
            $dumpFiles += (Get-ChildItem "C:\Windows\Minidump" -ErrorAction SilentlyContinue).FullName
            foreach ($dump in $dumpFiles) {
                if ($dump -and (Test-Path $dump)) {
                    $totalFreed += (Get-Item $dump).Length
                    Remove-Item $dump -Force -ErrorAction SilentlyContinue
                    Write-Log "[清理] 删除转储文件: $(Split-Path $dump -Leaf)" "SUCCESS"
                }
            }
        }

        $totalMB = [math]::Round($totalFreed / 1MB, 2)
        $totalGB = [math]::Round($totalFreed / 1GB, 2)
        $msg = if ($totalGB -ge 1) { "共释放 ${totalGB} GB 空间" } else { "共释放 ${totalMB} MB 空间" }
        Write-Log "清理完成！$msg，删除 $filesDeleted 个文件" "SUCCESS"

        $this.Enabled = $true
        $this.Text = "开始清理"

        [System.Windows.Forms.MessageBox]::Show("清理完成！`n$msg`n删除 $filesDeleted 个文件", "完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            Write-Log "清理出错: $($_.Exception.Message)" "ERROR"
            $this.Enabled = $true
            $this.Text = "开始清理"
            [System.Windows.Forms.MessageBox]::Show("清理出错: $($_.Exception.Message)", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })
    $page.Controls.Add($script:BtnClean)
}

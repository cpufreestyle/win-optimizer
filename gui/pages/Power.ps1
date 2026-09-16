function Build-PowerPage {
    $page = $script:Pages["Power"]
    $page.Controls.Clear()

    $lblTitle = New-Label "电源计划优化" 20 22 500 30 $Fonts.Header $Theme.TextBright
    $page.Controls.Add($lblTitle)

    $lblDesc = New-Label "切换高性能电源计划，最大化 CPU 性能响应速度" 20 56 760 24 $Fonts.Small $Theme.TextDim
    $page.Controls.Add($lblDesc)

    # 当前计划
    $currentPlan = @(powercfg /getactivescheme 2>&1) -join ' '
    $script:lblCurrent = New-Label "当前计划: $currentPlan" 20 96 760 24 $Fonts.Sub $Theme.Warning
    $page.Controls.Add($script:lblCurrent)

    $script:plans = @(
        @{Title="高性能模式"; Desc="最大化 CPU 性能，CPU 始终保持最高频率`n适合台式机或插电笔记本"; GUID="8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"; Color=$Theme.Success}
        @{Title="卓越性能模式"; Desc="比高性能更高，需解锁后可用`n极限性能优先"; GUID="e9a42b02-d5df-448d-aa00-03f14749eb61"; Color=$Theme.Accent}
        @{Title="平衡优化模式"; Desc="平衡基础上优化，禁用USB挂起`n适合笔记本电池模式"; GUID="381b4222-f694-41f0-9685-ff5bb260df2e"; Color=$Theme.Warning}
    )

    $yPlan = 130
    $script:radioPowers = @()
    for ($i = 0; $i -lt 3; $i++) {
        $p = $script:plans[$i]
        $card = New-Object System.Windows.Forms.Panel
        $card.Location = New-Object System.Drawing.Point(20, $yPlan)
        $card.Size = New-Object System.Drawing.Size(760, 88)
        $card.BackColor = $Theme.BgCard
        $page.Controls.Add($card)

        $rb = New-Object System.Windows.Forms.RadioButton
        $rb.Location = New-Object System.Drawing.Point(12, 30)
        $rb.Size = New-Object System.Drawing.Size(24, 24)
        $rb.Checked = ($i -eq 0)
        $rb.BackColor = $Theme.BgCard
        $rb.ForeColor = $p.Color
        $card.Controls.Add($rb)
        $script:radioPowers += $rb

        $lblP = New-Label $p.Title 44 14 250 26 $Fonts.Header $p.Color
        $card.Controls.Add($lblP)

        $lblPDesc = New-Label $p.Desc 44 42 700 40 $Fonts.Small $Theme.TextDim
        $card.Controls.Add($lblPDesc)

        $yPlan += 96
    }

    # 选项
    $script:chkUSB = New-Object System.Windows.Forms.CheckBox
    $script:chkUSB.Location = New-Object System.Drawing.Point(20, $yPlan)
    $script:chkUSB.Size = New-Object System.Drawing.Size(300, 24)
    $script:chkUSB.Text = "禁用 USB 选择性挂起"
    $script:chkUSB.Checked = $true
    $script:chkUSB.Font = $Fonts.Body
    $script:chkUSB.ForeColor = $Theme.TextMain
    $script:chkUSB.BackColor = $Theme.BgDark
    $page.Controls.Add($script:chkUSB)

    $script:chkPCI = New-Object System.Windows.Forms.CheckBox
    $script:chkPCI.Location = New-Object System.Drawing.Point(330, $yPlan)
    $script:chkPCI.Size = New-Object System.Drawing.Size(300, 24)
    $script:chkPCI.Text = "关闭 PCI Express 电源管理"
    $script:chkPCI.Checked = $true
    $script:chkPCI.Font = $Fonts.Body
    $script:chkPCI.ForeColor = $Theme.TextMain
    $script:chkPCI.BackColor = $Theme.BgDark
    $page.Controls.Add($script:chkPCI)

    $yPlan += 32

    $script:btnApplyPower = New-Button "应用电源计划" 20 ([int]($yPlan + 10)) 200 44 $Theme.Success 11
    $script:btnApplyPower.Add_Click({
        try {
        $selectedGUID = $script:plans[0].GUID
        for ($i = 0; $i -lt 3; $i++) { if ($script:radioPowers[$i].Checked) { $selectedGUID = $script:plans[$i].GUID } }

        $this.Enabled = $false
        $this.Text = "应用中..."
        Invoke-UIRefresh

        # 统一走共享库：先备份；卓越性能自动解锁并支持失败回退；
        # 三种模式都设置 CPU 上下限与 DISKIDLE（此前仅高性能设置 CPU，且完全没有备份与回退）
        $cat = Get-PowerPlanCatalog | Where-Object { $_.GUID -eq $selectedGUID }
        $params = @{
            Guid               = $selectedGUID
            UsbSuspendOff      = [bool]$script:chkUSB.Checked
            PciAspmOff         = [bool]$script:chkPCI.Checked
            BackupDir          = $script:BackupDir
            UnlockUltimate     = ($selectedGUID -eq "e9a42b02-d5df-448d-aa00-03f14749eb61")
            FallbackToHighPerf = ($selectedGUID -eq "e9a42b02-d5df-448d-aa00-03f14749eb61")
        }
        switch ($cat.Value) {
            1 { $params.MinPercent = 100; $params.MaxPercent = 100; $params.DiskIdleSeconds = 0 }
            2 { $params.MinPercent = 100; $params.MaxPercent = 100; $params.DiskIdleSeconds = 0 }
            3 { $params.MinPercent = 5;   $params.MaxPercent = 100; $params.DiskIdleSeconds = 1800 }
        }
        $r = Set-PowerPlan @params
        Write-Log "电源计划备份: $($r.backup)"
        foreach ($d in $r.details) { Write-Log $d "SUCCESS" }
        Write-Log "已切换电源计划: $($r.appliedGuid)" "SUCCESS"

        $this.Enabled = $true
        $this.Text = "应用电源计划"

        $newPlan = @(powercfg /getactivescheme 2>&1) -join ' '
        $script:lblCurrent.Text = "当前计划: $newPlan"

        [System.Windows.Forms.MessageBox]::Show("电源计划已切换！", "完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            Write-Log "电源计划出错: $($_.Exception.Message)" "ERROR"
            [System.Windows.Forms.MessageBox]::Show("电源计划出错: $($_.Exception.Message)", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })
    $page.Controls.Add($script:btnApplyPower)
}

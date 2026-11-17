function Build-NetworkPageContent {
    $page = $script:Pages["Network"]
    $page.Controls.Clear()

    $lblTitle = New-Label "网络优化" 20 22 500 30 $Fonts.Header $Theme.TextBright
    $page.Controls.Add($lblTitle)

    $lblDesc = New-Label "优化 DNS 和网络参数以提升网络响应速度" 20 56 760 24 $Fonts.Small $Theme.TextDim
    $page.Controls.Add($lblDesc)

    # DNS 选项
    $y = 100
    $lblDNS = New-Label "DNS 设置:" 20 $y 100 24 $Fonts.Body $Theme.TextBright
    $page.Controls.Add($lblDNS)

    $script:cbDNS = New-Object System.Windows.Forms.ComboBox
    $script:cbDNS.Location = New-Object System.Drawing.Point(130, [int]($y - 2))
    $script:cbDNS.Size = New-Object System.Drawing.Size(300, 28)
    $script:cbDNS.Font = $Fonts.Body
    $script:cbDNS.BackColor = $Theme.BgInput
    $script:cbDNS.ForeColor = $Theme.TextMain
    $script:cbDNS.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $script:cbDNS.Items.Add("保持当前 DNS") | Out-Null
    # DNS 选项统一由共享库提供（编号与 CLI / WebUI 完全一致，config 只覆盖地址）
    foreach ($o in (Get-DnsOptions)) {
        $script:cbDNS.Items.Add("$($o.Label) ($($o.Primary) / $($o.Secondary))") | Out-Null
    }
    $script:cbDNS.SelectedIndex = 0
    $page.Controls.Add($script:cbDNS)

    $y += 40

    $script:chkTCP = New-Object System.Windows.Forms.CheckBox
    $script:chkTCP.Location = New-Object System.Drawing.Point(20, $y)
    $script:chkTCP.Size = New-Object System.Drawing.Size(300, 24)
    $script:chkTCP.Text = "TCP 自动调优 (Auto Tuning)"
    $script:chkTCP.Checked = $true
    $script:chkTCP.Font = $Fonts.Body
    $script:chkTCP.ForeColor = $Theme.TextMain
    $script:chkTCP.BackColor = $Theme.BgDark
    $page.Controls.Add($script:chkTCP)

    $y += 30

    $script:chkRSS = New-Object System.Windows.Forms.CheckBox
    $script:chkRSS.Location = New-Object System.Drawing.Point(20, $y)
    $script:chkRSS.Size = New-Object System.Drawing.Size(300, 24)
    $script:chkRSS.Text = "RSS 接收端缩放"
    $script:chkRSS.Checked = $true
    $script:chkRSS.Font = $Fonts.Body
    $script:chkRSS.ForeColor = $Theme.TextMain
    $script:chkRSS.BackColor = $Theme.BgDark
    $page.Controls.Add($script:chkRSS)

    $y += 30

    $script:chkRSC = New-Object System.Windows.Forms.CheckBox
    $script:chkRSC.Location = New-Object System.Drawing.Point(20, $y)
    $script:chkRSC.Size = New-Object System.Drawing.Size(300, 24)
    $script:chkRSC.Text = "RSC 接收段合并"
    $script:chkRSC.Checked = $true
    $script:chkRSC.Font = $Fonts.Body
    $script:chkRSC.ForeColor = $Theme.TextMain
    $script:chkRSC.BackColor = $Theme.BgDark
    $page.Controls.Add($script:chkRSC)

    $y += 30

    $script:chkDNSCache = New-Object System.Windows.Forms.CheckBox
    $script:chkDNSCache.Location = New-Object System.Drawing.Point(20, $y)
    $script:chkDNSCache.Size = New-Object System.Drawing.Size(300, 24)
    $script:chkDNSCache.Text = "刷新 DNS 缓存"
    $script:chkDNSCache.Checked = $true
    $script:chkDNSCache.Font = $Fonts.Body
    $script:chkDNSCache.ForeColor = $Theme.TextMain
    $script:chkDNSCache.BackColor = $Theme.BgDark
    $page.Controls.Add($script:chkDNSCache)

    $y += 40

    $lblCurDNS = New-Label "当前 DNS:" 20 $y 760 24 $Fonts.Small $Theme.TextDim
    try {
        $dnsText = @()
        # 只查一次 CIM，所有适配器的 DNS 一起取（Win32_NetworkAdapterConfiguration 单次约 50ms）
        $cfgs = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' -ErrorAction SilentlyContinue)
        foreach ($a in (Get-ActiveNetAdapters)) {
            $dns = @()
            foreach ($c in $cfgs) {
                if ([int]$c.InterfaceIndex -eq [int]$a.IfIndex -or ($a.Name -and $c.Description -eq $a.Name)) {
                    $dns = @($c.DNSServerSearchOrder)
                    break
                }
            }
            $dnsText += "$($a.Name): $($dns -join ', ')"
        }
        $lblCurDNS.Text = "当前 DNS: $($dnsText -join ' | ')"
    } catch {}
    $page.Controls.Add($lblCurDNS)

    $y += 40

    $script:btnNetOpt = New-Button "开始优化" 20 $y 200 44 $Theme.Success 11
    $script:btnNetOpt.Add_Click({
        try {
        $this.Enabled = $false
        $this.Text = "优化中..."
        Invoke-UIRefresh

        $dnsChoice = $script:cbDNS.SelectedIndex

        # 统一走共享库：先备份再应用。
        # 此前 GUI 改 DNS 完全没有备份（改坏无法恢复），且 RSS/RSC 只用全局 netsh、
        # 不区分适配器——一并修复。虚拟/隧道类网卡由共享库自动排除，避免误改 VPN。
        $r = Invoke-NetworkOptimization -BackupDir $script:BackupDir -DnsOption $dnsChoice `
                -Tcp $script:chkTCP.Checked -Rss $script:chkRSS.Checked `
                -Rsc $script:chkRSC.Checked -DnsCache $script:chkDNSCache.Checked
        foreach ($d in $r.details) { Write-Log "[网络] $d" }
        if ($r.backup) { Write-Log "网络备份: $($r.backup)" }
        if (-not $r.ok) { Write-Log "[网络] 部分设置失败（可能需要管理员权限）" "WARN" }
        Write-Log "网络优化完成！" "SUCCESS"
        $this.Enabled = $true
        $this.Text = "开始优化"
        [System.Windows.Forms.MessageBox]::Show("网络优化完成！", "完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            Write-Log "网络优化出错: $($_.Exception.Message)" "ERROR"
            $this.Enabled = $true
            $this.Text = "开始优化"
            [System.Windows.Forms.MessageBox]::Show("网络优化出错: $($_.Exception.Message)", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })
    $page.Controls.Add($script:btnNetOpt)
}

# 启动时先画占位内容，窗口出现后再查网卡/DNS（Get-ActiveNetAdapters 首次约 400ms）
function Build-NetworkPage {
    $page = $script:Pages["Network"]
    if ($null -eq $page) { return }
    # 离屏渲染 / 布局审计需要完整内容，保持同步构建
    if ($script:HeadlessRender) {
        Build-NetworkPageContent
        return
    }
    $page.Controls.Clear()
    $page.Controls.Add((New-Label "网络优化" 20 22 500 30 $Fonts.Header $Theme.TextBright))
    $page.Controls.Add((New-Label "正在读取网卡信息…" 20 60 500 24 $Fonts.Small $Theme.TextDim))
    if ($null -ne $script:NetworkTimer) {
        try { $script:NetworkTimer.Stop(); $script:NetworkTimer.Dispose() } catch { }
        $script:NetworkTimer = $null
    }
    $script:NetworkTimer = New-Object System.Windows.Forms.Timer
    $script:NetworkTimer.Interval = 120
    $script:NetworkTimer.Add_Tick({
        param($Sender, $e)
        try { $Sender.Stop(); $Sender.Dispose() } catch { }
        $script:NetworkTimer = $null
        Build-NetworkPageContent
        if (Get-Command Reposition-PageControls -ErrorAction SilentlyContinue) {
            Reposition-PageControls $script:Pages["Network"]
        }
    })
    $script:NetworkTimer.Start()
}

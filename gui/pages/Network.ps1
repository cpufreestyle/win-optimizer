function Build-NetworkPage {
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
    $script:cbDNS.Items.Add("Cloudflare (1.1.1.1 / 1.0.0.1)") | Out-Null
    $script:cbDNS.Items.Add("Google (8.8.8.8 / 8.8.4.4)") | Out-Null
    $script:cbDNS.Items.Add("阿里 DNS (223.5.5.5 / 223.6.6.6)") | Out-Null
    $script:cbDNS.Items.Add("114 DNS (114.114.114.114 / 114.114.115.115)") | Out-Null
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
        $adapters = Get-DnsClientServerAddressCompat
        $dnsText = $adapters | ForEach-Object { "$($_.InterfaceAlias): $($_.ServerAddresses -join ', ')" }
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

        if ($dnsChoice -gt 0) {
            $dnsServers = switch ($dnsChoice) {
                1 { @("1.1.1.1", "1.0.0.1") }
                2 { @("8.8.8.8", "8.8.4.4") }
                3 { @("223.5.5.5", "223.6.6.6") }
                4 { @("114.114.114.114", "114.114.115.115") }
            }

            try {
                $adapters = Get-NetAdapterCompat
                foreach ($adapter in $adapters) {
                    if ($adapter.Name) {
                        Set-DnsCompat -InterfaceName $adapter.Name -DnsServers $dnsServers
                        Write-Log "[DNS] $($adapter.Name) 已设置为 $($dnsServers -join ', ')" "SUCCESS"
                    }
                }
            } catch {
                Write-Log "[DNS] 设置失败: $_" "ERROR"
            }
        }

        if ($script:chkTCP.Checked) {
            try {
                netsh int tcp set global autotuninglevel=normal 2>&1 | Out-Null
                Write-Log "[TCP] 自动调优已启用" "SUCCESS"
            } catch { Write-Log "[TCP] 设置失败" "WARN" }
        }

        if ($script:chkRSS.Checked) {
            Enable-NetAdapterRssCompat
            Write-Log "[RSS] 接收端缩放已启用" "SUCCESS"
        }

        if ($script:chkRSC.Checked) {
            Enable-NetAdapterRscCompat
            Write-Log "[RSC] 接收段合并已启用" "SUCCESS"
        }

        if ($script:chkDNSCache.Checked) {
            Clear-DnsClientCacheCompat
            Write-Log "[DNS] 缓存已刷新" "SUCCESS"
        }

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

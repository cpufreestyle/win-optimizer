function Build-AboutPage {
    $page = $script:Pages["About"]
    $page.Controls.Clear()

    $lblAboutTitle = New-Label "PC-Optimizer-7thGen" 20 30 760 36 $Fonts.Title $Theme.Accent
    $page.Controls.Add($lblAboutTitle)

    $lblVer = New-Label "版本 v$Version" 20 72 760 24 $Fonts.Sub $Theme.TextDim
    $page.Controls.Add($lblVer)

    $aboutText = @"
专为 7 代及更老 CPU 的 Windows 电脑设计
兼容 Windows 7 / 8 / 10 / 11 (PS 2.0+)

功能特性:
  - 垃圾文件清理（临时文件、缓存、回收站等）
  - 服务优化（禁用遥测、Xbox、传感器等非必要服务）
  - 启动项管理（扫描注册表和启动文件夹）
  - 视觉效果优化（最佳性能/平衡/自定义）
  - 电源计划优化（高性能/卓越性能/平衡）
  - 磁盘优化（SSD TRIM / HDD 碎片整理 / 系统压缩）
  - 网络优化（DNS 设置 / TCP 调优 / RSS RSC）
  - 备份恢复（服务/启动项/电源计划备份）

Win7 兼容性:
  - 自动检测操作系统版本
  - PS 2.0 下回退到 Get-WmiObject
  - Win7 下用 netsh 替代 NetAdapter cmdlet
  - Win7 下用 schtasks 替代 ScheduledTask cmdlet
  - Win7 下用 COM 对象清空回收站

安全特性:
  - 所有操作前自动创建备份
  - 不修改系统核心文件
  - 不安装第三方软件
  - 操作日志记录在 optimize.log

使用提示:
  - 优化前建议先创建备份
  - 优化后重启电脑使更改生效
  - 笔记本电池模式建议使用平衡电源计划
"@ 

    $txtAbout = New-Object System.Windows.Forms.TextBox
    $txtAbout.Location = New-Object System.Drawing.Point(20, 120)
    $txtAbout.Size = New-Object System.Drawing.Size(760, 420)
    $txtAbout.Text = $aboutText
    $txtAbout.Font = $Fonts.Body
    $txtAbout.ForeColor = $Theme.TextMain
    $txtAbout.BackColor = $Theme.BgCard
    $txtAbout.Multiline = $true
    $txtAbout.ReadOnly = $true
    $txtAbout.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $txtAbout.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $txtAbout.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
    $page.Controls.Add($txtAbout)

    # 检查更新按钮
    $btnCheckUpdate = New-Object System.Windows.Forms.Button
    $btnCheckUpdate.Text = "检查更新"
    $btnCheckUpdate.Location = New-Object System.Drawing.Point(20, 552)
    $btnCheckUpdate.Size = New-Object System.Drawing.Size(140, 36)
    $btnCheckUpdate.Font = $Fonts.Body
    $btnCheckUpdate.ForeColor = [System.Drawing.Color]::White
    $btnCheckUpdate.BackColor = $Theme.Accent
    $btnCheckUpdate.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCheckUpdate.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnCheckUpdate.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Bottom
    $btnCheckUpdate.Add_Click({
        $this.Enabled = $false
        $this.Text = "检查中..."
        [System.Windows.Forms.Application]::DoEvents()
        $release = Get-GitHubLatestRelease
        if ($null -eq $release) {
            [System.Windows.Forms.MessageBox]::Show("无法连接到更新服务器，请检查网络或稍后重试。详情见日志。", "检查失败", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        } else {
            Show-UpdatePrompt -Release $release
        }
        $this.Enabled = $true
        $this.Text = "检查更新"
    })
    $page.Controls.Add($btnCheckUpdate)
}

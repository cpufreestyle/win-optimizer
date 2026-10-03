function Invoke-GuidedScan {
    <#
    体检并生成推荐方案（只读：不改动任何系统设置）。
    #>
    if ($script:GuidedBusy) { return }
    $script:GuidedBusy = $true
    $btn = $script:GuidedBackBtn
    if ($btn) { $btn.Enabled = $false; $btn.Text = "体检中..." }
    Invoke-UIRefresh
    try {
        Write-Log "一键向导：正在体检..."
        $plan = Get-GuidedPlan
        if (-not $plan.ok) {
            Write-Log ("一键向导体检失败: " + $plan.error) "ERROR"
            [System.Windows.Forms.MessageBox]::Show("体检失败：" + $plan.error + "`n`n通常是因为没有管理员权限，请右键以管理员身份重新启动本工具。", "一键向导",
                [System.Windows.Forms.MessageBox]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        $script:GuidedPlan = $plan
        $script:GuidedBefore = $plan.report
        Write-Log ("一键向导：体检完成，" + $plan.score + " 分（" + $plan.grade + "），推荐「" + $plan.profile.title + "」") "SUCCESS"
        Build-GuidedPage -KeepPlan
    } catch {
        Write-Log ("一键向导体检异常: " + $_.Exception.Message) "ERROR"
        [System.Windows.Forms.MessageBox]::Show("体检出现异常：" + $_.Exception.Message, "一键向导",
            [System.Windows.Forms.MessageBox]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    } finally {
        $script:GuidedBusy = $false
    }
}

function Invoke-GuidedRun {
    <#
    按当前推荐方案执行优化，并复检出前后对比。执行前由 lib 逐域自动备份。
    与 CLI / WebUI 一致：不传 -Force，高风险或需人工确认的步骤由 lib 自动跳过。
    #>
    if ($script:GuidedBusy) { return }
    $plan = $script:GuidedPlan
    if (-not $plan -or -not $plan.ok) {
        [System.Windows.Forms.MessageBox]::Show("请先点击「开始体检并推荐」。", "一键向导",
            [System.Windows.Forms.MessageBox]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }

    $autoCount = @($plan.steps).Count
    $ans = [System.Windows.Forms.MessageBox]::Show(
        ("将按「" + $plan.profile.title + "」执行 " + $autoCount + " 个步骤。`n`n" +
         "每个域执行前会自动备份，之后可到「备份恢复」页撤销。`n" +
         "高风险或需人工确认的步骤会被自动跳过。`n`n确认开始？"),
        "一键向导",
        [System.Windows.Forms.MessageBox]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) {
        Write-Log "一键向导：已取消执行。" "WARN"
        return
    }

    $script:GuidedBusy = $true
    $btn = $script:GuidedBackBtn
    if ($btn) { $btn.Enabled = $false; $btn.Text = "执行中..." }
    Invoke-UIRefresh
    try {
        $bkDir = Join-Path $script:ProjectRoot "backups"
        if (-not (Test-Path $bkDir)) { New-Item -ItemType Directory -Path $bkDir -Force | Out-Null }
        $r = Invoke-Profile -Name $plan.profile.name -BackupDir $bkDir
        Show-ProfileReport -Result $r

        # 前后对比（体检 -> 优化 -> 复检）
        if ($script:GuidedBefore) {
            $after = Get-SystemHealthReport
            $script:GuidedAfter = $after
            $cmp = Compare-HealthReports -Before $script:GuidedBefore -After $after
            if ($cmp) {
                Write-Log ("一键向导：优化前后体检 " + $cmp.beforeScore + " → " + $cmp.afterScore + "（" + $cmp.scoreDelta + "）") "SUCCESS"
                if ($cmp.scoreDelta -gt 0) {
                    [System.Windows.Forms.MessageBox]::Show(
                        ("优化完成！`n`n体检得分：" + $cmp.beforeScore + " → " + $cmp.afterScore + "（+" + $cmp.scoreDelta + "）`n`n建议重启电脑使所有更改生效。"),
                        "一键向导", [System.Windows.Forms.MessageBox]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
                } else {
                    [System.Windows.Forms.MessageBox]::Show(
                        ("优化已完成，体检得分没有变化（" + $cmp.beforeScore + " → " + $cmp.afterScore + "）。`n`n建议重启电脑后再体检一次查看效果。"),
                        "一键向导", [System.Windows.Forms.MessageBox]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
                }
            }
            try { Save-HealthReport -Report $after -BackupDir (Join-Path $script:ProjectRoot "backups\health") } catch { }
        }
        Build-GuidedPage -KeepPlan
    } catch {
        Write-Log ("一键向导执行异常: " + $_.Exception.Message) "ERROR"
        [System.Windows.Forms.MessageBox]::Show("执行出现异常：" + $_.Exception.Message, "一键向导",
            [System.Windows.Forms.MessageBox]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    } finally {
        $script:GuidedBusy = $false
    }
}
function Show-GuidedPageFromDashboard {
    <#
    从仪表盘跳转到一键向导页（导航逻辑与侧边栏一致，确保只显示目标页）。
    #>
    foreach ($k in $script:NavButtons.Keys) {
        $script:NavButtons[$k].BackColor = $Theme.BgDark
        $script:NavButtons[$k].ForeColor = $Theme.TextDim
    }
    $script:NavButtons["Guided"].BackColor = $Theme.Accent
    $script:NavButtons["Guided"].ForeColor = $Theme.ButtonText
    foreach ($pn in $script:Pages.Keys) {
        $script:Pages[$pn].Visible = ($pn -eq "Guided")
    }
    $script:CurrentPage = "Guided"
    if ($script:HeaderTitles.ContainsKey("Guided")) {
        $script:HeaderLabel.Text = $script:HeaderTitles["Guided"]
    }
    $script:Pages["Guided"].AutoScrollPosition = New-Object System.Drawing.Point(0, 0)
    Build-GuidedPage -KeepPlan
    # 不在这里重新体检：GuidedAfter 只由 Invoke-GuidedRun 在真正执行后写入，
    # 否则每次切页都跑一次全身体检，既慢又会让「导出」拿到执行前的旧数据
}

function Invoke-GuidedExport {
    <#
    把本次向导的前后体检对比导出成可分享报告，复用 lib 的 Export-HealthReport，
    与 GUI 体检页「导出对比报告」同一个函数，不另写一套导出逻辑。
    #>
    if (-not $script:GuidedBefore -or -not $script:GuidedAfter) {
        [System.Windows.Forms.MessageBox]::Show("还没有可导出的对比：请先执行一次优化。", "一键向导",
            [System.Windows.Forms.MessageBox]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }
    try { Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue } catch { }
    $fmt = 'Html'
    if ('Microsoft.VisualBasic.Interaction' -as [type]) {
        $pick = [Microsoft.VisualBasic.Interaction]::InputBox(
            "导出哪种格式？`n`nY = HTML（可双击打开，图表更直观）`n其它 = Markdown（纯文本，便于贴到 Issue / 论坛）",
            "导出对比报告", "Y")
        if ($pick -eq 'N' -or $pick -eq 'n') { $fmt = 'Markdown' }
    }
    try {
        $exp = Export-HealthReport -From $script:GuidedBefore -To $script:GuidedAfter -Format $fmt
        if ($exp.ok) {
            Write-Log ("一键向导：对比报告已导出 " + $exp.file) "SUCCESS"
            $open = [System.Windows.Forms.MessageBox]::Show(
                ("报告已保存到：" + $exp.file + "`n`n是否现在打开？"),
                "导出完成", [System.Windows.Forms.MessageBox]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Information)
            if ($open -eq [System.Windows.Forms.DialogResult]::Yes) {
                try { Start-Process $exp.file } catch { }
            }
        } else {
            Write-Log ("一键向导：导出失败 " + $exp.error) "ERROR"
            [System.Windows.Forms.MessageBox]::Show("导出失败：" + $exp.error, "一键向导",
                [System.Windows.Forms.MessageBox]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
    } catch {
        Write-Log ("一键向导：导出异常 " + $_.Exception.Message) "ERROR"
        [System.Windows.Forms.MessageBox]::Show("导出出现异常：" + $_.Exception.Message, "一键向导",
            [System.Windows.Forms.MessageBox]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
}


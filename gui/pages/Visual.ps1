function Build-VisualPage {
    $page = $script:Pages["Visual"]
    $page.Controls.Clear()

    $lblTitle = New-Label "视觉效果优化" 20 22 500 30 $Fonts.Header $Theme.TextBright
    $page.Controls.Add($lblTitle)

    $lblDesc = New-Label "降低视觉特效以提升系统响应速度，老电脑推荐使用最佳性能模式" 20 56 760 24 $Fonts.Small $Theme.TextDim
    $page.Controls.Add($lblDesc)

    # 选项卡片
    $script:modes = @(
        @{Title="最佳性能"; Desc="关闭所有动画和特效，仅保留字体平滑`n适合老旧电脑，最大化响应速度"; Color=$Theme.Success; Value=1}
        @{Title="平衡模式"; Desc="关闭大部分动画，保留基本效果`n适合日常使用"; Color=$Theme.Accent; Value=2}
        @{Title="自定义"; Desc="逐项选择要关闭的效果`n精细控制"; Color=$Theme.Warning; Value=3}
    )

    $yMode = 96
    $script:radioBtns = @()
    for ($i = 0; $i -lt 3; $i++) {
        $m = $script:modes[$i]
        $card = New-Object System.Windows.Forms.Panel
        $card.Location = New-Object System.Drawing.Point(20, $yMode)
        $card.Size = New-Object System.Drawing.Size(760, 84)
        $card.BackColor = $Theme.BgCard
        $page.Controls.Add($card)

        $rb = New-Object System.Windows.Forms.RadioButton
        $rb.Location = New-Object System.Drawing.Point(12, 28)
        $rb.Size = New-Object System.Drawing.Size(24, 24)
        $rb.Checked = ($i -eq 0)
        $rb.BackColor = $Theme.BgCard
        $rb.ForeColor = $m.Color
        $card.Controls.Add($rb)
        $script:radioBtns += $rb

        $lblMode = New-Label $m.Title 44 12 200 26 $Fonts.Header $m.Color
        $card.Controls.Add($lblMode)

        $lblModeDesc = New-Label $m.Desc 44 40 700 40 $Fonts.Small $Theme.TextDim
        $card.Controls.Add($lblModeDesc)

        $yMode += 92
    }

    $script:btnApplyVisual = New-Button "应用视觉效果" 20 ([int]($yMode + 10)) 200 44 $Theme.Success 11
    $script:btnApplyVisual.Add_Click({
        try {
        $selectedMode = 1
        for ($i = 0; $i -lt 3; $i++) { if ($script:radioBtns[$i].Checked) { $selectedMode = $script:modes[$i].Value } }

        $backupFile = Join-Path $script:BackupDir "visual_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"

        $this.Enabled = $false
        $this.Text = "应用中..."
        Invoke-UIRefresh

        $visualKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        if (-not (Test-Path $visualKey)) { New-Item -Path $visualKey -Force | Out-Null }

        if ($selectedMode -eq 1) {
            # 最佳性能
            Set-ItemProperty -Path $visualKey -Name "VisualFXSetting" -Value 3 -Type DWord
            $perfKey = "HKCU:\Control Panel\Desktop"
            Set-ItemProperty -Path $perfKey -Name "DragFullWindows" -Value "0" -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $perfKey -Name "FontSmoothing" -Value "2" -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $perfKey -Name "MenuShowDelay" -Value "0" -ErrorAction SilentlyContinue
            $advKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            Set-ItemProperty -Path $advKey -Name "TaskbarAnimations" -Value 0 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $advKey -Name "ListviewAlphaSelect" -Value 0 -Type DWord -ErrorAction SilentlyContinue
            $dwmKey = "HKCU:\Software\Microsoft\Windows\DWM"
            Set-ItemProperty -Path $dwmKey -Name "EnableAeroPeek" -Value 0 -Type DWord -ErrorAction SilentlyContinue
            Write-Log "视觉效果: 最佳性能模式已应用" "SUCCESS"
        }
        elseif ($selectedMode -eq 2) {
            # 平衡
            Set-ItemProperty -Path $visualKey -Name "VisualFXSetting" -Value 3 -Type DWord
            $perfKey = "HKCU:\Control Panel\Desktop"
            Set-ItemProperty -Path $perfKey -Name "DragFullWindows" -Value "1" -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $perfKey -Name "FontSmoothing" -Value "2" -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $perfKey -Name "MenuShowDelay" -Value "100" -ErrorAction SilentlyContinue
            $advKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            Set-ItemProperty -Path $advKey -Name "TaskbarAnimations" -Value 0 -Type DWord -ErrorAction SilentlyContinue
            $dwmKey = "HKCU:\Software\Microsoft\Windows\DWM"
            Set-ItemProperty -Path $dwmKey -Name "EnableAeroPeek" -Value 0 -Type DWord -ErrorAction SilentlyContinue
            Write-Log "视觉效果: 平衡模式已应用" "SUCCESS"
        }
        else {
            # 自定义 — 简化版
            Set-ItemProperty -Path $visualKey -Name "VisualFXSetting" -Value 3 -Type DWord
            $advKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            Set-ItemProperty -Path $advKey -Name "TaskbarAnimations" -Value 0 -Type DWord -ErrorAction SilentlyContinue
            Write-Log "视觉效果: 自定义模式已应用" "SUCCESS"
        }

        # 重启资源管理器
        try { Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue; Start-Sleep 1; Start-Process explorer } catch {}

        $this.Enabled = $true
        $this.Text = "应用视觉效果"
        [System.Windows.Forms.MessageBox]::Show("视觉效果已应用！`n资源管理器已重启。", "完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            Write-Log "视觉效果出错: $($_.Exception.Message)" "ERROR"
            [System.Windows.Forms.MessageBox]::Show("视觉效果出错: $($_.Exception.Message)", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })
    $page.Controls.Add($script:btnApplyVisual)
}

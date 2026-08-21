function Build-UpdatePage {
    $page = $script:Pages["Update"]
    $page.Controls.Clear()

    $lblTitle = New-Label "更新与功能" 20 22 500 30 $Fonts.Header $Theme.TextBright
    $page.Controls.Add($lblTitle)

    $lblDesc = New-Label "管理 Windows 更新策略与可选功能（点击后在独立管理员窗口交互运行）" 20 56 760 24 $Fonts.Small $Theme.TextDim
    $page.Controls.Add($lblDesc)

    # 各模块以独立管理员 PowerShell 窗口运行（这些模块是交互式控制台程序）
    function Start-ModuleWindow {
        param([string]$ScriptName)
        try {
            $scriptPath = Join-Path $script:ScriptsDir $ScriptName
            if (-not (Test-Path $scriptPath)) {
                [System.Windows.Forms.MessageBox]::Show("找不到模块文件: $scriptPath", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                return
            }
            Write-Log "启动模块窗口: $ScriptName"
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "powershell.exe"
            $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
            $psi.Verb = "RunAs"
            $psi.UseShellExecute = $true
            [System.Diagnostics.Process]::Start($psi) | Out-Null
        } catch {
            Write-Log "启动失败: $($_.Exception.Message)" "ERROR"
            [System.Windows.Forms.MessageBox]::Show("启动失败: $($_.Exception.Message)", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }

    $cards = @(
        @{Title="屏蔽 Windows 更新"; Desc="锁定当前版本，停止反复推送升级（如 24H2）"; Script="10-BlockWin1124H2.ps1"; Color=$Theme.Success}
        @{Title="手动更新模式";   Desc="更新照常下载提示，但不自动安装 / 强制重启"; Script="11-ManualUpdateMode.ps1"; Color=$Theme.Accent}
        @{Title="恢复自动更新";   Desc="恢复 Windows Update 服务，允许系统自动下载并安装更新"; Script="14-RestoreAutoUpdate.ps1"; Color=$Theme.Success}
        @{Title="隐藏指定更新";   Desc="把指定升级藏起来，不再出现在更新列表"; Script="12-HideUpdates.ps1"; Color=$Theme.Warning}
        @{Title="Windows 可选功能"; Desc="列出并启用微软默认未开启的功能（.NET3.5/Hyper-V/WSL 等）"; Script="13-WindowsFeatures.ps1"; Color=$Theme.Accent}
    )

    $yCard = 96
    foreach ($c in $cards) {
        $card = New-Object System.Windows.Forms.Panel
        $card.Location = New-Object System.Drawing.Point(20, $yCard)
        $card.Size = New-Object System.Drawing.Size(760, 64)
        $card.BackColor = $Theme.BgCard
        $page.Controls.Add($card)

        $lblCT = New-Label $c.Title 16 12 320 26 $Fonts.Header $c.Color
        $card.Controls.Add($lblCT)

        $lblCD = New-Label $c.Desc 16 38 620 22 $Fonts.Small $Theme.TextDim
        $card.Controls.Add($lblCD)

        $btn = New-Button "运行" 660 14 86 36 $c.Color 10
        $btn.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
        # 注意：直接拼脚本名到脚本块，避免闭包/参数绑定问题
        $scriptNameLocal = $c.Script
        $btn.Add_Click({
            Start-ModuleWindow -ScriptName $scriptNameLocal
        })
        $card.Controls.Add($btn)

        $yCard += 72
    }

    # 提示文字使用单引号（避免内部双引号转义问题）
    $noteText = '提示：点击『运行』会弹出独立的管理员 PowerShell 窗口，按窗口内提示操作即可，操作完关闭该窗口返回本界面。'
    $lblNote = New-Label $noteText 20 $yCard 760 40 $Fonts.Small $Theme.TextDim
    $page.Controls.Add($lblNote)
}

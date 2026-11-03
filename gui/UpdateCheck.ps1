# ============================================================
#  更新检查（GitHub Releases）
#  说明：仓库地址优先从 config/optimization.json 的 "update_repo" 读取
#        （格式 "owner/repo"）；未配置时自动从 git remote 探测；
#        仍无法识别则返回 $null（不弹窗、不打扰）。
# ============================================================

function Get-GitHubRepo {
    # 返回 "owner/repo" 或 $null
    try {
        $cfgPath = Join-Path $script:ProjectRoot "config\optimization.json"
        if (Test-Path $cfgPath) {
            $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cfg.update_repo) { return $cfg.update_repo }
        }
    } catch {
        Write-Log "读取更新仓库配置失败: $($_.Exception.Message)" "WARN"
    }
    # 从 git remote 自动探测
    try {
        $remote = & git -C $script:ProjectRoot remote get-url origin 2>$null
        if ($remote) {
            if ($remote -match 'github\.com[:/]([^/]+)/(.+?)(?:\.git)?$') {
                return ($Matches[1] + '/' + $Matches[2])
            }
        }
    } catch {
        Write-Log "从 git remote 探测仓库失败: $($_.Exception.Message)" "WARN"
    }
    return $null
}

function Get-GitHubLatestRelease {
    $repo = Get-GitHubRepo
    if ([string]::IsNullOrWhiteSpace($repo)) {
        Write-Log "未配置 update_repo 且无法从 git remote 探测，跳过更新检查。" "INFO"
        return $null
    }
    try {
        $url = "https://api.github.com/repos/$repo/releases/latest"
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "PC-Optimizer")
        $wc.Encoding = [System.Text.Encoding]::UTF8
        $json = $wc.DownloadString($url)
        $release = $json | ConvertFrom-Json
        if ($release -and $release.tag_name) {
            return $release
        }
        return $null
    } catch {
        Write-Log "获取最新版本信息失败: $($_.Exception.Message)" "WARN"
        return $null
    }
}

function Show-UpdatePrompt {
    param(
        [Parameter(Mandatory=$true)] $Release,
        [switch]$QuietWhenLatest
    )
    $latest = $Release.tag_name -replace '^v', ''
    $current = $script:Version
    $hasUpdate = $false
    try {
        $v1 = [version]($latest -replace '[^\d.]', '')
        $v2 = [version]($current -replace '[^\d.]', '')
        $hasUpdate = ($v1 -gt $v2)
    } catch {
        $hasUpdate = ($latest -ne $current)
    }
    if ($hasUpdate) {
        $msg = "发现新版本：$($Release.tag_name)`n`n当前版本：$current`n下载地址：$($Release.html_url)`n`n是否打开下载页面？"
        $r = [System.Windows.Forms.MessageBox]::Show($msg, "发现更新", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Information)
        if ($r -eq [System.Windows.Forms.DialogResult]::Yes) {
            Start-Process $Release.html_url
        }
    } elseif (-not $QuietWhenLatest) {
        [System.Windows.Forms.MessageBox]::Show("当前已是最新版本 ($current)。", "检查更新", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
}

function Start-BackgroundUpdateCheck {
    param([int]$DelaySeconds = 5)
    # 启动后延迟几秒静默检查一次，仅发现新版本时弹窗（不阻塞界面、无新版不打扰）
    #
    # ⚠️ 不要把这里改回「裸 .NET 线程 + PowerShell 脚本块」：
    #    普通线程的 TLS 里没有 runspace，脚本块一被调用就抛
    #    PSInvalidOperationException（ScriptBlock.GetContextFromTLS），
    #    而该异常发生在 IsBackground 线程上、没有任何调用栈能捕获它，
    #    会直接终止整个进程 —— 症状就是「主窗口刚显示出来就闪退」。
    #    现在改成 UI 线程上的计时器触发异步下载，完成事件同样回到 UI 线程，
    #    不占用后台线程，也不阻塞界面。
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = [math]::Max(1, $DelaySeconds) * 1000
    $script:UpdateCheckTimer = $timer
    $timer.Add_Tick({
        param($Sender, $EventArgs)
        try {
            if ($Sender) {
                $Sender.Stop()
                $Sender.Dispose()
            }
            $script:UpdateCheckTimer = $null

            $repo = Get-GitHubRepo
            if ([string]::IsNullOrWhiteSpace($repo)) {
                Write-Log "未配置 update_repo 且无法从 git remote 探测，跳过更新检查。" "INFO"
                return
            }
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "PC-Optimizer")
            $wc.Encoding = [System.Text.Encoding]::UTF8
            # 挂到脚本作用域，避免异步请求期间被 GC 回收
            $script:UpdateCheckClient = $wc
            $wc.Add_DownloadStringCompleted({
                param($SenderWc, $EventArgsWc)
                try {
                    if ($null -ne $EventArgsWc.Error -or $EventArgsWc.Cancelled) { return }
                    if ([string]::IsNullOrWhiteSpace($EventArgsWc.Result)) { return }
                    $release = $EventArgsWc.Result | ConvertFrom-Json
                    if (-not $release -or -not $release.tag_name) { return }
                    if ($script:MainForm -and -not $script:MainForm.IsDisposed) {
                        Show-UpdatePrompt -Release $release -QuietWhenLatest
                    }
                } catch {
                    Write-Log "自动检查更新提示失败: $($_.Exception.Message)" "WARN"
                }
            })
            try {
                $null = $wc.DownloadStringAsync([Uri]"https://api.github.com/repos/$repo/releases/latest")
            } catch {
                Write-Log "获取最新版本信息失败: $($_.Exception.Message)" "WARN"
            }
        } catch {
            Write-Log "后台检查更新异常: $($_.Exception.Message)" "WARN"
        }
    })
    $timer.Start()
}

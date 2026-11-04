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
    # ⚠️ 线程模型安全说明：
    #    任何在非 UI 线程或 ThreadPool 线程上执行 PowerShell 脚本块的操作（例如
    #    WebClient.DownloadStringCompleted 或裸 Thread），都会因该线程 TLS 中缺少
    #    Runspace 而抛出无法被用户代码捕获的 PSInvalidOperationException，导致静默崩溃闪退。
    #    因此采用安全架构：
    #    1. 使用专属的 [PowerShell]::Create() 实例在独立专用 Runspace 中异步发起网络请求；
    #    2. 主 UI 线程上的计时器按秒轮询 IAsyncResult.IsCompleted；
    #    3. 结果就绪后，在主 UI 线程上调用 EndInvoke 并安全弹窗，100% 线程安全无崩溃。
    $repo = Get-GitHubRepo
    if ([string]::IsNullOrWhiteSpace($repo)) {
        Write-Log "未配置 update_repo 且无法从 git remote 探测，跳过更新检查。" "INFO"
        return
    }

    try {
        $ps = [PowerShell]::Create()
        [void]$ps.AddScript({
            param($r)
            try {
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]'Tls12'
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add("User-Agent", "PC-Optimizer")
                $wc.Encoding = [System.Text.Encoding]::UTF8
                $json = $wc.DownloadString("https://api.github.com/repos/$r/releases/latest")
                return ($json | ConvertFrom-Json)
            } catch {
                return $null
            }
        }).AddParameter("r", $repo)

        $asyncResult = $ps.BeginInvoke()
        $script:UpdateCheckPS = $ps
        $script:UpdateCheckAsync = $asyncResult
        $script:UpdateCheckTicks = 0

        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = 1000
        $script:UpdateCheckTimer = $timer

        $timer.Add_Tick({
            param($Sender, $EventArgs)
            try {
                $script:UpdateCheckTicks++
                if ($script:UpdateCheckTicks -lt $DelaySeconds) { return }

                $targetTimer = if ($Sender) { $Sender } elseif ($this) { $this } else { $script:UpdateCheckTimer }

                if ($script:UpdateCheckAsync -and $script:UpdateCheckAsync.IsCompleted) {
                    if ($targetTimer) { $targetTimer.Stop(); $targetTimer.Dispose() }
                    $script:UpdateCheckTimer = $null

                    $results = $script:UpdateCheckPS.EndInvoke($script:UpdateCheckAsync)
                    $script:UpdateCheckPS.Dispose()
                    $script:UpdateCheckPS = $null
                    $script:UpdateCheckAsync = $null

                    if ($results -and $results.Count -gt 0) {
                        $release = $results[0]
                        if ($release -and $release.tag_name -and $script:MainForm -and -not $script:MainForm.IsDisposed) {
                            Show-UpdatePrompt -Release $release -QuietWhenLatest
                        }
                    }
                } elseif ($script:UpdateCheckTicks -gt 30) {
                    if ($targetTimer) { $targetTimer.Stop(); $targetTimer.Dispose() }
                    $script:UpdateCheckTimer = $null
                    if ($script:UpdateCheckPS) {
                        $script:UpdateCheckPS.Dispose()
                        $script:UpdateCheckPS = $null
                        $script:UpdateCheckAsync = $null
                    }
                }
            } catch {
                Write-Log "后台检查更新处理失败: $($_.Exception.Message)" "WARN"
            }
        })
        $timer.Start()
    } catch {
        Write-Log "初始化后台更新检查失败: $($_.Exception.Message)" "WARN"
    }
}

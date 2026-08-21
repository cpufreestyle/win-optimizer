# ============================================================
#  更新检查（GitHub Releases）
#  说明：仓库地址从 config/optimization.json 的 "update_repo" 读取，
#        格式为 "owner/repo"；未配置则返回 $null（不弹窗、不打扰）。
# ============================================================

function Get-GitHubLatestRelease {
    $repo = $null
    try {
        $cfgPath = Join-Path $script:ProjectRoot "config\optimization.json"
        if (Test-Path $cfgPath) {
            $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cfg.update_repo) { $repo = $cfg.update_repo }
        }
    } catch {
        Write-Log "读取更新仓库配置失败: $($_.Exception.Message)" "WARN"
    }
    if ([string]::IsNullOrWhiteSpace($repo)) {
        Write-Log "未配置 update_repo，跳过更新检查。" "INFO"
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
    # 启动后延迟几秒在后台静默检查一次，仅发现新版本时弹窗（不阻塞界面、无新版不打扰）
    $thread = New-Object System.Threading.Thread([System.Threading.ThreadStart]{
        Start-Sleep -Seconds 5
        $release = Get-GitHubLatestRelease
        if (-not $release) { return }
        try {
            if ($script:MainForm -and -not $script:MainForm.IsDisposed) {
                $script:MainForm.Invoke([Action]{ Show-UpdatePrompt -Release $release -QuietWhenLatest })
            }
        } catch {
            Write-Log "自动检查更新提示失败: $($_.Exception.Message)" "WARN"
        }
    })
    $thread.IsBackground = $true
    $thread.Start()
}

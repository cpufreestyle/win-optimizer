<#
.SYNOPSIS
    屏蔽 Windows 更新模块（加强版 / 硬锁，含 24H2 等功能升级）
.DESCRIPTION
    针对 7代及更老 CPU 的老电脑，反复被 Windows Update 推送 "Windows 11, version 24H2"
    功能升级（Feature Update）的问题。本模块采用"软策略 + 硬锁 + 隐藏更新"三重叠加，
    专门解决"之前屏蔽了还是反复弹 24H2"的情况：

      1. 读取当前具体版本号（DisplayVersion，如 23H2），锁定到该版本，
         而非笼统的 "Windows 11"（之前失效的主因）。
      2. 写入更高优先级的 UpdatePolicy 通道（组策略等价注册表），
         覆盖被累积更新重置的普通策略。
      3. 通过 Windows Update API 把 24H2 升级项直接"隐藏"，不再出现在更新列表。
      4. 所有注册表更改自动备份（.reg），可通过 [R] 一键恢复。

    适用：Windows 11 专业版 / 企业版 / 教育版（含组策略等价注册表通道）。
.NOTES
    需要以管理员身份运行（由 Optimize.ps1 入口统一校验）。
#>

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   屏蔽 Windows 更新（硬锁加强版，含 24H2 等升级）" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# --- 路径定义 ---
$backupDir = Join-Path $PSScriptRoot "..\backups"
$backupDir = [System.IO.Path]::GetFullPath($backupDir)
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }

$regKeys = @(
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate",
    "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings",
    "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\Settings"
)

# --- [1/4] 备份 ---
Write-Host "`n[1/4] 备份当前 Windows Update 相关注册表..." -ForegroundColor Yellow
$backupFile = Join-Path $backupDir "winupdate_block_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
$backupOk = $true
foreach ($key in $regKeys) {
    if (Test-Path $key) {
        try {
            & reg export $key $backupFile /y 2>$null
            if ($LASTEXITCODE -ne 0) { $backupOk = $false }
        } catch { $backupOk = $false }
    }
}
if ($backupOk) {
    Write-Host "  备份已保存: $backupFile" -ForegroundColor Green
} else {
    Write-Host "  警告：注册表备份部分失败，请谨慎操作。" -ForegroundColor Yellow
}

# --- [2/4] 检测当前版本 ---
Write-Host "`n[2/4] 检测当前系统..." -ForegroundColor Yellow
$curOS = Get-CimInstance Win32_OperatingSystem
Write-Host "  当前系统 : $($curOS.Caption) Build $($curOS.BuildNumber)"

# 读取具体版本号（如 23H2 / 22H2）。优先从注册表 DisplayVersion 读取。
$currentDisplayVersion = $null
$verKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
if (Test-Path $verKey) {
    $currentDisplayVersion = (Get-ItemProperty -Path $verKey -Name "DisplayVersion" -ErrorAction SilentlyContinue).DisplayVersion
}
if (-not $currentDisplayVersion) {
    # 兜底：用 BuildNumber 推断
    $build = [int]$curOS.BuildNumber
    $currentDisplayVersion = switch ($build) {
        { $_ -ge 26100 } { "24H2" }   # 已经/正在 24H2，无需屏蔽
        { $_ -ge 22631 } { "23H2" }
        { $_ -ge 22621 } { "22H2" }
        { $_ -ge 22000 } { "21H2" }
        default          { "22H2" }
    }
}
Write-Host "  当前版本 : $currentDisplayVersion" -ForegroundColor Green

# --- 函数：暂停更新 + 改为手动安装模式（针对已为 24H2、被累积更新弹窗困扰的场景） ---
function Invoke-PauseUpdates {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "   已为 24H2：改为暂停更新 + 手动安装模式" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan

    Write-Host "`n[1/2] 设置 Windows Update 为'通知下载并通知安装'..." -ForegroundColor Yellow
    try {
        $auKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        if (-not (Test-Path $auKey)) { New-Item -Path $auKey -Force | Out-Null }
        # 2 = 通知下载并通知安装（不自动下载、不强制重启）
        Set-ItemProperty -Path $auKey -Name "NoAutoUpdate" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $auKey -Name "AUOptions" -Value 2 -Type DWord -Force
        Write-Host "  [已设置] 自动更新模式 = 通知下载并通知安装" -ForegroundColor Green
    } catch {
        Write-Host "  [失败] 设置 AUOptions: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host "`n[2/2] 暂停质量/功能更新（最多 5 周，专业版）..." -ForegroundColor Yellow
    try {
        $now = Get-Date
        # 暂停截止日期（最多 35 天）
        $pauseEnd = $now.AddDays(35).ToString("yyyy-MM-ddTHH:mm:ssZ")
        $settingsKey = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
        if (-not (Test-Path $settingsKey)) { New-Item -Path $settingsKey -Force | Out-Null }
        Set-ItemProperty -Path $settingsKey -Name "PauseUpdatesExpiryTime" -Value $pauseEnd -Type String -Force
        Set-ItemProperty -Path $settingsKey -Name "PauseFeatureUpdatesEndTime" -Value $pauseEnd -Type String -Force
        Set-ItemProperty -Path $settingsKey -Name "PauseQualityUpdatesEndTime" -Value $pauseEnd -Type String -Force
        Write-Host "  [已设置] 更新已暂停至 $pauseEnd" -ForegroundColor Green
    } catch {
        Write-Host "  [失败] 设置暂停: $($_.Exception.Message)" -ForegroundColor Red
    }

    # 重启服务使生效
    foreach ($svc in @("wuauserv", "UsoSvc")) {
        try { Restart-Service -Name $svc -Force -ErrorAction SilentlyContinue; Write-Host "  [完成] $svc 已重启" -ForegroundColor Green } catch {}
    }

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  已完成！更新弹窗将不再强制出现。" -ForegroundColor Green
    Write-Host "  累积更新已暂停，且改为手动安装模式，" -ForegroundColor Gray
    Write-Host "  你想装的时候再去 设置->Windows 更新 手动点。" -ForegroundColor Gray
    Write-Host "  暂停到期后如需继续屏蔽，可再次运行本模块。" -ForegroundColor Gray
    Write-Host "  如需恢复自动更新：用 [R] 恢复本模块 .reg 备份，" -ForegroundColor Gray
    Write-Host "  或在设置里把'暂停更新'改回'继续'。" -ForegroundColor Gray
    Write-Host "============================================" -ForegroundColor Cyan
}

if ($currentDisplayVersion -eq "24H2") {
    Write-Host "  检测到当前已是 24H2（Build $($curOS.BuildNumber)）。" -ForegroundColor Yellow
    Write-Host "  无需屏蔽功能升级；改为处理累积更新弹窗问题。" -ForegroundColor Yellow
    $confirm = Read-Host "`n改为：暂停更新 + 手动安装模式？(Y/N)"
    if ($confirm -eq "Y" -or $confirm -eq "y") {
        Invoke-PauseUpdates
    } else {
        Write-Host "  操作已取消。" -ForegroundColor Gray
        Write-Host "============================================" -ForegroundColor Cyan
    }
    return
}

# --- 用户确认 ---
Write-Host ""
Write-Host "  即将执行的屏蔽措施（三重叠加）：" -ForegroundColor Yellow
Write-Host "   [1] 锁定版本到当前 $currentDisplayVersion（TargetReleaseVersion）" -ForegroundColor Gray
Write-Host "   [2] 写入 UpdatePolicy 高优先级通道（组策略等价）" -ForegroundColor Gray
Write-Host "   [3] 通过 WUAPI 隐藏 24H2 升级项" -ForegroundColor Gray

$confirm = Read-Host "`n确认屏蔽 Windows 11 24H2 升级？(Y/N)"
if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-Host "  操作已取消。" -ForegroundColor Gray
    Write-Host "============================================" -ForegroundColor Cyan
    return
}

# --- [3/4] 应用硬锁策略 ---
Write-Host "`n[3/4] 正在应用屏蔽策略..." -ForegroundColor Yellow

# 措施 1：TargetReleaseVersion（锁定到具体版本号，而非笼统名）
try {
    $releaseKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    if (-not (Test-Path $releaseKey)) { New-Item -Path $releaseKey -Force | Out-Null }
    Set-ItemProperty -Path $releaseKey -Name "TargetReleaseVersion" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $releaseKey -Name "TargetReleaseVersionInfo" -Value $currentDisplayVersion -Type String -Force
    # 同时兼容"产品版本 + 目标版本"写法
    Set-ItemProperty -Path $releaseKey -Name "ProductVersion" -Value "Windows 11" -Type String -Force
    Set-ItemProperty -Path $releaseKey -Name "TargetVersion" -Value $currentDisplayVersion -Type String -Force
    Write-Host "  [已设置] 锁定版本：$currentDisplayVersion" -ForegroundColor Green
} catch {
    Write-Host "  [失败] TargetReleaseVersion: $($_.Exception.Message)" -ForegroundColor Red
}

# 措施 2：UpdatePolicy 高优先级通道（组策略 "选择目标功能更新版本" 的等价注册表）
try {
    $policyKey = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\Settings"
    if (-not (Test-Path $policyKey)) { New-Item -Path $policyKey -Force | Out-Null }
    # 该通道使用 JSON 字符串形式的策略
    $policyJson = '{"U" :[{"F":"24H2"}]}'
    # 实际生效键为 ProductVersion / TargetReleaseVersionInfo（与组策略一致）
    Set-ItemProperty -Path $policyKey -Name "ProductVersion" -Value "Windows 11" -Type String -Force
    Set-ItemProperty -Path $policyKey -Name "TargetReleaseVersionInfo" -Value $currentDisplayVersion -Type String -Force
    Set-ItemProperty -Path $policyKey -Name "TargetReleaseVersion" -Value 1 -Type DWord -Force
    Write-Host "  [已设置] UpdatePolicy 高优先级通道已写入" -ForegroundColor Green
} catch {
    Write-Host "  [失败] UpdatePolicy: $($_.Exception.Message)" -ForegroundColor Red
}

# 措施 3：通过 WUAPI 隐藏 24H2 升级项
Write-Host "  [执行] 正在通过 Windows Update API 隐藏 24H2 升级..." -ForegroundColor Yellow
$hiddenCount = 0
try {
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    # 搜索所有"升级"类（分类包含 Upgrades）且标题含 24H2 的更新
    $searchResult = $searcher.Search("IsInstalled=0 AND Type='Software'")
    foreach ($update in $searchResult.Updates) {
        $title = $update.Title
        if ($title -match "24H2" -or $title -match "FeatureUpdate") {
            try {
                $update.IsHidden = $true
                $hiddenCount++
                Write-Host "    [已隐藏] $title" -ForegroundColor Green
            } catch {
                Write-Host "    [跳过] 无法隐藏: $title" -ForegroundColor Gray
            }
        }
    }
    if ($hiddenCount -eq 0) {
        Write-Host "    未发现待隐藏的 24H2 升级项（可能尚未检索到，可稍后重试）。" -ForegroundColor Gray
    }
} catch {
    Write-Host "  [提示] WUAPI 隐藏失败：$($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "    可手动运行微软 'wushowhide.diagcab' 工具隐藏 24H2。" -ForegroundColor Gray
}

# --- [3.5/4] 急救模式：拦截已下载的 24H2 安装包与挂起的重启 ---
Write-Host "`n[3.5/4] 急救模式：清除已下载的 24H2 与取消挂起的重启..." -ForegroundColor Yellow

# 取消任何挂起的重启（用户主动点了"立即重启"才会生效）
try {
    & shutdown /a 2>$null
    Write-Host "  [急救] 已尝试取消挂起的重启（shutdown /a）" -ForegroundColor Green
} catch {
    Write-Host "  [急救] 未发现挂起的重启" -ForegroundColor Gray
}

# 清空 SoftwareDistribution\Download（已下载未安装的更新缓存）
try {
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    $sdPath = Join-Path $env:SystemRoot "SoftwareDistribution\Download"
    if (Test-Path $sdPath) {
        $cleared = 0
        Get-ChildItem -Path $sdPath -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            try { Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue; $cleared++ } catch {}
        }
        Write-Host "  [急救] 已清理 SoftwareDistribution\Download：$cleared 个文件" -ForegroundColor Green
    }
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue
} catch {
    Write-Host "  [急救] 清理 SoftwareDistribution 失败：$($_.Exception.Message)" -ForegroundColor Yellow
}

# --- [4/4] 重启相关服务使策略生效 ---
Write-Host "`n[4/4] 正在重启 Windows Update 服务使策略生效..." -ForegroundColor Yellow
foreach ($svc in @("wuauserv", "UsoSvc")) {
    try {
        Restart-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Write-Host "  [完成] $svc 已重启" -ForegroundColor Green
    } catch {
        Write-Host "  [提示] 未能重启 $svc，可手动重启或重启电脑。" -ForegroundColor Gray
    }
}

# --- [5/5] 自检：确认策略是否真的生效，是否被域/Intune 组策略覆盖 ---
Write-Host "`n[5/5] 自检：确认策略是否生效..." -ForegroundColor Yellow

$selfCheckOk = $true

# 5.1 重新读取刚写入的键值，确认未被立刻重置
$releaseKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$checkTarget = $null
if (Test-Path $releaseKey) {
    $checkTarget = (Get-ItemProperty -Path $releaseKey -Name "TargetReleaseVersionInfo" -ErrorAction SilentlyContinue).TargetReleaseVersionInfo
}
if ($checkTarget -eq $currentDisplayVersion) {
    Write-Host "  [通过] TargetReleaseVersionInfo 已锁定为 $checkTarget" -ForegroundColor Green
} else {
    Write-Host "  [警告] 写入值未生效（当前=$checkTarget），可能被组策略覆盖！" -ForegroundColor Red
    $selfCheckOk = $false
}

# 5.2 检测是否存在域/Intune 组策略在管理 Windows Update
$gpoManaged = $false
try {
    $gpoKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Control Panel\Windows Update"
    if (Test-Path $gpoKey) { $gpoManaged = $true }
    # 更通用的判断：Policies 下 WindowsUpdate 是否由 GPO 强制
    $gpoResult = & gpresult /r 2>$null
    if ($gpoResult -match "Windows Update" -or $gpoResult -match "Intune" -or $gpoResult -match "MDM") {
        $gpoManaged = $true
    }
} catch { }

if ($gpoManaged) {
    Write-Host "  [重要] 检测到本机受 域组策略 / Intune(MDM) 管理！" -ForegroundColor Red
    Write-Host "    本模块写入的注册表可能被策略定期重置，导致'装好又弹'。" -ForegroundColor Yellow
    Write-Host "    排查步骤：" -ForegroundColor Yellow
    Write-Host "      1) 以管理员运行: gpresult /r" -ForegroundColor Gray
    Write-Host "         -> 查看 '应用到本机的组策略对象' 中是否有 Windows Update 相关 GPO" -ForegroundColor Gray
    Write-Host "      2) 运行: rsop.msc -> 计算机配置 -> 管理模板 -> Windows 组件 -> Windows 更新" -ForegroundColor Gray
    Write-Host "         -> 查看 '选择目标功能更新版本' / '管理预览版' 等项是否已被强制" -ForegroundColor Gray
    Write-Host "      3) 若是公司/学校电脑，需联系 IT 在 GPO/Intune 中放行，或加入 '目标发布版本' 策略" -ForegroundColor Gray
    Write-Host "      4) 临时规避: 在本机 gpedit.msc 设置相同策略可覆盖域默认值（若未被强制禁用）" -ForegroundColor Gray
    $selfCheckOk = $false
} else {
    Write-Host "  [通过] 未检测到域/Intune 组策略强制管理 Windows Update" -ForegroundColor Green
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  屏蔽完成（三重叠加）！" -ForegroundColor Green
Write-Host "  已锁定到当前版本 $currentDisplayVersion，" -ForegroundColor Gray
Write-Host "  并隐藏 24H2 升级项，应不再反复弹窗。" -ForegroundColor Gray
if (-not $selfCheckOk) {
    Write-Host "  ⚠ 自检发现异常：策略可能未生效或被组策略覆盖，请查看上方提示。" -ForegroundColor Red
} else {
    Write-Host "  ✔ 自检通过：策略已生效。" -ForegroundColor Green
}
Write-Host "  若仍出现，请重启电脑后再次运行本模块。" -ForegroundColor Gray
Write-Host "  如需恢复：使用 [R] 恢复功能，选择本模块生成的 .reg 备份。" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan

<#
.SYNOPSIS
    7代CPU老电脑 Windows 系统优化工具
.DESCRIPTION
    专为 7代及更老 CPU 的 Windows 10/11 电脑设计的系统优化脚本。
    包含临时文件清理、服务优化、启动项管理、视觉效果调整、电源计划优化、
    磁盘优化、网络优化等功能，并提供备份与恢复机制。
.NOTES
    需要以管理员身份运行 PowerShell
    作者: PC-Optimizer-7thGen
    日期: 2026-07-06
#>

#Requires -Version 5.1

param(
    [switch]$Plan,               # 只读预览「全面优化将做什么」，不执行任何修改
    [string]$Profile = '',       # -Plan 时额外附上某个优化组合包的步骤预览
    [switch]$SkipCleanScan,      # -Plan 时跳过可清理空间统计（省十几秒）
    [switch]$GuidedPlan,         # 只读预览「一键向导会怎么走」，不需要管理员权限
    [switch]$Guided              # 直接进入一键向导（供启动器一键直达，跳过主菜单）
)

# ============================================================
#  全局变量与初始化
# ============================================================
$script:ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ScriptsDir  = Join-Path $ProjectRoot "scripts"
$script:ConfigDir   = Join-Path $ProjectRoot "config"
$script:BackupDir   = Join-Path $ProjectRoot "backups"
$script:LogFile     = Join-Path $ProjectRoot "optimize.log"
# 共享核心库（版本号单一来源 Get-OptVersion 等）
$coreLib = Join-Path $ProjectRoot "lib\Optimize.Core.ps1"
if (Test-Path $coreLib) { . $coreLib }
$script:Version     = Get-OptVersion

# ============================================================
#  工具函数
# ============================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    # 优先复用共享库实现（AppendAllText 单次写入，高频调用比 Add-Content 更省 IO）
    if (Get-Command Write-OptLog -ErrorAction SilentlyContinue) {
        Write-OptLog -Message $Message -Level $Level -Path $LogFile
        return
    }
    # 共享库不可用时的等价兜底
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    switch ($Level) {
        "ERROR"   { Write-Host $line -ForegroundColor Red }
        "WARN"    { Write-Host $line -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $line -ForegroundColor Green }
        default   { Write-Host $line -ForegroundColor Cyan }
    }
}

function Test-Administrator {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-ScriptModule {
    param([string]$ScriptName, [switch]$NoPause)
    $scriptPath = Join-Path $ScriptsDir $ScriptName
    if (Test-Path $scriptPath) {
        Write-Log "正在执行模块: $ScriptName ..."
        try {
            & $scriptPath
            Write-Log "模块 $ScriptName 执行完成。" "SUCCESS"
            return $true
        } catch {
            Write-Log "模块 $ScriptName 执行失败: $($_.Exception.Message)" "ERROR"
            return $false
        }
    } else {
        Write-Log "找不到模块文件: $scriptPath" "ERROR"
        return $false
    }
    Write-Host ""
    if (-not $NoPause) { Read-Host "按回车键返回主菜单" }
}

function Show-Banner {
    Clear-Host
    $banner = @"
  ____  ____  ___  ____  _____    _    ____  
 |  _ \|  _ \/ _ \|  _ \| ____|  / \  / ___| 
 | |_) | |_) | | | | | | |  _|   / _ \| |    
 |  __/|  _ <| |_| | |_| | |___ / ___ \ |___ 
 |_|   |_| \_\\___/|____/|_____/_/   \_\____|
                                              
   7代CPU老电脑 Windows 优化工具 v$Version
   专为 Intel 7代及更老 CPU 打造 | Windows 10/11
"@
    Write-Host $banner -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor DarkGray
}

# ============================================================
#  主菜单
# ============================================================

function Show-Menu {
    $script:PlanProfile       = $Profile
    $script:PlanSkipCleanScan = $SkipCleanScan
    while ($true) {
        Show-Banner

        # 显示当前系统简要信息
        $os = (Get-CimInstance Win32_OperatingSystem)
        $cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1)
        $totalMem = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $freeMem  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        $uptime   = (Get-Date) - $os.LastBootUpTime

        Write-Host " [系统概况]" -ForegroundColor Yellow
        Write-Host "   CPU      : $($cpu.Name)"
        Write-Host "   内存     : ${totalMem}GB (可用 ${freeMem}GB)"
        Write-Host "   系统     : $($os.Caption) Build $($os.BuildNumber)"
        Write-Host "   运行时间 : $($uptime.Days)天 $($uptime.Hours)小时"
        Write-Host ""

        Write-Host " [优化选项]" -ForegroundColor Yellow
        Write-Host "   [0]  一键向导（推荐）    — 体检+推荐+执行+复检，一步到位，新手选它" -ForegroundColor Green
        Write-Host ""
        Write-Host "   [1]  系统信息检测        — 查看详细硬件与系统信息"
        Write-Host "   [2]  临时文件清理        — 清理系统/用户临时文件、缓存"
        Write-Host "   [3]  服务优化            — 禁用不必要的后台服务"
        Write-Host "   [4]  启动项优化          — 管理并禁用多余开机启动项"
        Write-Host "   [5]  视觉效果优化        — 降低视觉特效，提升响应速度"
        Write-Host "   [6]  电源计划优化        — 切换高性能电源计划"
        Write-Host "   [7]  磁盘优化            — 磁盘清理与碎片整理/SSD优化"
        Write-Host "   [8]  网络优化            — 优化DNS与网络参数"
        Write-Host "   [9]  一键全面优化        — 执行上述所有优化（推荐）"
        Write-Host "   [10] 屏蔽 Windows 更新   — 停止反复推送升级（如 24H2）"
        Write-Host "   [11] 手动更新模式         — 不暂停，但不自动安装/重启"
        Write-Host "   [12] 隐藏指定更新         — 把指定升级藏起来不再出现"
        Write-Host "   [13] Windows 可选功能     — 列出并启用微软默认未开启的功能"
        Write-Host "   [14] 恢复自动更新         — 恢复 Windows Update 服务与计划任务"
        Write-Host "   [15] 一键体检（只读）      — 体检分 + 问题清单，可优化前后对比"
        Write-Host "   [16] 优化组合包          — 老机均衡/游戏/省电/最小干预，一键到位"
        Write-Host ""
        Write-Host " [工具]" -ForegroundColor Yellow
        Write-Host "   [B]  备份当前系统设置"
        Write-Host "   [R]  恢复系统设置"
        Write-Host ""
        Write-Host "   [P]  优化预览（只读）   — 先看全面优化将做什么，不改任何设置" -ForegroundColor Cyan
        Write-Host "   [Q]  退出"
        Write-Host ("=" * 60) -ForegroundColor DarkGray

        $choice = Read-Host "请输入选项"

        switch ($choice) {
            "0" { Invoke-GuidedOptimization }
            "1" { Invoke-ScriptModule "01-SystemInfo.ps1" }
            "2" { Invoke-ScriptModule "02-CleanTemp.ps1" }
            "3" { Invoke-ScriptModule "03-DisableServices.ps1" }
            "4" { Invoke-ScriptModule "04-StartupOptimize.ps1" }
            "5" { Invoke-ScriptModule "05-VisualEffects.ps1" }
            "6" { Invoke-ScriptModule "06-PowerPlan.ps1" }
            "7" { Invoke-ScriptModule "07-DiskOptimize.ps1" }
            "8" { Invoke-ScriptModule "08-NetworkOptimize.ps1" }
            "9" { Invoke-FullOptimization }
            "10" { Invoke-ScriptModule "10-BlockWin1124H2.ps1" }
            "11" { Invoke-ScriptModule "11-ManualUpdateMode.ps1" }
            "12" { Invoke-ScriptModule "12-HideUpdates.ps1" }
            "13" { Invoke-ScriptModule "13-WindowsFeatures.ps1" }
            "14" { Invoke-ScriptModule "14-RestoreAutoUpdate.ps1" }
            "15" { Invoke-ScriptModule "15-HealthCheck.ps1" }
            "16" { Invoke-ScriptModule "16-Profiles.ps1" }
            { $_ -eq "B" -or $_ -eq "b" } { Invoke-ScriptModule "09-BackupRestore.ps1" }
            { $_ -eq "R" -or $_ -eq "r" } { Invoke-ScriptModule "09-BackupRestore.ps1" }
            { $_ -eq "P" -or $_ -eq "p" } { Show-OptimizePlanPreview }
            { $_ -eq "Q" -or $_ -eq "q" } { Write-Host "感谢使用，再见！" -ForegroundColor Green; return }
            default { Write-Host "无效选项，请重新输入。" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

# 只读预览：完整优化每一步将做什么（与 WebUI / MCP 的 optimize_plan 同源）
function Show-OptimizePlanPreview {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  优化预览（只读，不执行任何修改）" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  正在统计（可清理空间较慢，约十几秒）..." -ForegroundColor DarkGray
    $planArgs = @{}
    if ($script:PlanProfile)       { $planArgs['ProfileName']    = $script:PlanProfile }
    if ($script:PlanSkipCleanScan) { $planArgs['SkipCleanScan']  = $true }
    # 注意：局部变量不能叫 $plan——脚本参数 [switch]$Plan 会让同名变量变成
    # SwitchParameter 类型，往里塞 PSCustomObject 会直接转换失败。
    $planPreview = Get-OptimizePlan @planArgs
    if (-not $planPreview.ok) {
        Write-Host "  预览失败: $($planPreview.error)" -ForegroundColor Red
        Read-Host "按回车键返回主菜单"
        return
    }
    Write-Host ("  共 {0} 步（低危 {1} / 中危 {2} / 高危 {3}）；电源目标 {4}，DNS {5}" -f `
        $planPreview.summary.total, $planPreview.summary.low, $planPreview.summary.medium, $planPreview.summary.high, `
        $planPreview.powerPlan, $planPreview.dns) -ForegroundColor Gray
    foreach ($line in @(Format-OptimizePlan $planPreview)) { Write-Host $line -ForegroundColor DarkGray }
    Write-Host ""
    Write-Host "  说明: 以上仅为预览。真要执行请在菜单选择 [9] 一键全面优化。" -ForegroundColor Yellow
    Read-Host "按回车键返回主菜单"
}

# ============================================================
#  一键向导（新手入口）：体检 -> 推荐 -> 预览 -> 执行 -> 复检
#  与菜单 [15] 体检 / [16] 组合包同源，只是把「该选哪个」交给程序判断，
#  执行默认不传 -Force，因此高危步骤一律跳过，不会误删启动项或做整盘优化。
# ============================================================

# 只读地渲染一份向导计划（供菜单 [0] 与 -GuidedPlan 共用）
function Show-GuidedPlanPreview {
    param([object]$Preview, [switch]$WithHint)
    foreach ($line in @(Format-GuidedPlan -Plan $Preview)) {
        Write-Host $line -ForegroundColor DarkGray
    }
    if ($WithHint) {
        Write-Host "  说明: 以上仅为预览。真要执行请在菜单选择 [0] 一键向导。" -ForegroundColor Yellow
    }
}

function Invoke-GuidedOptimization {
    Write-Log "开始一键向导..." "WARN"
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  一键向导（体检 -> 推荐 -> 执行 -> 自动复检）" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  正在体检（统计可清理空间约十几秒）..." -ForegroundColor DarkGray

    $guidedPreview = Get-GuidedPlan
    if (-not $guidedPreview.ok) {
        Write-Host "  体检失败: $($guidedPreview.error)" -ForegroundColor Red
        Read-Host "按回车键返回主菜单"
        return
    }

    # --- 把「推荐什么、将要做什么」一次讲清楚 ---
    Write-Host ""
    Show-GuidedPlanPreview -Preview $guidedPreview
    Write-Host ""

    if (-not $guidedPreview.profile.matched) {
        Write-Host "  推荐组合包不可用，请改用菜单 [16] 手动选择。" -ForegroundColor Red
        Read-Host "按回车键返回主菜单"
        return
    }
    if (@($guidedPreview.steps).Count -eq 0) {
        Write-Host "  该系统当前无需改动，体检结果见菜单 [15]。" -ForegroundColor Green
        Read-Host "按回车键返回主菜单"
        return
    }
    if ($guidedPreview.summary.autoSteps -eq 0) {
        Write-Host "  推荐组合包全部为需人工确认的步骤，向导不代为执行。" -ForegroundColor Yellow
        Write-Host "  请改用菜单 [16] 逐个确认。" -ForegroundColor Yellow
        Read-Host "按回车键返回主菜单"
        return
    }

    # --- 确认后执行；默认不传 -Force，高危步骤自动跳过 ---
    $confirm = Read-Host "  确认按上述方案优化？(Y/N)"
    if ($confirm -ne "Y" -and $confirm -ne "y") {
        Write-Host "  已取消。" -ForegroundColor Gray
        Read-Host "按回车键返回主菜单"
        return
    }

    Write-Host ""
    Write-Host "  正在执行（每步执行前自动备份，可在 [R] 恢复）..." -ForegroundColor Yellow
    $runArgs = @{ Name = $guidedPreview.profile.name; BackupDir = $script:BackupDir }
    $runResult = Invoke-Profile @runArgs

    Write-Host ""
    foreach ($r in @($runResult.results)) {
        $mark  = if ($r.ok) { '[成功]' } else { '[失败]' }
        $color = if ($r.ok) { 'Green' } else { 'Red' }
        Write-Host ("  {0} {1} - {2}" -f $mark, $r.domain, $r.action) -ForegroundColor $color
        if ($r.summary) { Write-Host "        $($r.summary)" -ForegroundColor DarkGray }
        if ($r.backup)  { Write-Host "        备份: $(Split-Path -Leaf $r.backup)" -ForegroundColor DarkGray }
        if ($r.error)   { Write-Host "        错误: $($r.error)" -ForegroundColor Red }
    }
    foreach ($s in @($runResult.skipped)) {
        Write-Host ("  [跳过] {0} - {1}（{2}）" -f $s.domain, $s.action, $s.reason) -ForegroundColor Gray
    }
    if ($runResult.restorePoint) {
        if ($runResult.restorePoint.ok) {
            Write-Host "  [还原点] 已创建: $($runResult.restorePoint.name)" -ForegroundColor Green
        } else {
            Write-Host "  [还原点] 创建失败，继续执行: $($runResult.restorePoint.error)" -ForegroundColor Yellow
        }
    }
    if ($runResult.error) { Write-Host "  $($runResult.error)" -ForegroundColor Yellow }
    $okCount = @($runResult.results | Where-Object { $_.ok }).Count
    Write-Log ("一键向导执行完成（组合包 {0}），成功 {1} 步，跳过 {2} 步" -f $guidedPreview.profile.name, $okCount, @($runResult.skipped).Count) "SUCCESS"

    # --- 自动复检并给出前后对比 ---
    Write-Host ""
    Write-Host "  正在复检..." -ForegroundColor DarkGray
    $afterReport = $null
    try { $afterReport = Get-SystemHealthReport } catch { $afterReport = $null }

    if ($afterReport) {
        $cmp = Compare-HealthReports -Before $guidedPreview.report -After $afterReport
        Write-Host ""
        Write-Host "================================================" -ForegroundColor Cyan
        Write-Host "  优化前后对比" -ForegroundColor Cyan
        Write-Host "================================================" -ForegroundColor Cyan
        if ($cmp) {
            Write-Host ("  优化前: {0} 分  ->  优化后: {1} 分" -f $cmp.beforeScore, $cmp.afterScore) -ForegroundColor Gray
            $sign = if ($cmp.scoreDelta -gt 0) { "+$($cmp.scoreDelta)" } else { "$($cmp.scoreDelta)" }
            $dc   = if ($cmp.scoreDelta -gt 0) { 'Green' } elseif ($cmp.scoreDelta -lt 0) { 'Red' } else { 'Gray' }
            Write-Host ("  分数变化: {0}" -f $sign) -ForegroundColor $dc
            if (@($cmp.resolved).Count -gt 0) {
                Write-Host "  已解决:" -ForegroundColor Green
                foreach ($i in $cmp.resolved) { Write-Host ("    + {0}" -f $i.title) -ForegroundColor Green }
            }
            if (@($cmp.new).Count -gt 0) {
                Write-Host "  新增问题:" -ForegroundColor Red
                foreach ($i in $cmp.new) { Write-Host ("    - {0}" -f $i.title) -ForegroundColor Red }
            }
            if (@($cmp.resolved).Count -eq 0 -and @($cmp.new).Count -eq 0) {
                Write-Host "  问题清单无变化。" -ForegroundColor Gray
            }
        }
        try { $null = Save-HealthReport -Report $afterReport -BackupDir $script:BackupDir } catch { }
    } else {
        Write-Host "  复检失败，可稍后到菜单 [15] 手动查看结果。" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  向导完成！建议重启电脑使所有更改生效；如需回滚请用菜单 [R]。" -ForegroundColor Green
    Read-Host "按回车键返回主菜单"
}

function Invoke-FullOptimization {
    Write-Log "开始一键全面优化..." "WARN"
    Write-Host ""
    Write-Host "即将执行所有优化操作，这可能需要几分钟时间。" -ForegroundColor Yellow
    Write-Host "建议先执行备份 [B] 以便后续恢复。" -ForegroundColor Yellow
    $confirm = Read-Host "确认执行全面优化？(Y/N)"
    if ($confirm -ne "Y" -and $confirm -ne "y") {
        Write-Host "已取消。" -ForegroundColor Gray
        Read-Host "按回车键返回主菜单"
        return
    }

    $modules = @(
        "02-CleanTemp.ps1",
        "03-DisableServices.ps1",
        "04-StartupOptimize.ps1",
        "05-VisualEffects.ps1",
        "06-PowerPlan.ps1",
        "07-DiskOptimize.ps1",
        "08-NetworkOptimize.ps1",
        "10-BlockWin1124H2.ps1"
    )

    $total = $modules.Count
    $current = 0
    $failed = @()
    foreach ($mod in $modules) {
        $current++
        Write-Host ""
        Write-Host "[$current/$total] " -NoNewline -ForegroundColor Yellow
        $ok = Invoke-ScriptModule $mod -NoPause
        if (-not $ok) { $failed += $mod }
    }

    Write-Host ""
    if ($failed.Count -gt 0) {
        Write-Log ("一键全面优化完成，但有 {0} 个模块执行失败: {1}" -f $failed.Count, ($failed -join ', ')) "WARN"
        Write-Host ("以下模块执行失败: " + ($failed -join ', ')) -ForegroundColor Red
        Write-Host "失败详情见 optimize.log" -ForegroundColor Yellow
    } else {
        Write-Log "一键全面优化完成！建议重启电脑使所有更改生效。" "SUCCESS"
    }
    Read-Host "按回车键返回主菜单"
}

# ============================================================
#  入口
# ============================================================

# -GuidedPlan 是只读预览，不需要管理员权限；输出后直接退出
if ($GuidedPlan) {
    $guidedPreview = Get-GuidedPlan -SkipCleanScan:$SkipCleanScan
    if (-not $guidedPreview.ok) { Write-Host "预览失败: $($guidedPreview.error)" -ForegroundColor Red; exit 1 }
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  一键向导预览（只读，不执行任何修改）" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Show-GuidedPlanPreview -Preview $guidedPreview
    exit 0
}

# -Plan 是只读预览，不需要管理员权限；输出后直接退出
if ($Plan) {
    $planArgs = @{}
    if ($Profile)       { $planArgs['ProfileName']   = $Profile }
    if ($SkipCleanScan) { $planArgs['SkipCleanScan'] = $true }
    # 同 Show-OptimizePlanPreview：不能把返回值赋给 $plan（与 [switch]$Plan 同名同型）
    $planPreview = Get-OptimizePlan @planArgs
    if (-not $planPreview.ok) { Write-Host "预览失败: $($planPreview.error)" -ForegroundColor Red; exit 1 }
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  优化预览（只读，不执行任何修改）" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ("  共 {0} 步（低危 {1} / 中危 {2} / 高危 {3}）；电源目标 {4}，DNS {5}" -f `
        $planPreview.summary.total, $planPreview.summary.low, $planPreview.summary.medium, $planPreview.summary.high, `
        $planPreview.powerPlan, $planPreview.dns) -ForegroundColor Gray
    foreach ($line in @(Format-OptimizePlan $planPreview)) { Write-Host $line -ForegroundColor DarkGray }
    exit 0
}

if (-not (Test-Administrator)) {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Red
    Write-Host "  错误：请以管理员身份运行此脚本！" -ForegroundColor Red
    Write-Host "  右键 PowerShell -> 以管理员身份运行" -ForegroundColor Red
    Write-Host "  然后执行: cd $ProjectRoot; .\Optimize.ps1" -ForegroundColor Red
    Write-Host "================================================" -ForegroundColor Red
    Write-Host ""
    Read-Host "按回车键退出"
    exit 1
}

# 日志轮转：超过 5MB 归档为 .old，避免无限增长
if (Test-Path $script:LogFile) {
    try {
        if ((Get-Item $script:LogFile).Length -gt 5MB) {
            $arc = Join-Path $script:ProjectRoot ("optimize.log." + (Get-Date -Format 'yyyyMMddHHmmss') + ".old")
            Move-Item $script:LogFile $arc -Force
        }
    } catch {}
}
Write-Log "===== PC-Optimizer-7thGen v$Version 启动 ====="
if ($Guided) { Invoke-GuidedOptimization } else { Show-Menu }
Write-Log "===== 程序退出 ====="

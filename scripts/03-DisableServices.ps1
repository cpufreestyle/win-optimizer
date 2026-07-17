<#
.SYNOPSIS
    服务优化模块 — 禁用不必要的后台服务以释放系统资源
.DESCRIPTION
    针对 7代及更老 CPU 的低配电脑，禁用以下非必要服务：
    - 诊断服务 (DiagTrack, dmwappushservice)
    - Xbox 相关服务
    - Windows 搜索索引（可选，SSD 可保留）
    - 打印后台处理程序（无打印机时）
    - 传真服务
    - 远程注册表
    - 传感器服务
    - OneDrive 同步服务
    所有更改会记录到备份文件，可随时恢复。
#>

. "$PSScriptRoot\Common.ps1"
Show-ModuleBanner "服务优化"

# 服务列表与计划任务统一从配置文件读取（单一数据源，避免与 config 重复维护）
# 安全禁用 = 对日常使用几乎无影响
# 建议禁用 = 大多数用户不需要，但某些场景可能用到
$config = Get-OptimizationConfig -ConfigPath (Join-Path $PSScriptRoot "..\config\optimization.json")
if (-not $config) {
    Write-Host "============================================" -ForegroundColor Cyan
    return
}

$servicesToDisable = @()
foreach ($s in $config.services.safe_to_disable) {
    $servicesToDisable += [PSCustomObject]@{Name = $s.name; Desc = $s.desc; Level = "安全禁用"}
}
foreach ($s in $config.services.recommended_to_disable) {
    $servicesToDisable += [PSCustomObject]@{Name = $s.name; Desc = $s.desc; Level = "建议禁用"}
}

# 备份当前服务状态
$backupFile = Join-Path $PSScriptRoot "..\backups\services_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$backupFile = [System.IO.Path]::GetFullPath($backupFile)

Write-Host "`n[1/3] 备份当前服务状态..." -ForegroundColor Yellow
$backupData = @()
foreach ($svc in $servicesToDisable) {
    $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
    if ($service) {
        $startMode = (Get-CimInstance Win32_Service -Filter "Name='$($svc.Name)'").StartMode
        $backupData += [PSCustomObject]@{
            Name      = $svc.Name
            Status    = $service.Status
            StartType = $startMode
            Date      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    }
}
$backupData | Export-Csv -Path $backupFile -NoTypeInformation -Encoding UTF8
Write-Host "  备份已保存: $backupFile" -ForegroundColor Green

# 显示服务列表并让用户确认
Write-Host "`n[2/3] 以下服务将被禁用:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  $('服务名'.PadRight(28)) $('级别'.PadRight(10)) 描述" -ForegroundColor DarkGray
Write-Host "  $('-' * 75)" -ForegroundColor DarkGray
foreach ($svc in $servicesToDisable) {
    $levelColor = if ($svc.Level -eq "安全禁用") { "Green" } else { "Yellow" }
    $exists = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
    if ($exists) {
        Write-Host "  $($svc.Name.PadRight(28)) " -NoNewline
        Write-Host "$($svc.Level.PadRight(10)) " -NoNewline -ForegroundColor $levelColor
        Write-Host "$($svc.Desc)"
    } else {
        Write-Host "  $($svc.Name.PadRight(28)) " -NoNewline
        Write-Host "未安装      " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($svc.Desc)" -ForegroundColor DarkGray
    }
}

Write-Host ""
$confirm = Read-Host "确认禁用以上服务？(Y=全部禁用 / S=仅安全禁用 / N=取消)"

$toProcess = switch ($confirm) {
    { $_ -eq "Y" -or $_ -eq "y" } { $servicesToDisable }
    { $_ -eq "S" -or $_ -eq "s" } { $servicesToDisable | Where-Object { $_.Level -eq "安全禁用" } }
    default { @() }
}

if ($toProcess.Count -eq 0) {
    Write-Host "  操作已取消。" -ForegroundColor Gray
    Write-Host "============================================" -ForegroundColor Cyan
    return
}

# 执行禁用
Write-Host "`n[3/3] 正在禁用服务..." -ForegroundColor Yellow
$disabledCount = 0
$skippedCount = 0

foreach ($svc in $toProcess) {
    $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Host "  [跳过] $($svc.Name) — 服务不存在" -ForegroundColor Gray
        $skippedCount++
        continue
    }

    try {
        # 先停止服务
        if ($service.Status -eq "Running") {
            Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
        }
        # 设置为禁用
        Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction Stop
        Write-Host "  [已禁用] $($svc.Name) — $($svc.Desc)" -ForegroundColor Green
        $disabledCount++
    } catch {
        Write-Host "  [失败] $($svc.Name) — $($_.Exception.Message)" -ForegroundColor Red
        $skippedCount++
    }
}

# 额外：禁用遥测相关计划任务
Write-Host "`n[额外] 禁用遥测相关计划任务..." -ForegroundColor Yellow
$telemetryTasks = @($config.telemetry_tasks)
foreach ($task in $telemetryTasks) {
    try {
        $t = Get-ScheduledTask -TaskPath ($task | Split-Path) -TaskName ($task | Split-Path -Leaf) -ErrorAction SilentlyContinue
        if ($t -and $t.State -ne "Disabled") {
            Disable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop | Out-Null
            Write-Host "  [已禁用] 计划任务: $($t.TaskName)" -ForegroundColor Green
        }
    } catch {
        Write-Host "  [跳过] 计划任务: $($task | Split-Path -Leaf)" -ForegroundColor Gray
    }
}

Write-Host ""
Show-ModuleFooter "服务优化完成！" -Lines @(
    "已禁用: $disabledCount 个服务"
    "已跳过: $skippedCount 个服务"
    "备份文件: $backupFile"
    "如需恢复，请使用 [B] 备份恢复功能"
)

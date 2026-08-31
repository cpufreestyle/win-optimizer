<#
.SYNOPSIS
    PC-Optimizer 共享核心逻辑库 (lib/Optimize.Core.ps1)
.DESCRIPTION
    本文件抽取了 CLI(scripts/)、WebUI(webui/ps/)、GUI(OptimizeGUI.ps1) 三套实现中
    重复的服务优化逻辑，作为单一数据源与纯逻辑函数集合。
    - 不依赖任何 UI (WinForms / Web)
    - 不调用 Read-Host，纯函数式，返回结构化数据
    - CLI/Web 通过 dot-source 复用；GUI 通过 Build-EXE 拼接进 EXE 复用
.NOTES
    Level 字段统一约定: "安全禁用" / "建议禁用"
#>

# 定位仓库 config 目录（lib 位于 <root>/lib，config 位于 <root>/config）
function Get-OptConfigPath {
    # $PSCommandPath 在 dot-source 时指向 lib 文件自身，比 $MyInvocation.MyCommand.Path 更可靠
    $scriptFile = $PSCommandPath
    if (-not $scriptFile) { $scriptFile = $MyInvocation.MyCommand.Path }
    if (-not $scriptFile) { return $null }
    $libDir = Split-Path -Parent $scriptFile
    $root = Split-Path -Parent $libDir
    return Join-Path $root "config\optimization.json"
}

# 读取配置文件；失败时返回 $null
function Get-OptConfig {
    $p = Get-OptConfigPath
    if (-not (Test-Path $p)) { return $null }
    try {
        return (Get-Content -Path $p -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        Write-Warning ("配置文件解析失败: " + $_.Exception.Message)
        return $null
    }
}

# 返回可禁用服务列表: @( @{Name; Desc; Level} )
# Level 统一为 "安全禁用" / "建议禁用"
function Get-ServiceList {
    $cfg = Get-OptConfig
    if ($cfg -and $cfg.services) {
        $list = @()
        foreach ($it in $cfg.services.safe_to_disable) {
            $list += @{Name=$it.name; Desc=$it.desc; Level="安全禁用"}
        }
        foreach ($it in $cfg.services.recommended_to_disable) {
            $list += @{Name=$it.name; Desc=$it.desc; Level="建议禁用"}
        }
        if ($list.Count -gt 0) { return $list }
    }
    # 内置回退（保证离线可用）
    return @(
        @{Name="DiagTrack";           Desc="诊断跟踪服务（遥测数据收集）";       Level="安全禁用"}
        @{Name="dmwappushservice";    Desc="设备管理 WAP 推送消息路由服务";      Level="安全禁用"}
        @{Name="WerSvc";              Desc="Windows 错误报告服务";               Level="安全禁用"}
        @{Name="XblAuthManager";      Desc="Xbox Live 身份验证管理器";           Level="安全禁用"}
        @{Name="XblGameSave";         Desc="Xbox Live 游戏保存";                 Level="安全禁用"}
        @{Name="XboxGipSvc";          Desc="Xbox 附件管理服务";                  Level="安全禁用"}
        @{Name="XboxNetApiSvc";       Desc="Xbox Live 网络服务";                 Level="安全禁用"}
        @{Name="Fax";                 Desc="传真服务";                           Level="安全禁用"}
        @{Name="RemoteRegistry";      Desc="远程注册表服务";                     Level="安全禁用"}
        @{Name="RetailDemo";          Desc="零售演示服务";                       Level="安全禁用"}
        @{Name="SensorService";       Desc="传感器服务";                         Level="建议禁用"}
        @{Name="SensrSvc";            Desc="传感器监控服务";                     Level="建议禁用"}
        @{Name="WMPNetworkSvc";       Desc="WMP 网络共享服务";                   Level="建议禁用"}
        @{Name="HvHost";              Desc="HV 主机服务（虚拟化）";              Level="建议禁用"}
        @{Name="vmickvpexchange";     Desc="Hyper-V 数据交换服务";               Level="建议禁用"}
        @{Name="vmicguestinterface";   Desc="Hyper-V 来宾接口服务";               Level="建议禁用"}
        @{Name="vmicshutdown";        Desc="Hyper-V 关机服务";                   Level="建议禁用"}
        @{Name="vmicheartbeat";       Desc="Hyper-V 心跳服务";                   Level="建议禁用"}
        @{Name="vmicvmsession";       Desc="Hyper-V PowerShell 直接服务";        Level="建议禁用"}
        @{Name="vmicrdv";             Desc="Hyper-V 远程桌面虚拟化服务";         Level="建议禁用"}
        @{Name="vmictimesync";        Desc="Hyper-V 时间同步服务";               Level="建议禁用"}
    )
}

# 返回遥测计划任务路径数组
function Get-TelemetryTasks {
    $cfg = Get-OptConfig
    if ($cfg -and $cfg.telemetry_tasks -and $cfg.telemetry_tasks.Count -gt 0) {
        return @($cfg.telemetry_tasks)
    }
    return @(
        "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
        "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
        "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
        "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
        "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector"
    )
}

# 获取服务当前启动类型
function Get-ServiceStartType {
    param([string]$n)
    try {
        $s = Get-CimInstance Win32_Service -Filter "Name='$n'" -ErrorAction SilentlyContinue
        if ($s) { return $s.StartMode } else { return "不存在" }
    } catch { return "未知" }
}

# 备份服务状态到 CSV，返回备份文件路径
function Backup-ServiceStates {
    param([string]$BackupDir, [array]$Services)
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupFile = Join-Path $BackupDir "services_backup_$ts.csv"
    $rows = @()
    foreach ($svc in $Services) {
        $rows += [PSCustomObject]@{
            Name      = $svc.Name
            StartType = Get-ServiceStartType $svc.Name
            Date      = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        }
    }
    $rows | Export-Csv -Path $backupFile -NoTypeInformation -Encoding UTF8
    return $backupFile
}

# 禁用服务
# 参数: Services(过滤后的列表), Mode("all"|"safe")
# 返回: @{ disabled; skipped; details: @(@{name; result}) }
function Disable-Services {
    param([array]$Services, [string]$Mode = "all")
    $toProcess = if ($Mode -eq "all") { $Services }
                 else { $Services | Where-Object { $_.Level -eq "安全禁用" } }
    $disabled = 0; $skipped = 0; $details = @()
    foreach ($svc in $toProcess) {
        $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if (-not $service) { $skipped++; continue }
        try {
            if ($service.Status -eq "Running") {
                Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 300
            }
            Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction Stop
            $disabled++
            $details += @{name = $svc.Name; result = "已禁用"}
        } catch {
            $skipped++
            $details += @{name = $svc.Name; result = "失败: $($_.Exception.Message)"}
        }
    }
    return @{ disabled = $disabled; skipped = $skipped; details = $details }
}

# 从最近备份 CSV 恢复服务状态
# 参数: BackupDir
# 返回: @{ restored; backup; details: @(@{name; result}) }
function Restore-Services {
    param([string]$BackupDir)
    $csv = Get-ChildItem -Path $BackupDir -Filter "services_backup_*.csv" -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $csv) { return @{restored = 0; backup = $null; details = @(); error = "未找到服务备份"} }
    $rows = Import-Csv $csv.FullName -ErrorAction Stop
    $restored = 0; $details = @()
    foreach ($r in $rows) {
        try {
            if ($r.StartType -and $r.StartType -ne "不存在") {
                Set-Service -Name $r.Name -StartupType $r.StartType -ErrorAction Stop
                $restored++
                $details += @{name = $r.Name; result = "已恢复为 $($r.StartType)"}
            }
        } catch {
            $details += @{name = $r.Name; result = "失败: $($_.Exception.Message)"}
        }
    }
    return @{restored = $restored; backup = $csv.FullName; details = $details; error = $null}
}

# ============================================================
#  通用工具函数（CLI / GUI / WebUI 三端共享的单一实现）
# ============================================================

# 计算文件夹大小（字节）。
# 已做空路径防御：Test-Path / Get-ChildItem 的 -Path 参数不允许空值，
# 否则会抛 "无法将参数绑定到参数 Path，因为该参数是空值"。
function Get-FolderSize {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return 0 }
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return 0 }
        $size = (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($null -eq $size) { return 0 }
        return [double]$size
    } catch { return 0 }
}

# 恢复 Windows 自动更新（撤销手动更新模式 / 更新屏蔽）
# 不依赖 UI，返回 @{ok; details: @(字符串); error}
# 调用方（CLI 弹 MessageBox、WebUI 输出 JSON）自行决定呈现方式
function Restore-AutoUpdate {
    $details = @()
    try {
        # 1. 恢复 Windows Update 服务为自动并启动
        $svc = Get-Service -Name wuauserv -ErrorAction Stop
        if ($svc.StartType -ne 'Automatic') {
            Set-Service -Name wuauserv -StartupType Automatic -ErrorAction Stop
            $details += "已将 wuauserv 启动类型设为 自动"
        } else {
            $details += "wuauserv 已经是 自动 启动"
        }
        if ($svc.Status -ne 'Running') {
            Start-Service -Name wuauserv -ErrorAction Stop
            $details += "已启动 wuauserv 服务"
        } else {
            $details += "wuauserv 服务正在运行"
        }

        # 2. 重新启用与 Windows Update 相关的计划任务
        $tasks = @(
            "\Microsoft\Windows\WindowsUpdate\Scheduled Start",
            "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan",
            "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan Static Task",
            "\Microsoft\Windows\UpdateOrchestrator\USO_UxBroker"
        )
        foreach ($task in $tasks) {
            try {
                $t = Get-ScheduledTask -TaskName $task -ErrorAction Stop
                if ($t.State -eq 'Disabled') {
                    Enable-ScheduledTask -TaskName $task -ErrorAction Stop | Out-Null
                    $details += "已启用计划任务: $task"
                } else {
                    $details += "计划任务已启用: $task"
                }
            } catch {
                $details += "计划任务 $task 不存在或无法启用（已跳过）"
            }
        }

        # 3. 删除手动更新模式留下的 AUOptions 限制
        $auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        if (Test-Path $auPath) {
            $auOpt = Get-ItemProperty -Path $auPath -Name AUOptions -ErrorAction SilentlyContinue
            if ($auOpt -and ($auOpt.AUOptions -eq 2 -or $auOpt.AUOptions -eq 3)) {
                Remove-ItemProperty -Path $auPath -Name AUOptions -Force -ErrorAction SilentlyContinue
                $details += "已删除 AUOptions 限制，恢复自动安装"
            }
        }

        return @{ok = $true; details = $details; error = $null}
    } catch {
        return @{ok = $false; details = $details; error = $_.Exception.Message}
    }
}

# 删除文件夹内的所有内容（保留文件夹本身），返回成功删除的条目数
function Remove-FolderContent {
    param([string]$Path)
    $cnt = 0
    if ([string]::IsNullOrWhiteSpace($Path)) { return $cnt }
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $cnt }
        Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue; $cnt++ } catch {}
        }
    } catch {}
    return $cnt
}

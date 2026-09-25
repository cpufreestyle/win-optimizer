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
# 会话内缓存：避免循环/多次调用时反复读盘+解析 JSON
$script:_optConfigCache    = $null
$script:_optConfigCachePath = $null
function Get-OptConfig {
    $p = Get-OptConfigPath
    if (-not $p) { return $null }
    if ($script:_optConfigCache -and $script:_optConfigCachePath -eq $p -and (Test-Path $p)) {
        return $script:_optConfigCache
    }
    if (-not (Test-Path $p)) { return $null }
    try {
        $script:_optConfigCache    = (Get-Content -Path $p -Raw -Encoding UTF8 | ConvertFrom-Json)
        $script:_optConfigCachePath = $p
        return $script:_optConfigCache
    } catch {
        Write-Warning ("配置文件解析失败: " + $_.Exception.Message)
        return $null
    }
}

# 版本号单一来源：优先取 config/optimization.json 的 version，缺失时回退 3.1.0
function Get-OptVersion {
    $cfg = Get-OptConfig
    if ($cfg -and $cfg.version) { return [string]$cfg.version }
    return "3.1.0"
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

# ============================================================
#  遥测计划任务域（CLI / GUI / WebUI 三端共享的单一实现）
#  任务清单唯一来源：config/optimization.json -> telemetry_tasks
#  状态查询与启停自动适配：Win8+/PS3+ 用 ScheduledTasks 模块，Win7/PS2 回退 schtasks.exe
# ============================================================

# 查询单个计划任务状态（Win7 兼容）
# 返回: @{ exists=$bool; state=$string }（state 形如 Ready / Disabled / Running，无法解析时为 $null）
function Get-ScheduledTaskState {
    param([string]$TaskPath, [string]$TaskName)
    if ([string]::IsNullOrWhiteSpace($TaskName)) { return @{ exists = $false; state = $null } }
    $fullName = "$TaskPath$TaskName"
    if ($PSVersionTable.PSVersion.Major -ge 3 -and -not (Test-IsLegacyWindows)) {
        try {
            $t = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop
            if (-not $t) { return @{ exists = $false; state = $null } }
            return @{ exists = $true; state = "$($t.State)" }
        } catch {
            return @{ exists = $false; state = $null }
        }
    }
    # Win7 / PS2.0 回退：schtasks /Query（详细列表输出）
    try {
        $out = & schtasks /Query /TN $fullName /FO LIST /V 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $out) { return @{ exists = $false; state = $null } }
        $state = $null
        foreach ($line in $out) {
            if ("$line" -match 'Scheduled Task State:\s*([A-Za-z]+)') { $state = $Matches[1] }
        }
        return @{ exists = $true; state = $state }
    } catch {
        return @{ exists = $false; state = $null }
    }
}

# 启用/禁用单个计划任务（Win7 兼容），成功返回 $true
function Set-ScheduledTaskState {
    param([string]$TaskPath, [string]$TaskName, [bool]$Enable)
    if ([string]::IsNullOrWhiteSpace($TaskName)) { return $false }
    try {
        if ($PSVersionTable.PSVersion.Major -ge 3 -and -not (Test-IsLegacyWindows)) {
            if ($Enable) {
                Enable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null
            } else {
                Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null
            }
            return $true
        }
        # Win7 / PS2.0 回退：schtasks /Change
        $switchArg = if ($Enable) { '/ENABLE' } else { '/DISABLE' }
        & schtasks /Change /TN "$TaskPath$TaskName" $switchArg 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

# 列出全部遥测计划任务及当前状态（只读，供三端展示）
# 返回 @( @{name; taskPath; exists; state; disabled} )
function Get-TelemetryTaskStates {
    $result = @()
    foreach ($full in @(Get-TelemetryTasks)) {
        $leaf   = Split-Path $full -Leaf
        $parent = Split-Path $full -Parent
        if (-not $parent.EndsWith("\")) { $parent = "$parent\" }
        $st = Get-ScheduledTaskState -TaskPath $parent -TaskName $leaf
        $result += [PSCustomObject]@{
            name     = $leaf
            taskPath = $parent
            exists   = [bool]$st.exists
            state    = $st.state
            disabled = ("$($st.state)" -eq 'Disabled')
        }
    }
    return $result
}

# 备份遥测计划任务当前状态到 JSON，返回备份文件路径（与其它域备份同目录）
function Backup-TelemetryTaskStates {
    param([string]$BackupDir)
    if (-not $BackupDir) { $BackupDir = Get-OptBackupDir }
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
    $ts         = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupFile = Join-Path $BackupDir "telemetry_backup_$ts.json"
    $rows = @()
    foreach ($s in @(Get-TelemetryTaskStates)) {
        $rows += [PSCustomObject]@{ name = $s.name; taskPath = $s.taskPath; state = $s.state }
    }
    [PSCustomObject]@{
        date  = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        host  = $env:COMPUTERNAME
        tasks = $rows
    } | ConvertTo-Json -Depth 4 | Set-Content -Path $backupFile -Encoding UTF8
    Write-BackupManifest -BackupFile $backupFile -Domain 'telemetry' -ItemCount $rows.Count | Out-Null
    return $backupFile
}

# 禁用全部遥测计划任务（config 为唯一来源，Win7 自动回退 schtasks）
# 默认先备份当前状态；-WhatIf 只预览不改动
# 返回: @{ disabled; skipped; backup; details: @(@{name; result}); error=$null }
function Disable-TelemetryTasks {
    param([string]$BackupDir, [switch]$WhatIf, [switch]$SkipBackup)
    if (-not $BackupDir) { $BackupDir = Get-OptBackupDir }
    $details = @()
    $disabled = 0
    $skipped  = 0
    $backupFile = $null
    try {
        if (-not $SkipBackup -and -not $WhatIf) {
            $backupFile = Backup-TelemetryTaskStates -BackupDir $BackupDir
        }
        foreach ($s in @(Get-TelemetryTaskStates)) {
            if (-not $s.exists) {
                $skipped++
                $details += @{ name = $s.name; result = "不存在，已跳过" }
                continue
            }
            if ($s.disabled) {
                $skipped++
                $details += @{ name = $s.name; result = "已处于禁用，已跳过" }
                continue
            }
            if ($WhatIf) {
                $disabled++
                $details += @{ name = $s.name; result = "将禁用(预览)" }
                continue
            }
            if (Set-ScheduledTaskState -TaskPath $s.taskPath -TaskName $s.name -Enable $false) {
                $disabled++
                $details += @{ name = $s.name; result = "已禁用" }
            } else {
                $skipped++
                $details += @{ name = $s.name; result = "失败: 无法禁用计划任务" }
            }
        }
    } catch {
        return @{ disabled = $disabled; skipped = $skipped; backup = $backupFile; details = $details; error = $_.Exception.Message }
    }
    return @{ disabled = $disabled; skipped = $skipped; backup = $backupFile; details = $details; error = $null }
}

# 从最近一次遥测计划任务备份恢复（备份时未禁用的任务会被重新启用）
# 返回: @{ restored; backup; details: @(@{name; result}); error=$null }
function Restore-TelemetryTasks {
    param([string]$BackupDir, [string]$File)
    if (-not $BackupDir) { $BackupDir = Get-OptBackupDir }
    try {
        $target = $null
        if ($File) {
            $target = Get-Item -LiteralPath $File -ErrorAction SilentlyContinue
        } else {
            $target = Get-ChildItem -Path $BackupDir -Filter "telemetry_backup_*.json" -ErrorAction SilentlyContinue |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1
        }
        if (-not $target) { return @{ restored = 0; backup = $null; details = @(); error = "未找到遥测计划任务备份" } }
        $data = Get-Content -LiteralPath $target.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $restored = 0
        $details  = @()
        foreach ($t in @($data.tasks)) {
            if (-not $t) { continue }
            if ($null -eq $t.state) { continue }  # 备份时即不存在的任务，恢复时跳过
            if ("$($t.state)" -eq 'Disabled') {
                $details += @{ name = $t.name; result = "备份时即为禁用，保持禁用" }
                continue
            }
            if (Set-ScheduledTaskState -TaskPath $t.taskPath -TaskName $t.name -Enable $true) {
                $restored++
                $details += @{ name = $t.name; result = "已重新启用" }
            } else {
                $details += @{ name = $t.name; result = "失败: 无法启用计划任务" }
            }
        }
        return @{ restored = $restored; backup = $target.FullName; details = $details; error = $null }
    } catch {
        return @{ restored = 0; backup = $null; details = @(); error = $_.Exception.Message }
    }
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
    Write-BackupManifest -BackupFile $backupFile -Domain 'services' -ItemCount $rows.Count | Out-Null
    return $backupFile
}

# 禁用服务
# 参数: Services(过滤后的列表), Mode("all"|"safe")
# 返回: @{ disabled; skipped; details: @(@{name; result}) }
function Disable-Services {
    param([array]$Services, [string]$Mode = "all", [switch]$WhatIf)
    $toProcess = if ($Mode -eq "all") { $Services }
                 else { $Services | Where-Object { $_.Level -eq "安全禁用" } }
    $disabled = 0; $skipped = 0; $details = @()
    foreach ($svc in $toProcess) {
        $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if (-not $service) { $skipped++; continue }
        if ($WhatIf) {
            $disabled++
            $details += @{name = $svc.Name; result = "将禁用(预览)"}
            continue
        }
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

# 从备份 CSV 恢复服务状态。省略 File 时取最近一份 services_backup_*.csv
# 参数: BackupDir, File(可选，指定备份文件全路径)
# 返回: @{ restored; backup; details: @(@{name; result}) }
function Restore-Services {
    param([string]$BackupDir, [string]$File)
    $csv = $null
    if ($File) {
        $csv = Get-Item -LiteralPath $File -ErrorAction SilentlyContinue
    } else {
        $csv = Get-ChildItem -Path $BackupDir -Filter "services_backup_*.csv" -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }
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
        # -File：只枚举文件，避免把无 Length 的目录对象也送进 Measure-Object，减少遍历开销
        $size = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($null -eq $size) { return 0 }
        return [double]$size
    } catch { return 0 }
}

# 统一日志写入：文件追加 + 控制台彩色输出。
# 相比原先 CLI 每次 Add-Content（反复开关文件句柄），此处用 AppendAllText 单次写入，
# 高频调用时 IO 开销更低；三端共用同一份实现，避免日志格式漂移。
function Write-OptLog {
    param(
        [string]$Message,
        [string]$Level = 'INFO',
        [string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path (Split-Path -Parent $PSScriptRoot) 'optimize.log'
    }
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Message"
    try {
        [System.IO.File]::AppendAllText($Path, $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
    } catch { }
    switch ($Level) {
        'ERROR'   { Write-Host $line -ForegroundColor Red }
        'WARN'    { Write-Host $line -ForegroundColor Yellow }
        'SUCCESS' { Write-Host $line -ForegroundColor Green }
        default   { Write-Host $line -ForegroundColor Cyan }
    }
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
    param([string]$Path, [switch]$WhatIf)
    $cnt = 0
    if ([string]::IsNullOrWhiteSpace($Path)) { return $cnt }
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $cnt }
        Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            if ($WhatIf) { $cnt++; return }
            try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue; $cnt++ } catch {}
        }
    } catch {}
    return $cnt
}

# ============================================================
#  清理目标清单（CLI / WebUI 共享的单一数据源）
#  从 config/optimization.json 读取；缺失时用内置回退，保证离线可用。
#  路径中的 %VAR% 环境变量在返回前展开。
# ============================================================
function Get-CleanTargets {
    param([switch]$Web)
    $cfg = Get-OptConfig
    $items = $null
    if ($cfg -and $cfg.clean_targets -and $cfg.clean_targets.Count -gt 0) {
        $items = $cfg.clean_targets
    } else {
        $items = @(
            @{ key = 'temp';     name = 'Windows 系统临时文件'; path = 'C:\Windows\Temp';                                web = $true }
            @{ key = 'usertemp'; name = '用户临时文件';         path = '%TEMP%';                                          web = $true }
            @{ key = 'prefetch'; name = '预读取文件';           path = 'C:\Windows\Prefetch';                            web = $true }
            @{ key = 'wsus';     name = 'Windows Update 下载缓存'; path = 'C:\Windows\SoftwareDistribution\Download';    web = $true }
            @{ key = 'thumb';    name = '缩略图缓存';           path = '%LOCALAPPDATA%\Microsoft\Windows\Explorer';      web = $true }
            @{ key = 'wer';      name = 'Windows 错误报告';     path = '%PROGRAMDATA%\Microsoft\Windows\WER';            web = $true }
        )
    }
    $list = @()
    foreach ($it in $items) {
        if ($Web -and $it.web -ne $true) { continue }
        $list += [PSCustomObject]@{
            key  = $it.key
            name = $it.name
            path = [Environment]::ExpandEnvironmentVariables($it.path)
        }
    }
    return $list
}

# ============================================================
#  启动项（CLI / GUI / WebUI 三端统一实现）
# ============================================================
# 背景：此前三端各写一份，且备份 CSV 列名不一致
#   CLI   : Name,Value,Scope,Source,Path
#   GUI   : Name,Command,Scope,Source        （缺 Path）
#   WebUI : name,value,scope,source,path     （全小写）
# 导致 GUI / WebUI 产生的备份无法被 CLI 的恢复流程读取（真会丢备份）。
# 现统一为单一字段集与单一 CSV 列名：Name,Value,Scope,Source,Path

# 统一的备份目录：<root>/backups。显式传参优先，避免 PS2EXE 下 $PSScriptRoot 为空。
function Get-OptBackupDir {
    param([string]$BackupDir)
    if ($BackupDir) { return [System.IO.Path]::GetFullPath($BackupDir) }
    $cfgPath = Get-OptConfigPath
    if ($cfgPath) {
        # <root>/config/optimization.json -> <root>/backups
        return (Join-Path (Split-Path -Parent (Split-Path -Parent $cfgPath)) 'backups')
    }
    return (Join-Path (Get-Location).Path 'backups')
}

# 列出全部启动项：5 个注册表项 + 2 个启动文件夹 + WMI 系统启动命令（按名称去重）
# 返回 @( @{Index;Name;Value;Scope;Source;Path} )
function Get-StartupItems {
    $items = @()

    $regPaths = @(
        @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';                Scope='当前用户'}
        @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce';            Scope='当前用户'}
        @{Path='HKLM:\Software\Microsoft\Windows\CurrentVersion\Run';                Scope='所有用户'}
        @{Path='HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce';            Scope='所有用户'}
        @{Path='HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run';    Scope='所有用户(32位)'}
    )
    foreach ($reg in $regPaths) {
        if (-not (Test-Path $reg.Path)) { continue }
        $props = Get-ItemProperty -Path $reg.Path -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($prop in ($props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' -and $_.Value })) {
            $items += [PSCustomObject]@{
                Name   = $prop.Name
                Value  = $prop.Value
                Scope  = $reg.Scope
                Source = '注册表'
                Path   = $reg.Path
            }
        }
    }

    $folders = @(
        @{Path="$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup";     Scope='当前用户'}
        @{Path="$env:PROGRAMDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Scope='所有用户'}
    )
    foreach ($f in $folders) {
        if (-not (Test-Path $f.Path)) { continue }
        foreach ($child in (Get-ChildItem -Path $f.Path -ErrorAction SilentlyContinue)) {
            $items += [PSCustomObject]@{
                Name   = $child.Name
                Value  = $child.FullName
                Scope  = $f.Scope
                Source = '启动文件夹'
                Path   = $f.Path
            }
        }
    }

    try {
        $apps = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue
        foreach ($app in $apps) {
            if ($items.Count -gt 0 -and ($items.Name -contains $app.Name)) { continue }
            $items += [PSCustomObject]@{
                Name   = $app.Name
                Value  = $app.Command
                Scope  = $app.Location
                Source = '系统启动命令'
                Path   = $app.Location
            }
        }
    } catch { }

    # 统一编号
    $i = 0
    foreach ($it in $items) {
        $i++
        Add-Member -InputObject $it -NotePropertyName Index -NotePropertyValue $i -Force
    }
    return $items
}

# 解析选择器：'all' 或 '1,3,5'，返回选中的启动项数组
function Select-StartupItems {
    param([array]$Items, [string]$Selector)
    if (-not $Items -or $Items.Count -eq 0) { return @() }
    if ([string]::IsNullOrWhiteSpace($Selector)) { return @() }
    if ($Selector.Trim().ToLower() -eq 'all') { return $Items }
    $idxs = $Selector -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }
    $picked = @()
    foreach ($it in $Items) {
        if ($idxs -contains ([string]$it.Index)) { $picked += $it }
    }
    return $picked
}

# 备份启动项到 CSV（列名统一为 Name,Value,Scope,Source,Path），返回备份文件路径
function Backup-StartupItems {
    param([string]$BackupDir, [array]$Items)
    $dir = Get-OptBackupDir -BackupDir $BackupDir
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $file = Join-Path $dir ('startup_backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.csv')
    if ($Items -and $Items.Count -gt 0) {
        $Items | Select-Object Name, Value, Scope, Source, Path |
            Export-Csv -Path $file -NoTypeInformation -Encoding UTF8
    } else {
        # 空列表也写出表头，避免下游读取时因缺列而报错
        Set-Content -Path $file -Value 'Name,Value,Scope,Source,Path' -Encoding UTF8
    }
    Write-BackupManifest -BackupFile $file -Domain 'startup' -ItemCount @($Items).Count | Out-Null
    return $file
}

# 禁用启动项（先备份，再按来源禁用）。返回 @{disabled;failed;backup;details}
# -WhatIf 只做试算不改动系统，便于测试与预演
function Disable-StartupItems {
    param(
        [string]$BackupDir,
        [array]$Items,
        [switch]$SkipBackup,
        [switch]$WhatIf
    )
    $result = [PSCustomObject]@{
        disabled = 0
        failed   = 0
        backup   = $null
        details  = @()
    }
    if (-not $Items -or $Items.Count -eq 0) { return $result }

    # -WhatIf 同样不落盘：预览必须零副作用（与 Invoke-NetworkOptimization 等保持一致）
    if (-not $SkipBackup -and -not $WhatIf) {
        $result.backup = Backup-StartupItems -BackupDir $BackupDir -Items $Items
    }

    foreach ($item in $Items) {
        try {
            if ($item.Source -eq '注册表') {
                # 先确认键仍存在，避免对已删除项误报成功
                $key = Get-Item -Path $item.Path -ErrorAction SilentlyContinue
                if (-not $key) {
                    $result.failed++
                    $result.details += [PSCustomObject]@{ Name = $item.Name; Source = $item.Source; Result = '失败: 注册表键不存在' }
                    continue
                }
                if (-not $WhatIf) { Remove-ItemProperty -Path $item.Path -Name $item.Name -ErrorAction Stop }
                $result.disabled++
                $result.details += [PSCustomObject]@{ Name = $item.Name; Source = $item.Source; Result = '已禁用' }
            }
            elseif ($item.Source -eq '启动文件夹') {
                # 移动到备份目录而非直接删除，保证可恢复
                $dir = Get-OptBackupDir -BackupDir $BackupDir
                $moveDir = Join-Path $dir 'startup_items'
                # -WhatIf 同样不落盘：预览不得创建备份目录
                if (-not $WhatIf -and -not (Test-Path $moveDir)) { New-Item -ItemType Directory -Path $moveDir -Force | Out-Null }
                $dest = Join-Path $moveDir (Split-Path $item.Value -Leaf)
                if (-not $WhatIf) { Move-Item -Path $item.Value -Destination $dest -Force -ErrorAction Stop }
                $result.disabled++
                $result.details += [PSCustomObject]@{ Name = $item.Name; Source = $item.Source; Result = '已禁用(已备份文件)' }
            }
            else {
                $result.failed++
                $result.details += [PSCustomObject]@{ Name = $item.Name; Source = $item.Source; Result = '跳过: 需通过任务管理器手动禁用' }
            }
        } catch {
            $result.failed++
            $result.details += [PSCustomObject]@{ Name = $item.Name; Source = $item.Source; Result = ('失败: ' + $_.Exception.Message) }
        }
    }
    return $result
}

# ============================================================
#  视觉效果（CLI / GUI / WebUI 三端统一实现）
# ============================================================
# 背景：此前只有 CLI 会备份并写入完整设置；GUI / WebUI 既不备份，
# 也缺少 UserPreferencesMask / FontSmoothingType / MinAnimate /
# AlwaysHibernateThumbnails 与 HKLM 系统级设置，
# 导致其「最佳性能」名不副实且不可恢复。现统一到下列函数。

# 三端共用的模式清单
function Get-VisualEffectProfiles {
    return @(
        [PSCustomObject]@{ Value = 1; Title = '最佳性能'; Desc = '关闭所有动画和特效，仅保留字体平滑。适合老旧电脑，最大化响应速度。'; Safe = $true }
        [PSCustomObject]@{ Value = 2; Title = '平衡模式'; Desc = '关闭大部分动画，保留基本效果。适合日常使用。'; Safe = $true }
        [PSCustomObject]@{ Value = 3; Title = '自定义';   Desc = '逐项选择要关闭的效果，精细控制。'; Safe = $false }
    )
}

# 自定义模式可逐项选择的开关（供三端展示与传参）
function Get-VisualEffectToggles {
    $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $desktop = 'HKCU:\Control Panel\Desktop'
    return @(
        [PSCustomObject]@{ Key = 'taskbar';   Name = '禁用任务栏动画';     RegKey = $adv;                              RegValue = 'TaskbarAnimations';   RegData = 0;   RegType = 'DWord' }
        [PSCustomObject]@{ Key = 'listview';  Name = '禁用列表透明选择';   RegKey = $adv;                              RegValue = 'ListviewAlphaSelect'; RegData = 0;   RegType = 'DWord' }
        [PSCustomObject]@{ Key = 'dragfull';  Name = '禁用拖拽完整窗口';   RegKey = $desktop;                          RegValue = 'DragFullWindows';     RegData = '0'; RegType = 'String' }
        [PSCustomObject]@{ Key = 'minanim';   Name = '禁用窗口最小化动画'; RegKey = 'HKCU:\Control Panel\Desktop\WindowMetrics'; RegValue = 'MinAnimate'; RegData = '0'; RegType = 'String' }
        [PSCustomObject]@{ Key = 'aeropeek';  Name = '禁用 Aero Peek';     RegKey = 'HKCU:\Software\Microsoft\Windows\DWM';   RegValue = 'EnableAeroPeek';    RegData = 0;   RegType = 'DWord' }
        [PSCustomObject]@{ Key = 'menudelay'; Name = '菜单延迟设为0';      RegKey = $desktop;                          RegValue = 'MenuShowDelay';       RegData = '0'; RegType = 'String' }
    )
}

# 当前 VisualFXSetting（0=让Windows选择 / 1=最佳外观 / 2=自定义平衡 / 3=自定义）
function Get-VisualEffectState {
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
    try {
        if (Test-Path $key) {
            $v = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).VisualFXSetting
            if ($null -ne $v) { return [int]$v }
        }
    } catch { }
    return $null
}

# 备份视觉效果相关注册表键到 JSON，返回备份文件路径
function Backup-VisualEffects {
    param([string]$BackupDir)
    $dir = Get-OptBackupDir -BackupDir $BackupDir
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $file = Join-Path $dir ('visual_backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.json')

    $keys = [ordered]@{
        VisualEffects = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
        DWM           = 'HKCU:\Software\Microsoft\Windows\DWM'
        Advanced      = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        Desktop       = 'HKCU:\Control Panel\Desktop'
    }
    $backup = @{}
    foreach ($k in $keys.Keys) {
        $path = $keys[$k]
        if (Test-Path $path) {
            $backup[$k] = (Get-ItemProperty -Path $path -ErrorAction SilentlyContinue)
        }
    }
    try {
        ($backup | ConvertTo-Json -Depth 3) | Set-Content -Path $file -Encoding UTF8
    } catch { }
    Write-BackupManifest -BackupFile $file -Domain 'visual' -ItemCount $backup.Keys.Count | Out-Null
    return $file
}

# 写入单个注册表值（内部辅助：自动建键、按类型写入、吞掉可忽略错误）
function Set-VisualRegValue {
    param($RegKey, $RegValue, $RegData, $RegType = 'DWord', [switch]$WhatIf)
    if ($WhatIf) { return $true }
    try {
        if (-not (Test-Path $RegKey)) { New-Item -Path $RegKey -Force | Out-Null }
        Set-ItemProperty -Path $RegKey -Name $RegValue -Value $RegData -Type $RegType -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# 应用视觉效果方案。
# -Profile 1=最佳性能 / 2=平衡 / 3=自定义（配合 -Toggles）
# -BackupDir 传入则先备份（强烈建议三端都传，否则不可恢复）
# 返回 @{ ok; profile; backup; details = @() }
function Set-VisualEffectProfile {
    param(
        [ValidateSet(1, 2, 3)][int]$Profile,
        [string[]]$Toggles,
        [string]$BackupDir,
        [switch]$SkipExplorerRestart,
        [switch]$WhatIf
    )
    $res = [PSCustomObject]@{
        ok      = $true
        profile = $Profile
        backup  = $null
        details = @()
    }

    # -WhatIf 时同样不落盘：预览必须零副作用（与 Disable-TelemetryTasks 保持一致）
    if ($BackupDir -and -not $WhatIf) { $res.backup = Backup-VisualEffects -BackupDir $BackupDir }

    $visualKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
    $perfKey   = 'HKCU:\Control Panel\Desktop'
    $advKey    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $dwmKey    = 'HKCU:\Software\Microsoft\Windows\DWM'
    $minKey    = 'HKCU:\Control Panel\Desktop\WindowMetrics'

    # 始终用「自定义(3)」承载我们的细项设置
    if (-not (Set-VisualRegValue $visualKey 'VisualFXSetting' 3 'DWord' -WhatIf:$WhatIf)) {
        $res.details += 'VisualFXSetting 写入失败'
        $res.ok = $false
    }

    if ($Profile -eq 1) {
        # 最佳性能：完整写入（含 GUI/WebUI 此前缺失的项）
        Set-VisualRegValue $perfKey 'DragFullWindows'     '0' 'String' -WhatIf:$WhatIf | Out-Null
        Set-VisualRegValue $perfKey 'FontSmoothing'       '2' 'String' -WhatIf:$WhatIf | Out-Null
        Set-VisualRegValue $perfKey 'FontSmoothingType'   '2' 'String' -WhatIf:$WhatIf | Out-Null
        Set-VisualRegValue $perfKey 'MenuShowDelay'       '0' 'String' -WhatIf:$WhatIf | Out-Null
        # UserPreferencesMask 是「最佳性能」真正生效的关键掩码，此前 GUI/WebUI 未写入
        if (-not $WhatIf) {
            try {
                Set-ItemProperty -Path $perfKey -Name 'UserPreferencesMask' `
                    -Value ([byte[]](0x90, 0x12, 0x01, 0x80, 0x10, 0x00, 0x00, 0x00)) -ErrorAction Stop
            } catch { }
        }
        Set-VisualRegValue $advKey 'TaskbarAnimations'   0 'DWord' -WhatIf:$WhatIf | Out-Null
        Set-VisualRegValue $advKey 'ListviewAlphaSelect' 0 'DWord' -WhatIf:$WhatIf | Out-Null
        Set-VisualRegValue $minKey 'MinAnimate'          '0' 'String' -WhatIf:$WhatIf | Out-Null
        Set-VisualRegValue $dwmKey 'EnableAeroPeek'      0 'DWord' -WhatIf:$WhatIf | Out-Null
        Set-VisualRegValue $dwmKey 'AlwaysHibernateThumbnails' 0 'DWord' -WhatIf:$WhatIf | Out-Null
        # 系统级
        Set-VisualRegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' `
            'VisualFXSetting' 3 'DWord' -WhatIf:$WhatIf | Out-Null
        $res.details += '最佳性能'
    }
    elseif ($Profile -eq 2) {
        Set-VisualRegValue $perfKey 'DragFullWindows'    '1'   'String' -WhatIf:$WhatIf | Out-Null
        Set-VisualRegValue $perfKey 'FontSmoothing'      '2'   'String' -WhatIf:$WhatIf | Out-Null
        Set-VisualRegValue $perfKey 'MenuShowDelay'      '100' 'String' -WhatIf:$WhatIf | Out-Null
        Set-VisualRegValue $advKey  'TaskbarAnimations'   0 'DWord' -WhatIf:$WhatIf | Out-Null
        # 与 CLI 对齐：平衡模式同样关闭列表透明选择（此前 GUI/WebUI 漏掉）
        Set-VisualRegValue $advKey  'ListviewAlphaSelect' 0 'DWord' -WhatIf:$WhatIf | Out-Null
        Set-VisualRegValue $dwmKey  'EnableAeroPeek'      0 'DWord' -WhatIf:$WhatIf | Out-Null
        $res.details += '平衡模式'
    }
    else {
        $all = Get-VisualEffectToggles
        $picked = @()
        if ($Toggles -and $Toggles.Count -gt 0) {
            foreach ($t in $all) { if ($Toggles -contains $t.Key) { $picked += $t } }
        } else {
            # 未指定时保持向后兼容：仅关任务栏动画
            $picked = @($all | Where-Object { $_.Key -eq 'taskbar' })
        }
        foreach ($t in $picked) {
            Set-VisualRegValue $t.RegKey $t.RegValue $t.RegData $t.RegType -WhatIf:$WhatIf | Out-Null
            $res.details += $t.Name
        }
    }

    if (-not $SkipExplorerRestart) { Restart-Explorer -WhatIf:$WhatIf | Out-Null }
    return $res
}

# 重启资源管理器使视觉效果生效，返回是否成功
function Restart-Explorer {
    param([int]$DelaySeconds = 1, [switch]$WhatIf)
    if ($WhatIf) { return $true }
    try {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds $DelaySeconds
        Start-Process explorer
        return $true
    } catch {
        return $false
    }
}

# ============================================================
#  电源计划（CLI / GUI / WebUI 三端统一实现）
# ============================================================
# 背景：此前只有 CLI 会备份并处理「卓越性能解锁失败回退」，
# 也只有 CLI 会设置 DISKIDLE / WIRELESS_PWRSAV；GUI / WebUI 既无备份，
# 也不做回退，且只在高性能模式下设置 CPU 频率。现统一到下列函数。

# 三端共用的电源计划清单（GUID 为 Windows 内置计划固定值）
function Get-PowerPlanCatalog {
    return @(
        [PSCustomObject]@{ Value = 1; Title = '高性能模式';   Desc = '最大化 CPU 性能，CPU 始终保持最高频率。适合台式机或插电笔记本。'; GUID = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' }
        [PSCustomObject]@{ Value = 2; Title = '卓越性能模式'; Desc = '比高性能更高，需解锁后可用。极限性能优先。';                     GUID = 'e9a42b02-d5df-448d-aa00-03f14749eb61' }
        [PSCustomObject]@{ Value = 3; Title = '平衡优化模式'; Desc = '平衡基础上优化，禁用 USB 挂起。适合笔记本电池模式。';             GUID = '381b4222-f694-41f0-9685-ff5bb260df2e' }
    )
}

# 当前生效计划的 GUID
function Get-ActivePowerPlan {
    try {
        $out = @(powercfg /getactivescheme 2>&1) -join ' '
        if ($out -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
            return $matches[1]
        }
    } catch { }
    return $null
}

# 备份当前电源计划，返回备份文件路径
# 2026-09-23 起改为结构化 JSON：除 powercfg /query 全文外，额外记录
#   activeGuid / activeName —— 还原时靠 GUID 精确切回原计划；
#   旧版 .txt 备份只有纯文本，无法可靠解析活动方案，只能给手动提示。
function Backup-PowerPlan {
    param([string]$BackupDir)
    $dir = Get-OptBackupDir -BackupDir $BackupDir
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $file = Join-Path $dir ('power_backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.json')
    $activeGuid = Get-ActivePowerPlan
    $activeName = ''
    foreach ($p in @(Get-PowerPlanCatalog)) { if ($p.GUID -eq $activeGuid) { $activeName = $p.Title } }
    $query = ''
    try { $query = (@(& powercfg /query 2>&1) -join "`n") } catch { }
    try {
        [PSCustomObject]@{
            date       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            host       = $env:COMPUTERNAME
            activeGuid = $activeGuid
            activeName = $activeName
            query      = $query
        } | ConvertTo-Json -Depth 4 | Out-File -FilePath $file -Encoding UTF8
    } catch { }
    Write-BackupManifest -BackupFile $file -Domain 'power' -ItemCount 1 | Out-Null
    return $file
}

# 内部：调用 powercfg（-WhatIf 时不真正执行），返回合并输出文本
function Invoke-PowerCfg {
    param([string[]]$CfgArgs, [switch]$WhatIf)
    if ($WhatIf) { return '' }
    try { return (@(& powercfg @CfgArgs 2>&1) -join "`n") } catch { return '' }
}

# 应用电源方案。所有「改不改」的项用哨兵值表示不改：
#   MinPercent/MaxPercent/DiskIdleSeconds = -1 表示不改
# 返回 @{ ok; guid; appliedGuid; backup; fallback; details = @() }
function Set-PowerPlan {
    param(
        [string]$Guid,
        [int]$MinPercent = -1,
        [int]$MaxPercent = -1,
        [bool]$UsbSuspendOff = $false,
        [bool]$PciAspmOff = $false,
        [int]$DiskIdleSeconds = -1,
        [bool]$WirelessMaxPerf = $false,
        [string]$BackupDir,
        [switch]$UnlockUltimate,
        [switch]$FallbackToHighPerf,
        [switch]$SkipBackup,
        [switch]$WhatIf
    )
    $res = [PSCustomObject]@{
        ok          = $true
        guid        = $Guid
        appliedGuid = $Guid
        backup      = $null
        fallback    = $false
        details     = @()
    }
    $highPerf = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'

    if ($BackupDir -and -not $SkipBackup -and -not $WhatIf) { $res.backup = Backup-PowerPlan -BackupDir $BackupDir }

    # 卓越性能需先解锁；解锁失败时可回退高性能
    if ($UnlockUltimate) {
        Invoke-PowerCfg @(' /duplicatescheme'.Trim(), $Guid) -WhatIf:$WhatIf | Out-Null
        $listed = if ($WhatIf) { $true } else {
            (@(Invoke-PowerCfg @('/list') -WhatIf:$WhatIf) -join "`n") -match [regex]::Escape($Guid)
        }
        if (-not $listed -and $FallbackToHighPerf) {
            $res.fallback    = $true
            $res.appliedGuid = $highPerf
            $res.details    += '卓越性能解锁失败，已回退高性能计划'
            $Guid = $highPerf
        }
    }

    Invoke-PowerCfg @('/setactive', $Guid) -WhatIf:$WhatIf | Out-Null

    if ($MinPercent -ge 0) { Invoke-PowerCfg @('/setacvalueindex', $Guid, 'SUB_PROCESSOR', 'PROCTHROTTLEMIN', [string]$MinPercent) -WhatIf:$WhatIf | Out-Null }
    if ($MaxPercent -ge 0) { Invoke-PowerCfg @('/setacvalueindex', $Guid, 'SUB_PROCESSOR', 'PROCTHROTTLEMAX', [string]$MaxPercent) -WhatIf:$WhatIf | Out-Null }
    if ($MinPercent -ge 0 -or $MaxPercent -ge 0) { $res.details += ("CPU 处理器状态: 最低 {0}% / 最高 {1}%" -f $MinPercent, $MaxPercent) }
    if ($UsbSuspendOff) { Invoke-PowerCfg @('/setacvalueindex', $Guid, 'SUB_USB', 'USBSELSUSP', '0') -WhatIf:$WhatIf | Out-Null; $res.details += 'USB 选择性挂起: 已禁用' }
    if ($PciAspmOff)    { Invoke-PowerCfg @('/setacvalueindex', $Guid, 'SUB_PCIEXPRESS', 'ASPM', '0') -WhatIf:$WhatIf | Out-Null; $res.details += 'PCI Express 电源管理: 已关闭' }
    if ($DiskIdleSeconds -ge 0) { Invoke-PowerCfg @('/setacvalueindex', $Guid, 'SUB_DISK', 'DISKIDLE', [string]$DiskIdleSeconds) -WhatIf:$WhatIf | Out-Null; $res.details += ("硬盘休眠: " + $(if ($DiskIdleSeconds -eq 0) { '从不' } else { "$DiskIdleSeconds 秒" })) }
    if ($WirelessMaxPerf) { Invoke-PowerCfg @('/setacvalueindex', $Guid, 'SUB_NONE', 'WIRELESS_PWRSAV', '0') -WhatIf:$WhatIf | Out-Null; $res.details += '无线适配器电源模式: 最高性能' }

    Invoke-PowerCfg @('/setactive', $Guid) -WhatIf:$WhatIf | Out-Null
    return $res
}

# 设置当前（或指定）计划的 CPU 频率上下限（CLI 自定义模式）
function Set-CpuThrottle {
    param([int]$MinPercent, [int]$MaxPercent, [string]$Guid, [switch]$WhatIf)
    if ($MinPercent -lt 1 -or $MinPercent -gt 100 -or $MaxPercent -lt 1 -or $MaxPercent -gt 100) {
        return [PSCustomObject]@{ ok = $false; error = '值必须在 1-100 之间' }
    }
    if (-not $Guid) { $Guid = Get-ActivePowerPlan }
    if (-not $Guid) { return [PSCustomObject]@{ ok = $false; error = '无法获取当前电源计划 GUID' } }
    Invoke-PowerCfg @('/setacvalueindex', $Guid, 'SUB_PROCESSOR', 'PROCTHROTTLEMIN', [string]$MinPercent) -WhatIf:$WhatIf | Out-Null
    Invoke-PowerCfg @('/setacvalueindex', $Guid, 'SUB_PROCESSOR', 'PROCTHROTTLEMAX', [string]$MaxPercent) -WhatIf:$WhatIf | Out-Null
    Invoke-PowerCfg @('/setactive', $Guid) -WhatIf:$WhatIf | Out-Null
    return [PSCustomObject]@{ ok = $true; guid = $Guid; min = $MinPercent; max = $MaxPercent }
}

# ============================================================
#  网络（CLI / GUI / WebUI 三端统一实现）
# ============================================================
# 背景：此前三端各写一份，且已实际漂移出缺陷
#   1) CLI 改 DNS 会备份到 JSON，而 GUI / WebUI 完全没有备份 → 改坏无法恢复
#   2) DNS 选项三端各写一套：CLI 从 config 读(阿里/腾讯/114/Google/Cloudflare)，
#      GUI/WebUI 硬编码(Cloudflare/Google/阿里/114)，编号含义不一致
#   3) 适配器选择不一致：CLI 只取第一个活动适配器，GUI 用 WMI 取全部，
#      WebUI 取全部并把数组传给 -Name（多网卡时行为不可预期）
#   4) 实现路径不一致：CLI/GUI 混用 NetAdapter 系列 cmdlet 与 netsh，WebUI 全用 cmdlet
#
# 统一策略：
#   - 编号保持稳定（1=Cloudflare / 2=Google / 3=阿里 / 4=114 / 5=腾讯），
#     因为 WebUI 前端 index.html 硬编码了这些编号，改动会直接破坏界面；
#     config/optimization.json 的 dns_options 只覆盖"地址"，不改编号。
#   - 三端统一"对所有活动物理网卡"生效（与 GUI/WebUI 一致，CLI 此前只改第一个）。
#   - 统一先备份再修改；所有变更函数支持 -WhatIf 预演。

# 虚拟网卡关键词：默认排除，避免把 DNS 改到 VPN/虚拟机网卡上导致断网
$script:VirtualAdapterPatterns = @('Virtual', 'VMware', 'VirtualBox', 'Hyper-V', 'TAP-', 'Tunnel', 'Loopback', 'WAN Miniport', 'Bluetooth', 'Wi-Fi Direct')

# 获取活动网络适配器。优先 NetAdapter cmdlet，失败回退 CIM（Win7）。
# -IncludeVirtual 默认关闭，排除虚拟/隧道类网卡。
function Get-ActiveNetAdapters {
    param([switch]$IncludeVirtual)
    $result = @()
    try {
        $nets = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' })
        foreach ($n in $nets) {
            $result += [PSCustomObject]@{
                Name        = $n.Name
                IfIndex     = [int]$n.ifIndex
                Description = $n.InterfaceDescription
                MacAddress  = $n.MacAddress
                LinkSpeed   = $n.LinkSpeed
            }
        }
    } catch { }
    if ($result.Count -eq 0) {
        # Win7 回退：CIM（与 GUI 的 Get-NetAdapterCompat 同思路）
        try {
            $cims = @(Get-CimInstance Win32_NetworkAdapter -Filter 'NetEnabled=True' -ErrorAction Stop)
            foreach ($c in $cims) {
                if (-not $c.NetConnectionID) { continue }
                $result += [PSCustomObject]@{
                    Name        = $c.NetConnectionID
                    IfIndex     = [int]$c.InterfaceIndex
                    Description = $c.Description
                    MacAddress  = $c.MacAddress
                    LinkSpeed   = $null
                }
            }
        } catch { }
    }
    if (-not $IncludeVirtual) {
        $result = @($result | Where-Object {
            $text = ($_.Name + ' ' + $_.Description)
            -not ($script:VirtualAdapterPatterns | Where-Object { $text -like ('*' + $_ + '*') })
        })
    }
    return $result
}

# 统一 DNS 选项清单。编号稳定，地址可被 config 覆盖。
# 返回 @{Value;Key;Label;Primary;Secondary}
function Get-DnsOptions {
    $canonical = @(
        [PSCustomObject]@{ Value = 1; Key = 'cloudflare'; Label = 'Cloudflare'; Primary = '1.1.1.1';         Secondary = '1.0.0.1' }
        [PSCustomObject]@{ Value = 2; Key = 'google';     Label = 'Google';     Primary = '8.8.8.8';         Secondary = '8.8.4.4' }
        [PSCustomObject]@{ Value = 3; Key = 'aliyun';     Label = '阿里 DNS';   Primary = '223.5.5.5';       Secondary = '223.6.6.6' }
        [PSCustomObject]@{ Value = 4; Key = '114';        Label = '114 DNS';    Primary = '114.114.114.114'; Secondary = '114.114.115.115' }
        [PSCustomObject]@{ Value = 5; Key = 'tencent';    Label = '腾讯 DNS';   Primary = '119.29.29.29';    Secondary = '119.28.28.28' }
    )
    # config 只覆盖地址，不改编号（WebUI 前端硬编码了编号，改动会破坏界面）
    try {
        $cfg = Get-OptConfig
        if ($cfg -and $cfg.dns_options) {
            foreach ($o in $canonical) {
                $p = @($cfg.dns_options.PSObject.Properties | Where-Object { $_.Name -eq $o.Key })[0]
                if ($p) {
                    $addrs = @($p.Value)
                    if ($addrs.Count -gt 0 -and $addrs[0]) {
                        $o.Primary   = [string]$addrs[0]
                        $o.Secondary = if ($addrs.Count -gt 1) { [string]$addrs[1] } else { [string]$addrs[0] }
                    }
                }
            }
        }
    } catch { }
    return $canonical
}

# 读取指定适配器当前 DNS（现代 cmdlet 优先，回退 CIM）
function Get-AdapterDns {
    param([int]$IfIndex = 0, [string]$Name = '')
    if ($IfIndex -gt 0) {
        try {
            $a = Get-DnsClientServerAddress -InterfaceIndex $IfIndex -AddressFamily IPv4 -ErrorAction Stop
            return @($a.ServerAddresses)
        } catch { }
    }
    try {
        $cfgs = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' -ErrorAction Stop)
        foreach ($c in $cfgs) {
            if (($IfIndex -gt 0 -and [int]$c.InterfaceIndex -eq $IfIndex) -or ($Name -and $c.Description -eq $Name)) {
                return @($c.DNSServerSearchOrder)
            }
        }
    } catch { }
    return @()
}

# 备份所有活动适配器的 DNS 到 JSON（三端统一，CLI 此前独有）
function Backup-NetworkSettings {
    param([string]$BackupDir)
    $dir = Get-OptBackupDir -BackupDir $BackupDir
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $adapters = @()
    foreach ($a in (Get-ActiveNetAdapters)) {
        $adapters += [PSCustomObject]@{
            InterfaceAlias = $a.Name
            InterfaceIndex = $a.IfIndex
            DnsServers     = @(Get-AdapterDns -IfIndex $a.IfIndex -Name $a.Name)
        }
    }
    $file = Join-Path $dir ('network_backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.json')
    [PSCustomObject]@{
        Date     = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Adapters = $adapters
    } | ConvertTo-Json -Depth 5 | Out-File -FilePath $file -Encoding UTF8
    Write-BackupManifest -BackupFile $file -Domain 'network' -ItemCount $adapters.Count | Out-Null
    return $file
}

# 设置适配器 DNS（现代 cmdlet 优先，回退 netsh）。支持 -WhatIf。
function Set-AdapterDns {
    param([string]$Name, [int]$IfIndex = 0, [string[]]$DnsServers, [switch]$WhatIf)
    if (-not $DnsServers -or $DnsServers.Count -eq 0) {
        return [PSCustomObject]@{ ok = $false; error = '未提供 DNS 服务器' }
    }
    $joined = ($DnsServers -join ', ')
    if ($WhatIf) { return [PSCustomObject]@{ ok = $true; whatif = $true; method = '(预演)'; applied = $joined } }
    if ($IfIndex -gt 0) {
        try {
            Set-DnsClientServerAddress -InterfaceIndex $IfIndex -ServerAddresses $DnsServers -ErrorAction Stop
            return [PSCustomObject]@{ ok = $true; method = 'Set-DnsClientServerAddress'; applied = $joined }
        } catch { }
    }
    try {
        netsh interface ip set dns name="$Name" static $DnsServers[0] 2>&1 | Out-Null
        if ($DnsServers.Count -gt 1) { netsh interface ip add dns name="$Name" $DnsServers[1] index=2 2>&1 | Out-Null }
        return [PSCustomObject]@{ ok = $true; method = 'netsh'; applied = $joined }
    } catch {
        return [PSCustomObject]@{ ok = $false; error = $_.Exception.Message }
    }
}

# TCP 自动调优（现代 cmdlet 优先，回退 netsh）
function Set-TcpAutoTuning {
    param([string]$Level = 'Normal', [switch]$WhatIf)
    if ($WhatIf) { return [PSCustomObject]@{ ok = $true; whatif = $true; method = '(预演)'; level = $Level } }
    try {
        Set-NetTCPSetting -SettingName Internet -AutoTuningLevelLocal $Level -ErrorAction Stop
        return [PSCustomObject]@{ ok = $true; method = 'Set-NetTCPSetting'; level = $Level }
    } catch {
        try {
            netsh int tcp set global autotuninglevel=normal 2>&1 | Out-Null
            return [PSCustomObject]@{ ok = $true; method = 'netsh'; level = 'normal' }
        } catch { return [PSCustomObject]@{ ok = $false; error = $_.Exception.Message } }
    }
}

# RSS 接收端缩放（逐适配器；不支持时回退 netsh 全局）
function Enable-NetworkRss {
    param([string]$Name, [switch]$WhatIf)
    if ($WhatIf) { return [PSCustomObject]@{ ok = $true; whatif = $true; method = '(预演)' } }
    if ($Name) {
        try {
            if (Get-NetAdapterRss -Name $Name -ErrorAction Stop) {
                Enable-NetAdapterRss -Name $Name -ErrorAction Stop
                return [PSCustomObject]@{ ok = $true; method = 'Enable-NetAdapterRss' }
            }
        } catch { }
    }
    try { netsh int tcp set global rss=enabled 2>&1 | Out-Null; return [PSCustomObject]@{ ok = $true; method = 'netsh' } }
    catch { return [PSCustomObject]@{ ok = $false; error = $_.Exception.Message } }
}

# RSC 接收段合并
function Enable-NetworkRsc {
    param([string]$Name, [switch]$WhatIf)
    if ($WhatIf) { return [PSCustomObject]@{ ok = $true; whatif = $true; method = '(预演)' } }
    if ($Name) {
        try {
            if (Get-NetAdapterRsc -Name $Name -ErrorAction Stop) {
                Enable-NetAdapterRsc -Name $Name -ErrorAction Stop
                return [PSCustomObject]@{ ok = $true; method = 'Enable-NetAdapterRsc' }
            }
        } catch { }
    }
    try { netsh int tcp set global rsc=enabled 2>&1 | Out-Null; return [PSCustomObject]@{ ok = $true; method = 'netsh' } }
    catch { return [PSCustomObject]@{ ok = $false; error = $_.Exception.Message } }
}

# 清除 DNS 缓存
function Clear-NetDnsCache {
    param([switch]$WhatIf)
    if ($WhatIf) { return [PSCustomObject]@{ ok = $true; whatif = $true; method = '(预演)' } }
    try { Clear-DnsClientCache -ErrorAction Stop; return [PSCustomObject]@{ ok = $true; method = 'Clear-DnsClientCache' } }
    catch {
        try { ipconfig /flushdns 2>&1 | Out-Null; return [PSCustomObject]@{ ok = $true; method = 'ipconfig /flushdns' } }
        catch { return [PSCustomObject]@{ ok = $false; error = $_.Exception.Message } }
    }
}

# 编排：先备份，再按开关应用网络优化。
# 返回 @{ok;backup;details;adapters}
function Invoke-NetworkOptimization {
    param(
        [string]$BackupDir,
        [int]$DnsOption = 0,
        [bool]$Tcp = $true,
        [bool]$Rss = $true,
        [bool]$Rsc = $true,
        [bool]$DnsCache = $true,
        [switch]$SkipBackup,
        [switch]$WhatIf
    )
    $adapters = @(Get-ActiveNetAdapters)
    if ($adapters.Count -eq 0) {
        # 保持返回结构一致：三端（CLI/GUI/WebUI）只渲染 details，若 details 为空数组，
        # 无网卡环境下用户会看到一片空白（GitHub Actions 等无活动网卡环境已实测）。
        return [PSCustomObject]@{
            ok       = $false
            error    = '未检测到活动网络适配器'
            backup   = $null
            details  = @('未检测到活动网络适配器，已跳过网络优化')
            adapters = 0
        }
    }

    $details = @()
    $backup  = $null
    $ok      = $true

    # 统一先备份（此前 GUI / WebUI 完全没有备份，改坏无法恢复）
    # -WhatIf 时同样不落盘：预览必须零副作用
    if (-not $SkipBackup -and -not $WhatIf) {
        try { $backup = Backup-NetworkSettings -BackupDir $BackupDir }
        catch { $details += "备份失败: $($_.Exception.Message)" }
    }

    if ($DnsOption -gt 0) {
        $opt = @(Get-DnsOptions | Where-Object { $_.Value -eq $DnsOption })[0]
        if (-not $opt) {
            $details += "DNS 选项无效: $DnsOption"
            $ok = $false
        } else {
            foreach ($a in $adapters) {
                $r = Set-AdapterDns -Name $a.Name -IfIndex $a.IfIndex -DnsServers @($opt.Primary, $opt.Secondary) -WhatIf:$WhatIf
                if ($r.ok) { $details += "DNS [$($a.Name)] -> $($opt.Label) ($($r.applied))" }
                else { $details += "DNS [$($a.Name)] 失败: $($r.error)"; $ok = $false }
            }
        }
    } else {
        $details += 'DNS 保持当前设置'
    }

    if ($Tcp) {
        $r = Set-TcpAutoTuning -WhatIf:$WhatIf
        $details += if ($r.ok) { "TCP 自动调优已启用 ($($r.method))" } else { "TCP 自动调优失败: $($r.error)" }
        if (-not $r.ok) { $ok = $false }
    }
    if ($Rss) {
        foreach ($a in $adapters) {
            $r = Enable-NetworkRss -Name $a.Name -WhatIf:$WhatIf
            $details += if ($r.ok) { "RSS [$($a.Name)] 已启用 ($($r.method))" } else { "RSS [$($a.Name)] 失败: $($r.error)" }
            if (-not $r.ok) { $ok = $false }
        }
    }
    if ($Rsc) {
        foreach ($a in $adapters) {
            $r = Enable-NetworkRsc -Name $a.Name -WhatIf:$WhatIf
            $details += if ($r.ok) { "RSC [$($a.Name)] 已启用 ($($r.method))" } else { "RSC [$($a.Name)] 失败: $($r.error)" }
            if (-not $r.ok) { $ok = $false }
        }
    }
    if ($DnsCache) {
        $r = Clear-NetDnsCache -WhatIf:$WhatIf
        $details += if ($r.ok) { "DNS 缓存已刷新 ($($r.method))" } else { "DNS 缓存刷新失败: $($r.error)" }
        if (-not $r.ok) { $ok = $false }
    }

    return [PSCustomObject]@{
        ok       = $ok
        backup   = $backup
        details  = $details
        adapters = $adapters.Count
    }
}

# ============================================================
#  磁盘（CLI / GUI / WebUI 三端统一实现）
# ============================================================
# 背景：三端的实现路径与"正确性"都已漂移
#   1) CLI 用 WMI + defrag.exe（Win7 可用）；WebUI 用 Storage 模块的
#      Get-PhysicalDisk / Get-Volume / Optimize-Volume —— 该模块在 Win7 上
#      根本不存在，WebUI 在 Win7 会直接失败。
#   2) GUI / WebUI 对"每个卷同时执行 TRIM 和碎片整理"，且不区分 SSD/HDD
#      —— 对 SSD 做碎片整理是无谓写入、损耗寿命。
#   3) GUI 的 SSD 判定（Get-PhysicalDiskCompat）把 WMI 的
#      "Fixed hard disk media" 一律判成 HDD，导致 SSD 也被当成 HDD 整理。
#
# 统一策略（按要求优先保证 Win7 兼容）：
#   - 全部走 WMI + defrag.exe + fsutil，不使用 Storage 模块。
#   - TRIM 只用于 SSD；碎片整理只用于 HDD。
#   - defrag /L（TRIM）在 Win7 不可用，自动跳过（Win7 会自动执行 TRIM）。

# Win7 及更早（defrag /L 不可用）。版本号 < 6.2 视为旧系统。
function Test-IsLegacyWindows {
    try {
        $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
        $v = [version]$os.Version
        return ($v.Major -lt 6 -or ($v.Major -eq 6 -and $v.Minor -lt 2))
    } catch { return $false }
}

# 物理磁盘（WMI Win32_DiskDrive，Win7 可用）
# 注意：WMI 的 MediaType 对 SSD 通常也返回 "Fixed hard disk media"，
# 因此这里只在"明确匹配到 SSD"时才判 SSD，其余一律 Unknown，交由后续手段判定。
function Get-PhysicalDiskInfo {
    $disks = @()
    try {
        foreach ($d in @(Get-WmiObject -Class Win32_DiskDrive -ErrorAction Stop)) {
            $media = 'Unknown'
            if ($d.MediaType -match 'SSD|Solid State') { $media = 'SSD' }
            $disks += [PSCustomObject]@{
                DeviceId     = [int]$d.Index
                FriendlyName = $d.Model
                MediaType    = $media
                Size         = $d.Size
            }
        }
    } catch { }

    # 增强：Win8+ 的 MSFT_PhysicalDisk 能准确区分 SSD(4) / HDD(3)。
    # Win7 没有该命名空间，Get-WmiObject 会失败并被 catch 忽略 —— 不影响 Win7 兼容。
    # 该类不提供与 Win32_DiskDrive.Index 的直接对应，这里按"容量"匹配回写。
    try {
        $msft = @(Get-WmiObject -Namespace 'root\Microsoft\Windows\Storage' -Class MSFT_PhysicalDisk -ErrorAction Stop)
        if ($msft.Count -gt 0) {
            # MSFT_PhysicalDisk.DeviceId 与 Win32_DiskDrive.Index 实测是一一对应的，
            # 按此对应即可。（注意：两者 Size 有数 MB 级差异，不能用来做匹配依据。）
            foreach ($d in $disks) {
                if ($d.MediaType -ne 'Unknown') { continue }
                $match = @($msft | Where-Object { [string]$_.DeviceId -eq [string]$d.DeviceId })[0]
                if (-not $match) { continue }
                if ($match.MediaType -eq 4) { $d.MediaType = 'SSD' }
                elseif ($match.MediaType -eq 3) { $d.MediaType = 'HDD' }
                # 0 = Unspecified（Windows 自身也无法判定）→ 保持 Unknown，
                # 交给后面的 defrag /A 分析或 fsutil 兜底
            }
        }
    } catch { }

    return $disks
}

# 固定卷（WMI Win32_LogicalDisk DriveType=3，Win7 可用）
function Get-FixedVolumeList {
    $vols = @()
    try {
        foreach ($ld in @(Get-WmiObject -Class Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop)) {
            $vols += [PSCustomObject]@{
                DriveLetter   = $ld.DeviceID.Substring(0, 1)
                Size          = $ld.Size
                SizeRemaining = $ld.FreeSpace
            }
        }
    } catch { }
    return $vols
}

# 盘符 -> 介质类型（WMI 关联：逻辑盘 → 分区 → 物理盘）
function Get-DriveMediaMap {
    $map = @{}
    try {
        $diskMedia = @{}
        foreach ($d in (Get-PhysicalDiskInfo)) { $diskMedia[[string]$d.DeviceId] = $d.MediaType }
        foreach ($ld in @(Get-WmiObject -Class Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop)) {
            $letter = $ld.DeviceID.Substring(0, 1)
            $media  = 'Unknown'
            try {
                $parts = @(Get-WmiObject -Query ("ASSOCIATORS OF {Win32_LogicalDisk.DeviceID='" + $ld.DeviceID + "'} WHERE AssocClass=Win32_LogicalDiskToPartition") -ErrorAction Stop)
                foreach ($p in $parts) {
                    $drives = @(Get-WmiObject -Query ("ASSOCIATORS OF {Win32_DiskPartition.DeviceID='" + $p.DeviceID + "'} WHERE AssocClass=Win32_DiskDriveToDiskPartition") -ErrorAction Stop)
                    foreach ($drv in $drives) {
                        $m = $diskMedia[[string]$drv.Index]
                        if ($m -and $m -ne 'Unknown') { $media = $m; break }
                    }
                    if ($media -ne 'Unknown') { break }
                }
            } catch { }
            $map[$letter] = $media
        }
    } catch { }
    return $map
}

# 判断单个卷是 SSD 还是 HDD（Win7 兼容的多级回退）
# 顺序：WMI 显式 SSD → defrag /A 分析（Win8+ 逐卷精确）→ fsutil → 兜底 HDD
function Get-VolumeMediaType {
    param([string]$DriveLetter, [hashtable]$MediaMap)
    $letter = $DriveLetter.Substring(0, 1).ToUpper()

    if ($MediaMap -and $MediaMap.ContainsKey($letter) -and $MediaMap[$letter] -eq 'SSD') { return 'SSD' }

    # defrag /A 分析报告：Win8+ 会给出媒体类型，Win7 无此信息（会落空继续往下）
    try {
        $info = (defrag.exe "$letter`:" /A /U /V 2>&1 | Out-String)
        if ($info -match 'SSD|固态|Solid') { return 'SSD' }
        if ($info -match 'HDD|硬盘|机械|Hard disk') { return 'HDD' }
    } catch { }

    # fsutil：DisableDeleteNotify=0 表示系统启用了 TRIM（通常即存在 SSD）
    try {
        $out = (fsutil behavior query disabledeletenotify 2>&1 | Out-String)
        if ($out -match 'DisableDeleteNotify\s*=\s*0') { return 'SSD' }
    } catch { }

    return 'HDD'
}

# 对单个卷执行优化：SSD→TRIM，HDD→碎片整理（避免对 SSD 做碎片整理）
function Invoke-VolumeOptimization {
    param(
        [string]$DriveLetter,
        [string]$MediaType,
        [switch]$Trim,
        [switch]$Defrag,
        [switch]$WhatIf
    )
    $letter = $DriveLetter.Substring(0, 1).ToUpper()
    $drive  = "$letter`:"
    $result = [PSCustomObject]@{ drive = $drive; media = $MediaType; action = '无'; ok = $true; note = '' }

    if ($MediaType -eq 'SSD') {
        if (-not $Trim) { return $result }
        if (Test-IsLegacyWindows) {
            $result.action = 'TRIM(跳过)'
            $result.note   = 'Win7 及更早不支持 defrag /L；Win7 会自动执行 TRIM'
        } elseif ($WhatIf) {
            $result.action = 'TRIM(预演)'
        } else {
            defrag.exe $drive /L /O /U /V 2>&1 | Out-Null
            $result.action = 'TRIM'
        }
    } else {
        if (-not $Defrag) { return $result }
        if ($WhatIf) {
            $result.action = '碎片整理(预演)'
        } else {
            # 不带 /D：纯 defrag 在 Win7 及以后均可用
            defrag.exe $drive /U /V 2>&1 | Out-Null
            $result.action = '碎片整理'
        }
    }
    return $result
}

# 清理 WinSxS 组件存储
function Invoke-WinSxSCleanup {
    param([switch]$WhatIf)
    if ($WhatIf) { return 'WinSxS 组件清理(预演)' }
    Dism.exe /Online /Cleanup-Image /StartComponentCleanup 2>&1 | Out-Null
    return 'WinSxS 组件清理完成'
}

# CompactOS 默认开关的单一来源：config/optimization.json 的 disk.compact_os_default。
# 三端（CLI / GUI / WebUI）统一读这里，默认 false —— 压缩系统文件耗时长、
# 且回滚要走 Compact.exe /CompactOS:never，静默默认开启属于行为过激（见 HANDOFF §7.1）。
function Get-CompactOSDefault {
    $cfg = Get-OptConfig
    if ($cfg -and $cfg.disk -and ($cfg.disk.PSObject.Properties.Name -contains 'compact_os_default')) {
        return [bool]$cfg.disk.compact_os_default
    }
    return $false
}

# CompactOS 系统文件压缩（可选；-Enable 关闭时表示取消压缩）
function Set-CompactOSState {
    param([switch]$Enable, [switch]$WhatIf)
    if ($WhatIf) { return 'CompactOS(预演)' }
    if ($Enable) {
        Compact.exe /CompactOS:always 2>&1 | Out-Null
        return '系统文件压缩完成'
    }
    Compact.exe /CompactOS:never 2>&1 | Out-Null
    return '已取消系统文件压缩'
}

# 编排：逐卷判定介质后择优优化 + 可选的 WinSxS / CompactOS。
# 注：CompactOS 默认取 config 的 disk.compact_os_default（默认关闭），
#     调用方必须显式传 -Compact $true 才会压缩系统文件。
# 返回 @{ok;details;volumes;mediaMap}
function Invoke-DiskOptimization {
    param(
        [bool]$Trim = $true,
        [bool]$Defrag = $true,
        [bool]$WinSxS = $true,
        [bool]$Compact = (Get-CompactOSDefault),
        [string[]]$DriveLetters,
        [switch]$WhatIf
    )
    $vols = @(Get-FixedVolumeList)
    if ($DriveLetters -and $DriveLetters.Count -gt 0) {
        $set = @($DriveLetters | ForEach-Object { $_.Substring(0, 1).ToUpper() })
        $vols = @($vols | Where-Object { $set -contains $_.DriveLetter.ToUpper() })
    }

    $details = @()
    $ok      = $true
    $mediaMap = Get-DriveMediaMap

    foreach ($v in $vols) {
        $media = Get-VolumeMediaType -DriveLetter $v.DriveLetter -MediaMap $mediaMap
        try {
            $r = Invoke-VolumeOptimization -DriveLetter $v.DriveLetter -MediaType $media `
                                           -Trim:$Trim -Defrag:$Defrag -WhatIf:$WhatIf
            $line = "$($r.drive) [$($r.media)] $($r.action)"
            if ($r.note) { $line += " — $($r.note)" }
            $details += $line
            if (-not $r.ok) { $ok = $false }
        } catch {
            $details += "$($v.DriveLetter): [$media] 失败: $($_.Exception.Message)"
            $ok = $false
        }
    }

    if ($WinSxS) {
        try { $details += (Invoke-WinSxSCleanup -WhatIf:$WhatIf) }
        catch { $details += "WinSxS 清理失败: $($_.Exception.Message)"; $ok = $false }
    }
    if ($Compact) {
        try { $details += (Set-CompactOSState -Enable -WhatIf:$WhatIf) }
        catch { $details += "CompactOS 失败: $($_.Exception.Message)"; $ok = $false }
    }

    return [PSCustomObject]@{
        ok       = $ok
        details  = $details
        volumes  = $vols.Count
        mediaMap = $mediaMap
    }
}

# ============================================================
#  系统体检（只读）与优化前后对比
# ============================================================
# 复述已有 Get-* 只读函数，对五个域做一次可观测状态扫描，产出：
#   - metrics：各域量化指标（用于前后对比）
#   - issues ：问题清单（带严重级别与扣分）
#   - score  ：0-100 体检分
# 全程只读，不修改任何系统设置；报告可存为 JSON 以便优化前后对比。

# 体检项：严重级别决定扣分权重
function New-HealthIssue {
    param(
        [string]$Id,
        [string]$Severity,   # High / Medium / Low
        [string]$Title,
        [string]$Detail,
        [string]$Suggestion,
        # 可选：建议动作代码，取值见 Get-HealthRemediationCatalog。
        # 在 issue 产生处一次性声明，三端据此零漂移地展示与执行『自动修复』。
        [string]$Remediation = ''
    )
    $penalty = switch ($Severity) {
        'High'   { 15 }
        'Medium' { 8 }
        default  { 3 }
    }
    return [PSCustomObject]@{
        id         = $Id
        severity   = $Severity
        title      = $Title
        detail     = $Detail
        suggestion = $Suggestion
        remediation = $Remediation
        penalty    = $penalty
    }
}

# 只读扫描，生成体检报告
function Get-SystemHealthReport {
    param([switch]$SkipCleanScan)

    $issues  = @()
    $metrics = [ordered]@{}

    # --- 内存 ---
    $memTotalMB = 0
    $memFreeMB  = 0
    try {
        $os         = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $memTotalMB = [math]::Round($os.TotalVisibleMemorySize / 1KB, 0)
        $memFreeMB  = [math]::Round($os.FreePhysicalMemory   / 1KB, 0)
    } catch { }
    $memFreePct = if ($memTotalMB -gt 0) { [math]::Round($memFreeMB / $memTotalMB * 100, 1) } else { 0 }
    $metrics.totalRamMB = $memTotalMB
    $metrics.freeRamMB  = $memFreeMB
    $metrics.freeRamPct = $memFreePct
    if ($memTotalMB -gt 0 -and $memFreePct -lt 20) {
        $issues += New-HealthIssue 'memory.low' 'High' '可用内存偏低' `
            "可用 ${memFreeMB}MB / 共 ${memTotalMB}MB（${memFreePct}%）" `
            '关闭占用内存的程序，或减少开机启动项（菜单 [4]）' ''
    }

    # --- 服务：仍为自动启动的可优化服务 ---
    $svcList = @(Get-ServiceList)
    $autoSvc = @()
    try {
        $cimSvc = @(Get-CimInstance Win32_Service -ErrorAction Stop)
        foreach ($s in $svcList) {
            $hit = @($cimSvc | Where-Object { $_.Name -eq $s.Name })[0]
            if ($hit -and $hit.StartMode -eq 'Auto') { $autoSvc += $s.Name }
        }
    } catch { }
    $metrics.optimizableServices = $svcList.Count
    $metrics.servicesStillAuto   = $autoSvc.Count
    if ($autoSvc.Count -gt 0) {
        $issues += New-HealthIssue 'services.auto' 'Medium' "$($autoSvc.Count) 个可优化服务仍自动启动" `
            ($autoSvc -join '、') '使用菜单 [3] 服务优化禁用不必要的后台服务' 'services.disable'
    }

    # --- 启动项 ---
    $startups = @(Get-StartupItems)
    $metrics.startupCount = $startups.Count
    if ($startups.Count -gt 15) {
        $issues += New-HealthIssue 'startup.many' 'Medium' "开机启动项偏多（$($startups.Count) 项）" `
            '启动项越多，开机越慢、后台占用越高' '使用菜单 [4] 启动项优化' 'startup.list'
    }

    # --- 视觉效果：统计尚未关闭的特效开关 ---
    $toggles = @(Get-VisualEffectToggles)
    $visualLeft = @()
    foreach ($t in $toggles) {
        $cur = $null
        try {
            $p = Get-ItemProperty -Path $t.RegKey -Name $t.RegValue -ErrorAction SilentlyContinue
            if ($p) { $cur = $p.PSObject.Properties[$t.RegValue].Value }
        } catch { }
        # 键缺失时 Windows 默认即开启该特效，同样计为"未优化"
        if ($null -eq $cur) { $visualLeft += $t.Name }
        elseif ([string]$cur -ne [string]$t.RegData) { $visualLeft += $t.Name }
    }
    $metrics.visualTogglesTotal = $toggles.Count
    $metrics.visualTogglesLeft  = $visualLeft.Count
    $metrics.visualFXSetting    = Get-VisualEffectState
    if ($visualLeft.Count -gt 0) {
        $issues += New-HealthIssue 'visual.effects' 'Low' "$($visualLeft.Count)/$($toggles.Count) 项视觉特效仍开启" `
            ($visualLeft -join '、') '使用菜单 [5] 视觉效果优化切换为"最佳性能"' 'visual.profile'
    }

    # --- 电源计划 ---
    $planGuid  = Get-ActivePowerPlan
    $planTitle = '未知'
    try {
        $hitPlan = @(Get-PowerPlanCatalog | Where-Object { $_.GUID -eq $planGuid })[0]
        if ($hitPlan) { $planTitle = $hitPlan.Title }
        elseif ($planGuid) { $planTitle = $planGuid }
    } catch { }
    $metrics.powerPlanGuid  = $planGuid
    $metrics.powerPlanTitle = $planTitle
    if ($planGuid -eq '381b4222-f694-41f0-9685-ff5bb260df2e') {
        $issues += New-HealthIssue 'power.balanced' 'Medium' '当前为"平衡"电源计划' `
            '平衡计划会限制 CPU 频率，老电脑上体感更明显' '使用菜单 [6] 切换为高性能/卓越性能' 'power.plan'
    }

    # --- 磁盘空间 ---
    $vols     = @(Get-FixedVolumeList)
    $mediaMap = Get-DriveMediaMap
    $diskList = @()
    $tightDisks = @()
    foreach ($v in $vols) {
        $totalGB = if ($v.Size)          { [math]::Round([double]$v.Size / 1GB, 1) }          else { 0 }
        $freeGB  = if ($v.SizeRemaining) { [math]::Round([double]$v.SizeRemaining / 1GB, 1) } else { 0 }
        $usedPct = if ($v.Size -gt 0)    { [math]::Round((1 - ([double]$v.SizeRemaining / [double]$v.Size)) * 100, 1) } else { 0 }
        $media = if ($mediaMap -and $mediaMap.ContainsKey($v.DriveLetter)) { $mediaMap[$v.DriveLetter] } else { 'Unknown' }
        $diskList += [PSCustomObject]@{
            drive   = $v.DriveLetter
            media   = $media
            totalGB = $totalGB
            freeGB  = $freeGB
            usedPct = $usedPct
        }
        if ($usedPct -ge 90 -or ($freeGB -ge 0 -and $freeGB -lt 10 -and $totalGB -gt 0)) {
            $tightDisks += "$($v.DriveLetter): (可用 ${freeGB}GB / 已用 ${usedPct}%)"
        }
    }
    $metrics.volumes = $diskList
    $metrics.tightDisks = $tightDisks.Count
    if ($tightDisks.Count -gt 0) {
        $issues += New-HealthIssue 'disk.space' 'High' "$($tightDisks.Count) 个分区空间紧张" `
            ($tightDisks -join '；') '使用菜单 [2] 清理临时文件、[7] 磁盘优化' ''
    }

    # --- 可清理空间（递归统计，较慢，可用 -SkipCleanScan 跳过）---
    if (-not $SkipCleanScan) {
        $cleanable = 0
        $perTarget = @()
        foreach ($t in @(Get-CleanTargets)) {
            $b = Get-FolderSize $t.path
            if ($b -gt 0) {
                $perTarget += [PSCustomObject]@{ name = $t.name; mb = [math]::Round($b / 1MB, 1) }
                $cleanable += $b
            }
        }
        $metrics.cleanableMB = [math]::Round($cleanable / 1MB, 1)
        $metrics.cleanTargets = $perTarget
        if ($metrics.cleanableMB -gt 500) {
            $issues += New-HealthIssue 'disk.cleanable' 'Medium' "可回收约 $($metrics.cleanableMB) MB" `
                '临时文件/缓存/更新下载缓存等占用较多空间' '使用菜单 [2] 临时文件清理' 'disk.clean'
        }
    }

    # --- 网络 ---
    $adapters = @(Get-ActiveNetAdapters)
    $dnsInfo  = @()
    $fastDns  = @(Get-DnsOptions | ForEach-Object { $_.Primary })
    foreach ($a in $adapters) {
        $dns = @(Get-AdapterDns -IfIndex $a.IfIndex -Name $a.Name)
        $dnsInfo += [PSCustomObject]@{ name = $a.Name; dns = ($dns -join ', ') }
        $isFast = $false
        foreach ($d in $dns) { if ($fastDns -contains $d) { $isFast = $true; break } }
        if (-not $isFast -and $dns.Count -gt 0) {
            $issues += New-HealthIssue "network.dns.$($a.Name)" 'Low' "适配器 $($a.Name) 未使用公共快速 DNS" `
                "当前 DNS: $($dns -join ', ')" '使用菜单 [8] 网络优化切换为 Cloudflare / 阿里 / 114 等' 'network.dns'
        }
    }
    $metrics.activeAdapters = $adapters.Count
    $metrics.adapters       = $dnsInfo

    # --- 汇总 ---
    $penalty = 0
    foreach ($i in $issues) { $penalty += $i.penalty }
    $score = 100 - $penalty
    if ($score -lt 0) { $score = 0 }
    $grade = if ($score -ge 90) { '良好' }
             elseif ($score -ge 75) { '一般' }
             elseif ($score -ge 60) { '建议优化' }
             else { '亟需优化' }

    $hostName = $env:COMPUTERNAME
    return [PSCustomObject]@{
        timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        host      = $hostName
        version   = (Get-OptVersion)
        score     = $score
        grade     = $grade
        metrics   = [PSCustomObject]$metrics
        issues    = $issues
    }
}

# 保存体检报告为 JSON，返回文件路径（存于 <备份目录>/health）
function Save-HealthReport {
    param([object]$Report, [string]$BackupDir)
    $dir = Join-Path (Get-OptBackupDir -BackupDir $BackupDir) 'health'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    # 文件名精确到秒；同一秒内重复保存会互相覆盖，故存在时追加序号
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $file  = Join-Path $dir ("health_$stamp.json")
    $n = 1
    while (Test-Path $file) {
        $n++
        $file = Join-Path $dir ("health_${stamp}_$n.json")
    }
    $Report | ConvertTo-Json -Depth 8 | Out-File -FilePath $file -Encoding UTF8
    return $file
}

# 列出历史体检报告文件（按时间倒序）
function Get-HealthHistory {
    param([string]$BackupDir, [int]$Count = 10)
    $dir = Join-Path (Get-OptBackupDir -BackupDir $BackupDir) 'health'
    if (-not (Test-Path $dir)) { return @() }
    return @(Get-ChildItem -Path $dir -Filter 'health_*.json' -File -ErrorAction SilentlyContinue |
             Sort-Object Name -Descending | Select-Object -First $Count)
}

# 读取上一份体检报告（可排除刚保存的这份）
function Get-PreviousHealthReport {
    param([string]$BackupDir, [string]$ExcludeFile)
    foreach ($f in @(Get-HealthHistory -BackupDir $BackupDir -Count 5)) {
        if ($ExcludeFile -and $f.FullName -eq $ExcludeFile) { continue }
        try {
            return (Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json)
        } catch { }
    }
    return $null
}

# 对比两份体检报告，返回分数变化、已解决问题、新增问题、指标差值
function Compare-HealthReports {
    param([object]$Before, [object]$After)
    if (-not $Before -or -not $After) { return $null }

    $beforeIds = @($Before.issues | ForEach-Object { $_.id })
    $afterIds  = @($After.issues  | ForEach-Object { $_.id })

    $deltas = @()
    foreach ($p in $Before.metrics.PSObject.Properties) {
        $bv   = $p.Value
        $av   = $After.metrics.($p.Name)
        $bNum = 0.0
        $aNum = 0.0
        if ($null -eq $av) { continue }
        if ([double]::TryParse([string]$bv, [ref]$bNum) -and [double]::TryParse([string]$av, [ref]$aNum)) {
            $d = [math]::Round($aNum - $bNum, 2)
            if ($d -ne 0) {
                $deltas += [PSCustomObject]@{ metric = $p.Name; before = $bv; after = $av; delta = $d }
            }
        }
    }

    return [PSCustomObject]@{
        beforeScore  = [int]$Before.score
        afterScore   = [int]$After.score
        scoreDelta   = ([int]$After.score - [int]$Before.score)
        beforeTime   = $Before.timestamp
        afterTime    = $After.timestamp
        resolved     = @($Before.issues | Where-Object { $afterIds  -notcontains $_.id })
        new          = @($After.issues  | Where-Object { $beforeIds -notcontains $_.id })
        metricDeltas = $deltas
    }
}
# ============================================================
#  体检自动修复（Auto-Remediation，CLI / GUI / WebUI 三端共享）
#
#  背景：体检只告诉用户"哪里有问题"，老电脑用户面对十几个菜单依然无从下手。
#  这里把 issue 映射成"具体动作"，并编排**已存在**的域函数完成修复：
#
#  1. 单一映射来源：Get-HealthRemediationCatalog 是唯一一张 issue -> 动作表，
#     issue 产生处（New-HealthIssue 的 -Remediation）按 code 引用它，三端零漂移；
#  2. 纯编排，不新增任何系统操作面，因此天然继承各域的备份与 Win7 兼容层；
#  3. 只读先行：Get-HealthRemediationPlan 不碰系统，可随时预览；
#  4. 修改必备份：Invoke-HealthRemediation 每一步前自动调用对应域 Backup-*；
#  5. High 级问题一律不自动执行，需 -MaxSeverity High 且 -Force 双重确认；
#  6. startup.many / memory.low / disk.space 只给建议，永远不自动执行。
# ============================================================

# 严重级别排序权重：数值越大越严重，用于"允许自动执行的最高级别"判定
function Get-HealthSeverityRank {
    param([string]$Severity)
    switch ($Severity) {
        'High'   { return 3 }
        'Medium' { return 2 }
        'Low'    { return 1 }
        default  { return 0 }
    }
}

# issue -> 动作 的唯一映射表（lib 单点定义，三端零漂移）
#   Code      issue 的 remediation 字段值，即 New-HealthIssue -Remediation 的取值
#   IdPattern 兜底匹配模式：旧报告 / 手工构造的报告没有 remediation 字段时按 issue id 匹配
#   Domain    目标域，三端据此分域展示
#   Action    将要调用的既有 lib 函数
#   Auto      $true = 可自动执行；$false = 仅列清单或给建议，永不自动执行
function Get-HealthRemediationCatalog {
    return @(
        [PSCustomObject]@{ Code = 'services.disable'; IdPattern = 'services.auto';  Domain = 'services'; Action = 'Disable-Services';            Auto = $true  }
        [PSCustomObject]@{ Code = 'startup.list';    IdPattern = 'startup.many';    Domain = 'startup';  Action = 'List-StartupItems';          Auto = $false }
        [PSCustomObject]@{ Code = 'visual.profile';  IdPattern = 'visual.effects';  Domain = 'visual';   Action = 'Set-VisualEffectProfile';    Auto = $true  }
        [PSCustomObject]@{ Code = 'power.plan';      IdPattern = 'power.balanced';  Domain = 'power';    Action = 'Set-PowerPlan';              Auto = $true  }
        [PSCustomObject]@{ Code = 'disk.clean';      IdPattern = 'disk.cleanable';  Domain = 'clean';    Action = 'Remove-FolderContent';       Auto = $true  }
        [PSCustomObject]@{ Code = 'network.dns';     IdPattern = 'network.dns.*';   Domain = 'network';  Action = 'Invoke-NetworkOptimization'; Auto = $true  }
        [PSCustomObject]@{ Code = '';                IdPattern = 'memory.low';      Domain = 'memory';   Action = '';                          Auto = $false }
        [PSCustomObject]@{ Code = '';                IdPattern = 'disk.space';      Domain = 'disk';     Action = '';                          Auto = $false }
    )
}

# 由单个 issue 反查映射；无映射时返回 $null
function Resolve-HealthRemediation {
    param([object]$Issue)
    if (-not $Issue) { return $null }
    $cat  = @(Get-HealthRemediationCatalog)
    $code = ''
    if ($Issue.PSObject.Properties.Name -contains 'remediation') {
        $code = [string]$Issue.remediation
    }
    if ($code) {
        foreach ($m in $cat) { if ($m.Code -eq $code) { return $m } }
        return $null
    }
    foreach ($m in $cat) {
        if ($m.IdPattern -and [string]$Issue.id -like $m.IdPattern) { return $m }
    }
    return $null
}

# 生成「将做什么」清单。纯只读，不改动任何系统设置。
#   Report        指定体检报告；省略时自动体检（可加 -SkipCleanScan 提速）
#   PowerPlanGuid 电源计划目标 GUID，省略时用高性能计划
#   DnsOption     DNS 选项编号（见 Get-DnsOptions），默认 1 = Cloudflare
# 返回数组，元素字段：
#   id / severity / title / detail / domain / action / actionKey / auto / target / impact
function Get-HealthRemediationPlan {
    param(
        [object]$Report,
        [string]$PowerPlanGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c',
        [int]$DnsOption = 1,
        [switch]$SkipCleanScan
    )
    if (-not $Report) { $Report = Get-SystemHealthReport -SkipCleanScan:$SkipCleanScan }
    if (-not $Report) { return @() }

    $svcCount     = @(Get-ServiceList).Count
    $cleanTargets = @(Get-CleanTargets -Web)
    $dnsLabel     = ''
    foreach ($o in @(Get-DnsOptions))  { if ($o.Value -eq $DnsOption) { $dnsLabel = $o.Label } }
    $planTitle = ''
    foreach ($p in @(Get-PowerPlanCatalog)) { if ($p.GUID -eq $PowerPlanGuid) { $planTitle = $p.Title } }

    $plan = @()
    foreach ($i in @($Report.issues)) {
        $m = Resolve-HealthRemediation -Issue $i
        if (-not $m) { continue }

        $target = ''
        $impact = ''
        switch ($m.Code) {
            'services.disable' {
                $target = "config 全部可优化服务（$svcCount 项）"
                $impact = '相关后台服务停止运行；已自动备份服务状态，可随时恢复'
            }
            'startup.list' {
                $target = '开机启动项清单'
                $impact = '无任何改动，仅输出清单交由人工确认'
            }
            'visual.profile' {
                $target = '最佳性能（关闭全部视觉特效）'
                $impact = '窗口动画 / 阴影关闭，界面观感变化；已备份注册表，可恢复'
            }
            'power.plan' {
                $target = $(if ($planTitle) { $planTitle } else { $PowerPlanGuid })
                $impact = 'CPU 保持高频，耗电与发热上升；已备份电源配置，可恢复'
            }
            'disk.clean' {
                $target = "$($cleanTargets.Count) 个清理目标（临时文件 / 缓存 / 更新下载缓存）"
                $impact = '临时文件删除后不可恢复，浏览器缓存会重新生成'
            }
            'network.dns' {
                $target = "全部活动网卡 -> $dnsLabel"
                $impact = 'DNS 切换后个别站点需重连；已备份原 DNS，可恢复'
            }
            default {
                $target = '无（仅建议）'
                $impact = '仅给出建议，不执行任何改动'
            }
        }

        $plan += [PSCustomObject]@{
            id        = [string]$i.id
            severity  = [string]$i.severity
            title     = [string]$i.title
            detail    = [string]$i.detail
            domain    = $m.Domain
            action    = $m.Action
            actionKey = $m.Code
            auto      = [bool]$m.Auto
            target    = $target
            impact    = $impact
        }
    }
    return $plan
}

# 按 plan 逐个执行修复，每一步前自动调用对应域 Backup-*。
#   Report          指定体检报告；省略时自动体检
#   IssueCode       只修这些 issue id（如 'visual.effects'）；省略表示全部
#   MaxSeverity     允许自动执行的最高严重级别，默认 Medium（即 Low + Medium 可自动修）
#   PowerPlanGuid   电源计划目标 GUID，默认高性能
#   DnsOption       DNS 选项编号，默认 1 = Cloudflare
#   BackupDir       备份目录，省略时用 lib 默认 backups 目录
#   SkipBackup      跳过自动备份（不推荐，出问题将无法恢复）
#   SkipCleanScan   Report 省略时跳过可清理空间统计以提速
#   WhatIf          只预览将做什么，不实际执行
#   Force           允许自动执行 High 级问题（需配合 -MaxSeverity High）
#   SkipExplorerRestart 视觉修复后不自动重启资源管理器（CLI 默认行为）
# 返回 @{ ok; whatIf; executed; skipped; results; error }
function Invoke-HealthRemediation {
    param(
        [object]$Report,
        [string[]]$IssueCode,
        [ValidateSet('High', 'Medium', 'Low')][string]$MaxSeverity = 'Medium',
        [string]$PowerPlanGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c',
        [int]$DnsOption = 1,
        [string]$BackupDir,
        [switch]$SkipBackup,
        [switch]$SkipCleanScan,
        [switch]$WhatIf,
        [switch]$Force,
        [switch]$SkipExplorerRestart,
        # 优化前先建系统还原点（P1-3）；默认读 config 的 safety.create_restore_point
        [bool]$CreateRestorePoint = (Get-RestorePointDefault)
    )

    $res = [PSCustomObject]@{
        ok           = $true
        whatIf       = [bool]$WhatIf
        executed     = @()
        skipped      = @()
        results      = @()
        restorePoint = $null
        error        = $null
    }

    $plan = @(Get-HealthRemediationPlan -Report $Report -PowerPlanGuid $PowerPlanGuid `
                                       -DnsOption $DnsOption -SkipCleanScan:$SkipCleanScan)
    if ($plan.Count -eq 0) {
        $res.ok = $false
        $res.error = '没有可执行的修复项（未发现问题，或问题无对应动作）'
        return $res
    }

    $bdir      = Get-OptBackupDir -BackupDir $BackupDir
    $bdirOrNil = if ($SkipBackup) { $null } else { $bdir }

    # 安全天花板：MaxSeverity 是本次允许的上限；High 级还需 -Force 才放行
    $cap = Get-HealthSeverityRank $MaxSeverity
    if (-not $Force -and $cap -gt 2) { $cap = 2 }

    $svcList  = @(Get-ServiceList)
    $done     = @{}
    $executed = @()
    $skips    = @()
    $results  = @()

    foreach ($item in $plan) {
        # 指定了 IssueCode 时只处理这些 issue，其余连 skip 都不记录
        if ($IssueCode -and $IssueCode.Count -gt 0) {
            $hit = $false
            foreach ($c in $IssueCode) { if ($c -eq $item.id) { $hit = $true; break } }
            if (-not $hit) { continue }
        }

        $reason = ''
        if (-not $item.auto) {
            $reason = '该问题只提供建议，不自动执行'
        }
        elseif ((Get-HealthSeverityRank $item.severity) -gt $cap) {
            if ($item.severity -eq 'High') { $reason = 'High 级问题需 -Force 才会自动执行' }
            else { $reason = "严重级别高于 -MaxSeverity $MaxSeverity" }
        }
        elseif ($done.ContainsKey($item.actionKey)) {
            # 例如多个网卡都命中 network.dns.*，合并为一次网络优化
            $reason = '同一动作已执行（重复问题已合并）'
        }

        if ($reason) {
            $skips += [PSCustomObject]@{
                id = $item.id; severity = $item.severity; title = $item.title; reason = $reason
            }
            continue
        }
        $done[$item.actionKey] = $true

        # 真要动系统了才建还原点（懒创建）：若全部项目都被跳过，不默默硬建一个。
        # 失败不阻塞：只记录，让上层膨警告。
        if (-not $WhatIf -and $CreateRestorePoint -and $null -eq $restorePoint) {
            $restorePoint = New-SystemRestorePoint -Description ("PC-Optimizer 体棃修复前 {0:yyyy-MM-dd HH:mm}" -f (Get-Date))
            $res.restorePoint = $restorePoint
        }

        $step = [PSCustomObject]@{
            id        = $item.id
            domain    = $item.domain
            action    = $item.action
            ok        = $false
            backup    = $null
            summary   = ''
            error     = $null
        }

        if ($item.actionKey -eq 'services.disable') {
            if (-not $SkipBackup -and -not $WhatIf) {
                try { $step.backup = Backup-ServiceStates -BackupDir $bdir -Services $svcList }
                catch { $step.error = "备份失败: $($_.Exception.Message)" }
            }
            $r = Disable-Services -Services $svcList -Mode 'all' -WhatIf:$WhatIf
            # skipped 同时包含『未安装』与『执行失败』，只有真的失败才算 ok=False
            $svcFailed = @($r.details | Where-Object { [string]$_.result -like '失败*' }).Count
            $step.ok      = ($svcFailed -eq 0)
            $step.summary = "禁用 $($r.disabled) 项，跳过 $($r.skipped) 项"
            if ($svcFailed -gt 0) { $step.error = ($svcFailed.ToString() + ' 个服务禁用失败（可能未以管理员运行）') }
        }
        elseif ($item.actionKey -eq 'visual.profile') {
            $r = Set-VisualEffectProfile -Profile 1 -BackupDir $bdirOrNil `
                                         -SkipExplorerRestart:$SkipExplorerRestart -WhatIf:$WhatIf
            $step.ok      = $r.ok
            $step.backup  = $r.backup
            $step.summary = '已切换为最佳性能（关闭全部视觉特效）'
        }
        elseif ($item.actionKey -eq 'power.plan') {
            $r = Set-PowerPlan -Guid $PowerPlanGuid -BackupDir $bdirOrNil -SkipBackup:$SkipBackup -WhatIf:$WhatIf
            $step.ok      = $r.ok
            $step.backup  = $r.backup
            $step.summary = "电源计划已切换为 $(if ($r.appliedGuid) { $r.appliedGuid } else { $PowerPlanGuid })"
        }
        elseif ($item.actionKey -eq 'disk.clean') {
            $freed = 0
            foreach ($t in @(Get-CleanTargets -Web)) {
                $freed += [int](Remove-FolderContent -Path $t.path -WhatIf:$WhatIf)
            }
            $step.ok      = $true
            $step.summary = "清理 $(@(Get-CleanTargets -Web).Count) 个目标，删除 $freed 个条目"
        }
        elseif ($item.actionKey -eq 'network.dns') {
            $r = Invoke-NetworkOptimization -BackupDir $bdirOrNil -DnsOption $DnsOption `
                                            -SkipBackup:$SkipBackup -WhatIf:$WhatIf
            $step.ok      = $r.ok
            $step.backup  = $r.backup
            $step.summary = (@($r.details) -join '；')
            if ($r.error) { $step.error = $r.error }
        }
        else {
            $step.error = "未知动作: $($item.actionKey)"
        }

        if (-not $step.ok -and -not $res.error) { $res.error = $step.error }
        $results  += $step
        $executed += $item.id
    }

    $res.executed     = $executed
    $res.skipped      = $skips
    $res.results      = $results
    $res.restorePoint = $restorePoint
    $res.ok           = (@($results | Where-Object { -not $_.ok }).Count -eq 0)
    if ($res.error) { $res.ok = $false }
    return $res
}

# ============================================================
#  备份元数据 manifest / 优化时间线 / 一键回滚
# ============================================================
# 背景：此前各域备份都是扁平堆在 backups/ 下，恢复要逐域翻菜单，
#   用户既说不清「上周到底改了什么」，也无法整体退回某个时间点。
# 现约定（三端共用，避免再次漂移）：
#   1) 每次 Backup-* 在写备份文件的同时，写一份 <备份文件>.manifest.json
#      元数据（域 / 时间 / 条目数 / 版本 / 主机 / 备注）；manifest 写失败
#      绝不影响备份本身。
#   2) Get-OptimizationTimeline 聚合全部 manifest，按时间倒序给时间线；
#      旧备份没有 manifest 时按文件名推断域、按文件时间兜底，并标注「元数据缺失」。
#   3) Get-RollbackPlan 只读地算出「将回滚哪些备份」；
#      Invoke-Rollback 按固定顺序（服务→启动项→视觉→电源→网络→遥测→更新）
#      调用既有 Restore-* 还原，并在还原前先把当前状态再备份一遍（后悔药）。

# 内部小工具：安全取数组长度（避免个别主机上 $null.Count 抛错）
function Get-SafeCount {
    param($Items)
    if ($null -eq $Items) { return 0 }
    return @($Items).Count
}

# 写备份元数据 manifest，返回 manifest 文件路径；失败返回 $null（不影响备份主流程）
function Write-BackupManifest {
    param(
        [Parameter(Mandatory=$true)][string]$BackupFile,
        [Parameter(Mandatory=$true)][string]$Domain,
        [int]$ItemCount = 0,
        [string]$Note = ''
    )
    try {
        $file = Get-Item -LiteralPath $BackupFile -ErrorAction SilentlyContinue
        if (-not $file) { return $null }
        $now = Get-Date
        $manifest = [PSCustomObject]@{
            version  = (Get-OptVersion)
            domain   = $Domain
            file     = $file.Name
            date     = $now.ToString('yyyy-MM-dd HH:mm:ss')
            time     = $now.ToString('yyyy-MM-ddTHH:mm:ss')
            items    = [int]$ItemCount
            bytes    = [long]$file.Length
            host     = $env:COMPUTERNAME
            user     = $env:USERNAME
            note     = $Note
        }
        $manifestFile = ($file.FullName + '.manifest.json')
        ($manifest | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $manifestFile -Encoding UTF8
        return $manifestFile
    } catch {
        return $null
    }
}

# 备份域 -> 中文标签（三端展示统一，避免各端各写一套文案）
function Get-BackupDomainLabel {
    param([string]$Domain)
    switch ($Domain) {
        'services'  { return '服务' }
        'startup'   { return '启动项' }
        'visual'    { return '视觉效果' }
        'power'     { return '电源计划' }
        'network'   { return '网络 DNS' }
        'telemetry' { return '遥测计划任务' }
        'update'    { return 'Windows 更新' }
        'health'    { return '体检报告' }
        'clean'     { return '临时文件清理' }
        default     { return '其它' }
    }
}

# 由备份文件名推断域（旧备份没有 manifest 时用）。先匹配更具体的模式。
function Get-BackupDomainFromName {
    param([string]$Name)
    $n = [string]$Name
    if     ($n -like 'services_backup_*')   { return 'services' }
    elseif ($n -like 'startup_backup_*')    { return 'startup' }
    elseif ($n -like 'visual_backup_*')     { return 'visual' }
    elseif ($n -like 'power_backup_*')      { return 'power' }
    elseif ($n -like 'network_backup_*')    { return 'network' }
    elseif ($n -like 'telemetry_backup_*')  { return 'telemetry' }
    elseif ($n -like 'winupdate_block_*')   { return 'update' }
    elseif ($n -like 'manual_update_*')     { return 'update' }
    # 旧 GUI / WebUI 命名：services_*.csv / startup_*.csv / power_*.txt / visual_*.txt
    elseif ($n -like 'services_*')          { return 'services' }
    elseif ($n -like 'startup_*')           { return 'startup' }
    elseif ($n -like 'visual_*')            { return 'visual' }
    elseif ($n -like 'power_*')             { return 'power' }
    elseif ($n -like 'network_*')           { return 'network' }
    elseif ($n -like 'telemetry_*')         { return 'telemetry' }
    elseif ($n -like 'health_*')            { return 'health' }
    else { return 'unknown' }
}

# 由单个备份文件生成时间线条目（manifest 存在则元数据完整，否则按文件名/时间容错）
function New-BackupTimelineEntry {
    param($FileInfo)
    if (-not $FileInfo) { return $null }
    $f = $FileInfo
    $dom = Get-BackupDomainFromName $f.Name
    $timeText = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
    $timeValue = $f.LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss')
    $items = 0; $hostName = ''; $ver = ''; $note = ''; $missing = $true

    $manifestFile = ($f.FullName + '.manifest.json')
    if (Test-Path -LiteralPath $manifestFile) {
        try {
            $mf = Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($mf.domain) { $dom       = [string]$mf.domain }
            if ($mf.date)   { $timeText  = [string]$mf.date }
            if ($mf.time)   { $timeValue = [string]$mf.time }
            if ($null -ne $mf.items)  { $items    = [int]$mf.items }
            if ($mf.host)   { $hostName = [string]$mf.host }
            if ($mf.version){ $ver      = [string]$mf.version }
            if ($mf.note)   { $note     = [string]$mf.note }
            $missing = $false
        } catch { }
    }

    return [PSCustomObject]@{
        id              = $f.BaseName
        timeText        = $timeText
        time            = $timeValue
        domain          = $dom
        domainLabel     = (Get-BackupDomainLabel -Domain $dom)
        file            = $f.Name
        path            = $f.FullName
        items           = $items
        host            = $hostName
        version         = $ver
        note            = $note
        metadataMissing = $missing
        sizeKB          = [math]::Round($f.Length / 1KB, 1)
    }
}

# 聚合全部备份，给出「优化时间线」（按时间倒序）。纯只读。
# 返回数组元素：id / time / timeText / domain / domainLabel / file / path /
#               items / host / version / note / metadataMissing / sizeKB
function Get-OptimizationTimeline {
    param([string]$BackupDir, [int]$Max = 200)
    $dir = Get-OptBackupDir -BackupDir $BackupDir
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    $entries = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)) {
        if ($f.Name -like '*.manifest.json') { continue }
        $e = New-BackupTimelineEntry -FileInfo $f
        if ($e) { $entries += $e }
    }
    # 同一秒内可能连建多份备份（manifest 的 time 只到秒），
    # 用文件名（内含 yyyyMMdd_HHmmss）做次级排序保证顺序确定
    $sorted = @($entries | Sort-Object `
        @{Expression = { [datetime]$_.time }; Descending = $true}, `
        @{Expression = { $_.file }; Descending = $true})
    if ($Max -gt 0 -and $sorted.Count -gt $Max) { $sorted = @($sorted | Select-Object -First $Max) }
    return $sorted
}

# 计算「将回滚哪些备份」。纯只读，不碰系统。
#   Since    回滚到该时间点：每个域取 <= Since 的最新一份备份（即该时间点的状态）
#   Last     回滚到最近第 N 条备份所在的时间点（与 Since 同一套语义）
#   Domain   只处理这些域（services/startup/visual/power/network/telemetry/update）
#   File     直接指定单个备份文件（GUI 单选某一份备份时用）
# 返回 @{ ok; mode; since; entries; domains; error }
function Get-RollbackPlan {
    param(
        [string]$BackupDir,
        [datetime]$Since = [datetime]::MinValue,
        [int]$Last = 0,
        [string[]]$Domain,
        [string]$File
    )
    $res = [PSCustomObject]@{ ok = $true; mode = ''; since = $null; entries = @(); domains = @(); error = $null }
    $dir = Get-OptBackupDir -BackupDir $BackupDir

    # --- 模式一：指定单个备份文件 ---
    if ($File) {
        $target = Get-Item -LiteralPath $File -ErrorAction SilentlyContinue
        if (-not $target) {
            try { $target = Get-Item -LiteralPath (Join-Path $dir $File) -ErrorAction Stop } catch { $target = $null }
        }
        if (-not $target) {
            $res.ok = $false; $res.error = '指定的备份文件不存在（或已被删除）'
            return $res
        }
        $res.mode   = 'file'
        $res.since  = $target.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
        $res.entries = @(New-BackupTimelineEntry -FileInfo $target)
        $res.domains = @($res.entries | ForEach-Object { $_.domain })
        return $res
    }

    $timeline = @(Get-OptimizationTimeline -BackupDir $BackupDir)
    if ($timeline.Count -eq 0) {
        $res.ok = $false; $res.error = '没有任何备份，无法回滚'
        return $res
    }

    # --- 模式二：回到某个时间点（每个域取该时间点之前的最新备份）---
    # 未指定 Since / Last 时取「最近的一份备份」（boundary 用极大值等于不过滤）
    $hasSince = ($Since -gt [datetime]::MinValue)
    $boundary = [datetime]::MaxValue
    if ($Last -gt 0) {
        $nth = @($timeline | Select-Object -Skip ($Last - 1) -First 1)
        if ($nth.Count -eq 0) {
            $res.ok = $false; $res.error = "备份数量不足 $Last 条，无法回滚"
            return $res
        }
        $boundary = [datetime]$nth[0].time
    }
    elseif ($hasSince) {
        $boundary = $Since
    }
    $res.mode  = 'point'
    $res.since = if ($boundary -eq [datetime]::MaxValue) { '最近的备份' } else { $boundary.ToString('yyyy-MM-dd HH:mm:ss') }

    $picked = @()
    $done = @{}
    foreach ($e in ($timeline | Sort-Object `
        @{Expression = { [datetime]$_.time }; Descending = $true}, `
        @{Expression = { $_.file }; Descending = $true})) {
        if ([datetime]$e.time -gt $boundary) { continue }
        if ($done.ContainsKey($e.domain)) { continue }
        $done[$e.domain] = $true
        $picked += $e
    }

    if ($Domain -and $Domain.Count -gt 0) {
        $want = @()
        foreach ($d in $Domain) {
            foreach ($p in $picked) { if ($p.domain -eq $d) { $want += $p } }
        }
        $picked = @($want)
    }

    if ($picked.Count -eq 0) {
        $res.ok = $false
        $res.error = if ($Domain -and $Domain.Count -gt 0) { '指定域在该时间点没有可回滚的备份' } else { '该时间点之前没有任何备份' }
        return $res
    }
    $res.entries = $picked
    $res.domains = @($picked | ForEach-Object { $_.domain })
    return $res
}

# 把还原结果里的 details 渲染成一行可读文本。
# details 既可能是字符串（如 Restore-UpdateBackup），也可能是 @{name;result} 哈希表。
function Format-RestoreDetails {
    param($Details, [string]$Fallback = '')
    $parts = @()
    foreach ($d in @($Details)) {
        if ($null -eq $d) { continue }
        if ($d -is [string]) { $parts += $d }
        else {
            $name = ''
            $text = ''
            try { $name = [string]$d.name } catch { }
            try { $text = [string]$d.result } catch { }
            if ($name -and $text) { $parts += ("{0}: {1}" -f $name, $text) }
            elseif ($text)       { $parts += $text }
            elseif ($name)       { $parts += $name }
        }
    }
    if ($parts.Count -eq 0) { return $Fallback }
    return ($parts -join '；')
}

# 备份某个域的当前状态（回滚前的「后悔药」），返回备份文件路径；失败返回 $null
function Backup-DomainState {
    param([string]$Domain, [string]$BackupDir)
    try {
        switch ($Domain) {
            'services'  { return (Backup-ServiceStates     -BackupDir $BackupDir -Services (Get-ServiceList)) }
            'startup'   { return (Backup-StartupItems      -BackupDir $BackupDir -Items    (Get-StartupItems)) }
            'visual'    { return (Backup-VisualEffects    -BackupDir $BackupDir) }
            'power'     { return (Backup-PowerPlan        -BackupDir $BackupDir) }
            'network'   { return (Backup-NetworkSettings  -BackupDir $BackupDir) }
            'telemetry' { return (Backup-TelemetryTaskStates -BackupDir $BackupDir) }
        }
    } catch { }
    return $null
}

# 按域调度对应的还原函数（三端共用的单一分发点）
#   Domain 不可回滚（health / unknown）时返回 $null，由调用方自己提示
#   File 省略时各域自己取最近一份备份
function Restore-DomainState {
    param([string]$Domain, [string]$File, [string]$BackupDir)
    switch ($Domain) {
        'services'  { return (Restore-Services        -BackupDir $BackupDir -File $File) }
        'startup'   { return (Restore-StartupItems    -BackupDir $BackupDir -File $File) }
        'visual'    { return (Restore-VisualEffects   -BackupDir $BackupDir -File $File) }
        'power'     { return (Restore-PowerPlan       -BackupDir $BackupDir -File $File) }
        'network'   { return (Restore-NetworkSettings -BackupDir $BackupDir -File $File) }
        'telemetry' { return (Restore-TelemetryTasks  -BackupDir $BackupDir -File $File) }
        'update'    { return (Restore-UpdateBackup    -File            $File) }
    }
    return $null
}

# ============================================================
#  各域还原（三端共用的单一实现，此前 CLI/GUI/WebUI 各写一份且读不懂彼此的备份）
# ============================================================

# 从备份 CSV 恢复启动项（列名统一为 Name,Value,Scope,Source,Path）
#   注册表项：值已缺失时按备份值重建
#   启动文件夹项：从 backups/startup_items 移回原位置
#   系统启动命令（WMI 视图）：与上面两类条目重复，只登记不动作
# 返回 @{ restored; failed; backup; details; error }
function Restore-StartupItems {
    param([string]$BackupDir, [string]$File)
    try {
        $dir = Get-OptBackupDir -BackupDir $BackupDir
        $target = $null
        if ($File) {
            $target = Get-Item -LiteralPath $File -ErrorAction SilentlyContinue
        } else {
            $target = Get-ChildItem -Path $dir -Filter 'startup_backup_*.csv' -ErrorAction SilentlyContinue |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1
        }
        if (-not $target) {
            return @{restored = 0; failed = 0; backup = $null; details = @(); error = '未找到启动项备份'}
        }

        $rows = @(Import-Csv -LiteralPath $target.FullName -Encoding UTF8)
        $restored = 0; $failed = 0; $details = @()

        foreach ($row in $rows) {
            $name = [string]$row.Name
            $path = [string]$row.Path
            # Source 列是中文，旧工具写的或非 UTF8 编码的 CSV 读进来可能变成乱码，
            # 因此不背依中文 Source 判别：先看路径形态（注册表路径 / 启动文件夹路径），
            # 中文 Source 只作为启动文件夹的补充判据
            $isStartupFolder = ($path -like '*\Start Menu\*') -or ([string]$row.Source -eq '启动文件夹')
            $isRegistryPath  = $path -like '?*:\*'
            try {
                if ($isStartupFolder) {
                    $leaf = Split-Path -Leaf ([string]$row.Value)
                    $src  = Join-Path $dir ("startup_items\" + $leaf)
                    if (-not (Test-Path -LiteralPath $src)) {
                        $failed++
                        $details += @{name = $name; result = '跳过: 启动文件夹备份文件不存在'}
                    } else {
                        $destDir = $path
                        if (-not (Test-Path -LiteralPath $destDir)) {
                            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                        }
                        Move-Item -LiteralPath $src -Destination (Join-Path $destDir $leaf) -Force -ErrorAction Stop
                        $restored++
                        $details += @{name = $name; result = '已还原到启动文件夹'}
                    }
                }
                elseif ($isRegistryPath) {
                    # 只有注册表路径才写注册表；路径不像注册表路径时一律跳过，
                    # 避免把 'Startup' 之类的 WMI 位置字符串当成文件系统路径而误建目录
                    if ([string]::IsNullOrWhiteSpace($path)) {
                        $failed++
                        $details += @{name = $name; result = '失败: 备份缺少 Path 列（旧格式）'}
                    }
                    elseif (-not (Test-Path -LiteralPath $path)) {
                        New-Item -Path $path -Force | Out-Null
                        New-ItemProperty -Path $path -Name $name -Value $row.Value -PropertyType String -Force | Out-Null
                        $restored++
                        $details += @{name = $name; result = '已恢复'}
                    }
                    elseif (Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue) {
                        $details += @{name = $name; result = '已存在，跳过'}
                    }
                    else {
                        New-ItemProperty -Path $path -Name $name -Value $row.Value -PropertyType String -Force | Out-Null
                        $restored++
                        $details += @{name = $name; result = '已恢复'}
                    }
                }
                else {
                    # 系统启动命令（WMI 视图）与注册表 / 启动文件夹条目重复，无需单独还原
                    $details += @{name = $name; result = '跳过: 与注册表/启动文件夹条目重复'}
                }
            } catch {
                $failed++
                $details += @{name = $name; result = ('失败: ' + $_.Exception.Message)}
            }
        }

        return @{restored = $restored; failed = $failed; backup = $target.FullName; details = $details; error = $null}
    } catch {
        return @{restored = 0; failed = 0; backup = $null; details = @(); error = $_.Exception.Message}
    }
}

# 从备份 JSON 恢复视觉效果相关注册表键（覆盖 Set-VisualEffectProfile 写入的项）
# 返回 @{ restored; backup; details; error }
function Restore-VisualEffects {
    param([string]$BackupDir, [string]$File)
    try {
        $dir = Get-OptBackupDir -BackupDir $BackupDir
        $target = $null
        if ($File) {
            $target = Get-Item -LiteralPath $File -ErrorAction SilentlyContinue
        } else {
            $target = Get-ChildItem -Path $dir -Filter 'visual_backup_*.json' -ErrorAction SilentlyContinue |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1
        }
        if (-not $target) { return @{restored = 0; backup = $null; details = @(); error = '未找到视觉效果备份'} }
        $data = Get-Content -LiteralPath $target.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $data) { return @{restored = 0; backup = $target.FullName; details = @(); error = '备份内容为空或已损坏'} }

        $keyMap = [ordered]@{
            VisualEffects = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
            DWM           = 'HKCU:\Software\Microsoft\Windows\DWM'
            Advanced      = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
            Desktop       = 'HKCU:\Control Panel\Desktop'
        }
        $restored = 0; $details = @()
        foreach ($k in $keyMap.Keys) {
            $section = $null
            $prop = $data.PSObject.Properties[$k]
            if ($prop) { $section = $prop.Value }
            if (-not $section) { continue }
            $regPath = $keyMap[$k]
            if (-not (Test-Path -LiteralPath $regPath)) {
                try { New-Item -Path $regPath -Force | Out-Null } catch { }
            }
            foreach ($p in ($section.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })) {
                try {
                    $existing = Get-ItemProperty -Path $regPath -Name $p.Name -ErrorAction SilentlyContinue
                    if ($existing) {
                        # 值已存在：不指定类型，保留原类型（DWord / Binary / String 都不变形）
                        Set-ItemProperty -Path $regPath -Name $p.Name -Value $p.Value -ErrorAction Stop
                    } else {
                        $regType = 'String'
                        if ($p.Value -is [int] -or $p.Value -is [long] -or $p.Value -is [bool]) { $regType = 'DWord' }
                        elseif ($p.Value -is [Array]) { $regType = 'Binary' }
                        New-ItemProperty -Path $regPath -Name $p.Name -Value $p.Value -PropertyType $regType -Force | Out-Null
                    }
                    $restored++
                } catch {
                    $details += ("{0}\{1} 恢复失败: {2}" -f $k, $p.Name, $_.Exception.Message)
                }
            }
        }
        return @{restored = $restored; backup = $target.FullName; details = $details; error = $null}
    } catch {
        return @{restored = 0; backup = $null; details = @(); error = $_.Exception.Message}
    }
}

# 从备份恢复电源计划。
#   power_backup_*.json（新版，记录 activeGuid）：powercfg /setactive 精确切回
#   power_backup_*.txt（旧版，仅 powercfg /query 文本）：无法可靠解析，只给手动提示
# 返回 @{ restored; backup; details; error }
function Restore-PowerPlan {
    param([string]$BackupDir, [string]$File)
    try {
        $dir = Get-OptBackupDir -BackupDir $BackupDir
        $target = $null
        if ($File) {
            $target = Get-Item -LiteralPath $File -ErrorAction SilentlyContinue
        } else {
            $target = Get-ChildItem -Path $dir -Filter 'power_backup_*' -ErrorAction SilentlyContinue |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1
        }
        if (-not $target) { return @{restored = 0; backup = $null; details = @(); error = '未找到电源计划备份'} }

        if ($target.Extension -eq '.json') {
            $data = Get-Content -LiteralPath $target.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $guid = ''
            if ($data.PSObject.Properties.Name -contains 'activeGuid') { $guid = [string]$data.activeGuid }
            if ([string]::IsNullOrWhiteSpace($guid)) {
                return @{restored = 0; backup = $target.FullName; details = @('备份中未记录电源计划 GUID，无法自动恢复'); error = $null}
            }
            Invoke-PowerCfg @('/setactive', $guid) | Out-Null
            $now = Get-ActivePowerPlan
            if ($now -eq $guid) {
                return @{restored = 1; backup = $target.FullName; guid = $guid; details = @("已切回电源计划 $guid"); error = $null}
            }
            return @{restored = 0; backup = $target.FullName; guid = $guid; details = @(); error = '设置电源计划失败（可能需要管理员权限）'}
        }

        return @{restored = 0; backup = $target.FullName;
                 details = @('旧格式备份（.txt）未记录计划 GUID，请在 控制面板→电源选项 手动选择原计划，或运行 powercfg /restoredefaultschemes');
                 error = $null}
    } catch {
        return @{restored = 0; backup = $null; details = @(); error = $_.Exception.Message}
    }
}

# 从备份 JSON 恢复各网卡 DNS（含「备份时为 DHCP 自动获取」的情况）
# 返回 @{ restored; failed; backup; details; error }
function Restore-NetworkSettings {
    param([string]$BackupDir, [string]$File)
    try {
        $dir = Get-OptBackupDir -BackupDir $BackupDir
        $target = $null
        if ($File) {
            $target = Get-Item -LiteralPath $File -ErrorAction SilentlyContinue
        } else {
            $target = Get-ChildItem -Path $dir -Filter 'network_backup_*.json' -ErrorAction SilentlyContinue |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1
        }
        if (-not $target) { return @{restored = 0; failed = 0; backup = $null; details = @(); error = '未找到网络 DNS 备份'} }
        $data = Get-Content -LiteralPath $target.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $restored = 0; $failed = 0; $details = @()

        foreach ($a in @($data.Adapters)) {
            if (-not $a) { continue }
            $name = [string]$a.InterfaceAlias
            $idx  = 0
            if ($null -ne $a.InterfaceIndex) { $idx = [int]$a.InterfaceIndex }
            $servers = @()
            foreach ($s in @($a.DnsServers)) { if ($s) { $servers += [string]$s } }

            if ($servers.Count -eq 0) {
                # 备份时是自动获取：置空 / dhcp 即恢复
                $okReset = $false
                if ($idx -gt 0) {
                    try { Set-DnsClientServerAddress -InterfaceIndex $idx -ResetServerAddresses -ErrorAction Stop; $okReset = $true } catch { }
                }
                if (-not $okReset) {
                    try { netsh interface ip set dns name="$name" dhcp 2>&1 | Out-Null; $okReset = $true } catch { }
                }
                if ($okReset) { $restored++; $details += "$name -> 自动获取 (DHCP)" }
                else { $failed++; $details += "$name -> 恢复 DHCP 失败" }
                continue
            }

            $r = Set-AdapterDns -Name $name -IfIndex $idx -DnsServers $servers
            if ($r.ok) { $restored++; $details += "$name -> $($servers -join ', ')" }
            else { $failed++; $details += "$name 失败: $($r.error)" }
        }
        return @{restored = $restored; failed = $failed; backup = $target.FullName; details = $details; error = $null}
    } catch {
        return @{restored = 0; failed = 0; backup = $null; details = @(); error = $_.Exception.Message}
    }
}

# 导入 Windows 更新屏蔽备份（*.reg），并调用 Restore-AutoUpdate 兜底清理策略/任务
# 返回 @{ ok; details; error }
function Restore-UpdateBackup {
    param([string]$File)
    $details = @()
    try {
        if ($File -and (Test-Path -LiteralPath $File) -and $File -like '*.reg') {
            & reg import $File 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { $details += "已导入注册表备份: $File" }
            else { $details += "注册表导入退出码: $LASTEXITCODE（可能需要管理员权限）" }
        }
        $r = Restore-AutoUpdate
        foreach ($d in @($r.details)) { $details += [string]$d }
        if ($r.error) { return @{ok = $false; details = $details; error = $r.error} }
        return @{ok = $true; details = $details; error = $null}
    } catch {
        return @{ok = $false; details = $details; error = $_.Exception.Message}
    }
}

# 一键回滚：按固定顺序调用既有 Restore-* 还原，并遵守「修改必备份」红线——
#   还原前先把当前状态整体再备份一遍（可用 -SkipBackup 关闭，不推荐）。
#   Since     回到该时间点（每个域取 <= Since 的最新备份；省略则为最近的备份）
#   Last      回到最近第 N 条备份所在的时间点
#   Domain    只回滚这些域
#   File      只回滚某一个备份文件（GUI 单选）
#   DryRun    只输出「将做什么」，零副作用（连安全备份都不写）
#   SkipBackup 跳过还原前的当前状态备份
#   Force     安全备份失败时仍继续
# 返回 @{ ok; dryRun; mode; since; safetyBackups; results; skipped; error }
function Invoke-Rollback {
    param(
        [string]$BackupDir,
        [datetime]$Since = [datetime]::MinValue,
        [int]$Last = 0,
        [string[]]$Domain,
        [string]$File,
        [switch]$DryRun,
        [switch]$SkipBackup,
        [switch]$Force
    )
    $res = [PSCustomObject]@{
        ok            = $true
        dryRun        = [bool]$DryRun
        mode          = ''
        since         = $null
        safetyBackups = @()
        results       = @()
        skipped       = @()
        error         = $null
    }

    $plan = Get-RollbackPlan -BackupDir $BackupDir -Since $Since -Last $Last -Domain $Domain -File $File
    if (-not $plan.ok) {
        $res.ok = $false; $res.error = $plan.error
        return $res
    }
    $res.mode  = $plan.mode
    $res.since = $plan.since

    $bdir = Get-OptBackupDir -BackupDir $BackupDir
    # 固定回滚顺序：服务→启动项→视觉→电源→网络→遥测→更新（与依赖关系一致：先服务后启动）
    $order = @('services', 'startup', 'visual', 'power', 'network', 'telemetry', 'update')

    # 没有自动还原实现的域单独记账，保证用户看得见、不会静默吞掉
    foreach ($e in @($plan.entries)) {
        if ($order -notcontains $e.domain) {
            $res.skipped += [PSCustomObject]@{
                domain = $e.domain; domainLabel = $e.domainLabel; file = $e.file
                reason = '该域没有可用的自动还原实现，需手动处理'
            }
        }
    }

    foreach ($dom in $order) {
        $e = @($plan.entries | Where-Object { $_.domain -eq $dom } | Select-Object -First 1)[0]
        if (-not $e) { continue }

        $step = [PSCustomObject]@{
            domain       = $dom
            domainLabel  = $e.domainLabel
            file         = $e.file
            path         = $e.path
            ok           = $false
            restored     = 0
            summary      = ''
            safetyBackup = $null
            error        = $null
        }

        if ($DryRun) {
            $step.ok      = $true
            $step.summary = "将从 $($e.file) 恢复（执行前会先备份当前状态）"
            $res.results += $step
            continue
        }

        # 还原前先把当前状态备份一遍——回滚本身也要可回滚
        if (-not $SkipBackup) {
            try {
                $sb = Backup-DomainState -Domain $dom -BackupDir $bdir
                if ($sb) { $step.safetyBackup = $sb }
                else { $step.error = '无法备份当前状态' }
            } catch { $step.error = "无法备份当前状态: $($_.Exception.Message)" }
            if ($step.error -and -not $Force) {
                $res.results += $step
                continue
            }
        }

        switch ($dom) {
            'services'  { $r = Restore-Services        -BackupDir $bdir -File $e.path }
            'startup'   { $r = Restore-StartupItems    -BackupDir $bdir -File $e.path }
            'visual'    { $r = Restore-VisualEffects   -BackupDir $bdir -File $e.path }
            'power'     { $r = Restore-PowerPlan       -BackupDir $bdir -File $e.path }
            'network'   { $r = Restore-NetworkSettings -BackupDir $bdir -File $e.path }
            'telemetry' { $r = Restore-TelemetryTasks  -BackupDir $bdir -File $e.path }
            'update'    { $r = Restore-UpdateBackup    -File        $e.path }
        }

        if (-not $r) {
            $step.error = '还原函数未返回结果'
        } else {
            if ($null -ne $r.restored) { $step.restored = [int]$r.restored }
            $step.ok = [bool](-not $r.error)
            $step.summary = Format-RestoreDetails -Details $r.details -Fallback ('已完成（还原 {0} 项）' -f $step.restored)
            if ($r.error)   { $step.error = [string]$r.error }
        }
        $res.results += $step
    }

    $res.safetyBackups = @($res.results | Where-Object { $_.safetyBackup } | ForEach-Object { $_.safetyBackup })
    $failed = @($res.results | Where-Object { -not $_.ok })
    $res.ok = ($failed.Count -eq 0)
    if (@($res.results).Count -eq 0) {
        $res.ok = $false
        if (-not $res.error) { $res.error = '没有匹配的备份可回滚' }
    }
    elseif (-not $res.ok -and -not $res.error) {
        $res.error = ("有 {0} 个域还原失败，详见 results" -f $failed.Count)
    }
    return $res
}

# ============================================================
#  优化组合包 Profiles（P0-3）
#  纯编排：每一步都调用已存在的域函数，不新增任何系统操作面，
#  因此天然获得「修改必备份」与 Win7 兼容保障，三端共用同一份计划。
#  单个优化域要 5~6 次点击，不同场景（老机均衡/游戏/省电/最小干预）取舍完全不同；
#  组合包把「该禁哪些服务、动画关多少、电源切哪个、DNS 换哪家」固化成一份配置。
# ============================================================

# 组合包字段缺省值：config 未写的字段按此补全，旧 config 也能跑
function Get-ProfileDefaults {
    return [PSCustomObject]@{
        services   = 'none'
        startup    = 'none'
        visual     = 'keep'
        power      = 'keep'
        dns        = 'none'
        telemetry  = $false
        disk       = 'none'
        compact_os = $false
    }
}

# 内置组合包：config/optimization.json 的 profiles 缺失时兜底（三端永远有可用项）
function Get-BuiltinProfiles {
    return [ordered]@{
        'old_balanced' = @{
            title = '老机均衡'; desc = '通用首选：安全禁用服务、关闭动画特效、切高性能电源'
            services = 'safe'; startup = 'list'; visual = 'best_performance'; power = 'high'
            dns = 'cloudflare'; telemetry = $true; disk = 'none'; compact_os = $false
        }
        'gaming' = @{
            title = '游戏加速'; desc = '更激进：safe+recommended 服务全禁、动画全关、卓越性能、阿里 DNS'
            services = 'recommended'; startup = 'all'; visual = 'best_performance'; power = 'ultimate'
            dns = 'aliyun'; telemetry = $true; disk = 'none'; compact_os = $false
        }
        'quiet_saver' = @{
            title = '静音省电'; desc = '笔记本电池模式：仅安全禁用服务、保留基本动画、切省电计划'
            services = 'safe'; startup = 'list'; visual = 'balanced'; power = 'power_saver'
            dns = '114'; telemetry = $true; disk = 'none'; compact_os = $false
        }
        'minimal' = @{
            title = '最小干预'; desc = '几乎不动系统：仅关闭遥测计划任务，服务/动画/电源/DNS 全部保持原状'
            services = 'none'; startup = 'none'; visual = 'keep'; power = 'keep'
            dns = 'none'; telemetry = $true; disk = 'none'; compact_os = $false
        }
    }
}

# 组合包清单：config/optimization.json 的 profiles 为唯一真源，缺失时回退内置默认
function Get-Profiles {
    $src = Get-BuiltinProfiles
    try {
        $cfg = Get-OptConfig
        if ($cfg -and $cfg.profiles) {
            $src = [ordered]@{}
            foreach ($p in @($cfg.profiles.PSObject.Properties)) { $src[$p.Name] = $p.Value }
        }
    } catch { }

    $out = @()
    foreach ($k in @($src.Keys)) {
        $v  = $src[$k]
        $d  = Get-ProfileDefaults
        $pick = {
            param($Field, $Default)
            $val = $null
            if ($v -is [System.Collections.IDictionary]) {
                if ($v.Contains($Field)) { $val = $v[$Field] }
            } else {
                $prop = @($v.PSObject.Properties | Where-Object { $_.Name -eq $Field })[0]
                if ($prop) { $val = $prop.Value }
            }
            if ($null -eq $val -or [string]$val -eq '') { return $Default }
            return $val
        }
        $out += [PSCustomObject]@{
            name      = [string]$k
            title     = [string](& $pick 'title' $k)
            desc      = [string](& $pick 'desc' '')
            services  = [string](& $pick 'services'   $d.services)
            startup   = [string](& $pick 'startup'   $d.startup)
            visual    = [string](& $pick 'visual'     $d.visual)
            power     = [string](& $pick 'power'      $d.power)
            dns       = [string](& $pick 'dns'        $d.dns)
            telemetry = [bool]  (& $pick 'telemetry'  $d.telemetry)
            disk      = [string](& $pick 'disk'       $d.disk)
            compactOs = [bool]  (& $pick 'compact_os' $d.compact_os)
        }
    }
    return $out
}

function Get-Profile {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
    $n = $Name.Trim()
    foreach ($p in @(Get-Profiles)) {
        if ($p.name -ieq $n -or $p.title -ieq $n) { return $p }
    }
    return $null
}

# power 字段 -> powercfg GUID（power_saver / ultimate 需 Win7 适配，Set-PowerPlan 已有兼容层）
function Get-ProfilePowerGuid {
    param([string]$Key)
    switch ($Key) {
        'high'        { return '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' }
        'ultimate'    { return 'e9a42b02-d5df-448d-aa00-03f14749eb61' }
        'balanced'    { return '381b4222-f694-41f0-9685-ff5bb260df2e' }
        'power_saver' { return 'a1841308-3541-4fab-bc81-f71556f20b4a' }
        default {
            if ($Key -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') { return $Key }
            return $null
        }
    }
}

# 把组合包展开成「步骤清单」（plan 与 invoke 共用，保证预览与执行零漂移）
# 每步: id / domain / action / target / impact / auto / risk / params
function Get-ProfileSteps {
    param($Profile)
    $steps = @()
    if (-not $Profile) { return $steps }

    if ($Profile.services -and $Profile.services -ne 'none') {
        $mode  = 'all'
        $label = 'safe + recommended 全部'
        if ($Profile.services -eq 'safe') { $mode = 'safe'; $label = '仅安全禁用' }
        $steps += [PSCustomObject]@{
            id = 'services'; domain = '服务'; risk = $(if ($mode -eq 'safe') { 'low' } else { 'medium' }); auto = $true
            action = "禁用服务（$label）"
            target = $(if ($mode -eq 'safe') { 'config.services.safe_to_disable' } else { 'config.services 全量' })
            impact = '关闭后台服务，开机更快、内存占用更低；改前自动备份服务状态'
            params = @{ Mode = $mode }
        }
    }

    if ($Profile.startup -and $Profile.startup -ne 'none') {
        if ($Profile.startup -eq 'list') {
            $steps += [PSCustomObject]@{
                id = 'startup'; domain = '启动项'; risk = 'none'; auto = $true
                action = '仅列出启动项清单'
                target = 'Get-StartupItems'
                impact = '只读，不动手；请按清单自行决定禁用哪些'
                params = @{ ListOnly = $true }
            }
        } else {
            $steps += [PSCustomObject]@{
                id = 'startup'; domain = '启动项'; risk = 'high'; auto = $false
                action = '禁用全部启动项'
                target = 'Disable-StartupItems'
                impact = '输入法/显卡面板/云同步等也会被禁用，需逐项确认；改前自动备份'
                params = @{ ListOnly = $false }
            }
        }
    }

    if ($Profile.visual -and $Profile.visual -ne 'keep') {
        $pnum = 2; $vlabel = '平衡模式'
        if ($Profile.visual -eq 'best_performance') { $pnum = 1; $vlabel = '最佳性能' }
        $steps += [PSCustomObject]@{
            id = 'visual'; domain = '视觉效果'; risk = 'low'; auto = $true
            action = "设置视觉效果（$vlabel）"
            target = "Set-VisualEffectProfile -Profile $pnum"
            impact = '关闭动画与淡入淡出，窗口响应更快；改前自动备份注册表'
            params = @{ Profile = $pnum }
        }
    }

    if ($Profile.power -and $Profile.power -ne 'keep') {
        $guid = Get-ProfilePowerGuid -Key $Profile.power
        if ($guid) {
            $steps += [PSCustomObject]@{
                id = 'power'; domain = '电源计划'; risk = 'low'; auto = $true
                action = "切换电源计划（$($Profile.power)）"
                target = $guid
                impact = '影响 CPU 频率与休眠策略；改前自动备份当前计划'
                params = @{ Guid = $guid; UnlockUltimate = ($Profile.power -eq 'ultimate') }
            }
        }
    }

    if ($Profile.dns -and $Profile.dns -ne 'none') {
        $opt = @(Get-DnsOptions | Where-Object { $_.Key -ieq $Profile.dns })[0]
        if ($opt) {
            $steps += [PSCustomObject]@{
                id = 'network'; domain = '网络'; risk = 'low'; auto = $true
                action = ("优化网络（DNS 切到 {0}）" -f $opt.Label)
                target = ("Invoke-NetworkOptimization -DnsOption {0}" -f $opt.Value)
                impact = '可能影响内网 DNS 解析或专线访问；改前自动备份网卡 DNS 与 TCP 参数'
                params = @{ DnsOption = [int]$opt.Value }
            }
        }
    }

    if ($Profile.telemetry) {
        $steps += [PSCustomObject]@{
            id = 'telemetry'; domain = '遥测计划任务'; risk = 'low'; auto = $true
            action = '禁用遥测计划任务'
            target = 'config.telemetry_tasks'
            impact = '停止系统自动回传 diagnostic 数据；改前自动备份任务状态'
            params = @{}
        }
    }

    if ($Profile.disk -and $Profile.disk -ne 'none') {
        $steps += [PSCustomObject]@{
            id = 'disk'; domain = '磁盘'; risk = 'high'; auto = $false
            action = ("磁盘优化（TRIM/碎片整理{0}）" -f $(if ($Profile.compactOs) { ' + CompactOS' } else { '' }))
            target = 'Invoke-DiskOptimization'
            impact = '耗时数分钟；CompactOS 回滚需再跑一次 Compact.exe /CompactOS:never'
            params = @{ Compact = [bool]$Profile.compactOs }
        }
    }

    return $steps
}

# 只读预览：返回组合包将做什么，不碰系统
function Get-ProfilePlan {
    param([string]$Name)
    $p = Get-Profile -Name $Name
    if (-not $p) {
        return [PSCustomObject]@{ ok = $false; name = $Name; title = $null; desc = $null; steps = @(); error = "未找到组合包: $Name" }
    }
    $steps = @(Get-ProfileSteps -Profile $p)
    return [PSCustomObject]@{
        ok = $true; name = $p.name; title = $p.title; desc = $p.desc
        steps = $steps; error = $null
    }
}

# 执行组合包。单步失败不中断（续跑），汇总到 results
#   -WhatIf            完全零副作用（连备份都不落盘）
#   -Force             允许执行 risk=high/medium 的步骤（默认只跑 low）
function Invoke-Profile {
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$BackupDir,
        [switch]$WhatIf,
        [switch]$Force,
        # 优化前先建系统还原点（P1-3）；默认读 config 的 safety.create_restore_point
        [bool]$CreateRestorePoint = (Get-RestorePointDefault)
    )
    $plan = Get-ProfilePlan -Name $Name
    $res  = [PSCustomObject]@{
        ok       = $false
        name     = $Name
        title    = $plan.title
        desc     = $plan.desc
        dryRun   = [bool]$WhatIf
        forced   = [bool]$Force
        steps    = @($plan.steps)
        results  = @()
        skipped  = @()
        restorePoint = $null
        error    = $null
    }
    if (-not $plan.ok) { $res.error = $plan.error; return $res }

    $bkDir = $BackupDir
    if (-not $bkDir) { $bkDir = Get-OptBackupDir }

    foreach ($s in @($plan.steps)) {
        # 闸门：auto=false 或 high 风险的步骤默认跳过，必须显式 -Force 才执行；
        # low / medium 的 auto 步骤直接跑，且每个域执行前都会自动备份。
        if (-not $Force -and (-not $s.auto -or $s.risk -eq 'high')) {
            $reason = if (-not $s.auto) { "需人工确认后执行（$($s.action)）" } else { "风险级别 $($s.risk)，需 -Force" }
            $res.skipped += [PSCustomObject]@{ id = $s.id; domain = $s.domain; risk = $s.risk; reason = $reason; action = $s.action }
            continue
        }
        # 真要动系统了才建还原点（P1-3）；失败不阻塞优化。
        if (-not $WhatIf -and $CreateRestorePoint -and $null -eq $restorePoint) {
            $restorePoint = New-SystemRestorePoint -Description ("PC-Optimizer 组合包 $($plan.title) 优化前 {0:yyyy-MM-dd HH:mm}" -f (Get-Date))
            $res.restorePoint = $restorePoint
        }
        $r = [PSCustomObject]@{ id = $s.id; domain = $s.domain; action = $s.action; ok = $false; summary = ''; backup = $null; error = $null }
        try {
            switch ($s.id) {
                'services' {
                    $x = Disable-Services -Services (Get-ServiceList) -Mode $s.params.Mode -WhatIf:$WhatIf
                    $r.summary = "禁用 $($x.disabled) 项，跳过 $($x.skipped) 项"
                    $r.ok = $true
                }
                'startup' {
                    $items = @(Get-StartupItems)
                    if ($s.params.ListOnly) {
                        $r.summary = "共 $($items.Count) 个启动项，已列出（未改动）"
                        $r.ok = $true
                    } else {
                        $x = Disable-StartupItems -BackupDir $bkDir -Items $items -WhatIf:$WhatIf
                        $r.summary = "禁用 $($x.disabled) 项，失败 $($x.failed) 项"
                        $r.backup = $x.backup
                        $r.ok = $true
                    }
                }
                'visual' {
                    $x = Set-VisualEffectProfile -Profile $s.params.Profile -BackupDir $bkDir -WhatIf:$WhatIf
                    $r.summary = (@($x.details) -join ' / ')
                    $r.backup = $x.backup
                    $r.ok = [bool]$x.ok
                }
                'power' {
                    $x = Set-PowerPlan -Guid $s.params.Guid -BackupDir $bkDir -UnlockUltimate:$s.params.UnlockUltimate -FallbackToHighPerf -WhatIf:$WhatIf
                    $r.summary = (@($x.details) -join ' / ')
                    if (-not $r.summary) { $r.summary = $(if ($WhatIf) { "（预演）切换电源计划 $($s.params.Guid)" } else { "已切换电源计划 $($s.params.Guid)" }) }
                    $r.backup = $x.backup
                    $r.ok = [bool]$x.ok
                    if ($x.fallback) { $r.summary = ($r.summary + '；已回退高性能计划').Trim('；') }
                }
                'network' {
                    $x = Invoke-NetworkOptimization -BackupDir $bkDir -DnsOption $s.params.DnsOption -WhatIf:$WhatIf
                    $r.summary = (@($x.details) -join ' / ')
                    $r.ok = [bool]$x.ok
                    if (-not $x.ok -and $x.error) { $r.error = $x.error }
                }
                'telemetry' {
                    $x = Disable-TelemetryTasks -BackupDir $bkDir -WhatIf:$WhatIf
                    $r.summary = "禁用 $($x.disabled) 项，跳过 $($x.skipped) 项"
                    $r.ok = $true
                }
                'disk' {
                    $x = Invoke-DiskOptimization -BackupDir $bkDir -Compact:$s.params.Compact -WhatIf:$WhatIf
                    $r.summary = (@($x.details) -join ' / ')
                    if (-not $r.summary) { $r.summary = $(if ($WhatIf) { '（预演）执行磁盘优化' } else { '磁盘优化已执行' }) }
                    $r.ok = [bool]$x.ok
                }
                default {
                    $r.error = "未知步骤: $($s.id)"
                }
            }
        } catch {
            $r.error = $_.Exception.Message
        }
        $res.results += $r
    }

    $failed = @($res.results | Where-Object { -not $_.ok })
    $res.ok = (@($res.results).Count -gt 0 -and $failed.Count -eq 0)
    if (@($res.results).Count -eq 0) { $res.error = '该组合包没有可执行的步骤' }
    elseif (-not $res.ok) { $res.error = ("有 {0} 个步骤失败，详见 results" -f $failed.Count) }
    return $res
}

# ============================================================
#  体检趋势与定时体检（P1-1）
# ============================================================

# 把数值序列渲染成字符 sparkline。纯 ASCII 字符集，
# Win7 控制台与 GUI 等宽字体都能稳定显示（不依赖 Unicode 区块字符）。
function Format-Sparkline {
    param([double[]]$Values, [int]$Levels = 8)
    $chars = @('.', ':', '-', '=', '+', '*', '#', '%')
    $vals = @($Values | Where-Object { $null -ne $_ })
    if ($vals.Count -eq 0) { return '' }
    $min   = ($vals | Measure-Object -Minimum).Minimum
    $max   = ($vals | Measure-Object -Maximum).Maximum
    $span  = $max - $min
    $sb    = New-Object System.Text.StringBuilder
    $top   = $chars.Count - 1
    foreach ($x in $vals) {
        if ($span -le 0) {
            $null = $sb.Append($chars[[int][math]::Floor($chars.Count / 2)])
            continue
        }
        $ratio = ($x - $min) / $span
        if ($ratio -lt 0) { $ratio = 0 }
        if ($ratio -gt 1) { $ratio = 1 }
        $idx = [int][math]::Floor($ratio * $top + 0.0001)
        if ($idx -lt 0)    { $idx = 0 }
        if ($idx -gt $top) { $idx = $top }
        $null = $sb.Append($chars[$idx])
    }
    return $sb.ToString()
}

# 体检趋势：读取 backups/health 下的历史报告，按时间升序输出指标序列。
# 每点: time / score / freeRamPct / cleanableMB / startupCount / issueCount
# -Days 只保留最近 N 天；超过 -MaxPoints 时均匀抽样（末点即最新一次必保留）。
function Get-HealthTrend {
    param([string]$BackupDir, [int]$Days = 30, [int]$MaxPoints = 60)
    $dir = Join-Path (Get-OptBackupDir -BackupDir $BackupDir) 'health'
    if (-not (Test-Path $dir)) { return @() }
    $cutoff = (Get-Date).AddDays(-[math]::Abs($Days))
    $files  = @(Get-ChildItem -Path $dir -Filter 'health_*.json' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -ge $cutoff } |
                Sort-Object LastWriteTime)
    $points = @()
    foreach ($f in $files) {
        try {
            $r = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -eq $r -or $null -eq $r.score) { continue }
            $t = $f.LastWriteTime
            try { $t = [datetime]::ParseExact([string]$r.timestamp, 'yyyy-MM-dd HH:mm:ss', $null) } catch { }
            $points += [PSCustomObject]@{
                time         = $t
                score        = [int]$r.score
                freeRamPct   = [double]$r.metrics.freeRamPct
                cleanableMB  = [double]$r.metrics.cleanableMB
                startupCount = [int]$r.metrics.startupCount
                issueCount   = @($r.issues).Count
            }
        } catch { }
    }
    if ($points.Count -gt $MaxPoints -and $MaxPoints -gt 1) {
        $step    = [int][math]::Ceiling($points.Count / $MaxPoints)
        $sampled = @()
        for ($i = 0; $i -lt $points.Count; $i += $step) { $sampled += $points[$i] }
        if ($sampled[$sampled.Count - 1].time -ne $points[$points.Count - 1].time) {
            $sampled += $points[$points.Count - 1]
        }
        $points = $sampled
    }
    return $points
}

# 当前进程是否管理员身份（计划任务降级判断用）
function Test-IsAdmin {
    try {
        $id        = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($id)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

# 注册每日自动体检计划任务（schtasks.exe，Win7~Win11 通用，不依赖 ScheduledTasks 模块）
# 非管理员自动降级为「登录时触发」并在 warning 中说明；
# 注册失败只返回 error，绝不抛异常（虚拟机/域控环境容徙）。
function Install-HealthSchedule {
    param(
        [string]$TaskName = 'PCOptimizer-DailyHealthCheck',
        [string]$Time     = '09:00',
        [string]$HealthScript
    )
    if ([string]::IsNullOrWhiteSpace($HealthScript) -or -not (Test-Path -LiteralPath $HealthScript)) {
        return [PSCustomObject]@{ ok = $false; error = (“未找到体检脚本: {0}” -f $HealthScript); task = $TaskName; trigger = $null; warning = $null }
    }
    if ($Time -notmatch '^([01]?[0-9]|2[0-3]):[0-5][0-9]$') {
        return [PSCustomObject]@{ ok = $false; error = (“时间格式无效: {0}（应为 HH:mm，例如 09:00）” -f $Time); task = $TaskName; trigger = $null; warning = $null }
    }
    $isAdmin = Test-IsAdmin
    $schtasksArgs = @('/Create', '/F', '/TN', $TaskName)
    if ($isAdmin) { $schtasksArgs += @('/SC', 'DAILY', '/ST', $Time) }
    else          { $schtasksArgs += @('/SC', 'ONLOGON') }
    $schtasksArgs += @('/TR', ('powershell -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $HealthScript))
    try {
        $out = & schtasks.exe @schtasksArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            return [PSCustomObject]{
                ok = $false; error = (“schtasks 退出码 {0}: {1}” -f $LASTEXITCODE, (($out | Out-String).Trim()))
                task = $TaskName; trigger = $null; warning = $null
            }
        }
    } catch {
        return [PSCustomObject]@{ ok = $false; error = $_.Exception.Message; task = $TaskName; trigger = $null; warning = $null }
    }
    $trigger = if ($isAdmin) { “每日 $Time” } else { '登录时' }
    $warning = if ($isAdmin) { $null } else { '当前非管理员，已降级为「登录时触发」（每日定时需管理员权限）' }
    return [PSCustomObject]@{ ok = $true; error = $null; warning = $warning; task = $TaskName; trigger = $trigger }
}

# 删除自动体检计划任务；任务不存在时视为成功（幂等）
function Remove-HealthSchedule {
    param([string]$TaskName = 'PCOptimizer-DailyHealthCheck')
    try {
        $null = & schtasks.exe /Query /TN $TaskName 2>&1
        if ($LASTEXITCODE -ne 0) {
            return [PSCustomObject]@{ ok = $true; removed = $false; error = $null; task = $TaskName }
        }
        $out = & schtasks.exe /Delete /TN $TaskName /F 2>&1
        if ($LASTEXITCODE -ne 0) {
            return [PSCustomObject]@{ ok = $false; removed = $false; error = (($out | Out-String).Trim()); task = $TaskName }
        }
        return [PSCustomObject]@{ ok = $true; removed = $true; error = $null; task = $TaskName }
    } catch {
        return [PSCustomObject]@{ ok = $false; removed = $false; error = $_.Exception.Message; task = $TaskName }
    }
}

# ============================================================
#  前后对比报告导出（P1-2）
# ============================================================

# 将前后对比结果导出为自包含单文件（HTML / Markdown）。
# 用途：发帖求助、优化前后效果证明。HTML 内联全部 CSS，零外链依赖。
# 参数 -From/-To 支持：报告对象 / health JSON 文件路径；省略时自动取最新一对。
function Export-HealthReport {
    param(
        $From,
        $To,
        [ValidateSet('Html', 'Markdown')][string]$Format = 'Html',
        [string]$BackupDir,
        [string]$OutDir,
        [string]$FileName
    )
    $resolve = {
        param($Item)
        if ($null -eq $Item) { return $null }
        if ($Item -is [string]) {
            if (-not (Test-Path -LiteralPath $Item)) { return $null }
            try { return (Get-Content -LiteralPath $Item -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
        }
        return $Item
    }
    $before = & $resolve $From
    $after  = & $resolve $To
    if ((-not $before -or -not $after) -and $BackupDir) {
        $hist = @(Get-HealthHistory -BackupDir $BackupDir -Count 2)
        if (-not $after  -and $hist.Count -ge 1) { $after  = & $resolve $hist[0].FullName }
        if (-not $before -and $hist.Count -ge 2) { $before = & $resolve $hist[1].FullName }
    }
    if (-not $before -or -not $after) {
        return [PSCustomObject]@{ ok = $false; error = '需要两份体检报告（From/To）才能导出对比'; file = $null; format = $Format }
    }
    $cmp = Compare-HealthReports -Before $before -After $after
    if (-not $cmp) {
        return [PSCustomObject]@{ ok = $false; error = '对比失败：报告缺失 score/metrics 字段'; file = $null; format = $Format }
    }

    $dir = $OutDir
    if ([string]::IsNullOrWhiteSpace($dir)) {
        $dir = [Environment]::GetFolderPath('Desktop')
        if ([string]::IsNullOrWhiteSpace($dir) -or -not (Test-Path $dir)) { $dir = $env:USERPROFILE }
    }
    if (-not (Test-Path $dir)) {
        try { New-Item -ItemType Directory -Path $dir -Force | Out-Null } catch {
            return [PSCustomObject]@{ ok = $false; error = "无法创建输出目录: $($_.Exception.Message)"; file = $null; format = $Format }
        }
    }
    $name = $FileName
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = ('health-compare_{0:yyyyMMdd_HHmmss}.{1}' -f (Get-Date), $(if ($Format -eq 'Html') { 'html' } else { 'md' }))
    }
    $outFile = Join-Path $dir $name
    $body = if ($Format -eq 'Html') { ConvertTo-HealthCompareHtml -Comparison $cmp } else { ConvertTo-HealthCompareMarkdown -Comparison $cmp }
    try {
        [System.IO.File]::WriteAllText($outFile, $body, (New-Object System.Text.UTF8Encoding($false)))
    } catch {
        return [PSCustomObject]@{ ok = $false; error = "写入失败: $($_.Exception.Message)"; file = $null; format = $Format }
    }
    return [PSCustomObject]@{ ok = $true; error = $null; file = $outFile; format = $Format; comparison = $cmp }
}

# --- 内部：对比结果 -> Markdown ---
function ConvertTo-HealthCompareMarkdown {
    param($Comparison)
    $c = $Comparison
    $sign = if ($c.scoreDelta -gt 0) { "+$($c.scoreDelta)" } else { "$($c.scoreDelta)" }
    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine("# 系统体检前后对比报告")
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("- 优化前：**$($c.beforeScore) 分**（$($c.beforeTime)）")
    $null = $sb.AppendLine("- 优化后：**$($c.afterScore) 分**（$($c.afterTime)）")
    $null = $sb.AppendLine("- 分数变化：**$sign**")
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("## 指标对比")
    $null = $sb.AppendLine("")
    if (@($c.metricDeltas).Count -eq 0) {
        $null = $sb.AppendLine("无可对比的数值指标变化。")
    } else {
        $null = $sb.AppendLine("| 指标 | 优化前 | 优化后 | 变化 |")
        $null = $sb.AppendLine("|------|--------|--------|------|")
        foreach ($d in @($c.metricDeltas)) {
            $ds = if ($d.delta -gt 0) { "+$($d.delta)" } else { "$($d.delta)" }
            $null = $sb.AppendLine("| $($d.metric) | $($d.before) | $($d.after) | $ds |")
        }
    }
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("## 已解决的问题（$(@($c.resolved).Count) 项）")
    $null = $sb.AppendLine("")
    if (@($c.resolved).Count -eq 0) { $null = $sb.AppendLine("无") }
    foreach ($i in @($c.resolved)) { $null = $sb.AppendLine("- [$($i.severity)] $($i.title)") }
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("## 新墟问题（$(@($c.new).Count) 项）")
    $null = $sb.AppendLine("")
    if (@($c.new).Count -eq 0) { $null = $sb.AppendLine("无") }
    foreach ($i in @($c.new)) { $null = $sb.AppendLine("- [$($i.severity)] $($i.title)") }
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("---")
    $null = $sb.AppendLine("由 PC-Optimizer-7thGen 体检对比生成（只读报告，不含任何个人隐私数据）。")
    return $sb.ToString()
}

# --- 内部：对比结果 -> 自包含 HTML（全内联 CSS）---
function ConvertTo-HealthCompareHtml {
    param($Comparison)
    $c  = $Comparison
    $e  = { param([string]$s) [System.Net.WebUtility]::HtmlEncode([string]$s) }
    $sign = if ($c.scoreDelta -gt 0) { "+$($c.scoreDelta)" } else { "$($c.scoreDelta)" }
    $dcls = if ($c.scoreDelta -gt 0) { 'up' } elseif ($c.scoreDelta -lt 0) { 'down' } else { 'flat' }
    $rows = New-Object System.Text.StringBuilder
    foreach ($d in @($c.metricDeltas)) {
        $ds = if ($d.delta -gt 0) { "+$($d.delta)" } else { "$($d.delta)" }
        $null = $rows.Append($(
            "<tr><td>$(& $e $d.metric)</td><td>$(& $e "$($d.before)")</td><td>$(& $e "$($d.after)")</td><td class='num'>$ds</td></tr>"))
    }
    if ($rows.Length -eq 0) {
        $null = $rows.Append("<tr><td colspan='4' class='muted'>无可对比的数值指标变化</td></tr>")
    }
    $resolvedHtml = New-Object System.Text.StringBuilder
    foreach ($i in @($c.resolved)) {
        $null = $resolvedHtml.Append("<li><span class='tag ok'>$(& $e $i.severity)</span> $(& $e $i.title)<div class='muted'>$(& $e $i.detail)</div></li>")
    }
    if ($resolvedHtml.Length -eq 0) { $null = $resolvedHtml.Append("<li class='muted'>无</li>") }
    $newHtml = New-Object System.Text.StringBuilder
    foreach ($i in @($c.new)) {
        $null = $newHtml.Append("<li><span class='tag bad'>$(& $e $i.severity)</span> $(& $e $i.title)<div class='muted'>$(& $e $i.detail)</div></li>")
    }
    if ($newHtml.Length -eq 0) { $null = $newHtml.Append("<li class='muted'>无</li>") }
    $gen = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $html = @'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>系统体检前后对比报告</title>
<style>
  :root { color-scheme: light dark; }
  * { box-sizing: border-box; }
  body { margin: 0; padding: 24px; font: 14px/1.6 "Segoe UI", "Microsoft YaHei", system-ui, sans-serif; background: #f3f5f9; color: #1f2733; }
  .wrap { max-width: 860px; margin: 0 auto; }
  .card { background: #fff; border: 1px solid #e4e8ee; border-radius: 12px; padding: 20px 24px; margin-bottom: 16px; box-shadow: 0 1px 3px rgba(16,24,40,.06); }
  h1 { font-size: 20px; margin: 0 0 4px; }
  h2 { font-size: 15px; margin: 0 0 12px; color: #344054; }
  .muted { color: #667085; font-size: 12px; }
  .scores { display: flex; align-items: baseline; gap: 18px; flex-wrap: wrap; }
  .score { font-size: 40px; font-weight: 700; }
  .delta { font-size: 22px; font-weight: 700; }
  .up { color: #12925a; } .down { color: #d92d20; } .flat { color: #667085; }
  .num { font-variant-numeric: tabular-nums; font-weight: 600; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; }
  th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid #eef1f5; }
  th { color: #667085; font-weight: 600; }
  ul { margin: 0; padding-left: 18px; }
  li { margin-bottom: 8px; }
  .tag { display: inline-block; min-width: 52px; text-align: center; padding: 1px 8px; border-radius: 999px; font-size: 12px; margin-right: 8px; }
  .tag.ok  { background: #e7f6ee; color: #12925a; }
  .tag.bad { background: #fdecea; color: #d92d20; }
  footer { text-align: center; }
  @media (prefers-color-scheme: dark) {
    body { background: #101418; color: #e6e9ee; }
    .card { background: #171c22; border-color: #2a3138; box-shadow: none; }
    h2 { color: #aeb6c2; } th { color: #98a2b3; } th, td { border-color: #262c33; }
  }
</style>
</head>
<body><div class="wrap">
  <div class="card">
    <h1>系统体检前后对比报告</h1>
    <div class="muted">生成于 __GEN__ · PC-Optimizer-7thGen</div>
  </div>
  <div class="card">
    <h2>总分变化</h2>
    <div class="scores">
      <span class="score">__BEFORE__</span><span class="muted">优化前</span>
      <span class="muted">→</span>
      <span class="score">__AFTER__</span><span class="muted">优化后</span>
      <span class="delta __DCLS__">__SIGN__</span>
    </div>
  </div>
  <div class="card">
    <h2>指标对比</h2>
    <table><thead><tr><th>指标</th><th>优化前</th><th>优化后</th><th>变化</th></tr></thead>
    <tbody>__ROWS__</tbody></table>
  </div>
  <div class="card">
    <h2>已解决的问题</h2>
    <ul>__RESOLVED__</ul>
  </div>
  <div class="card">
    <h2>新墟问题</h2>
    <ul>__NEW__</ul>
  </div>
  <footer class="muted">本报告由只读体检数据生成，不含任何个人隐私数据。</footer>
</div></body>
</html>
'@
    $html = $html.Replace('__GEN__', $gen).Replace('__BEFORE__', [string]$c.beforeScore).Replace('__AFTER__', [string]$c.afterScore).Replace('__DCLS__', $dcls).Replace('__SIGN__', $sign).Replace('__ROWS__', $rows.ToString()).Replace('__RESOLVED__', $resolvedHtml.ToString()).Replace('__NEW__', $newHtml.ToString())
    return $html
}


# ============================================================
#  优化前自动创建系统还原点（P1-3）
# ============================================================
# 系统还原点是“改坏了还能退回上一版”的最后一道保险：
# 备份文件只覆盖自己动过的那些键值，还原点是整机快照。
# 默认关闭（config 的 safety.create_restore_point）——很多老机器上
# System Restore 本是关着的，感觉上打开会占掉几个 GB 磁盘，不能用户不知情。
# 创建失败只警告、不阻塞：非管理员 / SR 被禁用 / 24 小时内已建过
# 这三种情形都会失败，到时拦住用户优化比不建还原点更糟。

# 默认值唯一来源：config/optimization.json 的 safety.create_restore_point
function Get-RestorePointDefault {
    $cfg = Get-OptConfig
    if ($cfg -and $cfg.safety -and ($cfg.safety.PSObject.Properties.Name -contains 'create_restore_point')) {
        return [bool]$cfg.safety.create_restore_point
    }
    return $false
}

# 系统还原是否处于可用状态；判断不出时按“可用”处理，交给 API 去决定。
# 只读注册表，不会改动任何设置——SR 被关掉时我们返回 false 告诉命令行展示。
function Test-SystemRestoreEnabled {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore'
    )
    foreach ($rp in $paths) {
        try {
            if (-not (Test-Path -LiteralPath $rp)) { continue }
            $v = Get-ItemProperty -LiteralPath $rp -ErrorAction SilentlyContinue
            if ($null -eq $v) { continue }
            if ($v.PSObject.Properties.Name -contains 'DisableSR') {
                if ([int]$v.DisableSR -ne 0) { return $false }
            }
        } catch {
            # 读不到就当没限制，不因为读注册表失败而影响优化
        }
    }
    return $true
}

# 创建系统还原点：先 Checkpoint-Computer（Win8+），失败再退 WMI SystemRestore（Win7 可用）。
# 返回 @{ok; method; name; error; returnValue; whatIf}＋异常不往外抔。
function New-SystemRestorePoint {
    param(
        [string]$Description = 'PC-Optimizer 优化前自动还原点',
        [int]$RestorePointType = 12,
        [switch]$WhatIf
    )

    $res = [PSCustomObject]@{
        ok          = $false
        whatIf      = [bool]$WhatIf
        method      = $null
        name        = $Description
        error       = $null
        returnValue = $null
    }

    # 预演不能真建还原点（那就不只读了），但要把结果给出去，让 UI 能告诉用户“会建”。
    if ($WhatIf) {
        $res.ok     = $true
        $res.method = 'WhatIf'
        return $res
    }

    if (-not (Test-IsAdmin)) {
        $res.error = '创建系统还原点需要管理员权限（请以管理员身份运行）'
        return $res
    }
    if (-not (Test-SystemRestoreEnabled)) {
        $res.error = '系统还原已被关闭或被组策略禁用，跳过创建（可在「系统属性→系统保护」中开启）'
        return $res
    }

    $cpError = $null
    if (Get-Command Checkpoint-Computer -ErrorAction SilentlyContinue) {
        try {
            Checkpoint-Computer -Description $Description -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
            $res.ok     = $true
            $res.method = 'Checkpoint-Computer'
            return $res
        } catch {
            $cpError = $_.Exception.Message
        }
    }

    try {
        $sr = [WMIClass]("\\" + $env:COMPUTERNAME + "\root\default:SystemRestore")
        $rc = $sr.CreateRestorePoint($Description, $RestorePointType, 100)
        $rv = [int]$rc.ReturnValue
        $res.returnValue = $rv
        if ($rv -eq 0) {
            $res.ok     = $true
            $res.method = 'WMI SystemRestore'
            return $res
        }
        # 非 0 就是失败；常见的是系统节流（24h 内只让建一个还原点）、空间不足
        $res.error = "WMI SystemRestore.CreateRestorePoint 返回码 $rv"
    } catch {
        $res.error = "调用 WMI SystemRestore 失败: $($_.Exception.Message)"
    }
    if ($cpError) { $res.error = ($res.error + '；Checkpoint-Computer: ' + $cpError) }
    return $res
}

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

    if (-not $SkipBackup) {
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
                if (-not (Test-Path $moveDir)) { New-Item -ItemType Directory -Path $moveDir -Force | Out-Null }
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

    if ($BackupDir) { $res.backup = Backup-VisualEffects -BackupDir $BackupDir }

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

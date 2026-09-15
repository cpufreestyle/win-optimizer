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

# 备份当前电源计划（powercfg /query 全文），返回备份文件路径
function Backup-PowerPlan {
    param([string]$BackupDir)
    $dir = Get-OptBackupDir -BackupDir $BackupDir
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $file = Join-Path $dir ('power_backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.txt')
    try { powercfg /query 2>&1 | Out-File -FilePath $file -Encoding UTF8 } catch { }
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

    if ($BackupDir -and -not $SkipBackup) { $res.backup = Backup-PowerPlan -BackupDir $BackupDir }

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
        return [PSCustomObject]@{ ok = $false; error = '未检测到活动网络适配器'; backup = $null; details = @(); adapters = 0 }
    }

    $details = @()
    $backup  = $null
    $ok      = $true

    # 统一先备份（此前 GUI / WebUI 完全没有备份，改坏无法恢复）
    if (-not $SkipBackup) {
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
# 返回 @{ok;details;volumes;mediaMap}
function Invoke-DiskOptimization {
    param(
        [bool]$Trim = $true,
        [bool]$Defrag = $true,
        [bool]$WinSxS = $true,
        [bool]$Compact = $false,
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

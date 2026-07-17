<#
.SYNOPSIS
    PC-Optimizer-7thGen GUI 版本
.DESCRIPTION
    基于 Windows Forms 的现代化深色主题 GUI，兼容 PowerShell 5.1。
#>

# ============================================================
#  加载程序集（必须在 trap 之前，否则 trap 中无法使用 WinForms）
# ============================================================
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Data")

# ============================================================
#  全局错误捕获（PS2EXE -noConsole 模式下静默崩溃的防护）
# ============================================================
trap {
    $errFile = Join-Path ([System.AppDomain]::CurrentDomain.BaseDirectory.TrimEnd('\', '/')) "crash.log"
    $errMsg = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] CRASH: $($_.Exception.Message)`r`nLine: $($_.InvocationInfo.ScriptLineNumber)`r`nText: $($_.InvocationInfo.Line)`r`n`r`n"
    try { [System.IO.File]::AppendAllText($errFile, $errMsg, [System.Text.Encoding]::UTF8) } catch {}
    try {
        [System.Windows.Forms.MessageBox]::Show("程序出错: $($_.Exception.Message)", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    } catch {}
    break
}

# ============================================================
#  全局变量
# ============================================================
# PS2EXE 兼容：多级回退获取项目根目录
if ($PSScriptRoot) {
    $script:ProjectRoot = $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    $script:ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    # PS2EXE 编译后最终回退：使用 AppDomain 基目录
    $script:ProjectRoot = [System.AppDomain]::CurrentDomain.BaseDirectory.TrimEnd('\', '/')
}
$script:ScriptsDir  = Join-Path $script:ProjectRoot "scripts"
$script:BackupDir   = Join-Path $script:ProjectRoot "backups"
$script:LogFile     = Join-Path $script:ProjectRoot "optimize.log"
$script:Version     = "2.1.0"

# ============================================================
#  Win7 兼容性检测
# ============================================================
$script:OSVersion = [System.Environment]::OSVersion.Version
$script:IsWin7 = $script:OSVersion.Major -eq 6 -and $script:OSVersion.Minor -le 1
$script:PSVersion = $PSVersionTable.PSVersion.Major

# ============================================================
#  兼容性辅助函数（Win7/PS2 回退）
# ============================================================
function Get-CimData {
    param([string]$Class, [string]$Filter = $null)
    if ($script:PSVersion -ge 3) {
        if ($Filter) { return @(Get-CimInstance -ClassName $Class -Filter $Filter -ErrorAction SilentlyContinue) }
        else { return @(Get-CimInstance -ClassName $Class -ErrorAction SilentlyContinue) }
    } else {
        if ($Filter) { return @(Get-WmiObject -Class $Class -Filter $Filter -ErrorAction SilentlyContinue) }
        else { return @(Get-WmiObject -Class $Class -ErrorAction SilentlyContinue) }
    }
}

function Invoke-UIRefresh {
    # 防止 UI 卡死：在长操作中调用
    try { [System.Windows.Forms.Application]::DoEvents() } catch {}
    try { Start-Sleep -Milliseconds 10 } catch {}
}

function Clear-RecycleBinCompat {
    if ($script:PSVersion -ge 5) {
        try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}
    } else {
        # Win7/PS2 回退：用 COM 对象清空回收站
        try {
            $shell = New-Object -ComObject Shell.Application
            $recycleBin = $shell.Namespace(0xa)
            if ($recycleBin) {
                $items = $recycleBin.Items()
                foreach ($item in $items) {
                    try { Remove-Item -Path $item.Path -Recurse -Force -ErrorAction SilentlyContinue } catch {}
                }
            }
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
        } catch {}
    }
}

function Get-ScheduledTaskCompat {
    param([string]$TaskPath, [string]$TaskName)
    # Win7 回退：用 schtasks.exe 查询
    $output = schtasks /Query /TN "$($TaskPath)$($TaskName)" 2>&1
    return ($LASTEXITCODE -eq 0)
}

function Disable-ScheduledTaskCompat {
    param([string]$TaskPath, [string]$TaskName)
    if ($script:PSVersion -ge 3 -and -not $script:IsWin7) {
        try { Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null; return $true } catch { return $false }
    } else {
        try { schtasks /Change /TN "$($TaskPath)$($TaskName)" /DISABLE 2>&1 | Out-Null; return ($LASTEXITCODE -eq 0) } catch { return $false }
    }
}

function Get-PhysicalDiskCompat {
    # Win7 回退：用 WMI
    return @(Get-CimData Win32_DiskDrive | Select-Object @{N='DeviceId';E={$_.Index}}, @{N='FriendlyName';E={$_.Model}}, @{N='MediaType';E={ if($_.MediaType -like '*Fixed*' -or $_.MediaType -like '*Hard*') { 'HDD' } else { 'Unknown' } }}, @{N='Size';E={$_.Size}})
}

function Get-VolumeCompat {
    return @(Get-CimData Win32_LogicalDisk -Filter "DriveType=3" | Select-Object @{N='DriveLetter';E={$_.DeviceID.Substring(0,1)}}, @{N='DriveType';E={'Fixed'}}, @{N='Size';E={$_.Size}}, @{N='SizeRemaining';E={$_.FreeSpace}})
}

function Optimize-VolumeCompat {
    param([string]$DriveLetter, [switch]$ReTrim, [switch]$Defrag)
    $drive = "$($DriveLetter):"
    if ($ReTrim) {
        # SSD TRIM - 用 defrag /L (Win7 不支持，静默跳过)
        if (-not $script:IsWin7) {
            try { defrag $drive /L /O 2>&1 | Out-Null } catch {}
        }
    }
    if ($Defrag) {
        try { defrag $drive /D 2>&1 | Out-Null } catch {}
    }
}

function Get-NetAdapterCompat {
    return @(Get-CimData Win32_NetworkAdapter -Filter "NetEnabled=True" | Select-Object @{N='Name';E={$_.NetConnectionID}}, @{N='ifIndex';E={$_.InterfaceIndex}}, @{N='InterfaceDescription';E={$_.Description}})
}

function Set-DnsCompat {
    param([string]$InterfaceName, [string[]]$DnsServers)
    if ($DnsServers -and $DnsServers.Count -gt 0) {
        $dnsStr = $DnsServers -join ','
        # 用 netsh 设置 DNS（Win7 兼容）
        netsh interface ip set dns name="$InterfaceName" static $DnsServers[0] 2>&1 | Out-Null
        if ($DnsServers.Count -gt 1) {
            netsh interface ip add dns name="$InterfaceName" $DnsServers[1] index=2 2>&1 | Out-Null
        }
    }
}

function Get-DnsClientServerAddressCompat {
    $result = @()
    $adapters = Get-CimData Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True"
    foreach ($adapter in $adapters) {
        if ($adapter.DNSServerSearchOrder -and $adapter.DNSServerSearchOrder.Count -gt 0) {
            $result += [PSCustomObject]@{
                InterfaceAlias = $adapter.Description
                ServerAddresses = $adapter.DNSServerSearchOrder
            }
        }
    }
    return $result
}

function Enable-NetAdapterRssCompat {
    # Win7 回退：用 netsh
    try { netsh int tcp set global rss=enabled 2>&1 | Out-Null } catch {}
}

function Enable-NetAdapterRscCompat {
    # Win7 回退：用 netsh
    try { netsh int tcp set global rsc=enabled 2>&1 | Out-Null } catch {}
}

function Clear-DnsClientCacheCompat {
    try { ipconfig /flushdns 2>&1 | Out-Null } catch {}
}

# ============================================================
#  颜色主题（深色主题）
# ============================================================
$script:Theme = @{
    BgDark       = [System.Drawing.Color]::FromArgb(30, 30, 40)
    BgPanel      = [System.Drawing.Color]::FromArgb(45, 45, 58)
    BgCard       = [System.Drawing.Color]::FromArgb(52, 52, 68)
    BgInput      = [System.Drawing.Color]::FromArgb(60, 60, 78)
    Accent       = [System.Drawing.Color]::FromArgb(0, 150, 255)
    AccentDark   = [System.Drawing.Color]::FromArgb(0, 110, 200)
    AccentHover  = [System.Drawing.Color]::FromArgb(0, 170, 255)
    TextMain     = [System.Drawing.Color]::FromArgb(235, 235, 245)
    TextDim      = [System.Drawing.Color]::FromArgb(160, 160, 180)
    TextBright   = [System.Drawing.Color]::FromArgb(255, 255, 255)
    Success      = [System.Drawing.Color]::FromArgb(80, 200, 120)
    Warning      = [System.Drawing.Color]::FromArgb(255, 180, 60)
    Error        = [System.Drawing.Color]::FromArgb(240, 90, 90)
    SideActive   = [System.Drawing.Color]::FromArgb(0, 150, 255)
    SideHover    = [System.Drawing.Color]::FromArgb(55, 55, 72)
}

# ============================================================
#  字体
# ============================================================
$script:Fonts = @{
    Title   = New-Object System.Drawing.Font("Microsoft YaHei UI", 20, [System.Drawing.FontStyle]::Bold)
    Header  = New-Object System.Drawing.Font("Microsoft YaHei UI", 14, [System.Drawing.FontStyle]::Bold)
    Sub     = New-Object System.Drawing.Font("Microsoft YaHei UI", 11, [System.Drawing.FontStyle]::Regular)
    Body    = New-Object System.Drawing.Font("Microsoft YaHei UI", 10, [System.Drawing.FontStyle]::Regular)
    Small   = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Regular)
    Mono    = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Regular)
}

# ============================================================
#  工具函数
# ============================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    # PS2EXE 兼容：用 .NET 方法替代 Add-Content
    try { [System.IO.File]::AppendAllText($script:LogFile, "$line`r`n", [System.Text.Encoding]::UTF8) } catch {}
    # 同时输出到 GUI 日志（必须检查 IsHandleCreated，否则 PS2EXE 启动时崩溃）
    if ($script:LogTextBox -and -not $script:LogTextBox.IsDisposed -and $script:LogTextBox.IsHandleCreated) {
        $color = switch ($Level) {
            "ERROR"   { $Theme.Error }
            "WARN"    { $Theme.Warning }
            "SUCCESS" { $Theme.Success }
            default   { $Theme.TextDim }
        }
        try {
            $script:LogTextBox.Invoke([Action]{
                $script:LogTextBox.SelectionStart = $script:LogTextBox.TextLength
                $script:LogTextBox.SelectionColor = $color
                $script:LogTextBox.AppendText("$line`n")
                $script:LogTextBox.ScrollToCaret()
            })
        } catch {}
    }
}

function Test-Administrator {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-FolderSize {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    try {
        $size = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($null -eq $size) { return 0 }
        return $size
    } catch { return 0 }
}

function Invoke-ScriptModule {
    param([string]$ScriptName)
    $scriptPath = Join-Path $script:ScriptsDir $ScriptName
    if (Test-Path $scriptPath) {
        Write-Log "执行模块: $ScriptName"
        & $scriptPath
        Write-Log "模块 $ScriptName 完成" "SUCCESS"
    } else {
        Write-Log "找不到模块文件: $scriptPath" "ERROR"
    }
}

# ============================================================
#  一键优化：各页面执行逻辑抽取（单页按钮与一键按钮共用）
# ============================================================
function Invoke-CleanOptimization {
    $totalFreed = 0
    $filesDeleted = 0
    for ($i = 0; $i -lt $script:CleanItems.Count; $i++) {
        if ($script:CleanListBox.GetItemChecked($i)) {
            $item = $script:CleanItems[$i]
            $before = Get-FolderSize $item.Path
            if (Test-Path $item.Path) {
                Get-ChildItem -Path $item.Path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    try { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue; $filesDeleted++ } catch {}
                }
                $after = Get-FolderSize $item.Path
                $freed = $before - $after
                $totalFreed += $freed
                Write-Log "[清理] $($item.Name): 释放 $([math]::Round($freed/1MB,2)) MB" "SUCCESS"
            }
        }
        Invoke-UIRefresh
    }
    if ($script:ChkRecycle.Checked) { Clear-RecycleBinCompat; Write-Log "[清理] 回收站已清空" "SUCCESS" }
    if ($script:ChkDNS.Checked) { try { ipconfig /flushdns | Out-Null; Write-Log "[清理] DNS 缓存已清除" "SUCCESS" } catch {} }
    if ($script:ChkDump.Checked) {
        $dumpFiles = @("C:\Windows\MEMORY.DMP")
        $dumpFiles += (Get-ChildItem "C:\Windows\Minidump" -ErrorAction SilentlyContinue).FullName
        foreach ($dump in $dumpFiles) {
            if ($dump -and (Test-Path $dump)) {
                $totalFreed += (Get-Item $dump).Length
                Remove-Item $dump -Force -ErrorAction SilentlyContinue
                Write-Log "[清理] 删除转储文件: $(Split-Path $dump -Leaf)" "SUCCESS"
            }
        }
    }
    $totalMB = [math]::Round($totalFreed / 1MB, 2)
    $totalGB = [math]::Round($totalFreed / 1GB, 2)
    $msg = if ($totalGB -ge 1) { "共释放 ${totalGB} GB 空间" } else { "共释放 ${totalMB} MB 空间" }
    Write-Log "清理完成！$msg，删除 $filesDeleted 个文件" "SUCCESS"
    return "清理完成，$msg，删除 $filesDeleted 个文件"
}

function Invoke-ServicesOptimization {
    if (-not (Test-Path $script:BackupDir)) { New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null }
    $backupFile = Join-Path $script:BackupDir "services_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $backupData = @()
    for ($i = 0; $i -lt $script:SvcDataTable.Rows.Count; $i++) {
        $svcName = $script:SvcDataTable.Rows[$i]["服务名称"]
        $service = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($service) {
            $svcWmi = @(Get-CimData Win32_Service -Filter "Name='$svcName'")[0]
            $startMode = if ($svcWmi) { $svcWmi.StartMode } else { "Unknown" }
            $backupData += [PSCustomObject]@{ Name=$svcName; Status=$service.Status; StartType=$startMode; Date=(Get-Date -Format "yyyy-MM-dd HH:mm:ss") }
        }
        Invoke-UIRefresh
    }
    $backupData | Export-Csv -Path $backupFile -NoTypeInformation -Encoding UTF8
    Write-Log "服务备份已保存: $backupFile"

    $disabledCount = 0
    for ($i = 0; $i -lt $script:SvcDataTable.Rows.Count; $i++) {
        if ($script:SvcDataTable.Rows[$i]["选择"] -eq $true) {
            $svcName = $script:SvcDataTable.Rows[$i]["服务名称"]
            $service = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($service) {
                try {
                    if ($service.Status -eq "Running") {
                        Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
                        Start-Sleep -Milliseconds 300
                    }
                    Set-Service -Name $svcName -StartupType Disabled -ErrorAction Stop
                    Write-Log "[禁用] $svcName" "SUCCESS"
                    $disabledCount++
                    $script:SvcDataTable.Rows[$i]["状态"] = "Stopped"
                } catch {
                    Write-Log "[失败] $svcName — $($_.Exception.Message)" "ERROR"
                }
            }
        }
        Invoke-UIRefresh
    }

    if ($script:chkTelemetry.Checked) {
        $telemetryTasks = @(
            @{Path="\Microsoft\Windows\Application Experience\"; Name="Microsoft Compatibility Appraiser"},
            @{Path="\Microsoft\Windows\Application Experience\"; Name="ProgramDataUpdater"},
            @{Path="\Microsoft\Windows\Customer Experience Improvement Program\"; Name="Consolidator"},
            @{Path="\Microsoft\Windows\Customer Experience Improvement Program\"; Name="UsbCeip"}
        )
        foreach ($task in $telemetryTasks) {
            try {
                $r = Disable-ScheduledTaskCompat -TaskPath $task.Path -TaskName $task.Name
                if ($r) { Write-Log "[禁用] 计划任务: $($task.Name)" "SUCCESS" }
            } catch {}
        }
    }

    Write-Log "服务优化完成！已禁用 $disabledCount 个服务" "SUCCESS"
    return "已禁用 $disabledCount 个服务"
}

function Invoke-StartupOptimization {
    param([switch]$DisableAll)
    if (-not $DisableAll -and $script:DgvStartup.SelectedRows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("请先选择要禁用的启动项（点击行左侧选择整行）", "提示", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        return $null
    }
    if (-not (Test-Path $script:BackupDir)) { New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null }
    $backupFile = Join-Path $script:BackupDir "startup_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $toRemove = @()
    if ($DisableAll) {
        $toRemove = $script:StartupItems
    } else {
        foreach ($row in $script:DgvStartup.SelectedRows) {
            $idx = $row.Index
            $toRemove += $script:StartupItems[$idx]
        }
    }
    $toRemove | Select-Object Name, Command, Scope, Source | Export-Csv -Path $backupFile -NoTypeInformation -Encoding UTF8
    Write-Log "启动项备份: $backupFile"
    $count = 0
    foreach ($item in $toRemove) {
        try {
            if ($item.Source -eq "注册表") {
                Remove-ItemProperty -Path $item.RegPath -Name $item.Name -ErrorAction Stop
                Write-Log "[禁用] $($item.Name) (注册表)" "SUCCESS"
                $count++
            } elseif ($item.Source -eq "启动文件夹") {
                $backupDir2 = Join-Path $script:BackupDir "startup_items"
                if (-not (Test-Path $backupDir2)) { New-Item -ItemType Directory -Path $backupDir2 -Force | Out-Null }
                Move-Item -Path $item.Command -Destination (Join-Path $backupDir2 (Split-Path $item.Command -Leaf)) -Force -ErrorAction Stop
                Write-Log "[禁用] $($item.Name) (启动文件夹)" "SUCCESS"
                $count++
            }
        } catch {
            Write-Log "[失败] $($item.Name)" "ERROR"
        }
        Invoke-UIRefresh
    }
    Write-Log "启动项优化完成！已禁用 $count 项" "SUCCESS"
    return "已禁用 $count 个启动项"
}

function Invoke-VisualOptimization {
    $selectedMode = 1
    for ($i = 0; $i -lt 3; $i++) { if ($script:radioBtns[$i].Checked) { $selectedMode = $script:modes[$i].Value } }
    if (-not (Test-Path $script:BackupDir)) { New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null }
    $visualKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    if (-not (Test-Path $visualKey)) { New-Item -Path $visualKey -Force | Out-Null }
    $perfKey = "HKCU:\Control Panel\Desktop"
    $advKey  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    $dwmKey  = "HKCU:\Software\Microsoft\Windows\DWM"
    Set-ItemProperty -Path $visualKey -Name "VisualFXSetting" -Value 3 -Type DWord
    Set-ItemProperty -Path $advKey -Name "TaskbarAnimations" -Value 0 -Type DWord -ErrorAction SilentlyContinue
    $modeName = switch ($selectedMode) {
        1 {
            Set-ItemProperty -Path $perfKey -Name "DragFullWindows" -Value "0" -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $perfKey -Name "FontSmoothing" -Value "2" -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $perfKey -Name "MenuShowDelay" -Value "0" -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $advKey -Name "ListviewAlphaSelect" -Value 0 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $dwmKey -Name "EnableAeroPeek" -Value 0 -Type DWord -ErrorAction SilentlyContinue
            "BEST"
        }
        2 {
            Set-ItemProperty -Path $perfKey -Name "DragFullWindows" -Value "1" -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $perfKey -Name "FontSmoothing" -Value "2" -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $perfKey -Name "MenuShowDelay" -Value "100" -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $dwmKey -Name "EnableAeroPeek" -Value 0 -Type DWord -ErrorAction SilentlyContinue
            "BALANCED"
        }
        default { "CUSTOM" }
    }
    $modeLabel = switch ($modeName) { "BEST" { "最佳性能" } "BALANCED" { "平衡" } default { "自定义" } }
    Write-Log "视觉效果: $modeLabel 模式已应用" "SUCCESS"
    try { Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue; Start-Sleep 1; Start-Process explorer } catch {}
    return "视觉效果已应用（$modeLabel）"
}

function Invoke-PowerOptimization {
    $selectedGUID = $script:plans[0].GUID
    for ($i = 0; $i -lt 3; $i++) { if ($script:radioPowers[$i].Checked) { $selectedGUID = $script:plans[$i].GUID } }
    if ($selectedGUID -eq "e9a42b02-d5df-448d-aa00-03f14749eb61") {
        powercfg /duplicatescheme $selectedGUID 2>&1 | Out-Null
    }
    powercfg /setactive $selectedGUID 2>&1 | Out-Null
    Write-Log "已切换电源计划: $selectedGUID" "SUCCESS"
    if ($selectedGUID -eq "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c") {
        powercfg /setacvalueindex $selectedGUID SUB_PROCESSOR PROCTHROTTLEMIN 100 2>&1 | Out-Null
        powercfg /setacvalueindex $selectedGUID SUB_PROCESSOR PROCTHROTTLEMAX 100 2>&1 | Out-Null
        Write-Log "CPU 处理器状态: 最低100% / 最高100%" "SUCCESS"
    }
    if ($script:chkUSB.Checked) {
        powercfg /setacvalueindex $selectedGUID SUB_USB USBSELSUSP 0 2>&1 | Out-Null
        Write-Log "USB 选择性挂起: 已禁用" "SUCCESS"
    }
    if ($script:chkPCI.Checked) {
        powercfg /setacvalueindex $selectedGUID SUB_PCIEXPRESS ASPM 0 2>&1 | Out-Null
        Write-Log "PCI Express 电源管理: 已关闭" "SUCCESS"
    }
    powercfg /setactive $selectedGUID 2>&1 | Out-Null
    $planTitle = ($script:plans | Where-Object { $_.GUID -eq $selectedGUID }).Title
    return "电源计划已切换（$planTitle）"
}

function Invoke-DiskOptimization {
    $volumes = @(Get-VolumeCompat)
    if ($script:chkTRIM.Checked -or $script:chkDefrag.Checked) {
        foreach ($vol in $volumes) {
            $drive = "$($vol.DriveLetter):"
            if ($script:chkTRIM.Checked) {
                try { Optimize-VolumeCompat -DriveLetter $vol.DriveLetter -ReTrim; Write-Log "[优化] $drive TRIM 完成" "SUCCESS" }
                catch { Write-Log "[跳过] $drive TRIM" "WARN" }
            }
            if ($script:chkDefrag.Checked) {
                try { Optimize-VolumeCompat -DriveLetter $vol.DriveLetter -Defrag; Write-Log "[优化] $drive 碎片整理完成" "SUCCESS" }
                catch { Write-Log "[跳过] $drive 碎片整理" "WARN" }
            }
            Invoke-UIRefresh
        }
    }
    if ($script:chkWinSxS.Checked) {
        Write-Log "正在清理 WinSxS 组件存储..."
        Dism.exe /Online /Cleanup-Image /StartComponentCleanup 2>&1 | Out-Null
        Write-Log "WinSxS 组件存储清理完成" "SUCCESS"
    }
    if ($script:chkCompact.Checked) {
        Write-Log "正在压缩系统文件..."
        Compact.exe /CompactOS:always 2>&1 | Out-Null
        Write-Log "系统文件压缩完成" "SUCCESS"
    }
    Write-Log "磁盘优化完成！" "SUCCESS"
    return "磁盘优化完成"
}

function Invoke-NetworkOptimization {
    $dnsChoice = $script:cbDNS.SelectedIndex
    if ($dnsChoice -gt 0) {
        $dnsServers = switch ($dnsChoice) {
            1 { @("1.1.1.1", "1.0.0.1") }
            2 { @("8.8.8.8", "8.8.4.4") }
            3 { @("223.5.5.5", "223.6.6.6") }
            4 { @("114.114.114.114", "114.114.115.115") }
        }
        try {
            $adapters = Get-NetAdapterCompat
            foreach ($adapter in $adapters) {
                if ($adapter.Name) {
                    Set-DnsCompat -InterfaceName $adapter.Name -DnsServers $dnsServers
                    Write-Log "[DNS] $($adapter.Name) 已设置为 $($dnsServers -join ', ')" "SUCCESS"
                }
            }
        } catch {
            Write-Log "[DNS] 设置失败: $_" "ERROR"
        }
    }
    if ($script:chkTCP.Checked) {
        try { netsh int tcp set global autotuninglevel=normal 2>&1 | Out-Null; Write-Log "[TCP] 自动调优已启用" "SUCCESS" }
        catch { Write-Log "[TCP] 设置失败" "WARN" }
    }
    if ($script:chkRSS.Checked) { Enable-NetAdapterRssCompat; Write-Log "[RSS] 接收端缩放已启用" "SUCCESS" }
    if ($script:chkRSC.Checked) { Enable-NetAdapterRscCompat; Write-Log "[RSC] 接收段合并已启用" "SUCCESS" }
    if ($script:chkDNSCache.Checked) { Clear-DnsClientCacheCompat; Write-Log "[DNS] 缓存已刷新" "SUCCESS" }
    Write-Log "网络优化完成！" "SUCCESS"
    return "网络优化完成"
}

# ============================================================
#  UI 辅助函数
# ============================================================
function New-Label {
    param([string]$Text, [int]$X, [int]$Y, [int]$W=200, [int]$H=24, $Font=$null, $Color=$null)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Location = New-Object System.Drawing.Point([int]$X, [int]$Y)
    $lbl.Size = New-Object System.Drawing.Size([int]$W, [int]$H)
    $lbl.Text = $Text
    $lbl.Font = if ($Font) { $Font } else { $Fonts.Body }
    $lbl.ForeColor = if ($Color) { $Color } else { $Theme.TextMain }
    $lbl.BackColor = [System.Drawing.Color]::Transparent
    $lbl.AutoEllipsis = $true
    return $lbl
}

function New-Button {
    param([string]$Text, [int]$X, [int]$Y, [int]$W=160, [int]$H=40, $Color=$null, [int]$FontSize=10)
    $btn = New-Object System.Windows.Forms.Button
    $btn.Location = New-Object System.Drawing.Point([int]$X, [int]$Y)
    $btn.Size = New-Object System.Drawing.Size([int]$W, [int]$H)
    $btn.Text = $Text
    $btn.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", $FontSize, [System.Drawing.FontStyle]::Bold)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 0
    $btn.FlatAppearance.MouseOverBackColor = $Theme.AccentHover
    $btn.BackColor = if ($Color) { $Color } else { $Theme.Accent }
    $btn.ForeColor = $Theme.TextBright
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    return $btn
}

function New-SideButton {
    param([string]$Text, [int]$Y)
    $btn = New-Object System.Windows.Forms.Button
    $btn.Location = New-Object System.Drawing.Point(0, [int]$Y)
    $btn.Size = New-Object System.Drawing.Size(220, 46)
    $btn.Text = "  $Text"
    $btn.Font = $Fonts.Sub
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 0
    $btn.FlatAppearance.MouseOverBackColor = $Theme.SideHover
    $btn.BackColor = $Theme.BgDark
    $btn.ForeColor = $Theme.TextDim
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $btn.Padding = New-Object System.Windows.Forms.Padding(20, 0, 0, 0)
    return $btn
}

function New-Card {
    param([int]$X, [int]$Y, [int]$W, [int]$H, [string]$Title, [string]$Desc)
    $card = New-Object System.Windows.Forms.Panel
    $card.Location = New-Object System.Drawing.Point([int]$X, [int]$Y)
    $card.Size = New-Object System.Drawing.Size([int]$W, [int]$H)
    $card.BackColor = $Theme.BgCard

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Location = New-Object System.Drawing.Point(16, 12)
    $lblTitle.Size = New-Object System.Drawing.Size([int]($W - 32), 28)
    $lblTitle.Text = $Title
    $lblTitle.Font = $Fonts.Header
    $lblTitle.ForeColor = $Theme.TextBright
    $lblTitle.BackColor = [System.Drawing.Color]::Transparent
    $card.Controls.Add($lblTitle)

    $lblDesc = New-Object System.Windows.Forms.Label
    $lblDesc.Location = New-Object System.Drawing.Point(16, 42)
    $lblDesc.Size = New-Object System.Drawing.Size([int]($W - 32), [int]($H - 58))
    $lblDesc.Text = $Desc
    $lblDesc.Font = $Fonts.Body
    $lblDesc.ForeColor = $Theme.TextDim
    $lblDesc.BackColor = [System.Drawing.Color]::Transparent
    $card.Controls.Add($lblDesc)

    return $card
}

# ============================================================
#  管理员权限检查
# ============================================================
if (-not (Test-Administrator)) {
    [System.Windows.Forms.MessageBox]::Show(
        "需要管理员权限才能运行此程序！`n`n请右键以管理员身份运行 PowerShell。`n然后执行: .\OptimizeGUI.ps1",
        "权限不足",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    exit 1
}

# ============================================================
#  创建主窗体
# ============================================================
$MainForm = New-Object System.Windows.Forms.Form
$MainForm.Text = "PC-Optimizer-7thGen  v$Version"
$MainForm.Size = New-Object System.Drawing.Size(1024, 720)
$MainForm.MinimumSize = New-Object System.Drawing.Size(900, 640)
$MainForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$MainForm.BackColor = $Theme.BgDark
$MainForm.ForeColor = $Theme.TextMain
$MainForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
$MainForm.Font = $Fonts.Body
$MainForm.Icon = $null

# ============================================================
#  主布局：TableLayoutPanel（根除 Dock Z-Order 遮挡问题）
#  WinUI 原则：导航面板与内容面板使用明确的列分隔，不依赖 Dock 顺序
# ============================================================
$mainLayout = New-Object System.Windows.Forms.TableLayoutPanel
$mainLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
$mainLayout.ColumnCount = 2
$mainLayout.RowCount = 1
$mainLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 220)))
$mainLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$mainLayout.BackColor = $Theme.BgDark
$mainLayout.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 0)
$MainForm.Controls.Add($mainLayout)

# ============================================================
#  侧边栏面板
# ============================================================
$sidePanel = New-Object System.Windows.Forms.Panel
$sidePanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$sidePanel.BackColor = $Theme.BgDark
$mainLayout.Controls.Add($sidePanel, 0, 0)

# 侧边栏 Logo
$lblLogo = New-Object System.Windows.Forms.Label
$lblLogo.Location = New-Object System.Drawing.Point(0, 16)
$lblLogo.Size = New-Object System.Drawing.Size(220, 36)
$lblLogo.Text = "  PC OPTIMIZER"
$lblLogo.Font = $Fonts.Header
$lblLogo.ForeColor = $Theme.Accent
$lblLogo.BackColor = $Theme.BgDark
$lblLogo.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$sidePanel.Controls.Add($lblLogo)

$lblSubtitle = New-Object System.Windows.Forms.Label
$lblSubtitle.Location = New-Object System.Drawing.Point(0, 54)
$lblSubtitle.Size = New-Object System.Drawing.Size(220, 18)
$lblSubtitle.Text = "  7代CPU老电脑优化工具"
$lblSubtitle.Font = $Fonts.Small
$lblSubtitle.ForeColor = $Theme.TextDim
$lblSubtitle.BackColor = $Theme.BgDark
$sidePanel.Controls.Add($lblSubtitle)

# 分隔线
$sepLine = New-Object System.Windows.Forms.Panel
$sepLine.Location = New-Object System.Drawing.Point(20, 78)
$sepLine.Size = New-Object System.Drawing.Size(180, 2)
$sepLine.BackColor = $Theme.BgPanel
$sidePanel.Controls.Add($sepLine)

# 侧边栏按钮（高度46，间距4，共10个按钮=500px，从Y=88到Y=588）
$script:NavButtons = @{}
$btnY = 88
$btnH = 46
$btnGap = 4
$navItems = @(
    @{Key="Dashboard"; Text="系统仪表盘"}
    @{Key="Clean";     Text="垃圾清理"}
    @{Key="Services";  Text="服务优化"}
    @{Key="Startup";   Text="启动项"}
    @{Key="Visual";    Text="视觉效果"}
    @{Key="Power";     Text="电源计划"}
    @{Key="Disk";      Text="磁盘优化"}
    @{Key="Network";   Text="网络优化"}
    @{Key="Backup";    Text="备份恢复"}
    @{Key="About";     Text="关于"}
)
foreach ($item in $navItems) {
    $item.Y = $btnY
    $btnY += $btnH + $btnGap
}

foreach ($item in $navItems) {
    $btn = New-SideButton $item.Text $item.Y
    $btn.Tag = $item.Key
    $btn.Add_Click({
        param($s, $e)
        foreach ($k in $script:NavButtons.Keys) {
            $script:NavButtons[$k].BackColor = $Theme.BgDark
            $script:NavButtons[$k].ForeColor = $Theme.TextDim
        }
        $s.BackColor = $Theme.Accent
        $s.ForeColor = $Theme.TextBright
        $key = $s.Tag
        foreach ($pn in $script:Pages.Keys) {
            $script:Pages[$pn].Visible = ($pn -eq $key)
        }
        $script:CurrentPage = $key
        # 更新顶部标题
        if ($script:HeaderTitles.ContainsKey($key)) {
            $script:HeaderLabel.Text = $script:HeaderTitles[$key]
        }
    })
    $script:NavButtons[$item.Key] = $btn
    $sidePanel.Controls.Add($btn)
}

# 默认选中仪表盘
$script:NavButtons["Dashboard"].BackColor = $Theme.Accent
$script:NavButtons["Dashboard"].ForeColor = $Theme.TextBright

# ============================================================
#  内容区域（右侧主面板）
# ============================================================
$contentPanel = New-Object System.Windows.Forms.Panel
$contentPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$contentPanel.BackColor = $Theme.BgDark
$mainLayout.Controls.Add($contentPanel, 1, 0)

# 顶部标题栏
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Location = New-Object System.Drawing.Point(0, 0)
$headerPanel.Size = New-Object System.Drawing.Size(804, 50)
$headerPanel.BackColor = $Theme.BgPanel
$headerPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$contentPanel.Controls.Add($headerPanel)

$lblHeader = New-Object System.Windows.Forms.Label
$lblHeader.Location = New-Object System.Drawing.Point(20, 0)
$lblHeader.Size = New-Object System.Drawing.Size(400, 50)
$lblHeader.Text = "系统仪表盘"
$lblHeader.Font = $Fonts.Header
$lblHeader.ForeColor = $Theme.TextBright
$lblHeader.BackColor = $Theme.BgPanel
$lblHeader.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$headerPanel.Controls.Add($lblHeader)

# 页面容器
$pageContainer = New-Object System.Windows.Forms.Panel
$pageContainer.Location = New-Object System.Drawing.Point(0, 50)
$pageContainer.Size = New-Object System.Drawing.Size(804, 670)
$pageContainer.BackColor = $Theme.BgDark
$pageContainer.Dock = [System.Windows.Forms.DockStyle]::Fill
$contentPanel.Controls.Add($pageContainer)

# ============================================================
#  页面集合
# ============================================================
$script:Pages = @{}

# --- 辅助：创建页面面板 ---
function New-Page {
    param([string]$Title)
    $page = New-Object System.Windows.Forms.Panel
    $page.Dock = [System.Windows.Forms.DockStyle]::Fill
    $page.BackColor = $Theme.BgDark
    $page.Visible = $false
    return $page
}

# ============================================================
#  页面 1: 系统仪表盘
# ============================================================
$pageDash = New-Page "Dashboard"
$script:Pages["Dashboard"] = $pageDash

function Build-Dashboard {
    $page = $script:Pages["Dashboard"]
    $page.Controls.Clear()

    # 获取系统信息（使用兼容函数，避免多CPU/多OS返回数组）
    $os = @(Get-CimData Win32_OperatingSystem)[0]
    $cpu = @(Get-CimData Win32_Processor)[0]
    $totalMem = [math]::Round([double]$os.TotalVisibleMemorySize / 1MB, 1)
    $freeMem  = [math]::Round([double]$os.FreePhysicalMemory / 1MB, 1)
    $usedMem  = [math]::Round($totalMem - $freeMem, 1)
    $memPct   = if ($totalMem -gt 0) { [math]::Round(($usedMem / $totalMem) * 100, 0) } else { 0 }
    # Win7 WMI LastBootUpTime 是字符串，需转换
    $bootTime = $os.LastBootUpTime
    if ($bootTime -is [string]) { $bootTime = [System.Management.ManagementDateTimeConverter]::ToDateTime($bootTime) }
    $uptime   = (Get-Date) - $bootTime

    # CPU 代数检测
    $cpuGen = ""
    $cpuColor = $Theme.TextMain
    if ($cpu.Name -match "i[3579]-(\d)") {
        $gen = [int]$matches[1]
        $cpuGen = "第 $gen 代"
        if ($gen -le 7) {
            $cpuGen += " (本工具优化目标)"
            $cpuColor = $Theme.Success
        }
    }

    # --- CPU 卡片 ---
    $cardCPU = New-Object System.Windows.Forms.Panel
    $cardCPU.Location = New-Object System.Drawing.Point(20, 10)
    $cardCPU.Size = New-Object System.Drawing.Size(370, 130)
    $cardCPU.BackColor = $Theme.BgCard
    $page.Controls.Add($cardCPU)

    $cardCPU.Controls.Add((New-Label "CPU 处理器" 16 10 340 26 $Fonts.Header $Theme.Accent))
    $cardCPU.Controls.Add((New-Label $cpu.Name 16 40 340 24 $Fonts.Body $Theme.TextBright))
    $cardCPU.Controls.Add((New-Label "核心: $($cpu.NumberOfCores)  线程: $($cpu.NumberOfLogicalProcessors)  频率: $([math]::Round($cpu.MaxClockSpeed/1000,2)) GHz" 16 66 340 22 $Fonts.Small $Theme.TextDim))
    $cardCPU.Controls.Add((New-Label "当前负载: $($cpu.LoadPercentage)%" 16 88 340 22 $Fonts.Small $Theme.Warning))

    if ($cpuGen) {
        $cardCPU.Controls.Add((New-Label $cpuGen 16 108 340 22 $Fonts.Small $cpuColor))
    }

    # --- 内存卡片 ---
    $cardMem = New-Object System.Windows.Forms.Panel
    $cardMem.Location = New-Object System.Drawing.Point(410, 10)
    $cardMem.Size = New-Object System.Drawing.Size(370, 130)
    $cardMem.BackColor = $Theme.BgCard
    $page.Controls.Add($cardMem)

    $cardMem.Controls.Add((New-Label "内存" 16 10 340 26 $Fonts.Header $Theme.Accent))

    $lblMemTotal = New-Label "总内存: ${totalMem} GB" 16 40 340 22 $Fonts.Body $Theme.TextBright
    $cardMem.Controls.Add($lblMemTotal)

    $lblMemUsed = New-Label "已使用: ${usedMem} GB / ${totalMem} GB (${memPct}%)" 16 64 340 22 $Fonts.Small $Theme.TextDim
    $cardMem.Controls.Add($lblMemUsed)

    # 内存进度条
    $memBar = New-Object System.Windows.Forms.ProgressBar
    $memBar.Location = New-Object System.Drawing.Point(16, 90)
    $memBar.Size = New-Object System.Drawing.Size(340, 16)
    $memBar.Value = $memPct
    $memBar.ForeColor = if ($memPct -gt 80) { $Theme.Error } elseif ($memPct -gt 60) { $Theme.Warning } else { $Theme.Success }
    $memBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $cardMem.Controls.Add($memBar)

    $lblMemFree = New-Label "可用: ${freeMem} GB" 16 110 340 18 $Fonts.Small $Theme.TextDim
    $cardMem.Controls.Add($lblMemFree)

    # --- 磁盘卡片 ---
    $disks = @(Get-CimData Win32_LogicalDisk -Filter "DriveType=3")
    $yDisk = 150
    foreach ($disk in $disks) {
        $total = [math]::Round([double]$disk.Size / 1GB, 1)
        $free  = [math]::Round([double]$disk.FreeSpace / 1GB, 1)
        $used  = [math]::Round($total - $free, 1)
        $pct   = if ($total -gt 0) { [math]::Round(($used / $total) * 100, 0) } else { 0 }

        $cardDisk = New-Object System.Windows.Forms.Panel
        $cardDisk.Location = New-Object System.Drawing.Point(20, $yDisk)
        $cardDisk.Size = New-Object System.Drawing.Size(760, 56)
        $cardDisk.BackColor = $Theme.BgCard
        $page.Controls.Add($cardDisk)

        $lblDiskName = New-Label "$($disk.DeviceID) 总计 ${total}GB" 16 6 200 22 $Fonts.Body $Theme.TextBright
        $cardDisk.Controls.Add($lblDiskName)

        $lblDiskUse = New-Label "已用 ${used}GB / 可用 ${free}GB (${pct}%)" 220 8 300 18 $Fonts.Small $Theme.TextDim
        $cardDisk.Controls.Add($lblDiskUse)

        $diskBar = New-Object System.Windows.Forms.ProgressBar
        $diskBar.Location = New-Object System.Drawing.Point(530, 16)
        $diskBar.Size = New-Object System.Drawing.Size(210, 14)
        $diskBar.Value = $pct
        $diskBar.ForeColor = if ($pct -gt 85) { $Theme.Error } elseif ($pct -gt 70) { $Theme.Warning } else { $Theme.Success }
        $diskBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
        $cardDisk.Controls.Add($diskBar)

        $yDisk += 64
    }

    # --- 系统信息 ---
    $cardSys = New-Object System.Windows.Forms.Panel
    $cardSys.Location = New-Object System.Drawing.Point(20, [int]($yDisk + 4))
    $cardSys.Size = New-Object System.Drawing.Size(760, 100)
    $cardSys.BackColor = $Theme.BgCard
    $page.Controls.Add($cardSys)

    $lblSysTitle = New-Label "系统信息" 16 8 400 26 $Fonts.Header $Theme.Accent
    $cardSys.Controls.Add($lblSysTitle)

    $sysInfo = "系统: $($os.Caption) Build $($os.BuildNumber)`n"
    $sysInfo += "运行时间: $($uptime.Days) 天 $($uptime.Hours) 小时 $($uptime.Minutes) 分钟`n"

    # 显卡
    $gpus = @(Get-CimData Win32_VideoController) | Select-Object -First 2
    foreach ($gpu in $gpus) {
        if ($gpu.Name) { $sysInfo += "显卡: $($gpu.Name)`n" }
    }

    $lblSysInfo = New-Object System.Windows.Forms.Label
    $lblSysInfo.Location = New-Object System.Drawing.Point(16, 38)
    $lblSysInfo.Size = New-Object System.Drawing.Size(728, 60)
    $lblSysInfo.Text = $sysInfo
    $lblSysInfo.Font = $Fonts.Small
    $lblSysInfo.ForeColor = $Theme.TextDim
    $lblSysInfo.BackColor = [System.Drawing.Color]::Transparent
    $cardSys.Controls.Add($lblSysInfo)

    # --- 刷新按钮 ---
    $btnRefresh = New-Button "刷新信息" 20 ([int]($yDisk + 112)) 120 36 $Theme.AccentDark 10
    $btnRefresh.Add_Click({ Build-Dashboard })
    $page.Controls.Add($btnRefresh)

    # --- 一键优化按钮 ---
    $btnFull = New-Button "一键全面优化" 640 ([int]($yDisk + 112)) 140 36 $Theme.Success 10
    $btnFull.Add_Click({
        $result = [System.Windows.Forms.MessageBox]::Show(
            "即将依次执行所有优化（垃圾清理→服务→启动项→视觉→电源→磁盘→网络），可能需要几分钟。`n`n建议先进行备份。`n`n确认继续？",
            "一键全面优化",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($result -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        $script:btnFull.Enabled = $false
        $script:btnFull.Text = "优化中..."
        Invoke-UIRefresh

        $summaries = @()
        $steps = @(
            @{ Name = "垃圾清理"; Action = { Invoke-CleanOptimization } },
            @{ Name = "服务优化"; Action = { Invoke-ServicesOptimization } },
            @{ Name = "启动项";   Action = { Invoke-StartupOptimization -DisableAll } },
            @{ Name = "视觉效果"; Action = { Invoke-VisualOptimization } },
            @{ Name = "电源计划"; Action = { Invoke-PowerOptimization } },
            @{ Name = "磁盘优化"; Action = { Invoke-DiskOptimization } },
            @{ Name = "网络优化"; Action = { Invoke-NetworkOptimization } }
        )
        $idx = 0
        foreach ($step in $steps) {
            $idx++
            $script:btnFull.Text = "优化中 ($idx/$($steps.Count)): $($step.Name)"
            Write-Log "========== 一键优化 [$idx/$($steps.Count)] $($step.Name) ==========" "INFO"
            try {
                $s = & $step.Action
                if ($s) { $summaries += "[$($step.Name)] $s" }
            } catch {
                Write-Log "[$($step.Name)] 执行出错: $($_.Exception.Message)" "ERROR"
                $summaries += "[$($step.Name)] 出错: $($_.Exception.Message)"
            }
            Invoke-UIRefresh
        }

        $script:btnFull.Enabled = $true
        $script:btnFull.Text = "一键全面优化"
        $report = "一键全面优化完成！`n`n" + ($summaries -join "`n")
        Write-Log "一键全面优化完成" "SUCCESS"
        [System.Windows.Forms.MessageBox]::Show("$report`n`n建议重启电脑使所有更改生效。", "一键优化完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    })
    $page.Controls.Add($btnFull)
}

# ============================================================
#  页面 2: 垃圾清理
# ============================================================
$pageClean = New-Page "Clean"
$script:Pages["Clean"] = $pageClean

function Build-CleanPage {
    $page = $script:Pages["Clean"]
    $page.Controls.Clear()

    $lblTitle = New-Label "垃圾文件清理" 20 10 500 30 $Fonts.Header $Theme.TextBright
    $page.Controls.Add($lblTitle)

    $lblDesc = New-Label "清理系统临时文件、更新缓存、缩略图缓存、回收站等，释放磁盘空间" 20 42 760 24 $Fonts.Small $Theme.TextDim
    $page.Controls.Add($lblDesc)

    # 扫描结果
    $lblScan = New-Label "可清理项目:" 20 78 760 24 $Fonts.Sub $Theme.Accent
    $page.Controls.Add($lblScan)

    # 用 script 作用域保存变量供事件处理器使用
    $script:CleanItems = @(
        @{Path="C:\Windows\Temp";                    Name="Windows 系统临时文件"}
        @{Path=$env:TEMP;                             Name="用户临时文件"}
        @{Path="C:\Windows\Prefetch";                Name="预读取文件"}
        @{Path="C:\Windows\SoftwareDistribution\Download"; Name="Windows Update 下载缓存"}
        @{Path="$env:LOCALAPPDATA\Microsoft\Windows\Explorer"; Name="缩略图缓存"}
        @{Path="$env:PROGRAMDATA\Microsoft\Windows\WER"; Name="Windows 错误报告"}
    )

    $script:CleanListBox = New-Object System.Windows.Forms.CheckedListBox
    $script:CleanListBox.Location = New-Object System.Drawing.Point(20, 108)
    $script:CleanListBox.Size = New-Object System.Drawing.Size(760, 200)
    $script:CleanListBox.BackColor = $Theme.BgInput
    $script:CleanListBox.ForeColor = $Theme.TextMain
    $script:CleanListBox.Font = $Fonts.Body
    $script:CleanListBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $script:CleanListBox.CheckOnClick = $true
    foreach ($item in $script:CleanItems) {
        $size = Get-FolderSize $item.Path
        $sizeMB = [math]::Round($size / 1MB, 2)
        $display = "$($item.Name) — ${sizeMB} MB"
        $script:CleanListBox.Items.Add($display, $true) | Out-Null
    }
    $page.Controls.Add($script:CleanListBox)

    # 额外选项
    $script:ChkRecycle = New-Object System.Windows.Forms.CheckBox
    $script:ChkRecycle.Location = New-Object System.Drawing.Point(20, 318)
    $script:ChkRecycle.Size = New-Object System.Drawing.Size(200, 24)
    $script:ChkRecycle.Text = "清空回收站"
    $script:ChkRecycle.Checked = $true
    $script:ChkRecycle.Font = $Fonts.Body
    $script:ChkRecycle.ForeColor = $Theme.TextMain
    $script:ChkRecycle.BackColor = $Theme.BgDark
    $page.Controls.Add($script:ChkRecycle)

    $script:ChkDNS = New-Object System.Windows.Forms.CheckBox
    $script:ChkDNS.Location = New-Object System.Drawing.Point(230, 318)
    $script:ChkDNS.Size = New-Object System.Drawing.Size(200, 24)
    $script:ChkDNS.Text = "清除 DNS 缓存"
    $script:ChkDNS.Checked = $true
    $script:ChkDNS.Font = $Fonts.Body
    $script:ChkDNS.ForeColor = $Theme.TextMain
    $script:ChkDNS.BackColor = $Theme.BgDark
    $page.Controls.Add($script:ChkDNS)

    $script:ChkDump = New-Object System.Windows.Forms.CheckBox
    $script:ChkDump.Location = New-Object System.Drawing.Point(440, 318)
    $script:ChkDump.Size = New-Object System.Drawing.Size(200, 24)
    $script:ChkDump.Text = "删除内存转储文件"
    $script:ChkDump.Checked = $true
    $script:ChkDump.Font = $Fonts.Body
    $script:ChkDump.ForeColor = $Theme.TextMain
    $script:ChkDump.BackColor = $Theme.BgDark
    $page.Controls.Add($script:ChkDump)

    # 执行按钮
    $script:BtnClean = New-Button "开始清理" 20 356 200 44 $Theme.Success 11
    $script:BtnClean.Add_Click({
        $script:BtnClean.Enabled = $false
        $script:BtnClean.Text = "正在清理..."
        Invoke-UIRefresh
        try {
            $summary = Invoke-CleanOptimization
            [System.Windows.Forms.MessageBox]::Show($summary, "完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            Write-Log "清理出错: $($_.Exception.Message)" "ERROR"
            [System.Windows.Forms.MessageBox]::Show("清理出错: $($_.Exception.Message)", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        } finally {
            $script:BtnClean.Enabled = $true
            $script:BtnClean.Text = "开始清理"
        }
    })
    $page.Controls.Add($script:BtnClean)
}

# ============================================================
#  页面 3: 服务优化
# ============================================================
$pageSvc = New-Page "Services"
$script:Pages["Services"] = $pageSvc

function Build-ServicesPage {
    $page = $script:Pages["Services"]
    $page.Controls.Clear()

    $lblTitle = New-Label "服务优化" 20 10 500 30 $Fonts.Header $Theme.TextBright
    $page.Controls.Add($lblTitle)

    $lblDesc = New-Label "禁用不必要的后台服务以释放 CPU 和内存资源" 20 42 760 24 $Fonts.Small $Theme.TextDim
    $page.Controls.Add($lblDesc)

    $servicesList = @(
        @{Name="DiagTrack";           Desc="诊断跟踪服务（遥测数据收集）";          Level="安全禁用"}
        @{Name="dmwappushservice";    Desc="设备管理 WAP 推送消息路由服务";         Level="安全禁用"}
        @{Name="WerSvc";              Desc="Windows 错误报告服务";                  Level="安全禁用"}
        @{Name="XblAuthManager";      Desc="Xbox Live 身份验证管理器";              Level="安全禁用"}
        @{Name="XblGameSave";         Desc="Xbox Live 游戏保存";                    Level="安全禁用"}
        @{Name="XboxGipSvc";          Desc="Xbox 附件管理服务";                     Level="安全禁用"}
        @{Name="XboxNetApiSvc";       Desc="Xbox Live 网络服务";                    Level="安全禁用"}
        @{Name="Fax";                 Desc="传真服务";                              Level="安全禁用"}
        @{Name="RemoteRegistry";      Desc="远程注册表服务";                        Level="安全禁用"}
        @{Name="RetailDemo";          Desc="零售演示服务";                          Level="安全禁用"}
        @{Name="SensorService";       Desc="传感器服务";                            Level="建议禁用"}
        @{Name="SensrSvc";            Desc="传感器监控服务";                        Level="建议禁用"}
        @{Name="WMPNetworkSvc";       Desc="WMP 网络共享服务";                      Level="建议禁用"}
        @{Name="HvHost";              Desc="HV 主机服务（虚拟化）";                 Level="建议禁用"}
        @{Name="vmickvpexchange";     Desc="Hyper-V 数据交换服务";                  Level="建议禁用"}
        @{Name="vmicguestinterface";  Desc="Hyper-V 来宾接口服务";                  Level="建议禁用"}
        @{Name="vmicshutdown";        Desc="Hyper-V 关机服务";                      Level="建议禁用"}
        @{Name="vmicheartbeat";       Desc="Hyper-V 心跳服务";                      Level="建议禁用"}
        @{Name="vmicvmsession";       Desc="Hyper-V PowerShell 直接服务";           Level="建议禁用"}
        @{Name="vmicrdv";             Desc="Hyper-V 远程桌面虚拟化服务";            Level="建议禁用"}
        @{Name="vmictimesync";        Desc="Hyper-V 时间同步服务";                  Level="建议禁用"}
    )

    # DataGridView
    $dgv = New-Object System.Windows.Forms.DataGridView
    $dgv.Location = New-Object System.Drawing.Point(20, 76)
    $dgv.Size = New-Object System.Drawing.Size(760, 280)
    $dgv.BackgroundColor = $Theme.BgPanel
    $dgv.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dgv.DefaultCellStyle.BackColor = $Theme.BgInput
    $dgv.DefaultCellStyle.ForeColor = $Theme.TextMain
    $dgv.DefaultCellStyle.Font = $Fonts.Small
    $dgv.DefaultCellStyle.SelectionBackColor = $Theme.Accent
    $dgv.DefaultCellStyle.SelectionForeColor = $Theme.TextBright
    $dgv.ColumnHeadersDefaultCellStyle.BackColor = $Theme.BgPanel
    $dgv.ColumnHeadersDefaultCellStyle.ForeColor = $Theme.TextBright
    $dgv.ColumnHeadersDefaultCellStyle.Font = $Fonts.Body
    $dgv.EnableHeadersVisualStyles = $false
    $dgv.AllowUserToAddRows = $false
    $dgv.AllowUserToDeleteRows = $false
    $dgv.ReadOnly = $false
    $dgv.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $dgv.RowTemplate.Height = 28

    $dt = New-Object System.Data.DataTable
    $dt.Columns.Add("选择", [System.Type]::GetType("System.Boolean")) | Out-Null
    $dt.Columns.Add("服务名称") | Out-Null
    $dt.Columns.Add("描述") | Out-Null
    $dt.Columns.Add("级别") | Out-Null
    $dt.Columns.Add("状态") | Out-Null

    foreach ($svc in $servicesList) {
        $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        $status = if ($service) { $service.Status.ToString() } else { "未安装" }
        $check = $svc.Level -eq "安全禁用"
        $dt.Rows.Add($check, $svc.Name, $svc.Desc, $svc.Level, $status) | Out-Null
    }
    $dgv.DataSource = $dt

    # 设置列样式
    $dgv.AutoGenerateColumns = $true
    if ($dgv.Columns.Count -gt 0) {
        $dgv.Columns[0].Width = 50
        $dgv.Columns[0].ReadOnly = $false
        $dgv.Columns[1].Width = 150
        $dgv.Columns[1].ReadOnly = $true
        $dgv.Columns[2].AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
        $dgv.Columns[2].ReadOnly = $true
        if ($dgv.Columns.Count -gt 3) {
            $dgv.Columns[3].Width = 80
            $dgv.Columns[3].ReadOnly = $true
        }
        if ($dgv.Columns.Count -gt 4) {
            $dgv.Columns[4].Width = 70
            $dgv.Columns[4].ReadOnly = $true
        }
    }
    $page.Controls.Add($dgv)

    # 遥测任务
    $script:chkTelemetry = New-Object System.Windows.Forms.CheckBox
    $script:chkTelemetry.Location = New-Object System.Drawing.Point(20, 366)
    $script:chkTelemetry.Size = New-Object System.Drawing.Size(400, 24)
    $script:chkTelemetry.Text = "同时禁用遥测相关计划任务"
    $script:chkTelemetry.Checked = $true
    $script:chkTelemetry.Font = $Fonts.Body
    $script:chkTelemetry.ForeColor = $Theme.TextMain
    $script:chkTelemetry.BackColor = $Theme.BgDark
    $page.Controls.Add($script:chkTelemetry)

    # 按钮
    # 保存 DataTable 到 script 作用域
    $script:SvcDataTable = $dt

    $btnSafe = New-Button "仅安全禁用" 20 400 140 40 $Theme.Accent 10
    $btnSafe.Add_Click({
        for ($i = 0; $i -lt $script:SvcDataTable.Rows.Count; $i++) {
            $script:SvcDataTable.Rows[$i]["选择"] = ($script:SvcDataTable.Rows[$i]["级别"] -eq "安全禁用")
        }
    })
    $page.Controls.Add($btnSafe)

    $btnAll = New-Button "全选" 170 400 100 40 $Theme.AccentDark 10
    $btnAll.Add_Click({
        for ($i = 0; $i -lt $script:SvcDataTable.Rows.Count; $i++) { $script:SvcDataTable.Rows[$i]["选择"] = $true }
    })
    $page.Controls.Add($btnAll)

    $script:btnDisable = New-Button "执行禁用" 640 400 140 40 $Theme.Success 10
    $script:btnDisable.Add_Click({
        $script:btnDisable.Enabled = $false
        $script:btnDisable.Text = "处理中..."
        Invoke-UIRefresh
        try {
            $summary = Invoke-ServicesOptimization
            [System.Windows.Forms.MessageBox]::Show("服务优化完成！`n$summary`n`n备份文件已生成", "完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            Write-Log "服务优化出错: $($_.Exception.Message)" "ERROR"
            [System.Windows.Forms.MessageBox]::Show("服务优化出错: $($_.Exception.Message)", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        } finally {
            $script:btnDisable.Enabled = $true
            $script:btnDisable.Text = "执行禁用"
        }
    })
    $page.Controls.Add($script:btnDisable)
}

# ============================================================
#  页面 4: 启动项
# ============================================================
$pageStartup = New-Page "Startup"
$script:Pages["Startup"] = $pageStartup

function Build-StartupPage {
    $page = $script:Pages["Startup"]
    $page.Controls.Clear()

    $lblTitle = New-Label "启动项管理" 20 10 500 30 $Fonts.Header $Theme.TextBright
    $page.Controls.Add($lblTitle)

    $lblDesc = New-Label "管理开机启动项，禁用不必要的程序以加快开机速度" 20 42 760 24 $Fonts.Small $Theme.TextDim
    $page.Controls.Add($lblDesc)

    # 扫描启动项 - 用 script 作用域保存
    $script:StartupItems = @()
    $regPaths = @(
        @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"; Scope="当前用户"}
        @{Path="HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"; Scope="所有用户"}
        @{Path="HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; Scope="所有用户(32位)"}
    )
    foreach ($reg in $regPaths) {
        if (Test-Path $reg.Path) {
            $props = Get-ItemProperty -Path $reg.Path -ErrorAction SilentlyContinue
            if ($props) {
                $props.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" -and $_.Value } | ForEach-Object {
                    $script:StartupItems += [PSCustomObject]@{ Name=$_.Name; Command=$_.Value; Scope=$reg.Scope; Source="注册表"; RegPath=$reg.Path }
                }
            }
        }
    }

    # 启动文件夹
    $startupFolders = @(
        @{Path="$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Scope="当前用户"}
        @{Path="$env:PROGRAMDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Scope="所有用户"}
    )
    foreach ($folder in $startupFolders) {
        if (Test-Path $folder.Path) {
            Get-ChildItem -Path $folder.Path -ErrorAction SilentlyContinue | ForEach-Object {
                $script:StartupItems += [PSCustomObject]@{ Name=$_.Name; Command=$_.FullName; Scope=$folder.Scope; Source="启动文件夹"; RegPath=$folder.Path }
            }
        }
    }

    $script:DgvStartup = New-Object System.Windows.Forms.DataGridView
    $script:DgvStartup.Location = New-Object System.Drawing.Point(20, 76)
    $script:DgvStartup.Size = New-Object System.Drawing.Size(760, 360)
    $script:DgvStartup.BackgroundColor = $Theme.BgPanel
    $script:DgvStartup.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $script:DgvStartup.DefaultCellStyle.BackColor = $Theme.BgInput
    $script:DgvStartup.DefaultCellStyle.ForeColor = $Theme.TextMain
    $script:DgvStartup.DefaultCellStyle.Font = $Fonts.Small
    $script:DgvStartup.DefaultCellStyle.SelectionBackColor = $Theme.Accent
    $script:DgvStartup.DefaultCellStyle.SelectionForeColor = $Theme.TextBright
    $script:DgvStartup.ColumnHeadersDefaultCellStyle.BackColor = $Theme.BgPanel
    $script:DgvStartup.ColumnHeadersDefaultCellStyle.ForeColor = $Theme.TextBright
    $script:DgvStartup.ColumnHeadersDefaultCellStyle.Font = $Fonts.Body
    $script:DgvStartup.EnableHeadersVisualStyles = $false
    $script:DgvStartup.AllowUserToAddRows = $false
    $script:DgvStartup.ReadOnly = $true
    $script:DgvStartup.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $script:DgvStartup.RowTemplate.Height = 28

    $dtStartup = New-Object System.Data.DataTable
    $dtStartup.Columns.Add("名称") | Out-Null
    $dtStartup.Columns.Add("来源") | Out-Null
    $dtStartup.Columns.Add("范围") | Out-Null
    $dtStartup.Columns.Add("命令") | Out-Null

    foreach ($item in $script:StartupItems) {
        $cmd = if ($item.Command.Length -gt 60) { $item.Command.Substring(0, 57) + "..." } else { $item.Command }
        $dtStartup.Rows.Add($item.Name, $item.Source, $item.Scope, $cmd) | Out-Null
    }
    $script:DgvStartup.DataSource = $dtStartup
    $page.Controls.Add($script:DgvStartup)

    $script:btnDisableStartup = New-Button "禁用选中项" 20 446 160 40 $Theme.Success 10
    $script:btnDisableStartup.Add_Click({
        try {
            $summary = Invoke-StartupOptimization
            if ($summary) {
                [System.Windows.Forms.MessageBox]::Show("$summary`n`n部分项需通过任务管理器->启动 禁用", "完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                Build-StartupPage
            }
        } catch {
            Write-Log "启动项优化出错: $($_.Exception.Message)" "ERROR"
            [System.Windows.Forms.MessageBox]::Show("启动项优化出错: $($_.Exception.Message)", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })
    $page.Controls.Add($script:btnDisableStartup)

    $btnRefreshStartup = New-Button "刷新列表" 190 446 120 40 $Theme.AccentDark 10
    $btnRefreshStartup.Add_Click({ Build-StartupPage })
    $page.Controls.Add($btnRefreshStartup)
}

# ============================================================
#  页面 5: 视觉效果
# ============================================================
$pageVisual = New-Page "Visual"
$script:Pages["Visual"] = $pageVisual

function Build-VisualPage {
    $page = $script:Pages["Visual"]
    $page.Controls.Clear()

    $lblTitle = New-Label "视觉效果优化" 20 10 500 30 $Fonts.Header $Theme.TextBright
    $page.Controls.Add($lblTitle)

    $lblDesc = New-Label "降低视觉特效以提升系统响应速度，老电脑推荐使用最佳性能模式" 20 42 760 24 $Fonts.Small $Theme.TextDim
    $page.Controls.Add($lblDesc)

    # 选项卡片
    $script:modes = @(
        @{Title="最佳性能"; Desc="关闭所有动画和特效，仅保留字体平滑`n适合老旧电脑，最大化响应速度"; Color=$Theme.Success; Value=1}
        @{Title="平衡模式"; Desc="关闭大部分动画，保留基本效果`n适合日常使用"; Color=$Theme.Accent; Value=2}
        @{Title="自定义"; Desc="逐项选择要关闭的效果`n精细控制"; Color=$Theme.Warning; Value=3}
    )

    $yMode = 78
    $script:radioBtns = @()
    for ($i = 0; $i -lt 3; $i++) {
        $m = $script:modes[$i]
        $card = New-Object System.Windows.Forms.Panel
        $card.Location = New-Object System.Drawing.Point(20, $yMode)
        $card.Size = New-Object System.Drawing.Size(760, 64)
        $card.BackColor = $Theme.BgCard
        $page.Controls.Add($card)

        $rb = New-Object System.Windows.Forms.RadioButton
        $rb.Location = New-Object System.Drawing.Point(12, 18)
        $rb.Size = New-Object System.Drawing.Size(24, 24)
        $rb.Checked = ($i -eq 0)
        $rb.BackColor = $Theme.BgCard
        $rb.ForeColor = $m.Color
        $card.Controls.Add($rb)
        $script:radioBtns += $rb

        $lblMode = New-Label $m.Title 44 12 200 26 $Fonts.Header $m.Color
        $card.Controls.Add($lblMode)

        $lblModeDesc = New-Label $m.Desc 44 36 700 28 $Fonts.Small $Theme.TextDim
        $card.Controls.Add($lblModeDesc)

        $yMode += 72
    }

    $script:btnApplyVisual = New-Button "应用视觉效果" 20 ([int]($yMode + 10)) 200 44 $Theme.Success 11
    $script:btnApplyVisual.Add_Click({
        $script:btnApplyVisual.Enabled = $false
        $script:btnApplyVisual.Text = "应用中..."
        Invoke-UIRefresh
        try {
            $summary = Invoke-VisualOptimization
            [System.Windows.Forms.MessageBox]::Show("$summary！`n资源管理器已重启。", "完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            Write-Log "视觉效果出错: $($_.Exception.Message)" "ERROR"
            [System.Windows.Forms.MessageBox]::Show("视觉效果出错: $($_.Exception.Message)", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        } finally {
            $script:btnApplyVisual.Enabled = $true
            $script:btnApplyVisual.Text = "应用视觉效果"
        }
    })
    $page.Controls.Add($script:btnApplyVisual)
}

# ============================================================
#  页面 6: 电源计划
# ============================================================
$pagePower = New-Page "Power"
$script:Pages["Power"] = $pagePower

function Build-PowerPage {
    $page = $script:Pages["Power"]
    $page.Controls.Clear()

    $lblTitle = New-Label "电源计划优化" 20 10 500 30 $Fonts.Header $Theme.TextBright
    $page.Controls.Add($lblTitle)

    $lblDesc = New-Label "切换高性能电源计划，最大化 CPU 性能响应速度" 20 42 760 24 $Fonts.Small $Theme.TextDim
    $page.Controls.Add($lblDesc)

    # 当前计划
    $currentPlan = @(powercfg /getactivescheme 2>&1) -join ' '
    $script:lblCurrent = New-Label "当前计划: $currentPlan" 20 78 760 24 $Fonts.Sub $Theme.Warning
    $page.Controls.Add($script:lblCurrent)

    $script:plans = @(
        @{Title="高性能模式"; Desc="最大化 CPU 性能，CPU 始终保持最高频率`n适合台式机或插电笔记本"; GUID="8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"; Color=$Theme.Success}
        @{Title="卓越性能模式"; Desc="比高性能更高，需解锁后可用`n极限性能优先"; GUID="e9a42b02-d5df-448d-aa00-03f14749eb61"; Color=$Theme.Accent}
        @{Title="平衡优化模式"; Desc="平衡基础上优化，禁用USB挂起`n适合笔记本电池模式"; GUID="381b4222-f694-41f0-9685-ff5bb260df2e"; Color=$Theme.Warning}
    )

    $yPlan = 112
    $script:radioPowers = @()
    for ($i = 0; $i -lt 3; $i++) {
        $p = $script:plans[$i]
        $card = New-Object System.Windows.Forms.Panel
        $card.Location = New-Object System.Drawing.Point(20, $yPlan)
        $card.Size = New-Object System.Drawing.Size(760, 68)
        $card.BackColor = $Theme.BgCard
        $page.Controls.Add($card)

        $rb = New-Object System.Windows.Forms.RadioButton
        $rb.Location = New-Object System.Drawing.Point(12, 20)
        $rb.Size = New-Object System.Drawing.Size(24, 24)
        $rb.Checked = ($i -eq 0)
        $rb.BackColor = $Theme.BgCard
        $rb.ForeColor = $p.Color
        $card.Controls.Add($rb)
        $script:radioPowers += $rb

        $lblP = New-Label $p.Title 44 14 250 26 $Fonts.Header $p.Color
        $card.Controls.Add($lblP)

        $lblPDesc = New-Label $p.Desc 44 38 700 30 $Fonts.Small $Theme.TextDim
        $card.Controls.Add($lblPDesc)

        $yPlan += 76
    }

    # 选项
    $script:chkUSB = New-Object System.Windows.Forms.CheckBox
    $script:chkUSB.Location = New-Object System.Drawing.Point(20, $yPlan)
    $script:chkUSB.Size = New-Object System.Drawing.Size(300, 24)
    $script:chkUSB.Text = "禁用 USB 选择性挂起"
    $script:chkUSB.Checked = $true
    $script:chkUSB.Font = $Fonts.Body
    $script:chkUSB.ForeColor = $Theme.TextMain
    $script:chkUSB.BackColor = $Theme.BgDark
    $page.Controls.Add($script:chkUSB)

    $script:chkPCI = New-Object System.Windows.Forms.CheckBox
    $script:chkPCI.Location = New-Object System.Drawing.Point(330, $yPlan)
    $script:chkPCI.Size = New-Object System.Drawing.Size(300, 24)
    $script:chkPCI.Text = "关闭 PCI Express 电源管理"
    $script:chkPCI.Checked = $true
    $script:chkPCI.Font = $Fonts.Body
    $script:chkPCI.ForeColor = $Theme.TextMain
    $script:chkPCI.BackColor = $Theme.BgDark
    $page.Controls.Add($script:chkPCI)

    $yPlan += 32

    $script:btnApplyPower = New-Button "应用电源计划" 20 ([int]($yPlan + 10)) 200 44 $Theme.Success 11
    $script:btnApplyPower.Add_Click({
        $script:btnApplyPower.Enabled = $false
        $script:btnApplyPower.Text = "应用中..."
        Invoke-UIRefresh
        try {
            $summary = Invoke-PowerOptimization
            $newPlan = @(powercfg /getactivescheme 2>&1) -join ' '
            $script:lblCurrent.Text = "当前计划: $newPlan"
            [System.Windows.Forms.MessageBox]::Show("$summary！", "完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            Write-Log "电源计划出错: $($_.Exception.Message)" "ERROR"
            [System.Windows.Forms.MessageBox]::Show("电源计划出错: $($_.Exception.Message)", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        } finally {
            $script:btnApplyPower.Enabled = $true
            $script:btnApplyPower.Text = "应用电源计划"
        }
    })
    $page.Controls.Add($script:btnApplyPower)
}

# ============================================================
#  页面 7: 磁盘优化
# ============================================================
$pageDisk = New-Page "Disk"
$script:Pages["Disk"] = $pageDisk

function Build-DiskPage {
    $page = $script:Pages["Disk"]
    $page.Controls.Clear()

    $lblTitle = New-Label "磁盘优化" 20 10 500 30 $Fonts.Header $Theme.TextBright
    $page.Controls.Add($lblTitle)

    $lblDesc = New-Label "SSD 执行 TRIM 优化 / HDD 执行碎片整理 / 清理系统组件" 20 42 760 24 $Fonts.Small $Theme.TextDim
    $page.Controls.Add($lblDesc)

    # 磁盘列表 - 使用兼容函数
    $physicalDisks = @(Get-PhysicalDiskCompat)

    $yDisk = 76
    $lblDiskInfo = New-Label "物理磁盘:" 20 $yDisk 760 24 $Fonts.Sub $Theme.Accent
    $page.Controls.Add($lblDiskInfo)
    $yDisk += 30

    foreach ($pd in $physicalDisks) {
        $sizeGB = if ($pd.Size) { [math]::Round([double]$pd.Size / 1GB, 0) } else { 0 }
        $typeColor = if ($pd.MediaType -eq "SSD") { $Theme.Success } else { $Theme.Warning }
        $card = New-Object System.Windows.Forms.Panel
        $card.Location = New-Object System.Drawing.Point(20, $yDisk)
        $card.Size = New-Object System.Drawing.Size(760, 44)
        $card.BackColor = $Theme.BgCard
        $page.Controls.Add($card)

        $lbl = New-Label "$($pd.FriendlyName)" 16 6 350 20 $Fonts.Body $Theme.TextBright
        $card.Controls.Add($lbl)

        $lblType = New-Label "类型: $($pd.MediaType)" 16 24 200 18 $Fonts.Small $typeColor
        $card.Controls.Add($lblType)

        $lblSize = New-Label "容量: ${sizeGB}GB" 260 24 200 18 $Fonts.Small $Theme.TextDim
        $card.Controls.Add($lblSize)

        $yDisk += 50
    }

    # 操作选项
    $yDisk += 10
    $script:chkTRIM = New-Object System.Windows.Forms.CheckBox
    $script:chkTRIM.Location = New-Object System.Drawing.Point(20, $yDisk)
    $script:chkTRIM.Size = New-Object System.Drawing.Size(250, 24)
    $script:chkTRIM.Text = "SSD TRIM 优化"
    $script:chkTRIM.Checked = $true
    $script:chkTRIM.Font = $Fonts.Body
    $script:chkTRIM.ForeColor = $Theme.TextMain
    $script:chkTRIM.BackColor = $Theme.BgDark
    $page.Controls.Add($script:chkTRIM)

    $script:chkDefrag = New-Object System.Windows.Forms.CheckBox
    $script:chkDefrag.Location = New-Object System.Drawing.Point(280, $yDisk)
    $script:chkDefrag.Size = New-Object System.Drawing.Size(250, 24)
    $script:chkDefrag.Text = "HDD 碎片整理"
    $script:chkDefrag.Checked = $true
    $script:chkDefrag.Font = $Fonts.Body
    $script:chkDefrag.ForeColor = $Theme.TextMain
    $script:chkDefrag.BackColor = $Theme.BgDark
    $page.Controls.Add($script:chkDefrag)

    $script:chkWinSxS = New-Object System.Windows.Forms.CheckBox
    $script:chkWinSxS.Location = New-Object System.Drawing.Point(20, [int]($yDisk + 30))
    $script:chkWinSxS.Size = New-Object System.Drawing.Size(250, 24)
    $script:chkWinSxS.Text = "清理 WinSxS 组件存储"
    $script:chkWinSxS.Checked = $true
    $script:chkWinSxS.Font = $Fonts.Body
    $script:chkWinSxS.ForeColor = $Theme.TextMain
    $script:chkWinSxS.BackColor = $Theme.BgDark
    $page.Controls.Add($script:chkWinSxS)

    $script:chkCompact = New-Object System.Windows.Forms.CheckBox
    $script:chkCompact.Location = New-Object System.Drawing.Point(280, [int]($yDisk + 30))
    $script:chkCompact.Size = New-Object System.Drawing.Size(250, 24)
    $script:chkCompact.Text = "压缩系统文件 (CompactOS)"
    $script:chkCompact.Checked = $false
    $script:chkCompact.Font = $Fonts.Body
    $script:chkCompact.ForeColor = $Theme.TextMain
    $script:chkCompact.BackColor = $Theme.BgDark
    $page.Controls.Add($script:chkCompact)

    $yDisk += 70

    $script:btnDiskOpt = New-Button "开始优化" 20 $yDisk 200 44 $Theme.Success 11
    $script:btnDiskOpt.Add_Click({
        $script:btnDiskOpt.Enabled = $false
        $script:btnDiskOpt.Text = "优化中...(可能需要数分钟)"
        Invoke-UIRefresh
        try {
            $summary = Invoke-DiskOptimization
            [System.Windows.Forms.MessageBox]::Show($summary, "完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            Write-Log "磁盘优化出错: $($_.Exception.Message)" "ERROR"
            [System.Windows.Forms.MessageBox]::Show("磁盘优化出错: $($_.Exception.Message)", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        } finally {
            $script:btnDiskOpt.Enabled = $true
            $script:btnDiskOpt.Text = "开始优化"
        }
    })
    $page.Controls.Add($script:btnDiskOpt)
}

# ============================================================
#  页面 8: 网络优化
# ============================================================
$pageNet = New-Page "Network"
$script:Pages["Network"] = $pageNet

function Build-NetworkPage {
    $page = $script:Pages["Network"]
    $page.Controls.Clear()

    $lblTitle = New-Label "网络优化" 20 10 500 30 $Fonts.Header $Theme.TextBright
    $page.Controls.Add($lblTitle)

    $lblDesc = New-Label "优化 DNS 和网络参数以提升网络响应速度" 20 42 760 24 $Fonts.Small $Theme.TextDim
    $page.Controls.Add($lblDesc)

    # DNS 选项
    $y = 80
    $lblDNS = New-Label "DNS 设置:" 20 $y 100 24 $Fonts.Body $Theme.TextBright
    $page.Controls.Add($lblDNS)

    $script:cbDNS = New-Object System.Windows.Forms.ComboBox
    $script:cbDNS.Location = New-Object System.Drawing.Point(130, [int]($y - 2))
    $script:cbDNS.Size = New-Object System.Drawing.Size(300, 28)
    $script:cbDNS.Font = $Fonts.Body
    $script:cbDNS.BackColor = $Theme.BgInput
    $script:cbDNS.ForeColor = $Theme.TextMain
    $script:cbDNS.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $script:cbDNS.Items.Add("保持当前 DNS") | Out-Null
    $script:cbDNS.Items.Add("Cloudflare (1.1.1.1 / 1.0.0.1)") | Out-Null
    $script:cbDNS.Items.Add("Google (8.8.8.8 / 8.8.4.4)") | Out-Null
    $script:cbDNS.Items.Add("阿里 DNS (223.5.5.5 / 223.6.6.6)") | Out-Null
    $script:cbDNS.Items.Add("114 DNS (114.114.114.114 / 114.114.115.115)") | Out-Null
    $script:cbDNS.SelectedIndex = 0
    $page.Controls.Add($script:cbDNS)

    $y += 40

    $script:chkTCP = New-Object System.Windows.Forms.CheckBox
    $script:chkTCP.Location = New-Object System.Drawing.Point(20, $y)
    $script:chkTCP.Size = New-Object System.Drawing.Size(300, 24)
    $script:chkTCP.Text = "TCP 自动调优 (Auto Tuning)"
    $script:chkTCP.Checked = $true
    $script:chkTCP.Font = $Fonts.Body
    $script:chkTCP.ForeColor = $Theme.TextMain
    $script:chkTCP.BackColor = $Theme.BgDark
    $page.Controls.Add($script:chkTCP)

    $y += 30

    $script:chkRSS = New-Object System.Windows.Forms.CheckBox
    $script:chkRSS.Location = New-Object System.Drawing.Point(20, $y)
    $script:chkRSS.Size = New-Object System.Drawing.Size(300, 24)
    $script:chkRSS.Text = "RSS 接收端缩放"
    $script:chkRSS.Checked = $true
    $script:chkRSS.Font = $Fonts.Body
    $script:chkRSS.ForeColor = $Theme.TextMain
    $script:chkRSS.BackColor = $Theme.BgDark
    $page.Controls.Add($script:chkRSS)

    $y += 30

    $script:chkRSC = New-Object System.Windows.Forms.CheckBox
    $script:chkRSC.Location = New-Object System.Drawing.Point(20, $y)
    $script:chkRSC.Size = New-Object System.Drawing.Size(300, 24)
    $script:chkRSC.Text = "RSC 接收段合并"
    $script:chkRSC.Checked = $true
    $script:chkRSC.Font = $Fonts.Body
    $script:chkRSC.ForeColor = $Theme.TextMain
    $script:chkRSC.BackColor = $Theme.BgDark
    $page.Controls.Add($script:chkRSC)

    $y += 30

    $script:chkDNSCache = New-Object System.Windows.Forms.CheckBox
    $script:chkDNSCache.Location = New-Object System.Drawing.Point(20, $y)
    $script:chkDNSCache.Size = New-Object System.Drawing.Size(300, 24)
    $script:chkDNSCache.Text = "刷新 DNS 缓存"
    $script:chkDNSCache.Checked = $true
    $script:chkDNSCache.Font = $Fonts.Body
    $script:chkDNSCache.ForeColor = $Theme.TextMain
    $script:chkDNSCache.BackColor = $Theme.BgDark
    $page.Controls.Add($script:chkDNSCache)

    $y += 40

    $lblCurDNS = New-Label "当前 DNS:" 20 $y 760 24 $Fonts.Small $Theme.TextDim
    try {
        $adapters = Get-DnsClientServerAddressCompat
        $dnsText = $adapters | ForEach-Object { "$($_.InterfaceAlias): $($_.ServerAddresses -join ', ')" }
        $lblCurDNS.Text = "当前 DNS: $($dnsText -join ' | ')"
    } catch {}
    $page.Controls.Add($lblCurDNS)

    $y += 40

    $script:btnNetOpt = New-Button "开始优化" 20 $y 200 44 $Theme.Success 11
    $script:btnNetOpt.Add_Click({
        $script:btnNetOpt.Enabled = $false
        $script:btnNetOpt.Text = "优化中..."
        Invoke-UIRefresh
        try {
            $summary = Invoke-NetworkOptimization
            [System.Windows.Forms.MessageBox]::Show($summary, "完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            Write-Log "网络优化出错: $($_.Exception.Message)" "ERROR"
            [System.Windows.Forms.MessageBox]::Show("网络优化出错: $($_.Exception.Message)", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        } finally {
            $script:btnNetOpt.Enabled = $true
            $script:btnNetOpt.Text = "开始优化"
        }
    })
    $page.Controls.Add($script:btnNetOpt)
}

# ============================================================
#  页面 9: 备份恢复
# ============================================================
$pageBackup = New-Page "Backup"
$script:Pages["Backup"] = $pageBackup

function Build-BackupPage {
    $page = $script:Pages["Backup"]
    $page.Controls.Clear()

    $lblTitle = New-Label "备份恢复" 20 10 500 30 $Fonts.Header $Theme.TextBright
    $page.Controls.Add($lblTitle)

    $lblDesc = New-Label "管理优化操作的备份，可随时恢复" 20 42 760 24 $Fonts.Small $Theme.TextDim
    $page.Controls.Add($lblDesc)

    $y = 80

    $btnBackup = New-Button "创建备份" 20 $y 160 44 $Theme.Success 11
    $btnBackup.Add_Click({
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $script:BackupDir = Join-Path $script:ProjectRoot "backups"

        if (-not (Test-Path $script:BackupDir)) {
            New-Item -Path $script:BackupDir -ItemType Directory -Force | Out-Null
        }

        Write-Log "正在创建系统备份..."
        try {
            $startupFile = Join-Path $script:BackupDir "startup_$timestamp.csv"
            Get-CimData Win32_StartupCommand | Export-Csv $startupFile -NoTypeInformation -ErrorAction SilentlyContinue

            $svcFile = Join-Path $script:BackupDir "services_$timestamp.csv"
            Get-CimData Win32_Service | Select-Object Name, DisplayName, StartMode, State | Export-Csv $svcFile -NoTypeInformation

            $powerFile = Join-Path $script:BackupDir "power_$timestamp.txt"
            powercfg /list | Out-File $powerFile -Encoding UTF8

            $visFile = Join-Path $script:BackupDir "visual_$timestamp.txt"
            Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" | Out-File $visFile -Encoding UTF8

            Write-Log "备份已创建" "SUCCESS"
            [System.Windows.Forms.MessageBox]::Show("备份已创建成功！", "完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            Build-BackupPage
        } catch {
            Write-Log "备份创建失败: $_" "ERROR"
            [System.Windows.Forms.MessageBox]::Show("备份创建失败: $_", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })
    $page.Controls.Add($btnBackup)

    $btnRestore = New-Button "恢复最近备份" 200 $y 160 44 $Theme.Warning 11
    $btnRestore.Add_Click({
        $result = [System.Windows.Forms.MessageBox]::Show(
            "确定要从最近备份恢复吗？`n`n这将恢复服务、启动项和电源设置。",
            "确认恢复",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($result -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        $script:BackupDir = Join-Path $script:ProjectRoot "backups"
        if (-not (Test-Path $script:BackupDir)) {
            [System.Windows.Forms.MessageBox]::Show("未找到备份目录", "提示", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            return
        }

        Write-Log "开始从备份恢复..."
        $restored = 0

        $svcBackups = Get-ChildItem $script:BackupDir -Filter "services_*.csv" -ErrorAction SilentlyContinue | Sort-Object Name -Descending
        if ($svcBackups) {
            try {
                $svcs = Import-Csv $svcBackups[0].FullName
                foreach ($svc in $svcs) {
                    try {
                        if ($svc.StartMode -eq "Auto") {
                            Set-Service -Name $svc.Name -StartupType Automatic -ErrorAction SilentlyContinue
                        } elseif ($svc.StartMode -eq "Manual") {
                            Set-Service -Name $svc.Name -StartupType Manual -ErrorAction SilentlyContinue
                        } elseif ($svc.StartMode -eq "Disabled") {
                            Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction SilentlyContinue
                        }
                    } catch {}
                }
                Write-Log "服务状态已恢复" "SUCCESS"
                $restored++
            } catch { Write-Log "服务恢复失败" "WARN" }
        }

        $startupBackups = Get-ChildItem $script:BackupDir -Filter "startup_*.csv" -ErrorAction SilentlyContinue | Sort-Object Name -Descending
        if ($startupBackups) {
            try {
                $items = Import-Csv $startupBackups[0].FullName
                foreach ($item in $items) {
                    try {
                        $regPath = Split-Path $item.Location -Parent
                        $regName = Split-Path $item.Location -Leaf
                        if (Test-Path $regPath) {
                            New-ItemProperty -Path $regPath -Name $regName -Value $item.Command -Force -ErrorAction SilentlyContinue | Out-Null
                        }
                    } catch {}
                }
                Write-Log "启动项已恢复" "SUCCESS"
                $restored++
            } catch { Write-Log "启动项恢复失败" "WARN" }
        }

        if ($restored -gt 0) {
            Write-Log "恢复完成！恢复了 $restored 项" "SUCCESS"
        } else {
            Write-Log "未找到可恢复的备份" "WARN"
        }

        [System.Windows.Forms.MessageBox]::Show("恢复完成！请重启电脑使所有更改生效。", "完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    })
    $page.Controls.Add($btnRestore)

    $y += 56

    $lblBackupList = New-Label "备份列表:" 20 $y 760 24 $Fonts.Body $Theme.TextBright
    $page.Controls.Add($lblBackupList)

    $y += 26

    $dgvBackups = New-Object System.Windows.Forms.DataGridView
    $dgvBackups.Location = New-Object System.Drawing.Point(20, $y)
    $dgvBackups.Size = New-Object System.Drawing.Size(760, 250)
    $dgvBackups.BackgroundColor = $Theme.BgPanel
    $dgvBackups.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dgvBackups.AllowUserToAddRows = $false
    $dgvBackups.AllowUserToDeleteRows = $false
    $dgvBackups.AllowUserToResizeRows = $false
    $dgvBackups.ReadOnly = $true
    $dgvBackups.RowHeadersVisible = $false
    $dgvBackups.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $dgvBackups.DefaultCellStyle.BackColor = $Theme.BgPanel
    $dgvBackups.DefaultCellStyle.ForeColor = $Theme.TextMain
    $dgvBackups.DefaultCellStyle.SelectionBackColor = $Theme.AccentDark
    $dgvBackups.DefaultCellStyle.SelectionForeColor = $Theme.TextBright
    $dgvBackups.ColumnHeadersDefaultCellStyle.BackColor = $Theme.BgCard
    $dgvBackups.ColumnHeadersDefaultCellStyle.ForeColor = $Theme.TextBright
    $dgvBackups.EnableHeadersVisualStyles = $false

    $dgvBackups.Columns.Add("Name", "备份文件") | Out-Null
    $dgvBackups.Columns.Add("Date", "日期") | Out-Null
    $dgvBackups.Columns.Add("Type", "类型") | Out-Null
    $dgvBackups.Columns.Add("Size", "大小") | Out-Null

    $script:BackupDir = Join-Path $script:ProjectRoot "backups"
    if (Test-Path $script:BackupDir) {
        $backupFiles = Get-ChildItem $script:BackupDir -File | Sort-Object LastWriteTime -Descending | Select-Object -First 50
        foreach ($b in $backupFiles) {
            $type = if ($b.Name -like "services_*") { "服务备份" }
                    elseif ($b.Name -like "startup_*") { "启动项备份" }
                    elseif ($b.Name -like "power_*") { "电源计划备份" }
                    elseif ($b.Name -like "visual_*") { "视觉效果备份" }
                    else { "其他" }
            $size = if ($b.Length -gt 1KB) { "$([math]::Round($b.Length/1KB, 1)) KB" } else { "$($b.Length) B" }
            $dgvBackups.Rows.Add($b.Name, $b.LastWriteTime.ToString("yyyy-MM-dd HH:mm"), $type, $size) | Out-Null
        }
    }

    $page.Controls.Add($dgvBackups)

    $y += 260

    $btnRestoreSel = New-Button "恢复选中备份" 20 $y 160 44 $Theme.Warning 11
    $btnRestoreSel.Add_Click({
        if ($dgvBackups.SelectedRows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("请先选择一行备份", "提示", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            return
        }
        $selectedFile = $dgvBackups.SelectedRows[0].Cells["Name"].Value
        $selectedPath = Join-Path $script:BackupDir $selectedFile

        if (-not (Test-Path $selectedPath)) {
            [System.Windows.Forms.MessageBox]::Show("备份文件不存在", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }

        $result = [System.Windows.Forms.MessageBox]::Show(
            "确定要恢复备份: $selectedFile 吗？",
            "确认恢复",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($result -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        Write-Log "正在恢复: $selectedFile"

        if ($selectedFile -like "services_*.csv") {
            try {
                $svcs = Import-Csv $selectedPath
                foreach ($svc in $svcs) {
                    try {
                        if ($svc.StartMode -eq "Auto") {
                            Set-Service -Name $svc.Name -StartupType Automatic -ErrorAction SilentlyContinue
                        } elseif ($svc.StartMode -eq "Manual") {
                            Set-Service -Name $svc.Name -StartupType Manual -ErrorAction SilentlyContinue
                        } elseif ($svc.StartMode -eq "Disabled") {
                            Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction SilentlyContinue
                        }
                    } catch {}
                }
                Write-Log "服务已从备份恢复" "SUCCESS"
            } catch { Write-Log "服务恢复失败" "ERROR" }
        }
        elseif ($selectedFile -like "startup_*.csv") {
            try {
                $items = Import-Csv $selectedPath
                foreach ($item in $items) {
                    try {
                        $regPath = Split-Path $item.Location -Parent
                        $regName = Split-Path $item.Location -Leaf
                        if (Test-Path $regPath) {
                            New-ItemProperty -Path $regPath -Name $regName -Value $item.Command -Force -ErrorAction SilentlyContinue | Out-Null
                        }
                    } catch {}
                }
                Write-Log "启动项已从备份恢复" "SUCCESS"
            } catch { Write-Log "启动项恢复失败" "ERROR" }
        }

        [System.Windows.Forms.MessageBox]::Show("恢复完成！请重启电脑使所有更改生效。", "完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    })
    $page.Controls.Add($btnRestoreSel)

    $btnRefreshBackup = New-Button "刷新列表" 200 $y 120 44 $Theme.AccentDark 10
    $btnRefreshBackup.Add_Click({ Build-BackupPage })
    $page.Controls.Add($btnRefreshBackup)
}

# ============================================================
#  页面 10: 关于
# ============================================================
$pageAbout = New-Page "About"
$script:Pages["About"] = $pageAbout

function Build-AboutPage {
    $page = $script:Pages["About"]
    $page.Controls.Clear()

    $lblAboutTitle = New-Label "PC-Optimizer-7thGen" 20 20 760 36 $Fonts.Title $Theme.Accent
    $page.Controls.Add($lblAboutTitle)

    $lblVer = New-Label "版本 v$Version" 20 60 760 24 $Fonts.Sub $Theme.TextDim
    $page.Controls.Add($lblVer)

    $aboutText = @"
专为 7 代及更老 CPU 的 Windows 电脑设计
兼容 Windows 7 / 8 / 10 / 11 (PS 2.0+)

功能特性:
  - 垃圾文件清理（临时文件、缓存、回收站等）
  - 服务优化（禁用遥测、Xbox、传感器等非必要服务）
  - 启动项管理（扫描注册表和启动文件夹）
  - 视觉效果优化（最佳性能/平衡/自定义）
  - 电源计划优化（高性能/卓越性能/平衡）
  - 磁盘优化（SSD TRIM / HDD 碎片整理 / 系统压缩）
  - 网络优化（DNS 设置 / TCP 调优 / RSS RSC）
  - 备份恢复（服务/启动项/电源计划备份）

Win7 兼容性:
  - 自动检测操作系统版本
  - PS 2.0 下回退到 Get-WmiObject
  - Win7 下用 netsh 替代 NetAdapter cmdlet
  - Win7 下用 schtasks 替代 ScheduledTask cmdlet
  - Win7 下用 COM 对象清空回收站

安全特性:
  - 所有操作前自动创建备份
  - 不修改系统核心文件
  - 不安装第三方软件
  - 操作日志记录在 optimize.log

使用提示:
  - 优化前建议先创建备份
  - 优化后重启电脑使更改生效
  - 笔记本电池模式建议使用平衡电源计划
"@ 

    $lblAbout = New-Object System.Windows.Forms.Label
    $lblAbout.Location = New-Object System.Drawing.Point(20, 100)
    $lblAbout.Size = New-Object System.Drawing.Size(760, 480)
    $lblAbout.Text = $aboutText
    $lblAbout.Font = $Fonts.Body
    $lblAbout.ForeColor = $Theme.TextMain
    $lblAbout.BackColor = [System.Drawing.Color]::Transparent
    $page.Controls.Add($lblAbout)
}

# ============================================================
#  日志面板
# ============================================================
$logSplit = New-Object System.Windows.Forms.SplitContainer
$logSplit.Dock = [System.Windows.Forms.DockStyle]::Bottom
$logSplit.Height = 140
$logSplit.BackColor = $Theme.BgDark
$logSplit.SplitterWidth = 1
$logSplit.Panel1.BackColor = $Theme.BgDark
$logSplit.Panel2.BackColor = $Theme.BgDark
$logSplit.FixedPanel = [System.Windows.Forms.FixedPanel]::Panel1
$logSplit.Panel1MinSize = 80
$logSplit.SplitterDistance = 80
# 日志面板放到 contentPanel 而非 pageContainer，避免遮挡页面内容
$contentPanel.Controls.Add($logSplit)

# 日志标题
$lblLogTitle = New-Object System.Windows.Forms.Label
$lblLogTitle.Dock = [System.Windows.Forms.DockStyle]::Top
$lblLogTitle.Height = 24
$lblLogTitle.Text = "  操作日志"
$lblLogTitle.Font = $Fonts.Sub
$lblLogTitle.ForeColor = $Theme.Accent
$lblLogTitle.BackColor = $Theme.BgPanel
$logSplit.Panel1.Controls.Add($lblLogTitle)

# 清空日志按钮
$btnClearLog = New-Object System.Windows.Forms.Button
$btnClearLog.Dock = [System.Windows.Forms.DockStyle]::Fill
$btnClearLog.Text = "清空"
$btnClearLog.Font = $Fonts.Small
$btnClearLog.ForeColor = $Theme.TextDim
$btnClearLog.BackColor = $Theme.BgPanel
$btnClearLog.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClearLog.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnClearLog.Add_Click({
    $script:LogTextBox.Clear()
})
$logSplit.Panel1.Controls.Add($btnClearLog)

# 日志文本框
$script:LogTextBox = New-Object System.Windows.Forms.RichTextBox
$script:LogTextBox.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:LogTextBox.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 35)
$script:LogTextBox.ForeColor = $Theme.TextDim
$script:LogTextBox.Font = $Fonts.Mono
$script:LogTextBox.ReadOnly = $true
$script:LogTextBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$script:LogTextBox.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$logSplit.Panel2.Controls.Add($script:LogTextBox)

# ============================================================
#  构建所有页面
# ============================================================
Build-Dashboard
Build-CleanPage
Build-ServicesPage
Build-StartupPage
Build-VisualPage
Build-PowerPage
Build-DiskPage
Build-NetworkPage
Build-BackupPage
Build-AboutPage

# 将所有页面添加到容器
foreach ($key in $script:Pages.Keys) {
    $pageContainer.Controls.Add($script:Pages[$key])
    $script:Pages[$key].BringToFront()
}
# 确保日志在最前
$logSplit.BringToFront()
# 确保 pageContainer 在日志之下但不被遮挡
$pageContainer.SendToBack()

# ============================================================
#  侧边栏标题映射
# ============================================================
$script:HeaderTitles = @{
    "Dashboard" = "系统仪表盘"
    "Clean"     = "垃圾清理"
    "Services"  = "服务优化"
    "Startup"   = "启动项管理"
    "Visual"    = "视觉效果"
    "Power"     = "电源计划"
    "Disk"      = "磁盘优化"
    "Network"   = "网络优化"
    "Backup"    = "备份恢复"
    "About"     = "关于"
}
$script:HeaderLabel = $lblHeader

# ============================================================
#  启动
# ============================================================
Write-Log "===== PC-Optimizer-7thGen GUI v$Version 启动 ====="
Write-Log "GUI 已就绪，请选择左侧功能进行优化操作。"

# 显示窗口
$MainForm.ShowDialog() | Out-Null
Write-Log "===== GUI 退出 ====="

# 清理
$MainForm.Dispose()

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
#  编码环境初始化（PowerShell 5.1 中文乱码根治）
#  PS 5.1 捕获外部命令行工具（schtasks/sc/netsh/powercfg 等）输出时，
#  默认按 UTF-8 解码系统 ANSI(GBK) 输出，导致中文变问号。
#  这里将标准输出/管道编码统一设为系统默认(GBK)，保证读取到的中文正确。
# ============================================================
try {
    $ansi = [System.Text.Encoding]::Default
    [System.Console]::OutputEncoding = $ansi
    $OutputEncoding = $ansi
} catch {}
# 提供统一的编码校正辅助函数：把可能被错误解码的字符串还原为正确中文
function Repair-StringEncoding {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return [System.Text.Encoding]::Default.GetString($bytes)
    } catch {
        return $Text
    }
}

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
$script:Version     = "3.0.0"

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

    $hasNewline = ($Text -match "`n")

    if ($W -ge 500) {
        if ($hasNewline) {
            # 含换行：按实际行数自动计算高度，避免第二行被裁切
            $lbl.AutoSize = $true
            $lbl.AutoEllipsis = $false
            $lbl.MaximumSize = New-Object System.Drawing.Size([int]$W, 0)
            $lbl.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
        } else {
            # 宽 Label（描述/说明类，单行）跟随父容器宽度自适应
            # 避免窗口拉窄时被右侧裁切，也不会被不当地横向拉伸
            $lbl.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
            $lbl.AutoSize = $false
            # 高度 0 表示不限，让其按内容自动纵向扩展
            $lbl.MaximumSize = New-Object System.Drawing.Size(0, 0)
        }
    } elseif ($hasNewline) {
        # 窄 Label 但含换行：同样自动高度
        $lbl.AutoSize = $true
        $lbl.AutoEllipsis = $false
        $lbl.MaximumSize = New-Object System.Drawing.Size([int]$W, 0)
    }
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
$MainForm.Text = "PC-Optimizer-7thGen  v$($script:Version)"
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
$sidePanel.AutoScroll = $true
$sidePanel.AutoScrollMinSize = New-Object System.Drawing.Size(0, 680)
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
    @{Key="Update";    Text="更新与功能"}
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
        # 切换到目标页面时重置其滚动位置，避免残留偏移导致内容被裁
        $script:Pages[$key].AutoScrollPosition = New-Object System.Drawing.Point(0, 0)
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
#  内容区域（右侧主面板）— 用 SplitContainer 上下分区，根除遮挡
#  Panel1（上）: 页面区（标题栏 + 页面宿主），自动占满剩余空间
#  Panel2（下）: 日志面板（固定 140px），与页面区完全独立、互不重叠
# ============================================================
$contentPanel = New-Object System.Windows.Forms.SplitContainer
$contentPanel.Orientation = [System.Windows.Forms.Orientation]::Horizontal
$contentPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$contentPanel.BackColor = $Theme.BgDark
$contentPanel.SplitterWidth = 1
$contentPanel.Panel1.BackColor = [System.Drawing.Color]::Transparent
$contentPanel.Panel2.BackColor = $Theme.BgDark
$contentPanel.FixedPanel = [System.Windows.Forms.FixedPanel]::Panel2
$contentPanel.Panel2MinSize = 140
# 不手动设 SplitterDistance（避免构造期宽度未定导致越界异常），
# 依赖 FixedPanel=Panel2 + Panel2MinSize=140 让日志面板固定 140px、页面区占满剩余空间
$mainLayout.Controls.Add($contentPanel, 1, 0)

# 页面容器（分层：顶部标题栏 + 页面宿主，互不重叠，避免遮挡页面内容）
$pageContainer = New-Object System.Windows.Forms.Panel
# 在 SplitContainer.Panel1 中 Dock=Fill，占满页面区（已与底部日志 Panel2 完全独立）
$pageContainer.BackColor = [System.Drawing.Color]::Transparent
$pageContainer.Dock = [System.Windows.Forms.DockStyle]::Fill
$contentPanel.Panel1.Controls.Add($pageContainer)

# 顶部标题栏（常驻 pageContainer 顶部；pagesHost 后添加 Dock=Fill 会自动避让到其下方）
# 只创建一次 headerPanel，避免重复创建导致两个 Dock=Top 控件堆叠占用 100px 顶部空间（视觉上形成空色块）
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Location = New-Object System.Drawing.Point(0, 0)
$headerPanel.Size = New-Object System.Drawing.Size(804, 50)
$headerPanel.BackColor = $Theme.BgPanel
$headerPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$pageContainer.Controls.Add($headerPanel)

$lblHeader = New-Object System.Windows.Forms.Label
$lblHeader.Location = New-Object System.Drawing.Point(20, 0)
$lblHeader.Size = New-Object System.Drawing.Size(400, 50)
$lblHeader.Text = "系统仪表盘"
$lblHeader.Font = $Fonts.Header
$lblHeader.ForeColor = $Theme.TextBright
$lblHeader.BackColor = $Theme.BgPanel
$lblHeader.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$headerPanel.Controls.Add($lblHeader)

# 页面宿主（位于标题栏之下，承载所有页面；Dock=Fill 在 headerPanel 之后添加，自动避让到其下方）
$pagesHost = New-Object System.Windows.Forms.Panel
$pagesHost.BackColor = [System.Drawing.Color]::Transparent
$pagesHost.Dock = [System.Windows.Forms.DockStyle]::Fill
$pageContainer.Controls.Add($pagesHost)

# ============================================================
#  页面集合
# ============================================================
$script:Pages = @{}

# ============================================================
#  加载页面函数（开发模式 dot-source；编译模式函数已内联，自动跳过）
# ============================================================
$pageLoader = @(
    "gui/pages/Dashboard.ps1", "gui/pages/Clean.ps1", "gui/pages/Services.ps1",
    "gui/pages/Startup.ps1", "gui/pages/Visual.ps1", "gui/pages/Power.ps1",
    "gui/pages/Disk.ps1", "gui/pages/Network.ps1", "gui/pages/Backup.ps1",
    "gui/pages/Update.ps1", "gui/pages/About.ps1", "gui/UpdateCheck.ps1"
)
foreach ($pf in $pageLoader) {
    $pfPath = Join-Path $script:ProjectRoot $pf
    if (Test-Path $pfPath) { . $pfPath }
}


# --- 辅助：创建页面面板 ---
function New-Page {
    param([string]$Title)
    $page = New-Object System.Windows.Forms.Panel
    # 不设置 Dock，由 Reposition-PageControls 在 Resize/Shown 时按 pagesHost.ClientSize 主动定位 (0,0) 并铺满
    # （必须显式赋 Location+Size，否则页面将保持默认 (0,0,200,100)，所有页面会叠在 pagesHost 左上角遮挡标题栏）
    $page.AutoScroll = $true
    $page.AutoScrollMinSize = New-Object System.Drawing.Size(0, 0)
    $page.BackColor = [System.Drawing.Color]::Transparent
    $page.Visible = $false
    return $page
}

# ============================================================
#  页面 1: 系统仪表盘
# ============================================================
$pageDash = New-Page "Dashboard"
$script:Pages["Dashboard"] = $pageDash


# ============================================================
#  页面 2: 垃圾清理
# ============================================================
$pageClean = New-Page "Clean"
$script:Pages["Clean"] = $pageClean


# ============================================================
#  页面 3: 服务优化
# ============================================================
$pageSvc = New-Page "Services"
$script:Pages["Services"] = $pageSvc


# ============================================================
#  页面 4: 启动项
# ============================================================
$pageStartup = New-Page "Startup"
$script:Pages["Startup"] = $pageStartup


# ============================================================
#  页面 5: 视觉效果
# ============================================================
$pageVisual = New-Page "Visual"
$script:Pages["Visual"] = $pageVisual


# ============================================================
#  页面 6: 电源计划
# ============================================================
$pagePower = New-Page "Power"
$script:Pages["Power"] = $pagePower


# ============================================================
#  页面 7: 磁盘优化
# ============================================================
$pageDisk = New-Page "Disk"
$script:Pages["Disk"] = $pageDisk


# ============================================================
#  页面 8: 网络优化
# ============================================================
$pageNet = New-Page "Network"
$script:Pages["Network"] = $pageNet


# ============================================================
#  页面 9: 备份恢复
# ============================================================
$pageBackup = New-Page "Backup"
$script:Pages["Backup"] = $pageBackup


# ============================================================
#  页面 9.5: 更新与功能
# ============================================================
$pageUpdate = New-Page "Update"
$script:Pages["Update"] = $pageUpdate


# ============================================================
#  页面 10: 关于
# ============================================================
$pageAbout = New-Page "About"
$script:Pages["About"] = $pageAbout



# ============================================================
#  日志面板
# ============================================================
$logSplit = New-Object System.Windows.Forms.SplitContainer
$logSplit.Dock = [System.Windows.Forms.DockStyle]::Fill
$logSplit.BackColor = $Theme.BgDark
$logSplit.SplitterWidth = 1
$logSplit.Panel1.BackColor = $Theme.BgDark
$logSplit.Panel2.BackColor = $Theme.BgDark
$logSplit.FixedPanel = [System.Windows.Forms.FixedPanel]::Panel1
$logSplit.Panel1MinSize = 80
$logSplit.SplitterDistance = 80
# 日志面板放到 SplitContainer.Panel2（固定 140px），与页面区完全独立、互不遮挡
$contentPanel.Panel2.Controls.Add($logSplit)

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
Build-UpdatePage
Build-AboutPage

# 将所有页面添加到页面宿主（pagesHost 位于标题栏之下、日志之上，互不遮挡）
foreach ($key in $script:Pages.Keys) {
    $pagesHost.Controls.Add($script:Pages[$key])
    $script:Pages[$key].BringToFront()
}

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
    "Update"    = "更新与功能"
    "About"     = "关于"
}
$script:HeaderLabel = $lblHeader

# ============================================================
#  启动
# ============================================================
Write-Log "===== PC-Optimizer-7thGen GUI v$Version 启动 ====="
Write-Log "GUI 已就绪，请选择左侧功能进行优化操作。"

# 主窗体 Resize 时强制所有页面按当前尺寸重排（让内容自适应、不被裁切）
function Reposition-PageControls {
    param($Page)
    if (-not $Page) { return }
    try {
        # 使用父容器（pagesHost）的实际客户区宽度，避免写死尺寸导致 ClientSize 失真
        $parentW = if ($Page.Parent) { $Page.Parent.ClientSize.Width } else { $Page.ClientSize.Width }
        $parentH = if ($Page.Parent) { $Page.Parent.ClientSize.Height } else { $Page.ClientSize.Height }
        # 先把页面本身定位到 (0,0) 并撑满整个 pagesHost —— 否则所有页面会保持默认 (0,0,200,100) 叠在 pagesHost 左上角
        if ($Page.Parent) {
            $Page.Location = New-Object System.Drawing.Point(0, 0)
            $Page.Size = New-Object System.Drawing.Size($parentW, $parentH)
        }
        $avail = [math]::Max(300, $parentW - 40)
        $maxW  = [math]::Min(760, $avail)
        foreach ($ctrl in $Page.Controls) {
            # 重排靠左的“宽”控件（卡片、宽 Label、列表等）
            if ($ctrl.Left -le 30 -and $ctrl.Width -ge 400) {
                $ctrl.Width = $maxW
                # 卡片内部子控件也按卡片宽度跟随，避免被拉宽超出卡片
                if ($ctrl -is [System.Windows.Forms.Panel]) {
                    foreach ($child in $ctrl.Controls) {
                        if ($child.Width -ge 300) { $child.Width = [math]::Max(200, $ctrl.Width - 32) }
                    }
                }
            }
        }
        # 计算内容总高（最底端控件的 Bottom + 边距），确保 AutoScroll 滚动条正确出现
        $maxBottom = 0
        foreach ($ctrl in $Page.Controls) {
            $bottom = $ctrl.Bottom
            if ($bottom -gt $maxBottom) { $maxBottom = $bottom }
        }
        # 内容总高 + 40 底部余量，作为 AutoScrollMinSize.Height，保证内容超出时一定显示滚动条
        $contentH = $maxBottom + 40
        $Page.AutoScrollMinSize = New-Object System.Drawing.Size(0, [int]$contentH)
        # 重置滚动位置到顶部，避免切换页面后内容偏移导致顶部被裁
        $Page.AutoScrollPosition = New-Object System.Drawing.Point(0, 0)
        $Page.PerformLayout()
    } catch {}
}

$MainForm.Add_Resize({
    foreach ($key in $script:Pages.Keys) {
        Reposition-PageControls $script:Pages[$key]
    }
})

# 首次显示前按当前 ClientSize 重排（防止初始尺寸下被裁切）
foreach ($key in $script:Pages.Keys) {
    Reposition-PageControls $script:Pages[$key]
}

# 启动后后台自动检查程序本体更新（静默，仅发现新版本时提示）
$MainForm.Add_Shown({ Start-BackgroundUpdateCheck })

# 显示窗口
$MainForm.ShowDialog() | Out-Null
Write-Log "===== GUI 退出 ====="

# 清理
$MainForm.Dispose()

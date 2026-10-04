<#
.SYNOPSIS
    在桌面创建启动快捷方式
.DESCRIPTION
    为一键向导与图形界面各建一个桌面快捷方式，让新用户双击即可启动，
    不必先找到安装目录，也不必面对多个启动脚本做选择。

    - 一键向导：指向 Start.bat（脚本自己请求管理员权限，默认项即向导）
    - 图形界面：指向 PC-Optimizer.exe（PS2EXE 打包版，自带管理员请求）

    图标优先使用 assets/app.ico（由 EXE 提取）；找不到时回退为 EXE 自身图标。
    重复执行安全：已存在的快捷方式会被刷新，描述与图标跟随当前版本。
.PARAMETER Desktop
    快捷方式目标目录，默认取当前用户桌面（含被重定向到 OneDrive 的桌面）。
.PARAMETER Force
    目标目录已存在同名快捷方式时也覆盖写入。
.EXAMPLE
    .\New-DesktopShortcuts.ps1
    在桌面创建两个快捷方式。
#>
param(
    [string]$Desktop = '',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# 定位项目根目录：正常情况脚本就在仓库根下；从别处调用时退回当前目录
$root = $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $root 'Start.bat'))) {
    $root = (Get-Location).Path
}

function Get-DesktopPath {
    param([string]$Explicit)
    if ($Explicit) { return [System.IO.Path]::GetFullPath($Explicit) }
    # 用特殊文件夹取桌面，能正确处理被重定向到 OneDrive 的情况
    $d = [Environment]::GetFolderPath('Desktop')
    if ([string]::IsNullOrWhiteSpace($d)) {
        $d = Join-Path $env:USERPROFILE 'Desktop'
    }
    return $d
}

function New-AppShortcut {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$TargetPath,
        [Parameter(Mandatory=$true)][string]$WorkingDirectory,
        [Parameter(Mandatory=$true)][string]$IconLocation,
        [Parameter(Mandatory=$true)][string]$Description
    )

    if (-not (Test-Path -LiteralPath $TargetPath)) {
        return [PSCustomObject]@{ ok = $false; path = $Path; error = ('目标文件不存在: ' + $TargetPath) }
    }

    $sc = $null
    $shell = $null
    try {
        $shell = New-Object -ComObject WScript.Shell
        $sc = $shell.CreateShortcut($Path)
        $sc.TargetPath       = $TargetPath
        $sc.WorkingDirectory = $WorkingDirectory
        $sc.IconLocation     = $IconLocation
        $sc.Description      = $Description
        $sc.Save()
        return [PSCustomObject]@{ ok = $true; path = $Path; error = $null }
    } catch {
        return [PSCustomObject]@{ ok = $false; path = $Path; error = $_.Exception.Message }
    } finally {
        if ($sc)    { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($sc) }
        if ($shell) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
    }
}

$desktop = Get-DesktopPath -Explicit $Desktop
if (-not (Test-Path -LiteralPath $desktop)) {
    try {
        New-Item -ItemType Directory -Path $desktop -Force | Out-Null
    } catch {
        Write-Host ('无法创建桌面目录: ' + $_.Exception.Message) -ForegroundColor Red
        exit 1
    }
}

$exe     = Join-Path $root 'PC-Optimizer.exe'
$start   = Join-Path $root 'Start.bat'
$iconIco = Join-Path $root 'assets\app.ico'
$icon    = if (Test-Path -LiteralPath $iconIco) { ($iconIco + ',0') } else { ($exe + ',0') }

Write-Host ''
Write-Host '================================================' -ForegroundColor Cyan
Write-Host '  创建桌面快捷方式' -ForegroundColor Cyan
Write-Host '================================================' -ForegroundColor Cyan
Write-Host ('项目目录: ' + $root)
Write-Host ('桌面目录: ' + $desktop)
Write-Host ('图标    : ' + $icon)
Write-Host ''

$results = @()
$results += New-AppShortcut -Path (Join-Path $desktop 'PC优化工具.lnk') -TargetPath $start -WorkingDirectory $root -IconLocation $icon -Description 'PC-Optimizer-7thGen 一键向导（体检 - 推荐 - 执行 - 复检）'
$results += New-AppShortcut -Path (Join-Path $desktop 'PC优化工具-图形界面.lnk') -TargetPath $exe -WorkingDirectory $root -IconLocation ($exe + ',0') -Description 'PC-Optimizer-7thGen 图形界面'

$failed = @($results | Where-Object { -not $_.ok })
foreach ($r in $results) {
    if ($r.ok) { Write-Host ('  [OK] ' + $r.path) -ForegroundColor Green }
    else       { Write-Host ('  [!!] ' + $r.path + ' -> ' + $r.error) -ForegroundColor Red }
}

Write-Host ''
if ($failed.Count -gt 0) {
    Write-Host ('完成，但有 ' + $failed.Count + ' 个失败（若缺少启动文件，先运行 Build-EXE.ps1）。') -ForegroundColor Yellow
    exit 1
}
Write-Host '完成。双击桌面图标即可启动；一键向导会自动请求管理员权限。' -ForegroundColor Green
exit 0

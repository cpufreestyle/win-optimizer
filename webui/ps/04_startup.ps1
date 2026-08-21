<#
.SYNOPSIS
    WebUI 启动项优化 — 列出/禁用，返回 JSON
.DESCRIPTION
    -Action list   : 列出所有启动项
    -Action disable: 禁用指定索引（items=1,3 或 all）
#>
param(
    [ValidateSet("list", "disable")]$Action = "list",
    [string]$Items = "all"
)

function Out-Json {
    param($obj)
    $obj | ConvertTo-Json -Depth 4 -Compress
}

$ErrorActionPreference = "Stop"
$backupDir = Join-Path $PSScriptRoot "..\..\backups"
$backupDir = [System.IO.Path]::GetFullPath($backupDir)

function Get-StartupItems {
    $items = @()
    $regPaths = @(
        @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Run";             Scope="当前用户";  Source="注册表"}
        @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce";         Scope="当前用户";  Source="注册表"}
        @{Path="HKLM:\Software\Microsoft\Windows\CurrentVersion\Run";             Scope="所有用户";  Source="注册表"}
        @{Path="HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce";         Scope="所有用户";  Source="注册表"}
        @{Path="HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; Scope="所有用户(32位)"; Source="注册表"}
    )
    foreach ($reg in $regPaths) {
        if (Test-Path $reg.Path) {
            $props = Get-ItemProperty -Path $reg.Path -ErrorAction SilentlyContinue
            if ($props) {
                $props.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" -and $_.Value } | ForEach-Object {
                    $items += [PSCustomObject]@{
                        name   = $_.Name
                        value  = $_.Value
                        scope  = $reg.Scope
                        source = $reg.Source
                        path   = $reg.Path
                    }
                }
            }
        }
    }
    $folders = @(
        @{Path="$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup";     Scope="当前用户"}
        @{Path="$env:PROGRAMDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Scope="所有用户"}
    )
    foreach ($f in $folders) {
        if (Test-Path $f.Path) {
            Get-ChildItem -Path $f.Path -ErrorAction SilentlyContinue | ForEach-Object {
                $items += [PSCustomObject]@{ name = $_.Name; value = $_.FullName; scope = $f.Scope; source = "启动文件夹"; path = $f.Path }
            }
        }
    }
    try {
        $apps = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue
        foreach ($app in $apps) {
            if ($items.Name -notcontains $app.Name) {
                $items += [PSCustomObject]@{ name = $app.Name; value = $app.Command; scope = $app.Location; source = "系统启动命令"; path = $app.Location }
            }
        }
    } catch {}
    $i = 0
    foreach ($it in $items) { $i++; Add-Member -InputObject $it -NotePropertyName index -NotePropertyValue $i -Force }
    return $items
}

try {
    if ($Action -eq "list") {
        $items = Get-StartupItems
        Out-Json ([PSCustomObject]@{ ok = $true; items = $items; count = $items.Count })
    }
    elseif ($Action -eq "disable") {
        $items = Get-StartupItems
        $targets = @()
        if ($Items -eq "all") { $targets = $items } else {
            $idxs = $Items -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^\d+$" }
            foreach ($it in $items) { if ($idxs -contains [string]$it.index) { $targets += $it } }
        }
        if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
        $backupFile = Join-Path $backupDir "startup_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $targets | Select-Object name, value, scope, source, path | Export-Csv -Path $backupFile -NoTypeInformation -Encoding UTF8

        $disabled = 0; $failed = 0; $details = @()
        foreach ($it in $targets) {
            try {
                if ($it.source -eq "注册表") {
                    Remove-ItemProperty -Path $it.path -Name $it.name -ErrorAction Stop
                    $disabled++; $details += [PSCustomObject]@{ name = $it.name; result = "已禁用" }
                }
                elseif ($it.source -eq "启动文件夹") {
                    $bkDir = Join-Path $backupDir "startup_items"
                    if (-not (Test-Path $bkDir)) { New-Item -ItemType Directory -Path $bkDir -Force | Out-Null }
                    Move-Item -Path $it.value -Destination (Join-Path $bkDir (Split-Path $it.value -Leaf)) -Force -ErrorAction Stop
                    $disabled++; $details += [PSCustomObject]@{ name = $it.name; result = "已禁用(已备份)" }
                }
                else {
                    $failed++; $details += [PSCustomObject]@{ name = $it.name; result = "跳过: 需任务管理器手动禁用" }
                }
            } catch {
                $failed++; $details += [PSCustomObject]@{ name = $it.name; result = "失败: $($_.Exception.Message)" }
            }
        }
        Out-Json ([PSCustomObject]@{ ok = $true; disabled = $disabled; failed = $failed; backup = $backupFile; details = $details })
    }
} catch {
    Out-Json ([PSCustomObject]@{ ok = $false; error = $_.Exception.Message })
}

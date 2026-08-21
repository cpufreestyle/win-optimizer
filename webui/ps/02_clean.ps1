<#
.SYNOPSIS
    WebUI 垃圾清理 — 扫描/清理，返回 JSON
.DESCRIPTION
    -Action scan : 返回可清理项列表（含预估大小）
    -Action clean: 清理指定索引（或 all）的项，返回结果
#>
param(
    [ValidateSet("scan", "clean")]$Action = "scan",
    [string]$Items = "all"   # 逗号分隔索引，或 "all"
)

function Out-Json {
    param($obj)
    $obj | ConvertTo-Json -Depth 4 -Compress
}

$ErrorActionPreference = "Stop"

$cleanDefs = @(
    @{Key="temp";     Path="C:\Windows\Temp";                                Name="Windows 系统临时文件"}
    @{Key="usertemp"; Path=$env:TEMP;                                         Name="用户临时文件"}
    @{Key="prefetch"; Path="C:\Windows\Prefetch";                            Name="预读取文件"}
    @{Key="wsus";     Path="C:\Windows\SoftwareDistribution\Download";       Name="Windows Update 下载缓存"}
    @{Key="thumb";    Path="$env:LOCALAPPDATA\Microsoft\Windows\Explorer";   Name="缩略图缓存"}
    @{Key="wer";      Path="$env:PROGRAMDATA\Microsoft\Windows\WER";         Name="Windows 错误报告"}
)

function Get-FolderSizeMB {
    param([string]$p)
    if (-not (Test-Path $p)) { return 0 }
    try {
        $sz = (Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue |
               Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($null -eq $sz) { return 0 }
        return [math]::Round($sz / 1MB, 2)
    } catch { return 0 }
}

function Remove-FolderContent {
    param([string]$p)
    $cnt = 0
    if (-not (Test-Path $p)) { return $cnt }
    Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue; $cnt++ } catch {}
    }
    return $cnt
}

try {
    if ($Action -eq "scan") {
        $list = @()
        $i = 0
        foreach ($d in $cleanDefs) {
            $i++
            $list += [PSCustomObject]@{
                index = $i
                key   = $d.Key
                name  = $d.Name
                path  = $d.Path
                sizeMB= (Get-FolderSizeMB $d.Path)
            }
        }
        $recycle = 0
        try {
            $shell = New-Object -ComObject Shell.Application
            $rb = $shell.NameSpace(10)
            $recycle = [math]::Round((Get-FolderSizeMB $rb.Self.Path) , 2)
        } catch {}
        Out-Json ([PSCustomObject]@{
            ok = $true
            items = $list
            recycleMB = $recycle
        })
    }
    elseif ($Action -eq "clean") {
        $targets = @()
        if ($Items -eq "all") {
            $targets = $cleanDefs
        } else {
            $idxs = $Items -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^\d+$" }
            $i = 0
            foreach ($d in $cleanDefs) {
                $i++
                if ($idxs -contains [string]$i) { $targets += $d }
            }
        }
        $totalFreed = 0
        $files = 0
        $details = @()
        foreach ($d in $targets) {
            $before = (Get-FolderSizeMB $d.Path) * 1MB
            $files += (Remove-FolderContent $d.Path)
            $after  = (Get-FolderSizeMB $d.Path) * 1MB
            $freed  = [math]::Max(0, $before - $after)
            $totalFreed += $freed
            $details += [PSCustomObject]@{ name = $d.Name; freedMB = [math]::Round($freed/1MB, 2) }
        }
        Out-Json ([PSCustomObject]@{
            ok = $true
            freedMB = [math]::Round($totalFreed/1MB, 2)
            filesDeleted = $files
            details = $details
        })
    }
} catch {
    Out-Json ([PSCustomObject]@{ ok = $false; error = $_.Exception.Message })
}

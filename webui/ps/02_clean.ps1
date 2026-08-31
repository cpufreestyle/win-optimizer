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


# 统一 stdout 为 UTF-8（让 Python subprocess.run 按 utf-8 解码时不乱码；与 OptimizeGUI 同款）
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
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

# 复用共享核心库（Get-FolderSize 返回字节；Remove-FolderContent 返回删除条目数）
$libPath = Join-Path $PSScriptRoot "..\..\lib\Optimize.Core.ps1"
if (Test-Path $libPath) { . $libPath }

# MB 版本，基于共享库的 Get-FolderSize 换算
function Get-FolderSizeMB {
    param([string]$p)
    return [math]::Round((Get-FolderSize $p) / 1MB, 2)
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
            $rbPath = $rb.Self.Path
            if ([string]::IsNullOrWhiteSpace($rbPath)) { $recycle = 0 } else { $recycle = [math]::Round((Get-FolderSizeMB $rbPath) , 2) }
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

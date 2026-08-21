<#
.SYNOPSIS
    WebUI 备份恢复 — 创建/列出/恢复，返回 JSON
.DESCRIPTION
    -Action create : 创建当前系统备份（服务/启动项/电源/视觉）
    -Action list   : 列出 backups 目录下的备份文件
    -Action restore: 从最近备份（或指定文件名）恢复服务与启动项
#>
param(
    [ValidateSet("create", "list", "restore")]$Action = "list",
    [string]$File = ""   # restore 时指定文件名；为空则取最近
)

function Out-Json {
    param($obj)
    $obj | ConvertTo-Json -Depth 4 -Compress
}

$ErrorActionPreference = "Stop"
$backupDir = Join-Path $PSScriptRoot "..\..\backups"
$backupDir = [System.IO.Path]::GetFullPath($backupDir)

function Type-Of($name) {
    if ($name -like "services_*") { return "服务备份" }
    if ($name -like "startup_*")  { return "启动项备份" }
    if ($name -like "power_*")    { return "电源计划备份" }
    if ($name -like "visual_*")   { return "视觉效果备份" }
    return "其他"
}

try {
    if ($Action -eq "create") {
        if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
        $ts = Get-Date -Format "yyyyMMdd_HHmmss"

        try { Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue | Export-Csv (Join-Path $backupDir "startup_$ts.csv") -NoTypeInformation -Encoding UTF8 } catch {}
        try { Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Select-Object Name, DisplayName, StartMode, State | Export-Csv (Join-Path $backupDir "services_$ts.csv") -NoTypeInformation -Encoding UTF8 } catch {}
        try { powercfg /list | Out-File (Join-Path $backupDir "power_$ts.txt") -Encoding UTF8 } catch {}
        try { Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -ErrorAction SilentlyContinue | Out-File (Join-Path $backupDir "visual_$ts.txt") -Encoding UTF8 } catch {}

        Out-Json ([PSCustomObject]@{ ok = $true; created = $ts })
    }
    elseif ($Action -eq "list") {
        $files = @()
        if (Test-Path $backupDir) {
            $items = Get-ChildItem $backupDir -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 50
            foreach ($b in $items) {
                $sz = if ($b.Length -gt 1KB) { "$([math]::Round($b.Length/1KB,1)) KB" } else { "$($b.Length) B" }
                $files += [PSCustomObject]@{
                    name = $b.Name
                    date = $b.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                    type = Type-Of $b.Name
                    size = $sz
                }
            }
        }
        Out-Json ([PSCustomObject]@{ ok = $true; files = $files })
    }
    elseif ($Action -eq "restore") {
        if (-not (Test-Path $backupDir)) { Out-Json ([PSCustomObject]@{ ok=$false; error="未找到备份目录" }); exit }
        $target = $null
        if ($File) {
            $target = Get-ChildItem $backupDir -Filter $File -ErrorAction SilentlyContinue | Select-Object -First 1
        } else {
            # 最近的服务备份作为主恢复源
            $target = Get-ChildItem $backupDir -Filter "services_*.csv" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        }
        if (-not $target) { Out-Json ([PSCustomObject]@{ ok=$false; error="未找到可恢复备份" }); exit }

        $restored = 0; $log = @()
        if ($target.Name -like "services_*.csv") {
            $rows = Import-Csv $target.FullName -ErrorAction Stop
            foreach ($r in $rows) {
                try {
                    if ($r.StartMode -eq "Auto") { Set-Service -Name $r.Name -StartupType Automatic -ErrorAction SilentlyContinue }
                    elseif ($r.StartMode -eq "Manual") { Set-Service -Name $r.Name -StartupType Manual -ErrorAction SilentlyContinue }
                    elseif ($r.StartMode -eq "Disabled") { Set-Service -Name $r.Name -StartupType Disabled -ErrorAction SilentlyContinue }
                    $restored++
                } catch {}
            }
            $log += "服务已恢复 $restored 项"
        }

        # 启动项恢复（找同批次 startup_ 文件）
        $stFile = Get-ChildItem $backupDir -Filter "startup_*.csv" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($stFile) {
            try {
                $items = Import-Csv $stFile.FullName -ErrorAction SilentlyContinue
                foreach ($it in $items) {
                    try {
                        $regPath = Split-Path $it.Location -Parent
                        $regName = Split-Path $it.Location -Leaf
                        if (Test-Path $regPath) {
                            New-ItemProperty -Path $regPath -Name $regName -Value $it.Command -Force -ErrorAction SilentlyContinue | Out-Null
                        }
                    } catch {}
                }
                $log += "启动项已恢复"
            } catch {}
        }

        Out-Json ([PSCustomObject]@{ ok = $true; restored = $restored; file = $target.Name; log = $log })
    }
} catch {
    Out-Json ([PSCustomObject]@{ ok = $false; error = $_.Exception.Message })
}

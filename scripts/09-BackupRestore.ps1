<#
.SYNOPSIS
    备份与恢复模块 — 备份当前系统设置 / 从备份恢复
.DESCRIPTION
    - 查看现有备份文件
    - 从备份恢复服务设置
    - 从备份恢复启动项
    - 从备份恢复视觉效果
    - 从备份恢复电源计划
#>

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "         备份与恢复" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

$backupDir = Join-Path $PSScriptRoot "..\backups"
$backupDir = [System.IO.Path]::GetFullPath($backupDir)

# --- 列出现有备份 ---
Write-Host "`n[现有备份文件]" -ForegroundColor Yellow

if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
}

$backups = Get-ChildItem -Path $backupDir -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending

if ($backups.Count -eq 0) {
    Write-Host "  暂无备份文件" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  建议在优化前先执行备份，以便随时恢复。" -ForegroundColor Yellow
    Write-Host "============================================" -ForegroundColor Cyan
    return
}

# 分类显示备份
$serviceBackups  = $backups | Where-Object { $_.Name -like "services_backup_*" }
$startupBackups  = $backups | Where-Object { $_.Name -like "startup_backup_*" }
$visualBackups   = $backups | Where-Object { $_.Name -like "visual_backup_*" }
$powerBackups    = $backups | Where-Object { $_.Name -like "power_backup_*" }

$categories = @(
    @{Name="服务备份";    Backups=$serviceBackups;  Type="services"}
    @{Name="启动项备份";  Backups=$startupBackups;  Type="startup"}
    @{Name="视觉效果备份"; Backups=$visualBackups;   Type="visual"}
    @{Name="电源计划备份"; Backups=$powerBackups;    Type="power"}
)

$menuIndex = 1
$menuItems = @()

foreach ($cat in $categories) {
    if ($cat.Backups.Count -gt 0) {
        Write-Host "`n  $($cat.Name):" -ForegroundColor Cyan
        foreach ($b in $cat.Backups) {
            $sizeKB = [math]::Round($b.Length / 1KB, 1)
            Write-Host "    [$menuIndex] $($b.Name)  (${sizeKB}KB, $($b.LastWriteTime.ToString('yyyy-MM-dd HH:mm')))"
            $menuItems += @{Index=$menuIndex; File=$b.FullName; Type=$cat.Type}
            $menuIndex++
        }
    }
}

# 查找启动文件夹备份
$startupItemDir = Join-Path $backupDir "startup_items"
if (Test-Path $startupItemDir) {
    $startupFiles = Get-ChildItem -Path $startupItemDir -File -ErrorAction SilentlyContinue
    if ($startupFiles.Count -gt 0) {
        Write-Host "`n  启动文件夹备份项:" -ForegroundColor Cyan
        Write-Host "    [R] 恢复所有启动文件夹项 (共 $($startupFiles.Count) 个文件)"
    }
}

Write-Host ""
Write-Host "  [A] 恢复所有类型（从最近的备份）"
Write-Host "  [N] 取消"
$input = Read-Host "选择要恢复的备份"

if ($input -eq "N" -or $input -eq "n") {
    Write-Host "  操作已取消。" -ForegroundColor Gray
    Write-Host "============================================" -ForegroundColor Cyan
    return
}

# 执行恢复
function Restore-Services {
    param([string]$BackupFile)
    Write-Host "  正在恢复服务设置..." -ForegroundColor Yellow
    $data = Import-Csv -Path $BackupFile -Encoding UTF8
    foreach ($row in $data) {
        try {
            $service = Get-Service -Name $row.Name -ErrorAction SilentlyContinue
            if ($service) {
                $startType = switch ($row.StartType) {
                    "Auto"     { "Automatic" }
                    "Manual"   { "Manual" }
                    "Disabled" { "Disabled" }
                    default    { $row.StartType }
                }
                Set-Service -Name $row.Name -StartupType $startType -ErrorAction SilentlyContinue
                if ($row.Status -eq "Running") {
                    Start-Service -Name $row.Name -ErrorAction SilentlyContinue
                }
                Write-Host "    [恢复] $($row.Name) -> $startType" -ForegroundColor Green
            }
        } catch {
            Write-Host "    [失败] $($row.Name)" -ForegroundColor Red
        }
    }
}

function Restore-Startup {
    param([string]$BackupFile)
    Write-Host "  正在恢复启动项..." -ForegroundColor Yellow
    $data = Import-Csv -Path $BackupFile -Encoding UTF8
    foreach ($row in $data) {
        try {
            if ($row.Path -and (Test-Path $row.Path)) {
                if (-not (Get-ItemProperty -Path $row.Path -Name $row.Name -ErrorAction SilentlyContinue)) {
                    New-ItemProperty -Path $row.Path -Name $row.Name -Value $row.Value -PropertyType String -Force | Out-Null
                    Write-Host "    [恢复] $($row.Name)" -ForegroundColor Green
                }
            }
        } catch {
            Write-Host "    [失败] $($row.Name)" -ForegroundColor Red
        }
    }
}

function Restore-Visual {
    param([string]$BackupFile)
    Write-Host "  正在恢复视觉效果设置..." -ForegroundColor Yellow
    $data = Get-Content -Path $BackupFile -Raw | ConvertFrom-Json

    if ($data.VisualEffects) {
        $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        if (Test-Path $key) {
            $data.VisualEffects.PSObject.Properties | Where-Object { $_.Name -ne "PSPath" -and $_.Name -ne "PSParentPath" -and $_.Name -ne "PSChildName" -and $_.Name -ne "PSDrive" -and $_.Name -ne "PSProvider" } | ForEach-Object {
                Set-ItemProperty -Path $key -Name $_.Name -Value $_.Value -ErrorAction SilentlyContinue
            }
        }
    }

    if ($data.Desktop) {
        $key = "HKCU:\Control Panel\Desktop"
        $data.Desktop.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
            Set-ItemProperty -Path $key -Name $_.Name -Value $_.Value -ErrorAction SilentlyContinue
        }
    }

    Write-Host "    [完成] 视觉效果已恢复" -ForegroundColor Green
}

function Restore-Power {
    param([string]$BackupFile)
    Write-Host "  正在恢复电源计划..." -ForegroundColor Yellow
    Write-Host "    (电源计划恢复需要手动操作)" -ForegroundColor Gray
    Write-Host "    请打开 控制面板 -> 电源选项 手动选择原来的计划" -ForegroundColor Gray
    Write-Host "    或运行: powercfg /restoredefaultschemes" -ForegroundColor Gray

    $confirm = Read-Host "    是否恢复默认电源方案? (Y/N)"
    if ($confirm -eq "Y" -or $confirm -eq "y") {
        powercfg /restoredefaultschemes 2>&1 | Out-Null
        Write-Host "    [完成] 默认电源方案已恢复" -ForegroundColor Green
    }
}

if ($input -eq "A" -or $input -eq "a") {
    # 恢复所有最近的备份
    foreach ($cat in $categories) {
        $latest = $cat.Backups | Select-Object -First 1
        if ($latest) {
            Write-Host ""
            switch ($cat.Type) {
                "services" { Restore-Services -BackupFile $latest.FullName }
                "startup"  { Restore-Startup  -BackupFile $latest.FullName }
                "visual"   { Restore-Visual   -BackupFile $latest.FullName }
                "power"    { Restore-Power    -BackupFile $latest.FullName }
            }
        }
    }
}
elseif ($input -eq "R" -or $input -eq "r") {
    # 恢复启动文件夹项
    $startupItemDir = Join-Path $backupDir "startup_items"
    $startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    if (Test-Path $startupItemDir) {
        $files = Get-ChildItem -Path $startupItemDir -File
        foreach ($f in $files) {
            $dest = Join-Path $startupFolder $f.Name
            Move-Item -Path $f.FullName -Destination $dest -Force -ErrorAction SilentlyContinue
            Write-Host "  [恢复] $($f.Name) -> 启动文件夹" -ForegroundColor Green
        }
    }
}
else {
    # 恢复指定备份
    $selected = $menuItems | Where-Object { $_.Index -eq [int]$input }
    if ($selected) {
        switch ($selected.Type) {
            "services" { Restore-Services -BackupFile $selected.File }
            "startup"  { Restore-Startup  -BackupFile $selected.File }
            "visual"   { Restore-Visual   -BackupFile $selected.File }
            "power"    { Restore-Power    -BackupFile $selected.File }
        }
    } else {
        Write-Host "  无效选择。" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  恢复操作完成！" -ForegroundColor Green
Write-Host "  建议重启电脑使所有更改生效" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan

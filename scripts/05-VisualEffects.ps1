<#
.SYNOPSIS
    视觉效果优化模块 — 降低视觉特效，提升系统响应速度
.DESCRIPTION
    针对 7代及更老 CPU/集显的电脑，关闭不必要的视觉效果：
    - 设置为"最佳性能"模式
    - 保留基本字体平滑（避免文字难看）
    - 禁用透明效果
    - 禁用动画控件
    - 调整菜单显示延迟
    所有更改会备份，可随时恢复。
#>

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "         视觉效果优化" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# --- 备份当前设置 ---
$backupFile = Join-Path $PSScriptRoot "..\backups\visual_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
$backupFile = [System.IO.Path]::GetFullPath($backupFile)

Write-Host "`n[1/3] 备份当前视觉效果设置..." -ForegroundColor Yellow

$backup = @{}

# 备份 VisualEffects 注册表设置
$visualKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
if (Test-Path $visualKey) {
    $backup["VisualEffects"] = Get-ItemProperty -Path $visualKey -ErrorAction SilentlyContinue
}

# 备份 DWM (桌面窗口管理器) 设置
$dwmKey = "HKCU:\Software\Microsoft\Windows\DWM"
if (Test-Path $dwmKey) {
    $backup["DWM"] = Get-ItemProperty -Path $dwmKey -ErrorAction SilentlyContinue
}

# 备份性能设置
$perfKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
if (Test-Path $perfKey) {
    $backup["Advanced"] = Get-ItemProperty -Path $perfKey -ErrorAction SilentlyContinue
}

# 备份菜单延迟
$desktopKey = "HKCU:\Control Panel\Desktop"
if (Test-Path $desktopKey) {
    $backup["Desktop"] = Get-ItemProperty -Path $desktopKey -ErrorAction SilentlyContinue
}

$backup | ConvertTo-Json -Depth 3 | Out-File -FilePath $backupFile -Encoding UTF8
Write-Host "  备份已保存: $backupFile" -ForegroundColor Green

# --- 显示选项 ---
Write-Host "`n[2/3] 选择优化级别:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  [1] 最佳性能 (推荐老电脑) — 关闭所有特效，仅保留字体平滑"
Write-Host "  [2] 平衡模式 — 关闭大部分特效，保留基本动画"
Write-Host "  [3] 自定义 — 逐项选择"
Write-Host "  [N] 取消"
$choice = Read-Host "选择 (1/2/3/N)"

if ($choice -eq "N" -or $choice -eq "n") {
    Write-Host "  操作已取消。" -ForegroundColor Gray
    Write-Host "============================================" -ForegroundColor Cyan
    return
}

Write-Host "`n[3/3] 正在应用视觉效果设置..." -ForegroundColor Yellow

switch ($choice) {
    "1" {
        # --- 最佳性能模式 ---
        # VisualEffects 设置: 0 = 自定义, 我们手动设置各项
        $visualKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        if (-not (Test-Path $visualKey)) { New-Item -Path $visualKey -Force | Out-Null }
        Set-ItemProperty -Path $visualKey -Name "VisualFXSetting" -Value 3 -Type DWord

        # 性能选项: 禁用所有动画，仅保留字体平滑
        $perfKey = "HKCU:\Control Panel\Desktop"
        $perfSettings = @{
            "DragFullWindows"        = "0"    # 拖拽时不显示完整窗口
            "FontSmoothing"          = "2"    # 保留字体平滑
            "FontSmoothingType"      = "2"    # ClearType
            "MenuShowDelay"          = "0"    # 菜单显示延迟 0ms
            "UserPreferencesMask"    = [byte[]](0x90,0x12,0x01,0x80,0x10,0x00,0x00,0x00) # 最佳性能
        }
        foreach ($kvp in $perfSettings.GetEnumerator()) {
            Set-ItemProperty -Path $perfKey -Name $kvp.Key -Value $kvp.Value -ErrorAction SilentlyContinue
        }

        # 禁用动画控件
        $advancedKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        $advancedSettings = @{
            "TaskbarAnimations"     = 0  # 禁用任务栏动画
            "ListviewAlphaSelect"   = 0  # 禁用列表选择透明效果
        }
        foreach ($kvp in $advancedSettings.GetEnumerator()) {
            Set-ItemProperty -Path $advancedKey -Name $kvp.Key -Value $kvp.Value -Type DWord -ErrorAction SilentlyContinue
        }

        # 禁用窗口最小化/最大化动画
        $minAnimKey = "HKCU:\Control Panel\Desktop\WindowMetrics"
        if (-not (Test-Path $minAnimKey)) { New-Item -Path $minAnimKey -Force | Out-Null }
        Set-ItemProperty -Path $minAnimKey -Name "MinAnimate" -Value "0" -Type String -ErrorAction SilentlyContinue

        # DWM: 禁用透明
        $dwmKey = "HKCU:\Software\Microsoft\Windows\DWM"
        Set-ItemProperty -Path $dwmKey -Name "EnableAeroPeek" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $dwmKey -Name "AlwaysHibernateThumbnails" -Value 0 -Type DWord -ErrorAction SilentlyContinue

        # 系统级性能设置
        $sysPerfKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        if (-not (Test-Path $sysPerfKey)) { New-Item -Path $sysPerfKey -Force | Out-Null }
        Set-ItemProperty -Path $sysPerfKey -Name "VisualFXSetting" -Value 3 -Type DWord -ErrorAction SilentlyContinue

        Write-Host "  [完成] 已设置最佳性能模式" -ForegroundColor Green
        Write-Host "    - 禁用拖拽完整窗口显示" -ForegroundColor Gray
        Write-Host "    - 禁用任务栏动画" -ForegroundColor Gray
        Write-Host "    - 禁用列表透明选择" -ForegroundColor Gray
        Write-Host "    - 禁用窗口动画" -ForegroundColor Gray
        Write-Host "    - 禁用 Aero Peek" -ForegroundColor Gray
        Write-Host "    - 菜单延迟设为 0ms" -ForegroundColor Gray
        Write-Host "    - 保留字体平滑 (ClearType)" -ForegroundColor Green
    }

    "2" {
        # --- 平衡模式 ---
        $visualKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        if (-not (Test-Path $visualKey)) { New-Item -Path $visualKey -Force | Out-Null }
        Set-ItemProperty -Path $visualKey -Name "VisualFXSetting" -Value 3 -Type DWord

        $perfKey = "HKCU:\Control Panel\Desktop"
        Set-ItemProperty -Path $perfKey -Name "DragFullWindows" -Value "1" -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $perfKey -Name "FontSmoothing" -Value "2" -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $perfKey -Name "MenuShowDelay" -Value "100" -ErrorAction SilentlyContinue

        $advancedKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        Set-ItemProperty -Path $advancedKey -Name "TaskbarAnimations" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $advancedKey -Name "ListviewAlphaSelect" -Value 0 -Type DWord -ErrorAction SilentlyContinue

        $dwmKey = "HKCU:\Software\Microsoft\Windows\DWM"
        Set-ItemProperty -Path $dwmKey -Name "EnableAeroPeek" -Value 0 -Type DWord -ErrorAction SilentlyContinue

        Write-Host "  [完成] 已设置平衡模式" -ForegroundColor Green
        Write-Host "    - 保留拖拽完整窗口" -ForegroundColor Gray
        Write-Host "    - 禁用任务栏动画" -ForegroundColor Gray
        Write-Host "    - 禁用透明选择" -ForegroundColor Gray
        Write-Host "    - 禁用 Aero Peek" -ForegroundColor Gray
        Write-Host "    - 菜单延迟设为 100ms" -ForegroundColor Gray
        Write-Host "    - 保留字体平滑" -ForegroundColor Green
    }

    "3" {
        # --- 自定义模式 ---
        $options = @(
            @{Name="禁用任务栏动画";          RegKey="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; RegValue="TaskbarAnimations"; RegData=0}
            @{Name="禁用列表透明选择";        RegKey="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; RegValue="ListviewAlphaSelect"; RegData=0}
            @{Name="禁用拖拽完整窗口";        RegKey="HKCU:\Control Panel\Desktop"; RegValue="DragFullWindows"; RegData="0"}
            @{Name="禁用窗口最小化动画";      RegKey="HKCU:\Control Panel\Desktop\WindowMetrics"; RegValue="MinAnimate"; RegData="0"}
            @{Name="禁用 Aero Peek";          RegKey="HKCU:\Software\Microsoft\Windows\DWM"; RegValue="EnableAeroPeek"; RegData=0}
            @{Name="菜单延迟设为0";           RegKey="HKCU:\Control Panel\Desktop"; RegValue="MenuShowDelay"; RegData="0"}
        )

        Write-Host ""
        for ($i = 0; $i -lt $options.Count; $i++) {
            Write-Host "  [$($i+1)] $($options[$i].Name)"
        }
        Write-Host "  输入序号(逗号分隔)选择要应用的项, 或 A 全部应用"
        $sel = Read-Host "选择"

        $selected = @()
        if ($sel -eq "A" -or $sel -eq "a") {
            $selected = $options
        } else {
            $indices = $sel -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^\d+$" }
            foreach ($idx in $indices) {
                $i = [int]$idx - 1
                if ($i -ge 0 -and $i -lt $options.Count) { $selected += $options[$i] }
            }
        }

        $visualKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        if (-not (Test-Path $visualKey)) { New-Item -Path $visualKey -Force | Out-Null }
        Set-ItemProperty -Path $visualKey -Name "VisualFXSetting" -Value 3 -Type DWord

        foreach ($opt in $selected) {
            if (-not (Test-Path $opt.RegKey)) { New-Item -Path $opt.RegKey -Force | Out-Null }
            if ($opt.RegValue -eq "DragFullWindows" -or $opt.RegValue -eq "MinAnimate" -or $opt.RegValue -eq "MenuShowDelay") {
                Set-ItemProperty -Path $opt.RegKey -Name $opt.RegValue -Value $opt.RegData -Type String -ErrorAction SilentlyContinue
            } else {
                Set-ItemProperty -Path $opt.RegKey -Name $opt.RegValue -Value $opt.RegData -Type DWord -ErrorAction SilentlyContinue
            }
            Write-Host "  [完成] $($opt.Name)" -ForegroundColor Green
        }
    }

    default {
        Write-Host "  无效选择，操作取消。" -ForegroundColor Red
        Write-Host "============================================" -ForegroundColor Cyan
        return
    }
}

# 刷新资源管理器以应用更改
Write-Host "`n正在刷新系统设置..." -ForegroundColor Yellow
try {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Start-Process explorer
    Write-Host "  资源管理器已重启" -ForegroundColor Green
} catch {
    Write-Host "  请手动重启资源管理器或重启电脑" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  视觉效果优化完成！" -ForegroundColor Green
Write-Host "  备份文件: $backupFile" -ForegroundColor Gray
Write-Host "  如需恢复，请使用 [B] 备份恢复功能" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan

<#
.SYNOPSIS
    Windows 可选功能管理模块
.DESCRIPTION
    微软默认未主动开启、需要手动到“启用或关闭 Windows 功能”里勾选的可选功能
    （如 .NET Framework 3.5、Hyper-V、WSL、SMB1、Telnet、Internet Information Services 等）。
    本模块会：
      - 列出当前“已禁用（未启用）”的所有可选功能
      - 让你勾选后一键启用（Enable-WindowsOptionalFeature）
      - 支持查看“已启用”列表、以及“全部可选的恢复/关闭”提示
    启用功能可能需要 Windows 安装介质/在线更新源（DISM 会自动尝试从 Windows Update 获取）。
.NOTES
    需要以管理员身份运行（由 Optimize.ps1 入口统一校验）。
#>

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   Windows 可选功能（手动开启的版本功能）" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# --- 取全部可选功能（含状态） ---
function Get-AllFeatures {
    try {
        return Get-WindowsOptionalFeature -Online -ErrorAction Stop
    } catch {
        Write-Host "  无法读取可选功能列表：$($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

$features = Get-AllFeatures
if ($null -eq $features) { return }

# 分类
$disabled = $features | Where-Object { $_.State -eq "Disabled" }
$enabled  = $features | Where-Object { $_.State -eq "Enabled" }

# --- 菜单 ---
Write-Host ""
Write-Host "  [1] 列出并启用“未开启”的可选功能（推荐）"
Write-Host "  [2] 查看当前“已启用”的可选功能"
Write-Host "  [Q] 返回"
$action = Read-Host "请选择操作"

switch ($action) {
    "1" {
        if ($disabled.Count -eq 0) {
            Write-Host "`n  没有发现未启用的可选功能，系统已经全部开启。" -ForegroundColor Gray
            return
        }
        Write-Host ""
        Write-Host "  以下功能是微软默认未开启、需要手动启用的：" -ForegroundColor Yellow
        Write-Host "  $('-' * 70)" -ForegroundColor DarkGray
        $i = 1
        $map = @{}
        foreach ($f in $disabled) {
            $desc = if ($f.Description) { $f.Description } else { $f.DisplayName }
            Write-Host ("  [{0}]  {1}" -f $i, $f.FeatureName)
            if ($desc) { Write-Host ("        $desc") -ForegroundColor DarkGray }
            $map[$i] = $f.FeatureName
            $i++
        }
        Write-Host ""
        Write-Host "  输入要启用的序号（多个用逗号，如 1,3；全部输入 A；取消输入 Q）" -ForegroundColor Yellow
        $sel = Read-Host "选择"
        if ($sel -eq "Q" -or $sel -eq "q") { Write-Host "  已取消。" -ForegroundColor Gray; return }

        $targets = @()
        if ($sel -eq "A" -or $sel -eq "a") {
            $targets = $disabled | ForEach-Object { $_.FeatureName }
        } else {
            foreach ($s in ($sel -split "," | ForEach-Object { $_.Trim() })) {
                if ($s -match '^\d+$' -and $map[[int]$s]) { $targets += $map[[int]$s] }
            }
        }
        if ($targets.Count -eq 0) { Write-Host "  未选择任何功能。" -ForegroundColor Gray; return }

        Write-Host ""
        Write-Host "  将启用 $($targets.Count) 个功能，可能需要从 Windows Update 下载组件..." -ForegroundColor Yellow
        $ok = 0; $fail = 0
        foreach ($name in $targets) {
            Write-Host "  [启用中] $name" -ForegroundColor Cyan
            try {
                $r = Enable-WindowsOptionalFeature -Online -FeatureName $name -All -NoRestart -ErrorAction Stop
                if ($r.RestartNeeded) {
                    Write-Host "      -> 已完成（需要重启生效）" -ForegroundColor Green
                } else {
                    Write-Host "      -> 已完成" -ForegroundColor Green
                }
                $ok++
            } catch {
                Write-Host "      -> 失败：$($_.Exception.Message)" -ForegroundColor Red
                Write-Host "         可尝试以管理员运行：DISM /Online /Enable-Feature /FeatureName:$name /All" -ForegroundColor Gray
                $fail++
            }
        }
        Write-Host ""
        Write-Host "  启用完成：成功 $ok，失败 $fail。" -ForegroundColor Green
        if ($ok -gt 0) {
            Write-Host "  若提示需要重启，请稍后重启电脑使功能生效。" -ForegroundColor Yellow
        }
    }
    "2" {
        if ($enabled.Count -eq 0) {
            Write-Host "`n  当前没有任何已启用的可选功能。" -ForegroundColor Gray
            return
        }
        Write-Host ""
        Write-Host "  当前已启用的可选功能（共 $($enabled.Count) 个）：" -ForegroundColor Yellow
        Write-Host "  $('-' * 70)" -ForegroundColor DarkGray
        foreach ($f in $enabled) {
            Write-Host ("  - {0}" -f $f.FeatureName)
        }
    }
    default { Write-Host "  操作已取消。" -ForegroundColor Gray }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  完成。启用后可到“控制面板-程序-启用或关闭 Windows 功能”查看。" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan

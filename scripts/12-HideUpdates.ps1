<#
.SYNOPSIS
    隐藏/恢复指定 Windows 更新模块
.DESCRIPTION
    基于 Windows Update API (WUAPI) 的"隐藏更新"功能（等同微软官方 wushowhide.diagcab）：
      - 列出当前"可选/待安装"的更新，供你选择要隐藏的项（如功能升级、累积更新等）
      - 把选中的更新标记为隐藏，不再出现在更新列表、不再被自动安装
      - 支持"恢复显示"此前隐藏的更新
    隐藏是系统级、持久的，不会因为重启或累积更新而丢失。
    注意：隐藏只影响"被隐藏的那一条"，其他安全更新照常推送。
.NOTES
    需要以管理员身份运行（由 Optimize.ps1 入口统一校验）。
#>

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   隐藏/恢复指定 Windows 更新" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

function Get-WUUpdates {
    param([bool]$IncludeHidden = $false)
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    # 搜索所有未安装软件更新；IncludeHidden 控制是否含已隐藏
    $criteria = "IsInstalled=0 AND Type='Software'"
    if ($IncludeHidden) { $criteria = "Type='Software'" }
    $result = $searcher.Search($criteria)
    return $result.Updates
}

# --- 菜单选择 ---
Write-Host ""
Write-Host "  [1] 隐藏指定更新（如功能升级、累积更新）"
Write-Host "  [2] 恢复显示已隐藏的更新"
Write-Host "  [Q] 取消"
$action = Read-Host "请选择操作"

switch ($action) {
    "1" {
        Write-Host "`n正在检索可隐藏的更新..." -ForegroundColor Yellow
        try {
            $updates = Get-WUUpdates -IncludeHidden $false
        } catch {
            Write-Host "  检索失败：$($_.Exception.Message)" -ForegroundColor Red
            Write-Host "  可手动运行微软 'wushowhide.diagcab' 工具。" -ForegroundColor Gray
            return
        }
        if ($updates.Count -eq 0) {
            Write-Host "  当前没有待安装的更新可隐藏。" -ForegroundColor Gray
            return
        }
        Write-Host ""
        Write-Host "  序号  标题" -ForegroundColor DarkGray
        Write-Host "  $('-' * 70)" -ForegroundColor DarkGray
        $i = 1
        $map = @{}
        foreach ($u in $updates) {
            Write-Host "  [$i]  $($u.Title)"
            $map[$i] = $u
            $i++
        }
        Write-Host ""
        $sel = Read-Host "输入要隐藏的序号（多个用逗号，如 1,3；全部输入 A）"
        $targets = @()
        if ($sel -eq "A" -or $sel -eq "a") {
            $targets = $updates
        } else {
            foreach ($s in ($sel -split "," | ForEach-Object { $_.Trim() })) {
                if ($s -match '^\d+$' -and $map[[int]$s]) { $targets += $map[[int]$s] }
            }
        }
        if ($targets.Count -eq 0) { Write-Host "  未选择任何项。" -ForegroundColor Gray; return }
        $cnt = 0
        foreach ($t in $targets) {
            try { $t.IsHidden = $true; Write-Host "  [已隐藏] $($t.Title)" -ForegroundColor Green; $cnt++ }
            catch { Write-Host "  [失败] $($t.Title)" -ForegroundColor Red }
        }
        Write-Host "`n  共隐藏 $cnt 个更新。" -ForegroundColor Green
    }
    "2" {
        Write-Host "`n正在检索已隐藏的更新..." -ForegroundColor Yellow
        try {
            $hidden = Get-WUUpdates -IncludeHidden $true | Where-Object { $_.IsHidden }
        } catch {
            Write-Host "  检索失败：$($_.Exception.Message)" -ForegroundColor Red
            return
        }
        if ($hidden.Count -eq 0) {
            Write-Host "  没有已隐藏的更新。" -ForegroundColor Gray
            return
        }
        Write-Host ""
        Write-Host "  序号  标题" -ForegroundColor DarkGray
        Write-Host "  $('-' * 70)" -ForegroundColor DarkGray
        $i = 1; $map = @()
        foreach ($u in $hidden) {
            Write-Host "  [$i]  $($u.Title)"
            $map += $u; $i++
        }
        Write-Host ""
        $sel = Read-Host "输入要恢复显示的序号（多个用逗号；全部输入 A）"
        $targets = @()
        if ($sel -eq "A" -or $sel -eq "a") { $targets = $hidden }
        else {
            foreach ($s in ($sel -split "," | ForEach-Object { $_.Trim() })) {
                if ($s -match '^\d+$') { $idx = [int]$s - 1; if ($map[$idx]) { $targets += $map[$idx] } }
            }
        }
        $cnt = 0
        foreach ($t in $targets) {
            try { $t.IsHidden = $false; Write-Host "  [已恢复] $($t.Title)" -ForegroundColor Green; $cnt++ }
            catch { Write-Host "  [失败] $($t.Title)" -ForegroundColor Red }
        }
        Write-Host "`n  共恢复 $cnt 个更新。" -ForegroundColor Green
    }
    default { Write-Host "  操作已取消。" -ForegroundColor Gray }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  完成。隐藏的更新不再出现在更新列表。" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan

<#
.SYNOPSIS
    C 盘程序迁移到 D 盘（robocopy + NTFS 目录联接）
.DESCRIPTION
    扫描 C:\Program Files* 下可迁移程序，复制到 D 盘并建立目录联接，
    原路径继续有效、注册表/卸载信息无需改动，C 盘空间立即释放。
    高风险目录与正在运行的程序会被拦截。
#>

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  C 盘程序迁移到 D 盘" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

$coreLib = Join-Path $PSScriptRoot "..\lib\Optimize.Core.ps1"
if (Test-Path $coreLib) { . $coreLib }

# 检查管理员权限（创建目录联接需要）
if (-not (Test-IsAdmin)) {
    Write-Host "  [提示] 检测到非管理员运行，创建目录联接可能失败，建议以管理员身份运行。" -ForegroundColor Yellow
    Write-Host ""
}

$drive = "D:"
if (-not (Test-Path $drive)) {
    Write-Host "  [错误] 当前机器未检测到 D 盘，无法迁移。" -ForegroundColor Red
    return
}
Write-Host "  目标盘符：$drive（副本将放在 $drive\Program Files Migrated\）" -ForegroundColor Yellow
Write-Host ""

Write-Host "  正在扫描 C:\Program Files* 可迁移程序..." -ForegroundColor Yellow
$cands = Get-MigratablePrograms
if ($cands.Count -eq 0) {
    Write-Host "  未发现可迁移的程序目录。" -ForegroundColor Gray
    return
}

Write-Host ""
Write-Host "  可迁移程序（按占用空间降序）：" -ForegroundColor Cyan
for ($i = 0; $i -lt $cands.Count; $i++) {
    $c = $cands[$i]
    Write-Host ("  [{0}] {1}  ({2} MB, {3})" -f ($i + 1), $c.Name, $c.SizeMB, $c.Path) -ForegroundColor Gray
}
Write-Host ""

$sel = Read-Host "  输入要迁移的编号（多个用逗号分隔，如 1,3；输入 Q 取消）"
if ($sel -match '^[Qq]$') { Write-Host "  已取消。" -ForegroundColor Gray; return }

$indexes = @()
foreach ($part in ($sel -split ',')) {
    $part = $part.Trim()
    if ($part -match '^\d+$') {
        $idx = [int]$part
        if ($idx -ge 1 -and $idx -le $cands.Count) { $indexes += $idx - 1 }
    }
}
if ($indexes.Count -eq 0) {
    Write-Host "  未输入有效编号，已取消。" -ForegroundColor Gray
    return
}

Write-Host ""
Write-Host "  将要迁移以下程序："
foreach ($i in $indexes) { Write-Host ("    {0}  ({1} MB) -> {2}" -f $cands[$i].Name, $cands[$i].SizeMB, $drive) -ForegroundColor Gray }
$confirm = Read-Host "  确认迁移？(Y=是 / N=否)"
if ($confirm -match '^[Yy]$') {
    $totalFreed = 0
    $moved = 0
    $skipped = 0
    foreach ($i in $indexes) {
        $c = $cands[$i]
        Write-Host ""
        Write-Host ("  [{0}] 正在迁移 {1} ..." -f ($moved + $skipped + 1), $c.Name) -ForegroundColor Yellow
        $r = Move-ProgramToDrive -SourcePath $c.Path -TargetDrive $drive -Confirm
        if ($r.ok -and $r.moved) {
            $totalFreed += $r.freedMB
            $moved++
            Write-Host ("    [完成] {0} -> {1}，释放约 {2} MB" -f $c.Path, $r.junction, $r.freedMB) -ForegroundColor Green
        } else {
            $skipped++
            Write-Host ("    [跳过] {0} : {1}" -f $c.Path, $r.reason) -ForegroundColor Yellow
        }
    }
    Write-Host ""
    Write-Host ("  迁移结束：成功 {0} 个，跳过 {1} 个，累计释放约 {2} MB" -f $moved, $skipped, [math]::Round($totalFreed, 2)) -ForegroundColor Cyan
    Write-Host "  提示：原路径保持不变，访问会自动重定向到 D 盘；如需还原，删除目录联接并将 D 盘副本拷回即可。"
} else {
    Write-Host "  用户取消。" -ForegroundColor Gray
}

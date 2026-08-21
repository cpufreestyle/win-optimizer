<#
.SYNOPSIS
    编译 GUI 脚本为 EXE 可执行文件
.DESCRIPTION
    使用 PS2EXE 模块将 OptimizeGUI.ps1 编译为 PC-Optimizer.exe
#>

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  编译 PC-Optimizer.exe" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# 检查 ps2exe 模块
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "[安装] 正在安装 ps2exe 模块..." -ForegroundColor Yellow
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction SilentlyContinue
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
    Install-Module -Name ps2exe -Force -Scope CurrentUser
}

Import-Module ps2exe

$inputFile  = Join-Path $PSScriptRoot "OptimizeGUI.ps1"
$outputFile = Join-Path $PSScriptRoot "PC-Optimizer.exe"
$libFile    = Join-Path $PSScriptRoot "lib\Optimize.Core.ps1"
$guiDir     = Join-Path $PSScriptRoot "gui"

# 关键：ps2exe 默认会按 ANSI 读取源文件，导致其中的中文在编译后变成乱码。
# 这里将 UTF-8(BOM) 源文件转为 Windows PowerShell 原生的
# UTF-16 LE (Unicode, 带 BOM) 临时副本，配合 -UNICODEEncoding，
# 保证编译出的 EXE 中所有中文字符完整无损。
# 编译时把所有模块（共享库 lib + 各页面 gui/pages + 更新检查 gui/UpdateCheck
# + 主窗体 OptimizeGUI）拼接成单一脚本，函数先定义后用，实现 CLI/Web/GUI 三套复用。
# 主窗体中的 dot-source 加载器段会被剥离（函数已内联，运行时无需外部文件）。
$tmpFile = Join-Path $env:TEMP ("PC-Optimizer_GUI_" + [guid]::NewGuid().ToString("N") + ".ps1")

$parts = @()
if (Test-Path $libFile) {
    $parts += [System.IO.File]::ReadAllText($libFile, [System.Text.Encoding]::UTF8)
}

$pageFiles = @(
    "pages/Dashboard.ps1", "pages/Clean.ps1", "pages/Services.ps1",
    "pages/Startup.ps1", "pages/Visual.ps1", "pages/Power.ps1",
    "pages/Disk.ps1", "pages/Network.ps1", "pages/Backup.ps1",
    "pages/Update.ps1", "pages/About.ps1", "UpdateCheck.ps1"
)
foreach ($pf in $pageFiles) {
    $p = Join-Path $guiDir $pf
    if (Test-Path $p) { $parts += [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) }
}

$srcText = [System.IO.File]::ReadAllText($inputFile, [System.Text.Encoding]::UTF8)
# 剥离主窗体中的 dot-source 加载器段（从 "#  加载页面函数" 到其所在 foreach 块结束）
$loaderStart = $srcText.IndexOf('#  加载页面函数')
if ($loaderStart -ge 0) {
    $loaderEnd = $srcText.IndexOf('if (Test-Path $pfPath) { . $pfPath }', $loaderStart)
    if ($loaderEnd -ge 0) {
        $nl = $srcText.IndexOf("`n", $loaderEnd)
        $loaderEnd = if ($nl -ge 0) { $nl + 1 } else { $loaderEnd }
        $srcText = $srcText.Remove($loaderStart, $loaderEnd - $loaderStart)
    }
}
$parts += $srcText

$fullText = ($parts -join "`r`n`r`n")
[System.IO.File]::WriteAllText($tmpFile, $fullText, [System.Text.Encoding]::Unicode)

$compileInput = $tmpFile

Write-Host ""
Write-Host "  输入: $inputFile"
Write-Host "  输出: $outputFile"
Write-Host ""
Write-Host "  正在编译..." -ForegroundColor Yellow

try {
    Invoke-ps2exe -inputFile $compileInput -outputFile $outputFile -title "PC-Optimizer-7thGen" -version "3.0.0.0" -noConsole -requireAdmin -UNICODEEncoding
} finally {
    if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue }
}

if (Test-Path $outputFile) {
    $size = [math]::Round((Get-Item $outputFile).Length / 1KB, 1)
    Write-Host ""
    Write-Host "  [成功] 编译完成！" -ForegroundColor Green
    Write-Host "  文件: $outputFile"
    Write-Host "  大小: ${size} KB"
    Write-Host ""
    Write-Host "  使用方法:" -ForegroundColor Cyan
    Write-Host "    双击 PC-Optimizer.exe 运行（自动请求管理员权限）"
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "  [失败] 编译失败！" -ForegroundColor Red
}

Write-Host "============================================" -ForegroundColor Cyan

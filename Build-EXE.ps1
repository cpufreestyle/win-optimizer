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

Write-Host ""
Write-Host "  输入: $inputFile"
Write-Host "  输出: $outputFile"
Write-Host ""
Write-Host "  正在编译..." -ForegroundColor Yellow

Invoke-ps2exe -inputFile $inputFile -outputFile $outputFile -title "PC-Optimizer-7thGen" -version "1.0.0.0" -noConsole -requireAdmin

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

<#
.SYNOPSIS
    Runtime check that Common.ps1 exports Show-ModuleFooter and that it renders
    a module footer banner without throwing. Does not change the system.
#>
$ErrorActionPreference = "Stop"

$scriptsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "scripts"
. (Join-Path $scriptsDir "Common.ps1")

$fnOk = (Get-Command Show-ModuleFooter -ErrorAction SilentlyContinue) -ne $null
Write-Host "Show-ModuleFooter exported : $(if ($fnOk) { 'OK' } else { 'FAIL' })"

Write-Host "--- sample footer (single line) ---"
Show-ModuleFooter "Network Optimization Done" -Lines @("Reboot to apply network stack changes")

Write-Host "--- sample footer (multi-line) ---"
Show-ModuleFooter "Disk Optimization Done" -Lines @(
    "SSD TRIM applied | HDD defrag applied"
    "System components cleaned and compressed"
)

Write-Host "RESULT: $(if ($fnOk) { 'PASS' } else { 'FAIL' })"

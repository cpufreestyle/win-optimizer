<#
.SYNOPSIS
    Static syntax test - parses (does not execute) every .ps1 file to check syntax,
    and reports each file's line count (to spot abnormally bloated files).
    Uses the PowerShell language parser only; no system commands are invoked, zero side effects.
#>

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$targets = @(
    (Join-Path $root "Optimize.ps1")
    (Join-Path $root "OptimizeGUI.ps1")
    (Join-Path $root "Build-EXE.ps1")
    (Join-Path $root "scripts")
)

$files = @()
foreach ($t in $targets) {
    if (Test-Path $t -PathType Leaf) { $files += $t }
    elseif (Test-Path $t -PathType Container) {
        $files += Get-ChildItem -Path $t -Filter *.ps1 -File | Select-Object -ExpandProperty FullName
    }
}
$files = $files | Sort-Object

$totalErrors = 0
$results = @()

foreach ($f in $files) {
    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errors)
    $lineCount = (Get-Content $f).Count
    $results += [PSCustomObject]@{
        File       = $f.Replace($root, ".")
        Lines      = $lineCount
        ErrorCount = $errors.Count
        Errors     = $errors
    }
    $totalErrors += $errors.Count
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "         PowerShell Syntax Test" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

foreach ($r in $results) {
    if ($r.ErrorCount -eq 0) {
        Write-Host "  [OK]   $($r.File)  ($($r.Lines) lines)" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $($r.File)  ($($r.Lines) lines, $($r.ErrorCount) errors)" -ForegroundColor Red
        foreach ($e in $r.Errors) {
            Write-Host "        L$($e.Extent.StartLineNumber): $($e.Message)" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "  Files scanned : $($results.Count)" -ForegroundColor Gray
Write-Host "  Syntax errors : $totalErrors" -ForegroundColor $(if ($totalErrors -eq 0) { "Green" } else { "Red" })
Write-Host "============================================" -ForegroundColor Cyan

exit $totalErrors

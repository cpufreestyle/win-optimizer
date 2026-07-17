<#
.SYNOPSIS
    Compile the C# launcher to PCOptimizer.exe
.DESCRIPTION
    Uses .NET Framework's csc.exe to compile Launcher.cs into a native Windows EXE.
    No external dependencies required (no ps2exe, no PowerShell modules).
#>

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Build PCOptimizer.exe (C# Launcher)" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }

$csFile    = Join-Path $scriptDir "Launcher.cs"
$outFile   = Join-Path $scriptDir "PCOptimizer.exe"

# Find csc.exe (.NET Framework C# compiler)
$dotNetDirs = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319",
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319",
    "$env:WINDIR\Microsoft.NET\Framework64\v3.5",
    "$env:WINDIR\Microsoft.NET\Framework\v3.5"
)

$csc = $null
foreach ($dir in $dotNetDirs) {
    $candidate = Join-Path $dir "csc.exe"
    if (Test-Path $candidate) {
        $csc = $candidate
        break
    }
}

if (-not $csc) {
    # Fallback: search for any v4+ compiler
    $found = Get-ChildItem "$env:WINDIR\Microsoft.NET" -Recurse -Filter "csc.exe" -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -match 'v4\.' } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if ($found) { $csc = $found.FullName }
}

if (-not $csc) {
    Write-Host "  [ERROR] Cannot find csc.exe (C# compiler)" -ForegroundColor Red
    Write-Host "  Please install .NET Framework 4.x Developer Pack" -ForegroundColor Yellow
    exit 1
}

Write-Host "  Compiler: $csc"
Write-Host "  Source:   $csFile"
Write-Host "  Output:   $outFile"
Write-Host ""

if (-not (Test-Path $csFile)) {
    Write-Host "  [ERROR] Launcher.cs not found!" -ForegroundColor Red
    exit 1
}

Write-Host "  Compiling..." -ForegroundColor Yellow

# Compile as winexe (Windows app, no console window)
& $csc /nologo /target:winexe /optimize+ /out:"$outFile" /reference:System.Windows.Forms.dll "$csFile"

if ($LASTEXITCODE -eq 0 -and (Test-Path $outFile)) {
    $size = [math]::Round((Get-Item $outFile).Length / 1KB, 1)
    Write-Host ""
    Write-Host "  [OK] Build successful!" -ForegroundColor Green
    Write-Host "  File: $outFile"
    Write-Host "  Size: ${size} KB"
    Write-Host ""
    Write-Host "  Usage:" -ForegroundColor Cyan
    Write-Host "    Double-click PCOptimizer.exe (auto UAC elevation)"
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "  [FAIL] Build failed!" -ForegroundColor Red
    Write-Host "  Exit code: $LASTEXITCODE"
}

Write-Host "============================================" -ForegroundColor Cyan

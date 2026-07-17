<#
.SYNOPSIS
    Check release-facing text files for a UTF-8 BOM, which GitHub renders as
    visible garbage (the "release mojibake" on the repo/Release page).
#>
$root = Split-Path -Parent $PSScriptRoot
$candidates = @(
    "README.md"
    "config/optimization.json"
    "Optimize.ps1"
    "OptimizeGUI.ps1"
)
$sb = New-Object System.Text.StringBuilder
foreach ($rel in $candidates) {
    $p = Join-Path $root $rel
    if (-not (Test-Path $p)) { $sb.AppendLine("$rel : MISSING"); continue }
    $b = [System.IO.File]::ReadAllBytes($p)
    $hasBom = ($b.Count -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
    $first = ($b[0..2] | ForEach-Object { $_.ToString('X2') }) -join ' '
    $sb.AppendLine("$rel : BOM=$hasBom  first3=$first") | Out-Null
}
$sb.ToString() | Out-File -FilePath (Join-Path $PSScriptRoot "release-enc.txt") -Encoding UTF8

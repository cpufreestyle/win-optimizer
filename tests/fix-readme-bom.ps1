<#
.SYNOPSIS
    Strip the UTF-8 BOM from every Markdown file in the repo. GitHub renders
    Markdown files with a leading BOM as visible garbage (the "release mojibake"),
    so .md files should be stored as UTF-8 without BOM.
#>
$root = Split-Path -Parent $PSScriptRoot
$mds = Get-ChildItem -Path $root -Recurse -Filter *.md -File

foreach ($f in $mds) {
    $b = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($b.Count -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) {
        # Decode as UTF-8 skipping the 3 BOM bytes, then write back as raw
        # UTF-8 bytes (WriteAllBytes never adds a BOM).
        $content = [System.Text.Encoding]::UTF8.GetString($b, 3, $b.Count - 3)
        $outBytes = [System.Text.Encoding]::UTF8.GetBytes($content)
        [System.IO.File]::WriteAllBytes($f.FullName, $outBytes)
        Write-Host "  stripped BOM: $($f.FullName.Substring($root.Length + 1))"
    } else {
        Write-Host "  no BOM (skip): $($f.FullName.Substring($root.Length + 1))"
    }
}
Write-Host "Done."

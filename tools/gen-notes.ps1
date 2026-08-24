# Generate release notes for the current tag.
# If tools/release-notes-<tag>.md exists, use it; otherwise auto-generate
# from git history and write to $RUNNER_TEMP/auto-notes.md.
# Outputs NOTES_PATH env var for the downstream release step.

$ErrorActionPreference = 'Stop'
$tag = $env:GITHUB_REF_NAME
if (-not $tag) { $tag = (git describe --tags --abbrev=0) }
$notes = Join-Path $PSScriptRoot ("release-notes-" + $tag + ".md")

if (Test-Path $notes) {
    Write-Host "Found $notes"
    "NOTES_PATH=$notes" | Out-File -Append -Encoding utf8 $env:GITHUB_ENV
} else {
    Write-Host "No notes file for $tag, auto-generating from git history"
    $prev = git describe --tags --abbrev=0 HEAD^ 2>$null
    if ($prev) {
        $log = git log "$prev..HEAD" --oneline
    } else {
        $log = git log --oneline -n 50
    }
    $lines = ($log | ForEach-Object { "- $_" }) -join "`n"
    $body = @"
# PC-Optimizer $tag

## Changes (since previous tag)

$lines

> Auto-generated from commit history.
"@
    $out = Join-Path $env:RUNNER_TEMP "auto-notes.md"
    Set-Content -Path $out -Value $body -Encoding UTF8
    "NOTES_PATH=$out" | Out-File -Append -Encoding utf8 $env:GITHUB_ENV
}

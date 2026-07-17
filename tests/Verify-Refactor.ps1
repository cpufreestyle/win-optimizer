<#
.SYNOPSIS
    Runtime verification of the shared Common.ps1 module and the config-driven
    DNS resolution that script 08 now relies on. Does not change the system.
#>
$ErrorActionPreference = "Stop"

# Locate the scripts folder the same way the modules do (scripts/ next to config/).
$scriptsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "scripts"
. (Join-Path $scriptsDir "Common.ps1")

$sb = New-Object System.Text.StringBuilder
$sb.AppendLine("Show-ModuleBanner runs:") | Out-Null
Show-ModuleBanner "Refactor Verify"

$cfgPath = Join-Path $scriptsDir "..\config\optimization.json"
$config = Get-OptimizationConfig -ConfigPath $cfgPath
if (-not $config) { $sb.AppendLine("  FAIL: config not loaded") | Out-Null }
else { $sb.AppendLine("  config loaded: OK") | Out-Null }

# Replicate 08's DNS resolution against the config.
$dns = $config.dns_options
$menu = @(
    @{ Key = "aliyun";     Label = "Aliyun" }
    @{ Key = "tencent";    Label = "Tencent" }
    @{ Key = "114";        Label = "114" }
    @{ Key = "google";     Label = "Google" }
    @{ Key = "cloudflare"; Label = "Cloudflare" }
)
$expected = @{
    aliyun     = @("223.5.5.5", "223.6.6.6")
    tencent    = @("119.29.29.29", "119.28.28.28")
    "114"      = @("114.114.114.114", "114.114.115.115")
    google     = @("8.8.8.8", "8.8.4.4")
    cloudflare = @("1.1.1.1", "1.0.0.1")
}
$allOk = $true
foreach ($m in $menu) {
    $primary   = ($dns.$($m.Key))[0]
    $secondary = ($dns.$($m.Key))[1]
    $pass = ($primary -eq $expected.$($m.Key)[0]) -and ($secondary -eq $expected.$($m.Key)[1])
    if (-not $pass) { $allOk = $false }
    $sb.AppendLine("  $($m.Label): $primary / $secondary  [$(if ($pass) { 'OK' } else { 'FAIL' })]") | Out-Null
}
# Hybrid option 6: aliyun primary + cloudflare secondary
$hybrid = "$(($dns.aliyun)[0]) / $(($dns.cloudflare)[0])"
$hybridOk = $hybrid -eq "223.5.5.5 / 1.1.1.1"
if (-not $hybridOk) { $allOk = $false }
$sb.AppendLine("  hybrid(6): $hybrid  [$(if ($hybridOk) { 'OK' } else { 'FAIL' })]") | Out-Null

$sb.AppendLine("RESULT: $(if ($allOk) { 'PASS' } else { 'FAIL' })") | Out-Null
$sb.ToString() | Out-File -FilePath (Join-Path $PSScriptRoot "verify-result.txt") -Encoding UTF8

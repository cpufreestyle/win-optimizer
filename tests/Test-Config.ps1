<#
.SYNOPSIS
    Config consistency test - verifies config/optimization.json can be parsed and that
    the service list / telemetry tasks / DNS options match what scripts 03 and 08 expect.
    Parse-only, does not change the system.
#>
$root = Split-Path -Parent $PSScriptRoot
$cfgPath = Join-Path $root "config\optimization.json"
$cfg = Get-Content -Path $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json

$safe  = $cfg.services.safe_to_disable
$rec   = $cfg.services.recommended_to_disable
$tasks = $cfg.telemetry_tasks
$dns   = $cfg.dns_options
$expectedDns = @("aliyun", "tencent", "114", "google", "cloudflare")

$sb = New-Object System.Text.StringBuilder
$sb.AppendLine("safe_to_disable    : $($safe.Count)") | Out-Null
$sb.AppendLine("recommended        : $($rec.Count)") | Out-Null
$sb.AppendLine("telemetry_tasks    : $($tasks.Count)") | Out-Null
$dnsCount = ($expectedDns | Where-Object { $dns.$_ }).Count
$sb.AppendLine("dns_options        : $dnsCount") | Out-Null

$ok = $true

# service / task field checks
foreach ($s in ($safe + $rec)) {
    if (-not $s.name -or -not $s.desc) { $ok = $false; $sb.AppendLine("  missing field: $($s | Out-String)") | Out-Null }
}
foreach ($t in $tasks) { if (-not $t) { $ok = $false } }

# DNS option checks: 08 depends on 5 keys, each must hold 2 IPs
foreach ($k in $expectedDns) {
    $entry = $dns.$k
    if (-not $entry -or $entry.Count -ne 2) {
        $ok = $false
        $sb.AppendLine("  dns_options.$k invalid (need 2 IPs, got: $($entry.Count))") | Out-Null
    }
}

$sb.AppendLine("field integrity     : $(if ($ok) { 'OK' } else { 'FAIL' })") | Out-Null
$sb.ToString() | Out-File -FilePath (Join-Path $PSScriptRoot "config-result.txt") -Encoding UTF8

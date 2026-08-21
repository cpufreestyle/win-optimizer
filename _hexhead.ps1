$p = Join-Path $PSScriptRoot "scripts\03-DisableServices.ps1"
$b = [System.IO.File]::ReadAllBytes($p)
Write-Output ("文件大小: " + $b.Length)
Write-Output ("前16字节(hex): " + ([BitConverter]::ToString($b[0..15])))
# 读取前3行（按 \n 或 \r\n）
$text = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
$lines = $text -split "`r?`n"
for ($i = 0; $i -lt 3; $i++) {
    $l = $lines[$i]
    Write-Output ("L$($i+1) 长度=$($l.Length) 内容: [" + $l + "]")
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($l)
    Write-Output ("  字节: " + ([BitConverter]::ToString($bytes[0..([Math]::Min(15,$bytes.Length-1))]))
}

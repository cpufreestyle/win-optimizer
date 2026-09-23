<#
.SYNOPSIS
    WebUI 备份恢复 — 时间线 / 创建 / 恢复 / 一键回滚，返回 JSON
.DESCRIPTION
    -Action timeline: 只读聚合 backups 下的备份元数据，输出「优化时间线」（新 → 旧）
    -Action create  : 创建当前系统备份（服务/启动项/视觉/电源/网络/遥测，全部写 manifest）
    -Action restore : 恢复单个域（-File 指定备份文件；省略则取该域最近一份）
    -Action rollback: 一键回滚（-Since 时间点 / -Last N 条 / -Domain 限定域 / -DryRun 只预览），
                      还原前先把当前状态备份一遍
    逻辑复用共享库 lib/Optimize.Core.ps1，与 CLI / GUI 行为一致。
#>
param(
    [ValidateSet("timeline", "create", "list", "restore", "rollback")]$Action = "timeline",
    [string]$File = "",        # restore / rollback 指定单个备份文件
    [string]$Since = "",       # rollback：回到该时间点之前（yyyy-MM-dd HH:mm:ss）
    [int]$Last = 0,            # rollback：回退最近 N 条备份
    [string[]]$Domain = @(),   # rollback：只回滚指定域
    [switch]$DryRun,           # rollback：只出计划，不做任何修改
    [switch]$SkipBackup        # rollback：跳过回滚前的「后悔药」备份
)


# 统一 stdout 为 UTF-8（让 Python subprocess.run 按 utf-8 解码时不乱码；与 OptimizeGUI 同款）
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
function Out-Json {
    param($obj)
    $obj | ConvertTo-Json -Depth 8 -Compress
}

$ErrorActionPreference = "Stop"
$backupDir = Join-Path $PSScriptRoot "..\..\backups"
$backupDir = [System.IO.Path]::GetFullPath($backupDir)

# 复用共享核心库（时间线 / 回滚 / 各域备份与还原，与 CLI / GUI 同源）
$libPath = Join-Path $PSScriptRoot "..\..\lib\Optimize.Core.ps1"
if (Test-Path $libPath) { . $libPath }
if (-not (Get-Command Get-OptimizationTimeline -ErrorAction SilentlyContinue)) {
    Out-Json ([PSCustomObject]@{ ok = $false; error = "未找到共享核心库 lib\Optimize.Core.ps1" })
    exit
}

if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }

# 单域备份创建（与 lib 的固定回滚顺序一致，便于回滚时逐域处理）
function New-DomainBackup {
    param([string]$Domain)
    switch ($Domain) {
        'services'  { return (Backup-ServiceStates    -BackupDir $backupDir -Services (Get-ServiceList)) }
        'startup'   { return (Backup-StartupItems     -BackupDir $backupDir -Items    (Get-StartupItems)) }
        'visual'    { return (Backup-VisualEffects   -BackupDir $backupDir) }
        'power'     { return (Backup-PowerPlan       -BackupDir $backupDir) }
        'network'   { return (Backup-NetworkSettings -BackupDir $backupDir) }
        'telemetry' { return (Backup-TelemetryTaskStates -BackupDir $backupDir) }
    }
    return $null
}

try {
    if ($Action -eq "timeline") {
        $entries = @(Get-OptimizationTimeline -BackupDir $backupDir -Max 200)
        $rows = @()
        foreach ($e in $entries) {
            $rows += [PSCustomObject]@{
                id              = $e.id
                timeText        = $e.timeText
                time            = $e.time
                domain          = $e.domain
                domainLabel     = $e.domainLabel
                file            = $e.file
                items           = $e.items
                host            = $e.host
                version         = $e.version
                metadataMissing = [bool]$e.metadataMissing
                sizeKB          = $e.sizeKB
            }
        }
        Out-Json ([PSCustomObject]@{ ok = $true; count = $rows.Count; timeline = $rows })
    }
    elseif ($Action -eq "create") {
        $created = @()
        foreach ($d in @('services', 'startup', 'visual', 'power', 'network', 'telemetry')) {
            try {
                $f = New-DomainBackup -Domain $d
                if ($f) { $created += [PSCustomObject]@{ domain = $d; file = (Split-Path -Leaf $f) } }
            } catch {
                $created += [PSCustomObject]@{ domain = $d; file = $null; error = $_.Exception.Message }
            }
        }
        Out-Json ([PSCustomObject]@{ ok = $true; created = $created; dir = $backupDir })
    }
    elseif ($Action -eq "list") {
        $files = @()
        if (Test-Path $backupDir) {
            $items = Get-ChildItem $backupDir -File -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -notlike '*.manifest.json' } |
                     Sort-Object LastWriteTime -Descending | Select-Object -First 50
            foreach ($b in $items) {
                $sz = if ($b.Length -gt 1KB) { "$([math]::Round($b.Length/1KB,1)) KB" } else { "$($b.Length) B" }
                $files += [PSCustomObject]@{
                    name = $b.Name
                    date = $b.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                    type = (Get-BackupDomainLabel (Get-BackupDomainFromName $b.Name))
                    size = $sz
                }
            }
        }
        Out-Json ([PSCustomObject]@{ ok = $true; files = $files })
    }
    elseif ($Action -eq "restore") {
        if (-not $File) { Out-Json ([PSCustomObject]@{ ok = $false; error = "请通过 -File 指定要恢复的备份文件（时间线中的 file 字段）" }); exit }
        $target = Join-Path $backupDir $File
        if (-not (Test-Path -LiteralPath $target)) {
            Out-Json ([PSCustomObject]@{ ok = $false; error = "备份文件不存在: $File" }); exit
        }
        $dom = Get-BackupDomainFromName (Split-Path -Leaf $File)
        # 修改必备份：先备份当前状态，再还原（后悔药）
        $safety = New-DomainBackup -Domain $dom
        $r = Restore-DomainState -Domain $dom -File $target -BackupDir $backupDir
        Out-Json ([PSCustomObject]@{
            ok        = [bool]$r -and -not $r.error
            domain    = $dom
            domainLabel = (Get-BackupDomainLabel $dom)
            file      = (Split-Path -Leaf $File)
            restored  = [int]$r.restored
            details   = @($r.details)
            safetyBackup = $(if ($safety) { Split-Path -Leaf $safety } else { $null })
            error     = $r.error
        })
    }
    elseif ($Action -eq "rollback") {
        $args = @{ BackupDir = $backupDir }
        if ($Since) {
            $dt = [datetime]::MinValue
            if (-not [datetime]::TryParse($Since, [ref]$dt)) {
                Out-Json ([PSCustomObject]@{ ok = $false; error = "无法识别的时间格式: $Since" }); exit
            }
            $args['Since'] = $dt
        }
        if ($Last -gt 0) { $args['Last'] = $Last }
        if ($Domain.Count -gt 0) { $args['Domain'] = $Domain }
        if ($File) { $args['File'] = $File }
        if ($DryRun)     { $args['DryRun']     = $true }
        if ($SkipBackup) { $args['SkipBackup'] = $true }
        $rb = Invoke-Rollback @args
        Out-Json $rb
    }
} catch {
    Out-Json ([PSCustomObject]@{ ok = $false; error = $_.Exception.Message })
}
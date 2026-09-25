# Pester unit tests for lib/Optimize.Core.ps1 pure logic
# Run: Invoke-Pester tests/Optimize.Core.Tests.ps1

# Resolve lib path robustly (Pester may change $PSScriptRoot scope)
$script:lib = Join-Path $PWD.Path 'lib\Optimize.Core.ps1'
if (-not (Test-Path $script:lib)) {
    $script:lib = Join-Path $PSScriptRoot '..\lib\Optimize.Core.ps1'
}
if (-not (Test-Path $script:lib)) {
    throw ("Cannot locate lib at: " + $script:lib)
}

Describe 'Optimize.Core config and lists' {
    BeforeAll {
        $lp = Join-Path $PWD.Path 'lib\Optimize.Core.ps1'
        . $lp
    }

    It 'Get-OptConfigPath returns existing config path' {
        $p = Get-OptConfigPath
        $p | Should -Not -BeNullOrEmpty
        Test-Path $p | Should -BeTrue
    }

    It 'Get-OptConfig returns non-null object with a valid semver version' {
        $cfg = Get-OptConfig
        $cfg | Should -Not -BeNullOrEmpty
        $cfg.version | Should -Match '^\d+\.\d+\.\d+$'
    }

    It 'Get-OptVersion matches config version' {
        $cfg = Get-OptConfig
        Get-OptVersion | Should -Be $cfg.version
    }

    It 'Get-ServiceList contains at least built-in 21 services' {
        $list = Get-ServiceList
        $list.Count | Should -BeGreaterOrEqual 21
    }

    It 'Get-ServiceList items have Name/Desc/Level' {
        $list = Get-ServiceList
        foreach ($s in $list) {
            $s.Name  | Should -Not -BeNullOrEmpty
            $s.Desc  | Should -Not -BeNullOrEmpty
            $s.Level | Should -Not -BeNullOrEmpty
        }
    }

    It 'Get-ServiceList returns exactly 21 services (10 safe + 11 recommended from config)' {
        $list = Get-ServiceList
        $list.Count | Should -Be 21
    }

    It 'Get-ServiceList levels are non-empty strings' {
        $list = Get-ServiceList
        $levels = $list | ForEach-Object { $_.Level }
        $levels | Should -Not -BeNullOrEmpty
        $levels | Should -BeOfType [string]
    }

    It 'Get-TelemetryTasks returns non-empty array' {
        $t = Get-TelemetryTasks
        $t.GetType().IsArray | Should -BeTrue
        $t.Count | Should -BeGreaterOrEqual 5
    }
}

Describe 'Optimize.Core service operations (mocked)' {
    BeforeAll {
        $lp = Join-Path $PWD.Path 'lib\Optimize.Core.ps1'
        . $lp
        Mock Get-Service -ParameterFilter { $Name -eq 'FakeSvc' } -MockWith {
            [PSCustomObject]@{ Name = 'FakeSvc'; Status = 'Stopped' }
        }
        Mock Get-CimInstance { [PSCustomObject]@{ Name = 'FakeSvc'; StartMode = 'Automatic' } }
        Mock Set-Service {}
        Mock Stop-Service {}
        Mock Start-Sleep {}
    }

    It 'Get-ServiceStartType returns StartMode string' {
        Get-ServiceStartType 'FakeSvc' | Should -Be 'Automatic'
    }

    It 'Disable-Services all mode disables every provided service' {
        $svcs = @(
            @{ Name = 'FakeSvc'; Desc = 'x'; Level = '安全禁用' }
        )
        $r = Disable-Services -Services $svcs -Mode 'all'
        $r.disabled | Should -Be 1
        $r.details.Count | Should -Be 1
    }

    It 'Disable-Services reports skipped for unknown service' {
        $svcs = @(
            @{ Name = 'MissingSvc'; Desc = 'z'; Level = '安全禁用' }
        )
        Mock Get-Service -ParameterFilter { $Name -eq 'MissingSvc' } -MockWith { $null }
        $r = Disable-Services -Services $svcs -Mode 'all'
        $r.skipped | Should -Be 1
        $r.disabled | Should -Be 0
    }
}

Describe 'Optimize.Core backup and restore (mocked)' {
    BeforeAll {
        $lp = Join-Path $PWD.Path 'lib\Optimize.Core.ps1'
        . $lp
    }
    It 'Backup-ServiceStates produces CSV restorable by Restore-Services' {
        $tmp = Join-Path $env:TEMP ("svc_test_" + (New-Guid).ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            Mock Get-ServiceStartType { return 'Disabled' }
            $svcs = @(@{ Name = 'DiagTrack'; Desc = 't' })
            $bak = Backup-ServiceStates -BackupDir $tmp -Services $svcs
            Test-Path $bak | Should -BeTrue

            Mock Get-ChildItem { [PSCustomObject]@{ FullName = $bak; LastWriteTime = Get-Date } }
            Mock Set-Service {}
            $r = Restore-Services -BackupDir $tmp
            $r.restored | Should -BeGreaterOrEqual 1
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Optimize.Core clean targets (shared with WebUI)' {
    BeforeAll {
        . (Join-Path $PWD.Path 'lib\Optimize.Core.ps1')
    }
    It 'Get-CleanTargets -All returns at least 6 targets' {
        $t = Get-CleanTargets -All
        $t.Count | Should -BeGreaterOrEqual 6
    }
    It 'Get-CleanTargets -Web returns a subset exposed to Web' {
        $w = Get-CleanTargets -Web
        $all = Get-CleanTargets -All
        $w.Count | Should -BeLessOrEqual $all.Count
        $w.Count | Should -BeGreaterOrEqual 1
    }
    It 'returned paths are expanded (no %VAR% left)' {
        foreach ($x in (Get-CleanTargets -All)) {
            $x.path | Should -Not -Match '%'
            $x.path | Should -Not -BeNullOrEmpty
        }
    }
    It 'each target has key/name/path' {
        foreach ($x in (Get-CleanTargets -All)) {
            $x.key  | Should -Not -BeNullOrEmpty
            $x.name | Should -Not -BeNullOrEmpty
            $x.path | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Optimize.Core folder sizing and logging' {
    BeforeAll {
        . (Join-Path $PWD.Path 'lib\Optimize.Core.ps1')
    }

    It 'Get-FolderSize returns 0 for empty path' {
        (Get-FolderSize '') | Should -Be 0
    }

    It 'Get-FolderSize returns 0 for non-existent path' {
        $missing = Join-Path $env:TEMP ('nofolder_' + (New-Guid).ToString('N'))
        (Get-FolderSize $missing) | Should -Be 0
    }

    It 'Get-FolderSize sums only file lengths, ignoring directory entries' {
        $tmp = Join-Path $env:TEMP ('size_test_' + (New-Guid).ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmp 'subdir') -Force | Out-Null
        try {
            $a = Join-Path $tmp 'a.txt'
            $b = Join-Path $tmp 'subdir\b.txt'
            Set-Content -Path $a -Value ('A' * 100) -NoNewline
            Set-Content -Path $b -Value ('B' * 50) -NoNewline
            $expected = (Get-Item $a).Length + (Get-Item $b).Length
            (Get-FolderSize $tmp) | Should -Be $expected
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Write-OptLog appends a line containing level and message' {
        $log = Join-Path $env:TEMP ('optlog_' + (New-Guid).ToString('N') + '.log')
        try {
            Write-OptLog -Message 'unit test message' -Level 'WARN' -Path $log 6>&1 | Out-Null
            Test-Path $log | Should -BeTrue
            $content = Get-Content $log -Raw
            $content | Should -Match 'unit test message'
            $content | Should -Match '\[WARN\]'
        } finally {
            Remove-Item $log -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Write-OptLog defaults to INFO level' {
        $log = Join-Path $env:TEMP ('optlog2_' + (New-Guid).ToString('N') + '.log')
        try {
            Write-OptLog -Message 'default level test' -Path $log 6>&1 | Out-Null
            (Get-Content $log -Raw) | Should -Match '\[INFO\]'
        } finally {
            Remove-Item $log -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Optimize.Core startup items (shared by CLI/GUI/WebUI)' {
    BeforeAll {
        . (Join-Path $PWD.Path 'lib\Optimize.Core.ps1')
        $script:FakeItems = @(
            [PSCustomObject]@{ Index = 1; Name = 'AppOne';   Value = 'C:\a.exe'; Scope = '当前用户'; Source = '注册表';       Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' }
            [PSCustomObject]@{ Index = 2; Name = 'AppTwo';   Value = 'C:\b.lnk'; Scope = '当前用户'; Source = '启动文件夹';   Path = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup" }
            [PSCustomObject]@{ Index = 3; Name = 'AppThree'; Value = 'cmd';      Scope = '某处';     Source = '系统启动命令'; Path = '某处' }
        )
    }

    It 'Get-OptBackupDir defaults to a folder named backups' {
        Split-Path (Get-OptBackupDir) -Leaf | Should -Be 'backups'
    }

    It 'Get-OptBackupDir honours explicit BackupDir' {
        (Get-OptBackupDir -BackupDir 'C:\custom\bk') | Should -Be 'C:\custom\bk'
    }

    It 'Select-StartupItems returns everything for all' {
        (Select-StartupItems -Items $script:FakeItems -Selector 'all').Count | Should -Be 3
    }

    It 'Select-StartupItems picks by index list' {
        $picked = Select-StartupItems -Items $script:FakeItems -Selector '1,3'
        $picked.Count | Should -Be 2
        $picked.Name | Should -Contain 'AppOne'
        $picked.Name | Should -Contain 'AppThree'
    }

    It 'Select-StartupItems returns empty for blank or unknown selector' {
        (Select-StartupItems -Items $script:FakeItems -Selector '').Count | Should -Be 0
        (Select-StartupItems -Items $script:FakeItems -Selector '999').Count | Should -Be 0
    }

    It 'Backup-StartupItems writes CSV with unified columns incl. Path' {
        $tmp = Join-Path $env:TEMP ('bk_' + (New-Guid).ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            $file = Backup-StartupItems -BackupDir $tmp -Items $script:FakeItems
            Test-Path $file | Should -BeTrue
            $rows = @(Import-Csv $file)
            $rows.Count | Should -Be 3
            # Path 列此前 GUI 导出时缺失，导致备份无法被恢复流程读取
            $rows[0].PSObject.Properties.Name | Should -Contain 'Path'
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Backup-StartupItems still writes header when list is empty' {
        $tmp = Join-Path $env:TEMP ('bk2_' + (New-Guid).ToString('N'))
        try {
            $file = Backup-StartupItems -BackupDir $tmp -Items @()
            Test-Path $file | Should -BeTrue
            (Get-Content $file -TotalCount 1) | Should -Match 'Path'
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Disable-StartupItems does not throw for missing registry key' {
        $fake = @(
            [PSCustomObject]@{ Index = 1; Name = 'NoSuchApp'; Value = 'x'; Scope = '当前用户'; Source = '注册表'; Path = 'HKCU:\Software\NoSuchKeyForUnitTest' }
        )
        $tmp = Join-Path $env:TEMP ('bk3_' + (New-Guid).ToString('N'))
        try {
            $r = Disable-StartupItems -BackupDir $tmp -Items $fake
            $r.failed | Should -Be 1
            $r.backup | Should -Not -BeNullOrEmpty
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Disable-StartupItems treats unknown source as failed' {
        $tmp = Join-Path $env:TEMP ('bk4_' + (New-Guid).ToString('N'))
        try {
            $r = Disable-StartupItems -BackupDir $tmp -Items @($script:FakeItems[2])
            $r.failed | Should -Be 1
            $r.disabled | Should -Be 0
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Get-StartupItems exposes unified fields on every item' {
        foreach ($it in @(Get-StartupItems)) {
            $it.Index | Should -Not -BeNullOrEmpty
            $it.Name | Should -Not -BeNullOrEmpty
            $it.PSObject.Properties.Name | Should -Contain 'Value'
            $it.PSObject.Properties.Name | Should -Contain 'Scope'
            $it.PSObject.Properties.Name | Should -Contain 'Source'
            $it.PSObject.Properties.Name | Should -Contain 'Path'
        }
    }
}

Describe 'Optimize.Core visual effects (shared by CLI/GUI/WebUI)' {
    BeforeAll {
        . (Join-Path $PWD.Path 'lib\Optimize.Core.ps1')
    }

    It 'Get-VisualEffectProfiles returns three profiles' {
        $p = @(Get-VisualEffectProfiles)
        $p.Count | Should -Be 3
        $p.Value | Should -Contain 1
        $p.Value | Should -Contain 2
        $p.Value | Should -Contain 3
        foreach ($x in $p) { $x.Title | Should -Not -BeNullOrEmpty }
    }

    It 'Get-VisualEffectToggles exposes registry target for each toggle' {
        $t = @(Get-VisualEffectToggles)
        $t.Count | Should -BeGreaterOrEqual 6
        foreach ($x in $t) {
            $x.Key | Should -Not -BeNullOrEmpty
            $x.RegKey | Should -Not -BeNullOrEmpty
            $x.RegValue | Should -Not -BeNullOrEmpty
            $x.RegType | Should -Not -BeNullOrEmpty
        }
    }

    It 'Get-VisualEffectState returns an int or null' {
        $s = Get-VisualEffectState
        if ($null -ne $s) { $s | Should -BeOfType [int] }
    }

    It 'Backup-VisualEffects creates a json backup file' {
        $tmp = Join-Path $env:TEMP ('vis_' + (New-Guid).ToString('N'))
        try {
            $f = Backup-VisualEffects -BackupDir $tmp
            Test-Path $f | Should -BeTrue
            $f | Should -Match '\.json$'
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Set-VisualEffectProfile -WhatIf is side-effect free (no backup written)' {
        $tmp = Join-Path $env:TEMP ('vis2_' + (New-Guid).ToString('N'))
        try {
            $r = Set-VisualEffectProfile -Profile 1 -BackupDir $tmp -SkipExplorerRestart -WhatIf
            $r.profile | Should -Be 1
            $r.backup | Should -BeNullOrEmpty
            $r.details.Count | Should -BeGreaterOrEqual 1
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Set-VisualEffectProfile rejects invalid profile value' {
        { Set-VisualEffectProfile -Profile 9 -WhatIf } | Should -Throw
    }

    It 'Restart-Explorer -WhatIf returns true without touching explorer' {
        Restart-Explorer -WhatIf | Should -BeTrue
    }
}

Describe 'Optimize.Core power plans (shared by CLI/GUI/WebUI)' {
    BeforeAll {
        . (Join-Path $PWD.Path 'lib\Optimize.Core.ps1')
    }

    It 'Get-PowerPlanCatalog returns three plans with GUIDs' {
        $p = @(Get-PowerPlanCatalog)
        $p.Count | Should -Be 3
        foreach ($x in $p) {
            $x.GUID | Should -Match '^[0-9a-f-]{36}$'
            $x.Title | Should -Not -BeNullOrEmpty
        }
    }

    It 'Get-ActivePowerPlan returns a GUID or null' {
        $g = Get-ActivePowerPlan
        if ($null -ne $g) { $g | Should -Match '^[0-9a-fA-F-]{36}$' }
    }

    It 'Backup-PowerPlan writes a structured json backup with the active plan GUID' {
        $tmp = Join-Path $env:TEMP ('pwr_' + (New-Guid).ToString('N'))
        try {
            $f = Backup-PowerPlan -BackupDir $tmp
            Test-Path $f | Should -BeTrue
            # 2026-09-23 起从 .txt 改为结构化 JSON：还原必须拿到活动计划 GUID 才能精确切回
            $f | Should -Match '\.json$'
            $data = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
            $data.PSObject.Properties.Name | Should -Contain 'activeGuid'
            $data.PSObject.Properties.Name | Should -Contain 'query'
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Set-PowerPlan -WhatIf is side-effect free (no backup written)' {
        $tmp = Join-Path $env:TEMP ('pwr2_' + (New-Guid).ToString('N'))
        try {
            $r = Set-PowerPlan -Guid '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' -MinPercent 100 -MaxPercent 100 `
                -DiskIdleSeconds 0 -UsbSuspendOff $true -PciAspmOff $true -BackupDir $tmp -WhatIf
            $r.ok | Should -BeTrue
            $r.appliedGuid | Should -Be '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
            $r.details.Count | Should -BeGreaterOrEqual 3
            $r.backup | Should -BeNullOrEmpty
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Set-PowerPlan ultimate unlock does not throw under -WhatIf' {
        $r = Set-PowerPlan -Guid 'e9a42b02-d5df-448d-aa00-03f14749eb61' -UnlockUltimate -FallbackToHighPerf -SkipBackup -WhatIf
        $r | Should -Not -BeNullOrEmpty
        $r.ok | Should -BeTrue
    }

    It 'Set-CpuThrottle rejects out-of-range values' {
        $r = Set-CpuThrottle -MinPercent 0 -MaxPercent 100 -WhatIf
        $r.ok | Should -BeFalse
    }
}

Describe 'Optimize.Core network (shared by CLI/GUI/WebUI)' {
    BeforeAll {
        . (Join-Path $PWD.Path 'lib\Optimize.Core.ps1')
    }

    # 编号被 WebUI 前端 index.html 硬编码，改动会直接破坏界面 —— 这里锁死
    It 'Get-DnsOptions locks stable numbering (1=Cloudflare 2=Google 3=Ali 4=114)' {
        $o = @(Get-DnsOptions)
        $o.Count | Should -BeGreaterOrEqual 4
        (@($o | Where-Object { $_.Value -eq 1 })[0]).Primary | Should -Be '1.1.1.1'
        (@($o | Where-Object { $_.Value -eq 2 })[0]).Primary | Should -Be '8.8.8.8'
        (@($o | Where-Object { $_.Value -eq 3 })[0]).Primary | Should -Be '223.5.5.5'
        (@($o | Where-Object { $_.Value -eq 4 })[0]).Primary | Should -Be '114.114.114.114'
    }

    It 'Get-DnsOptions exposes required properties on every option' {
        foreach ($o in @(Get-DnsOptions)) {
            $o.PSObject.Properties.Name | Should -Contain 'Value'
            $o.PSObject.Properties.Name | Should -Contain 'Key'
            $o.PSObject.Properties.Name | Should -Contain 'Label'
            $o.PSObject.Properties.Name | Should -Contain 'Primary'
            $o.PSObject.Properties.Name | Should -Contain 'Secondary'
        }
    }

    It 'Get-ActiveNetAdapters does not throw' {
        { @(Get-ActiveNetAdapters) } | Should -Not -Throw
    }

    It 'Get-ActiveNetAdapters items expose Name and IfIndex' {
        foreach ($a in @(Get-ActiveNetAdapters)) {
            $a.Name | Should -Not -BeNullOrEmpty
            $a.IfIndex | Should -Not -BeNullOrEmpty
        }
    }

    It 'Get-AdapterDns does not throw for unknown adapter' {
        { @(Get-AdapterDns -IfIndex 0 -Name 'NoSuchAdapter') } | Should -Not -Throw
    }

    It 'Backup-NetworkSettings writes JSON containing Date and Adapters' {
        $tmp = Join-Path $env:TEMP ('netbk_' + (New-Guid).ToString('N'))
        try {
            $f = Backup-NetworkSettings -BackupDir $tmp
            Test-Path $f | Should -BeTrue
            $j = Get-Content $f -Raw | ConvertFrom-Json
            $j.Date | Should -Not -BeNullOrEmpty
            $j.PSObject.Properties.Name | Should -Contain 'Adapters'
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Set-AdapterDns rejects empty server list' {
        $r = Set-AdapterDns -Name 'x' -DnsServers @()
        $r.ok | Should -BeFalse
    }

    It 'Set-AdapterDns -WhatIf previews without touching system' {
        $r = Set-AdapterDns -Name 'NoSuchAdapter' -IfIndex 0 -DnsServers @('1.1.1.1', '1.0.0.1') -WhatIf
        $r.ok | Should -BeTrue
        $r.whatif | Should -BeTrue
    }

    It 'Set-TcpAutoTuning -WhatIf reports ok' {
        (Set-TcpAutoTuning -WhatIf).ok | Should -BeTrue
    }

    It 'Enable-NetworkRss -WhatIf reports ok' {
        (Enable-NetworkRss -Name 'x' -WhatIf).ok | Should -BeTrue
    }

    It 'Enable-NetworkRsc -WhatIf reports ok' {
        (Enable-NetworkRsc -Name 'x' -WhatIf).ok | Should -BeTrue
    }

    It 'Clear-NetDnsCache -WhatIf reports ok' {
        (Clear-NetDnsCache -WhatIf).ok | Should -BeTrue
    }

    It 'Invoke-NetworkOptimization -WhatIf returns a result without throwing' {
        $tmp = Join-Path $env:TEMP ('netop_' + (New-Guid).ToString('N'))
        try {
            # 注意：不要用 { $r = ... } | Should -Not -Throw —— 该脚本块在子作用域执行，
            # 赋值不会回写到父作用域，$r 会一直是 $null。直接调用即可（抛错则测试自然失败）。
            $r = Invoke-NetworkOptimization -BackupDir $tmp -DnsOption 0 -WhatIf
            $r | Should -Not -BeNullOrEmpty
            $r.details | Should -Not -BeNull
            $r.adapters | Should -BeGreaterOrEqual 0
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Invoke-NetworkOptimization 无活动网卡时 details 必须可读（不能是空数组）' {
        # 三端只渲染 details：若返回空数组，无网卡环境（如 GitHub Actions runner）用户看到的是空白。
        Mock -CommandName Get-ActiveNetAdapters -MockWith { @() }
        $tmp = Join-Path $env:TEMP ('netop3_' + (New-Guid).ToString('N'))
        try {
            $r = Invoke-NetworkOptimization -BackupDir $tmp -DnsOption 0 -WhatIf
            $r.ok | Should -BeFalse
            $r.adapters | Should -Be 0
            ($r.details | Measure-Object).Count | Should -BeGreaterThan 0
            ($r.details -join ' ') | Should -Match '未检测到活动网络适配器'
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Invoke-NetworkOptimization reports invalid DNS option when adapters exist' {
        if (@(Get-ActiveNetAdapters).Count -gt 0) {
            $tmp = Join-Path $env:TEMP ('netop2_' + (New-Guid).ToString('N'))
            try {
                $r = Invoke-NetworkOptimization -BackupDir $tmp -DnsOption 999 -SkipBackup -WhatIf
                ($r.details -join ' ') | Should -Match '无效'
            } finally {
                Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Optimize.Core disk (shared by CLI/GUI/WebUI, Win7 compatible)' {
    BeforeAll {
        . (Join-Path $PWD.Path 'lib\Optimize.Core.ps1')
    }

    It 'Test-IsLegacyWindows returns a boolean' {
        (Test-IsLegacyWindows) | Should -BeOfType [bool]
    }

    It 'Get-PhysicalDiskInfo exposes required properties' {
        foreach ($d in @(Get-PhysicalDiskInfo)) {
            $d.PSObject.Properties.Name | Should -Contain 'DeviceId'
            $d.PSObject.Properties.Name | Should -Contain 'FriendlyName'
            $d.PSObject.Properties.Name | Should -Contain 'MediaType'
            $d.PSObject.Properties.Name | Should -Contain 'Size'
        }
    }

    It 'Get-FixedVolumeList exposes DriveLetter and sizes' {
        $vols = @(Get-FixedVolumeList)
        $vols.Count | Should -BeGreaterThan 0
        foreach ($v in $vols) {
            $v.DriveLetter | Should -Not -BeNullOrEmpty
            $v.PSObject.Properties.Name | Should -Contain 'Size'
            $v.PSObject.Properties.Name | Should -Contain 'SizeRemaining'
        }
    }

    It 'Get-DriveMediaMap returns a hashtable' {
        (Get-DriveMediaMap) | Should -BeOfType [hashtable]
    }

    It 'Get-VolumeMediaType resolves to SSD or HDD' {
        $vols = @(Get-FixedVolumeList)
        $m = Get-VolumeMediaType -DriveLetter $vols[0].DriveLetter -MediaMap (Get-DriveMediaMap)
        @('SSD', 'HDD') | Should -Contain $m
    }

    # ---- 关键回归：SSD 只做 TRIM，绝不做碎片整理 ----
    # 对 SSD 做碎片整理是无谓写入、损耗寿命；GUI / WebUI 此前对每个卷同时执行两者。
    It 'Invoke-VolumeOptimization does NOT defrag an SSD' {
        $r = Invoke-VolumeOptimization -DriveLetter 'C' -MediaType 'SSD' -Defrag -WhatIf
        $r.action | Should -Be '无'
    }

    It 'Invoke-VolumeOptimization does NOT trim an HDD' {
        $r = Invoke-VolumeOptimization -DriveLetter 'C' -MediaType 'HDD' -Trim -WhatIf
        $r.action | Should -Be '无'
    }

    It 'Invoke-VolumeOptimization previews TRIM for SSD' {
        $r = Invoke-VolumeOptimization -DriveLetter 'C' -MediaType 'SSD' -Trim -WhatIf
        @('TRIM(预演)', 'TRIM(跳过)') | Should -Contain $r.action
    }

    It 'Invoke-VolumeOptimization previews defrag for HDD' {
        $r = Invoke-VolumeOptimization -DriveLetter 'C' -MediaType 'HDD' -Defrag -WhatIf
        $r.action | Should -Be '碎片整理(预演)'
    }

    It 'Invoke-WinSxSCleanup -WhatIf previews only' {
        (Invoke-WinSxSCleanup -WhatIf) | Should -Match '预演'
    }

    It 'Set-CompactOSState -WhatIf previews only' {
        (Set-CompactOSState -Enable -WhatIf) | Should -Match '预演'
    }

    It 'Invoke-DiskOptimization -WhatIf returns per-volume details' {
        # 限定 C: 以控制耗时（介质判定会调用 defrag /A 分析）
        $r = Invoke-DiskOptimization -Trim $true -Defrag $true -WinSxS $false -Compact $false `
                                     -DriveLetters @('C') -WhatIf
        $r | Should -Not -BeNullOrEmpty
        $r.details | Should -Not -BeNull
        $r.volumes | Should -BeGreaterThan 0
    }

    # ---- CompactOS：显式开关、默认关闭（HANDOFF §7.1） ----
    # 压缩系统文件耗时长、回滚要再跑一次 Compact.exe /CompactOS:never，
    # 此前 CLI 无条件执行，而 GUI / WebUI 默认关闭 —— 三端已统一为「默认关闭、显式开启」。
    It 'Get-CompactOSDefault returns a bool and is false by default' {
        $d = Get-CompactOSDefault
        $d | Should -BeOfType [bool]
        $d | Should -BeFalse
    }

    It 'config disk.compact_os_default exists and is false' {
        $cfg = Get-OptConfig
        $cfg.disk | Should -Not -BeNullOrEmpty
        $cfg.disk.compact_os_default | Should -BeFalse
    }

    It 'Invoke-DiskOptimization -WhatIf does NOT touch CompactOS by default' {
        $r = Invoke-DiskOptimization -Trim $true -Defrag $true -WinSxS $false `
                                     -DriveLetters @('C') -WhatIf
        ($r.details -join '|') | Should -Not -Match 'CompactOS'
    }

    It 'Invoke-DiskOptimization runs CompactOS only when explicitly requested' {
        $r = Invoke-DiskOptimization -Trim $false -Defrag $false -WinSxS $false -Compact $true `
                                     -DriveLetters @('C') -WhatIf
        ($r.details -join '|') | Should -Match 'CompactOS'
    }

    It 'CLI 磁盘脚本不再无条件压缩系统文件（Set-CompactOSState 必须受 if 保护）' {
        $p = Join-Path $PWD.Path 'scripts\07-DiskOptimize.ps1'
        Test-Path $p | Should -BeTrue
        $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$null, [ref]$errs)
        $errs.Count | Should -Be 0
        $cmds = @($ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and
            $n.GetCommandName() -eq 'Set-CompactOSState'
        }, $true))
        # 仍然复用共享库函数（不允许各自另写一份 compact 实现）
        $cmds.Count | Should -BeGreaterThan 0
        foreach ($c in $cmds) {
            $guarded = $false
            $node = $c.Parent
            while ($node) {
                if ($node -is [System.Management.Automation.Language.IfStatementAst]) { $guarded = $true; break }
                $node = $node.Parent
            }
            $guarded | Should -BeTrue
        }
    }

    It '三端 CompactOS 默认值同源（均走 Get-CompactOSDefault）' {
        foreach ($rel in @('scripts\07-DiskOptimize.ps1', 'gui\pages\Disk.ps1', 'webui\ps\07_disk.ps1')) {
            $f = Join-Path $PWD.Path $rel
            Test-Path $f | Should -BeTrue
            (Get-Content $f -Raw -Encoding UTF8) | Should -Match 'Get-CompactOSDefault'
        }
    }
}

Describe 'Optimize.Core health check and before/after comparison' {
    BeforeAll {
        . (Join-Path $PWD.Path 'lib\Optimize.Core.ps1')
        # 体检用 -SkipCleanScan：跳过递归统计可清理空间，避免测试变慢
        $script:HcOpt = @{ SkipCleanScan = $true }
    }

    It 'New-HealthIssue assigns penalty by severity' {
        (New-HealthIssue -Id 'x' -Severity 'High'   -Title 't' -Detail 'd' -Suggestion 's').penalty | Should -Be 15
        (New-HealthIssue -Id 'x' -Severity 'Medium' -Title 't' -Detail 'd' -Suggestion 's').penalty | Should -Be 8
        (New-HealthIssue -Id 'x' -Severity 'Low'    -Title 't' -Detail 'd' -Suggestion 's').penalty | Should -Be 3
    }

    It 'Get-SystemHealthReport returns required top-level fields' {
        $r = Get-SystemHealthReport @script:HcOpt
        $r.timestamp | Should -Not -BeNullOrEmpty
        $r.PSObject.Properties.Name | Should -Contain 'score'
        $r.PSObject.Properties.Name | Should -Contain 'grade'
        $r.PSObject.Properties.Name | Should -Contain 'metrics'
        $r.PSObject.Properties.Name | Should -Contain 'issues'
    }

    It 'Get-SystemHealthReport score stays within 0..100' {
        $r = Get-SystemHealthReport @script:HcOpt
        $r.score | Should -BeGreaterOrEqual 0
        $r.score | Should -BeLessOrEqual 100
    }

    It 'Get-SystemHealthReport score = 100 - total penalty (floored at 0)' {
        $r = Get-SystemHealthReport @script:HcOpt
        $penalty = 0
        foreach ($i in @($r.issues)) { $penalty += $i.penalty }
        $expected = if ($penalty -ge 100) { 0 } else { 100 - $penalty }
        $r.score | Should -Be $expected
    }

    It 'Get-SystemHealthReport metrics expose key indicators' {
        $r = Get-SystemHealthReport @script:HcOpt
        $names = $r.metrics.PSObject.Properties.Name
        $names | Should -Contain 'freeRamPct'
        $names | Should -Contain 'startupCount'
        $names | Should -Contain 'servicesStillAuto'
        $names | Should -Contain 'visualTogglesLeft'
        $names | Should -Contain 'powerPlanTitle'
        $names | Should -Contain 'activeAdapters'
    }

    It 'Save-HealthReport writes a readable JSON with same score' {
        $tmp = Join-Path $env:TEMP ('health_' + (New-Guid).ToString('N'))
        try {
            $r = Get-SystemHealthReport @script:HcOpt
            $f = Save-HealthReport -Report $r -BackupDir $tmp
            Test-Path $f | Should -BeTrue
            $loaded = Get-Content $f -Raw | ConvertFrom-Json
            $loaded.score | Should -Be $r.score
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Save-HealthReport never overwrites within the same second' {
        $tmp = Join-Path $env:TEMP ('health2_' + (New-Guid).ToString('N'))
        try {
            $r = Get-SystemHealthReport @script:HcOpt
            $f1 = Save-HealthReport -Report $r -BackupDir $tmp
            $f2 = Save-HealthReport -Report $r -BackupDir $tmp
            $f1 | Should -Not -Be $f2
            (@(Get-HealthHistory -BackupDir $tmp)).Count | Should -Be 2
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Get-PreviousHealthReport loads latest and honours ExcludeFile' {
        $tmp = Join-Path $env:TEMP ('health3_' + (New-Guid).ToString('N'))
        try {
            $r = Get-SystemHealthReport @script:HcOpt
            $f = Save-HealthReport -Report $r -BackupDir $tmp
            (Get-PreviousHealthReport -BackupDir $tmp).score | Should -Be $r.score
            (Get-PreviousHealthReport -BackupDir $tmp -ExcludeFile $f) | Should -BeNullOrEmpty
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Compare-HealthReports reports no change for identical reports' {
        $r = Get-SystemHealthReport @script:HcOpt
        $c = Compare-HealthReports -Before $r -After $r
        $c.scoreDelta | Should -Be 0
        @($c.resolved).Count | Should -Be 0
        @($c.new).Count | Should -Be 0
    }

    It 'Compare-HealthReports detects resolved issue and metric delta' {
        # 构造轻量报告（不跑真实扫描），保证确定性与速度
        $before = [PSCustomObject]@{
            timestamp = 't1'; score = 70
            issues    = @((New-HealthIssue 'a' 'High' 'A' 'd' 's'), (New-HealthIssue 'b' 'Low' 'B' 'd' 's'))
            metrics   = [PSCustomObject]@{ startupCount = 20 }
        }
        $after = [PSCustomObject]@{
            timestamp = 't2'; score = 85
            issues    = @((New-HealthIssue 'b' 'Low' 'B' 'd' 's'))
            metrics   = [PSCustomObject]@{ startupCount = 12 }
        }
        $c = Compare-HealthReports -Before $before -After $after
        $c.scoreDelta | Should -Be 15
        @($c.resolved).Count | Should -Be 1
        $c.resolved[0].id | Should -Be 'a'
        @($c.new).Count | Should -Be 0
        (@($c.metricDeltas | Where-Object { $_.metric -eq 'startupCount' })[0]).delta | Should -Be -8
    }

    It 'Compare-HealthReports returns null when either side is missing' {
        (Compare-HealthReports -Before $null -After (Get-SystemHealthReport @script:HcOpt)) | Should -BeNullOrEmpty
    }
}


Describe 'Optimize.Core telemetry tasks (shared by CLI/GUI/WebUI)' {
    BeforeAll {
        $lp = Join-Path $PWD.Path 'lib\Optimize.Core.ps1'
        . $lp
    }

    It 'Get-TelemetryTasks returns non-empty array of task paths' {
        $t = Get-TelemetryTasks
        @($t).Count | Should -BeGreaterThan 0
        $t[0] | Should -Match '^\\'
    }

    It 'Get-TelemetryTaskStates returns one entry per configured task' {
        $states = Get-TelemetryTaskStates
        @($states).Count | Should -Be @(Get-TelemetryTasks).Count
        foreach ($s in $states) {
            $s.name     | Should -Not -BeNullOrEmpty
            $s.taskPath | Should -Match '\\$'
            $s.exists   | Should -BeOfType [bool]
        }
    }

    It 'Get-ScheduledTaskState reports exists=$false for a bogus task' {
        $r = Get-ScheduledTaskState -TaskPath '\NoSuch\Path\' -TaskName 'NoSuchTask_12345'
        $r.exists | Should -BeFalse
    }

    It 'Disable-TelemetryTasks -WhatIf previews only and writes no backup' {
        $tmp = Join-Path $env:TEMP ('tele_test_' + (New-Guid).ToString('N'))
        try {
            $r = Disable-TelemetryTasks -BackupDir $tmp -WhatIf
            $r.backup | Should -BeNullOrEmpty
            Test-Path $tmp | Should -BeFalse
            # 预览计数与实际可禁用任务数一致（幂等：重复运行不重复计数）
            $r2 = Disable-TelemetryTasks -BackupDir $tmp -WhatIf
            $r2.disabled | Should -Be $r.disabled
            $r2.details.Count | Should -Be $r.details.Count
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Disable-TelemetryTasks details use only known result vocabulary' {
        $tmp = Join-Path $env:TEMP ('tele_test_' + (New-Guid).ToString('N'))
        try {
            $r = Disable-TelemetryTasks -BackupDir $tmp -WhatIf
            foreach ($d in $r.details) {
                $d.result | Should -Match '^(已禁用|将禁用\(预览\)|已处于禁用，已跳过|不存在，已跳过|失败: .+)$'
            }
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Backup-TelemetryTaskStates writes JSON listing every configured task' {
        $tmp = Join-Path $env:TEMP ('tele_test_' + (New-Guid).ToString('N'))
        try {
            $f = Backup-TelemetryTaskStates -BackupDir $tmp
            Test-Path $f | Should -BeTrue
            $f | Should -Match 'telemetry_backup_\d{8}_\d{6}\.json$'
            $data = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
            @($data.tasks).Count | Should -Be @(Get-TelemetryTasks).Count
            $data.host | Should -Be $env:COMPUTERNAME
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Restore-TelemetryTasks errors cleanly when no backup exists' {
        $tmp = Join-Path $env:TEMP ('tele_test_' + (New-Guid).ToString('N'))
        try {
            $r = Restore-TelemetryTasks -BackupDir $tmp
            $r.error | Should -Match '未找到'
            $r.restored | Should -Be 0
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Restore-TelemetryTasks re-enables tasks that were enabled at backup time (mocked)' {
        $tmp = Join-Path $env:TEMP ('tele_test_' + (New-Guid).ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            $f = Join-Path $tmp 'telemetry_backup_20200101_000000.json'
            @{
                date  = '2020-01-01 00:00:00'
                host  = $env:COMPUTERNAME
                tasks = @(
                    @{ name = 'TaskEnabled';  taskPath = '\Microsoft\Test\'; state = 'Ready'    }
                    @{ name = 'TaskDisabled'; taskPath = '\Microsoft\Test\'; state = 'Disabled' }
                    @{ name = 'TaskMissing';  taskPath = '\Microsoft\Test\'; state = $null      }
                )
            } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $f -Encoding UTF8

            Mock Set-ScheduledTaskState { param($TaskPath, $TaskName, $Enable) return $Enable } -ParameterFilter { $TaskName -eq 'TaskEnabled' }

            $r = Restore-TelemetryTasks -BackupDir $tmp -File $f
            $r.error | Should -BeNullOrEmpty
            $r.restored | Should -Be 1
            @($r.details | Where-Object { $_.result -like '已重新启用' }).Count | Should -Be 1
            @($r.details | Where-Object { $_.name -eq 'TaskDisabled' }).Count | Should -Be 1
            ($r.details | Where-Object { $_.name -eq 'TaskDisabled' }).result | Should -Match '保持禁用'
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Optimize.Core health auto-remediation (shared by CLI/GUI/WebUI)' {
    BeforeAll {
        . (Join-Path $PWD.Path 'lib\Optimize.Core.ps1')
        # 构造轻量报告，保证确定性与速度（不跑真实扫描）
        $script:RemRep = [PSCustomObject]@{
            timestamp = 't'; score = 50; grade = '一般'
            issues = @(
                (New-HealthIssue 'services.auto'       'Medium' 'svc'  'd' 's' 'services.disable'),
                (New-HealthIssue 'startup.many'        'Medium' 'st'   'd' 's' 'startup.list'),
                (New-HealthIssue 'visual.effects'      'High'   'vis'  'd' 's' 'visual.profile'),
                (New-HealthIssue 'power.balanced'      'High'   'pwr'  'd' 's' 'power.plan'),
                (New-HealthIssue 'disk.cleanable'      'Medium' 'cln'  'd' 's' 'disk.clean'),
                (New-HealthIssue 'network.dns.adapterA' 'Low'   'dnsA' 'd' 's' 'network.dns'),
                (New-HealthIssue 'network.dns.adapterB' 'Low'   'dnsB' 'd' 's' 'network.dns'),
                (New-HealthIssue 'memory.low'          'High'   'mem'  'd' 's' ''),
                (New-HealthIssue 'disk.space'          'High'   'spc'  'd' 's' '')
            )
            metrics = [PSCustomObject]@{}
        }
    }

    It 'New-HealthIssue exposes an optional remediation field (defaults to empty)' {
        (New-HealthIssue 'a' 'Low' 't' 'd' 's').remediation | Should -Be ''
        (New-HealthIssue 'a' 'Low' 't' 'd' 's' 'visual.profile').remediation | Should -Be 'visual.profile'
    }

    It 'Get-HealthSeverityRank orders High > Medium > Low' {
        (Get-HealthSeverityRank 'High')   | Should -BeGreaterThan (Get-HealthSeverityRank 'Medium')
        (Get-HealthSeverityRank 'Medium') | Should -BeGreaterThan (Get-HealthSeverityRank 'Low')
        Get-HealthSeverityRank 'unknown' | Should -Be 0
    }

    It 'Get-HealthRemediationCatalog keeps domain/action pairs unique' {
        $cat = @(Get-HealthRemediationCatalog)
        $cat.Count | Should -BeGreaterThan 0
        $keys = @($cat | ForEach-Object { $_.IdPattern })
        $keys.Count | Should -Be ($keys | Select-Object -Unique).Count
        $cat | Where-Object { $_.Auto } | ForEach-Object { $_.Action | Should -Not -BeNullOrEmpty }
    }

    It 'Resolve-HealthRemediation matches dynamic network issue ids by pattern' {
        $m = Resolve-HealthRemediation -Issue @($script:RemRep.issues | Where-Object { $_.id -eq 'network.dns.adapterA' })[0]
        $m.Code | Should -Be 'network.dns'
        $m.Domain | Should -Be 'network'
    }

    It 'Resolve-HealthRemediation falls back to id match when remediation is absent' {
        $legacy = [PSCustomObject]@{ id = 'services.auto'; severity = 'Medium'; title='t'; detail='d'; suggestion='s' }
        (Resolve-HealthRemediation -Issue $legacy).Code | Should -Be 'services.disable'
    }

    It 'Resolve-HealthRemediation returns null for unmapped issues' {
        Resolve-HealthRemediation -Issue (New-HealthIssue 'foo.bar' 'Low' 't' 'd' 's') | Should -BeNullOrEmpty
    }

    It 'Get-HealthRemediationPlan maps every issue to a domain and stays read-only' {
        $plan = @(Get-HealthRemediationPlan -Report $script:RemRep -SkipCleanScan)
        $plan.Count | Should -Be 9
        $plan | ForEach-Object {
            $_.domain | Should -Not -BeNullOrEmpty
            $_.PSObject.Properties.Name | Should -Contain 'auto'
            $_.PSObject.Properties.Name | Should -Contain 'target'
            $_.PSObject.Properties.Name | Should -Contain 'impact'
        }
        @($plan | Where-Object { $_.auto }).Count      | Should -Be 6
        @($plan | Where-Object { -not $_.auto }).Count | Should -Be 3
    }

    It 'Get-HealthRemediationPlan keeps advice-only issues non-actionable' {
        $plan = @(Get-HealthRemediationPlan -Report $script:RemRep -SkipCleanScan)
        foreach ($id in @('startup.many', 'memory.low', 'disk.space')) {
            @($plan | Where-Object { $_.id -eq $id })[0].auto | Should -BeFalse
        }
    }

    It 'Get-HealthRemediationPlan accepts a real (non-synthetic) report shape' {
        $real = Get-SystemHealthReport -SkipCleanScan
        $plan = @(Get-HealthRemediationPlan -Report $real -SkipCleanScan)
        foreach ($p in $plan) {
            $p.PSObject.Properties.Name | Should -Contain 'actionKey'
            if ($p.auto) {
                $p.actionKey | Should -Not -BeNullOrEmpty
                $p.action    | Should -Not -BeNullOrEmpty
            }
        }
    }

    It 'Invoke-HealthRemediation -WhatIf never writes a backup and reports whatIf' {
        $tmp = Join-Path $env:TEMP ('rem_' + (New-Guid).ToString('N'))
        try {
            $r = Invoke-HealthRemediation -Report $script:RemRep -BackupDir $tmp -WhatIf -SkipCleanScan
            $r.whatIf | Should -BeTrue
            @($r.results).Count | Should -Be 3
            (Test-Path $tmp -PathType Container) | Should -BeFalse
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Invoke-HealthRemediation blocks High severity unless -Force is given' {
        $tmp = Join-Path $env:TEMP ('rem2_' + (New-Guid).ToString('N'))
        try {
            $r = Invoke-HealthRemediation -Report $script:RemRep -BackupDir $tmp -WhatIf -SkipCleanScan
            @($r.executed) | Should -Not -Contain 'visual.effects'
            @($r.executed) | Should -Not -Contain 'power.balanced'
            @($r.skipped | Where-Object { $_.id -eq 'visual.effects' }).Count | Should -Be 1

            $r2 = Invoke-HealthRemediation -Report $script:RemRep -BackupDir $tmp -WhatIf -SkipCleanScan -MaxSeverity 'High'
            @($r2.executed) | Should -Not -Contain 'power.balanced'

            $r3 = Invoke-HealthRemediation -Report $script:RemRep -BackupDir $tmp -WhatIf -SkipCleanScan -MaxSeverity 'High' -Force
            @($r3.executed) | Should -Contain 'visual.effects'
            @($r3.executed) | Should -Contain 'power.balanced'
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Invoke-HealthRemediation merges repeated network issues into one execution' {
        $tmp = Join-Path $env:TEMP ('rem3_' + (New-Guid).ToString('N'))
        try {
            $r = Invoke-HealthRemediation -Report $script:RemRep -BackupDir $tmp -WhatIf -SkipCleanScan
            @($r.executed | Where-Object { $_ -like 'network.dns.*' }).Count | Should -Be 1
            @($r.skipped  | Where-Object { $_.id -eq 'network.dns.adapterB' }).Count | Should -Be 1
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Invoke-HealthRemediation honours -IssueCode filtering' {
        $tmp = Join-Path $env:TEMP ('rem4_' + (New-Guid).ToString('N'))
        try {
            $r = Invoke-HealthRemediation -Report $script:RemRep -BackupDir $tmp -WhatIf -SkipCleanScan `
                                           -IssueCode @('services.auto')
            @($r.executed) | Should -Be @('services.auto')
            @($r.skipped).Count | Should -Be 0
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Invoke-HealthRemediation returns a structured failure when nothing is actionable' {
        $empty = [PSCustomObject]@{ timestamp='t'; score=100; issues=@(); metrics=[PSCustomObject]@{} }
        $r = Invoke-HealthRemediation -Report $empty -BackupDir (Join-Path $env:TEMP ('rem5_' + (New-Guid).ToString('N'))) -SkipCleanScan
        $r.ok | Should -BeFalse
        $r.error | Should -Not -BeNullOrEmpty
    }
}

Describe 'Optimize.Core backup manifest and timeline (shared by CLI/GUI/WebUI)' {
    BeforeAll {
        . (Join-Path $PWD.Path 'lib\Optimize.Core.ps1')
        # 测试夹具：写一份带指定时间戳 manifest 的假备份，保证排序断言确定
        function script:New-FakeBackup {
            param([string]$Dir, [string]$Domain, [string]$Stamp)
            $ext = 'json'
            if ($Domain -eq 'services' -or $Domain -eq 'startup') { $ext = 'csv' }
            if ($Domain -eq 'update') { $ext = 'reg' }
            $name = "${Domain}_backup_$Stamp.$ext"
            $f = Join-Path $Dir $name
            Set-Content -LiteralPath $f -Value '{}' -Encoding UTF8
            $t = [datetime]::ParseExact($Stamp, 'yyyyMMdd_HHmmss', $null)
            [PSCustomObject]@{
                version  = (Get-OptVersion)
                domain   = $Domain
                file     = $name
                date     = $t.ToString('yyyy-MM-dd HH:mm:ss')
                time     = $t.ToString('yyyy-MM-ddTHH:mm:ss')
                items    = 1
                bytes    = 10
                host     = $env:COMPUTERNAME
                user     = 'test'
                note     = ''
            } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath ($f + '.manifest.json') -Encoding UTF8
            return $f
        }
    }

    It 'Write-BackupManifest records domain/items/version/host beside the backup file' {
        $tmp = Join-Path $env:TEMP ('mf_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            $bak = Join-Path $tmp 'services_backup_20260101_010101.csv'
            Set-Content -LiteralPath $bak -Value 'Name,StartType,Date' -Encoding UTF8
            $mf = Write-BackupManifest -BackupFile $bak -Domain 'services' -ItemCount 7 -Note 'smoke'
            Test-Path $mf | Should -BeTrue
            $mf | Should -Match '\.manifest\.json$'
            $data = Get-Content -LiteralPath $mf -Raw | ConvertFrom-Json
            $data.domain  | Should -Be 'services'
            $data.items   | Should -Be 7
            $data.file    | Should -Be 'services_backup_20260101_010101.csv'
            $data.host    | Should -Be $env:COMPUTERNAME
            $data.version | Should -Be (Get-OptVersion)
            $data.date    | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Write-BackupManifest never throws when the backup file is missing' {
        $r = Write-BackupManifest -BackupFile (Join-Path $env:TEMP ('nope_' + (New-Guid).ToString('N') + '.csv')) -Domain 'services'
        $r | Should -BeNullOrEmpty
    }

    It 'every domain Backup-* writes a manifest next to its backup file' {
        $tmp = Join-Path $env:TEMP ('mf2_' + (New-Guid).ToString('N'))
        try {
            $svc   = Backup-ServiceStates       -BackupDir $tmp -Services @(@{Name='DiagTrack'})
            $start = Backup-StartupItems        -BackupDir $tmp -Items @()
            $vis   = Backup-VisualEffects       -BackupDir $tmp
            $pw    = Backup-PowerPlan           -BackupDir $tmp
            foreach ($f in @($svc, $start, $vis, $pw)) {
                $f | Should -Not -BeNullOrEmpty
                Test-Path ($f + '.manifest.json') | Should -BeTrue
            }
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Get-BackupDomainLabel gives a Chinese label for every backup domain' {
        Get-BackupDomainLabel -Domain 'services'  | Should -Be '服务'
        Get-BackupDomainLabel -Domain 'startup'   | Should -Be '启动项'
        Get-BackupDomainLabel -Domain 'visual'    | Should -Be '视觉效果'
        Get-BackupDomainLabel -Domain 'power'     | Should -Be '电源计划'
        Get-BackupDomainLabel -Domain 'network'   | Should -Be '网络 DNS'
        Get-BackupDomainLabel -Domain 'telemetry' | Should -Be '遥测计划任务'
        Get-BackupDomainLabel -Domain 'update'    | Should -Be 'Windows 更新'
    }

    It 'Get-BackupDomainFromName understands both new and legacy naming' {
        Get-BackupDomainFromName 'services_backup_20260101_010101.csv'   | Should -Be 'services'
        Get-BackupDomainFromName 'services_20260101_010101.csv'          | Should -Be 'services'
        Get-BackupDomainFromName 'startup_backup_20260101_010101.csv'    | Should -Be 'startup'
        Get-BackupDomainFromName 'startup_20260101_010101.csv'           | Should -Be 'startup'
        Get-BackupDomainFromName 'visual_backup_20260101_010101.json'    | Should -Be 'visual'
        Get-BackupDomainFromName 'visual_20260101_010101.txt'            | Should -Be 'visual'
        Get-BackupDomainFromName 'power_backup_20260101_010101.json'     | Should -Be 'power'
        Get-BackupDomainFromName 'power_backup_20260101_010101.txt'      | Should -Be 'power'
        Get-BackupDomainFromName 'network_backup_20260101_010101.json'   | Should -Be 'network'
        Get-BackupDomainFromName 'telemetry_backup_20260101_010101.json' | Should -Be 'telemetry'
        Get-BackupDomainFromName 'winupdate_block_20260101_010101.reg'   | Should -Be 'update'
        Get-BackupDomainFromName 'manual_update_20260101_010101.reg'     | Should -Be 'update'
        Get-BackupDomainFromName 'totally_unknown.bin'                   | Should -Be 'unknown'
    }

    It 'Get-OptimizationTimeline sorts newest first and flags legacy backups as metadata-missing' {
        $tmp = Join-Path $env:TEMP ('tl_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            # 旧格式备份（GUI / 早期 WebUI 命名，没有 manifest）：靠文件名 + 文件时间兜底
            $legacy = Join-Path $tmp 'startup_20200101_000000.csv'
            Set-Content -LiteralPath $legacy -Value 'Name,Value,Scope,Source,Path' -Encoding UTF8
            (Get-Item -LiteralPath $legacy).LastWriteTime = [datetime]'2020-01-01 00:00:00'
            # 现代备份（带 manifest，时间更晚）
            $null = New-FakeBackup -Dir $tmp -Domain 'services' -Stamp '20260101_010101'

            $tl = @(Get-OptimizationTimeline -BackupDir $tmp)
            $tl.Count | Should -Be 2
            $tl[0].file | Should -Be 'services_backup_20260101_010101.csv'
            $tl[0].metadataMissing | Should -BeFalse
            $tl[0].domain | Should -Be 'services'
            $tl[0].items  | Should -Be 1
            $tl[0].host   | Should -Be $env:COMPUTERNAME
            $tl[1].file | Should -Be 'startup_20200101_000000.csv'
            $tl[1].metadataMissing | Should -BeTrue
            $tl[1].domain | Should -Be 'startup'
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Get-OptimizationTimeline ignores manifest sidecar files and honours -Max' {
        $tmp = Join-Path $env:TEMP ('tl2_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            1..4 | ForEach-Object { $null = New-FakeBackup -Dir $tmp -Domain 'services' -Stamp ("2026010${_}_000000") }
            @(Get-OptimizationTimeline -BackupDir $tmp).Count | Should -Be 4
            @(Get-OptimizationTimeline -BackupDir $tmp -Max 2).Count | Should -Be 2
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Get-OptimizationTimeline returns nothing (not an error) when the folder is empty' {
        $tmp = Join-Path $env:TEMP ('tl3_' + (New-Guid).ToString('N'))
        try {
            @(Get-OptimizationTimeline -BackupDir $tmp).Count | Should -Be 0
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Optimize.Core rollback plan and one-click rollback (shared by CLI/GUI/WebUI)' {
    BeforeAll {
        . (Join-Path $PWD.Path 'lib\Optimize.Core.ps1')
        function script:New-FakeBackup {
            param([string]$Dir, [string]$Domain, [string]$Stamp)
            $ext = 'json'
            if ($Domain -eq 'services' -or $Domain -eq 'startup') { $ext = 'csv' }
            if ($Domain -eq 'update') { $ext = 'reg' }
            $name = "${Domain}_backup_$Stamp.$ext"
            $f = Join-Path $Dir $name
            Set-Content -LiteralPath $f -Value '{}' -Encoding UTF8
            $t = [datetime]::ParseExact($Stamp, 'yyyyMMdd_HHmmss', $null)
            [PSCustomObject]@{
                version  = (Get-OptVersion)
                domain   = $Domain
                file     = $name
                date     = $t.ToString('yyyy-MM-dd HH:mm:ss')
                time     = $t.ToString('yyyy-MM-ddTHH:mm:ss')
                items    = 1
                bytes    = 10
                host     = $env:COMPUTERNAME
                user     = 'test'
                note     = ''
            } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath ($f + '.manifest.json') -Encoding UTF8
            return $f
        }
    }

    It 'Get-RollbackPlan without filters picks the newest backup of every domain' {
        $tmp = Join-Path $env:TEMP ('rb_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            $null = New-FakeBackup -Dir $tmp -Domain 'services' -Stamp '20260101_000000'
            $null = New-FakeBackup -Dir $tmp -Domain 'power'    -Stamp '20260201_000000'
            $plan = Get-RollbackPlan -BackupDir $tmp
            $plan.ok | Should -BeTrue
            $plan.mode | Should -Be 'point'
            @($plan.entries).Count | Should -Be 2
            foreach ($e in @($plan.entries)) {
                $e.file | Should -Not -BeNullOrEmpty
                Test-Path $e.path | Should -BeTrue
            }
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Get-RollbackPlan -Last N falls back to the state N backups ago' {
        $tmp = Join-Path $env:TEMP ('rb2_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            $null = New-FakeBackup -Dir $tmp -Domain 'services' -Stamp '20260101_000000'
            $null = New-FakeBackup -Dir $tmp -Domain 'services' -Stamp '20260201_000000'
            $null = New-FakeBackup -Dir $tmp -Domain 'services' -Stamp '20260301_000000'
            (Get-RollbackPlan -BackupDir $tmp -Last 1).entries[0].file | Should -Be 'services_backup_20260301_000000.csv'
            (Get-RollbackPlan -BackupDir $tmp -Last 2).entries[0].file | Should -Be 'services_backup_20260201_000000.csv'
            (Get-RollbackPlan -BackupDir $tmp -Last 3).entries[0].file | Should -Be 'services_backup_20260101_000000.csv'
            $p9 = Get-RollbackPlan -BackupDir $tmp -Last 9
            $p9.ok | Should -BeFalse
            $p9.error | Should -Match '备份数量不足'
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Get-RollbackPlan -Since keeps only the newest backup per domain at that point in time' {
        $tmp = Join-Path $env:TEMP ('rb3_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            $null = New-FakeBackup -Dir $tmp -Domain 'services' -Stamp '20260101_000000'
            $null = New-FakeBackup -Dir $tmp -Domain 'services' -Stamp '20260301_000000'
            $null = New-FakeBackup -Dir $tmp -Domain 'power'    -Stamp '20260201_000000'
            $p = Get-RollbackPlan -BackupDir $tmp -Since ([datetime]'2026-02-15 00:00:00')
            $p.ok | Should -BeTrue
            @($p.entries).Count | Should -Be 2
            (@($p.entries | Where-Object { $_.domain -eq 'services' }))[0].file | Should -Be 'services_backup_20260101_000000.csv'
            (@($p.entries | Where-Object { $_.domain -eq 'power'    }))[0].file | Should -Be 'power_backup_20260201_000000.json'
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Get-RollbackPlan -Domain filters and -File selects a single backup' {
        $tmp = Join-Path $env:TEMP ('rb4_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            $svc = New-FakeBackup -Dir $tmp -Domain 'services' -Stamp '20260101_000000'
            $pw  = New-FakeBackup -Dir $tmp -Domain 'power'    -Stamp '20260201_000000'

            $only = Get-RollbackPlan -BackupDir $tmp -Domain 'power'
            $only.ok | Should -BeTrue
            @($only.entries).Count | Should -Be 1
            $only.entries[0].domain | Should -Be 'power'

            $bad = Get-RollbackPlan -BackupDir $tmp -Domain 'telemetry'
            $bad.ok | Should -BeFalse
            $bad.error | Should -Not -BeNullOrEmpty

            $file = Get-RollbackPlan -BackupDir $tmp -File $svc
            $file.ok | Should -BeTrue
            $file.mode | Should -Be 'file'
            @($file.entries).Count | Should -Be 1
            $file.entries[0].domain | Should -Be 'services'

            $file2 = Get-RollbackPlan -BackupDir $tmp -File (Split-Path -Leaf $pw)
            $file2.ok | Should -BeTrue
            $file2.entries[0].domain | Should -Be 'power'

            $missing = Get-RollbackPlan -BackupDir $tmp -File 'services_backup_19990101_000000.csv'
            $missing.ok | Should -BeFalse
            $missing.error | Should -Match '不存在'
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Invoke-Rollback -DryRun previews without writing anything' {
        $tmp = Join-Path $env:TEMP ('rb5_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            $null = New-FakeBackup -Dir $tmp -Domain 'services' -Stamp '20260101_000000'
            $null = New-FakeBackup -Dir $tmp -Domain 'power'    -Stamp '20260201_000000'
            $before = @(Get-ChildItem $tmp -File | Sort-Object Name | ForEach-Object { $_.Name })

            $r = Invoke-Rollback -BackupDir $tmp -DryRun
            $r.dryRun | Should -BeTrue
            $r.ok | Should -BeTrue
            @($r.results).Count | Should -Be 2
            @($r.safetyBackups).Count | Should -Be 0
            @($r.results | Where-Object { $_.ok }).Count | Should -Be 2
            foreach ($s in @($r.results)) {
                $s.summary | Should -Match '恢复'
                $s.safetyBackup | Should -BeNullOrEmpty
            }

            $after = @(Get-ChildItem $tmp -File | Sort-Object Name | ForEach-Object { $_.Name })
            ($after -join ',') | Should -Be ($before -join ',')
            # 预演必须连「当前状态备份」都不写
            Mock Backup-DomainState { return 'SHOULD_NOT_HAPPEN' }
            Assert-MockCalled -CommandName 'Backup-DomainState' -Times 0
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Invoke-Rollback restores in the fixed domain order and backs up current state first' {
        $tmp = Join-Path $env:TEMP ('rb6_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            $doms = @('services','startup','visual','power','network','telemetry','update')
            $i = 0
            foreach ($dom in $doms) {
                $i++
                $null = New-FakeBackup -Dir $tmp -Domain $dom -Stamp ("2026010${i}_000000")
            }

            # 七个域的还原函数全部 mock 掉，只验证编排（顺序 / 传参 / 安全备份）
            Mock Restore-Services        { @{restored = 1; details = @('svc'); error = $null} }
            Mock Restore-StartupItems    { @{restored = 1; details = @('st');  error = $null} }
            Mock Restore-VisualEffects   { @{restored = 1; details = @('vis'); error = $null} }
            Mock Restore-PowerPlan       { @{restored = 1; details = @('pwr'); error = $null} }
            Mock Restore-NetworkSettings { @{restored = 1; details = @('net'); error = $null} }
            Mock Restore-TelemetryTasks  { @{restored = 1; details = @('tel'); error = $null} }
            Mock Restore-UpdateBackup    { @{ok = $true; details = @('upd'); error = $null} }
            Mock Backup-DomainState      { return (Join-Path $env:TEMP ('safety_' + (New-Guid).ToString('N') + '.json')) }

            $r = Invoke-Rollback -BackupDir $tmp
            $r.ok | Should -BeTrue
            $r.mode | Should -Be 'point'
            @($r.results | ForEach-Object { $_.domain }) | Should -Be @('services','startup','visual','power','network','telemetry','update')
            # 每个域还原前都先备份当前状态（回滚本身也要可回滚）
            @($r.safetyBackups).Count | Should -Be 7
            Assert-MockCalled -CommandName 'Backup-DomainState' -Times 7
            Assert-MockCalled -CommandName 'Restore-Services'     -Times 1 -ParameterFilter { $File -like '*services_backup_*' }
            Assert-MockCalled -CommandName 'Restore-UpdateBackup' -Times 1 -ParameterFilter { $File -like '*update_backup_*' }
            Assert-MockCalled -CommandName 'Restore-PowerPlan'    -Times 1 -ParameterFilter { $File -like '*power_backup_*.json' }
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Invoke-Rollback restores a single selected backup through -File' {
        $tmp = Join-Path $env:TEMP ('rb11_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            $null = New-FakeBackup -Dir $tmp -Domain 'services' -Stamp '20260101_000000'
            $null = New-FakeBackup -Dir $tmp -Domain 'power'    -Stamp '20260201_000000'
            Mock Restore-PowerPlan { @{restored = 1; details = @('pwr'); error = $null} }
            Mock Backup-DomainState { return (Join-Path $env:TEMP ('safety_' + (New-Guid).ToString('N') + '.json')) }

            $r = Invoke-Rollback -BackupDir $tmp -File (Join-Path $tmp 'power_backup_20260201_000000.json')
            $r.ok | Should -BeTrue
            $r.mode | Should -Be 'file'
            @($r.results).Count | Should -Be 1
            $r.results[0].domain | Should -Be 'power'
            Assert-MockCalled -CommandName 'Restore-PowerPlan' -Times 1
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Invoke-Rollback skips domains without a restore implementation and reports them' {
        $tmp = Join-Path $env:TEMP ('rb7_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            $h = Join-Path $tmp 'health_20260101_000000.json'
            Set-Content -LiteralPath $h -Value '{}' -Encoding UTF8
            $null = New-FakeBackup -Dir $tmp -Domain 'services' -Stamp '20260101_000000'
            Mock Restore-Services   { @{restored = 1; details = @(); error = $null} }
            Mock Backup-DomainState { $null }

            $r = Invoke-Rollback -BackupDir $tmp -DryRun
            @($r.skipped | Where-Object { $_.domain -eq 'health' }).Count | Should -Be 1
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Invoke-Rollback surfaces a structured error when a domain fails to restore' {
        $tmp = Join-Path $env:TEMP ('rb8_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            $null = New-FakeBackup -Dir $tmp -Domain 'services' -Stamp '20260101_000000'
            Mock Restore-Services   { @{restored = 0; details = @(); error = 'mocked failure'} }
            Mock Backup-DomainState { $null }

            $r = Invoke-Rollback -BackupDir $tmp
            $r.ok | Should -BeFalse
            $r.error | Should -Not -BeNullOrEmpty
            @($r.results | Where-Object { -not $_.ok }).Count | Should -Be 1
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Invoke-Rollback refuses to restore when the safety backup fails unless -Force' {
        $tmp = Join-Path $env:TEMP ('rb9_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            $null = New-FakeBackup -Dir $tmp -Domain 'services' -Stamp '20260101_000000'
            Mock Backup-DomainState { $null }
            Mock Restore-Services   { @{restored = 1; details = @(); error = $null} }

            $r = Invoke-Rollback -BackupDir $tmp
            $r.ok | Should -BeFalse
            @($r.results).Count | Should -Be 1
            $r.results[0].error | Should -Match '无法备份当前状态'
            Assert-MockCalled -CommandName 'Restore-Services' -Times 0

            $null = Invoke-Rollback -BackupDir $tmp -Force
            Assert-MockCalled -CommandName 'Restore-Services' -Times 1
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Invoke-Rollback returns a clean error when there is no backup at all' {
        $tmp = Join-Path $env:TEMP ('rb10_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            $r = Invoke-Rollback -BackupDir $tmp
            $r.ok | Should -BeFalse
            $r.error | Should -Not -BeNullOrEmpty
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Optimize.Core per-domain restore helpers (shared by CLI/GUI/WebUI)' {
    BeforeAll {
        . (Join-Path $PWD.Path 'lib\Optimize.Core.ps1')
    }

    It 'Restore-Services honours -File instead of picking the newest backup' {
        $tmp = Join-Path $env:TEMP ('rs_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            $f = Join-Path $tmp 'services_backup_20260101_000000.csv'
            Set-Content -LiteralPath $f -Value "Name,StartType,Date`r`nDiagTrack,Automatic,2026-01-01 00:00:00" -Encoding UTF8
            Mock Set-Service {}
            $r = Restore-Services -BackupDir $tmp -File $f
            $r.restored | Should -Be 1
            # GitHub Actions runner 的 $env:TEMP 是 8.3 短路径（如 RUNNER~1），
            # 而 Get-Item 解析后返回的是长路径（runneradmin）；归一化后再比较，
            # 避免同一文件的短/长两种路径形态造成误报
            [IO.Path]::GetFullPath([string]$r.backup) | Should -Be ([IO.Path]::GetFullPath($f))
            $r.error    | Should -BeNullOrEmpty
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Restore-StartupItems recreates a missing registry value and counts failures' {
        $tmp = Join-Path $env:TEMP ('rs2_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            $f = Join-Path $tmp 'startup_backup_20260101_000000.csv'
            Set-Content -LiteralPath $f -Value 'Name,Value,Scope,Source,Path' -Encoding UTF8
            Add-Content -LiteralPath $f -Value 'FakeEntry,C:\fake.exe,当前用户,注册表,HKCU:\Software\Fake\Run' -Encoding UTF8
            Mock Get-ItemProperty  { $null }
            Mock New-Item          {}
            Mock New-ItemProperty  {}
            $r = Restore-StartupItems -BackupDir $tmp -File $f
            $r.error    | Should -BeNullOrEmpty
            $r.restored | Should -Be 1
            $r.details[0].name   | Should -Be 'FakeEntry'
            $r.details[0].result | Should -Be '已恢复'
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Restore-StartupItems restores registry rows even when Source reads as mojibake' {
        $tmp = Join-Path $env:TEMP ('rs2b_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            $f = Join-Path $tmp 'startup_backup_20260101_010101.csv'
            # 旧工具 / 非 UTF8 CSV 会把 Source 列读成乱码，此时仍应按路径形态识别为注册表条目
            Set-Content -LiteralPath $f -Value 'Name,Value,Scope,Source,Path' -Encoding UTF8
            Add-Content -LiteralPath $f -Value 'FakeEntry,C:\fake.exe,当前用户,Âå¨®Â¥Â¬,HKCU:\Software\Fake\Run' -Encoding UTF8
            Mock Get-ItemProperty  { $null }
            Mock New-Item          {}
            Mock New-ItemProperty  {}
            $r = Restore-StartupItems -BackupDir $tmp -File $f
            $r.error    | Should -BeNullOrEmpty
            $r.restored | Should -Be 1
            $r.details[0].result | Should -Be '已恢复'
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Restore-StartupItems reports a clean error when no backup exists' {
        $tmp = Join-Path $env:TEMP ('rs3_' + (New-Guid).ToString('N'))
        try {
            $r = Restore-StartupItems -BackupDir $tmp
            $r.error | Should -Match '未找到'
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Restore-VisualEffects writes every backed-up registry value back' {
        $tmp = Join-Path $env:TEMP ('rs4_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            $f = Join-Path $tmp 'visual_backup_20260101_000000.json'
            @{
                VisualEffects = @{ VisualFXSetting = 3 }
                DWM           = @{ EnableAeroPeek  = 0 }
                Advanced      = @{ TaskbarAnimations = 0 }
                Desktop       = @{ DragFullWindows = '0'; MenuShowDelay = '0' }
            } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $f -Encoding UTF8

            Mock Test-Path         { $true }
            Mock Get-ItemProperty  { $null }
            Mock New-Item          {}
            Mock New-ItemProperty  {}
            Mock Set-ItemProperty  {}

            $r = Restore-VisualEffects -BackupDir $tmp -File $f
            $r.error    | Should -BeNullOrEmpty
            $r.restored | Should -Be 5
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Restore-PowerPlan switches back to the backed-up plan GUID' {
        $tmp = Join-Path $env:TEMP ('rs5_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            $f = Join-Path $tmp 'power_backup_20260101_000000.json'
            @{ activeGuid = '381b4222-f694-41f0-9685-ff5bb260df2e'; activeName = '已平衡' } |
                ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $f -Encoding UTF8

            Mock Invoke-PowerCfg { '' }
            Mock Get-ActivePowerPlan { '381b4222-f694-41f0-9685-ff5bb260df2e' }
            $r = Restore-PowerPlan -BackupDir $tmp -File $f
            $r.error    | Should -BeNullOrEmpty
            $r.restored | Should -Be 1
            Assert-MockCalled -CommandName 'Invoke-PowerCfg' -Times 1 `
                -ParameterFilter { $CfgArgs -contains '/setactive' -and $CfgArgs -contains '381b4222-f694-41f0-9685-ff5bb260df2e' }
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Restore-PowerPlan explains legacy txt backups instead of guessing' {
        $tmp = Join-Path $env:TEMP ('rs6_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            $f = Join-Path $tmp 'power_backup_20200101_000000.txt'
            Set-Content -LiteralPath $f -Value 'powercfg /query' -Encoding UTF8
            Mock Invoke-PowerCfg { '' }
            $r = Restore-PowerPlan -BackupDir $tmp -File $f
            $r.error    | Should -BeNullOrEmpty
            $r.restored | Should -Be 0
            (@($r.details) -join '') | Should -Match '旧格式备份'
            Assert-MockCalled -CommandName 'Invoke-PowerCfg' -Times 0
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Restore-NetworkSettings restores DNS through Set-AdapterDns and handles DHCP' {
        $tmp = Join-Path $env:TEMP ('rs7_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            $f = Join-Path $tmp 'network_backup_20260101_000000.json'
            @{
                Date = '2026-01-01 00:00:00'
                Adapters = @(
                    @{ InterfaceAlias = '以太网'; InterfaceIndex = 12; DnsServers = @('1.1.1.1','1.0.0.1') }
                    @{ InterfaceAlias = 'WLAN';   InterfaceIndex = 7;  DnsServers = @() }
                )
            } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $f -Encoding UTF8

            Mock Set-AdapterDns { [PSCustomObject]@{ ok = $true; applied = 'mocked' } }
            Mock Set-DnsClientServerAddress {}
            Mock netsh {}

            $r = Restore-NetworkSettings -BackupDir $tmp -File $f
            $r.error    | Should -BeNullOrEmpty
            $r.restored | Should -Be 2
            Assert-MockCalled -CommandName 'Set-AdapterDns' -Times 1 `
                -ParameterFilter { $DnsServers.Count -eq 2 -and $DnsServers[0] -eq '1.1.1.1' }
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Restore-UpdateBackup imports the reg backup and then restores auto update' {
        $tmp = Join-Path $env:TEMP ('rs8_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            $f = Join-Path $tmp 'winupdate_block_20260101_000000.reg'
            Set-Content -LiteralPath $f -Value 'Windows Registry Editor Version 5.00' -Encoding UTF8
            Mock reg {}
            Mock Restore-AutoUpdate { @{ok = $true; details = @('wuauserv 已是自动'); error = $null} }
            $r = Restore-UpdateBackup -File $f
            $r.ok | Should -BeTrue
            (@($r.details) -join ' ') | Should -Match '已导入注册表备份'
            Assert-MockCalled -CommandName 'Restore-AutoUpdate' -Times 1
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Restore-DomainState dispatches every supported domain to its restore helper' {
        Mock Restore-Services         { @{restored = 1; details = @(); error = $null} }
        Mock Restore-StartupItems     { @{restored = 2; details = @(); error = $null} }
        Mock Restore-VisualEffects    { @{restored = 3; details = @(); error = $null} }
        Mock Restore-PowerPlan        { @{restored = 4; details = @(); error = $null} }
        Mock Restore-NetworkSettings  { @{restored = 5; details = @(); error = $null} }
        Mock Restore-TelemetryTasks   { @{restored = 6; details = @(); error = $null} }
        Mock Restore-UpdateBackup     { @{ok = $true; restored = 7; details = @(); error = $null} }

        $map = @{
            'services'  = 'Restore-Services'
            'startup'   = 'Restore-StartupItems'
            'visual'    = 'Restore-VisualEffects'
            'power'     = 'Restore-PowerPlan'
            'network'   = 'Restore-NetworkSettings'
            'telemetry' = 'Restore-TelemetryTasks'
            'update'    = 'Restore-UpdateBackup'
        }
        foreach ($dom in $map.Keys) {
            $r = Restore-DomainState -Domain $dom -File "D:\fake\$dom.dat" -BackupDir 'D:\fake'
            $r | Should -Not -BeNullOrEmpty
            Assert-MockCalled -CommandName $map[$dom] -Times 1 -Scope It
        }
    }

    It 'Restore-DomainState returns null for domains that cannot be rolled back' {
        (Restore-DomainState -Domain 'health')  | Should -BeNullOrEmpty
        (Restore-DomainState -Domain 'unknown') | Should -BeNullOrEmpty
        (Restore-DomainState -Domain '')        | Should -BeNullOrEmpty
    }
}

Describe 'Optimize.Core profiles - optimization bundles (shared by CLI/GUI/WebUI)' {
    BeforeAll {
        . (Join-Path $PWD.Path 'lib\Optimize.Core.ps1')
    }

    It 'Get-ProfileDefaults exposes every field a profile may specify' {
        $d = Get-ProfileDefaults
        foreach ($k in @('services','startup','visual','power','dns','telemetry','disk','compact_os')) {
            $d.PSObject.Properties.Name | Should -Contain $k
        }
    }

    It 'Get-BuiltinProfiles returns the 4 built-in bundles as a fallback' {
        $b = Get-BuiltinProfiles
        @($b.Keys).Count | Should -Be 4
        foreach ($k in @('old_balanced','gaming','quiet_saver','minimal')) {
            $b.Contains($k) | Should -BeTrue
        }
    }

    It 'Get-Profiles returns config profiles with every spec field filled' {
        $ps = @(Get-Profiles)
        $ps.Count | Should -BeGreaterThan 0
        foreach ($p in $ps) {
            $p.name      | Should -Not -BeNullOrEmpty
            $p.title     | Should -Not -BeNullOrEmpty
            $p.desc      | Should -Not -BeNullOrEmpty
            $p.services  | Should -Not -BeNullOrEmpty
            $p.startup   | Should -Not -BeNullOrEmpty
            $p.visual    | Should -Not -BeNullOrEmpty
            $p.power     | Should -Not -BeNullOrEmpty
            $p.dns       | Should -Not -BeNullOrEmpty
            $p.disk      | Should -Not -BeNullOrEmpty
            $p.telemetry | Should -BeOfType [bool]
            $p.compactOs | Should -BeOfType [bool]
        }
    }

    It 'Get-Profile looks up by name and by title, and returns null when unknown' {
        $all = @(Get-Profiles)
        $first = $all[0]
        (Get-Profile -Name $first.name).name   | Should -Be $first.name
        (Get-Profile -Name $first.title).name  | Should -Be $first.name
        (Get-Profile -Name 'no_such_profile')  | Should -BeNullOrEmpty
    }

    It 'Get-ProfileSteps derives risk and auto from the profile spec' {
        $safe = Get-ProfileSteps -Profile ([PSCustomObject]@{
            name='t'; title='t'; desc='t'; services='safe'; startup='list'
            visual='best_performance'; power='high'; dns='cloudflare'; telemetry=$true
            disk='none'; compactOs=$false })
        $svc = @($safe | Where-Object { $_.id -eq 'services' })[0]
        $svc.risk | Should -Be 'low'
        $svc.auto | Should -BeTrue

        $agg = Get-ProfileSteps -Profile ([PSCustomObject]@{
            name='t'; title='t'; desc='t'; services='recommended'; startup='all'
            visual='keep'; power='keep'; dns='none'; telemetry=$false
            disk='none'; compactOs=$false })
        $svc2 = @($agg | Where-Object { $_.id -eq 'services' })[0]
        $svc2.risk | Should -Be 'medium'
        $st = @($agg | Where-Object { $_.id -eq 'startup' })[0]
        $st.risk | Should -Be 'high'
        $st.auto | Should -BeFalse
        # startup=list 是只读步骤，必须 auto 且零风险
        $list = @($safe | Where-Object { $_.id -eq 'startup' })[0]
        $list.auto   | Should -BeTrue
        $list.risk   | Should -Be 'none'
        $list.params.ListOnly | Should -BeTrue
    }

    It 'Get-ProfileSteps maps power aliases to real GUIDs and drops keep/none' {
        $mk = { param($power,$visual,$dns,$disk,$compactOs)
            Get-ProfileSteps -Profile ([PSCustomObject]@{
                name='t'; title='t'; desc='t'; services='none'; startup='none'
                visual=$visual; power=$power; dns=$dns; telemetry=$false
                disk=$disk; compactOs=$compactOs }) }
        $high  = @(& $mk 'high'      'keep' 'none' 'none' $false | Where-Object { $_.id -eq 'power' })[0]
        $ult   = @(& $mk 'ultimate'  'keep' 'none' 'none' $false | Where-Object { $_.id -eq 'power' })[0]
        $sv    = @(& $mk 'power_saver' 'keep' 'none' 'none' $false | Where-Object { $_.id -eq 'power' })[0]
        $high.params.Guid | Should -Be '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
        $ult.params.Guid  | Should -Be 'e9a42b02-d5df-448d-aa00-03f14749eb61'
        $ult.params.UnlockUltimate | Should -BeTrue
        $sv.params.Guid   | Should -Be 'a1841308-3541-4fab-bc81-f71556f20b4a'
        $raw  = @(& $mk 'e9a42b02-d5df-448d-aa00-03f14749eb61' 'keep' 'none' 'none' $false | Where-Object { $_.id -eq 'power' })[0]
        $raw.params.Guid  | Should -Be 'e9a42b02-d5df-448d-aa00-03f14749eb61'
        # keep / none / 未知别名都不该产生步骤
        @(& $mk 'keep' 'keep' 'none' 'none' $false).Count | Should -Be 0
        @(& $mk 'bogus' 'keep' 'none' 'none' $false).Count | Should -Be 0
        @(& $mk 'keep' 'best_performance' 'none' 'none' $false | Where-Object { $_.id -eq 'visual' }).Count | Should -Be 1
    }

    It 'Get-ProfilePlan returns a read-only plan and errors on an unknown bundle' {
        $name = @(Get-Profiles)[0].name
        $p = Get-ProfilePlan -Name $name
        $p.ok    | Should -BeTrue
        $p.name  | Should -Be $name
        @($p.steps).Count | Should -BeGreaterThan 0
        $p.error | Should -BeNullOrEmpty

        $bad = Get-ProfilePlan -Name 'no_such_bundle'
        $bad.ok    | Should -BeFalse
        $bad.error | Should -Match '未找到组合包'
    }

    It 'Invoke-Profile -WhatIf is side-effect free and reports dryRun' {
        $name = @(Get-Profiles | Where-Object { $_.services -eq 'safe' })[0].name
        $tmp = Join-Path $env:TEMP ('prof_wi_' + (New-Guid).ToString('N'))
        # CI runner 无活动网卡（真实 Invoke-NetworkOptimization 会返回 ok=$false）；
        # 注入一个伪网卡，让 -WhatIf 网络分支真实跑完（各子项 -WhatIf 均返回 ok=$true）
        Mock Get-ActiveNetAdapters {
            @([PSCustomObject]@{ Name = 'Ethernet'; IfIndex = 1; Description = 'unit-test'; MacAddress = '00-00-00-00-00-00'; LinkSpeed = '1 Gbps' })
        }
        try {
            $r = Invoke-Profile -Name $name -BackupDir $tmp -WhatIf
            $r.ok     | Should -BeTrue
            $r.dryRun | Should -BeTrue
            $r.forced | Should -BeFalse
            # 预演不得落盘任何备份
            Test-Path $tmp | Should -BeFalse
            @($r.results).Count | Should -BeGreaterThan 0
            foreach ($s in $r.results) { $s.ok | Should -BeTrue }
            foreach ($s in $r.results) { $s.backup | Should -BeNullOrEmpty }
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Invoke-Profile skips high-risk and manual steps unless -Force is given' {
        $tmp = Join-Path $env:TEMP ('prof_g_' + (New-Guid).ToString('N'))
        # CI runner 无活动网卡（真实 Invoke-NetworkOptimization 会返回 ok=$false）；
        # 注入一个伪网卡，让 -WhatIf 网络分支真实跑完（各子项 -WhatIf 均返回 ok=$true）
        Mock Get-ActiveNetAdapters {
            @([PSCustomObject]@{ Name = 'Ethernet'; IfIndex = 1; Description = 'unit-test'; MacAddress = '00-00-00-00-00-00'; LinkSpeed = '1 Gbps' })
        }
        try {
            $r = Invoke-Profile -Name 'gaming' -BackupDir $tmp -WhatIf
            $r.ok     | Should -BeTrue
            $r.dryRun | Should -BeTrue
            $r.forced | Should -BeFalse
            $skipIds = @($r.skipped | ForEach-Object { $_.id })
            $skipIds | Should -Contain 'startup'
            $ran = @($r.results | ForEach-Object { $_.id })
            $ran | Should -Not -Contain 'startup'
            # -Force 放行后该步骤必须进入 results，且 skipped 清空
            $f = Invoke-Profile -Name 'gaming' -BackupDir $tmp -WhatIf -Force
            $f.forced | Should -BeTrue
            @($f.skipped).Count | Should -Be 0
            @($f.results | ForEach-Object { $_.id }) | Should -Contain 'startup'
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Invoke-Profile rejects an unknown bundle without touching the system' {
        $tmp = Join-Path $env:TEMP ('prof_bad_' + (New-Guid).ToString('N'))
        try {
            $r = Invoke-Profile -Name 'no_such_bundle' -BackupDir $tmp
            $r.ok     | Should -BeFalse
            $r.error  | Should -Match '未找到组合包'
            @($r.results).Count | Should -Be 0
            Test-Path $tmp | Should -BeFalse
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Invoke-Profile executes a low-risk bundle end to end with mocked helpers' {
        Mock Disable-Services        { @{ disabled = 3; skipped = 0 } }
        Mock Set-VisualEffectProfile { @{ ok = $true; details = @('已应用'); backup = $null } }
        Mock Set-PowerPlan           { @{ ok = $true; details = @('已切换'); backup = $null; fallback = $false } }
        Mock Disable-TelemetryTasks  { @{ disabled = 2; skipped = 0; details = @(); backup = $null } }
        Mock Get-StartupItems        { @() }
        Mock Invoke-NetworkOptimization { @{ ok = $true; error = $null; backup = $null; details = @('模拟网络优化'); adapters = 1 } }

        $tmp = Join-Path $env:TEMP ('prof_run_' + (New-Guid).ToString('N'))
        try {
            $r = Invoke-Profile -Name 'old_balanced' -BackupDir $tmp
            $r.dryRun | Should -BeFalse
            $r.ok     | Should -BeTrue
            $r.error  | Should -BeNullOrEmpty
            @($r.results).Count | Should -BeGreaterThan 0
            foreach ($s in $r.results) { $s.ok | Should -BeTrue }
            Assert-MockCalled -CommandName 'Disable-Services'       -Times 1 -Scope It
            Assert-MockCalled -CommandName 'Set-VisualEffectProfile' -Times 1 -Scope It
            Assert-MockCalled -CommandName 'Set-PowerPlan'          -Times 1 -Scope It
            Assert-MockCalled -CommandName 'Disable-TelemetryTasks' -Times 1 -Scope It
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
Describe 'Optimize.Core health trend, sparkline and schedule (shared by CLI/GUI/WebUI)' {
    BeforeAll {
        . (Join-Path $PWD.Path 'lib\Optimize.Core.ps1')
    }

    It 'Format-Sparkline maps values onto a fixed ASCII ramp' {
        Format-Sparkline -Values @(0.0, 50.0, 100.0) | Should -Be '.=%'
        Format-Sparkline -Values @()                  | Should -Be ''
        # 恒定序列输出平线（不除零）
        (Format-Sparkline -Values @(5.0, 5.0, 5.0)) | Should -Be '+++'
        # 越界值被夹紧到端点
        Format-Sparkline -Values @(-10.0, 500.0) | Should -Be '.%'
    }

    It 'Get-HealthTrend returns an ordered series from history JSON' {
        $tmp = Join-Path $env:TEMP ('trend_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path (Join-Path $tmp 'health') -Force | Out-Null
            $mk = {
                param($Day, $Score, $Free, $MB, $Startups)
                $when = (Get-Date).AddDays(-$Day)
                $name = $when.ToString('yyyyMMdd_HHmmss')
                $o = [PSCustomObject]@{
                    timestamp = $when.ToString('yyyy-MM-dd HH:mm:ss')
                    host      = 'h'; version = '3.3.0'; score = $Score; grade = 'x'
                    metrics   = [PSCustomObject]@{ freeRamPct = $Free; cleanableMB = $MB; startupCount = $Startups }
                    issues    = @()
                }
                $f = Join-Path $tmp "health\health_$name.json"
                $o | ConvertTo-Json -Depth 8 | Out-File -FilePath $f -Encoding UTF8
                (Get-Item $f).LastWriteTime = $when
            }
            & $mk 2 61 42.5 1200 18
            & $mk 1 72 55.0  900 12
            & $mk 0 80 60.0  300  9

            $t = @(Get-HealthTrend -BackupDir $tmp -Days 30)
            $t.Count | Should -Be 3
            $t[0].score | Should -Be 61
            $t[-1].score | Should -Be 80
            $t[1].freeRamPct   | Should -Be 55.0
            $t[1].cleanableMB  | Should -Be 900
            $t[1].startupCount | Should -Be 12
            $t[1].issueCount   | Should -Be 0
            # 时间升序
            ($t[1].time -gt $t[0].time) | Should -BeTrue
            ($t[2].time -gt $t[1].time) | Should -BeTrue

            # -Days 过滤：只看近 1 天应剩 1 点
            @(Get-HealthTrend -BackupDir $tmp -Days 1).Count | Should -Be 1
            # -MaxPoints 抽样：5 点取 2 应得 3 点（0/2/4 索引）且末点为最新
            & $mk 3 55 30.0 2000 20
            $s = @(Get-HealthTrend -BackupDir $tmp -Days 30 -MaxPoints 2)
            $s.Count    | Should -Be 3
            $s[-1].score | Should -Be 80
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Get-HealthTrend returns empty when no history exists' {
        $tmp = Join-Path $env:TEMP ('trend_empty_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            @(Get-HealthTrend -BackupDir $tmp).Count | Should -Be 0
            @(Get-HealthTrend -BackupDir (Join-Path $tmp 'no_such_subdir')).Count | Should -Be 0
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Install-HealthSchedule validates time and script path without touching schtasks' {
        $badTime = Install-HealthSchedule -Time 'abc' -HealthScript "$PWD\lib\Optimize.Core.ps1"
        $badTime.ok    | Should -BeFalse
        $badTime.error | Should -Match 'HH:mm'
        $badTime.trigger | Should -BeNullOrEmpty

        $badScript = Install-HealthSchedule -Time '09:00' -HealthScript "$PWD\no_such_health_script.ps1"
        $badScript.ok    | Should -BeFalse
        $badScript.error | Should -Match '未找到体检脚本'

        # 时间格式校验通过后才会命中 schtasks（此处不再测试真实注册）
        '09:00' -match '^([01]?[0-9]|2[0-3]):[0-5][0-9]$' | Should -BeTrue
        '9:5'   -match '^([01]?[0-9]|2[0-3]):[0-5][0-9]$' | Should -BeFalse
        '24:00' -match '^([01]?[0-9]|2[0-3]):[0-5][0-9]$' | Should -BeFalse
    }

    It 'Test-IsAdmin returns a boolean' {
        Test-IsAdmin | Should -BeOfType [bool]
    }
}

Describe 'Optimize.Core health report export - self-contained Html/Markdown (P1-2)' {
    BeforeAll {
        . (Join-Path $PWD.Path 'lib\Optimize.Core.ps1')
    }

    It 'Export-HealthReport writes a self-contained HTML comparison file' {
        $tmp = Join-Path $env:TEMP ('export_' + (New-Guid).ToString('N'))
        try {
            $before = [PSCustomObject]@{
                timestamp = '2026-09-20 09:00:00'; host = 'h'; version = '3.4.0'
                score = 61; grade = 'C'
                metrics = [PSCustomObject]@{ freeRamPct = 42.5; cleanableMB = 1200; startupCount = 18 }
                issues  = @(
                    [PSCustomObject]@{ id = 'temp_bloat';     severity = 'High';   title = 'temp_bloat_title';     detail = 'd1' }
                    [PSCustomObject]@{ id = 'startup_bloat';  severity = 'Medium'; title = 'startup_bloat_title';  detail = 'd2' }
                )
            }
            $after = [PSCustomObject]@{
                timestamp = '2026-09-25 09:00:00'; host = 'h'; version = '3.5.0'
                score = 88; grade = 'B'
                metrics = [PSCustomObject]@{ freeRamPct = 61.0; cleanableMB = 300; startupCount = 9 }
                issues  = @(
                    [PSCustomObject]@{ id = 'startup_bloat';  severity = 'Medium'; title = 'startup_bloat_title';  detail = 'd2' }
                    [PSCustomObject]@{ id = 'pagefile_small'; severity = 'Low';    title = 'pagefile_small_title'; detail = 'd3' }
                )
            }

            $r = Export-HealthReport -From $before -To $after -Format Html -OutDir $tmp -FileName 'cmp.html'
            $r.ok            | Should -BeTrue
            $r.error         | Should -BeNullOrEmpty
            $r.format        | Should -Be 'Html'
            $r.comparison.beforeScore | Should -Be 61
            $r.comparison.afterScore  | Should -Be 88
            $r.comparison.scoreDelta  | Should -Be 27
            Test-Path -LiteralPath $r.file | Should -BeTrue

            $html = Get-Content -LiteralPath $r.file -Raw -Encoding UTF8
            # 自包含单文件：样式全内联、零外部请求
            $html | Should -Match '<style>'
            $html | Should -Not -Match 'https?://'
            # 总分与分差直接渲染进 HTML
            $html | Should -Match '>61<'
            $html | Should -Match '>88<'
            $html | Should -Match '\+27'
            # 指标明细 + 已解决/新增 issue 内容
            $html | Should -Match 'freeRamPct'
            $html | Should -Match 'temp_bloat_title'
            $html | Should -Match 'pagefile_small_title'
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Export-HealthReport writes a Markdown table-based report' {
        $tmp = Join-Path $env:TEMP ('export_' + (New-Guid).ToString('N'))
        try {
            $before = [PSCustomObject]@{
                timestamp = '2026-09-20 09:00:00'; score = 61
                metrics = [PSCustomObject]@{ freeRamPct = 42.5 }
                issues  = @([PSCustomObject]@{ id = 'temp_bloat'; severity = 'High'; title = 'temp_bloat_title'; detail = 'd1' })
            }
            $after = [PSCustomObject]@{
                timestamp = '2026-09-25 09:00:00'; score = 88
                metrics = [PSCustomObject]@{ freeRamPct = 61.0 }
                issues  = @([PSCustomObject]@{ id = 'pagefile_small'; severity = 'Low'; title = 'pagefile_small_title'; detail = 'd3' })
            }

            $r = Export-HealthReport -From $before -To $after -Format Markdown -OutDir $tmp -FileName 'cmp.md'
            $r.ok     | Should -BeTrue
            $r.format | Should -Be 'Markdown'
            Test-Path -LiteralPath $r.file | Should -BeTrue

            $md = Get-Content -LiteralPath $r.file -Raw -Encoding UTF8
            $md | Should -Match '\| freeRamPct \|'
            $md | Should -Match '\| 42.5 \| 61 \| \+18.5 \|'
            $md | Should -Match 'temp_bloat_title'
            $md | Should -Match 'pagefile_small_title'
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Export-HealthReport accepts health JSON file paths as From/To' {
        $tmp = Join-Path $env:TEMP ('export_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path (Join-Path $tmp 'health') -Force | Out-Null
            $mk = {
                param($Name, $Score)
                $o = [PSCustomObject]@{
                    timestamp = '2026-09-2' + $Name + ' 09:00:00'; host = 'h'; version = '3.4.0'
                    score = $Score; grade = 'x'
                    metrics = [PSCustomObject]@{ freeRamPct = 42.5; cleanableMB = 1200; startupCount = 18 }
                    issues  = @()
                }
                $o | ConvertTo-Json -Depth 8 | Out-File -FilePath (Join-Path $tmp "health\health_$Name.json") -Encoding UTF8
            }
            & $mk '0' 61
            & $mk '5' 88

            $r = Export-HealthReport -From (Join-Path $tmp 'health\health_0.json') -To (Join-Path $tmp 'health\health_5.json') -OutDir $tmp -FileName 'json.html'
            $r.ok | Should -BeTrue
            $r.comparison.scoreDelta | Should -Be 27
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Export-HealthReport falls back to the two newest history reports when From/To are omitted' {
        $tmp = Join-Path $env:TEMP ('export_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path (Join-Path $tmp 'health') -Force | Out-Null
            $mk = {
                param($Name, $Score)
                $when = [datetime]::ParseExact($Name, 'yyyyMMdd_HHmmss', $null)
                $o = [PSCustomObject]@{
                    timestamp = $when.ToString('yyyy-MM-dd HH:mm:ss'); host = 'h'; version = '3.4.0'
                    score = $Score; grade = 'x'
                    metrics = [PSCustomObject]@{ freeRamPct = 42.5; cleanableMB = 1200; startupCount = 18 }
                    issues  = @()
                }
                $f = Join-Path $tmp "health\health_$Name.json"
                $o | ConvertTo-Json -Depth 8 | Out-File -FilePath $f -Encoding UTF8
                (Get-Item $f).LastWriteTime = $when
            }
            & $mk '20260920_090000' 61
            & $mk '20260925_090000' 88

            $r = Export-HealthReport -BackupDir $tmp -OutDir $tmp -FileName 'auto.html'
            $r.ok | Should -BeTrue
            $r.comparison.beforeScore | Should -Be 61
            $r.comparison.afterScore  | Should -Be 88
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Export-HealthReport fails cleanly when reports are missing' {
        $tmp = Join-Path $env:TEMP ('export_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null

            $r1 = Export-HealthReport -OutDir $tmp -FileName 'x.html'
            $r1.ok    | Should -BeFalse
            $r1.file  | Should -BeNullOrEmpty
            $r1.error | Should -Match 'From/To'

            $r2 = Export-HealthReport -From "$tmp\no_such.json" -OutDir $tmp -FileName 'x.html'
            $r2.ok | Should -BeFalse
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Export-HealthReport escapes markup in issue text' {
        $tmp = Join-Path $env:TEMP ('export_' + (New-Guid).ToString('N'))
        try {
            $before = [PSCustomObject]@{
                timestamp = '2026-09-20 09:00:00'; score = 61
                metrics = [PSCustomObject]@{ freeRamPct = 42.5 }
                issues  = @([PSCustomObject]@{ id = 'x'; severity = 'High'; title = '<script>alert(1)</script>'; detail = 'a & b' })
            }
            $after = [PSCustomObject]@{
                timestamp = '2026-09-25 09:00:00'; score = 88
                metrics = [PSCustomObject]@{ freeRamPct = 61.0 }
                issues  = @()
            }

            $r = Export-HealthReport -From $before -To $after -Format Html -OutDir $tmp -FileName 'esc.html'
            $html = Get-Content -LiteralPath $r.file -Raw -Encoding UTF8
            $html | Should -Not -Match '<script>alert'
            $html | Should -Match '&lt;script&gt;'
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Optimize.Core restore point before optimize (P1-3, shared by CLI/GUI/WebUI)' {
    BeforeAll {
        . (Join-Path $PWD.Path 'lib\Optimize.Core.ps1')
    }

    # 还原点占磁盘、且很多老机根本开着 System Restore，
    # 所以默认必须关闭，与 Safe-by-default 一致。
    It 'Get-RestorePointDefault returns a bool and is false by default' {
        $d = Get-RestorePointDefault
        $d | Should -BeOfType [bool]
        $d | Should -BeFalse
    }

    It 'config safety.create_restore_point exists and is false' {
        $cfg = Get-OptConfig
        $cfg.safety | Should -Not -BeNullOrEmpty
        $cfg.safety.create_restore_point | Should -BeFalse
    }

    It 'config schema allows the safety section' {
        $sp = Join-Path $PWD.Path 'config\optimization.schema.json'
        Test-Path $sp | Should -BeTrue
        { Get-Content -LiteralPath $sp -Raw -Encoding UTF8 | ConvertFrom-Json } | Should -Not -Throw
        $json = Get-Content -LiteralPath $sp -Raw -Encoding UTF8 | ConvertFrom-Json
        $json.properties.safety | Should -Not -BeNullOrEmpty
        $json.properties.safety.properties.create_restore_point.type | Should -Be 'boolean'
        # root 不开放其它字段，因此 safety 必须显式声明
        $json.additionalProperties | Should -BeFalse
    }

    It 'New-SystemRestorePoint -WhatIf only previews and reports its method' {
        $r = New-SystemRestorePoint -WhatIf
        $r.ok     | Should -BeTrue
        $r.whatIf | Should -BeTrue
        $r.method | Should -Be 'WhatIf'
        $r.name  | Should -Not -BeNullOrEmpty
    }

    It 'New-SystemRestorePoint never throws when restore point creation is unavailable' {
        # 非管理员 / SR 关闭 / 节流：全部应该返回对象而不是弹异常
        $e = $null
        try { $r = New-SystemRestorePoint -Description 'Pester smoke' } catch { $e = $_ }
        $e | Should -BeNullOrEmpty
        $r | Should -Not -BeNullOrEmpty
        $r.PSObject.Properties.Name | Should -Contain 'ok'
        $r.PSObject.Properties.Name | Should -Contain 'method'
        $r.PSObject.Properties.Name | Should -Contain 'error'
    }

    It 'Invoke-HealthRemediation exposes restorePoint and skips creation by default' {
        # 默认 false 时不应该真的去创建还原点（否则每次体检都会在 CI 里建还原点）
        $report = [PSCustomObject]@{
            timestamp = '2026-09-26 09:00:00'; host = 'h'; version = '3.5.0'
            score = 61; grade = 'C'
            metrics   = [PSCustomObject]@{ freeRamPct = 42.5; cleanableMB = 0; startupCount = 3 }
            issues    = @()
        }
        # 防歇层：即使以后改了配置默认，也不会在测试里真建还原点
        Mock New-SystemRestorePoint { [PSCustomObject]@{ ok = $true; whatIf = $true; method = 'Mock'; name = 'mocked'; error = $null; returnValue = $null } }
        $r = Invoke-HealthRemediation -Report $report -MaxSeverity 'Medium' -WhatIf -CreateRestorePoint:$false
        $r.PSObject.Properties.Name | Should -Contain 'restorePoint'
        # -WhatIf 下不创建
        if ($r.restorePoint) { $r.restorePoint.ok | Should -BeTrue; $r.restorePoint.method | Should -Be 'WhatIf' }
    }

    It 'Invoke-Profile exposes restorePoint in its result object' {
        Mock New-SystemRestorePoint { [PSCustomObject]@{ ok = $true; whatIf = $true; method = 'Mock'; name = 'mocked'; error = $null; returnValue = $null } }
        $plan = Get-ProfilePlan -Name ( @(Get-Profiles)[0].name )
        $r = Invoke-Profile -Name $plan.name -WhatIf -Force -CreateRestorePoint:$false
        $r.PSObject.Properties.Name | Should -Contain 'restorePoint'
        if ($r.restorePoint) { $r.restorePoint.ok | Should -BeTrue; $r.restorePoint.method | Should -Be 'WhatIf' }
    }

    # 三端默认值同源：GUI 复选框 / CLI 开关、WebUI 参数都必须回到 Get-RestorePointDefault
    It 'three ends share the same restore-point default (Get-RestorePointDefault)' {
        foreach ($rel in @('scripts\15-HealthCheck.ps1', 'scripts\16-Profiles.ps1', 'gui\pages\Health.ps1',
                           'webui\ps\15_health.ps1', 'webui\ps\16_profiles.ps1')) {
            $f = Join-Path $PWD.Path $rel
            Test-Path $f | Should -BeTrue
            (Get-Content $f -Raw -Encoding UTF8) | Should -Match 'Get-RestorePointDefault'
        }
    }

    It 'lib restore-point helpers exist and are pure PowerShell (no Storage module APIs)' {
        foreach ($fn in @('Get-RestorePointDefault', 'Test-SystemRestoreEnabled', 'New-SystemRestorePoint')) {
            (Get-Command $fn -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
        }
        # Win7 红线：不允许 Get-CimInstance / Get-Volume / Get-PhysicalDisk 等 Win8+ API
        $src = Get-Content (Join-Path $PWD.Path 'lib\Optimize.Core.ps1') -Raw -Encoding UTF8
        $i = $src.IndexOf('function New-SystemRestorePoint')
        $i | Should -BeGreaterThan 0
        $seg = $src.Substring($i, [Math]::Min(3000, $src.Length - $i))
        $seg | Should -Not -Match 'Get-CimInstance'
        $seg | Should -Not -Match 'Get-Volume'
        $seg | Should -Not -Match 'Get-PhysicalDisk'
    }
}

# ============================================================
#  源码卫生：字符串定限符与返回对象类型（防命令行中文转码回归）
#  背景：命令行中文经 GBK 往返时，ASCII 双引号有概率被写成中文弯引号，
#  PowerShell 并不把弯引号当字符串定界符——语法检查照样通过，直到运行
#  那一行才把整段当命令名报错（P1 期间真实踩过两次：体检趋势行、
#  Install-HealthSchedule 的 schtasks 失败分支）。
#  另一类 quieter 的坑是多行 [PSCustomObject]{ }：缺少 @ 会被解析成
#  「脚本块转型」，返回的是 ScriptBlock 而不是对象，属性全读不到。
# ============================================================
Describe 'PowerShell source hygiene - string delimiters and returned object types' {
    BeforeAll {
        $script:psFiles = @(
            Get-ChildItem -Path $PWD.Path -Filter *.ps1 -File
            Get-ChildItem -Path (Join-Path $PWD.Path 'lib')     -Filter *.ps1 -File -Recurse
            Get-ChildItem -Path (Join-Path $PWD.Path 'scripts') -Filter *.ps1 -File -Recurse
            Get-ChildItem -Path (Join-Path $PWD.Path 'gui')     -Filter *.ps1 -File -Recurse
            Get-ChildItem -Path (Join-Path $PWD.Path 'webui')   -Filter *.ps1 -File -Recurse
        ) | Where-Object { $_.FullName -notlike '*_scratch*' -and $_.FullName -notlike '*tests*' } | ForEach-Object { $_.FullName }
        # lib 供下方 Install-HealthSchedule 用例直接调用
        . (Join-Path $PWD.Path 'lib\Optimize.Core.ps1')
    }

    It 'collects the PowerShell sources to check' {
        @($script:psFiles).Count | Should -BeGreaterThan 10
    }

    It 'every PowerShell source parses without syntax errors' {
        foreach ($f in @($script:psFiles)) {
            $errs = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$errs)
            ("{0} -> {1} parse error(s)" -f (Split-Path -Leaf $f), @($errs).Count) | Should -Match ' 0 parse error'
        }
    }

    It 'no curly quotes are used as string delimiters' {
        # 赋值 / 参数 / 括号之后紧跟弯引号，说明弯引号被当成了定界符
        foreach ($f in @($script:psFiles)) {
            $text = Get-Content -LiteralPath $f -Raw -Encoding UTF8
            foreach ($line in ($text -split "`r?`n")) {
                if ($line -match '(=|\()\s*[\u201c\u2018]' -or $line -match '[\u201d\u2019]\s*(-f|\)|;|,|\}|\]|\|)') {
                    ("{0}: {1}" -f (Split-Path -Leaf $f), $line.Trim()) | Should -Match '___never_matches___'
                }
            }
        }
    }

    It 'no multi-line [PSCustomObject]{{ cast (it would return a ScriptBlock)' {
        foreach ($f in @($script:psFiles)) {
            $text = Get-Content -LiteralPath $f -Raw -Encoding UTF8
            $text | Should -Not -Match '\[PSCustomObject\]\{'
        }
    }

    It 'Install-HealthSchedule always returns a shaped object, never a ScriptBlock' {
        $badTime = Install-HealthSchedule -Time 'abc' -HealthScript (Join-Path $PWD.Path 'lib\Optimize.Core.ps1')
        $badTime | Should -BeOfType [System.Management.Automation.PSCustomObject]
        @($badTime.PSObject.Properties.Name) | Should -Contain 'ok'
        @($badTime.PSObject.Properties.Name) | Should -Contain 'error'
        @($badTime.PSObject.Properties.Name) | Should -Contain 'task'
        $badTime.ok | Should -BeFalse
        $badTime.error | Should -Match 'HH:mm'
    }
}

# ============================================================
#  P2 智能降级建议：启动项打分 / 清理目标排序 / 报告门控
# ============================================================
Describe 'Optimize.Core smart recommendations (P2, shared by CLI/GUI/WebUI)' {
    BeforeAll {
        . (Join-Path $PWD.Path 'lib\Optimize.Core.ps1')
    }

    It 'Get-StartupTargetPath handles quoted, argumented and env-var commands' {
        (Get-StartupTargetPath -Item ([PSCustomObject]@{ Name='a'; Value='"C:\Program Files\A B\app.exe" --flag' })) | Should -Be 'C:\Program Files\A B\app.exe'
        (Get-StartupTargetPath -Item ([PSCustomObject]@{ Name='a'; Value='C:\Windows\System32\notepad.exe foo' }))       | Should -Be 'C:\Windows\System32\notepad.exe'
        (Get-StartupTargetPath -Item ([PSCustomObject]@{ Name='a'; Value='%SystemRoot%\system32\wbem\wmiprvse.exe' }))     | Should -Match 'wbem\\wmiprvse\.exe$'
        (Get-StartupTargetPath -Item ([PSCustomObject]@{ Name='a'; Value='C:\tools\run.cmd /x' }))                        | Should -Be 'C:\tools\run.cmd'
        (Get-StartupTargetPath -Item ([PSCustomObject]@{ Name='a'; Value='' }))                                            | Should -Be ''
    }

    It 'Get-StartupRiskScore never recommends system / hardware essentials' {
        foreach ($pair in @(
            @{ N='SecurityHealth'; V='C:\Windows\System32\SecurityHealthSystray.exe' },
            @{ N='RealtekAudio';  V='C:\Windows\System32\RtkAudUService.exe' },
            @{ N='IgfxTray';      V='C:\Windows\System32\igfxEM.exe' },
            @{ N='IntelTBT';      V='C:\Program Files\Intel\Thunderbolt\ThunderboltControlCenter.exe' }
        )) {
            $r = Get-StartupRiskScore -Item ([PSCustomObject]@{ Name=$pair.N; Value=$pair.V })
            $r.score | Should -BeLessThan 0
            $r.reason | Should -Match '不建议禁用'
            $r.tags | Should -Contain 'essential'
        }
    }

    It 'Get-StartupRiskScore ranks updaters above plain third-party entries' {
        $updater = Get-StartupRiskScore -Item ([PSCustomObject]@{ Name='GhostUpdater'; Value='"C:\Program Files\Ghost\GhostUpdater.exe" /silent' })
        $plain   = Get-StartupRiskScore -Item ([PSCustomObject]@{ Name='SomeApp';      Value='C:\Program Files\SomeApp\SomeApp.exe' })
        $plain.score   | Should -Be 5
        $updater.score | Should -BeGreaterThan $plain.score
        $updater.tags  | Should -Contain 'update'
    }

    It 'Get-StartupRiskScore flags missing targets as zero-risk to disable' {
        $dead = Get-StartupRiskScore -Item ([PSCustomObject]@{ Name='SunloginClient'; Value='"d:\gone\SunloginClient.exe"' }) -TargetExists:$false
        $live = Get-StartupRiskScore -Item ([PSCustomObject]@{ Name='SunloginClient'; Value='"d:\gone\SunloginClient.exe"' }) -TargetExists:$true
        $dead.tags  | Should -Contain 'dead'
        $dead.reason | Should -Match '目标文件已不存在'
        $dead.score | Should -BeGreaterThan $live.score
    }

    It 'Get-StartupRiskScore pushes sync / background / userdir entries up' {
        $sync = Get-StartupRiskScore -Item ([PSCustomObject]@{ Name='OneDriveSync'; Value='C:\Users\me\AppData\Local\SomeVendor\sync\SyncAgent.exe' })
        $sync.tags  | Should -Contain 'sync'
        $sync.tags  | Should -Contain 'background'
        $sync.tags  | Should -Contain 'userdir'
        $sync.score | Should -BeGreaterThan 30
    }

    It 'Get-StartupRiskScore demotes one-shot RunOnce entries' {
        $base  = [PSCustomObject]@{ Name='ChromeUpdate'; Value='C:\Users\me\AppData\Local\Chrome\updater.exe' }
        $once  = Get-StartupRiskScore -Item ([PSCustomObject]@{ Name=$base.Name; Value=$base.Value; Scope='RunOnce 当前用户' }) -TargetExists:$false
        $plain = Get-StartupRiskScore -Item $base -TargetExists:$false
        $once.tags | Should -Contain 'once'
        # 同一个僵尸更新项：RunOnce 应比普通 Run 低 20 分
        ($once.score - $plain.score) | Should -Be -20
    }

    It 'Get-SmartRecommendations honours Top and ranks by score' {
        $items = @(
            [PSCustomObject]@{ Name='ZedUpdater';    Value='C:\Users\me\AppData\Local\Zed\ZedUpdater.exe'; Scope='当前用户'; Source='注册表'; Index=1 }
            [PSCustomObject]@{ Name='GhostSync';     Value='"C:\gone\GhostSync.exe"';                       Scope='所有用户'; Source='注册表'; Index=2 }
            [PSCustomObject]@{ Name='PlainApp';      Value='C:\Program Files\Plain\PlainApp.exe';           Scope='当前用户'; Source='注册表'; Index=3 }
            [PSCustomObject]@{ Name='DefenderTray';  Value='C:\Windows\System32\SecurityHealthSystray.exe'; Scope='所有用户'; Source='注册表'; Index=4 }
        )
        $tips = Get-SmartRecommendations -StartupItems $items -Top 2 -IncludeStartup
        $tips.ok | Should -BeTrue
        @($tips.startup).Count | Should -Be 2
        @($tips.clean).Count   | Should -Be 0
        $tips.startup[0].rank  | Should -Be 1
        $tips.startup[1].rank  | Should -Be 2
        $tips.startup[0].score | Should -BeGreaterThan $tips.startup[1].score
        # 两条目标都不存在：ZedUpdater=僵尸+更新+用户目录(80) > GhostSync=僵尸+云同步(65)
        $tips.startup[0].name  | Should -Be 'ZedUpdater'
        $tips.startup[0].score | Should -Be 80
        $tips.startup[1].score | Should -Be 65
        foreach ($s in @($tips.startup)) {
            @($s.PSObject.Properties.Name) | Should -Contain 'kind'
            @($s.PSObject.Properties.Name) | Should -Contain 'reason'
            @($s.PSObject.Properties.Name) | Should -Contain 'hint'
            $s.kind | Should -Be 'startup'
            $s.reason | Should -Not -BeNullOrEmpty
            $s.hint   | Should -Not -BeNullOrEmpty
        }
        # Defender 绝不出现在建议里
        @($tips.startup | Where-Object { $_.name -eq 'DefenderTray' }).Count | Should -Be 0
    }

    It 'Get-SmartRecommendations stays quiet when the report has no trigger issue' {
        $report = [PSCustomObject]@{
            issues = @([PSCustomObject]@{ id='network.dns.Wi-Fi'; severity='Low'; title='x' })
        }
        $tips = Get-SmartRecommendations -Report $report -StartupItems @()
        @($tips.startup).Count | Should -Be 0
        @($tips.clean).Count   | Should -Be 0
    }

    It 'memory.low only suggests startup items, disk.space only suggests clean targets' {
        $mem = [PSCustomObject]@{ issues = @([PSCustomObject]@{ id='memory.low'; severity='High' }) }
        $memTips = Get-SmartRecommendations -Report $mem -StartupItems @()
        @($memTips.startup).Count | Should -Be 0      # 显式传入空清单：不得回退去读真实注册表
        @($memTips.clean).Count   | Should -Be 0      # memory.low 不触发清理建议

        $dsk = [PSCustomObject]@{
            issues  = @([PSCustomObject]@{ id='disk.space'; severity='High' })
            metrics = [PSCustomObject]@{ cleanTargets = @([PSCustomObject]@{ name='用户临时文件'; mb = 12.0 }) }
        }
        $dskTips = Get-SmartRecommendations -Report $dsk
        @($dskTips.startup).Count | Should -Be 0      # disk.space 不触发启动项建议
        @($dskTips.clean).Count   | Should -Be 1
    }

    It 'clean recommendations reuse the report measurements and rank by size' {
        $report = [PSCustomObject]@{
            issues  = @([PSCustomObject]@{ id='disk.cleanable'; severity='Medium' })
            metrics = [PSCustomObject]@{
                cleanTargets = @(
                    [PSCustomObject]@{ name='用户临时文件';            mb = 100.0 }
                    [PSCustomObject]@{ name='Windows Update 下载缓存'; mb = 900.5 }
                    [PSCustomObject]@{ name='缩略图缓存';              mb = 5.0 }
                )
            }
        }
        $tips = Get-SmartRecommendations -Report $report -Top 3
        @($tips.clean).Count | Should -Be 3
        $tips.clean[0].name | Should -Be 'Windows Update 下载缓存'
        $tips.clean[0].rank | Should -Be 1
        $tips.clean[0].mb   | Should -Be 900.5
        $tips.clean[0].reason | Should -Match '可释放 900.5 MB'
        $tips.clean[0].reason | Should -Match '%'
        $tips.clean[1].rank | Should -Be 2
        $tips.clean[2].rank | Should -Be 3
        foreach ($c in @($tips.clean)) {
            @($c.PSObject.Properties.Name) | Should -Contain 'kind'
            @($c.PSObject.Properties.Name) | Should -Contain 'key'
            @($c.PSObject.Properties.Name) | Should -Contain 'path'
            @($c.PSObject.Properties.Name) | Should -Contain 'hint'
            $c.kind | Should -Be 'clean'
            $c.path | Should -Not -BeNullOrEmpty
        }
    }

    It 'Format-SmartRecommendations renders one block per recommendation' {
        $items = @([PSCustomObject]@{ Name='ZedUpdater'; Value='C:\Users\me\AppData\Local\Zed\ZedUpdater.exe'; Scope='当前用户'; Source='注册表'; Index=1 })
        $tips  = Get-SmartRecommendations -StartupItems $items -Top 3 -IncludeStartup
        $lines = @(Format-SmartRecommendations $tips)
        $lines.Count | Should -BeGreaterThan 3
        ($lines -join "`n") | Should -Match 'ZedUpdater'
        ($lines -join "`n") | Should -Match '一键应用本条建议'
    }

    It 'Get-SmartRecommendations measures clean targets on its own when no report given' {
        $tips = Get-SmartRecommendations -IncludeClean -Top 2
        @($tips.clean).Count | Should -BeGreaterThan 0
        @($tips.clean).Count | Should -BeLessOrEqual 2
        $tips.clean[0].mb | Should -BeGreaterThan 0
    }
}

Describe 'Optimize.Core unified optimize plan - read-only dry-run (P2, shared by CLI/GUI/WebUI)' {
    BeforeAll {
        . (Join-Path $PWD.Path 'lib\Optimize.Core.ps1')
    }

    It 'Get-OptimizePlan returns a well-formed plan with risks and a consistent summary' {
        $plan = Get-OptimizePlan -SkipCleanScan
        $plan.ok | Should -BeTrue
        $plan.version | Should -Not -BeNullOrEmpty
        $plan.generatedAt | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
        @($plan.steps).Count | Should -BeGreaterThan 0
        foreach ($s in @($plan.steps)) {
            foreach ($f in @('domain','title','menu','action','target','impact','risk')) {
                @($s.PSObject.Properties.Name) | Should -Contain $f
            }
            $s.domain | Should -Not -BeNullOrEmpty
            $s.menu   | Should -Not -BeNullOrEmpty
            $s.title  | Should -Not -BeNullOrEmpty
            $s.action | Should -Not -BeNullOrEmpty
            $s.impact | Should -Not -BeNullOrEmpty
            $s.risk   | Should -BeIn @('low','medium','high')
        }
        # SkipCleanScan：不得出现 clean 步骤
        @($plan.steps | Where-Object { $_.domain -eq 'clean' }).Count | Should -Be 0
        # summary 与实际步骤一一对应
        $plan.summary.total | Should -Be @($plan.steps).Count
        ($plan.summary.low + $plan.summary.medium + $plan.summary.high) | Should -Be @($plan.steps).Count
        $plan.summary.low    | Should -Be @($plan.steps | Where-Object { $_.risk -eq 'low' }).Count
        $plan.summary.medium | Should -Be @($plan.steps | Where-Object { $_.risk -eq 'medium' }).Count
        $plan.summary.high   | Should -Be @($plan.steps | Where-Object { $_.risk -eq 'high' }).Count
    }

    It 'plan always covers services/startup/power/disk and resolves power-plan labels' {
        $plan = Get-OptimizePlan -SkipCleanScan
        foreach ($d in @('services','startup','power','disk')) {
            @($plan.steps | Where-Object { $_.domain -eq $d }).Count | Should -Be 1
        }
        $plan.powerPlan | Should -Not -BeNullOrEmpty
        $plan.dns       | Should -Not -BeNullOrEmpty

        $bal = Get-OptimizePlan -SkipCleanScan -PowerPlanGuid '381b4222-f694-41f0-9685-ff5bb260df2e'
        $powerStep = @($bal.steps | Where-Object { $_.domain -eq 'power' })[0]
        $powerStep.target | Should -Match '平衡优化模式'
        $powerStep.action | Should -Be 'Set-PowerPlan'
        $powerStep.risk   | Should -Be 'low'
    }

    It 'network step reflects the chosen DNS option when adapters are present' {
        $plan = Get-OptimizePlan -SkipCleanScan -DnsOption 3
        $plan.dns | Should -Be '阿里 DNS'
        # 无活动网卡时跳过该步骤是合法行为；有网卡时必须带上所选 DNS
        if (@(Get-ActiveNetAdapters).Count -gt 0) {
            $net = @($plan.steps | Where-Object { $_.domain -eq 'network' })[0]
            $net | Should -Not -BeNullOrEmpty
            $net.action | Should -Be 'Invoke-NetworkOptimization'
            $net.risk   | Should -Be 'medium'
            $net.target | Should -Match '阿里 DNS'
        }
    }

    It 'profile steps are appended for known bundles and surface unknown ones as errors' {
        $plan = Get-OptimizePlan -SkipCleanScan -ProfileName 'old_balanced'
        $p = @($plan.steps | Where-Object { $_.domain -eq 'profile' })[0]
        $p | Should -Not -BeNullOrEmpty
        $p.target | Should -Match 'old_balanced'
        $p.title  | Should -Match '老机均衡'
        $p.action | Should -Be 'Invoke-Profile'

        $bad = Get-OptimizePlan -SkipCleanScan -ProfileName 'no_such_profile'
        $bad.ok | Should -BeTrue
        $bp = @($bad.steps | Where-Object { $_.domain -eq 'profile' })[0]
        $bp.target | Should -Be 'no_such_profile'
        $bp.impact | Should -Match '未找到组合包'
    }

    It 'clean step appears with size data when the scan is not skipped' {
        $plan  = Get-OptimizePlan
        $clean = @($plan.steps | Where-Object { $_.domain -eq 'clean' })
        $clean.Count | Should -BeLessOrEqual 1
        if ($clean.Count -eq 1) {
            $clean[0].menu   | Should -Be '[2]'
            $clean[0].action | Should -Be 'Remove-FolderContent'
            $clean[0].risk   | Should -Be 'low'
            $clean[0].target | Should -Match 'MB'
        }
    }

    It 'Format-OptimizePlan renders menu/title per step and stays empty for null or failed plans' {
        $plan  = Get-OptimizePlan -SkipCleanScan -ProfileName 'old_balanced'
        $lines = @(Format-OptimizePlan $plan)
        $text  = $lines -join "`n"
        foreach ($s in @($plan.steps)) {
            $text | Should -Match ([regex]::Escape($s.menu))
            $text | Should -Match ([regex]::Escape($s.title))
        }
        @(Format-OptimizePlan $null).Count | Should -Be 0
        @(Format-OptimizePlan ([PSCustomObject]@{ ok = $false })).Count | Should -Be 0
    }
}

Describe 'Optimize.Core boot-time performance baseline bench (P2-2, shared by CLI/GUI/WebUI)' {
    BeforeAll {
        . (Join-Path $PWD.Path 'lib\Optimize.Core.ps1')
    }

    It 'Get-SystemBench returns a well-formed, fully populated read-only probe result' {
        $b = Get-SystemBench -StartupCount 7 -AutoServices 3
        $b | Should -BeOfType [PSCustomObject]
        $b.ok | Should -BeTrue
        foreach ($f in @('diskReadMBps','diskWriteMBps','startupCount','autoServices','totalRamMB','elapsedMs','error')) {
            @($b.PSObject.Properties.Name) | Should -Contain $f
        }
        $b.diskReadMBps  | Should -BeGreaterThan 0
        $b.diskWriteMBps | Should -BeGreaterThan 0
        $b.totalRamMB    | Should -BeGreaterThan 0
        $b.elapsedMs     | Should -BeGreaterThan 0
        $b.error         | Should -BeNullOrEmpty
    }

    It 'Get-SystemBench reuses measured startup/service counts when supplied' {
        $b = Get-SystemBench -StartupCount 42 -AutoServices 9
        $b.startupCount | Should -Be 42
        $b.autoServices | Should -Be 9
        # 0 也是合法值（没有可优化服务处于自动启动），不得回退去重新扫描
        $z = Get-SystemBench -StartupCount 0 -AutoServices 0
        $z.startupCount | Should -Be 0
        $z.autoServices | Should -Be 0
    }

    It 'Get-SystemBench measures live startup/service counts when not supplied' {
        $b = Get-SystemBench
        $b.ok | Should -BeTrue
        $b.startupCount | Should -BeGreaterThan 0
        $b.startupCount | Should -Be (@(Get-StartupItems).Count)
        $b.autoServices | Should -BeGreaterOrEqual 0
    }

    It 'health report carries a bench section that reuses measured counts' {
        $r = Get-SystemHealthReport -SkipCleanScan
        $r.bench | Should -Not -BeNullOrEmpty
        $r.bench.ok            | Should -BeTrue
        $r.bench.startupCount  | Should -Be $r.metrics.startupCount
        $r.bench.autoServices  | Should -Be $r.metrics.servicesStillAuto
        $r.bench.diskReadMBps  | Should -BeGreaterThan 0
        $r.score | Should -BeGreaterOrEqual 0
    }

    It 'health report -SkipBench leaves the bench section null' {
        $r = Get-SystemHealthReport -SkipCleanScan -SkipBench
        $r.bench | Should -BeNullOrEmpty
    }

    It 'Get-HealthTrend tolerates legacy reports without a bench section' {
        $tmp = Join-Path $env:TEMP ('bench_trend_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path (Join-Path $tmp 'health') -Force | Out-Null
            $mkOld = {
                param($Day, $Score)
                $when = (Get-Date).AddDays(-$Day)
                $o = [PSCustomObject]@{
                    timestamp = $when.ToString('yyyy-MM-dd HH:mm:ss')
                    host      = 'h'; version = '3.6.0'; score = $Score; grade = 'x'
                    metrics   = [PSCustomObject]@{ freeRamPct = 50.0; cleanableMB = 100; startupCount = 5 }
                    issues    = @()
                }
                $f = Join-Path $tmp ("health\health_{0}.json" -f $when.ToString('yyyyMMdd_HHmmss'))
                $o | ConvertTo-Json -Depth 8 | Out-File -FilePath $f -Encoding UTF8
                (Get-Item $f).LastWriteTime = $when
            }
            & $mkOld 2 60
            & $mkOld 1 70
            # 新格式报告：带 bench 段
            $when = Get-Date
            $newRep = [PSCustomObject]@{
                timestamp = $when.ToString('yyyy-MM-dd HH:mm:ss')
                host      = 'h'; version = '3.7.0'; score = 80; grade = 'x'
                metrics   = [PSCustomObject]@{ freeRamPct = 55.0; cleanableMB = 100; startupCount = 5 }
                bench     = [PSCustomObject]@{ diskReadMBps = 1234.5 }
                issues    = @()
            }
            $f = Join-Path $tmp ("health\health_{0}.json" -f $when.ToString('yyyyMMdd_HHmmss'))
            $newRep | ConvertTo-Json -Depth 8 | Out-File -FilePath $f -Encoding UTF8
            (Get-Item $f).LastWriteTime = $when

            $t = @(Get-HealthTrend -BackupDir $tmp -Days 30)
            $t.Count | Should -Be 3
            # 历史（无 bench）点位磁盘读为 0，不抛异常
            $t[0].diskReadMBps | Should -Be 0
            $t[1].diskReadMBps | Should -Be 0
            # 新点位读到 bench.diskReadMBps
            $t[-1].diskReadMBps | Should -Be 1234.5
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================
#  P3-1 智能建议一键应用 / 服务依赖护栏 / 真实开机耗时
#  （三端共享：CLI / GUI / WebUI 均调用 lib 同一实现）
# ============================================================
Describe 'Optimize.Core smart recommendation apply loop (P3-1, shared by CLI/GUI/WebUI)' {
    BeforeAll {
        . (Join-Path $PWD.Path 'lib\Optimize.Core.ps1')
        $script:LiveItems = @(
            [PSCustomObject]@{ Name='ZedUpdater';  Value='C:\Users\me\AppData\Local\Zed\ZedUpdater.exe'; Scope='当前用户'; Source='注册表'; Path='HKCU:\Run'; Index=1 }
            [PSCustomObject]@{ Name='CloudSync';   Value='C:\Users\me\AppData\Local\Cloud\sync.exe';    Scope='当前用户'; Source='注册表'; Path='HKCU:\Run'; Index=2 }
            [PSCustomObject]@{ Name='RealtekHd';   Value='C:\Windows\System32\RtkAudUService.dll';      Scope='所有用户'; Source='注册表'; Path='HKLM:\Run'; Index=3 }
        )
        Mock Get-StartupItems { $script:LiveItems }
        Mock Disable-StartupItems {
            [PSCustomObject]@{
                disabled = @($Items).Count
                failed   = 0
                backup   = $null
                details  = @(@($Items) | ForEach-Object {
                    [PSCustomObject]@{ Name = $_.Name; Source = $_.Source; Result = '已禁用' }
                })
            }
        }
        Mock Backup-StartupItems { 'FAKE_BACKUP_CSV' }
        Mock New-SystemRestorePoint { [PSCustomObject]@{ ok = $true; name = 'FakeRP'; method = 'Checkpoint-Computer' } }
    }

    It 'applies startup recommendations end to end (backup first, then disable)' {
        $rep = [PSCustomObject]@{
            issues = @([PSCustomObject]@{ id = 'startup.many'; severity = 'Medium'; title = '开机启动项偏多' })
        }
        $r = Invoke-SmartRecommendations -Report $rep -Top 3 -BackupDir (Join-Path $env:TEMP 'p3_none')
        $r.ok | Should -BeTrue
        @($r.applied).Count | Should -Be 2
        @($r.applied) | Should -Contain 'ZedUpdater'
        @($r.applied) | Should -Contain 'CloudSync'
        $r.backup | Should -Be 'FAKE_BACKUP_CSV'
        Assert-MockCalled -CommandName 'Backup-StartupItems' -Times 1 -Scope It
        Assert-MockCalled -CommandName 'Disable-StartupItems' -ParameterFilter { @($Items).Count -eq 2 -and $SkipBackup } -Scope It
        # 默认不建还原点（config safety.create_restore_point 默认 false）
        $r.restorePoint | Should -BeNullOrEmpty
    }

    It 'never leaves essential items out of the blacklist: Realtek entry is not applied' {
        $rep = [PSCustomObject]@{
            issues = @([PSCustomObject]@{ id = 'startup.many'; severity = 'Medium'; title = 'x' })
        }
        $r = Invoke-SmartRecommendations -Report $rep -Top 5 -BackupDir (Join-Path $env:TEMP 'p3_none')
        @($r.applied) | Should -Not -Contain 'RealtekHd'
    }

    It '-WhatIf is side-effect free: no backup, no restore point, still reports would-be changes' {
        $rep = [PSCustomObject]@{
            issues = @([PSCustomObject]@{ id = 'startup.many'; severity = 'Medium'; title = 'x' })
        }
        $r = Invoke-SmartRecommendations -Report $rep -BackupDir (Join-Path $env:TEMP 'p3_none') -WhatIf -CreateRestorePoint:$true
        $r.whatIf | Should -BeTrue
        $r.ok     | Should -BeTrue
        @($r.applied).Count | Should -Be 2
        $r.backup       | Should -BeNullOrEmpty
        $r.restorePoint | Should -BeNullOrEmpty
        Assert-MockCalled -CommandName 'Backup-StartupItems'   -Times 0 -Scope It
        Assert-MockCalled -CommandName 'New-SystemRestorePoint' -Times 0 -Scope It
    }

    It 'creates a restore point lazily only when asked' {
        $rep = [PSCustomObject]@{
            issues = @([PSCustomObject]@{ id = 'startup.many'; severity = 'Medium'; title = 'x' })
        }
        $r = Invoke-SmartRecommendations -Report $rep -BackupDir (Join-Path $env:TEMP 'p3_none') -CreateRestorePoint:$true
        $r.restorePoint.ok   | Should -BeTrue
        $r.restorePoint.name | Should -Be 'FakeRP'
        Assert-MockCalled -CommandName 'New-SystemRestorePoint' -Times 1 -Scope It
    }

    It 'fails safely when the report gives no trigger issue' {
        $rep = [PSCustomObject]@{ issues = @([PSCustomObject]@{ id = 'disk.space'; severity = 'High'; title = 'x' }) }
        $r = Invoke-SmartRecommendations -Report $rep -BackupDir (Join-Path $env:TEMP 'p3_none')
        $r.ok    | Should -BeFalse
        $r.error | Should -Not -BeNullOrEmpty
        Assert-MockCalled -CommandName 'Backup-StartupItems'  -Times 0 -Scope It
        Assert-MockCalled -CommandName 'Disable-StartupItems' -Times 0 -Scope It
    }

    It 'fails safely when the recommended items vanished from the live system' {
        Mock Get-SmartRecommendations { [PSCustomObject]@{ ok = $true; startup = @([PSCustomObject]@{ kind='startup'; name='GhostApp'; command='C:\ghost\ghost.exe'; rank=1 }); clean = @() } }
        $rep = [PSCustomObject]@{
            issues = @([PSCustomObject]@{ id = 'startup.many'; severity = 'Medium'; title = 'x' })
        }
        $r = Invoke-SmartRecommendations -Report $rep -BackupDir (Join-Path $env:TEMP 'p3_none')
        $r.ok    | Should -BeFalse
        $r.error | Should -Match '已不存在'
        Assert-MockCalled -CommandName 'Disable-StartupItems' -Times 0 -Scope It
    }

    It 'a partially failed disable reports failed items and ok=$false' {
        Mock Disable-StartupItems {
            [PSCustomObject]@{
                disabled = 1; failed = 1; backup = $null
                details  = @(
                    [PSCustomObject]@{ Name = 'ZedUpdater'; Source = '注册表';     Result = '已禁用' }
                    [PSCustomObject]@{ Name = 'CloudSync';  Source = '启动文件夹'; Result = '失败: boom' }
                )
            }
        }
        $rep = [PSCustomObject]@{
            issues = @([PSCustomObject]@{ id = 'startup.many'; severity = 'Medium'; title = 'x' })
        }
        $r = Invoke-SmartRecommendations -Report $rep -BackupDir (Join-Path $env:TEMP 'p3_none')
        $r.ok | Should -BeFalse
        @($r.applied) | Should -Contain 'ZedUpdater'
        @($r.failed).Count | Should -Be 1
        $r.failed[0].name   | Should -Be 'CloudSync'
        $r.failed[0].reason | Should -Match '失败'
    }
}

Describe 'Optimize.Core service dependency guard (P3-1, shared by CLI/GUI/WebUI)' {
    BeforeAll {
        . (Join-Path $PWD.Path 'lib\Optimize.Core.ps1')
        Mock Get-Service -ParameterFilter { $Name -eq 'RpcSs' } { [PSCustomObject]@{ Name = 'RpcSs'; Status = 'Running' } }
        Mock Get-Service -ParameterFilter { $Name -eq 'DepA'  } { [PSCustomObject]@{ Name = 'DepA';  Status = 'Running' } }
        Mock Get-WmiObject { [PSCustomObject]@{ Name = 'DepA' } }
        Mock Set-Service  {}
        Mock Stop-Service {}
        Mock Start-Sleep {}
    }

    It 'Get-ServiceDependents returns only running dependents' {
        $d = @(Get-ServiceDependents -Name 'RpcSs')
        $d | Should -Contain 'DepA'
    }

    It 'Get-ServiceDependents tolerates unknown service names' {
        Mock Get-Service -ParameterFilter { $Name -eq 'Ghost' } { $null }
        Mock Get-WmiObject { @() }
        @(Get-ServiceDependents -Name 'Ghost').Count | Should -Be 0
    }

    It 'Get-ServiceDependents tolerates WMI failure (returns empty, never throws)' {
        Mock Get-WmiObject { throw 'WMI down' }
        { @(Get-ServiceDependents -Name 'RpcSs') } | Should -Not -Throw
        @(Get-ServiceDependents -Name 'RpcSs').Count | Should -Be 0
    }

    It 'Disable-Services skips services with running dependents by default' {
        $r = Disable-Services -Services @([PSCustomObject]@{ Name = 'RpcSs'; Level = '安全禁用'; Desc = 'd' }) -Mode 'all'
        $r.disabled | Should -Be 0
        $r.skipped  | Should -Be 1
        [string]$r.details[0].result | Should -Match '依赖'
    }

    It 'Disable-Services -Force overrides the dependency guard' {
        $r = Disable-Services -Services @([PSCustomObject]@{ Name = 'RpcSs'; Level = '安全禁用'; Desc = 'd' }) -Mode 'all' -Force
        $r.disabled | Should -Be 1
        $r.skipped  | Should -Be 0
        Assert-MockCalled -CommandName 'Set-Service' -Times 1 -Scope It
    }

    It 'Disable-Services -WhatIf previews the dependency skip without touching the system' {
        $r = Disable-Services -Services @([PSCustomObject]@{ Name = 'RpcSs'; Level = '安全禁用'; Desc = 'd' }) -Mode 'all' -WhatIf
        $r.skipped | Should -Be 1
        Assert-MockCalled -CommandName 'Set-Service' -Times 0 -Scope It
    }
}

Describe 'Optimize.Core real boot time sample (P3-1, accuracy)' {
    BeforeAll { . (Join-Path $PWD.Path 'lib\Optimize.Core.ps1') }

    It 'Get-BootPerformanceSample always returns a well-formed result' {
        $b = Get-BootPerformanceSample
        @($b.PSObject.Properties.Name) | Should -Contain 'ok'
        @($b.PSObject.Properties.Name) | Should -Contain 'seconds'
        @($b.PSObject.Properties.Name) | Should -Contain 'source'
        if ($b.ok) {
            $b.seconds | Should -BeGreaterThan 1
            $b.seconds | Should -BeLessThan 3600
            $b.source  | Should -Not -BeNullOrEmpty
        } else {
            $b.seconds | Should -BeNullOrEmpty
            $b.error   | Should -Not -BeNullOrEmpty
        }
    }

    It 'bench carries bootSeconds and tolerates missing boot events' {
        $b = Get-SystemBench -StartupCount 3 -AutoServices 2
        @($b.PSObject.Properties.Name) | Should -Contain 'bootSeconds'
        @($b.PSObject.Properties.Name) | Should -Contain 'bootError'
        $b.startupCount | Should -Be 3
        $b.autoServices | Should -Be 2
        $b.bootSeconds  | Should -BeNullOrEmpty
        $b.bootError    | Should -Not -BeNullOrEmpty
    }

    It 'Get-HealthTrend parses bootSeconds when present and stays null-safe otherwise' {
        $tmp = Join-Path $env:TEMP ('p3_boottrend_' + (New-Guid).ToString('N'))
        try {
            New-Item -ItemType Directory -Path (Join-Path $tmp 'health') -Force | Out-Null
            $mk = {
                param($Day, $Score, $Boot)
                $when = (Get-Date).AddDays(-$Day)
                $o = [PSCustomObject]@{
                    timestamp = $when.ToString('yyyy-MM-dd HH:mm:ss')
                    host = 'h'; version = '3.9.0'; score = $Score; grade = 'x'
                    metrics = [PSCustomObject]@{ freeRamPct = 50.0; cleanableMB = 100; startupCount = 5 }
                    issues  = @()
                }
                if ($null -ne $Boot) {
                    $o | Add-Member -NotePropertyName bench -NotePropertyValue ([PSCustomObject]@{ bootSeconds = $Boot }) -Force
                }
                $f = Join-Path $tmp ("health\health_{0}.json" -f $when.ToString('yyyyMMdd_HHmmss'))
                $o | ConvertTo-Json -Depth 8 | Out-File -FilePath $f -Encoding UTF8
                (Get-Item $f).LastWriteTime = $when
            }
            & $mk 2 60 $null
            & $mk 1 70 42.5
            $t = @(Get-HealthTrend -BackupDir $tmp -Days 30)
            $t.Count | Should -Be 2
            $t[0].bootSeconds  | Should -BeNullOrEmpty
            $t[-1].bootSeconds | Should -Be 42.5
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
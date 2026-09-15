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

    It 'Set-VisualEffectProfile -WhatIf reports backup without modifying system' {
        $tmp = Join-Path $env:TEMP ('vis2_' + (New-Guid).ToString('N'))
        try {
            $r = Set-VisualEffectProfile -Profile 1 -BackupDir $tmp -SkipExplorerRestart -WhatIf
            $r.profile | Should -Be 1
            $r.backup | Should -Not -BeNullOrEmpty
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

    It 'Backup-PowerPlan writes a txt backup file' {
        $tmp = Join-Path $env:TEMP ('pwr_' + (New-Guid).ToString('N'))
        try {
            $f = Backup-PowerPlan -BackupDir $tmp
            Test-Path $f | Should -BeTrue
            $f | Should -Match '\.txt$'
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Set-PowerPlan -WhatIf reports plan, backup and details without modifying system' {
        $tmp = Join-Path $env:TEMP ('pwr2_' + (New-Guid).ToString('N'))
        try {
            $r = Set-PowerPlan -Guid '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' -MinPercent 100 -MaxPercent 100 `
                -DiskIdleSeconds 0 -UsbSuspendOff $true -PciAspmOff $true -BackupDir $tmp -WhatIf
            $r.ok | Should -BeTrue
            $r.appliedGuid | Should -Be '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
            $r.details.Count | Should -BeGreaterOrEqual 3
            $r.backup | Should -Not -BeNullOrEmpty
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

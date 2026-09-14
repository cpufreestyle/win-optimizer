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

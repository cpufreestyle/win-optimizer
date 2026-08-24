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

    It 'Get-OptConfig returns non-null object with version 3.0.0' {
        $cfg = Get-OptConfig
        $cfg | Should -Not -BeNullOrEmpty
        $cfg.version | Should -Be '3.0.0'
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

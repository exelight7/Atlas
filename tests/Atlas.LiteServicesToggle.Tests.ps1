BeforeAll {
    . (Join-Path $PSScriptRoot 'AtlasTestHost.ps1')
    Import-Module (Join-Path $script:AtlasTestModulesRoot 'Atlas.Core\Atlas.Core.psd1') -Force
    Import-Module (Join-Path $script:AtlasTestModulesRoot 'Atlas.Services\Atlas.Services.psd1') -Force
    Import-Module (Join-Path $script:AtlasTestModulesRoot 'Atlas.Toggles\Atlas.Toggles.psd1') -Force
    $script:TogglesRoot = Join-Path $script:AtlasTestRepoRoot 'playbook\Executables\AtlasModules\Toggles'
    $script:Lite = Get-AtlasToggleDefinition -Name LiteServices -TogglesRoot $script:TogglesRoot

    # Windows 11 client defaults, which Enable restores.
    $script:WindowsDefault = @{
        DusmSvc = 2
        CDPUserSvc = 2
        XblAuthManager = 3
        XblGameSave = 3
        XboxNetApiSvc = 3
    }

    function Get-LiteServiceEntry {
        param([Parameter(Mandatory = $true)][string]$State)
        @($script:Lite['States'][$State]['Services'] | ForEach-Object { [hashtable]$_ })
    }
}

Describe 'LiteServices toggle definition' {
    It 'passes the toggle definition validator' {
        @(Test-AtlasToggleDefinition -Path (Join-Path $script:TogglesRoot 'Services\LiteServices.psd1')) | Should -BeNullOrEmpty
    }

    It 'is an administrator toggle that records Disable as 0 and Enable as 1' {
        $script:Lite['Elevation'] | Should -Be 'Admin'
        $script:Lite['States']['Disable']['StateValue'] | Should -Be 0
        $script:Lite['States']['Enable']['StateValue'] | Should -Be 1
        $script:Lite['States']['Enable']['Launcher'] | Should -BeLike '*(default).cmd'
    }

    It 'changes the same services in both states and restores the Windows defaults on Enable' {
        $disable = Get-LiteServiceEntry -State Disable
        $enable = Get-LiteServiceEntry -State Enable
        @($disable | ForEach-Object { $_['Name'] }) | Should -Be @($enable | ForEach-Object { $_['Name'] })
        foreach ($entry in $enable) {
            $entry['StartupType'] | Should -Be $script:WindowsDefault[$entry['Name']] -Because "$($entry['Name']) returns to its Windows default"
        }
        foreach ($entry in $disable) {
            $entry['StartupType'] | Should -BeGreaterThan $script:WindowsDefault[$entry['Name']] -Because "$($entry['Name']) starts later or never"
            $entry['AllowMissing'] | Should -BeTrue
        }
    }

    It 'never touches anti-cheat, security, search, update or shared Connected Devices services' {
        $protected = @(
            'vgc', 'vgk', 'EasyAntiCheat', 'EasyAntiCheat_EOS', 'BEService', 'WinDefend', 'MDCoreSvc', 'mpssvc',
            'wscsvc', 'BFE', 'CryptSvc', 'WSearch', 'UsoSvc', 'BITS', 'wuauserv', 'CDPSvc', 'TrkWks', 'iphlpsvc',
            'WpnService', 'GameInputRedistService', 'XboxGipSvc', 'vmms', 'vmcompute', 'HvHost', 'hns'
        )
        foreach ($state in 'Disable', 'Enable') {
            foreach ($entry in Get-LiteServiceEntry -State $state) {
                $protected | Should -Not -Contain $entry['Name']
            }
        }
    }
}

Describe 'LiteServices toggle work' {
    It 'applies every declared startup type, tolerating a missing service' {
        Mock Set-AtlasServiceStartup -ModuleName Atlas.Services {}

        Invoke-AtlasServiceEntries -Entries (Get-LiteServiceEntry -State Disable)

        foreach ($entry in Get-LiteServiceEntry -State Disable) {
            Should -Invoke Set-AtlasServiceStartup -ModuleName Atlas.Services -Times 1 -Exactly -ParameterFilter {
                $Name -ceq $entry['Name'] -and $StartupType -eq $entry['StartupType'] -and $AllowMissing
            }
        }
    }

    It 'reports drift until the services hold the chosen state, and none for absent services' {
        $root = 'TestRegistry:\Services'
        New-Item -Path $root -Force | Out-Null
        foreach ($name in $script:WindowsDefault.Keys) {
            New-Item -Path (Join-Path $root $name) -Force | Out-Null
            New-ItemProperty -Path (Join-Path $root $name) -Name Start -PropertyType DWord -Value $script:WindowsDefault[$name] -Force | Out-Null
        }

        @(Test-AtlasServiceEntries -Entries (Get-LiteServiceEntry -State Enable) -ServicesRoot $root) | Should -BeNullOrEmpty
        $drift = @(Test-AtlasServiceEntries -Entries (Get-LiteServiceEntry -State Disable) -ServicesRoot $root)
        $drift.Count | Should -Be $script:WindowsDefault.Count

        foreach ($entry in Get-LiteServiceEntry -State Disable) {
            Set-ItemProperty -Path (Join-Path $root $entry['Name']) -Name Start -Value $entry['StartupType']
        }
        @(Test-AtlasServiceEntries -Entries (Get-LiteServiceEntry -State Disable) -ServicesRoot $root) | Should -BeNullOrEmpty

        Remove-Item -Path (Join-Path $root 'XblGameSave') -Recurse -Force
        Remove-Item -Path (Join-Path $root 'DusmSvc') -Recurse -Force
        @(Test-AtlasServiceEntries -Entries (Get-LiteServiceEntry -State Disable) -ServicesRoot $root) | Should -BeNullOrEmpty
        @(Test-AtlasServiceEntries -Entries (Get-LiteServiceEntry -State Enable) -ServicesRoot $root).Count | Should -Be 3
    }
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'AtlasTestHost.ps1')
    Import-Module (Join-Path $script:AtlasTestModulesRoot 'Atlas.Core\Atlas.Core.psd1') -Force
    Import-Module (Join-Path $script:AtlasTestModulesRoot 'Atlas.TasksProcs\Atlas.TasksProcs.psd1') -Force
    Import-Module (Join-Path $script:AtlasTestModulesRoot 'Atlas.Toggles\Atlas.Toggles.psd1') -Force
    $script:TogglesRoot = Join-Path $script:AtlasTestRepoRoot 'playbook\Executables\AtlasModules\Toggles'
    $script:DefinitionPath = Join-Path $script:TogglesRoot 'Advanced\LiteTasks.psd1'
    $script:Lite = Get-AtlasToggleDefinition -Name LiteTasks -TogglesRoot $script:TogglesRoot

    function Get-LiteTaskEntry {
        param([Parameter(Mandatory = $true)][string]$State)
        @($script:Lite['States'][$State]['ScheduledTasks'] | ForEach-Object { [hashtable]$_ })
    }
}

Describe 'LiteTasks toggle definition' {
    It 'passes the toggle definition validator' {
        @(Test-AtlasToggleDefinition -Path $script:DefinitionPath) | Should -BeNullOrEmpty
    }

    It 'records Disable as 0 and Enable as 1, runs as TrustedInstaller and needs no restart' {
        $script:Lite['Elevation'] | Should -Be 'TrustedInstaller'
        $script:Lite['States']['Disable']['StateValue'] | Should -Be 0
        $script:Lite['States']['Enable']['StateValue'] | Should -Be 1
        $script:Lite['States']['Enable']['Launcher'] | Should -BeLike '*(default).cmd'
        foreach ($state in 'Disable', 'Enable') {
            $script:Lite['States'][$state]['Reboot'] | Should -Be 'None'
            $script:Lite['States'][$state].Contains('Registry') | Should -BeFalse
            $script:Lite['States'][$state].Contains('Services') | Should -BeFalse
        }
    }

    It 'changes the same 29 distinct Microsoft tasks in both states with one operation each' {
        $disable = Get-LiteTaskEntry -State Disable
        $enable = Get-LiteTaskEntry -State Enable
        $disable.Count | Should -Be 29
        @($disable | ForEach-Object { $_['Path'] }) | Should -Be @($enable | ForEach-Object { $_['Path'] })
        @($disable | ForEach-Object { $_['Path'] } | Sort-Object -Unique).Count | Should -Be 29
        foreach ($entry in $disable) {
            $entry['Path'] | Should -BeLike '\Microsoft\*'
            $entry['Operation'] | Should -BeExactly 'Disable'
            $entry.ContainsKey('IgnoreErrors') | Should -BeFalse
        }
        foreach ($entry in $enable) { $entry['Operation'] | Should -BeExactly 'Enable' }
    }

    It 'never touches security, update, storage, recovery, time, language, DirectX or search tasks' {
        $protected = @(
            '*\Windows Defender\*', '*\WindowsUpdate\*', '*\UpdateOrchestrator\*', '*\InstallService\*', '*\Hotpatch\*',
            '*\WaaSMedic\*', '*\ExploitGuard\*', '*\AppID\*', '*\BitLocker\*', '*\CertificateServicesClient\*',
            '*\Defrag\*', '*\Chkdsk\*', '*\SystemRestore\*', '*\Registry\RegIdleBackup', '*\Setup\*', '*\Servicing\*',
            '*\DiskCleanup\*', '*\DiskFootprint\StorageSense', '*\Time Synchronization\*', '*\Time Zone\*',
            '*\TextServicesFramework\*', '*\International\*', '*\LanguageComponentsInstaller\*', '*\DirectX\*',
            '*\Shell\IndexerAutomaticMaintenance', '*\FeatureConfig\ReconcileFeatures', '*\FeatureConfig\ReconcileConfigs',
            '*\FeatureConfig\SafeguardsReconciliation', '*\OneSettings\*', '*\Subscription\*', '*\StateRepository\*'
        )
        foreach ($entry in Get-LiteTaskEntry -State Disable) {
            foreach ($pattern in $protected) {
                $entry['Path'] | Should -Not -BeLike $pattern
            }
        }
    }

    It 'does not repeat a task that the Atlas install already disables' {
        $tweaksRoot = Join-Path $script:AtlasTestScriptsRoot 'Tweaks'
        $installed = @(Get-ChildItem -LiteralPath $tweaksRoot -Recurse -Filter '*.psd1' | ForEach-Object {
                $data = Import-PowerShellDataFile -LiteralPath $_.FullName
                if ($data -is [hashtable] -and $data.ContainsKey('ScheduledTasks')) { @($data['ScheduledTasks']) | ForEach-Object { [string]$_['Path'] } }
            })
        $installed.Count | Should -BeGreaterThan 0
        foreach ($entry in Get-LiteTaskEntry -State Disable) {
            $installed | Should -Not -Contain $entry['Path']
        }
    }
}

Describe 'LiteTasks toggle work' {
    It 'applies every declared operation through the Atlas task helpers' {
        Mock Disable-AtlasScheduledTask -ModuleName Atlas.TasksProcs {}
        Mock Enable-AtlasScheduledTask -ModuleName Atlas.TasksProcs {}

        Invoke-AtlasScheduledTaskEntries -Entries (Get-LiteTaskEntry -State Disable)
        Should -Invoke Disable-AtlasScheduledTask -ModuleName Atlas.TasksProcs -Times 29 -Exactly
        Should -Invoke Disable-AtlasScheduledTask -ModuleName Atlas.TasksProcs -Times 1 -Exactly -ParameterFilter {
            $Path -ceq '\Microsoft\Windows\Maintenance\WinSAT'
        }

        Invoke-AtlasScheduledTaskEntries -Entries (Get-LiteTaskEntry -State Enable)
        Should -Invoke Enable-AtlasScheduledTask -ModuleName Atlas.TasksProcs -Times 29 -Exactly
    }

    It 'reports drift until the tasks hold the chosen state, and none for absent tasks' {
        Mock Get-AtlasScheduledTaskState -ModuleName Atlas.TasksProcs { 'Enabled' }
        @(Test-AtlasScheduledTaskEntries -Entries (Get-LiteTaskEntry -State Disable)).Count | Should -Be 29
        @(Test-AtlasScheduledTaskEntries -Entries (Get-LiteTaskEntry -State Enable)) | Should -BeNullOrEmpty

        Mock Get-AtlasScheduledTaskState -ModuleName Atlas.TasksProcs { 'Disabled' }
        @(Test-AtlasScheduledTaskEntries -Entries (Get-LiteTaskEntry -State Disable)) | Should -BeNullOrEmpty

        Mock Get-AtlasScheduledTaskState -ModuleName Atlas.TasksProcs { 'Missing' }
        @(Test-AtlasScheduledTaskEntries -Entries (Get-LiteTaskEntry -State Disable)) | Should -BeNullOrEmpty
        @(Test-AtlasScheduledTaskEntries -Entries (Get-LiteTaskEntry -State Enable)) | Should -BeNullOrEmpty
    }
}

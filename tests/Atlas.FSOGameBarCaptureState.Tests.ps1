BeforeAll {
    . (Join-Path $PSScriptRoot 'AtlasTestHost.ps1')
    Import-Module (Join-Path $script:AtlasTestModulesRoot 'Atlas.Core\Atlas.Core.psd1') -Force
    Import-Module (Join-Path $script:AtlasTestModulesRoot 'Atlas.Toggles\Atlas.Toggles.psd1') -Force
    $script:TogglesRoot = Join-Path $script:AtlasTestRepoRoot 'playbook\Executables\AtlasModules\Toggles'
    $script:DefinitionPath = Join-Path $script:TogglesRoot 'General\FSOGameBar.psd1'
    $script:Definition = Get-AtlasToggleDefinition -Name FSOGameBar -TogglesRoot $script:TogglesRoot

    $script:PresenceWriter = 'HKLM:\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Windows.Gaming.GameBar.PresenceServer.Internal.PresenceWriter|ActivationType'
    $script:GameDvrEnabled = 'HKCU:\System\GameConfigStore|GameDVR_Enabled'
    $script:AppCapture = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR|AppCaptureEnabled'

    # One registry entry per target, as 'Path|Name' => 'Operation:Type:Data'.
    function Get-StateRegistryMap {
        param([Parameter(Mandatory = $true)][string]$State)
        $map = [ordered]@{}
        foreach ($entry in @($script:Definition['States'][$State]['Registry'])) {
            $target = '{0}|{1}' -f $entry['Path'], $entry['Name']
            $operation = if ($entry.Contains('Operation')) { [string]$entry['Operation'] } else { 'Set' }
            $map[$target] = '{0}:{1}:{2}' -f $operation, $entry['Type'], $entry['Data']
        }
        return $map
    }
}

Describe 'FSOGameBar DisableCapture state' {
    It 'passes the toggle definition validator' {
        @(Test-AtlasToggleDefinition -Path $script:DefinitionPath) | Should -BeNullOrEmpty
    }

    It 'adds a third recorded state and leaves the existing states and values alone' {
        @($script:Definition['States'].Keys) | Should -Be @('Disable', 'Enable', 'DisableCapture')
        $script:Definition['States']['Disable']['StateValue'] | Should -Be 0
        $script:Definition['States']['Enable']['StateValue'] | Should -Be 1
        $script:Definition['States']['DisableCapture']['StateValue'] | Should -Be 2
        $script:Definition['States']['Enable']['Launcher'] | Should -BeLike '*(default).cmd'
        $script:Definition['States']['DisableCapture']['Launcher'] | Should -Be '3. General Configuration\FSO and Game Bar\Disable Game Capture Only.cmd'
        $script:Definition['States']['DisableCapture']['Reboot'] | Should -Be 'None'
    }

    It 'is the Enable state with only Game Bar capture and the presence writer turned off' {
        $enable = Get-StateRegistryMap -State Enable
        $capture = Get-StateRegistryMap -State DisableCapture

        @($capture.Keys) | Should -Be @($enable.Keys)
        foreach ($target in $enable.Keys) {
            if ($target -in @($script:PresenceWriter, $script:GameDvrEnabled, $script:AppCapture)) { continue }
            $capture[$target] | Should -Be $enable[$target] -Because "$target keeps its Enable value"
        }
        $capture[$script:PresenceWriter] | Should -Be 'Set:DWord:0'
        $capture[$script:GameDvrEnabled] | Should -Be 'Set:DWord:0'
        $capture[$script:AppCapture] | Should -Be 'Set:DWord:0'
    }

    It 'keeps fullscreen optimizations, the Game DVR policy and the Game Bar package' {
        $capture = Get-StateRegistryMap -State DisableCapture
        $capture['HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment|__COMPAT_LAYER'] | Should -Be 'Delete::'
        $capture['HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR|'] | Should -Be 'DeleteKey::'
        $capture['HKLM:\SOFTWARE\Microsoft\PolicyManager\default\ApplicationManagement\AllowGameDVR|value'] | Should -Be 'Set:DWord:1'

        $state = $script:Definition['States']['DisableCapture']
        $state.Contains('MachineAction') | Should -BeFalse
        $state['UserAction'] | Should -Be 'Install-AtlasGameBarPackage'
    }
}

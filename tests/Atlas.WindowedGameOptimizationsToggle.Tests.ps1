BeforeAll {
    . (Join-Path $PSScriptRoot 'AtlasTestHost.ps1')
    Import-Module (Join-Path $script:AtlasTestModulesRoot 'Atlas.Core\Atlas.Core.psd1') -Force
    Import-Module (Join-Path $script:AtlasTestModulesRoot 'Atlas.Toggles\Atlas.Toggles.psd1') -Force
    $script:TogglesRoot = Join-Path $script:AtlasTestRepoRoot 'playbook\Executables\AtlasModules\Toggles'
    $script:DefinitionPath = Join-Path $script:TogglesRoot 'Gaming\WindowedGameOptimizations.psd1'
    $script:Definition = Get-AtlasToggleDefinition -Name WindowedGameOptimizations -TogglesRoot $script:TogglesRoot

    # The companion only defines functions; load them here to test them directly.
    . (Join-Path $script:TogglesRoot 'Gaming\WindowedGameOptimizations.ps1')
    # The engine runs companion functions under strict mode 3.0.
    Set-StrictMode -Version 3.0

    $script:Key = 'TestRegistry:\UserGpuPreferences'
    function Get-GlobalSetting {
        $item = Get-ItemProperty -LiteralPath $script:Key -ErrorAction SilentlyContinue
        if ($null -eq $item -or $item.PSObject.Properties.Name -notcontains 'DirectXUserGlobalSettings') { return $null }
        return [string]$item.DirectXUserGlobalSettings
    }
}

Describe 'WindowedGameOptimizations toggle definition' {
    It 'passes the toggle definition validator' {
        @(Test-AtlasToggleDefinition -Path $script:DefinitionPath) | Should -BeNullOrEmpty
    }

    It 'records Disable as 0 and Enable as 1, with per-user work only' {
        $script:Definition['Elevation'] | Should -Be 'Admin'
        $script:Definition['States']['Disable']['StateValue'] | Should -Be 0
        $script:Definition['States']['Enable']['StateValue'] | Should -Be 1
        $script:Definition['States']['Disable']['Launcher'] | Should -BeLike '*(default).cmd'
        foreach ($state in 'Disable', 'Enable') {
            $script:Definition['States'][$state].Contains('MachineAction') | Should -BeFalse
            $script:Definition['States'][$state].Contains('Services') | Should -BeFalse
            $script:Definition['States'][$state]['Reboot'] | Should -Be 'None'
        }
    }

    It 'targets the current user DirectX graphics preferences' {
        Get-AtlasDirectXUserSettingsPath | Should -Be 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    }
}

Describe 'DirectXUserGlobalSettings entry editing' {
    It 'adds the entry to an empty or missing string' {
        ConvertTo-AtlasDirectXUserSetting -Current $null -Name SwapEffectUpgradeEnable -Value 1 | Should -BeExactly 'SwapEffectUpgradeEnable=1;'
        ConvertTo-AtlasDirectXUserSetting -Current '' -Name SwapEffectUpgradeEnable -Value 1 | Should -BeExactly 'SwapEffectUpgradeEnable=1;'
    }

    It 'replaces only its own entry and keeps the others in order' {
        $current = 'AutoHDREnable=2097;swapeffectupgradeenable=0;VRROptimizeEnable=1;'
        ConvertTo-AtlasDirectXUserSetting -Current $current -Name SwapEffectUpgradeEnable -Value 1 |
            Should -BeExactly 'AutoHDREnable=2097;VRROptimizeEnable=1;SwapEffectUpgradeEnable=1;'
        ConvertTo-AtlasDirectXUserSetting -Current $current -Name SwapEffectUpgradeEnable -Value $null |
            Should -BeExactly 'AutoHDREnable=2097;VRROptimizeEnable=1;'
    }

    It 'returns an empty string when its entry was the only one' {
        ConvertTo-AtlasDirectXUserSetting -Current 'SwapEffectUpgradeEnable=1;' -Name SwapEffectUpgradeEnable -Value $null | Should -BeExactly ''
        ConvertTo-AtlasDirectXUserSetting -Current ';;' -Name SwapEffectUpgradeEnable -Value $null | Should -BeExactly ''
    }
}

Describe 'WindowedGameOptimizations registry work' {
    BeforeEach {
        Remove-Item -LiteralPath $script:Key -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'enables and then restores a missing value without leaving anything behind' {
        Set-AtlasWindowedGameOptimizationValue -Path $script:Key -Value '1'
        Get-GlobalSetting | Should -BeExactly 'SwapEffectUpgradeEnable=1;'
        Set-AtlasWindowedGameOptimizationValue -Path $script:Key -Value $null
        Get-GlobalSetting | Should -BeNullOrEmpty
        (Get-Item -LiteralPath $script:Key).Property | Should -Not -Contain 'DirectXUserGlobalSettings'
    }

    It 'keeps Auto HDR and variable refresh rate choices through enable and restore' {
        New-Item -Path $script:Key -Force | Out-Null
        New-ItemProperty -LiteralPath $script:Key -Name DirectXUserGlobalSettings -PropertyType String -Value 'AutoHDREnable=2097;VRROptimizeEnable=0;' | Out-Null

        Set-AtlasWindowedGameOptimizationValue -Path $script:Key -Value '1'
        Get-GlobalSetting | Should -BeExactly 'AutoHDREnable=2097;VRROptimizeEnable=0;SwapEffectUpgradeEnable=1;'
        Set-AtlasWindowedGameOptimizationValue -Path $script:Key -Value $null
        Get-GlobalSetting | Should -BeExactly 'AutoHDREnable=2097;VRROptimizeEnable=0;'
    }

    It 'restoring the default never creates the key' {
        Set-AtlasWindowedGameOptimizationValue -Path $script:Key -Value $null
        Test-Path -LiteralPath $script:Key | Should -BeFalse
    }

    It 'runs each state through the shared setter with the current user path' {
        Mock Set-AtlasWindowedGameOptimizationValue {}
        Mock Write-AtlasNote {}
        $toggle = [pscustomobject]@{ Silent = $true }

        Enable-AtlasWindowedGameOptimization -Toggle $toggle
        Should -Invoke Set-AtlasWindowedGameOptimizationValue -Times 1 -Exactly -ParameterFilter {
            $Path -eq 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' -and $Value -eq '1'
        }
        Reset-AtlasWindowedGameOptimization -Toggle $toggle
        Should -Invoke Set-AtlasWindowedGameOptimizationValue -Times 1 -Exactly -ParameterFilter {
            $Path -eq 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' -and [string]::IsNullOrEmpty($Value)
        }
        Should -Invoke Write-AtlasNote -Times 0 -Exactly
    }
}

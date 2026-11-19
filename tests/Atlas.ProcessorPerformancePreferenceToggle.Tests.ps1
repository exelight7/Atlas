BeforeAll {
    . (Join-Path $PSScriptRoot 'AtlasTestHost.ps1')
    Import-Module (Join-Path $script:AtlasTestModulesRoot 'Atlas.Core\Atlas.Core.psd1') -Force
    Import-Module (Join-Path $script:AtlasTestModulesRoot 'Atlas.Toggles\Atlas.Toggles.psd1') -Force
    $script:TogglesRoot = Join-Path $script:AtlasTestRepoRoot 'playbook\Executables\AtlasModules\Toggles'
    $script:DefinitionPath = Join-Path $script:TogglesRoot 'Gaming\ProcessorPerformancePreference.psd1'
    $script:Definition = Get-AtlasToggleDefinition -Name ProcessorPerformancePreference -TogglesRoot $script:TogglesRoot

    # The companion only defines functions; load them here to test them directly.
    . (Join-Path $script:TogglesRoot 'Gaming\ProcessorPerformancePreference.ps1')
    # The engine runs companion functions under strict mode 3.0.
    Set-StrictMode -Version 3.0

    $script:Epp = '36687f9e-e3a5-4dbf-b1dc-15eb381c6863'
    $script:Epp1 = '36687f9e-e3a5-4dbf-b1dc-15eb381c6864'
    $script:Balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
    $script:HighPerformance = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    $script:AtlasPlan = '11111111-1111-1111-1111-111111111111'
    $script:Root = 'TestRegistry:\PowerSettings\54533251-82be-4824-96c1-47b60b740d00'

    function New-SettingDefault {
        param([string]$Setting, [string]$Scheme, [int]$Ac)
        $key = Join-Path (Join-Path (Join-Path $script:Root $Setting) 'DefaultPowerSchemeValues') $Scheme
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -LiteralPath $key -Name AcSettingIndex -PropertyType DWord -Value $Ac -Force | Out-Null
        New-ItemProperty -LiteralPath $key -Name DcSettingIndex -PropertyType DWord -Value 50 -Force | Out-Null
    }

    function New-ToggleContext {
        param([string]$State, [bool]$Silent = $true)
        [pscustomobject]@{ Name = 'ProcessorPerformancePreference'; State = $State; Silent = $Silent; WinDir = 'C:\Windows' }
    }
}

Describe 'ProcessorPerformancePreference toggle definition' {
    It 'passes the toggle definition validator' {
        @(Test-AtlasToggleDefinition -Path $script:DefinitionPath) | Should -BeNullOrEmpty
    }

    It 'is a machine-only administrator toggle that needs no restart' {
        $script:Definition['Elevation'] | Should -Be 'Admin'
        $script:Definition['States']['Disable']['StateValue'] | Should -Be 0
        $script:Definition['States']['Enable']['StateValue'] | Should -Be 1
        $script:Definition['States']['Disable']['Launcher'] | Should -BeLike '*(default).cmd'
        foreach ($state in 'Disable', 'Enable') {
            $script:Definition['States'][$state]['Reboot'] | Should -Be 'None'
            $script:Definition['States'][$state].Contains('UserAction') | Should -BeFalse
            $script:Definition['States'][$state].Contains('Services') | Should -BeFalse
            $script:Definition['States'][$state].Contains('Registry') | Should -BeFalse
        }
    }

    It 'changes only the two EPP settings of the processor subgroup' {
        @(Get-AtlasProcessorPreferenceSetting) | Should -Be @($script:Epp, $script:Epp1)
        Get-AtlasProcessorPowerSettingsRoot | Should -Be 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00'
    }
}

Describe 'Windows default lookup' {
    BeforeEach {
        Remove-Item -LiteralPath 'TestRegistry:\PowerSettings' -Recurse -Force -ErrorAction SilentlyContinue
        New-SettingDefault -Setting $script:Epp -Scheme $script:Balanced -Ac 33
        New-SettingDefault -Setting $script:Epp -Scheme $script:HighPerformance -Ac 0
    }

    It 'uses the active plan''s own default when Windows lists one' {
        Get-AtlasProcessorPreferenceDefault -SettingsRoot $script:Root -Setting $script:Epp -Scheme $script:HighPerformance | Should -Be 0
        Get-AtlasProcessorPreferenceDefault -SettingsRoot $script:Root -Setting $script:Epp -Scheme $script:Balanced | Should -Be 33
    }

    It 'uses Balanced for the Atlas plan and other copies' {
        Get-AtlasProcessorPreferenceDefault -SettingsRoot $script:Root -Setting $script:Epp -Scheme $script:AtlasPlan | Should -Be 33
    }

    It 'refuses to guess when Windows records no default' {
        { Get-AtlasProcessorPreferenceDefault -SettingsRoot $script:Root -Setting $script:Epp1 -Scheme $script:AtlasPlan } |
            Should -Throw '*no default*'
    }

    It 'targets only the EPP settings this Windows defines' {
        @(Get-AtlasProcessorPreferenceTarget -SettingsRoot $script:Root) | Should -Be @($script:Epp)
        Remove-Item -LiteralPath 'TestRegistry:\PowerSettings' -Recurse -Force
        New-Item -Path $script:Root -Force | Out-Null
        { Get-AtlasProcessorPreferenceTarget -SettingsRoot $script:Root } | Should -Throw '*defines no processor energy performance preference*'
    }
}

Describe 'ProcessorPerformancePreference states' {
    BeforeEach {
        Remove-Item -LiteralPath 'TestRegistry:\PowerSettings' -Recurse -Force -ErrorAction SilentlyContinue
        foreach ($setting in $script:Epp, $script:Epp1) {
            New-SettingDefault -Setting $setting -Scheme $script:Balanced -Ac 33
            New-SettingDefault -Setting $setting -Scheme $script:HighPerformance -Ac 0
        }
        $script:Commands = New-Object 'System.Collections.Generic.List[string]'
        Mock Get-AtlasProcessorPowerSettingsRoot { $script:Root }
        Mock Write-AtlasNote {}
        Mock Invoke-AtlasToggleNativeCommand {
            $script:Commands.Add(($ArgumentList -join ' '))
            [pscustomobject]@{ ExitCode = 0; Output = @("Power Scheme GUID: $script:AtlasPlan  (Atlas Power Scheme)") }
        }
    }

    It 'Enable sets both EPP settings to 0 on AC, then reapplies the plan' {
        Enable-AtlasProcessorPerformancePreference -Toggle (New-ToggleContext -State Enable)

        @($script:Commands) | Should -Be @(
            "/setacvalueindex scheme_current sub_processor $script:Epp 0"
            "/setacvalueindex scheme_current sub_processor $script:Epp1 0"
            '/setactive scheme_current'
        )
        Should -Invoke Invoke-AtlasToggleNativeCommand -Times 3 -Exactly -ParameterFilter { $FilePath -eq 'C:\Windows\System32\powercfg.exe' }
        Should -Invoke Write-AtlasNote -Times 0 -Exactly
    }

    It 'Disable restores the Balanced default on the Atlas plan' {
        Reset-AtlasProcessorPerformancePreference -Toggle (New-ToggleContext -State Disable)

        @($script:Commands) | Should -Be @(
            '/getactivescheme'
            "/setacvalueindex scheme_current sub_processor $script:Epp 33"
            "/setacvalueindex scheme_current sub_processor $script:Epp1 33"
            '/setactive scheme_current'
        )
    }

    It 'Disable restores the High performance default when that plan is active' {
        Mock Invoke-AtlasToggleNativeCommand {
            $script:Commands.Add(($ArgumentList -join ' '))
            [pscustomobject]@{ ExitCode = 0; Output = @("Power Scheme GUID: $script:HighPerformance  (High performance)") }
        }
        Reset-AtlasProcessorPerformancePreference -Toggle (New-ToggleContext -State Disable)

        $script:Commands[1] | Should -Be "/setacvalueindex scheme_current sub_processor $script:Epp 0"
    }

    It 'Disable writes nothing when a default is missing' {
        Remove-Item -LiteralPath (Join-Path (Join-Path $script:Root $script:Epp1) 'DefaultPowerSchemeValues') -Recurse -Force

        { Reset-AtlasProcessorPerformancePreference -Toggle (New-ToggleContext -State Disable) } | Should -Throw '*no default*'
        @($script:Commands) | Should -Be @('/getactivescheme')
    }

    It 'refuses an ambiguous active plan' {
        Mock Invoke-AtlasToggleNativeCommand {
            $script:Commands.Add(($ArgumentList -join ' '))
            [pscustomobject]@{ ExitCode = 0; Output = @('no scheme here') }
        }
        { Reset-AtlasProcessorPerformancePreference -Toggle (New-ToggleContext -State Disable) } | Should -Throw '*found 0*'
        @($script:Commands) | Should -Be @('/getactivescheme')
    }
}

@{
    Name        = 'ProcessorPerformancePreference'
    Description = 'exelight7: processor energy performance preference (EPP) of the active power plan on AC power. Enable sets it to 0, the value of the Windows High performance plan, so processors with hardware-controlled performance states (Intel Speed Shift, AMD CPPC) raise their clock as soon as load arrives. Disable restores the Windows default for the active plan (Balanced: 33). Battery (DC) values are not changed; processors without hardware P-states ignore the setting.'
    Elevation   = 'Admin'
    Script      = 'ProcessorPerformancePreference.ps1'
    States      = @(
        @{
            Name          = 'Disable'
            StateValue    = 0
            Launcher      = '3. General Configuration\Gaming\Processor Performance Preference\Use Windows Default Processor Performance Preference (default).cmd'
            Reboot        = 'None'
            MachineAction = 'Reset-AtlasProcessorPerformancePreference'
        }
        @{
            Name          = 'Enable'
            StateValue    = 1
            Launcher      = '3. General Configuration\Gaming\Processor Performance Preference\Enable Processor Performance Preference.cmd'
            Reboot        = 'None'
            MachineAction = 'Enable-AtlasProcessorPerformancePreference'
        }
    )
}

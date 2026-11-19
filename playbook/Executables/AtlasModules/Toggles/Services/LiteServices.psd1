@{
    Name        = 'LiteServices'
    Description = 'exelight7 Lite services: Data Usage, the per-user Connected Devices service and the Xbox Live services.'
    Elevation   = 'Admin'
    Warning     = 'Sets Data Usage and the per-user Connected Devices Platform service to Manual and disables the Xbox Live services. While disabled, the Data usage page and metered-network data limits, Nearby Sharing and cross-device clipboard sync, and Xbox sign-in and cloud saves for Xbox app, Game Pass and Microsoft games are unavailable.'
    States      = @(
        @{
            Name       = 'Disable'
            StateValue = 0
            Launcher   = '6. Advanced Configuration\Services\Lite Services\Disable Lite Services.cmd'
            Reboot     = 'Recommend'
            Services   = @(
                @{ Name = 'DusmSvc'; StartupType = 3; AllowMissing = $true }
                # CDPSvc stays with the PhoneLink toggle: Night Light needs it available.
                @{ Name = 'CDPUserSvc'; StartupType = 3; AllowMissing = $true }
                @{ Name = 'XblAuthManager'; StartupType = 4; AllowMissing = $true }
                @{ Name = 'XblGameSave'; StartupType = 4; AllowMissing = $true }
                @{ Name = 'XboxNetApiSvc'; StartupType = 4; AllowMissing = $true }
            )
        }
        @{
            Name       = 'Enable'
            StateValue = 1
            Launcher   = '6. Advanced Configuration\Services\Lite Services\Enable Lite Services (default).cmd'
            Reboot     = 'Recommend'
            Services   = @(
                @{ Name = 'DusmSvc'; StartupType = 2; AllowMissing = $true }
                @{ Name = 'CDPUserSvc'; StartupType = 2; AllowMissing = $true }
                @{ Name = 'XblAuthManager'; StartupType = 3; AllowMissing = $true }
                @{ Name = 'XblGameSave'; StartupType = 3; AllowMissing = $true }
                @{ Name = 'XboxNetApiSvc'; StartupType = 3; AllowMissing = $true }
            )
        }
    )
}

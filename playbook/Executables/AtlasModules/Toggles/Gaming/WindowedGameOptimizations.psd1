@{
    Name        = 'WindowedGameOptimizations'
    Description = 'exelight7: Optimizations for windowed games (Settings > Display > Graphics), which moves DirectX 10 and 11 games in windowed and borderless mode to the flip presentation model. Enable turns it on for the current user; Disable removes that choice so Windows decides again. Other graphics preferences (Auto HDR, variable refresh rate) are kept.'
    Elevation   = 'Admin'
    Script      = 'WindowedGameOptimizations.ps1'
    States      = @(
        @{
            Name       = 'Disable'
            StateValue = 0
            Launcher   = '3. General Configuration\Gaming\Windowed Game Optimizations\Use Windows Default Windowed Game Optimizations (default).cmd'
            Reboot     = 'None'
            UserAction = 'Reset-AtlasWindowedGameOptimization'
        }
        @{
            Name       = 'Enable'
            StateValue = 1
            Launcher   = '3. General Configuration\Gaming\Windowed Game Optimizations\Enable Windowed Game Optimizations.cmd'
            Reboot     = 'None'
            UserAction = 'Enable-AtlasWindowedGameOptimization'
        }
    )
}

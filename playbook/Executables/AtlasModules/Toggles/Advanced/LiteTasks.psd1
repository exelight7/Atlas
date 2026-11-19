@{
    Name        = 'LiteTasks'
    Description = 'exelight7 Lite scheduled tasks: 29 Microsoft tasks that Atlas leaves on, for telemetry, diagnostics and reports (including the WinSAT benchmark and crash-report upload), features a gaming PC does not use (Work Folders, Family Safety, AD RMS, Maps, printing, media sharing, Xbox cloud saves) and the cloud backup of the app list. Security, update, storage maintenance (TRIM), System Restore, time, language, DirectX and search tasks are not changed.'
    Elevation   = 'TrustedInstaller'
    Warning     = 'While disabled: crash reports are not sent to Microsoft (local reports stay), Task Manager shows no startup impact, recommended troubleshooting does not run automatically, Windows Backup does not save the app list and settings to your account, and Work Folders, Microsoft Family, AD RMS, Maps alerts, printer cleanup, Windows Media sharing and Xbox cloud saves do not run.'
    States      = @(
        @{
            Name           = 'Disable'
            StateValue     = 0
            Launcher       = '6. Advanced Configuration\Lite Tasks\Disable Lite Tasks.cmd'
            Reboot         = 'None'
            ScheduledTasks = @(
                # Telemetry, diagnostics and reports
                @{ Path = '\Microsoft\Windows\Application Experience\MareBackup'; Operation = 'Disable' }
                @{ Path = '\Microsoft\Windows\Application Experience\StartupAppTask'; Operation = 'Disable' }
                @{ Path = '\Microsoft\Windows\Diagnosis\RecommendedTroubleshootingScanner'; Operation = 'Disable' }
                @{ Path = '\Microsoft\Windows\Diagnosis\Scheduled'; Operation = 'Disable' }
                @{ Path = '\Microsoft\Windows\Diagnosis\UnexpectedCodepath'; Operation = 'Disable' }
                @{ Path = '\Microsoft\Windows\DiskFootprint\Diagnostics'; Operation = 'Disable' }
                @{ Path = '\Microsoft\Windows\Flighting\FeatureConfig\GovernedFeatureUsageProcessing'; Operation = 'Disable' }
                @{ Path = '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataFlushing'; Operation = 'Disable' }
                @{ Path = '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReceiver'; Operation = 'Disable' }
                @{ Path = '\Microsoft\Windows\Windows Error Reporting\QueueReporting'; Operation = 'Disable' }
                @{ Path = '\Microsoft\Windows\PerformanceTrace\ShowFeedbackToast'; Operation = 'Disable' }
                @{ Path = '\Microsoft\Windows\PerformanceTrace\WhesvcToast'; Operation = 'Disable' }
                @{ Path = '\Microsoft\Windows\Sustainability\SustainabilityTelemetry'; Operation = 'Disable' }
                @{ Path = '\Microsoft\Windows\Sustainability\PowerGridForecastTask'; Operation = 'Disable' }
                @{ Path = '\Microsoft\Windows\Maintenance\WinSAT'; Operation = 'Disable' }
                # Features not used on a gaming PC
                @{ Path = '\Microsoft\Windows\Maps\MapsToastTask'; Operation = 'Disable' }
                @{ Path = '\Microsoft\Windows\Shell\FamilySafetyMonitor'; Operation = 'Disable' }
                @{ Path = '\Microsoft\Windows\Shell\FamilySafetyRefreshTask'; Operation = 'Disable' }
                @{ Path = '\Microsoft\Windows\Work Folders\Work Folders Logon Synchronization'; Operation = 'Disable' }
                @{ Path = '\Microsoft\Windows\Work Folders\Work Folders Maintenance Work'; Operation = 'Disable' }
                @{ Path = '\Microsoft\Windows\Active Directory Rights Management Services Client\AD RMS Rights Policy Template Management (Manual)'; Operation = 'Disable' }
                @{ Path = '\Microsoft\Windows\Printing\EduPrintProv'; Operation = 'Disable' }
                @{ Path = '\Microsoft\Windows\Printing\PrinterCleanupTask'; Operation = 'Disable' }
                @{ Path = '\Microsoft\Windows\Windows Media Sharing\UpdateLibrary'; Operation = 'Disable' }
                @{ Path = '\Microsoft\XblGameSave\XblGameSaveTask'; Operation = 'Disable' }
                @{ Path = '\Microsoft\Windows\AccountHealth\RecoverabilityToastTask'; Operation = 'Disable' }
                # Cloud backup of the app list and settings
                @{ Path = '\Microsoft\Windows\AppListBackup\Backup'; Operation = 'Disable' }
                @{ Path = '\Microsoft\Windows\AppListBackup\BackupNonMaintenance'; Operation = 'Disable' }
                @{ Path = '\Microsoft\Windows\CloudRestore\Backup'; Operation = 'Disable' }
            )
        }
        @{
            Name           = 'Enable'
            StateValue     = 1
            Launcher       = '6. Advanced Configuration\Lite Tasks\Enable Lite Tasks (default).cmd'
            Reboot         = 'None'
            ScheduledTasks = @(
                # Telemetry, diagnostics and reports
                @{ Path = '\Microsoft\Windows\Application Experience\MareBackup'; Operation = 'Enable' }
                @{ Path = '\Microsoft\Windows\Application Experience\StartupAppTask'; Operation = 'Enable' }
                @{ Path = '\Microsoft\Windows\Diagnosis\RecommendedTroubleshootingScanner'; Operation = 'Enable' }
                @{ Path = '\Microsoft\Windows\Diagnosis\Scheduled'; Operation = 'Enable' }
                @{ Path = '\Microsoft\Windows\Diagnosis\UnexpectedCodepath'; Operation = 'Enable' }
                @{ Path = '\Microsoft\Windows\DiskFootprint\Diagnostics'; Operation = 'Enable' }
                @{ Path = '\Microsoft\Windows\Flighting\FeatureConfig\GovernedFeatureUsageProcessing'; Operation = 'Enable' }
                @{ Path = '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataFlushing'; Operation = 'Enable' }
                @{ Path = '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReceiver'; Operation = 'Enable' }
                @{ Path = '\Microsoft\Windows\Windows Error Reporting\QueueReporting'; Operation = 'Enable' }
                @{ Path = '\Microsoft\Windows\PerformanceTrace\ShowFeedbackToast'; Operation = 'Enable' }
                @{ Path = '\Microsoft\Windows\PerformanceTrace\WhesvcToast'; Operation = 'Enable' }
                @{ Path = '\Microsoft\Windows\Sustainability\SustainabilityTelemetry'; Operation = 'Enable' }
                @{ Path = '\Microsoft\Windows\Sustainability\PowerGridForecastTask'; Operation = 'Enable' }
                @{ Path = '\Microsoft\Windows\Maintenance\WinSAT'; Operation = 'Enable' }
                # Features not used on a gaming PC
                @{ Path = '\Microsoft\Windows\Maps\MapsToastTask'; Operation = 'Enable' }
                @{ Path = '\Microsoft\Windows\Shell\FamilySafetyMonitor'; Operation = 'Enable' }
                @{ Path = '\Microsoft\Windows\Shell\FamilySafetyRefreshTask'; Operation = 'Enable' }
                @{ Path = '\Microsoft\Windows\Work Folders\Work Folders Logon Synchronization'; Operation = 'Enable' }
                @{ Path = '\Microsoft\Windows\Work Folders\Work Folders Maintenance Work'; Operation = 'Enable' }
                @{ Path = '\Microsoft\Windows\Active Directory Rights Management Services Client\AD RMS Rights Policy Template Management (Manual)'; Operation = 'Enable' }
                @{ Path = '\Microsoft\Windows\Printing\EduPrintProv'; Operation = 'Enable' }
                @{ Path = '\Microsoft\Windows\Printing\PrinterCleanupTask'; Operation = 'Enable' }
                @{ Path = '\Microsoft\Windows\Windows Media Sharing\UpdateLibrary'; Operation = 'Enable' }
                @{ Path = '\Microsoft\XblGameSave\XblGameSaveTask'; Operation = 'Enable' }
                @{ Path = '\Microsoft\Windows\AccountHealth\RecoverabilityToastTask'; Operation = 'Enable' }
                # Cloud backup of the app list and settings
                @{ Path = '\Microsoft\Windows\AppListBackup\Backup'; Operation = 'Enable' }
                @{ Path = '\Microsoft\Windows\AppListBackup\BackupNonMaintenance'; Operation = 'Enable' }
                @{ Path = '\Microsoft\Windows\CloudRestore\Backup'; Operation = 'Enable' }
            )
        }
    )
}

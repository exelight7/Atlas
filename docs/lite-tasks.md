# exelight7 Lite scheduled tasks (`LiteTasks`)

`Toggles\Advanced\LiteTasks.psd1` is an opt-in toggle. It turns off 29 Microsoft
scheduled tasks that the Atlas install leaves on. It runs as TrustedInstaller because
Administrators cannot change `Printing\PrinterCleanupTask`. Each state lists the same
tasks, so `Enable Lite Tasks (default).cmd` turns all of them back on. All 29 are on by
default in Windows. A task missing on an edition or build is skipped with a warning,
both when the state is applied and when drift is checked. No restart is needed.

Launchers: `AtlasDesktop\6. Advanced Configuration\Lite Tasks\`.

## Tasks and what turning them off costs

| Task (`\Microsoft\Windows\` unless shown) | What is lost while disabled |
| --- | --- |
| `Application Experience\MareBackup` | Nothing visible (compatibility telemetry backup). |
| `Application Experience\StartupAppTask` | Task Manager's Startup impact column shows "Not measured". |
| `Diagnosis\RecommendedTroubleshootingScanner`, `Diagnosis\Scheduled` | Recommended troubleshooting no longer runs automatically; manual troubleshooters still work. |
| `Diagnosis\UnexpectedCodepath` | Nothing visible (diagnostic configuration). |
| `DiskFootprint\Diagnostics` | Nothing visible (disk usage telemetry). Storage Sense is a separate task and stays on. |
| `Flighting\FeatureConfig\GovernedFeatureUsageProcessing`, `UsageDataFlushing`, `UsageDataReceiver` | Nothing visible (feature usage reporting). The feature and safeguard reconciliation tasks stay on. |
| `Windows Error Reporting\QueueReporting` | Queued crash reports are not sent to Microsoft. Local reports stay. |
| `PerformanceTrace\ShowFeedbackToast`, `PerformanceTrace\WhesvcToast` | Feedback and Windows Health notifications. |
| `Sustainability\SustainabilityTelemetry`, `Sustainability\PowerGridForecastTask` | Carbon-aware scheduling of Windows Update. |
| `Maintenance\WinSAT` | The WinSAT assessment, which runs a disk and graphics benchmark during maintenance. |
| `Maps\MapsToastTask` | Maps notifications. |
| `Shell\FamilySafetyMonitor`, `Shell\FamilySafetyRefreshTask` | Microsoft Family parental controls on this PC. |
| `Work Folders\Work Folders Logon Synchronization`, `Work Folders Maintenance Work` | Work Folders sync (a workplace feature). Both run at every sign-in. |
| `Active Directory Rights Management Services Client\AD RMS Rights Policy Template Management (Manual)` | AD RMS protected documents (a workplace feature). |
| `Printing\EduPrintProv`, `Printing\PrinterCleanupTask` | School printer provisioning and printer cleanup. |
| `Windows Media Sharing\UpdateLibrary` | Windows Media library sharing on the network. |
| `\Microsoft\XblGameSave\XblGameSaveTask` | Xbox cloud saves (see also `LiteServices`). |
| `AccountHealth\RecoverabilityToastTask` | Reminders to add recovery information to a Microsoft account. |
| `AppListBackup\Backup`, `AppListBackup\BackupNonMaintenance`, `CloudRestore\Backup` | Windows Backup no longer saves the app list and settings to the Microsoft account for restore on a new PC. File History and restore points are not affected. |

## Not changed

These tasks are never part of the list:

| Area | Tasks left alone |
| --- | --- |
| Security | Defender, Exploit Guard, AppID, BitLocker, certificate services |
| Updates | Windows Update, Store updates, hotpatch, feature and safeguard reconciliation, OneSettings |
| Storage and recovery | `Defrag\ScheduledDefrag` (TRIM for SSDs), Chkdsk, System Restore, registry backup, setup and servicing, Storage Sense and Silent Cleanup |
| Time | Time synchronization and time zone (anti-cheat and TLS need the correct time) |
| Language and input | Text Services Framework, language settings and components |
| Games | DirectX adapter cache and database updater |
| Search | Indexer maintenance |
| Owned by another toggle | `Sysmain\*` (SuperFetch) and `DUSM\dusmtask` (`LiteServices`) |
| Third party | Tasks from other publishers (AMD, browsers, updaters) |

The list also never repeats a task that the Atlas install already disables.

## Measuring

`Measure-AtlasPerformance` reports `tasks.enabled` and `tasks.ranLast24h`, the number of
tasks whose last run falls in the previous 24 hours. Measure before the change, disable
the tasks, use the PC normally for a day, then measure again. On the reference machine
the before values were 138 enabled and 69 run in 24 hours, and 12 of those 69 runs were
tasks on this list.

BeforeAll {
    . (Join-Path $PSScriptRoot 'AtlasTestHost.ps1')
    $script:MeasureScript = Join-Path $script:AtlasTestRepoRoot 'tools\dev\Measure-AtlasPerformance.ps1'
    . $script:MeasureScript
}

Describe 'Measure-AtlasPerformance pure helpers' {
    It 'reads the Task Manager startup state from the first StartupApproved byte' {
        Test-StartupApprovedEnabled -Data $null | Should -BeTrue
        Test-StartupApprovedEnabled -Data ([byte[]]@()) | Should -BeTrue
        Test-StartupApprovedEnabled -Data ([byte[]]@(2, 0, 0)) | Should -BeTrue
        Test-StartupApprovedEnabled -Data ([byte[]]@(6, 0, 0)) | Should -BeTrue
        Test-StartupApprovedEnabled -Data ([byte[]]@(3, 0, 0)) | Should -BeFalse
        Test-StartupApprovedEnabled -Data ([byte[]]@(7, 0, 0)) | Should -BeFalse
    }

    It 'parses the active scheme GUID and name from powercfg output in any language' {
        $english = ConvertFrom-PowerCfgActiveScheme -Line @('Power Scheme GUID: 381B4222-F694-41F0-9685-FF5BB260DF2E  (Balanced)')
        $english.guid | Should -Be '381b4222-f694-41f0-9685-ff5bb260df2e'
        $english.name | Should -Be 'Balanced'

        $german = ConvertFrom-PowerCfgActiveScheme -Line @('GUID des Energieschemas: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (Hoechstleistung)')
        $german.guid | Should -Be '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
        $german.name | Should -Be 'Hoechstleistung'

        (ConvertFrom-PowerCfgActiveScheme -Line @('GUID: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c')).name | Should -BeNullOrEmpty
        { ConvertFrom-PowerCfgActiveScheme -Line @('no scheme here') } | Should -Throw
    }

    It 'reads boot timings from an Event 100 document' {
        $xml = [xml]@'
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
  <System><TimeCreated SystemTime="2026-11-19T08:00:00.000Z" /></System>
  <EventData>
    <Data Name="BootTime">21450</Data>
    <Data Name="MainPathBootTime">9870</Data>
    <Data Name="BootPostBootTime">11580</Data>
    <Data Name="BootIsDegradation">false</Data>
  </EventData>
</Event>
'@
        $boot = ConvertFrom-BootPerformanceEvent -EventXml $xml
        $boot.bootTimeMs | Should -Be 21450
        $boot.mainPathBootTimeMs | Should -Be 9870
        $boot.postBootTimeMs | Should -Be 11580
        $boot.isDegraded | Should -BeFalse
        $boot.timeCreated | Should -Be '2026-11-19T08:00:00.000Z'
    }

    It 'leaves a missing boot timing null' {
        $xml = [xml]'<Event><System><TimeCreated SystemTime="x" /></System><EventData><Data Name="BootTime">100</Data></EventData></Event>'
        $boot = ConvertFrom-BootPerformanceEvent -EventXml $xml
        $boot.bootTimeMs | Should -Be 100
        $boot.mainPathBootTimeMs | Should -BeNullOrEmpty
        $boot.isDegraded | Should -BeNullOrEmpty
    }

    It 'averages memory samples into megabytes' {
        $sample = {
            param($Available, $Cpu)
            [pscustomobject]@{
                TotalBytes = 8GB; AvailableBytes = $Available; CommittedBytes = 4GB; CommitLimitBytes = 12GB
                CacheBytes = 1GB; PagedPoolBytes = 256MB; NonPagedPoolBytes = 128MB; CpuPercent = $Cpu
            }
        }
        $summary = Get-MemorySummary -Sample @((& $sample 6GB 2), (& $sample 4GB 4))
        $summary.sampleCount | Should -Be 2
        $summary.totalMB | Should -Be 8192
        $summary.availableMB | Should -Be 5120
        $summary.inUseMB | Should -Be 3072
        $summary.inUsePercent | Should -Be 37.5
        $summary.commitMB | Should -Be 4096
        $summary.nonPagedPoolMB | Should -Be 128
        $summary.cpuPercent | Should -Be 3
    }

    It 'groups processes by name and sums their counters' {
        $process = @(
            [pscustomobject]@{ Name = 'a.exe'; WorkingSetSize = 100MB; PrivatePageCount = 50MB; ThreadCount = 10; HandleCount = 100 }
            [pscustomobject]@{ Name = 'a.exe'; WorkingSetSize = 100MB; PrivatePageCount = 50MB; ThreadCount = 5; HandleCount = 50 }
            [pscustomobject]@{ Name = 'b.exe'; WorkingSetSize = 300MB; PrivatePageCount = 10MB; ThreadCount = 1; HandleCount = 10 }
        )
        $summary = Get-ProcessSummary -Process $process -Top 1
        $summary.processCount | Should -Be 3
        $summary.threadCount | Should -Be 16
        $summary.handleCount | Should -Be 160
        $summary.distinctNames | Should -Be 2
        @($summary.top).Count | Should -Be 1
        $summary.top[0].name | Should -Be 'b.exe'
    }

    It 'counts running, automatic, delayed and manual-running services' {
        $service = @(
            [pscustomobject]@{ Name = 'B'; State = 'Running'; StartMode = 'Auto'; DelayedAutoStart = $true }
            [pscustomobject]@{ Name = 'A'; State = 'Running'; StartMode = 'Manual'; DelayedAutoStart = $false }
            [pscustomobject]@{ Name = 'C'; State = 'Stopped'; StartMode = 'Auto'; DelayedAutoStart = $false }
            [pscustomobject]@{ Name = 'D'; State = 'Stopped'; StartMode = 'Disabled'; DelayedAutoStart = $false }
        )
        $summary = Get-ServiceSummary -Service $service
        $summary.total | Should -Be 4
        $summary.running | Should -Be 2
        $summary.automatic | Should -Be 2
        $summary.automaticDelayed | Should -Be 1
        $summary.manualRunning | Should -Be 1
        $summary.disabled | Should -Be 1
        @($summary.runningList | ForEach-Object { $_.name }) | Should -Be @('A', 'B')
    }

    It 'separates enabled Microsoft tasks from the others' {
        $task = @(
            [pscustomobject]@{ TaskPath = '\Microsoft\Windows\X\'; TaskName = 'One'; State = 'Ready' }
            [pscustomobject]@{ TaskPath = '\'; TaskName = 'Vendor'; State = 'Running' }
            [pscustomobject]@{ TaskPath = '\Microsoft\Windows\Y\'; TaskName = 'Off'; State = 'Disabled' }
        )
        $summary = Get-TaskSummary -Task $task
        $summary.total | Should -Be 3
        $summary.enabled | Should -Be 2
        $summary.ready | Should -Be 1
        $summary.running | Should -Be 1
        $summary.enabledMicrosoft | Should -Be 1
        $summary.enabledOther | Should -Be 1
        $summary.enabledList | Should -Be @('\Microsoft\Windows\X\One', '\Vendor')
    }

    It 'records a failing section and returns null' {
        $errors = [ordered]@{}
        Invoke-MeasureSection -Name 'broken' -Errors $errors -Collector { throw 'denied' } | Should -BeNullOrEmpty
        $errors['broken'] | Should -Be 'denied'
        Invoke-MeasureSection -Name 'fine' -Errors $errors -Collector { 42 } | Should -Be 42
        $errors.Contains('fine') | Should -BeFalse
    }

    It 'reads the installed version and options from the state document' {
        $path = Join-Path $TestDrive 'state.json'
        Set-Content -LiteralPath $path -Value '{"installedVersion":"0.6.0","installedAt":"t","options":["a","b"]}'
        $state = Get-AtlasStateSummary -Path $path
        $state.installedVersion | Should -Be '0.6.0'
        $state.options | Should -Be @('a', 'b')

        Get-AtlasStateSummary -Path (Join-Path $TestDrive 'missing.json') | Should -BeNullOrEmpty
        Set-Content -LiteralPath $path -Value 'not json'
        Get-AtlasStateSummary -Path $path | Should -BeNullOrEmpty
    }
}

Describe 'Measure-AtlasPerformance document' {
    It 'writes a JSON document with every section and changes nothing' {
        $output = Join-Path $TestDrive 'perf.json'
        & $script:MeasureScript -OutputPath $output -SampleCount 1 -BootEventCount 1 -TopProcessCount 3

        $document = [IO.File]::ReadAllText($output) | ConvertFrom-Json
        $document.schemaVersion | Should -Be 1
        foreach ($section in 'os', 'memory', 'processes', 'services', 'tasks', 'startup', 'boot', 'timer', 'power', 'gaming', 'appx', 'errors') {
            $document.PSObject.Properties.Name | Should -Contain $section
        }
        $document.memory.totalMB | Should -BeGreaterThan 0
        $document.processes.processCount | Should -BeGreaterThan 0
        $document.services.running | Should -BeGreaterThan 0
        $document.timer.currentMs | Should -BeGreaterThan 0
        $document.power.guid | Should -Match '^[0-9a-f-]{36}$'
    }
}

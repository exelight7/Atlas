<#
.SYNOPSIS
    Measures this machine's idle footprint and gaming-related settings and writes one
    JSON document, so that a tweak can be compared before and after it is applied.
.DESCRIPTION
    It reads only; it changes nothing. Run it unelevated or elevated. Some sources need
    elevation (the boot-performance log on some machines); a section that cannot be read
    records its error in 'errors' and the rest of the document is still written.

    Measure the same way each time: after a restart, signed in, with the same apps open,
    and after the machine has been idle for a few minutes. The document records the
    uptime so a sample taken too early can be recognised.

    Sections:
      os          edition, build and revision, uptime, elevation
      memory      averaged samples: in use, available, commit charge, cache, pools, CPU
      processes   process, thread and handle counts, the largest processes by name
      services    running, automatic and delayed services, and the running list
      tasks       enabled and ready scheduled tasks, and the enabled list
      startup     Run keys and Startup folders with their Task Manager enabled state
      boot        the last boot-performance events (Event 100)
      timer       the current, minimum and maximum system timer resolution
      power       the active power scheme
      gaming      Game Mode, GPU scheduling, Game DVR, mouse acceleration, VBS
      appx        installed package counts for the current user
.EXAMPLE
    .\tools\dev\Measure-AtlasPerformance.ps1 -OutputPath perf-before.json
.EXAMPLE
    .\tools\dev\Measure-AtlasPerformance.ps1 -SampleCount 10 -SampleIntervalSeconds 3
#>
[CmdletBinding()]
param(
    # Where to write the JSON document. Without it the document goes to the output stream.
    [string]$OutputPath,

    # Memory and CPU samples to average.
    [ValidateRange(1, 120)]
    [int]$SampleCount = 5,

    [ValidateRange(1, 60)]
    [int]$SampleIntervalSeconds = 2,

    # Uptime below this marks the sample as taken before the machine settled.
    [ValidateRange(0, 86400)]
    [int]$SettledUptimeSeconds = 300,

    [ValidateRange(1, 50)]
    [int]$TopProcessCount = 20,

    [ValidateRange(1, 50)]
    [int]$BootEventCount = 5
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$script:SchemaVersion = 1

function Invoke-MeasureSection {
    <# Runs one collector; a failure is recorded in Errors and the section is null. #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Collector,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Errors
    )

    try {
        return (& $Collector)
    } catch {
        $Errors[$Name] = $_.Exception.Message
        return $null
    }
}

function ConvertTo-Megabyte {
    param([double]$Bytes)
    return [math]::Round($Bytes / 1MB, 1)
}

function Get-AverageValue {
    param([double[]]$Value)
    if (-not $Value -or $Value.Count -eq 0) { return $null }
    return [math]::Round((($Value | Measure-Object -Average).Average), 1)
}

function Get-MemorySummary {
    <# Averages memory samples. Each sample has bytes for TotalBytes, AvailableBytes,
       CommittedBytes, CommitLimitBytes, CacheBytes, PagedPoolBytes, NonPagedPoolBytes
       and a CpuPercent value. #>
    param([Parameter(Mandatory = $true)][object[]]$Sample)

    $total = [double]$Sample[0].TotalBytes
    $available = Get-AverageValue -Value @($Sample | ForEach-Object { [double]$_.AvailableBytes })
    $committed = Get-AverageValue -Value @($Sample | ForEach-Object { [double]$_.CommittedBytes })

    return [ordered]@{
        sampleCount = $Sample.Count
        totalMB = ConvertTo-Megabyte $total
        inUseMB = ConvertTo-Megabyte ($total - $available)
        availableMB = ConvertTo-Megabyte $available
        inUsePercent = if ($total -gt 0) { [math]::Round((($total - $available) / $total) * 100, 1) } else { $null }
        commitMB = ConvertTo-Megabyte $committed
        commitLimitMB = ConvertTo-Megabyte (Get-AverageValue -Value @($Sample | ForEach-Object { [double]$_.CommitLimitBytes }))
        cacheMB = ConvertTo-Megabyte (Get-AverageValue -Value @($Sample | ForEach-Object { [double]$_.CacheBytes }))
        pagedPoolMB = ConvertTo-Megabyte (Get-AverageValue -Value @($Sample | ForEach-Object { [double]$_.PagedPoolBytes }))
        nonPagedPoolMB = ConvertTo-Megabyte (Get-AverageValue -Value @($Sample | ForEach-Object { [double]$_.NonPagedPoolBytes }))
        cpuPercent = Get-AverageValue -Value @($Sample | ForEach-Object { [double]$_.CpuPercent })
    }
}

function Get-MemorySample {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $memory = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Memory
    $cpu = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'"
    return [pscustomobject]@{
        TotalBytes = [double]$os.TotalVisibleMemorySize * 1KB
        AvailableBytes = [double]$memory.AvailableBytes
        CommittedBytes = [double]$memory.CommittedBytes
        CommitLimitBytes = [double]$memory.CommitLimit
        CacheBytes = [double]$memory.CacheBytes
        PagedPoolBytes = [double]$memory.PoolPagedBytes
        NonPagedPoolBytes = [double]$memory.PoolNonpagedBytes
        CpuPercent = [double]$cpu.PercentProcessorTime
    }
}

function Get-ProcessSummary {
    <# Process objects need Name, WorkingSetSize, PrivatePageCount, ThreadCount and
       HandleCount, as Win32_Process has them. #>
    param(
        [Parameter(Mandatory = $true)][object[]]$Process,
        [int]$Top = 20
    )

    $groups = @($Process | Group-Object -Property Name | ForEach-Object {
            $workingSet = ($_.Group | Measure-Object -Property WorkingSetSize -Sum).Sum
            $private = ($_.Group | Measure-Object -Property PrivatePageCount -Sum).Sum
            [pscustomobject]@{
                name = $_.Name
                count = $_.Count
                workingSetMB = ConvertTo-Megabyte $workingSet
                privateMB = ConvertTo-Megabyte $private
            }
        } | Sort-Object -Property workingSetMB -Descending)

    return [ordered]@{
        processCount = $Process.Count
        threadCount = [int](($Process | Measure-Object -Property ThreadCount -Sum).Sum)
        handleCount = [int](($Process | Measure-Object -Property HandleCount -Sum).Sum)
        distinctNames = $groups.Count
        top = @($groups | Select-Object -First $Top)
    }
}

function Get-ServiceSummary {
    <# Service objects need Name, State, StartMode and DelayedAutoStart, as Win32_Service
       has them. #>
    param([Parameter(Mandatory = $true)][object[]]$Service)

    $running = @($Service | Where-Object { $_.State -eq 'Running' })
    $automatic = @($Service | Where-Object { $_.StartMode -eq 'Auto' })
    $delayed = @($automatic | Where-Object { $_.PSObject.Properties['DelayedAutoStart'] -and $_.DelayedAutoStart })

    return [ordered]@{
        total = $Service.Count
        running = $running.Count
        automatic = $automatic.Count
        automaticDelayed = $delayed.Count
        manualRunning = @($running | Where-Object { $_.StartMode -eq 'Manual' }).Count
        disabled = @($Service | Where-Object { $_.StartMode -eq 'Disabled' }).Count
        runningList = @($running | Sort-Object -Property Name | ForEach-Object {
                [ordered]@{ name = $_.Name; startMode = $_.StartMode }
            })
    }
}

function Get-TaskSummary {
    <# Task objects need TaskPath, TaskName and State, as Get-ScheduledTask returns them. #>
    param([Parameter(Mandatory = $true)][object[]]$Task)

    $enabled = @($Task | Where-Object { [string]$_.State -ne 'Disabled' })
    $microsoft = @($enabled | Where-Object { $_.TaskPath -like '\Microsoft\*' })

    return [ordered]@{
        total = $Task.Count
        enabled = $enabled.Count
        ready = @($Task | Where-Object { [string]$_.State -eq 'Ready' }).Count
        running = @($Task | Where-Object { [string]$_.State -eq 'Running' }).Count
        enabledMicrosoft = $microsoft.Count
        enabledOther = $enabled.Count - $microsoft.Count
        enabledList = @($enabled | ForEach-Object { '{0}{1}' -f $_.TaskPath, $_.TaskName } | Sort-Object)
    }
}

function Test-StartupApprovedEnabled {
    <# Task Manager records a startup entry's state in StartupApproved as binary data whose
       first byte has bit 0 set when the entry is disabled (0x03, 0x07) and clear when it is
       enabled (0x02, 0x06). No value means enabled. #>
    param([byte[]]$Data)

    if ($null -eq $Data -or $Data.Length -eq 0) { return $true }
    return (($Data[0] -band 1) -eq 0)
}

function Get-StartupApprovedData {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $item = Get-ItemProperty -LiteralPath $Key -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    return [byte[]]$item.$Name
}

function Get-StartupEntry {
    $approvedRoot = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    $sources = @(
        @{ Scope = 'User'; Kind = 'Run'; Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Approved = "HKCU:\$approvedRoot\Run" }
        @{ Scope = 'Machine'; Kind = 'Run'; Key = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'; Approved = "HKLM:\$approvedRoot\Run" }
        @{ Scope = 'Machine'; Kind = 'Run32'; Key = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = "HKLM:\$approvedRoot\Run32" }
    )

    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($source in $sources) {
        if (-not (Test-Path -LiteralPath $source.Key)) { continue }
        $key = Get-Item -LiteralPath $source.Key
        foreach ($name in $key.GetValueNames()) {
            if ([string]::IsNullOrEmpty($name)) { continue }
            $entries.Add([ordered]@{
                    name = $name
                    scope = $source.Scope
                    kind = $source.Kind
                    command = [string]$key.GetValue($name)
                    enabled = Test-StartupApprovedEnabled -Data (Get-StartupApprovedData -Key $source.Approved -Name $name)
                })
        }
    }

    $folders = @(
        @{ Scope = 'User'; Path = [Environment]::GetFolderPath('Startup'); Approved = "HKCU:\$approvedRoot\StartupFolder" }
        @{ Scope = 'Machine'; Path = [Environment]::GetFolderPath('CommonStartup'); Approved = "HKLM:\$approvedRoot\StartupFolder" }
    )
    foreach ($folder in $folders) {
        if ([string]::IsNullOrEmpty($folder.Path) -or -not (Test-Path -LiteralPath $folder.Path)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $folder.Path -File -Force | Where-Object { $_.Name -ne 'desktop.ini' }) {
            $entries.Add([ordered]@{
                    name = $file.Name
                    scope = $folder.Scope
                    kind = 'StartupFolder'
                    command = $file.FullName
                    enabled = Test-StartupApprovedEnabled -Data (Get-StartupApprovedData -Key $folder.Approved -Name $file.Name)
                })
        }
    }

    $list = $entries.ToArray()
    return [ordered]@{
        total = $list.Count
        enabled = @($list | Where-Object { $_.enabled }).Count
        entries = $list
    }
}

function ConvertFrom-BootPerformanceEvent {
    <# Reads the timings from a Diagnostics-Performance Event 100 XML document. #>
    param([Parameter(Mandatory = $true)][xml]$EventXml)

    $data = @{}
    foreach ($node in $EventXml.Event.EventData.Data) { $data[$node.Name] = $node.'#text' }

    $read = {
        param($Name)
        if ($data.ContainsKey($Name) -and -not [string]::IsNullOrEmpty($data[$Name])) { return [long]$data[$Name] }
        return $null
    }

    return [ordered]@{
        timeCreated = [string]$EventXml.Event.System.TimeCreated.SystemTime
        bootTimeMs = & $read 'BootTime'
        mainPathBootTimeMs = & $read 'MainPathBootTime'
        postBootTimeMs = & $read 'BootPostBootTime'
        isDegraded = if ($data.ContainsKey('BootIsDegradation')) { $data['BootIsDegradation'] -eq 'true' } else { $null }
    }
}

function Get-BootPerformance {
    param([int]$Count = 5)

    $logName = 'Microsoft-Windows-Diagnostics-Performance/Operational'
    $identity = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        # Unelevated, Windows PowerShell reports this access-denied log as having no events.
        throw "Reading $logName needs an elevated PowerShell."
    }

    $events = @(Get-WinEvent -FilterHashtable @{ LogName = $logName; Id = 100 } -MaxEvents $Count -ErrorAction SilentlyContinue)

    return @($events | ForEach-Object { ConvertFrom-BootPerformanceEvent -EventXml ([xml]$_.ToXml()) })
}

function Get-TimerResolution {
    if (-not ('AtlasPerf.NtTimer' -as [type])) {
        Add-Type -Namespace AtlasPerf -Name NtTimer -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("ntdll.dll")]
public static extern int NtQueryTimerResolution(out uint MinimumResolution, out uint MaximumResolution, out uint CurrentResolution);
'@
    }

    [uint32]$minimum = 0
    [uint32]$maximum = 0
    [uint32]$current = 0
    $status = [AtlasPerf.NtTimer]::NtQueryTimerResolution([ref]$minimum, [ref]$maximum, [ref]$current)
    if ($status -ne 0) { throw ('NtQueryTimerResolution returned 0x{0:X8}.' -f $status) }

    # The values are in 100 ns units. 'Minimum' is the coarsest interval, 'Maximum' the finest.
    return [ordered]@{
        currentMs = [math]::Round($current / 10000.0, 4)
        coarsestMs = [math]::Round($minimum / 10000.0, 4)
        finestMs = [math]::Round($maximum / 10000.0, 4)
    }
}

function ConvertFrom-PowerCfgActiveScheme {
    <# Parses 'powercfg /getactivescheme' output. The GUID is language-independent; the
       name is the text in parentheses. #>
    param([string[]]$Line)

    $text = ($Line -join ' ')
    $match = [regex]::Match($text, '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s*\(([^)]*)\)')
    if (-not $match.Success) {
        $guidOnly = [regex]::Match($text, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
        if (-not $guidOnly.Success) { throw "No power scheme GUID in: $text" }
        return [ordered]@{ guid = $guidOnly.Value.ToLowerInvariant(); name = $null }
    }
    return [ordered]@{ guid = $match.Groups[1].Value.ToLowerInvariant(); name = $match.Groups[2].Value.Trim() }
}

function Get-RegistryValueOrNull {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    return $item.$Name
}

function Get-GamingContext {
    $deviceGuard = $null
    try {
        $deviceGuard = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop
    } catch {
        $deviceGuard = $null
    }

    return [ordered]@{
        autoGameModeEnabled = Get-RegistryValueOrNull -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled'
        hwSchMode = Get-RegistryValueOrNull -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode'
        gameDvrEnabled = Get-RegistryValueOrNull -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled'
        appCaptureEnabled = Get-RegistryValueOrNull -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'AppCaptureEnabled'
        directXUserGlobalSettings = Get-RegistryValueOrNull -Path 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' -Name 'DirectXUserGlobalSettings'
        mouseSpeed = Get-RegistryValueOrNull -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed'
        mouseThreshold1 = Get-RegistryValueOrNull -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold1'
        mouseThreshold2 = Get-RegistryValueOrNull -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold2'
        networkThrottlingIndex = Get-RegistryValueOrNull -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'NetworkThrottlingIndex'
        systemResponsiveness = Get-RegistryValueOrNull -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'SystemResponsiveness'
        vbsStatus = if ($deviceGuard) { [int]$deviceGuard.VirtualizationBasedSecurityStatus } else { $null }
        securityServicesRunning = if ($deviceGuard) { @($deviceGuard.SecurityServicesRunning | ForEach-Object { [int]$_ }) } else { $null }
    }
}

function Get-OsContext {
    param([int]$SettledUptime)

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $version = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $uptime = [int]((Get-Date) - $os.LastBootUpTime).TotalSeconds
    $identity = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()

    return [ordered]@{
        caption = $os.Caption
        displayVersion = Get-RegistryValueOrNull -Path $version -Name 'DisplayVersion'
        build = '{0}.{1}' -f (Get-RegistryValueOrNull -Path $version -Name 'CurrentBuild'), (Get-RegistryValueOrNull -Path $version -Name 'UBR')
        lastBoot = $os.LastBootUpTime.ToString('o')
        uptimeSeconds = $uptime
        settled = $uptime -ge $SettledUptime
        elevated = $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        logicalProcessors = [int]$env:NUMBER_OF_PROCESSORS
        atlas = Get-AtlasStateSummary -Path (Join-Path $env:SystemRoot 'AtlasOS\state.json')
    }
}

function Get-AtlasStateSummary {
    <# The installed version and install options from the Atlas state document, or null
       when Atlas is not installed or the document cannot be read. #>
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $state = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
    } catch {
        return $null
    }
    $read = {
        param($Name)
        if ($state.PSObject.Properties[$Name]) { return $state.$Name }
        return $null
    }
    return [ordered]@{
        installedVersion = & $read 'installedVersion'
        installedAt = & $read 'installedAt'
        options = @(& $read 'options')
    }
}

function Get-AppxSummary {
    $packages = @(Get-AppxPackage)
    return [ordered]@{
        total = $packages.Count
        nonFramework = @($packages | Where-Object { -not $_.IsFramework }).Count
        names = @($packages | Where-Object { -not $_.IsFramework } | ForEach-Object { $_.Name } | Sort-Object -Unique)
    }
}

if ($MyInvocation.InvocationName -eq '.') { return }

# The collectors below are script blocks; they read the parameters from here.
$run = @{
    SampleCount = $SampleCount
    SampleIntervalSeconds = $SampleIntervalSeconds
    SettledUptimeSeconds = $SettledUptimeSeconds
    TopProcessCount = $TopProcessCount
    BootEventCount = $BootEventCount
}

$errors = [ordered]@{}
$document = [ordered]@{
    schemaVersion = $script:SchemaVersion
    tool = 'Measure-AtlasPerformance'
    collectedAt = (Get-Date).ToString('o')
}

$document.os = Invoke-MeasureSection -Name 'os' -Errors $errors -Collector { Get-OsContext -SettledUptime $run.SettledUptimeSeconds }
$document.memory = Invoke-MeasureSection -Name 'memory' -Errors $errors -Collector {
    $samples = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $run.SampleCount; $i++) {
        if ($i -gt 0) { Start-Sleep -Seconds $run.SampleIntervalSeconds }
        $samples.Add((Get-MemorySample))
    }
    Get-MemorySummary -Sample $samples.ToArray()
}
$document.processes = Invoke-MeasureSection -Name 'processes' -Errors $errors -Collector {
    Get-ProcessSummary -Process @(Get-CimInstance -ClassName Win32_Process) -Top $run.TopProcessCount
}
$document.services = Invoke-MeasureSection -Name 'services' -Errors $errors -Collector {
    Get-ServiceSummary -Service @(Get-CimInstance -ClassName Win32_Service)
}
$document.tasks = Invoke-MeasureSection -Name 'tasks' -Errors $errors -Collector { Get-TaskSummary -Task @(Get-ScheduledTask) }
$document.startup = Invoke-MeasureSection -Name 'startup' -Errors $errors -Collector { Get-StartupEntry }
$document.boot = Invoke-MeasureSection -Name 'boot' -Errors $errors -Collector { Get-BootPerformance -Count $run.BootEventCount }
$document.timer = Invoke-MeasureSection -Name 'timer' -Errors $errors -Collector { Get-TimerResolution }
$document.power = Invoke-MeasureSection -Name 'power' -Errors $errors -Collector {
    $output = @(& powercfg.exe /getactivescheme 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0) { throw "powercfg exited with $LASTEXITCODE." }
    ConvertFrom-PowerCfgActiveScheme -Line $output
}
$document.gaming = Invoke-MeasureSection -Name 'gaming' -Errors $errors -Collector { Get-GamingContext }
$document.appx = Invoke-MeasureSection -Name 'appx' -Errors $errors -Collector { Get-AppxSummary }
$document.errors = $errors

$json = $document | ConvertTo-Json -Depth 8
if ($OutputPath) {
    $directory = Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Verbose "Wrote $OutputPath"
} else {
    $json
}

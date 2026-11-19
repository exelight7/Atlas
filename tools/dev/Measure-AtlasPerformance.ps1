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
                  use, and processor performance (% of base clock) and frequency
      processes   process, thread and handle counts, the largest processes by name
      services    running, automatic and delayed services, and the running list
      tasks       enabled and ready scheduled tasks, and the enabled list
      startup     Run keys and Startup folders with their Task Manager enabled state
      boot        the last boot-performance events (Event 100)
      timer       the current, minimum and maximum system timer resolution
      power       the active power scheme and its AC processor settings (EPP, min/max
                  state, boost mode, core parking, idle disable)
      gaming      Game Mode, the HwSchMode value, Game DVR, mouse acceleration, VBS
      gpuScheduling  per-adapter hardware GPU scheduling support and state (D3DKMT)
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
        cpuPerformancePercent = Get-OptionalAverage -Sample $Sample -Name 'CpuPerformancePercent'
        processorFrequencyMHz = Get-OptionalAverage -Sample $Sample -Name 'ProcessorFrequencyMHz'
    }
}

function Get-OptionalAverage {
    <# Averages one sample property that a sample may lack or hold as null; null when no
       sample has it. #>
    param(
        [Parameter(Mandatory = $true)][object[]]$Sample,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $values = @($Sample | Where-Object {
            $_.PSObject.Properties.Name -contains $Name -and $null -ne $_.$Name
        } | ForEach-Object { [double]$_.$Name })
    if ($values.Count -eq 0) { return $null }
    return Get-AverageValue -Value $values
}

function Get-MemorySample {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $memory = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Memory
    $cpu = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'"
    # % Processor Performance is the clock relative to the base frequency (above 100 while
    # boosting); it shows how a power plan lets the processor ramp.
    $performance = Get-CimInstance -ClassName Win32_PerfFormattedData_Counters_ProcessorInformation `
        -Filter "Name='_Total'" -ErrorAction SilentlyContinue
    return [pscustomobject]@{
        TotalBytes = [double]$os.TotalVisibleMemorySize * 1KB
        AvailableBytes = [double]$memory.AvailableBytes
        CommittedBytes = [double]$memory.CommittedBytes
        CommitLimitBytes = [double]$memory.CommitLimit
        CacheBytes = [double]$memory.CacheBytes
        PagedPoolBytes = [double]$memory.PoolPagedBytes
        NonPagedPoolBytes = [double]$memory.PoolNonpagedBytes
        CpuPercent = [double]$cpu.PercentProcessorTime
        CpuPerformancePercent = if ($performance) { [double]$performance.PercentProcessorPerformance } else { $null }
        ProcessorFrequencyMHz = if ($performance) { [double]$performance.ProcessorFrequency } else { $null }
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

function Get-ProcessorPowerPolicy {
    <# Reads the AC processor power settings of one plan through PowerReadACValueIndex,
       which returns the effective value whether or not the plan stores it explicitly.
       A setting this Windows does not define is null. #>
    param([Parameter(Mandatory = $true)][string]$Scheme)

    if (-not ('AtlasPerf.PowerPolicy' -as [type])) {
        Add-Type -Namespace AtlasPerf -Name PowerPolicy -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("powrprof.dll")]
public static extern uint PowerReadACValueIndex(System.IntPtr RootPowerKey, ref System.Guid SchemeGuid, ref System.Guid SubGroupOfPowerSettingsGuid, ref System.Guid PowerSettingGuid, out uint AcValueIndex);
'@
    }

    $processor = [guid]'54533251-82be-4824-96c1-47b60b740d00'
    $settings = [ordered]@{
        minStateAc = '893dee8e-2bef-41e0-89c6-b55d0929964c'
        maxStateAc = 'bc5038f7-23e0-4960-96da-33abaf5935ec'
        eppAc = '36687f9e-e3a5-4dbf-b1dc-15eb381c6863'
        epp1Ac = '36687f9e-e3a5-4dbf-b1dc-15eb381c6864'
        boostModeAc = 'be337238-0d82-4146-a960-4f3749d470c7'
        coreParkingMinAc = '0cc5b647-c1df-4637-891a-dec35c318583'
        idleDisableAc = '5d76a2ca-e8c0-402f-a133-2158492d58ad'
    }
    $schemeGuid = [guid]$Scheme
    $result = [ordered]@{}
    foreach ($name in $settings.Keys) {
        $settingGuid = [guid]$settings[$name]
        [uint32]$value = 0
        $status = [AtlasPerf.PowerPolicy]::PowerReadACValueIndex([IntPtr]::Zero, [ref]$schemeGuid, [ref]$processor, [ref]$settingGuid, [ref]$value)
        $result[$name] = if ($status -eq 0) { [int]$value } else { $null }
    }
    return $result
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

function ConvertFrom-GpuSchedulingCapability {
    <# Decodes D3DKMT_WDDM_2_7_CAPS: bit 0 HwSchSupported, bit 1 HwSchEnabled,
       bit 2 HwSchEnabledByDefault, bit 3 IndependentVidPnVSyncControl. #>
    param([Parameter(Mandatory = $true)][uint32]$Value)

    return [ordered]@{
        supported = [bool]($Value -band 1)
        enabled = [bool]($Value -band 2)
        enabledByDefault = [bool]($Value -band 4)
        independentVidPnVSyncControl = [bool]($Value -band 8)
        raw = ('0x{0:X8}' -f $Value)
    }
}

function Get-GpuSchedulingAdapter {
    <# Reads each display adapter's hardware GPU scheduling capability through D3DKMT
       (read-only queries; adapter handles are closed again). #>
    if (-not ('AtlasPerf.GpuScheduling' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace AtlasPerf
{
    public sealed class GpuAdapterCaps
    {
        public string Name;
        public uint LuidLow;
        public int LuidHigh;
        public int Status;
        public uint Caps;
    }

    public static class GpuScheduling
    {
        [StructLayout(LayoutKind.Sequential)] struct Luid { public uint Low; public int High; }
        [StructLayout(LayoutKind.Sequential)] struct AdapterInfo { public uint Handle; public Luid AdapterLuid; public uint NumOfSources; public int PrecisePresentRegionsPreferred; }
        [StructLayout(LayoutKind.Sequential)] struct EnumAdapters2 { public uint NumAdapters; public IntPtr Adapters; }
        [StructLayout(LayoutKind.Sequential)] struct QueryAdapterInfo { public uint Handle; public int Type; public IntPtr Data; public uint DataSize; }
        [StructLayout(LayoutKind.Sequential)] struct CloseAdapter { public uint Handle; }

        [DllImport("gdi32.dll")] static extern int D3DKMTEnumAdapters2(ref EnumAdapters2 data);
        [DllImport("gdi32.dll")] static extern int D3DKMTQueryAdapterInfo(ref QueryAdapterInfo data);
        [DllImport("gdi32.dll")] static extern int D3DKMTCloseAdapter(ref CloseAdapter data);

        const int AdapterRegistryInfo = 8;   // KMTQAITYPE_ADAPTERREGISTRYINFO
        const int Wddm27Caps = 70;           // KMTQAITYPE_WDDM_2_7_CAPS

        public static GpuAdapterCaps[] Query()
        {
            EnumAdapters2 enumeration = new EnumAdapters2();
            int status = D3DKMTEnumAdapters2(ref enumeration);
            if (status != 0) { throw new InvalidOperationException(String.Format("D3DKMTEnumAdapters2 returned 0x{0:X8}.", status)); }
            int size = Marshal.SizeOf(typeof(AdapterInfo));
            enumeration.Adapters = Marshal.AllocHGlobal(size * (int)Math.Max(enumeration.NumAdapters, 1u));
            try
            {
                status = D3DKMTEnumAdapters2(ref enumeration);
                if (status != 0) { throw new InvalidOperationException(String.Format("D3DKMTEnumAdapters2 returned 0x{0:X8}.", status)); }
                List<GpuAdapterCaps> result = new List<GpuAdapterCaps>();
                for (int i = 0; i < enumeration.NumAdapters; i++)
                {
                    AdapterInfo adapter = (AdapterInfo)Marshal.PtrToStructure(new IntPtr(enumeration.Adapters.ToInt64() + (long)i * size), typeof(AdapterInfo));
                    GpuAdapterCaps caps = new GpuAdapterCaps();
                    caps.LuidLow = adapter.AdapterLuid.Low;
                    caps.LuidHigh = adapter.AdapterLuid.High;
                    try
                    {
                        int nameSize = 4 * 260 * 2;
                        IntPtr name = Marshal.AllocHGlobal(nameSize);
                        try
                        {
                            QueryAdapterInfo query = new QueryAdapterInfo { Handle = adapter.Handle, Type = AdapterRegistryInfo, Data = name, DataSize = (uint)nameSize };
                            if (D3DKMTQueryAdapterInfo(ref query) == 0) { caps.Name = Marshal.PtrToStringUni(name); }
                        }
                        finally { Marshal.FreeHGlobal(name); }

                        IntPtr value = Marshal.AllocHGlobal(4);
                        try
                        {
                            Marshal.WriteInt32(value, 0);
                            QueryAdapterInfo query = new QueryAdapterInfo { Handle = adapter.Handle, Type = Wddm27Caps, Data = value, DataSize = 4 };
                            caps.Status = D3DKMTQueryAdapterInfo(ref query);
                            caps.Caps = (uint)Marshal.ReadInt32(value);
                        }
                        finally { Marshal.FreeHGlobal(value); }
                    }
                    finally
                    {
                        CloseAdapter close = new CloseAdapter { Handle = adapter.Handle };
                        D3DKMTCloseAdapter(ref close);
                    }
                    result.Add(caps);
                }
                return result.ToArray();
            }
            finally { Marshal.FreeHGlobal(enumeration.Adapters); }
        }
    }
}
'@
    }

    return @([AtlasPerf.GpuScheduling]::Query())
}

function Get-GpuSchedulingSummary {
    <# Builds the gpuScheduling section from adapter readings; an adapter whose caps
       query failed is reported with its status and no capability flags. #>
    param([AllowEmptyCollection()][object[]]$Adapter = @())

    $adapters = New-Object System.Collections.Generic.List[object]
    foreach ($item in $Adapter) {
        $entry = [ordered]@{
            name = if ([string]::IsNullOrEmpty([string]$item.Name)) { $null } else { [string]$item.Name }
            luid = ('{0:X8}:{1:X8}' -f [int]$item.LuidHigh, [uint32]$item.LuidLow)
            queryStatus = ('0x{0:X8}' -f [int]$item.Status)
        }
        if ([int]$item.Status -eq 0) {
            $decoded = ConvertFrom-GpuSchedulingCapability -Value ([uint32]$item.Caps)
            foreach ($key in $decoded.Keys) { $entry[$key] = $decoded[$key] }
        }
        $adapters.Add([pscustomobject]$entry)
    }
    $list = $adapters.ToArray()
    return [ordered]@{
        anySupported = [bool](@($list | Where-Object { $_.PSObject.Properties.Name -contains 'supported' -and $_.supported }).Count)
        anyEnabled = [bool](@($list | Where-Object { $_.PSObject.Properties.Name -contains 'enabled' -and $_.enabled }).Count)
        hwSchMode = Get-RegistryValueOrNull -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode'
        adapters = $list
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
    $scheme = ConvertFrom-PowerCfgActiveScheme -Line $output
    $scheme['processor'] = Get-ProcessorPowerPolicy -Scheme $scheme.guid
    $scheme
}
$document.gaming = Invoke-MeasureSection -Name 'gaming' -Errors $errors -Collector { Get-GamingContext }
$document.gpuScheduling = Invoke-MeasureSection -Name 'gpuScheduling' -Errors $errors -Collector {
    Get-GpuSchedulingSummary -Adapter (Get-GpuSchedulingAdapter)
}
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

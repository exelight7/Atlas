# Energy performance preference (EPP) is a per-plan processor power setting. Windows
# keeps one for every processor and a second one (PERFEPP1) for the efficiency class
# of hybrid processors; both are set together on AC power only. PowerSaving applies a
# recorded choice again after it switches or rebuilds the plan.

function Get-AtlasProcessorPreferenceSetting {
    return @(
        '36687f9e-e3a5-4dbf-b1dc-15eb381c6863'   # PERFEPP
        '36687f9e-e3a5-4dbf-b1dc-15eb381c6864'   # PERFEPP1 (processor power efficiency class 1)
    )
}

function Get-AtlasProcessorPowerSettingsRoot {
    return 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00'
}

function Get-AtlasProcessorPreferenceActiveScheme {
    param([Parameter(Mandatory = $true)][string]$PowerCfgPath)

    $output = (Invoke-AtlasToggleNativeCommand -FilePath $PowerCfgPath `
            -ArgumentList ([string[]]@('/getactivescheme')) -AllowedExitCodes ([int[]]@(0)) -PassThru).Output
    $guids = @([regex]::Matches((@($output) -join "`n"),
            '(?i)(?<![0-9a-f])[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}(?![0-9a-f])') |
        ForEach-Object { $_.Value.ToLowerInvariant() } | Sort-Object -Unique)
    if ($guids.Count -ne 1) {
        throw "Expected one active power-scheme GUID, found $($guids.Count)."
    }
    return $guids[0]
}

function Get-AtlasProcessorPreferenceDefault {
    <#
    .SYNOPSIS
        Returns the Windows default AC value of one EPP setting for a plan: that plan's
        own default when Windows lists one, otherwise Balanced's, because Atlas and
        user plans are copies of a Windows plan. Throws when neither is recorded.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$SettingsRoot,
        [Parameter(Mandatory = $true)][string]$Setting,
        [Parameter(Mandatory = $true)][string]$Scheme
    )

    $defaults = Join-Path (Join-Path $SettingsRoot $Setting) 'DefaultPowerSchemeValues'
    foreach ($candidate in @($Scheme, '381b4222-f694-41f0-9685-ff5bb260df2e') | Select-Object -Unique) {
        $key = Join-Path $defaults $candidate
        if (-not (Test-Path -LiteralPath $key)) { continue }
        $item = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
        if ($item.PSObject.Properties.Name -contains 'AcSettingIndex') {
            return [int]$item.AcSettingIndex
        }
    }
    throw "Windows records no default for processor power setting $Setting."
}

function Get-AtlasProcessorPreferenceTarget {
    <# Returns the EPP settings this version of Windows defines, in a fixed order. #>
    param([Parameter(Mandatory = $true)][string]$SettingsRoot)

    $targets = @(Get-AtlasProcessorPreferenceSetting | Where-Object {
            Test-Path -LiteralPath (Join-Path $SettingsRoot $_)
        })
    if ($targets.Count -eq 0) {
        throw 'This version of Windows defines no processor energy performance preference setting.'
    }
    return $targets
}

function Set-AtlasProcessorPreferenceValue {
    <#
    .SYNOPSIS
        Writes the given AC value of each EPP setting to the active plan, then makes
        the plan current again so the change takes effect.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$PowerCfgPath,
        [Parameter(Mandatory = $true)][System.Collections.Specialized.OrderedDictionary]$Value
    )

    foreach ($setting in $Value.Keys) {
        Invoke-AtlasToggleNativeCommand -FilePath $PowerCfgPath `
            -ArgumentList ([string[]]@('/setacvalueindex', 'scheme_current', 'sub_processor', [string]$setting, [string][int]$Value[$setting])) `
            -AllowedExitCodes ([int[]]@(0)) | Out-Null
    }
    Invoke-AtlasToggleNativeCommand -FilePath $PowerCfgPath `
        -ArgumentList ([string[]]@('/setactive', 'scheme_current')) -AllowedExitCodes ([int[]]@(0)) | Out-Null
}

function Enable-AtlasProcessorPerformancePreference {
    param($Toggle)

    $value = [ordered]@{}
    foreach ($setting in Get-AtlasProcessorPreferenceTarget -SettingsRoot (Get-AtlasProcessorPowerSettingsRoot)) {
        $value[$setting] = 0
    }
    if (-not $Toggle.Silent) {
        Write-AtlasNote -Text 'On AC power the processor now prefers performance, which can raise power use and heat a little.'
    }
    Set-AtlasProcessorPreferenceValue -PowerCfgPath "$($Toggle.WinDir)\System32\powercfg.exe" -Value $value
}

function Reset-AtlasProcessorPerformancePreference {
    param($Toggle)

    $powerCfg = "$($Toggle.WinDir)\System32\powercfg.exe"
    $root = Get-AtlasProcessorPowerSettingsRoot
    $scheme = Get-AtlasProcessorPreferenceActiveScheme -PowerCfgPath $powerCfg
    # Every default is read before anything is written, so a missing one changes nothing.
    $value = [ordered]@{}
    foreach ($setting in Get-AtlasProcessorPreferenceTarget -SettingsRoot $root) {
        $value[$setting] = Get-AtlasProcessorPreferenceDefault -SettingsRoot $root -Setting $setting -Scheme $scheme
    }
    Set-AtlasProcessorPreferenceValue -PowerCfgPath $powerCfg -Value $value
}

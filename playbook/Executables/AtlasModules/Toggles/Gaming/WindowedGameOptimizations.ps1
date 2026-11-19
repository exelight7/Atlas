# Optimizations for windowed games is one entry, SwapEffectUpgradeEnable, inside the
# DirectXUserGlobalSettings string that Settings > Display > Graphics also uses for Auto
# HDR and variable refresh rate ("Name=Value;Name=Value;"). A declarative Registry entry
# would replace the whole string, so these functions change only that one entry.

function Get-AtlasDirectXUserSettingsPath {
    return 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
}

function ConvertTo-AtlasDirectXUserSetting {
    <#
    .SYNOPSIS
        Returns a DirectXUserGlobalSettings string with one entry set or removed and every
        other entry kept in order; an empty string when no entries remain.
    #>
    param(
        [AllowNull()][AllowEmptyString()][string]$Current,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()][string]$Value
    )

    $entries = New-Object System.Collections.Generic.List[string]
    foreach ($entry in ([string]$Current).Split(';')) {
        $entry = $entry.Trim()
        if ($entry.Length -eq 0) { continue }
        $entryName = $entry.Split('=')[0].Trim()
        if ([string]::Equals($entryName, $Name, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $entries.Add($entry)
    }
    if (-not [string]::IsNullOrEmpty($Value)) {
        $entries.Add("$Name=$Value")
    }
    if ($entries.Count -eq 0) {
        return ''
    }
    return (($entries.ToArray()) -join ';') + ';'
}

function Set-AtlasWindowedGameOptimizationValue {
    <#
    .SYNOPSIS
        Sets SwapEffectUpgradeEnable to the given value, or removes it when Value is
        empty, leaving the rest of DirectXUserGlobalSettings unchanged.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowNull()][string]$Value
    )

    $valueName = 'DirectXUserGlobalSettings'
    $current = $null
    if (Test-Path -LiteralPath $Path) {
        $item = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
        if ($item.PSObject.Properties.Name -contains $valueName) {
            $current = [string]$item.$valueName
        }
    }
    $updated = ConvertTo-AtlasDirectXUserSetting -Current $current -Name 'SwapEffectUpgradeEnable' -Value $Value
    if ($updated.Length -eq 0) {
        if (-not [string]::IsNullOrEmpty($current)) {
            Remove-ItemProperty -LiteralPath $Path -Name $valueName -ErrorAction Stop
        }
        return
    }
    if ($updated -ceq $current) {
        return
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
    }
    New-ItemProperty -LiteralPath $Path -Name $valueName -PropertyType String -Value $updated -Force -ErrorAction Stop | Out-Null
}

function Enable-AtlasWindowedGameOptimization {
    param($Toggle)

    Set-AtlasWindowedGameOptimizationValue -Path (Get-AtlasDirectXUserSettingsPath) -Value '1'
    if (-not $Toggle.Silent) {
        Write-AtlasNote -Text 'Restart any game that is open for the change to apply to it.'
    }
}

function Reset-AtlasWindowedGameOptimization {
    param($Toggle)

    Set-AtlasWindowedGameOptimizationValue -Path (Get-AtlasDirectXUserSettingsPath) -Value $null
    if (-not $Toggle.Silent) {
        Write-AtlasNote -Text 'Restart any game that is open for the change to apply to it.'
    }
}

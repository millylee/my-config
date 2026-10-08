#Requires -Version 5.1
Set-StrictMode -Version Latest

$script:ExplorerAdvancedPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$script:ClassicMenuClsidPath = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'
$script:ClassicMenuServerPath = Join-Path $script:ClassicMenuClsidPath 'InprocServer32'

function Assert-WindowsShellPlatform {
    if ($env:OS -ne 'Windows_NT') {
        throw 'Windows Shell preferences are only available on Windows.'
    }
}

function Get-WindowsBuildNumber {
    Assert-WindowsShellPlatform
    $currentVersion = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    $build = if ($currentVersion.CurrentBuildNumber) { $currentVersion.CurrentBuildNumber } else { $currentVersion.CurrentBuild }
    return [int]$build
}

function Get-WindowsShellPreferenceDefinitions {
    return @{
        FileExtensions = @{
            Path = $script:ExplorerAdvancedPath; ValueName = 'HideFileExt'; Values = @{ Show = 0; Hide = 1 }
        }
        HiddenItems = @{
            Path = $script:ExplorerAdvancedPath; ValueName = 'Hidden'; Values = @{ Show = 1; Hide = 2 }
        }
        ExplorerStart = @{
            Path = $script:ExplorerAdvancedPath; ValueName = 'LaunchTo'; Values = @{ ThisPC = 1; Home = 2 }
        }
        ExplorerSpacing = @{
            Path = $script:ExplorerAdvancedPath; ValueName = 'UseCompactMode'; Values = @{ Comfortable = 0; Compact = 1 }
        }
        TaskbarAlignment = @{
            Path = $script:ExplorerAdvancedPath; ValueName = 'TaskbarAl'; Values = @{ Left = 0; Center = 1 }
        }
        Widgets = @{
            Path = $script:ExplorerAdvancedPath; ValueName = 'TaskbarDa'; Values = @{ Hide = 0; Show = 1 }
        }
        TaskView = @{
            Path = $script:ExplorerAdvancedPath; ValueName = 'ShowTaskViewButton'; Values = @{ Hide = 0; Show = 1 }
        }
        TaskbarCombine = @{
            Path = $script:ExplorerAdvancedPath; ValueName = 'TaskbarGlomLevel'; Values = @{ Always = 0; WhenFull = 1; Never = 2 }
        }
    }
}

function Get-RegistryDword {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $property = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    if (-not $property) { return $null }
    return [int]$property.$Name
}

function Set-RegistryDword {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Value
    )
    $current = Get-RegistryDword -Path $Path -Name $Name
    if ($null -ne $current -and $current -eq $Value) { return 'Skipped' }
    if ($PSCmdlet.ShouldProcess("$Path\\$Name", "Set DWORD value to $Value")) {
        New-Item -Path $Path -Force | Out-Null
        New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
        return 'Changed'
    }
    return 'WhatIf'
}

function Get-ClassicContextMenuEnabled {
    Assert-WindowsShellPlatform
    if (-not (Test-Path -LiteralPath $script:ClassicMenuServerPath)) { return $false }
    $key = Get-Item -LiteralPath $script:ClassicMenuServerPath -ErrorAction SilentlyContinue
    if (-not $key) { return $false }
    return ($null -ne $key.GetValue('', $null))
}

function Set-WindowsContextMenuStyle {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Parameter(Mandatory)][ValidateSet('Windows10', 'Windows11')][string]$Style)

    Assert-WindowsShellPlatform
    $build = Get-WindowsBuildNumber
    if ($build -lt 22000) {
        if ($Style -eq 'Windows10') { return 'Skipped' }
        throw 'The Windows 11 context menu is not available on Windows 10.'
    }

    $classicEnabled = Get-ClassicContextMenuEnabled
    if ($Style -eq 'Windows10') {
        if ($classicEnabled) { return 'Skipped' }
        if ($PSCmdlet.ShouldProcess('Current user', 'Enable the Windows 10-style classic context menu')) {
            New-Item -Path $script:ClassicMenuServerPath -Force | Out-Null
            Set-Item -LiteralPath $script:ClassicMenuServerPath -Value '' -Force
            return 'Changed'
        }
        return 'WhatIf'
    }

    if (-not (Test-Path -LiteralPath $script:ClassicMenuClsidPath)) { return 'Skipped' }
    if ($PSCmdlet.ShouldProcess('Current user', 'Restore the native Windows 11 context menu')) {
        Remove-Item -LiteralPath $script:ClassicMenuClsidPath -Recurse -Force
        return 'Changed'
    }
    return 'WhatIf'
}

function Set-WindowsShellPreference {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('FileExtensions', 'HiddenItems', 'ExplorerStart', 'ExplorerSpacing', 'TaskbarAlignment', 'Widgets', 'TaskView', 'TaskbarCombine')][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )

    Assert-WindowsShellPlatform
    $definitions = Get-WindowsShellPreferenceDefinitions
    $definition = $definitions[$Name]
    if (-not $definition.Values.ContainsKey($Value)) {
        $allowed = @($definition.Values.Keys | Sort-Object) -join ', '
        throw "Invalid value '$Value' for $Name. Allowed values: $allowed"
    }
    if ($Name -in @('TaskbarAlignment', 'Widgets') -and (Get-WindowsBuildNumber) -lt 22000) {
        throw "$Name is only supported on Windows 11."
    }

    return Set-RegistryDword -Path $definition.Path -Name $definition.ValueName -Value $definition.Values[$Value] -WhatIf:$WhatIfPreference -Confirm:$false
}

function Get-WindowsShellState {
    Assert-WindowsShellPlatform
    $definitions = Get-WindowsShellPreferenceDefinitions
    $state = [ordered]@{
        WindowsBuild = Get-WindowsBuildNumber
        ContextMenu = if (Get-ClassicContextMenuEnabled) { 'Windows10' } else { 'Windows11' }
    }
    foreach ($name in $definitions.Keys | Sort-Object) {
        $definition = $definitions[$name]
        $raw = Get-RegistryDword -Path $definition.Path -Name $definition.ValueName
        $label = $null
        foreach ($candidate in $definition.Values.GetEnumerator()) {
            if ($null -ne $raw -and $candidate.Value -eq $raw) { $label = $candidate.Key; break }
        }
        $state[$name] = if ($label) { $label } else { "SystemDefault ($raw)" }
    }
    return [pscustomobject]$state
}

function Restart-WindowsExplorer {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param()
    Assert-WindowsShellPlatform
    if ($PSCmdlet.ShouldProcess('Windows Explorer', 'Restart the desktop shell')) {
        Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Milliseconds 750
        if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) {
            Start-Process explorer.exe
        }
        return 'Restarted'
    }
    return 'WhatIf'
}

Export-ModuleMember -Function `
    Assert-WindowsShellPlatform,
    Get-WindowsBuildNumber,
    Get-WindowsShellPreferenceDefinitions,
    Get-RegistryDword,
    Set-RegistryDword,
    Get-ClassicContextMenuEnabled,
    Set-WindowsContextMenuStyle,
    Set-WindowsShellPreference,
    Get-WindowsShellState,
    Restart-WindowsExplorer

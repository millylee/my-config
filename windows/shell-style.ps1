#Requires -Version 5.1
<#
.SYNOPSIS
    Configure reversible per-user Windows Explorer and taskbar preferences.
.EXAMPLE
    ./windows/shell-style.ps1 -ContextMenu Windows10 -RestartExplorer
.EXAMPLE
    ./windows/shell-style.ps1 -ContextMenu Windows11 -RestartExplorer
.EXAMPLE
    ./windows/shell-style.ps1 -FileExtensions Show -HiddenItems Show -ExplorerStart ThisPC
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Windows10', 'Windows11')][string]$ContextMenu,
    [ValidateSet('Show', 'Hide')][string]$FileExtensions,
    [ValidateSet('Show', 'Hide')][string]$HiddenItems,
    [ValidateSet('Home', 'ThisPC')][string]$ExplorerStart,
    [ValidateSet('Compact', 'Comfortable')][string]$ExplorerSpacing,
    [ValidateSet('Left', 'Center')][string]$TaskbarAlignment,
    [ValidateSet('Show', 'Hide')][string]$Widgets,
    [ValidateSet('Show', 'Hide')][string]$TaskView,
    [ValidateSet('Always', 'WhenFull', 'Never')][string]$TaskbarCombine,
    [switch]$RestartExplorer,
    [switch]$Status
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/WindowsShell.psm1'
Import-Module $modulePath -Force

$requested = [ordered]@{
    FileExtensions  = $FileExtensions
    HiddenItems     = $HiddenItems
    ExplorerStart   = $ExplorerStart
    ExplorerSpacing = $ExplorerSpacing
    TaskbarAlignment = $TaskbarAlignment
    Widgets         = $Widgets
    TaskView        = $TaskView
    TaskbarCombine  = $TaskbarCombine
}

$hasChanges = [bool]$ContextMenu
foreach ($entry in $requested.GetEnumerator()) {
    if ($entry.Value) { $hasChanges = $true; break }
}

if ($ContextMenu) {
    $result = Set-WindowsContextMenuStyle -Style $ContextMenu -WhatIf:$WhatIfPreference -Confirm:$false
    Write-Host "[$result] ContextMenu -> $ContextMenu"
    if ($ContextMenu -eq 'Windows10') {
        Write-Warning 'Classic context menu mode is an undocumented compatibility tweak and may change in future Windows builds.'
    }
}

foreach ($entry in $requested.GetEnumerator()) {
    if ($entry.Value) {
        $result = Set-WindowsShellPreference -Name $entry.Key -Value $entry.Value -WhatIf:$WhatIfPreference -Confirm:$false
        Write-Host "[$result] $($entry.Key) -> $($entry.Value)"
    }
}

if ($RestartExplorer -and $hasChanges) {
    Restart-WindowsExplorer -WhatIf:$WhatIfPreference -Confirm:$false | Out-Null
}

if ($Status -or -not $hasChanges) {
    Get-WindowsShellState | Format-List
} elseif (-not $RestartExplorer -and -not $WhatIfPreference) {
    Write-Host 'Settings saved. Restart Explorer or sign out to apply every change.' -ForegroundColor Yellow
}

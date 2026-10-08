#Requires -Version 5.1
<#
.SYNOPSIS
    Install Scoop into a custom location and install this repository's Windows toolset.
.DESCRIPTION
    Defaults to D:\Scoop and D:\ScoopGlobal when drive D exists. Otherwise, uses
    %LOCALAPPDATA%\Programs\Scoop and %LOCALAPPDATA%\Programs\ScoopGlobal.
.EXAMPLE
    ./windows/install-scoop.ps1 -WhatIf
.EXAMPLE
    ./windows/install-scoop.ps1 -ScoopRoot 'E:\Apps\Scoop' -ScoopGlobalRoot 'E:\Apps\ScoopGlobal'
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ScoopRoot,
    [string]$ScoopGlobalRoot,
    [string]$ConfigPath,
    [AllowEmptyCollection()][string[]]$Packages,
    [AllowEmptyCollection()][string[]]$Buckets,
    [string[]]$AddPackage = @(),
    [string[]]$AddBucket = @(),
    [switch]$SkipPackages,
    [switch]$AllowAdmin
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/ScoopCore.psm1'
Import-Module $modulePath -Force

if (-not $ConfigPath) {
    $ConfigPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'config/scoop.psd1'
}
$configuration = Read-ScoopConfiguration -Path $ConfigPath
$packageSpecs = if ($PSBoundParameters.ContainsKey('Packages')) { @($Packages) } else { @($configuration.Packages) }
$bucketSpecs = if ($PSBoundParameters.ContainsKey('Buckets')) { @($Buckets) } else { @($configuration.Buckets) }
$packageSpecs += @($AddPackage)
$bucketSpecs += @($AddBucket)
$resolvedPackages = @(Get-ScoopPackageMap -Package $packageSpecs)
$resolvedBuckets = @(Get-RequiredScoopBuckets -Bucket $bucketSpecs)

$defaults = Get-DefaultScoopPaths
if (-not $ScoopRoot) { $ScoopRoot = $defaults.Root }
if (-not $ScoopGlobalRoot) { $ScoopGlobalRoot = $defaults.GlobalRoot }

Assert-ScoopInstallPaths -Root $ScoopRoot -GlobalRoot $ScoopGlobalRoot

Write-Host '==> Scoop plan' -ForegroundColor Magenta
Write-Host "User apps : $ScoopRoot"
Write-Host "Global apps: $ScoopGlobalRoot"
Write-Host "Config     : $($configuration.Path)"
$bucketSummary = if ($SkipPackages) {
    'Skipped (-SkipPackages)'
} elseif ($resolvedBuckets.Count -gt 0) {
    ($resolvedBuckets | ForEach-Object { $_.Name }) -join ', '
} else { '(none)' }
$packageSummary = if ($SkipPackages) {
    'Skipped (-SkipPackages)'
} elseif ($resolvedPackages.Count -gt 0) {
    ($resolvedPackages | ForEach-Object { "$($_.Bucket)/$($_.App)" }) -join ', '
} else { '(none)' }
Write-Host "Buckets    : $bucketSummary"
Write-Host "Packages   : $packageSummary"

$result = Install-ScoopBootstrap -Root $ScoopRoot -GlobalRoot $ScoopGlobalRoot -AllowAdmin:$AllowAdmin -WhatIf:$WhatIfPreference -Confirm:$false
Write-Host "[$result] Scoop"

if (-not $SkipPackages) {
    if ($WhatIfPreference -and $result -eq 'WhatIf') {
        foreach ($bucket in $resolvedBuckets) {
            Write-Host "[WhatIf] Add bucket -> $($bucket.Name)"
        }
        foreach ($package in $resolvedPackages) {
            Write-Host "[WhatIf] Install -> $($package.Bucket)/$($package.App)"
        }
    } else {
        Install-ScoopConfiguredPackages -Root $ScoopRoot -Packages $resolvedPackages -Buckets $resolvedBuckets -WhatIf:$WhatIfPreference -Confirm:$false
    }
}

if (-not $WhatIfPreference) {
    Write-Host 'Scoop setup complete. Open a new terminal if the scoop command is not yet visible.' -ForegroundColor Green
}

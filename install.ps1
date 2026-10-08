#Requires -Version 5.1
<#
.SYNOPSIS
    Install and configure a Windows terminal toolset with winget or Scoop.
.DESCRIPTION
    Idempotent: already-installed software is skipped; configs are not re-deployed when content is unchanged.
.PARAMETER Force
    Force overwrite local configs with the repo versions (even when content is identical).
.PARAMETER SkipInstall
    Only deploy configs; skip winget installation.
.PARAMETER SkipConfig
    Only install software; skip config deployment.
.PARAMETER PackageManager
    Package manager used for Windows software. Supported values: Winget, Scoop.
.PARAMETER ScoopRoot
    Optional custom per-user Scoop root. The Scoop installer chooses D:\Scoop when available.
.PARAMETER ScoopGlobalRoot
    Optional custom root for global Scoop applications.
.PARAMETER ScoopConfigPath
    Optional path to a .psd1 file that replaces the repository Scoop defaults.
.PARAMETER ScoopPackages
    Optional bucket/app list that replaces the configured package list.
.PARAMETER ScoopBuckets
    Optional name=url list that replaces the configured additional buckets.
.EXAMPLE
    ./install.ps1
.EXAMPLE
    ./install.ps1 -Force
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$SkipInstall,
    [switch]$SkipConfig,
    [ValidateSet('Winget', 'Scoop')][string]$PackageManager = 'Winget',
    [string]$ScoopRoot,
    [string]$ScoopGlobalRoot,
    [string]$ScoopConfigPath,
    [AllowEmptyCollection()][string[]]$ScoopPackages,
    [AllowEmptyCollection()][string[]]$ScoopBuckets,
    [string[]]$AddScoopPackage = @(),
    [string[]]$AddScoopBucket = @(),
    [switch]$AllowAdminScoop
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = $PSScriptRoot
Import-Module (Join-Path $RepoRoot 'lib/DotfileCore.psm1') -Force
$failures = [System.Collections.Generic.List[string]]::new()

function Write-Section {
    param([string]$Text)
    Write-Host ''
    Write-Host "==> $Text" -ForegroundColor Magenta
}

# 1. Install packages
if (-not $SkipInstall) {
    Write-Section "Installing packages ($PackageManager)"
    if ($PackageManager -eq 'Scoop') {
        try {
            $scoopArguments = @{
                AllowAdmin = $AllowAdminScoop
            }
            if ($ScoopRoot) { $scoopArguments.ScoopRoot = $ScoopRoot }
            if ($ScoopGlobalRoot) { $scoopArguments.ScoopGlobalRoot = $ScoopGlobalRoot }
            if ($ScoopConfigPath) { $scoopArguments.ConfigPath = $ScoopConfigPath }
            if ($PSBoundParameters.ContainsKey('ScoopPackages')) { $scoopArguments.Packages = $ScoopPackages }
            if ($PSBoundParameters.ContainsKey('ScoopBuckets')) { $scoopArguments.Buckets = $ScoopBuckets }
            if ($AddScoopPackage.Count -gt 0) { $scoopArguments.AddPackage = $AddScoopPackage }
            if ($AddScoopBucket.Count -gt 0) { $scoopArguments.AddBucket = $AddScoopBucket }
            & (Join-Path $RepoRoot 'windows/install-scoop.ps1') @scoopArguments
        } catch {
            Write-Warning "Scoop setup failed: $($_.Exception.Message)"
            $failures.Add('Scoop setup failed') | Out-Null
        }
    } else {
        if (-not (Test-CommandExists 'winget')) {
            Write-Warning 'winget not found. Install "App Installer" first: https://aka.ms/getwinget'
            $failures.Add('winget is unavailable') | Out-Null
        } else {
            foreach ($id in Get-WingetPackages) {
                $result = Install-Package -Id $id
                if ($result -eq 'Failed') {
                    $failures.Add("package installation failed: $id") | Out-Null
                }
            }
        }
    }
} else {
    Write-Host 'Skipped package installation (-SkipInstall)' -ForegroundColor DarkGray
}

# 2. Deploy configs
if (-not $SkipConfig) {
    Write-Section 'Deploying config files'
    $useSymlink = Test-SymlinkCapable
    if ($useSymlink) {
        Write-Host 'Admin/Developer Mode detected: deploying via symbolic links (repo edits apply instantly)' -ForegroundColor DarkGray
    } else {
        Write-Host 'No symlink privilege: deploying via copy (enable Developer Mode to use symlinks)' -ForegroundColor DarkGray
    }

    foreach ($cfg in Get-ConfigMap -RepoRoot $RepoRoot) {
        try {
            $result = Deploy-Config -Source $cfg.Source -Target $cfg.Target -Force:$Force -UseSymlink:$useSymlink
            $color = switch ($result) {
                'Skipped' { 'DarkGray' }
                default   { 'Green' }
            }
            Write-Host ("[{0,-7}] {1} -> {2}" -f $result, $cfg.Name, $cfg.Target) -ForegroundColor $color
        } catch {
            Write-Warning ("Config {0} deployment failed: {1}" -f $cfg.Name, $_.Exception.Message)
            $failures.Add("config deployment failed: $($cfg.Name)") | Out-Null
        }
    }
} else {
    Write-Host 'Skipped config deployment (-SkipConfig)' -ForegroundColor DarkGray
}

if ($failures.Count -gt 0) {
    Write-Section 'Completed with errors'
    foreach ($failure in $failures) {
        Write-Host "[failed] $failure" -ForegroundColor Red
    }
    throw "Setup failed with $($failures.Count) error(s)."
}

Write-Section 'Done'
Write-Host 'Restart your terminal, or run pwsh to load the new PowerShell profile.' -ForegroundColor Green
Write-Host 'Tip: set the font to "JetBrainsMono Nerd Font" in Windows Terminal/Alacritty to render icons correctly.' -ForegroundColor Green

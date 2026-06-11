#Requires -Version 5.1
<#
.SYNOPSIS
    Install and configure a Windows terminal toolset (PowerShell 7 / Zellij / Starship / Alacritty / JetBrainsMono Nerd Font).
.DESCRIPTION
    Idempotent: already-installed software is skipped; configs are not re-deployed when content is unchanged.
.PARAMETER Force
    Force overwrite local configs with the repo versions (even when content is identical).
.PARAMETER SkipInstall
    Only deploy configs; skip winget installation.
.PARAMETER SkipConfig
    Only install software; skip config deployment.
.EXAMPLE
    ./install.ps1
.EXAMPLE
    ./install.ps1 -Force
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$SkipInstall,
    [switch]$SkipConfig
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = $PSScriptRoot
Import-Module (Join-Path $RepoRoot 'lib/DotfileCore.psm1') -Force

function Write-Section {
    param([string]$Text)
    Write-Host ''
    Write-Host "==> $Text" -ForegroundColor Magenta
}

# 1. Install packages
if (-not $SkipInstall) {
    Write-Section 'Installing packages (winget)'
    if (-not (Test-CommandExists 'winget')) {
        Write-Warning 'winget not found. Install "App Installer" first: https://aka.ms/getwinget'
    } else {
        foreach ($id in Get-WingetPackages) {
            Install-Package -Id $id | Out-Null
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
        }
    }
} else {
    Write-Host 'Skipped config deployment (-SkipConfig)' -ForegroundColor DarkGray
}

Write-Section 'Done'
Write-Host 'Restart your terminal, or run pwsh to load the new PowerShell profile.' -ForegroundColor Green
Write-Host 'Tip: set the font to "JetBrainsMono Nerd Font" in Windows Terminal/Alacritty to render icons correctly.' -ForegroundColor Green

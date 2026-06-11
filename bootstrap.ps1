#Requires -Version 5.1
<#
.SYNOPSIS
    Online bootstrap: ensure dependencies -> clone/update repo -> run install.ps1.
.DESCRIPTION
    Designed to be run remotely:
        irm https://raw.githubusercontent.com/millylee/my-config/master/bootstrap.ps1 | iex
.PARAMETER InstallDir
    Local clone directory, defaults to $HOME\.dotfiles.
.PARAMETER Branch
    Branch to check out, defaults to master.
#>
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $HOME '.dotfiles'),
    [string]$Branch = 'master'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoUrl = 'https://github.com/millylee/my-config.git'

function Test-Cmd {
    param([string]$Name)
    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

Write-Host '==> Checking dependencies' -ForegroundColor Magenta

if (-not (Test-Cmd 'winget')) {
    Write-Warning 'winget not found. Install "App Installer" first: https://aka.ms/getwinget'
    Write-Warning 'Re-run this script after installing it.'
    return
}

if (-not (Test-Cmd 'git')) {
    Write-Host 'git not found, installing Git.Git via winget ...' -ForegroundColor Cyan
    winget install -e --id Git.Git --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Host
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not (Test-Cmd 'git')) {
        Write-Warning 'git is still unavailable after install. Restart your terminal and re-run this script.'
        return
    }
}

Write-Host "==> Fetching repo into $InstallDir" -ForegroundColor Magenta
if (Test-Path -LiteralPath (Join-Path $InstallDir '.git')) {
    Write-Host 'Repo already exists, running git pull ...' -ForegroundColor Cyan
    git -C $InstallDir pull --ff-only | Out-Host
} else {
    if (Test-Path -LiteralPath $InstallDir) {
        $items = Get-ChildItem -LiteralPath $InstallDir -Force -ErrorAction SilentlyContinue
        if ($items) { throw "Target directory is not empty and not a git repo: $InstallDir" }
    }
    git clone --branch $Branch $RepoUrl $InstallDir | Out-Host
}

$installScript = Join-Path $InstallDir 'install.ps1'
if (-not (Test-Path -LiteralPath $installScript)) {
    throw "Install script not found: $installScript"
}

Write-Host '==> Running install script' -ForegroundColor Magenta
& $installScript

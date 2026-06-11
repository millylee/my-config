#Requires -Version 5.1
Set-StrictMode -Version Latest

function Test-IsAdmin {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-DeveloperMode {
    try {
        $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
        $value = Get-ItemProperty -Path $key -Name 'AllowDevelopmentWithoutDevLicense' -ErrorAction Stop
        return [bool]$value.AllowDevelopmentWithoutDevLicense
    } catch {
        return $false
    }
}

function Test-SymlinkCapable {
    return ((Test-IsAdmin) -or (Test-DeveloperMode))
}

function Test-CommandExists {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Get-WingetPackages {
    return @(
        'Microsoft.PowerShell'
        'Zellij.Zellij'
        'Starship.Starship'
        'Alacritty.Alacritty'
        'DEVCOM.JetBrainsMonoNerdFont'
    )
}

function Get-ConfigMap {
    param([Parameter(Mandatory)][string]$RepoRoot)
    return @(
        [pscustomobject]@{
            Name   = 'starship'
            Source = Join-Path $RepoRoot 'config/starship/starship.toml'
            Target = Join-Path $HOME '.config/starship.toml'
        }
        [pscustomobject]@{
            Name   = 'alacritty'
            Source = Join-Path $RepoRoot 'config/alacritty/alacritty.toml'
            Target = Join-Path $env:APPDATA 'alacritty/alacritty.toml'
        }
        [pscustomobject]@{
            Name   = 'zellij'
            Source = Join-Path $RepoRoot 'config/zellij/config.kdl'
            Target = Join-Path $env:APPDATA 'zellij/config.kdl'
        }
        [pscustomobject]@{
            Name   = 'powershell'
            Source = Join-Path $RepoRoot 'config/powershell/Microsoft.PowerShell_profile.ps1'
            Target = Join-Path $HOME 'Documents/PowerShell/Microsoft.PowerShell_profile.ps1'
        }
    )
}

function Test-PackageInstalled {
    param([Parameter(Mandatory)][string]$Id)
    if (-not (Test-CommandExists 'winget')) { return $false }
    $output = winget list --id $Id -e --accept-source-agreements 2>$null
    return [bool]($output | Select-String -SimpleMatch $Id -Quiet)
}

function Invoke-WingetInstall {
    param([Parameter(Mandatory)][string]$Id)
    winget install -e --id $Id `
        --accept-package-agreements `
        --accept-source-agreements `
        --disable-interactivity | Out-Host
    return $LASTEXITCODE
}

function Install-Package {
    param([Parameter(Mandatory)][string]$Id)
    if (Test-PackageInstalled -Id $Id) {
        Write-Host "[skip]    $Id already installed" -ForegroundColor DarkGray
        return 'Skipped'
    }
    Write-Host "[install] $Id ..." -ForegroundColor Cyan
    $code = Invoke-WingetInstall -Id $Id
    if ($code -ne 0) {
        Write-Warning "$Id installation failed (exit code $code)"
        return 'Failed'
    }
    Write-Host "[ok]      $Id installed" -ForegroundColor Green
    return 'Installed'
}

function Deploy-Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Target,
        [switch]$Force,
        [switch]$UseSymlink
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Source config not found: $Source"
    }

    $resolvedSource = (Resolve-Path -LiteralPath $Source).Path
    $targetDir = Split-Path -Parent $Target
    if ($targetDir -and -not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    if ($UseSymlink) {
        $existing = Get-Item -LiteralPath $Target -Force -ErrorAction SilentlyContinue
        if ($existing -and $existing.LinkType -eq 'SymbolicLink' -and -not $Force) {
            $linkTarget = $existing.Target
            if ($linkTarget) {
                $resolvedLink = (Resolve-Path -LiteralPath $linkTarget -ErrorAction SilentlyContinue)
                if ($resolvedLink -and $resolvedLink.Path -eq $resolvedSource) {
                    return 'Skipped'
                }
            }
        }
    }

    if (Test-Path -LiteralPath $Target) {
        if (-not $UseSymlink) {
            $sourceHash = (Get-FileHash -LiteralPath $Source).Hash
            $targetHash = (Get-FileHash -LiteralPath $Target).Hash
            if ($sourceHash -eq $targetHash -and -not $Force) {
                return 'Skipped'
            }
        }
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = "$Target.$stamp.bak"
        Copy-Item -LiteralPath $Target -Destination $backup -Force
        Remove-Item -LiteralPath $Target -Force -Recurse
    }

    if ($UseSymlink) {
        New-Item -ItemType SymbolicLink -Path $Target -Value $resolvedSource -Force | Out-Null
        return 'Linked'
    }

    Copy-Item -LiteralPath $Source -Destination $Target -Force
    return 'Copied'
}

Export-ModuleMember -Function `
    Test-IsAdmin,
    Test-DeveloperMode,
    Test-SymlinkCapable,
    Test-CommandExists,
    Get-WingetPackages,
    Get-ConfigMap,
    Test-PackageInstalled,
    Invoke-WingetInstall,
    Install-Package,
    Deploy-Config

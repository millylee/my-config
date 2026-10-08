#Requires -Version 5.1
Set-StrictMode -Version Latest

$script:ScoopInstallerUrl = 'https://raw.githubusercontent.com/ScoopInstaller/Install/master/install.ps1'
$script:DefaultScoopConfigPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'config/scoop.psd1'

function Test-ScoopWindowsPlatform {
    return ($env:OS -eq 'Windows_NT')
}

function Test-ScoopProcessAdmin {
    if (-not (Test-ScoopWindowsPlatform)) { return $false }
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DefaultScoopPaths {
    $dataDrive = Get-PSDrive -Name D -PSProvider FileSystem -ErrorAction SilentlyContinue
    if ($dataDrive) {
        return [pscustomobject]@{
            Root       = 'D:\Scoop'
            GlobalRoot = 'D:\ScoopGlobal'
        }
    }

    $programs = Join-Path $env:LOCALAPPDATA 'Programs'
    return [pscustomobject]@{
        Root       = Join-Path $programs 'Scoop'
        GlobalRoot = Join-Path $programs 'ScoopGlobal'
    }
}

function Read-ScoopConfiguration {
    param([string]$Path = $script:DefaultScoopConfigPath)

    if (-not [System.IO.File]::Exists($Path)) {
        throw "Scoop configuration file not found: $Path"
    }
    $configuration = Import-PowerShellDataFile -LiteralPath $Path
    if (-not $configuration.ContainsKey('Packages') -or -not $configuration.ContainsKey('Buckets')) {
        throw "Scoop configuration must define Packages and Buckets: $Path"
    }
    return [pscustomobject]@{
        Path     = [System.IO.Path]::GetFullPath($Path)
        Packages = @($configuration.Packages)
        Buckets  = @($configuration.Buckets)
    }
}

function Get-ScoopPackageMap {
    param([AllowEmptyCollection()][string[]]$Package)

    if (-not $PSBoundParameters.ContainsKey('Package')) {
        $Package = (Read-ScoopConfiguration).Packages
    }

    $seen = @{}
    foreach ($qualifiedName in $Package) {
        if ($qualifiedName -notmatch '^(?<Bucket>[A-Za-z0-9][A-Za-z0-9._-]*)/(?<App>[A-Za-z0-9][A-Za-z0-9._+@-]*)$') {
            throw "Invalid Scoop package '$qualifiedName'. Use bucket/app, for example main/git."
        }
        $key = $qualifiedName.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [pscustomobject]@{
            Bucket = $Matches.Bucket
            App = $Matches.App
        }
    }
}

function Get-RequiredScoopBuckets {
    param([AllowEmptyCollection()][string[]]$Bucket)

    if (-not $PSBoundParameters.ContainsKey('Bucket')) {
        $Bucket = (Read-ScoopConfiguration).Buckets
    }

    $seen = @{}
    foreach ($specification in $Bucket) {
        $parts = $specification -split '=', 2
        if ($parts.Count -ne 2 -or $parts[0] -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or [string]::IsNullOrWhiteSpace($parts[1])) {
            throw "Invalid Scoop bucket '$specification'. Use name=https://repository-url."
        }
        $key = $parts[0].ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [pscustomobject]@{
            Name = $parts[0]
            Url = $parts[1]
        }
    }
}

function Get-InstalledScoopRoot {
    $command = Get-Command scoop -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { return $null }
    $source = $command.Source
    if (-not $source) { return $null }
    $shims = Split-Path -Parent $source
    return Split-Path -Parent $shims
}

function Test-SamePath {
    param(
        [Parameter(Mandatory)][string]$Left,
        [Parameter(Mandatory)][string]$Right
    )
    $leftFull = [System.IO.Path]::GetFullPath($Left).TrimEnd('\', '/')
    $rightFull = [System.IO.Path]::GetFullPath($Right).TrimEnd('\', '/')
    return $leftFull.Equals($rightFull, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-ScoopInstallPaths {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$GlobalRoot
    )
    foreach ($path in $Root, $GlobalRoot) {
        if (-not [System.IO.Path]::IsPathRooted($path)) {
            throw "Scoop paths must be absolute: $path"
        }
        $fullPath = [System.IO.Path]::GetFullPath($path)
        $pathRoot = [System.IO.Path]::GetPathRoot($fullPath)
        if ($fullPath.TrimEnd('\', '/') -eq $pathRoot.TrimEnd('\', '/')) {
            throw "Scoop cannot be installed directly at a drive root: $path"
        }
    }
    if (Test-SamePath -Left $Root -Right $GlobalRoot) {
        throw 'The per-user and global Scoop roots must be different directories.'
    }
}

function Get-ScoopCommandPath {
    param([Parameter(Mandatory)][string]$Root)
    $command = Get-Command scoop -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    $shim = Join-Path $Root 'shims/scoop.ps1'
    if (Test-Path -LiteralPath $shim) { return $shim }
    return $null
}

function Invoke-ScoopCommand {
    param(
        [Parameter(Mandatory)][string]$CommandPath,
        [Parameter(Mandatory)][string[]]$Arguments
    )
    $global:LASTEXITCODE = 0
    & $CommandPath @Arguments | Out-Host
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Scoop command failed with exit code $exitCode`: scoop $($Arguments -join ' ')"
    }
}

function Install-ScoopBootstrap {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$GlobalRoot,
        [switch]$AllowAdmin
    )

    if (-not (Test-ScoopWindowsPlatform)) { throw 'Scoop is only supported on Windows.' }
    Assert-ScoopInstallPaths -Root $Root -GlobalRoot $GlobalRoot

    $installedRoot = Get-InstalledScoopRoot
    if ($installedRoot) {
        if (-not (Test-SamePath -Left $installedRoot -Right $Root)) {
            throw "Scoop is already installed at '$installedRoot'. Automatic relocation is intentionally blocked. Use -ScoopRoot '$installedRoot' or migrate the existing installation manually."
        }
        return 'Skipped'
    }

    if (-not $PSCmdlet.ShouldProcess($Root, "Install Scoop with global apps at '$GlobalRoot'")) {
        return 'WhatIf'
    }

    $isAdmin = Test-ScoopProcessAdmin
    if ($isAdmin -and -not $AllowAdmin) {
        throw 'Scoop recommends a non-admin PowerShell session. Reopen PowerShell without elevation, or pass -AllowAdmin after reviewing the security tradeoff.'
    }

    $temporaryInstaller = Join-Path ([System.IO.Path]::GetTempPath()) ("scoop-install-$([guid]::NewGuid().ToString('N')).ps1")
    try {
        Invoke-WebRequest -Uri $script:ScoopInstallerUrl -OutFile $temporaryInstaller -UseBasicParsing
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
        # PowerShell script parameters require named (hashtable) splatting.
        # An array would bind these strings positionally, including to ProxyCredential.
        $installerParameters = @{
            ScoopDir = $Root
            ScoopGlobalDir = $GlobalRoot
        }
        if ($isAdmin) { $installerParameters.RunAsAdmin = $true }
        $global:LASTEXITCODE = 0
        # Keep progress and failure details visible without mixing them into the result.
        & $temporaryInstaller @installerParameters | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "The official Scoop installer failed with exit code $LASTEXITCODE."
        }
    } finally {
        if (Test-Path -LiteralPath $temporaryInstaller) {
            Remove-Item -LiteralPath $temporaryInstaller -Force
        }
    }

    $env:PATH = "$(Join-Path $Root 'shims');$env:PATH"
    return 'Installed'
}

function Install-ScoopConfiguredPackages {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Root,
        [AllowEmptyCollection()][object[]]$Packages = @(Get-ScoopPackageMap),
        [AllowEmptyCollection()][object[]]$Buckets = @(Get-RequiredScoopBuckets)
    )

    $commandPath = Get-ScoopCommandPath -Root $Root
    if (-not $commandPath) { throw "Scoop command not found below '$Root'." }

    # Install configured Git first so Scoop can clone additional buckets.
    $gitPackage = $Packages | Where-Object { $_.Bucket -eq 'main' -and $_.App -eq 'git' } | Select-Object -First 1
    if ($gitPackage -and $PSCmdlet.ShouldProcess('main/git', 'Install Scoop package')) {
        Invoke-ScoopCommand -CommandPath $commandPath -Arguments @('install', 'main/git')
    }

    foreach ($bucket in $Buckets) {
        $bucketPath = Join-Path $Root "buckets/$($bucket.Name)"
        if (-not (Test-Path -LiteralPath $bucketPath)) {
            if ($PSCmdlet.ShouldProcess($bucket.Name, 'Add Scoop bucket')) {
                Invoke-ScoopCommand -CommandPath $commandPath -Arguments @('bucket', 'add', $bucket.Name, $bucket.Url)
            }
        }
    }

    foreach ($package in $Packages | Where-Object { -not ($_.Bucket -eq 'main' -and $_.App -eq 'git') }) {
        $qualifiedName = "$($package.Bucket)/$($package.App)"
        if ($PSCmdlet.ShouldProcess($qualifiedName, 'Install Scoop package')) {
            Invoke-ScoopCommand -CommandPath $commandPath -Arguments @('install', $qualifiedName)
        }
    }
}

Export-ModuleMember -Function `
    Test-ScoopWindowsPlatform,
    Test-ScoopProcessAdmin,
    Get-DefaultScoopPaths,
    Read-ScoopConfiguration,
    Get-ScoopPackageMap,
    Get-RequiredScoopBuckets,
    Get-InstalledScoopRoot,
    Test-SamePath,
    Assert-ScoopInstallPaths,
    Get-ScoopCommandPath,
    Invoke-ScoopCommand,
    Install-ScoopBootstrap,
    Install-ScoopConfiguredPackages

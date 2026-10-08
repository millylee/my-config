#Requires -Version 5.1
Set-StrictMode -Version Latest

function Test-WindowsPlatform {
    return ($env:OS -eq 'Windows_NT')
}

function Test-CurrentProcessAdmin {
    if (-not (Test-WindowsPlatform)) { return $false }
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-ValidLocalUserName {
    param([Parameter(Mandatory)][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw 'The new user name cannot be empty.'
    }
    if ($Name.Length -gt 20) {
        throw 'The new user name cannot exceed 20 characters.'
    }
    if ($Name -ne $Name.Trim() -or $Name -match '^\.+$' -or $Name -match '[\x00-\x1f"/\\\[\]:;|=,+*?<>@]' -or $Name.EndsWith('.')) {
        throw "The new user name contains characters that Windows local accounts do not support: $Name"
    }
}

function Get-CurrentLocalUser {
    if (-not (Test-WindowsPlatform)) {
        throw 'Local Windows account management is only available on Windows.'
    }
    if (-not (Get-Command Get-LocalUser -ErrorAction SilentlyContinue)) {
        throw 'The Microsoft.PowerShell.LocalAccounts module is unavailable. Use 64-bit Windows PowerShell 5.1 or PowerShell 7.'
    }

    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $account = Get-LocalUser -SID $sid -ErrorAction SilentlyContinue
    if (-not $account) {
        throw 'The signed-in identity is not a local Windows account. Domain and Entra ID accounts are not renamed by this script.'
    }
    if ($account.PSObject.Properties.Name -contains 'PrincipalSource') {
        $source = [string]$account.PrincipalSource
        if ($source -and $source -ne 'Local') {
            throw "The signed-in account is managed by $source, not the local computer. Rename it through its identity provider."
        }
    }
    return $account
}

function Rename-CurrentLocalUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory)][string]$NewName)

    Assert-ValidLocalUserName -Name $NewName
    $account = Get-CurrentLocalUser
    if ($account.Name -eq $NewName) {
        return 'Skipped'
    }

    $existing = Get-LocalUser -Name $NewName -ErrorAction SilentlyContinue
    if ($existing -and $existing.SID.Value -ne $account.SID.Value) {
        throw "A different local account already uses the name '$NewName'."
    }

    if (-not $WhatIfPreference -and -not (Test-CurrentProcessAdmin)) {
        throw 'Renaming a local account requires an elevated PowerShell session.'
    }

    if ($PSCmdlet.ShouldProcess($account.Name, "Rename local account to '$NewName'")) {
        Rename-LocalUser -InputObject $account -NewName $NewName -ErrorAction Stop
        return 'Renamed'
    }
    return 'WhatIf'
}

function Get-KnownFolderDefinitions {
    return @(
        [pscustomobject]@{ Name = 'Desktop';   Id = [guid]'B4BFCC3A-DB2C-424C-B029-7FE99A87C641'; DirectoryName = 'Desktop' }
        [pscustomobject]@{ Name = 'Downloads'; Id = [guid]'374DE290-123F-4565-9164-39C4925E467B'; DirectoryName = 'Downloads' }
        [pscustomobject]@{ Name = 'Documents'; Id = [guid]'FDD39AD0-238F-46AF-ADB4-6C85480369C7'; DirectoryName = 'Documents' }
        [pscustomobject]@{ Name = 'Pictures';  Id = [guid]'33E28130-4E1E-4676-835A-98395C3BC3BB'; DirectoryName = 'Pictures' }
        [pscustomobject]@{ Name = 'Music';     Id = [guid]'4BD8D571-6D19-48D3-BE97-422220080E43'; DirectoryName = 'Music' }
        [pscustomobject]@{ Name = 'Videos';    Id = [guid]'18989B1D-99B5-455B-841C-AB7C74E4DDFC'; DirectoryName = 'Videos' }
    )
}

function Initialize-KnownFolderNativeType {
    if ('MyConfig.Windows.KnownFolders' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace MyConfig.Windows {
    public static class KnownFolders {
        [DllImport("shell32.dll")]
        private static extern int SHGetKnownFolderPath(
            [MarshalAs(UnmanagedType.LPStruct)] Guid rfid,
            uint flags,
            IntPtr token,
            out IntPtr path);

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern int SHSetKnownFolderPath(
            [MarshalAs(UnmanagedType.LPStruct)] Guid rfid,
            uint flags,
            IntPtr token,
            string path);

        [DllImport("ole32.dll")]
        private static extern void CoTaskMemFree(IntPtr pointer);

        [DllImport("shell32.dll")]
        private static extern void SHChangeNotify(uint eventId, uint flags, IntPtr item1, IntPtr item2);

        public static string GetPath(Guid folderId) {
            IntPtr pointer;
            int result = SHGetKnownFolderPath(folderId, 0, IntPtr.Zero, out pointer);
            if (result != 0) Marshal.ThrowExceptionForHR(result);
            try {
                return Marshal.PtrToStringUni(pointer);
            } finally {
                CoTaskMemFree(pointer);
            }
        }

        public static void SetPath(Guid folderId, string path) {
            int result = SHSetKnownFolderPath(folderId, 0, IntPtr.Zero, path);
            if (result != 0) Marshal.ThrowExceptionForHR(result);
        }

        public static void NotifyShell() {
            SHChangeNotify(0x08000000, 0x1000, IntPtr.Zero, IntPtr.Zero);
        }
    }
}
'@
}

function Get-WindowsKnownFolderPath {
    param([Parameter(Mandatory)][guid]$Id)
    if (-not (Test-WindowsPlatform)) { throw 'Windows Known Folders are only available on Windows.' }
    Initialize-KnownFolderNativeType
    return [MyConfig.Windows.KnownFolders]::GetPath($Id)
}

function Set-WindowsKnownFolderPath {
    param(
        [Parameter(Mandatory)][guid]$Id,
        [Parameter(Mandatory)][string]$Path
    )
    Initialize-KnownFolderNativeType
    [MyConfig.Windows.KnownFolders]::SetPath($Id, $Path)
}

function Get-KnownFolderMovePlan {
    param([Parameter(Mandatory)][string]$Root)

    if (-not [System.IO.Path]::IsPathRooted($Root)) {
        throw "The user data root must be an absolute path: $Root"
    }
    $fullRoot = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Root))
    $pathRoot = [System.IO.Path]::GetPathRoot($fullRoot)
    if ($fullRoot.TrimEnd('\', '/') -eq $pathRoot.TrimEnd('\', '/')) {
        throw 'The user data root must be a directory below the filesystem root.'
    }
    $fullRoot = $fullRoot.TrimEnd('\', '/')

    foreach ($folder in Get-KnownFolderDefinitions) {
        [pscustomobject]@{
            Name        = $folder.Name
            Id          = $folder.Id
            Source      = Get-WindowsKnownFolderPath -Id $folder.Id
            Destination = Join-Path $fullRoot $folder.DirectoryName
        }
    }
}

function Test-PathWithin {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Parent
    )
    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $fullParent = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\', '/')
    if ($fullPath.Equals($fullParent, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $fullPath.StartsWith($fullParent + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Test-OneDriveManagedPath {
    param([Parameter(Mandatory)][string]$Path)
    foreach ($variable in 'OneDrive', 'OneDriveConsumer', 'OneDriveCommercial') {
        $oneDriveRoot = [Environment]::GetEnvironmentVariable($variable)
        if ($oneDriveRoot -and (Test-PathWithin -Path $Path -Parent $oneDriveRoot)) { return $true }
    }
    return $false
}

function Invoke-Robocopy {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [switch]$Move
    )
    $arguments = @($Source, $Destination, '/E', '/COPY:DAT', '/DCOPY:DAT', '/XJ', '/R:2', '/W:1', '/NP', '/NFL', '/NDL', '/NJH', '/NJS')
    if ($Move) { $arguments += @('/MOVE', '/IS', '/IT') }
    & robocopy @arguments | Out-Host
    $exitCode = $LASTEXITCODE
    if ($exitCode -ge 8) {
        throw "robocopy failed for '$Source' -> '$Destination' (exit code $exitCode)."
    }
    return $exitCode
}

function Move-WindowsKnownFolders {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$Root,
        [switch]$AllowOneDrive,
        [switch]$Force
    )

    if (-not (Test-WindowsPlatform)) { throw 'Known Folder relocation is only available on Windows.' }
    if (-not (Get-Command robocopy -ErrorAction SilentlyContinue)) { throw 'robocopy is required to move Known Folder contents.' }

    $plan = @(Get-KnownFolderMovePlan -Root $Root)
    foreach ($item in $plan) {
        if ((Test-PathWithin -Path $item.Destination -Parent $item.Source) -and
            -not $item.Destination.Equals($item.Source, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Destination for $($item.Name) is inside its current folder: $($item.Destination)"
        }
        if (-not $AllowOneDrive -and (Test-OneDriveManagedPath -Path $item.Source)) {
            throw "$($item.Name) is currently managed by OneDrive: $($item.Source). Use OneDrive Known Folder Move, or pass -AllowOneDrive after pausing sync and reviewing the migration."
        }
        if (-not $Force -and (Test-Path -LiteralPath $item.Destination)) {
            $existing = Get-ChildItem -LiteralPath $item.Destination -Force -ErrorAction Stop | Select-Object -First 1
            if ($existing -and -not $item.Destination.Equals($item.Source, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Destination is not empty: $($item.Destination). Choose an empty root or pass -Force to merge."
            }
        }
    }

    if (-not $PSCmdlet.ShouldProcess($Root, 'Move Desktop, Downloads, Documents, Pictures, Music, and Videos')) {
        return $plan
    }

    foreach ($item in $plan) {
        New-Item -ItemType Directory -Path $item.Destination -Force | Out-Null
        if ((Test-Path -LiteralPath $item.Source) -and
            -not $item.Destination.Equals($item.Source, [StringComparison]::OrdinalIgnoreCase)) {
            Invoke-Robocopy -Source $item.Source -Destination $item.Destination | Out-Null
        }
    }

    $updated = [System.Collections.Generic.List[object]]::new()
    try {
        foreach ($item in $plan) {
            if (-not $item.Destination.Equals($item.Source, [StringComparison]::OrdinalIgnoreCase)) {
                Set-WindowsKnownFolderPath -Id $item.Id -Path $item.Destination
                $updated.Add($item) | Out-Null
            }
        }
    } catch {
        foreach ($item in $updated) {
            try { Set-WindowsKnownFolderPath -Id $item.Id -Path $item.Source } catch { Write-Warning "Could not roll back $($item.Name): $($_.Exception.Message)" }
        }
        throw
    }

    foreach ($item in $plan) {
        if ((Test-Path -LiteralPath $item.Source) -and
            -not $item.Destination.Equals($item.Source, [StringComparison]::OrdinalIgnoreCase)) {
            Invoke-Robocopy -Source $item.Source -Destination $item.Destination -Move | Out-Null
        }
    }

    Initialize-KnownFolderNativeType
    [MyConfig.Windows.KnownFolders]::NotifyShell()
    return $plan
}

Export-ModuleMember -Function `
    Test-WindowsPlatform,
    Test-CurrentProcessAdmin,
    Assert-ValidLocalUserName,
    Get-CurrentLocalUser,
    Rename-CurrentLocalUser,
    Get-KnownFolderDefinitions,
    Get-WindowsKnownFolderPath,
    Set-WindowsKnownFolderPath,
    Get-KnownFolderMovePlan,
    Test-PathWithin,
    Test-OneDriveManagedPath,
    Invoke-Robocopy,
    Move-WindowsKnownFolders

#Requires -Version 5.1
<#
.SYNOPSIS
    Optionally rename the current local account and relocate the six personal Known Folders.
.DESCRIPTION
    This script does not rename the profile directory under C:\Users. Account rename supports local
    accounts only. Known Folders are redirected through the Windows Shell API after their contents
    have been copied successfully. Sign out after an account rename; restart Explorer or sign out
    after relocating folders.
.EXAMPLE
    ./windows/setup-user.ps1 -NewUserName milly -UserDataRoot D:\Milly -WhatIf
.EXAMPLE
    ./windows/setup-user.ps1 -NewUserName milly -UserDataRoot D:\Milly -Confirm
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string]$NewUserName,
    [string]$UserDataRoot,
    [switch]$AllowOneDrive,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $NewUserName -and -not $UserDataRoot) {
    throw 'Specify -NewUserName, -UserDataRoot, or both.'
}

$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/WindowsUserSetup.psm1'
Import-Module $modulePath -Force

# Validate the complete account operation before moving any user data.
if ($NewUserName) {
    Assert-ValidLocalUserName -Name $NewUserName
    $currentAccount = Get-CurrentLocalUser
    $existingAccount = Get-LocalUser -Name $NewUserName -ErrorAction SilentlyContinue
    if ($existingAccount -and $existingAccount.SID.Value -ne $currentAccount.SID.Value) {
        throw "A different local account already uses the name '$NewUserName'."
    }
    if ($currentAccount.Name -ne $NewUserName -and -not $WhatIfPreference -and -not (Test-CurrentProcessAdmin)) {
        throw 'Renaming a local account requires an elevated PowerShell session.'
    }
}

if ($UserDataRoot) {
    Write-Host "==> Planning Known Folder relocation to $UserDataRoot" -ForegroundColor Magenta
    $plan = Move-WindowsKnownFolders -Root $UserDataRoot -AllowOneDrive:$AllowOneDrive -Force:$Force -WhatIf:$WhatIfPreference
    $plan | Format-Table Name, Source, Destination -AutoSize
}

if ($NewUserName) {
    Write-Host "==> Renaming the current local account to $NewUserName" -ForegroundColor Magenta
    $result = Rename-CurrentLocalUser -NewName $NewUserName -WhatIf:$WhatIfPreference
    Write-Host "[$result] local account" -ForegroundColor Green
}

if (-not $WhatIfPreference) {
    Write-Host 'Done. Sign out and sign back in so Explorer and the account name refresh everywhere.' -ForegroundColor Green
    Write-Host 'The existing C:\Users profile directory was intentionally not renamed.' -ForegroundColor Yellow
}

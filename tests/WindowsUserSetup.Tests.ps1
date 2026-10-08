#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $RepoRoot 'lib/WindowsUserSetup.psm1'
    Import-Module $ModulePath -Force
}

Describe 'Windows user setup compatibility' {
    It 'loads on Windows PowerShell 5.1 and PowerShell 7' {
        Test-WindowsPlatform | Should -BeTrue
        $PSVersionTable.PSVersion.Major | Should -BeGreaterOrEqual 5
    }

    It 'defines exactly the six requested Known Folders with unique IDs and paths' {
        $folders = @(Get-KnownFolderDefinitions)
        $folders.Count | Should -Be 6
        ($folders.Name -join ',') | Should -Be 'Desktop,Downloads,Documents,Pictures,Music,Videos'
        @($folders.Id | Select-Object -Unique).Count | Should -Be 6
        @($folders.DirectoryName | Select-Object -Unique).Count | Should -Be 6
    }
}

Describe 'Assert-ValidLocalUserName' {
    It 'accepts a normal local account name' {
        { Assert-ValidLocalUserName -Name 'milly' } | Should -Not -Throw
    }

    It 'rejects invalid or dangerous names' -ForEach @('', ' ', '...', 'trailing ', 'bad/name', 'bad@name', '123456789012345678901') {
        { Assert-ValidLocalUserName -Name $_ } | Should -Throw
    }
}

Describe 'Path safety helpers' {
    It 'detects a path inside another path without using string-prefix shortcuts' {
        Test-PathWithin -Path 'C:\Users\Milly\Documents' -Parent 'C:\Users\Milly' | Should -BeTrue
        Test-PathWithin -Path 'C:\Users\Milly2\Documents' -Parent 'C:\Users\Milly' | Should -BeFalse
    }

    It 'detects OneDrive-managed paths' {
        $oldValue = $env:OneDrive
        try {
            $env:OneDrive = 'C:\Users\Milly\OneDrive'
            Test-OneDriveManagedPath -Path 'C:\Users\Milly\OneDrive\Documents' | Should -BeTrue
            Test-OneDriveManagedPath -Path 'D:\Milly\Documents' | Should -BeFalse
        } finally {
            $env:OneDrive = $oldValue
        }
    }
}

Describe 'Get-KnownFolderMovePlan' {
    BeforeAll {
        Mock -ModuleName WindowsUserSetup Get-WindowsKnownFolderPath {
            param($Id)
            $definition = Get-KnownFolderDefinitions | Where-Object Id -eq $Id
            return Join-Path 'C:\Users\OldName' $definition.DirectoryName
        }
    }

    It 'maps all folders below the requested root' {
        $plan = @(Get-KnownFolderMovePlan -Root 'D:\Milly')
        $plan.Count | Should -Be 6
        ($plan | Where-Object Name -eq 'Desktop').Destination | Should -Be 'D:\Milly\Desktop'
        ($plan | Where-Object Name -eq 'Videos').Destination | Should -Be 'D:\Milly\Videos'
    }

    It 'rejects relative paths and drive roots' {
        { Get-KnownFolderMovePlan -Root '.\Milly' } | Should -Throw
        { Get-KnownFolderMovePlan -Root 'D:\' } | Should -Throw
    }
}

Describe 'Rename-CurrentLocalUser' {
    BeforeEach {
        $script:account = [pscustomobject]@{
            Name = 'OldName'
            SID  = [System.Security.Principal.SecurityIdentifier]'S-1-5-21-1-2-3-1001'
        }
        Mock -ModuleName WindowsUserSetup Get-CurrentLocalUser { $account }
        Mock -ModuleName WindowsUserSetup Get-LocalUser { $null }
        Mock -ModuleName WindowsUserSetup Test-CurrentProcessAdmin { $true }
        Mock -ModuleName WindowsUserSetup Rename-LocalUser {}
    }

    It 'renames the current local account after validation' {
        Rename-CurrentLocalUser -NewName 'NewName' -Confirm:$false | Should -Be 'Renamed'
        Should -Invoke -ModuleName WindowsUserSetup Rename-LocalUser -Times 1 -Exactly
    }

    It 'does not rename anything during WhatIf, including in a non-admin session' {
        Mock -ModuleName WindowsUserSetup Test-CurrentProcessAdmin { $false }
        Rename-CurrentLocalUser -NewName 'NewName' -WhatIf | Should -Be 'WhatIf'
        Should -Invoke -ModuleName WindowsUserSetup Rename-LocalUser -Times 0 -Exactly
    }
}

Describe 'Invoke-Robocopy' {
    BeforeEach {
        $caseName = [guid]::NewGuid().ToString('N')
        $script:source = Join-Path $TestDrive "source-$caseName"
        $script:destination = Join-Path $TestDrive "destination-$caseName"
        New-Item -ItemType Directory -Path $source | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'example.txt') -Value 'hello' -NoNewline
    }

    It 'copies directory contents without deleting the source' {
        { Invoke-Robocopy -Source $source -Destination $destination } | Should -Not -Throw
        Get-Content -LiteralPath (Join-Path $destination 'example.txt') -Raw | Should -Be 'hello'
        Test-Path -LiteralPath (Join-Path $source 'example.txt') | Should -BeTrue
    }

    It 'moves directory contents after a successful copy phase' {
        Invoke-Robocopy -Source $source -Destination $destination | Out-Null
        { Invoke-Robocopy -Source $source -Destination $destination -Move } | Should -Not -Throw
        Test-Path -LiteralPath (Join-Path $destination 'example.txt') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $source 'example.txt') | Should -BeFalse
    }
}

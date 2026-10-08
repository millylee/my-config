#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $RepoRoot 'lib/WindowsShell.psm1'
    Import-Module $ModulePath -Force
}

Describe 'Windows Shell preference definitions' {
    It 'contains reversible mappings for every exposed preference' {
        $definitions = Get-WindowsShellPreferenceDefinitions
        $definitions.Count | Should -Be 8
        $definitions.FileExtensions.Values.Show | Should -Be 0
        $definitions.FileExtensions.Values.Hide | Should -Be 1
        $definitions.HiddenItems.Values.Show | Should -Be 1
        $definitions.ExplorerStart.Values.ThisPC | Should -Be 1
        $definitions.ExplorerStart.Values.Home | Should -Be 2
        $definitions.TaskbarAlignment.Values.Left | Should -Be 0
        $definitions.TaskbarAlignment.Values.Center | Should -Be 1
        $definitions.TaskbarCombine.Values.Never | Should -Be 2
    }
}

Describe 'Set-WindowsContextMenuStyle' {
    BeforeEach {
        Mock -ModuleName WindowsShell Assert-WindowsShellPlatform {}
        Mock -ModuleName WindowsShell Get-WindowsBuildNumber { 26100 }
        Mock -ModuleName WindowsShell New-Item {}
        Mock -ModuleName WindowsShell Set-Item {}
        Mock -ModuleName WindowsShell Remove-Item {}
    }

    It 'creates the compatibility registration for Windows 10 style' {
        Mock -ModuleName WindowsShell Get-ClassicContextMenuEnabled { $false }
        Set-WindowsContextMenuStyle -Style Windows10 -Confirm:$false | Should -Be 'Changed'
        Should -Invoke -ModuleName WindowsShell New-Item -Times 1 -Exactly
        Should -Invoke -ModuleName WindowsShell Set-Item -Times 1 -Exactly
        Should -Invoke -ModuleName WindowsShell Remove-Item -Times 0 -Exactly
    }

    It 'removes only the compatibility CLSID to restore Windows 11 style' {
        Mock -ModuleName WindowsShell Get-ClassicContextMenuEnabled { $true }
        Mock -ModuleName WindowsShell Test-Path { $true }
        Set-WindowsContextMenuStyle -Style Windows11 -Confirm:$false | Should -Be 'Changed'
        Should -Invoke -ModuleName WindowsShell Remove-Item -Times 1 -Exactly
    }

    It 'makes no registry changes during WhatIf' {
        Mock -ModuleName WindowsShell Get-ClassicContextMenuEnabled { $false }
        Set-WindowsContextMenuStyle -Style Windows10 -WhatIf | Should -Be 'WhatIf'
        Should -Invoke -ModuleName WindowsShell New-Item -Times 0 -Exactly
        Should -Invoke -ModuleName WindowsShell Set-Item -Times 0 -Exactly
    }

    It 'does not claim Windows 11 style support on Windows 10' {
        Mock -ModuleName WindowsShell Get-WindowsBuildNumber { 19045 }
        { Set-WindowsContextMenuStyle -Style Windows11 -Confirm:$false } | Should -Throw
    }
}

Describe 'Set-WindowsShellPreference' {
    BeforeEach {
        Mock -ModuleName WindowsShell Assert-WindowsShellPlatform {}
        Mock -ModuleName WindowsShell Get-WindowsBuildNumber { 26100 }
        Mock -ModuleName WindowsShell Set-RegistryDword { 'Changed' }
    }

    It 'maps a friendly option to the expected DWORD' {
        Set-WindowsShellPreference -Name TaskbarAlignment -Value Left | Should -Be 'Changed'
        Should -Invoke -ModuleName WindowsShell Set-RegistryDword -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'TaskbarAl' -and $Value -eq 0
        }
    }

    It 'rejects values not supported by the selected preference' {
        { Set-WindowsShellPreference -Name ExplorerStart -Value Left } | Should -Throw
        Should -Invoke -ModuleName WindowsShell Set-RegistryDword -Times 0 -Exactly
    }

    It 'blocks Windows 11-only taskbar settings on Windows 10' {
        Mock -ModuleName WindowsShell Get-WindowsBuildNumber { 19045 }
        { Set-WindowsShellPreference -Name Widgets -Value Hide } | Should -Throw
    }
}

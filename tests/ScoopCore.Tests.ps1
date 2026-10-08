#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $RepoRoot 'lib/ScoopCore.psm1'
    Import-Module $ModulePath -Force
}

Describe 'Scoop paths and package map' {
    It 'uses a non-profile custom location by default' {
        $paths = Get-DefaultScoopPaths
        [System.IO.Path]::IsPathRooted($paths.Root) | Should -BeTrue
        [System.IO.Path]::IsPathRooted($paths.GlobalRoot) | Should -BeTrue
        Test-SamePath -Left $paths.Root -Right $paths.GlobalRoot | Should -BeFalse
        $paths.Root | Should -Not -Be (Join-Path $HOME 'scoop')
    }

    It 'maps every configured Windows tool to a Scoop manifest' {
        $packages = @(Get-ScoopPackageMap)
        $packages.Count | Should -Be 7
        ($packages | ForEach-Object { "$($_.Bucket)/$($_.App)" }) | Should -Contain 'main/pwsh'
        ($packages | ForEach-Object { "$($_.Bucket)/$($_.App)" }) | Should -Contain 'main/zellij'
        ($packages | ForEach-Object { "$($_.Bucket)/$($_.App)" }) | Should -Contain 'main/starship'
        ($packages | ForEach-Object { "$($_.Bucket)/$($_.App)" }) | Should -Contain 'main/neovim'
        ($packages | ForEach-Object { "$($_.Bucket)/$($_.App)" }) | Should -Contain 'extras/alacritty'
        ($packages | ForEach-Object { "$($_.Bucket)/$($_.App)" }) | Should -Contain 'nerd-fonts/JetBrainsMono-NF'
    }

    It 'loads defaults from the repository configuration file' {
        $configuration = Read-ScoopConfiguration
        $configuration.Path | Should -Be (Join-Path $RepoRoot 'config/scoop.psd1')
        $configuration.Buckets | Should -Contain 'extras=https://github.com/ScoopInstaller/Extras'
        $configuration.Packages | Should -Contain 'main/neovim'
    }

    It 'accepts complete package and bucket overrides and removes duplicates' {
        $packages = @(Get-ScoopPackageMap -Package @('main/7zip', 'main/7zip', 'extras/vscode'))
        $buckets = @(Get-RequiredScoopBuckets -Bucket @('extras=https://example.test/extras', 'extras=https://ignored.test/extras'))
        $packages.Count | Should -Be 2
        "$($packages[0].Bucket)/$($packages[0].App)" | Should -Be 'main/7zip'
        $buckets.Count | Should -Be 1
        $buckets[0].Url | Should -Be 'https://example.test/extras'
    }

    It 'rejects malformed package and bucket overrides' {
        { Get-ScoopPackageMap -Package @('git') } | Should -Throw
        { Get-RequiredScoopBuckets -Bucket @('extras') } | Should -Throw
    }

    It 'supports explicitly empty package and bucket overrides' {
        @(Get-ScoopPackageMap -Package @()).Count | Should -Be 0
        @(Get-RequiredScoopBuckets -Bucket @()).Count | Should -Be 0
    }

    It 'rejects relative, drive-root, and overlapping paths' {
        { Assert-ScoopInstallPaths -Root '.\Scoop' -GlobalRoot 'D:\ScoopGlobal' } | Should -Throw
        { Assert-ScoopInstallPaths -Root 'D:\' -GlobalRoot 'D:\ScoopGlobal' } | Should -Throw
        { Assert-ScoopInstallPaths -Root 'D:\Scoop' -GlobalRoot 'd:\scoop\' } | Should -Throw
    }
}

Describe 'Get-InstalledScoopRoot' {
    It 'derives the root from the Scoop shim location' {
        Mock -ModuleName ScoopCore Get-Command {
            [pscustomobject]@{ Source = 'E:\Tools\Scoop\shims\scoop.ps1' }
        }
        Get-InstalledScoopRoot | Should -Be 'E:\Tools\Scoop'
    }
}

Describe 'Install-ScoopBootstrap' {
    BeforeEach {
        $script:OriginalPath = $env:PATH
        Mock -ModuleName ScoopCore Test-ScoopWindowsPlatform { $true }
        Mock -ModuleName ScoopCore Test-ScoopProcessAdmin { $false }
        Mock -ModuleName ScoopCore Invoke-WebRequest {}
    }

    AfterEach {
        $env:PATH = $script:OriginalPath
    }

    It 'passes named directories and admin permission to the downloaded installer' {
        Mock -ModuleName ScoopCore Get-InstalledScoopRoot { $null }
        Mock -ModuleName ScoopCore Test-ScoopProcessAdmin { $true }
        Mock -ModuleName ScoopCore Set-ExecutionPolicy {}
        Mock -ModuleName ScoopCore Invoke-WebRequest {
            Copy-Item -LiteralPath (Join-Path $RepoRoot 'tests/fixtures/scoop-installer.ps1') -Destination $OutFile
        }
        Mock -ModuleName ScoopCore Out-Host {}

        $result = @(Install-ScoopBootstrap -Root 'D:\Test Apps\Scoop' -GlobalRoot 'D:\Test Apps\ScoopGlobal' -AllowAdmin -Confirm:$false)
        $result.Count | Should -Be 1
        $result[0] | Should -Be 'Installed'
        Should -Invoke -ModuleName ScoopCore Out-Host -Times 1 -Exactly -ParameterFilter {
            $InputObject.Root -eq 'D:\Test Apps\Scoop' -and
            $InputObject.GlobalRoot -eq 'D:\Test Apps\ScoopGlobal' -and
            $InputObject.RunAsAdmin -eq $true
        }
    }

    It 'does not set RunAsAdmin when the session is not elevated' {
        Mock -ModuleName ScoopCore Get-InstalledScoopRoot { $null }
        Mock -ModuleName ScoopCore Set-ExecutionPolicy {}
        Mock -ModuleName ScoopCore Invoke-WebRequest {
            Copy-Item -LiteralPath (Join-Path $RepoRoot 'tests/fixtures/scoop-installer.ps1') -Destination $OutFile
        }
        Mock -ModuleName ScoopCore Out-Host {}

        Install-ScoopBootstrap -Root 'D:\Test Apps\Scoop' -GlobalRoot 'D:\Test Apps\ScoopGlobal' -Confirm:$false | Should -Be 'Installed'
        Should -Invoke -ModuleName ScoopCore Out-Host -Times 1 -Exactly -ParameterFilter {
            $InputObject.RunAsAdmin -eq $false
        }
    }

    It 'skips an existing installation at the requested location' {
        Mock -ModuleName ScoopCore Get-InstalledScoopRoot { 'D:\Scoop' }
        Install-ScoopBootstrap -Root 'D:\Scoop' -GlobalRoot 'D:\ScoopGlobal' -Confirm:$false | Should -Be 'Skipped'
        Should -Invoke -ModuleName ScoopCore Invoke-WebRequest -Times 0 -Exactly
    }

    It 'blocks automatic relocation of an existing installation' {
        Mock -ModuleName ScoopCore Get-InstalledScoopRoot { 'C:\Users\Milly\scoop' }
        { Install-ScoopBootstrap -Root 'D:\Scoop' -GlobalRoot 'D:\ScoopGlobal' -Confirm:$false } | Should -Throw
    }

    It 'does not download or install anything during WhatIf' {
        Mock -ModuleName ScoopCore Get-InstalledScoopRoot { $null }
        Install-ScoopBootstrap -Root 'D:\Scoop' -GlobalRoot 'D:\ScoopGlobal' -WhatIf | Should -Be 'WhatIf'
        Should -Invoke -ModuleName ScoopCore Invoke-WebRequest -Times 0 -Exactly
    }

    It 'allows a safe WhatIf preview from an elevated CI session' {
        Mock -ModuleName ScoopCore Get-InstalledScoopRoot { $null }
        Mock -ModuleName ScoopCore Test-ScoopProcessAdmin { $true }
        Install-ScoopBootstrap -Root 'D:\Scoop' -GlobalRoot 'D:\ScoopGlobal' -WhatIf | Should -Be 'WhatIf'
        Should -Invoke -ModuleName ScoopCore Invoke-WebRequest -Times 0 -Exactly
    }
}

Describe 'Install-ScoopConfiguredPackages' {
    It 'adds required buckets and installs every configured package' {
        Mock -ModuleName ScoopCore Get-ScoopCommandPath { 'D:\Scoop\shims\scoop.ps1' }
        Mock -ModuleName ScoopCore Test-Path { $false }
        Mock -ModuleName ScoopCore Invoke-ScoopCommand {}

        Install-ScoopConfiguredPackages -Root 'D:\Scoop' -Confirm:$false

        Should -Invoke -ModuleName ScoopCore Invoke-ScoopCommand -Times 9 -Exactly
        Should -Invoke -ModuleName ScoopCore Invoke-ScoopCommand -Times 1 -Exactly -ParameterFilter {
            $Arguments -join ' ' -eq 'install extras/alacritty'
        }
        Should -Invoke -ModuleName ScoopCore Invoke-ScoopCommand -Times 1 -Exactly -ParameterFilter {
            $Arguments -join ' ' -eq 'install nerd-fonts/JetBrainsMono-NF'
        }
    }
}

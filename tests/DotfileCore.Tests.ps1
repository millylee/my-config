#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $RepoRoot 'lib/DotfileCore.psm1'
    Import-Module $ModulePath -Force
}

Describe 'Get-WingetPackages' {
    It 'returns exactly the 5 expected package IDs' {
        $pkgs = Get-WingetPackages
        $pkgs.Count | Should -Be 5
        $pkgs | Should -Contain 'Microsoft.PowerShell'
        $pkgs | Should -Contain 'Zellij.Zellij'
        $pkgs | Should -Contain 'Starship.Starship'
        $pkgs | Should -Contain 'Alacritty.Alacritty'
        $pkgs | Should -Contain 'DEVCOM.JetBrainsMonoNerdFont'
    }
}

Describe 'Get-ConfigMap' {
    It 'returns source and target paths for each tool' {
        $map = Get-ConfigMap -RepoRoot $RepoRoot
        $map.Count | Should -Be 4
        ($map | Where-Object Name -eq 'starship').Source | Should -Match 'starship\.toml$'
        ($map | Where-Object Name -eq 'powershell').Target | Should -Match 'Microsoft\.PowerShell_profile\.ps1$'
    }

    It 'all source config files exist in the repo' {
        foreach ($cfg in (Get-ConfigMap -RepoRoot $RepoRoot)) {
            Test-Path -LiteralPath $cfg.Source | Should -BeTrue -Because "missing $($cfg.Source)"
        }
    }
}

Describe 'Deploy-Config (copy mode idempotency)' {
    BeforeEach {
        $script:tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("dotfile-test-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $tmp | Out-Null
        $script:src = Join-Path $tmp 'source.toml'
        $script:dst = Join-Path $tmp 'sub/target.toml'
        Set-Content -LiteralPath $src -Value 'version = 1' -NoNewline
    }

    AfterEach {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
    }

    It 'copies when target does not exist and content matches' {
        $result = Deploy-Config -Source $src -Target $dst
        $result | Should -Be 'Copied'
        Test-Path -LiteralPath $dst | Should -BeTrue
        (Get-Content -LiteralPath $dst -Raw) | Should -Be (Get-Content -LiteralPath $src -Raw)
    }

    It 'skips a second run with identical content and creates no backup' {
        Deploy-Config -Source $src -Target $dst | Out-Null
        $result = Deploy-Config -Source $src -Target $dst
        $result | Should -Be 'Skipped'
        $backups = Get-ChildItem -LiteralPath (Split-Path $dst) -Filter '*.bak' -ErrorAction SilentlyContinue
        $backups | Should -BeNullOrEmpty
    }

    It 'creates a timestamped backup and updates target when source changes' {
        Deploy-Config -Source $src -Target $dst | Out-Null
        Set-Content -LiteralPath $src -Value 'version = 2' -NoNewline
        $result = Deploy-Config -Source $src -Target $dst
        $result | Should -Be 'Copied'
        (Get-Content -LiteralPath $dst -Raw) | Should -Be 'version = 2'
        $backups = Get-ChildItem -LiteralPath (Split-Path $dst) -Filter '*.bak'
        $backups.Count | Should -Be 1
        (Get-Content -LiteralPath $backups[0].FullName -Raw) | Should -Be 'version = 1'
    }

    It '-Force backs up and overwrites even when content is identical' {
        Deploy-Config -Source $src -Target $dst | Out-Null
        $result = Deploy-Config -Source $src -Target $dst -Force
        $result | Should -Be 'Copied'
        $backups = Get-ChildItem -LiteralPath (Split-Path $dst) -Filter '*.bak'
        $backups.Count | Should -Be 1
    }

    It 'throws when the source file does not exist' {
        { Deploy-Config -Source (Join-Path $tmp 'missing.toml') -Target $dst } | Should -Throw
    }
}

Describe 'Install-Package (mock winget)' {
    It 'skips when already installed and does not invoke install' {
        Mock -ModuleName DotfileCore Test-PackageInstalled { $true }
        Mock -ModuleName DotfileCore Invoke-WingetInstall { 0 }

        $result = Install-Package -Id 'Foo.Bar'

        $result | Should -Be 'Skipped'
        Should -Invoke -ModuleName DotfileCore Invoke-WingetInstall -Times 0 -Exactly
    }

    It 'invokes install once when not installed and returns Installed' {
        Mock -ModuleName DotfileCore Test-PackageInstalled { $false }
        Mock -ModuleName DotfileCore Invoke-WingetInstall { 0 }

        $result = Install-Package -Id 'Foo.Bar'

        $result | Should -Be 'Installed'
        Should -Invoke -ModuleName DotfileCore Invoke-WingetInstall -Times 1 -Exactly
    }

    It 'returns Failed when install exits with a non-zero code' {
        Mock -ModuleName DotfileCore Test-PackageInstalled { $false }
        Mock -ModuleName DotfileCore Invoke-WingetInstall { 1 }

        $result = Install-Package -Id 'Foo.Bar'

        $result | Should -Be 'Failed'
    }
}

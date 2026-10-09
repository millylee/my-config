@{
    # main is built into Scoop and does not need to be added explicitly.
    Buckets = @(
        'extras=https://github.com/ScoopInstaller/Extras'
        'nerd-fonts=https://github.com/matthewjberger/scoop-nerd-fonts'
    )

    Packages = @(
        'main/git'
        'main/fnm'
        'main/pnpm'
        'main/pwsh'
        'main/zellij'
        'main/starship'
        'main/neovim'
        'extras/alacritty'
        'extras/googlechrome'
        'nerd-fonts/JetBrainsMono-NF'
    )
}

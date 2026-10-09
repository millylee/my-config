# my-config

面向 Windows、macOS 和 Linux 的个人开发环境一键安装与配置仓库。

目标是让一台新机器通过一个入口完成工具安装、配置部署和后续更新，同时保证脚本可重复执行、失败可见、配置可恢复。

## 平台状态

| 平台 | 状态 | 入口 |
| --- | --- | --- |
| Windows | 可用 | `bootstrap.ps1` |
| macOS | 规划中 | 待实现 |
| Linux | 规划中 | 待实现 |

## Windows

当前可以通过 winget 或 Scoop 安装：

- PowerShell 7
- Zellij
- Starship
- Alacritty
- Neovim
- JetBrainsMono Nerd Font

并部署仓库中的 PowerShell、Zellij、Starship 和 Alacritty 配置。

### Scoop 一键安装

在新机器上直接运行在线入口：

```powershell
$bootstrap = [scriptblock]::Create((irm https://raw.githubusercontent.com/millylee/my-config/master/bootstrap.ps1)); & $bootstrap -PackageManager Scoop
```

已经克隆仓库时，使用本地入口：

使用 Scoop 安装完整工具集并部署配置：

```powershell
./install.ps1 -PackageManager Scoop
```

默认安装位置：

- 存在 D 盘：`D:\Scoop`，全局应用目录为 `D:\ScoopGlobal`
- 没有 D 盘：`%LOCALAPPDATA%\Programs\Scoop` 和 `%LOCALAPPDATA%\Programs\ScoopGlobal`

当前软件默认按用户安装；全局目录为以后显式使用 `scoop install -g` 的软件预先配置。

也可以显式指定：

```powershell
./install.ps1 `
  -PackageManager Scoop `
  -ScoopRoot 'E:\Apps\Scoop' `
  -ScoopGlobalRoot 'E:\Apps\ScoopGlobal'
```

只安装 Scoop 和软件、不部署配置：

```powershell
./windows/install-scoop.ps1
```

该入口使用 Scoop 官方高级安装参数 `-ScoopDir` 和 `-ScoopGlobalDir`，会安装：

```text
main/git
main/fnm
main/pnpm
main/pwsh
main/zellij
main/starship
main/neovim
extras/alacritty
extras/googlechrome
nerd-fonts/JetBrainsMono-NF
```

默认 bucket 和软件清单位于 [`config/scoop.psd1`](config/scoop.psd1)，修改这个文件即可改变仓库默认值。`main` 是 Scoop 内置 bucket，不需要写入 `Buckets`。

Git 会优先安装，再添加额外 bucket 和安装其他软件。fnm 用于管理 Node.js 版本，pnpm 通过 Scoop 安装；此步骤不会自动安装 Node.js 或修改 PowerShell profile。

临时追加软件或 bucket，不修改默认配置：

```powershell
./install.ps1 `
  -PackageManager Scoop `
  -AddScoopBucket 'java=https://github.com/ScoopInstaller/Java' `
  -AddScoopPackage 'java/temurin-lts-jdk' `
  -AddScoopPackage 'extras/vscode'
```

完全覆盖默认软件和 bucket 清单：

```powershell
./install.ps1 `
  -PackageManager Scoop `
  -ScoopBuckets @('extras=https://github.com/ScoopInstaller/Extras') `
  -ScoopPackages @('main/git', 'main/7zip', 'extras/vscode')
```

也可以保留默认文件不动，通过另一份 `.psd1` 整套覆盖：

```powershell
./install.ps1 -PackageManager Scoop -ScoopConfigPath 'D:\Config\my-scoop.psd1'
```

覆盖配置使用与默认文件相同的 `Buckets`、`Packages` 结构。bucket 写成 `名称=仓库地址`，软件写成 `bucket/app`；重复项会按名称忽略。

安全与兼容行为：

- 默认要求普通、非管理员 PowerShell；确需管理员安装时显式传入 `-AllowAdminScoop`
- 已安装 Scoop 但位置与目标不一致时会停止，不自动搬动现有安装
- 安装脚本先下载到临时文件再执行，不直接把网络响应管道给 `Invoke-Expression`
- 仅将执行策略临时设置为当前进程的 `Bypass`，不永久修改用户或系统策略
- `-WhatIf` 会显示安装目录、bucket 和软件清单，不下载或修改系统

### 一键安装

在 PowerShell 中运行：

```powershell
irm https://raw.githubusercontent.com/millylee/my-config/master/bootstrap.ps1 | iex
```

该命令会检查 `winget` 和 Git，将仓库安装或更新到 `$HOME\.dotfiles`，然后运行 Windows 安装脚本。在线脚本会执行仓库 `master` 分支的最新版本；需要固定环境时，请先克隆指定 tag 或 commit，再从本地运行。

### 本地运行

```powershell
git clone https://github.com/millylee/my-config.git "$HOME\.dotfiles"
& "$HOME\.dotfiles\install.ps1"
```

可用参数：

```powershell
# 只部署配置，不安装软件
./install.ps1 -SkipInstall

# 只安装软件，不部署配置
./install.ps1 -SkipConfig

# 备份并重新部署配置
./install.ps1 -Force
```

当 Windows 开发者模式已启用或终端以管理员身份运行时，配置会以符号链接部署；否则会复制文件。覆盖已有配置前会在原位置创建带时间戳的 `.bak` 备份。

### Windows 账户与个人目录

这是一项独立的高影响操作，不会在默认安装时自动执行。它可以：

- 重命名当前本地 Windows 账户
- 将桌面、下载、文档、图片、音乐和视频迁移到指定根目录
- 通过 Windows Known Folder API 更新系统位置，而不是直接修改注册表

先使用 `-WhatIf` 查看完整计划：

```powershell
./windows/setup-user.ps1 `
  -NewUserName milly `
  -UserDataRoot 'D:\Milly' `
  -WhatIf
```

确认路径正确后，在管理员 PowerShell 中执行：

```powershell
./windows/setup-user.ps1 `
  -NewUserName milly `
  -UserDataRoot 'D:\Milly' `
  -Confirm
```

目标结构为：

```text
D:\Milly\
├─ Desktop\
├─ Downloads\
├─ Documents\
├─ Pictures\
├─ Music\
└─ Videos\
```

兼容与安全边界：

- 账户重命名仅支持本地账户，不直接修改微软账户、域账户或 Entra ID 账户
- `C:\Users\原用户名` Profile 目录不会被改名；强改该目录容易导致登录和应用配置损坏
- 检测到 OneDrive 正在管理 Known Folders 时默认停止；应优先使用 OneDrive Known Folder Move
- 目标目录非空时默认停止，避免覆盖；确认需要合并时才使用 `-Force`
- 文件会先复制成功，再更新系统目录位置，最后清理旧位置；API 更新失败时会尝试回滚目录映射
- 操作完成后需要注销并重新登录

### Windows 桌面与资源管理器风格

使用独立的 Shell 设置工具切换 Windows 10 经典右键菜单：

```powershell
./windows/shell-style.ps1 -ContextMenu Windows10 -RestartExplorer
```

恢复 Windows 11 原生右键菜单：

```powershell
./windows/shell-style.ps1 -ContextMenu Windows11 -RestartExplorer
```

不带参数运行会显示当前状态：

```powershell
./windows/shell-style.ps1
```

它还支持以下可逆设置，可以在一次调用中组合：

```powershell
./windows/shell-style.ps1 `
  -FileExtensions Show `
  -HiddenItems Show `
  -ExplorerStart ThisPC `
  -ExplorerSpacing Compact `
  -TaskbarAlignment Left `
  -Widgets Hide `
  -TaskView Hide `
  -TaskbarCombine Never `
  -RestartExplorer
```

所有选项及反向值：

| 选项 | 可用值 |
| --- | --- |
| `-ContextMenu` | `Windows10` / `Windows11` |
| `-FileExtensions` | `Show` / `Hide` |
| `-HiddenItems` | `Show` / `Hide` |
| `-ExplorerStart` | `ThisPC` / `Home` |
| `-ExplorerSpacing` | `Compact` / `Comfortable` |
| `-TaskbarAlignment` | `Left` / `Center` |
| `-Widgets` | `Show` / `Hide` |
| `-TaskView` | `Show` / `Hide` |
| `-TaskbarCombine` | `Always` / `WhenFull` / `Never` |

经典右键菜单依赖 Windows 的兼容性注册项，并非微软公开承诺长期稳定的设置接口，未来大版本可能改变行为。恢复 Windows 11 风格只会删除本工具使用的当前用户兼容项，不替换或修改任何系统文件。建议先加 `-WhatIf` 预演。

`-RestartExplorer` 会关闭当前打开的资源管理器窗口并重启桌面 Shell；也可以不传该参数，稍后注销或重启系统后生效。

## 目录

```text
config/       当前使用的跨工具配置
lib/          安装脚本的 PowerShell 模块
tests/        Pester 测试
windows/      Windows 专用的显式系统配置脚本
bootstrap.ps1 Windows 在线入口
install.ps1   Windows 安装与配置入口
```

## 设计原则

- 重复执行不会破坏已经正确安装的环境
- 覆盖用户配置前先备份
- 安装逻辑与个人配置分离
- 各平台提供一致的入口和参数语义
- 已淘汰脚本不保留在当前工作树，需要时从 Git 历史追溯

## 历史内容

早期的 MiKit Inno Setup 安装器、前端镜像环境变量脚本和旧版 macOS Homebrew 初始化脚本已经从当前工作树删除。需要查看时可通过 Git 历史追溯。

## 开发与测试

Windows 核心逻辑使用 Pester 测试：

```powershell
Invoke-Pester ./tests
```

GitHub Actions 会同时在 Windows PowerShell 5.1 和 PowerShell 7 下执行 Pester 测试，并在 Windows、macOS、Linux runner 上进行 PowerShell 语法兼容检查。Windows runner 还会执行配置部署冒烟测试和用户目录迁移的 `-WhatIf` 安全预演。

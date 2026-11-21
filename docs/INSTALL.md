# WeAlfred 使用指南

WeAlfred 需要 macOS 14 或更新版本。当前打包产物适用于 Apple 芯片 Mac。Intel Mac 可使用下文的源码打包步骤生成适合本机的版本。

## 安装

### 使用现成的应用包

1. 在 Finder 中双击 `dist/WeAlfred.zip`，解压得到 `WeAlfred.app`。如果已有 `dist/WeAlfred.app`，可以直接使用。
2. 将 `WeAlfred.app` 拖到 Finder 的「应用程序」文件夹。
3. 双击「应用程序」里的 WeAlfred。启动后会显示搜索面板，菜单栏也会出现 WeAlfred 图标。

如果 macOS 因开发者身份拦截你自己构建且确认来源的应用，先尝试启动一次，再打开「系统设置」→「隐私与安全性」，在 WeAlfred 的提示下选择「仍要打开」。[Apple 的首次启动说明](https://support.apple.com/zh-cn/102445)

### 从源码构建

首次构建需要带 Swift 6 工具链的 Xcode 或 Command Line Tools。可以用 `xcode-select --install` 安装命令行工具。[Apple 的命令行工具安装说明](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools)

在 WeAlfred 仓库根目录运行打包脚本。然后按上面的步骤安装 `dist/WeAlfred.app`。

```bash
./scripts/package.sh
```

打包脚本生成 `dist/WeAlfred.app` 和 `dist/WeAlfred.zip`，默认进行 ad hoc 签名，无需 Apple Developer 账号。如果钥匙串中已有自签名的代码签名证书和私钥，可在 `WEALFRED_SIGN_IDENTITY` 中填入证书名称或指纹。

```bash
WEALFRED_SIGN_IDENTITY="My Local Code Signing" ./scripts/package.sh
```

安装后可分别验证应用包签名和运行自动测试。测试脚本也会验证 ZIP 解压完整性。

```bash
codesign --verify --strict --verbose=2 /Applications/WeAlfred.app
./scripts/test.sh
```

## 使用

### 用键盘打开项目

1. 按 `⌥ Space` 显示或关闭搜索面板。注册失败时，WeAlfred 会尝试 `⌃⌥ Space`。面板右上角和菜单栏会显示实际启用的快捷键。也可以从菜单栏选择「打开 WeAlfred」。
2. 在长条搜索框中输入名称，例如 `Calculator` 或 `报告`。匹配后会展开结果列表，最多显示 9 项。
3. 用 `↑`、`↓` 选择结果，再按回车或直接点击。也可按行尾标注的 `⌘1` 到 `⌘9` 直接打开对应结果。应用会启动或切换到前台，文件会交给默认程序，目录会在 Finder 中打开。按 `Esc` 关闭面板。

知道路径时，可直接粘贴绝对路径或以 `~/` 开头的路径。输入 `~/Downloads` 后按回车会进入下载目录，输入 `~` 会打开个人主目录。含空格的路径也可直接粘贴。

### 管理文件搜索范围

默认搜索主目录第一层，以及桌面、文稿和下载文件夹中的项目。

- 搜索其他目录时，在菜单栏选择「添加搜索目录…」并选中目标目录。可通过「移除搜索目录」取消相应的自定义范围。
- 新增或移动文件后，可用「刷新搜索索引」更新结果。如果 macOS 询问是否允许读取桌面、文稿或下载，请按需授权后再刷新。
- 如果知道索引范围之外的文件或目录路径，可以直接粘贴完整路径打开。

## 升级

1. 获取新版 `WeAlfred.zip` 并解压，或在新版源码目录运行 `./scripts/package.sh`。
2. 在菜单栏选择「退出 WeAlfred」。
3. 将新版 `WeAlfred.app` 拖到旧版所在位置。按默认方式安装时，该位置是「应用程序」。Finder 提示同名应用时，选择「替换」。
4. 双击新版启动。已添加的搜索目录会在同一 macOS 用户账户中保留。需要时可从菜单栏刷新索引。

## 卸载

1. 在菜单栏选择「退出 WeAlfred」。
2. 打开 Finder，找到「应用程序」中的 `WeAlfred.app`，或前往实际安装位置，将应用移到废纸篓。[Apple 的卸载说明](https://support.apple.com/zh-cn/102610)

移除应用后，可保留已保存的自定义搜索目录供下次安装使用。如需同时清除这份列表，在退出应用后运行下列命令。该命令只删除 WeAlfred 保存的目录路径列表。

```bash
defaults delete local.wealfred.launcher searchFolders
```

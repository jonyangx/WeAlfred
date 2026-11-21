# WeAlfred

WeAlfred 是一个个人 macOS 启动器。它从菜单栏或全局快捷键打开，用于启动应用、打开文件和进入 Finder 目录。

安装、日常使用、升级和卸载步骤见[使用指南](docs/INSTALL.md)。

## 构建和打包

需要 macOS 14 或更新版本和 Swift 6 工具链。使用带有 Swift Testing 的 Xcode 或 Command Line Tools。产物面向编译机器的架构。

| 命令 | 用途 |
| --- | --- |
| `./scripts/build.sh` | 编译 Release 可执行文件，输出路径。可传 `debug`。 |
| `./scripts/package.sh` | 编译、签名并生成 `dist/WeAlfred.app` 和 `dist/WeAlfred.zip`。 |
| `./scripts/test.sh` | 运行测试，并在临时目录打包验证 `.app` 和解压后的签名。 |
| `./scripts/make-icon.sh` | 重新生成应用图标 `Resources/WeAlfred.icns`。 |

打包默认用 `codesign --sign -` 进行本机 ad hoc 签名，无需开发者账户或证书。如果钥匙串中有自签名的代码签名证书和私钥，可通过 `WEALFRED_SIGN_IDENTITY` 指定名称或指纹。可通过 `WEALFRED_OUTPUT_DIR` 指定输出目录。

## 使用

1. 双击 `dist/WeAlfred.app`。需要常用时，可以把它移到 `/Applications`。
2. 用 `⌥ Space` 唤起或关闭面板。如果快捷键注册失败，应用会尝试 `⌃⌥ Space`。面板和菜单栏会显示实际启用的快捷键。
3. 输入名称，或粘贴绝对路径、`~` 或 `~/Downloads` 一类的路径。匹配后展开最多 9 项结果。按 `↑`、`↓` 选择，按回车或点击打开，也可用 `⌘1` 到 `⌘9` 直接打开对应项目。按 `Esc` 关闭。应用除显示名外还匹配 bundle 内的拉丁名称（如输入 `we` 可命中企业微信 WeCom、微信读书 wereader）；搜索结果不包含 WeAlfred 自身。结果按匹配程度排序，同级依次参考：当天新建的项目最优先、经常启动的应用靠前、应用排在目录和文件之前（启动计数仅保存在本机）。
4. 用菜单栏的「添加搜索目录…」扩展文件搜索范围。默认包含主目录第一层和桌面、文稿、下载的子目录。若 macOS 弹出文件夹访问提示，允许访问后可通过「刷新搜索索引」重新读取。

范围与桌面验收步骤见[需求文档](docs/brd/001-init-project.md)。

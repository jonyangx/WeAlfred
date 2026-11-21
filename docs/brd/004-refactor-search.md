1.优化wealfred输入框的颜色，再深色一些，与外框保持一个色差。
2.搜索匹配优化：排除搜索自己，例如we，不要显示wealfred。 字母除了匹配目前应用完，也要匹配应用名，例如企业微信wecom，微信读书wereader，输入we，都要匹配上。


## 实现约定

输入框是面板内图标前的独立长条：圆角深色底（浅色模式约 `#D1D1D1`，深色模式约 `#121212`）加细描边，比面板底色明显更深一档，与外框长条保持清晰色差，随深浅色模式自动适配，布局尺寸不变。

应用匹配范围在「显示名 + 文件名」之外，增加 bundle 信息中的拉丁名称：`CFBundleDisplayName`、`CFBundleName`、`CFBundleExecutable` 和 `CFBundleIdentifier`（含其最后一段，如 `com.tencent.wecom` 命中 `wecom`）。别名命中后，结果仍以本地化显示名展示，排序沿用 BRD 003 规则。

搜索结果排除 WeAlfred 自身（按应用 bundle 路径过滤应用索引与文件索引）；粘贴自身完整路径的直达打开不受影响。

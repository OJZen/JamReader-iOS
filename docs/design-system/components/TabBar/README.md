# TabBar

iPhone 一级导航：书库 · 远程 · 设置（原“浏览”改名“远程”，避免与“浏览书库”混淆）。

## 规则
- 使用系统 `UITabBarController`。iOS 26 起自动呈现为浮动 Liquid Glass 标签栏（图示）；iOS 17–18 回退为标准标签栏，不自绘。
- 图标：`books.vertical` / `server.rack` / `gearshape`，书库与设置选中用 fill 版本，远程仍用 `server.rack`，`accent` 着色。
- 启动时按“设置 → 通用 → 启动时打开”恢复。
- 选择模式的标签栏显隐与版本差异见 [SelectionBar](../SelectionBar/README.md)。

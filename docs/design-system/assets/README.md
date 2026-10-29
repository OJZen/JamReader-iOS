# 设计示意图片

补充设计系统页面稿用的图片：示意封面、示意漫画页，以及 App 图标的候选稿。生成用的提示词见 [PROMPTS.md](PROMPTS.md)。

- 这里的图片**只用于设计稿和评审**，不属于 App 资源。不要复制进 `JamReader/` 目录（该目录被 Xcode 自动收录，会打进安装包）。
- App 图标定稿后，再放进 `JamReader/Assets.xcassets/AppIcon.appiconset`（现有的图标集已建好浅色、深色、tinted 三个 1024 位，但还没有图片）。
- 全部为原创画面，书名虚构，不包含任何现有作品的角色、标志或画风。

## 清单

| 文件 | 尺寸 | 用途 | 状态 |
| --- | --- | --- | --- |
| `app-icon/concept-1.png` … `concept-3.png` | 1024×1024 | 图标方向候选，选定一个再出后续 | 已生成 |
| `app-icon/icon-light.png` | 1024×1024，不透明 | AppIcon 默认 | 选定方向后生成 |
| `app-icon/icon-dark.png` | 1024×1024，透明底 | AppIcon 深色 | 选定方向后生成 |
| `app-icon/icon-tinted.png` | 1024×1024，灰度透明底 | AppIcon tinted | 选定方向后生成 |
| `app-icon/icon-foreground.png` | 1024×1024，透明底 | 前景单独一层，供以后用 Icon Composer 做分层图标 | 选定方向后生成 |
| `covers/cover-01.png` … `cover-09.png` | 600×900（2:3） | 封面网格、继续阅读、远程目录：检验角标、进度条、书名在真实封面上的可读性 | 待生成 |
| `pages/page-01.png` … `page-03.png` | 1200×1800 | 分页阅读器：检验顶栏遮罩与工具在不同明暗画面上的可读性 | 待生成 |
| `pages/strip-01.png` | 800×4000 | 竖向连续阅读（条漫） | 待生成 |

# iPhone Duo

iPhone Duo 有外屏与内屏两块屏幕，中间是铰链。本章说明 JamReader 在它上面怎么摆：沿用现有 iPhone 与 iPad 两套布局，按窗口宽度切换，不为某个姿势单独设计。2026-10-22 定稿，同日二次审查补充了页面边距、系统栏细节与折叠区网格规则。

依据：Apple《Human Interface Guidelines · Designing for iPhone Duo》（2026-09-09），Tech Talk 111461（准备 App）、111462（竖向栏）、111463（保留区与排布）、111466（设计），以及 SwiftUI `ContentMarginGuide.container` 文档。预览卡片 `ScreenDuoLibrary`、`ScreenDuoReader` 中的设备框按比例示意，不是实际点数；规则里不写死任何屏幕尺寸。

## 已确认的决定

| 问题 | 决定 |
| --- | --- |
| 两个受保护的阅读器导航列表 | **只做环境适配**：外观、动效、手势、跳页全部不变；只把“按设备判断”换成“按窗口 / 容器判断”，并避开侧边状态栏、灵动岛与折叠区 |
| 内屏横放（书本形状） | **沿用用户偏好**：不自动切换为双页 |
| 半折姿势 | **只做系统要求的避让**：可交互元素离开折叠区，双页时两页分居两侧；不做桌面姿势专用模式 |

## 环境一览

| 环境 | 宽度类别 | 系统控件位置 | 保留区 | JamReader 用哪套布局 |
| --- | --- | --- | --- | --- |
| 外屏（合上） | 紧凑 | 后缘一列：灵动岛、状态栏、工具栏，标签栏在这一列底部 | 前置摄像头，常驻 | 现有 iPhone 布局 |
| 内屏竖放 | 常规 | 上下水平栏（与普通 iPhone 相同） | 内屏摄像头，仅启用时；半折时横向折叠区 | 现有 iPad 布局（侧栏 + 内容） |
| 内屏横放 | 常规 | 侧边一列（与外屏一致） | 同上；半折时竖向折叠区 | 现有 iPad 布局；半折时两栏由系统调成对称 |
| 内屏分屏多任务 | 按窗口宽度 | 各 App 的外侧边缘（在左边的 App 控件在左） | 同上 | 按窗口宽度：紧凑用 iPhone 布局 |

侧边控件的位置随硬件，不随语言方向：从右到左语言里也不换边。

## 原则

1. **按宽度，不按设备。** 用窗口的尺寸类别与容器宽度做判断；不用 `userInterfaceIdiom`，不用 `UIScreen.main`，不写死屏幕尺寸。iPad 上的结果必须与现在完全一致。
2. **外屏 = iPhone，内屏 = iPad。** 两块屏的信息层级相同，内屏只多显示一层（侧栏）。功能不因屏幕或姿势而缺少。
3. **开合要连续。** 打开、合上、旋转、进出分屏后，保留当前分区、导航层级、滚动位置、选择状态、已打开的 Sheet 和阅读页码；不重新加载列表。因窄屏而暂时不可用的设置（例如双页）只是暂时不显示，不改写已保存的偏好。
4. **只做系统要求的避让。** 按钮、浮层、可拖动的控件不放在折叠区；可滚动的内容可以跨过。不做桌面姿势专用布局，不做按姿势切换的特殊界面。
5. **系统控件交给系统摆放。** 不覆盖默认的侧边 / 水平放置，不自绘侧边栏。微调只通过系统提供的优先级与压缩方式。

## 页面边距

左右边距用系统给的**容器边距**，不写死 16。外屏和内屏横放时，靠近侧边控件那一侧的边距约为 0，内容直接贴到控件列；另一侧保持 16–20。分屏时 App 在左边，控件列在前缘，两侧边距随之对调。

| 实现 | 做法 |
| --- | --- |
| UIKit 列表 / 网格 | `UICollectionViewCompositionalLayout` 的 section 用 `contentInsetsReference = .layoutMargins`（或 `.readableContent`），不在 `contentInsets` 里写死左右值；`insetGrouped` 列表自动跟随 |
| UIKit 自定义视图 | 子视图约束到 `layoutMarginsGuide`，容器 `preservesSuperviewLayoutMargins = true`；滚动视图内容约束到 `contentLayoutGuide`，宽度跟 `frameLayoutGuide` |
| SwiftUI | `List`、`Form` 自动处理，不要再叠加 `.padding(.horizontal)`。自定义滚动内容在 iOS 27.1 起用 `.contentMargins(for: .container)`；更早系统保留现有 `Spacing.md`。社区反馈该 API 在部分 Xcode 27.2 beta 中缺失，用 `if #available` 包住并在正式版 SDK 上确认 |
| 计算宽度 | 每一侧单独取：`bounds.inset(by: safeAreaInsets)`，不要写 `width - inset * 2` |
| 不改的 | 受保护导航列表的内部间距；卡片、封面之间的间距 token |

`space-md` 仍是 token 值，但只作为没有系统边距可用时（iOS 27.1 之前的 SwiftUI 自定义视图）的回退值。

## 书库 · 远程 · 设置

| 项 | 规则 |
| --- | --- |
| 外壳 | 三个分区的 split view **始终创建**，由系统在紧凑宽度折成单栏（等于现在的 iPhone 导航）、在常规宽度展开（等于现在的 iPad 侧栏）。展开 / 折叠时保留选中项与导航层级 |
| 侧栏宽度 | 不写死 320；用系统默认或“比例 + 最小 / 最大值”，让系统能在半折时把两栏调成对称 |
| 侧栏常驻判断 | “侧栏是否同屏可见”看 split view 是否展开（`isCollapsed == false`），不看设备；注意侧栏所在列本身报告紧凑尺寸类别 |
| 不用标签栏侧栏 | 不开启 `tabBarController.sidebar.preferredPlacement = .sidebar` / `.defaultTabBarPlacement(.sidebar)`：每个分区已有自己的侧栏，再开会出现两层侧栏 |
| 只有系统栏会竖排 | 只有 `UINavigationController` / `UITabBarController` 管理的栏（SwiftUI `.toolbar` + `NavigationStack` / `NavigationSplitView`）会进侧边列。自建的 `UIToolbar`、`UINavigationBar`、`UITabBar` 或浮动按钮条不会——工具栏动作都要走系统栏 |
| 哪一栏竖排 | split view 只有内容（detail）栏的工具栏项进侧边列；侧栏自己的控件（如“我的书库”旁的 +）留在侧栏顶部，靠近它作用的内容 |
| 工具栏项 | 每项同时给标题与 SF Symbol（`Label` / `UIBarButtonItem` 的 title + image），系统按位置挑选显示方式；标题一定要有，溢出菜单里要用。“选择”显示为 `checkmark.circle`，标题仍为“选择”。文字本身带信息的按钮（“全选 / 全不选”）设 `axisBehavior = .horizontalOnly`，留在导航栏 |
| 侧边列顺序 | 自上而下：返回 / 关闭（自定义的用 `.cancellationAction` / 前导项）→ 主要动作（用 `.topBarPinnedTrailing` / `navigationItem.pinnedTrailingGroup`）→ 其余按原分组。书库首页 [+]；书库内容 选择 · ⋯；远程目录 图钉 · ⋯；服务器详情 ⋯ |
| 选择模式 | 底部动作（标为已读、收藏、标签与列表、删除）改用系统底部工具栏项，外屏会自动竖排；“完成”为主要动作钉在最上；“更多”的内容并入系统溢出菜单，不再单独放一个“更多”。见 `ScreenDuoLibrary` |
| 溢出 | iOS 27 起把页面自己的 ⋯ 菜单内容并入系统溢出菜单（`additionalOverflowItems` / `ToolbarOverflowMenu`），同一屏只有一个 ⋯。⋯ 只用于溢出；排序等其它菜单用各自的符号。iOS 26 及以下保持现在的 ⋯ 菜单 |
| 优先级 | 默认从下往上收起。最后才收起：书库首页 [+]、远程目录图钉（同时显示“已保存”状态）、选择模式的“完成”与“标为已读”。用 `visibilityPriority`（UIKit `item.visibilityPriority`，SwiftUI `.visibilityPriority`），先设分组再设单项 |
| 数量 | 需要显示数量的符号按钮用系统徽标（`item.badge = .count(n)` / `.badge(n)`），不要做成“文字 + 数字”的按钮，否则它会留在水平栏 |
| 压缩方式 | 书库、远程、设置的浏览页用默认方式（工具栏项先收起，保留标签栏）。选择模式是任务型，`verticalBarCompressionBehavior = .prefersBarItems` / `.toolbarVerticalCompressionBehavior(.prefersToolbarItems)` |
| 不加额外间距 | 栏周围不加自定义间距，也不在侧边列旁边再留白（见“页面边距”） |
| Sheet | 外屏的 Sheet 工具栏也会竖排。只有一个“取消 / 关闭”按钮、内容是一排大卡片的 Sheet（“添加漫画”）可以关闭竖排（`preferredVerticalBarBehavior = .disabled` / `.toolbarVerticalBehavior(.disabled)`），在 Device Hub 对比后决定；表单类 Sheet（取消 + 保存）保持竖排 |
| 网格列数 | 照常按容器宽度与现有最小宽度 token 计算 |
| 横跨竖向折叠区的网格 | 只针对自定义的全宽网格（侧栏收起时的书库网格、远程目录网格、阅读器缩略图总览）：只要存在折叠区（查询时包含未启用区域）就用偶数列，左右各一半；**外侧边距不变，加大折痕两侧的间距**，让中缝对准折痕；列宽相同。开合时只改中缝，不重排 |
| 浮动元素 | `TaskBanner`、`Toast`、空状态按钮：在安全区内；竖向折叠区启用时，原本居中的元素放进后缘一侧区域（与系统把 Alert 放到后缘一致），不横跨折叠区。靠近屏幕圆角的浮动容器用同心圆角（`UICornerConfiguration` / `ConcentricRectangle`） |
| Sheet / Alert / 菜单 / popover | 交给系统（自动避让折叠区，外屏 Sheet 停在摄像头前）。不自己改位置 |
| 背景与前景 | 背景（分组底色、阅读器黑底）可以铺满到屏幕边缘；文字、按钮、封面等前景留在安全区内 |

## 阅读器

| 项 | 规则 |
| --- | --- |
| 单页 / 双页 | 双页只在常规宽度提供（现有 `supportsDoublePageSpread`）。内屏按用户偏好显示，不自动切换。外屏或紧凑分屏窗口暂时显示单页，**不改写**偏好；回到内屏恢复。切换时停在同一阅读页 |
| 双页的位置 | 跨页中心对准折痕（division 区域中线，查询时包含未启用区域），不用安全区中心——侧边状态栏让安全区左右不对称。平放时两页按现有方式相接；半折时两页分居折叠区两侧，各自适应自己一侧 |
| 单页在内屏横放 | 居中，会跨过折痕。这是内容，允许；点按区域不变 |
| 画面视口 | 由窗口与安全区决定，不用 `UIScreen.main`。外屏避开常驻的摄像头保留区；依据常驻的保留区而不是会随状态栏显隐变化的值，保证工具显隐时画面不动 |
| 顶栏 | 保持水平：返回 · 书名 · [书签 · Aa · ⋯]。整体在安全区内，避开后缘的状态栏 / 灵动岛列；左右用容器边距，靠侧边列那一侧不再留白。它是阅读器自绘的控件，不会进系统侧边列，这是有意的。半折时返回 + 书名在前缘一侧、三键在后缘一侧，书名在折痕前截断。不改成侧边竖排：阅读器是沉浸界面，竖向模式的受保护轨道就在后缘 |
| 显示面板（Aa） | 紧凑宽度用底部浮动面板，常规宽度用 popover（系统避让折叠区）。按尺寸类别判断，不按设备 |
| 更多（⋯） | 系统菜单，自动避让 |
| 跳页浮层 | 用窗口高度替代 `UIScreen.main`；不横跨折叠区：竖向折叠时放后缘一侧，横向折叠时放下半区 |
| 缩略图总览 | 列数按容器宽度（替代“iPad 3 列 / iPhone 2 列”）；横跨竖向折叠区时按上面的偶数列规则 |
| 跨本导航胶囊 | 位置与行为不变；若与折叠区重叠，放进后缘一侧 |
| 方向锁 | 内屏会忽略 App 声明的支持方向。阅读器里的“旋转（仅本次）”只旋转画面，行为不变。外屏横放照常可读 |
| 内屏摄像头 | 内屏前置摄像头只在启用时成为保留区；阅读器顶栏按安全区布局即可，不为它单独处理 |

### 受保护导航列表 · 只做环境适配

适用于 `ReaderBottomBar`（`ReaderThumbnailScrubber`、浮动预览、页码胶囊）与 `ReaderVerticalThumbnailRail`。

| 现在 | 改为 | 不变 |
| --- | --- | --- |
| 档位按 `userInterfaceIdiom == .pad` 选 iPad / iPhone 数值 | 档位 = iPad，**或**窗口宽度类别为常规 → iPad 数值；其余 → iPhone 数值。iPad 结果与现在一致；Duo 内屏用 iPad 档，外屏与紧凑分屏用 iPhone 档。已有的“视口宽度 ≥ `regularReaderLayoutMinWidth`”判断保留 | 两档内的所有数值 |
| 视口回退到 `UIScreen.main.bounds` | 回退到所在窗口的 bounds | 计算方式 |
| 容器 = 全宽 / 全高 | 容器在安全区内（避开侧边列）。半折时限制在一个可用区域：底部列表在竖向折叠时放后缘一侧，横向折叠时它本就在下半区；右侧轨道在横向折叠时限制在下半区，竖向折叠时它本就在后缘 | 外观、尺寸、动效、显隐、手势、跳页 |

档位由窗口决定，不由半折后变窄的容器决定：开合时缩略图大小不跳变，容器变窄只改变能看到的缩略图数量。

## 工程要求

- 用 Xcode 27.1（iOS 27.1 SDK）构建才能铺满两块屏；未重新编译的版本会以信箱模式显示。最低系统仍为 iOS 17.6，Duo 专用 API 放在 `if #available(iOS 27.0, *)` 中。
- 不加 `UIRequiresFullScreen`。保留区查询：SwiftUI `reservedRegions(kind:)`，UIKit `UIView.reservedRegions(kind:)`；折叠区为 `.division`，摄像头为 `.occlusion`；决定列数时带 `.includeInactive`。
- 根标签栏现在在 iOS 18 起设 `mode = .tabBar`：在 Device Hub 确认它不妨碍系统把标签栏放到侧边；若妨碍，iOS 27 起不再设置。
- 判断用尺寸类别，不用设备方向：查找并替换 `UIDevice.current.orientation`、`interfaceOrientation.isLandscape` 等用于布局的方向判断。
- 外屏横放（立成帐篷状）也要可用：外屏横放是紧凑宽 × 紧凑高，侧边列空间最少、最容易溢出；不要锁定竖屏。内屏会忽略 App 声明的方向。
- 测试：Xcode Device Hub 的 iPhone Duo——合上、内屏竖放 / 横放、书本半折、桌面姿势、分屏在左 / 在右；浅色 / 深色、AX5、减少透明度（侧边列会出现底色，内容仍要清晰）、四种语言；Xcode 27.1 的 App Resizability 技能可用来辅助检查；iPhone 与 iPad 的受保护组件截图与改动前逐像素一致。

## 不在本次范围

桌面姿势专用阅读模式、按姿势自动切换单双页、为外屏单独设计的页面、自绘侧边栏、改动两个受保护导航列表的外观。

# 落地到代码

## Token → Swift

| 本系统 | `DesignTokens.swift` / 资源 | 做法 |
| --- | --- | --- |
| `accent` | `Assets.xcassets/AccentColor` | 填入 Any #9B1E56、Dark #E886B2；`Color.appAccent` 不变 |
| `jam` / `on-jam` | 新增 `Color.appJam`（资源 `Jam`）、`Color.appOnJam` | Jam：Any #9B1E56、Dark #C23A76；OnJam：白。实心主按钮用 `.buttonStyle(.borderedProminent).tint(.appJam)`，不要继承 AccentColor（深色下太亮，白字不可读）；进度条、选中勾也用它 |
| `jam-deep` | `Color.appJamDeep`（资源 `JamDeep`） | #5C1233，只给 App 图标、启动画面等品牌色块 |
| `reader-accent` | `Color.appReaderAccent`（资源 `ReaderAccent`） | #E886B2，两种外观同值；阅读器内的书签已加、准备阅读进度 |
| `accent-soft`、`accent-on-soft` | `Color.appAccentSoft`、`Color.appAccentOnSoft`（资源 `AccentSoft`、`AccentOnSoft`） | 选中的筛选标签、轻提示 |
| `bg` / `bg-grouped` / `surface` / `surface-2` | `surfacePrimary` / `surfaceGrouped` / `surfaceGroupedSecondary` / `surfaceSecondary` | 已是系统色，保持 |
| `ink` / `ink-2` / `ink-3` | `textPrimary` / `textSecondary` / `textTertiary` | 保持 |
| `success` / `offline` / `warning` / `danger` / `favorite` 及各 `-soft` | `Color.appSuccess` / `appOffline` / `appWarning` / `appDanger` / `appFavorite`，`appSuccessSoft` 等（资源 `Status*`、`Status*Soft`）；`statusRead` / `statusStale` / `statusCached` 为别名 | 用资源色（含深色值）替代 `.green.opacity(0.8)` 等；`-soft` 也做成资源色，以对上 token 的原值 |
| `space-*` | `Spacing` | 数值不变 |
| `radius-cover` | `CornerRadius.thumbnail` 10 → 6 | 只影响封面（第 1 批时该常量无引用，封面圆角仍是各处字面量，随第 2 批封面改为引用它）。已核对：两个阅读器导航列表用字面量圆角（13 / ≤8），只引用 `Spacing` 与 `AppFont`，本次都不改值，因此不受影响 |
| `size-grid-min-compact` | 新增 `AppLayout.gridItemMinWidthCompact = 100` | iPhone 网格 3 列 |
| `size-shelf-cover` | 新增 `AppLayout.shelfCoverWidthCompact = 112`、`shelfCoverWidthRegular = 140` | 继续阅读卡带 |
| `shadow-*` | `AppShadow` | 数值不变 |
| `chart-downloads` / `chart-temp` / `chart-thumbs` | `Color.appChartDownloads` / `appChartTemp` / `appChartThumbs`（资源 `Chart*`） | 只用于存储占用条，替代借用 `.blue` / `.orange` |
| `reader-title` | `ReaderTopBar` 书名 `AppFont.headline()` | 顶栏不再有页码副标题 |

工程开启了资源符号生成：每个颜色资源会自动生成同名的 `Color` / `UIColor` 成员（如 `Color.jam`、`Color.statusOffline`）。`DesignTokens.swift` 中的颜色因此统一用 `app` 前缀，不要再声明与资源同名的成员；UIKit 代码用 `UIColor(resource: .jam)`。

## 组件 → 文件

| 组件 | 主要改动位置 |
| --- | --- |
| TabBar | `AppNavigationSupport.swift`（`AppRootTab.browse` 改标题“远程”、图标 `server.rack`）；标签标题、远程首页大标题、“启动时打开”选项同用 `Remote` 文案 |
| Sidebar | `SidebarSelectionStyle.swift`（集中修改选中样式） |
| ComicCover / ComicRow / FolderAndCollection | `LibraryBrowserComponents.swift`、`LocalCoverThumbnailView.swift`、`RemoteBrowseCardComponents.swift`、`RemoteServerBrowserComponents.swift`、`LibraryOrganizationCollectionCard.swift` |
| StatusBadge | `StatusBadge.swift`（`StatusBadge.Status`：远程副本五态 + 已读 / 只读 / 需要重新授权；`RemoteComicCachedAvailability.statusBadgeStatus` 映射缓存状态） |
| ContinueReading | 新组件，书库首页与书库根目录、服务器详情共用 |
| TaskBanner | `LibraryImportProgressView.swift` 扩展为通用任务条（含结果态） |
| Notice / EmptyState | `ErrorStateView.swift`、`EmptyStateView.swift` |
| FilterChips | `FilterChipBar.swift`、`LibraryComicFilterBar.swift` |
| MoreMenu | `LibraryComicQuickActionsSheet.swift`、远程目录 `RemoteServerBrowserView` 中的菜单 |
| ReaderTopBar / ReaderDisplayPanel / ReaderMoreMenu | `ReaderChromeOverlay.swift`（只改 `ReaderTopBar`）、`Features/Reader/ReaderDisplayPanel.swift`、`ComicReaderView.swift`（更多菜单复用 `LibraryComicMenuContent`）；第 4 批已删除整屏 `ReaderControlsSheet.swift` |
| 设置“继续阅读显示在” | `SettingsSections.swift` 书库分区 + 新偏好键；`LibraryHomeView` 与 `LibraryBrowserView` 读同一偏好决定是否显示卡带 |
| **不改** | `ReaderBottomBar`、`ReaderThumbnailScrubber`、`ReaderVerticalThumbnailRail`、`ReaderPageThumbnailSupport` 中服务于两者的样式 |

## 建议分批

每批的任务清单、对照卡片与验收标准见“分批实施计划”章节（`05-batches.md`）。

1. **基础**：AccentColor 与状态色资源、`StatusBadge` 五态、“远程”改名。风险最低，立即统一观感。
2. **书库**：添加漫画 Sheet、书库内容页工具栏整理、面包屑、iPhone 封面网格、移除 Status 分区与重复入口。
3. **远程**：服务器详情主按钮、快捷区去重、远程漫画菜单三组、离线书架移除整服务器清空。
4. **阅读器**：顶栏三键、显示面板、更多菜单（不碰两个导航列表）。
5. **功能变化（已确认）**：首页汇总继续阅读 + “继续阅读显示在”设置；集合页快捷筛选。

## 验收

- 四个代表场景先走通：书库内容、远程目录、阅读器工具、导入流程。
- iPhone 与 iPad（含分屏、旋转），浅色 / 深色，Dynamic Type 到 AX5，VoiceOver，减弱动态效果。
- 四种语言文字长度。
- 逐屏检查：同一屏没有相同范围、相同后果的重复按钮；合并后原任务都能完成。
- 阅读器：没有新增误退出、误翻页或位置丢失；两个导航列表截图与改版前逐像素一致。

## iPhone Duo → 代码

规则见 `06-iphone-duo.md`，任务见第 6 批。

| 现在 | 位置 | 改为 |
| --- | --- | --- |
| `usesSplitLayout = userInterfaceIdiom == .pad` | `AppRootTabBarControllerView.swift` 287 / 613 / 1041 | split view 始终创建，系统按宽度折叠 / 展开 |
| `preferredPrimaryColumnWidth = 320` | 同上 294 / 620 | 系统默认或比例 + 最小 / 最大值，让半折时能对称 |
| `usesPersistentSplitSelection(isPad:)`、`LibraryHomeView.isPad` | `DesignTokens.swift` 191；`LibraryHomeView.swift` | 看 split view 是否展开 |
| 按 idiom 的列数 / 档位 | `RemoteServerBrowserGridUIKitView` 482 / 573；`ReaderThumbnailBrowserUIKitView` 59 / 673 | 按容器宽度与尺寸类别 |
| `UIScreen.main.bounds` | `ReaderChromeOverlay` 283；`ReaderPageJumpOverlay` 181；`RemoteServerBrowserView` 785 | 所在窗口的 bounds |
| `UIScreen.main.scale` | `ReaderThumbnailBrowserUIKitView` 728；`RemoteServerBrowserList/GridUIKitView` | `traitCollection.displayScale` |
| 受保护组件的 `isPad` | `ReaderChromeOverlay` 58–60、618–621；`ReaderVerticalThumbnailRail` 780–851 | iPad 或常规宽度窗口 → iPad 档；数值不变 |
| 折叠区 / 摄像头 | 新增 | iOS 27：`UIView.reservedRegions(kind:)` / SwiftUI `reservedRegions(kind:)`，`.division`、`.occlusion`，决定列数时 `.includeInactive` |
| 写死的左右边距 | SwiftUI `.padding(.horizontal, …)` / `scenePadding`；collection view `contentInsets` | 系统容器边距：`layoutMarginsGuide`、`contentInsetsReference = .layoutMargins`、iOS 27.1 `.contentMargins(for: .container)` |
| 自建栏 / 自绘按钮条 | 选择模式底栏等 | 系统栏项（只有系统栏会进侧边列） |
| 工具栏位置与轴向 | 新增 | `.cancellationAction`、`.topBarPinnedTrailing` / `pinnedTrailingGroup`；`axisBehavior`（`.horizontalOnly`）；徽标 `item.badge` / `.badge`；压缩 `verticalBarCompressionBehavior` |
| 工具栏优先级与溢出 | 新增 | iOS 27：`UIBarButtonItemVisibilityPriority`、`additionalOverflowItems`；SwiftUI 对应 `ToolbarItemVisibilityPriority`、`ToolbarOverflowMenu` |

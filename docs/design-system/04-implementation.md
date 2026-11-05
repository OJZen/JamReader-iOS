# 设计与代码映射

本页用于定位实现。视觉规则见 [基础](00-foundations.md)，数值来源为 `tokens.json`；与静态稿的差异见 [实现取舍与能力边界](05-batches.md)。

## Token → Swift

| 本系统 | `DesignTokens.swift` / 资源 | 用途 |
| --- | --- | --- |
| `accent` | `Color.appAccent` / `AccentColor` | 可点文字与图标 |
| `jam` / `on-jam` | `Color.appJam` / `Color.appOnJam`，资源 `Jam` / `OnJam` | 实心按钮、进度与选中标记 |
| `jam-deep` | `Color.appJamDeep` / `JamDeep` | 品牌色块 |
| `reader-accent` | `Color.appReaderAccent` / `ReaderAccent` | 阅读器书签等强调标记；加载进度条用 `appJam` |
| `accent-soft` / `accent-on-soft` | `Color.appAccentSoft` / `Color.appAccentOnSoft` | 筛选选中态 |
| `bg` / `bg-grouped` / `surface` / `surface-2` | `surfacePrimary` / `surfaceGrouped` / `surfaceGroupedSecondary` / `surfaceSecondary` | 系统语义背景 |
| `ink` / `ink-2` / `ink-3` | `textPrimary` / `textSecondary` / `textTertiary` | 系统语义文字 |
| 状态色与已有的 `-soft` | `Color.appSuccess` / `appOffline` / `appWarning` / `appDanger` / `appFavorite`，以及已有的 `app*Soft` 资源 | `statusRead` / `statusStale` / `statusCached` 为别名；`favorite` 没有对应的 `-soft` token |
| `space-*` / `shadow-*` | `Spacing` / `AppShadow` | 间距与阴影 |
| `radius-cover` | `CornerRadius.thumbnail` | 封面圆角；受保护导航不引用它 |
| `size-grid-min-compact` | `AppLayout.gridItemMinWidthCompact` | 紧凑窗口网格最小宽度，实际列数由容器决定 |
| `size-shelf-cover` | `AppLayout.shelfCoverWidthCompact` / `shelfCoverWidthRegular` | 首页继续阅读卡带 |
| `chart-*` | `Color.appChartDownloads` / `appChartTemp` / `appChartThumbs` | 存储占用条 |
| `reader-title` | `ReaderTopBar` 的 `AppFont.headline()` | 书名；顶栏不显示页码 |

工程开启资源符号生成。`DesignTokens.swift` 的颜色别名用 `app` 前缀，避免与自动生成的 `Color.jam` 等重名；UIKit 使用 `UIColor(resource: .jam)`。数值变更必须遵守 [受保护组件约束](03-reader.md#原样保留不在设计范围)。

## 组件 → 文件

| 组件或页面 | 实现位置 |
| --- | --- |
| TabBar / Sidebar | `AppNavigationSupport.swift`、`AppRootTabBarControllerView.swift`、`SidebarSelectionStyle.swift` |
| ComicCover / ComicRow / FolderAndCollection | `LibraryCoverComponents.swift`、`LibraryBrowserView.swift`、`LocalCoverThumbnailView.swift`、`RemoteBrowseCardComponents.swift`、`RemoteServerBrowserComponents.swift` |
| StatusBadge | `StatusBadge.swift`；远程展示由 `RemoteServerBrowserViewModel.offlineCopyAvailability` 先限定离线副本范围 |
| ContinueReading | `LibraryBrowserComponents.swift` 的 `ContinueReadingCard`；首页汇总在 `LibraryHomeContinueReading.swift` 与 `LibraryContinueReadingAggregate.swift`；服务器详情有自己的历史卡带 |
| TaskBanner | `LibraryImportProgressView.swift` |
| Notice / EmptyState | `NoticeView.swift`、`ErrorStateView.swift`、`EmptyStateView.swift` |
| FilterChips | `FilterChipBar.swift`、`LibraryComicFilterBar.swift` |
| MoreMenu | `LibraryComicActionMenu.swift`；远程动作在 `RemoteServerBrowserComponents.swift`、`RemoteServerBrowserView.swift` |
| ReaderTopBar / ReaderDisplayPanel / ReaderMoreMenu | `ReaderChromeOverlay.swift`、`ReaderDisplayPanel.swift`、`ComicReaderView.swift` |
| 继续阅读位置偏好 | `ContinueReadingPlacement.swift`、`LibraryPreferencesStore.swift`、`SettingsSections.swift`；首页与书库内容页读取同一偏好 |

## 窗口与系统栏适配

| 职责 | 实现位置 |
| --- | --- |
| 分栏创建、折叠 / 展开时移交页面、侧栏可见状态 | `AdaptiveSplitShell.swift`、`AppRootTabBarControllerView.swift` |
| 系统溢出菜单、工具栏优先级与轴向、浮层避开竖向折痕 | `AdaptiveBarSupport.swift`；版本边界见 [系统适配](05-batches.md#系统适配) |
| 系统容器边距及旧系统回退 | `DesignTokens.swift` 的 `containerHorizontalMargins()` |
| 书库与远程目录的跨折痕网格 | `FoldSplitGridMetrics.swift`、`LibraryBrowserView.swift`、`RemoteServerBrowserGridUIKitView.swift` |
| 阅读器窗口回退与导航档位 | `ReaderChromeOverlay.swift` 的 `ReaderViewportResolver` / `ReaderNavigationTier`；右侧轨道共用档位 |
| 缩略图总览列数与像素尺寸 | `ReaderThumbnailBrowserUIKitView.swift`，按尺寸类别、容器宽度与 `displayScale` |

适配规则与尚未接入的部分见 [iPhone Duo](06-iphone-duo.md)。验证命令与要求统一见 [开发流程](../development-workflow.md#validation-by-change-type) 和 [UI 检查清单](../ui-guidelines.md#change-checklist)。

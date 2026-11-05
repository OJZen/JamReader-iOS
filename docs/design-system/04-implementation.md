# Design-to-Code Mapping

Use this page to locate implementations. See [foundations](00-foundations.md) for visual rules; `tokens.json` owns numeric values. See [implementation decisions and capability limits](05-batches.md) for differences from static mockups.

## Token → Swift

| Design system | `DesignTokens.swift` / assets | Purpose |
| --- | --- | --- |
| `accent` | `Color.appAccent` / `AccentColor` | Tappable text and icons |
| `jam` / `on-jam` | `Color.appJam` / `Color.appOnJam`, assets `Jam` / `OnJam` | Solid buttons, progress, and selection markers |
| `jam-deep` | `Color.appJamDeep` / `JamDeep` | Brand blocks |
| `reader-accent` | `Color.appReaderAccent` / `ReaderAccent` | Reader emphasis such as bookmarks; loading progress uses `appJam` |
| `accent-soft` / `accent-on-soft` | `Color.appAccentSoft` / `Color.appAccentOnSoft` | Selected filters |
| `bg` / `bg-grouped` / `surface` / `surface-2` | `surfacePrimary` / `surfaceGrouped` / `surfaceGroupedSecondary` / `surfaceSecondary` | System semantic backgrounds |
| `ink` / `ink-2` / `ink-3` | `textPrimary` / `textSecondary` / `textTertiary` | System semantic text |
| Status colors and existing `-soft` variants | `Color.appSuccess` / `appOffline` / `appWarning` / `appDanger` / `appFavorite`, and existing `app*Soft` assets | `statusRead` / `statusStale` / `statusCached` are aliases; `favorite` has no matching `-soft` token |
| `space-*` / `shadow-*` | `Spacing` / `AppShadow` | Spacing and shadows |
| `radius-cover` | `CornerRadius.thumbnail` | Cover corners; protected navigation does not reference it |
| `size-grid-min-compact` | `AppLayout.gridItemMinWidthCompact` | Compact-window minimum grid width; the container determines actual column count |
| `size-shelf-cover` | `AppLayout.shelfCoverWidthCompact` / `shelfCoverWidthRegular` | Home Continue Reading strip |
| `chart-*` | `Color.appChartDownloads` / `appChartTemp` / `appChartThumbs` | Storage usage bar |
| `reader-title` | `AppFont.headline()` in `ReaderTopBar` | Book title; the top bar has no page number |

The project enables asset symbol generation. Color aliases in `DesignTokens.swift` use the `app` prefix to avoid collisions with generated names such as `Color.jam`; UIKit uses `UIColor(resource: .jam)`. Value changes must follow [protected-component constraints](03-reader.md#preserve-unchanged-outside-design-scope).

## Component → File

| Component or page | Implementation |
| --- | --- |
| TabBar / Sidebar | `AppNavigationSupport.swift`, `AppRootTabBarControllerView.swift`, `SidebarSelectionStyle.swift` |
| ComicCover / ComicRow / FolderAndCollection | `LibraryCoverComponents.swift`, `LibraryBrowserView.swift`, `LocalCoverThumbnailView.swift`, `RemoteBrowseCardComponents.swift`, `RemoteServerBrowserComponents.swift` |
| StatusBadge | `StatusBadge.swift`; remote presentation first limits scope to offline copies through `RemoteServerBrowserViewModel.offlineCopyAvailability` |
| ContinueReading | `ContinueReadingCard` in `LibraryBrowserComponents.swift`; home aggregation in `LibraryHomeContinueReading.swift` and `LibraryContinueReadingAggregate.swift`; server details have their own history strip |
| TaskBanner | `LibraryImportProgressView.swift` |
| Notice / EmptyState | `NoticeView.swift`, `ErrorStateView.swift`, `EmptyStateView.swift` |
| FilterChips | `FilterChipBar.swift`, `LibraryComicFilterBar.swift` |
| MoreMenu | `LibraryComicActionMenu.swift`; remote actions in `RemoteServerBrowserComponents.swift`, `RemoteServerBrowserView.swift` |
| ReaderTopBar / ReaderDisplayPanel / ReaderMoreMenu | `ReaderChromeOverlay.swift`, `ReaderDisplayPanel.swift`, `ComicReaderView.swift` |
| Continue Reading placement preference | `ContinueReadingPlacement.swift`, `LibraryPreferencesStore.swift`, `SettingsSections.swift`; home and library content pages read the same preference |

## Window and System Bar Adaptation

| Responsibility | Implementation |
| --- | --- |
| Split-view creation, page handoff on collapse/expansion, sidebar visibility | `AdaptiveSplitShell.swift`, `AppRootTabBarControllerView.swift` |
| System overflow menus, toolbar priority and axis, overlays avoiding vertical creases | `AdaptiveBarSupport.swift`; see [system adaptation](05-batches.md#system-adaptation) for version boundaries |
| System container margins and older-system fallback | `containerHorizontalMargins()` in `DesignTokens.swift` |
| Library and remote-directory grids spanning a crease | `FoldSplitGridMetrics.swift`, `LibraryBrowserView.swift`, `RemoteServerBrowserGridUIKitView.swift` |
| Reader window fallback and navigation tiers | `ReaderViewportResolver` / `ReaderNavigationTier` in `ReaderChromeOverlay.swift`; the right-side track shares the tier |
| Thumbnail overview columns and pixel dimensions | `ReaderThumbnailBrowserUIKitView.swift`, based on size class, container width, and `displayScale` |

See [iPhone Duo](06-iphone-duo.md) for adaptation rules and parts not yet connected. [Development workflow](../development-workflow.md#validation-by-change-type) and the [UI checklist](../ui-guidelines.md#change-checklist) own validation commands and requirements.

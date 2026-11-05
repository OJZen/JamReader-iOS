# iPhone Duo

iPhone Duo has outer and inner displays with a hinge between them. This chapter describes JamReader's layout on it: reuse the existing iPhone and iPad layouts, switching by window width rather than designing for individual postures. Shell, list, and reader window adaptation is connected; reader crease and camera geometry remain design constraints. See [implementation limits](05-batches.md#environment-adaptation-not-yet-connected) for the gaps.

Sources: Apple's Human Interface Guidelines · Designing for iPhone Duo (2026-09-09), Tech Talks 111461 (prepare your app), 111462 (vertical bars), 111463 (reserved regions and layout), 111466 (design), and the SwiftUI `ContentMarginGuide.container` documentation. Device frames in `ScreenDuoLibrary` and `ScreenDuoReader` preview cards are proportional illustrations, not actual point dimensions. These rules hard-code no screen dimensions.

## Confirmed Decisions

| Question | Decision |
| --- | --- |
| Two protected reader navigation lists | **Environment adaptation only**: appearance, animation, gestures, and page jumps remain unchanged. Replace device-based decisions only with window/container decisions and avoid the side status bar, Dynamic Island, and fold region |
| Inner display in landscape (book shape) | **Follow user preference**: do not automatically switch to double pages |
| Half-folded posture | **Only system-required avoidance**: keep interactive elements out of the fold region and place double pages on separate sides; no tabletop-specific mode |

## Environment Overview

These system-environment references guide the design; they do not mean every posture has passed device acceptance checks.

| Environment | Width class | System control placement | Reserved region | JamReader layout |
| --- | --- | --- | --- | --- |
| Outer display (closed) | Compact | A trailing column: Dynamic Island, status bar, toolbar, with the tab bar at the bottom of the column | Front camera, permanent | Existing iPhone layout |
| Inner display in portrait | Regular | Horizontal bars at top and bottom (like ordinary iPhone) | Inner camera only while active; horizontal fold region when half-folded | Existing iPad layout (sidebar + content) |
| Inner display in landscape | Regular | A side column (like the outer display) | Same as above; vertical fold region when half-folded | Existing iPad layout; the system makes the two columns symmetric when half-folded |
| Inner-display split-view multitasking | By window width | Each app's outer edge (the left app's controls are on the left) | Same as above | By window width: compact uses iPhone layout |

Side controls follow hardware, not language direction; they do not switch sides in right-to-left languages.

## Principles

These constraints continue to guide maintenance. Geometry not yet connected must not be described as implemented based on these rules.

1. **Use width, not device.** Decide using window size classes and container width, not `UIScreen.main` or hard-coded screen dimensions. Protected navigation keeps its iPad-device-first tier rule; see below.
2. **Outer display = iPhone, inner display = iPad.** Both displays have the same information hierarchy; the inner display shows only one extra level (the sidebar). Features do not disappear by screen or posture.
3. **Preserve continuity when opening and closing.** After opening, closing, rotating, or entering/leaving split view, preserve the current area, navigation hierarchy, scroll position, selection, open sheets, and reading page. Do not reload lists. Settings temporarily unavailable in a narrow window (such as double pages) are only hidden temporarily; do not overwrite saved preferences.
4. **Only system-required avoidance.** Keep buttons, overlays, and draggable controls out of the fold region; scrollable content may cross it. No tabletop-specific layouts or special interfaces that switch by posture.
5. **Let the system place system controls.** Do not override default side/horizontal placement or draw custom side bars. Fine-tune only through system priorities and compression behavior.

## Page Margins

Use system **container margins** for left and right margins rather than hard-coding 16. On the outer display and inner display in landscape, the margin beside side controls is about 0, so content meets the control column; the other side stays 16–20. In split view, an app on the left has controls on the leading edge, and the two margins swap accordingly.

| Implementation | Approach |
| --- | --- |
| UIKit lists / grids | Set `contentInsetsReference = .layoutMargins` (or `.readableContent`) on `UICollectionViewCompositionalLayout` sections rather than hard-coding left/right `contentInsets`; `insetGrouped` lists follow automatically |
| UIKit custom views | Constrain subviews to `layoutMarginsGuide`, with `preservesSuperviewLayoutMargins = true` on the container; constrain scroll content to `contentLayoutGuide` and its width to `frameLayoutGuide` |
| SwiftUI | `List` and `Form` handle this automatically; do not add `.padding(.horizontal)`. Custom scrolling content uses `.contentMargins(for: .container)` from iOS 27.1; earlier systems use `containerHorizontalMargins()` to fall back to `Spacing.md` at compact width / `Spacing.lg` at regular width |
| Width calculation | Resolve each side separately with `bounds.inset(by: safeAreaInsets)`, not `width - inset * 2` |
| Unchanged | Internal spacing in protected navigation lists; spacing tokens between cards and covers |

Fallback values for custom views on older systems come from existing spacing tokens and do not affect component-internal spacing.

## Library · Remote · Settings

| Item | Rule |
| --- | --- |
| Shell | **Always create** split views for all three areas. The system collapses them at compact width into one column (one navigation stack) and expands them at regular width (sidebar + content). Preserve selection and navigation hierarchy on expansion/collapse |
| Sidebar width | Use the system default, not a fixed 320pt |
| Persistent-sidebar detection | Determine whether the sidebar is visible alongside content from the split view's expansion (`isCollapsed == false`), not the device. The sidebar column itself reports a compact size class |
| Library sidebar restoration | `libraryHome.sidebarSelection` saves Continue Reading / library / collection selection; restore content and highlight after restart. When collection entries are visible alongside content, do not repeat the 2×2 collection cards at the library root |
| No tab-bar sidebar | Do not enable `tabBarController.sidebar.preferredPlacement = .sidebar` / `.defaultTabBarPlacement(.sidebar)`: each area already has its own sidebar, so this would create two layers |
| Only system bars become vertical | Only bars managed by `UINavigationController` / `UITabBarController` (SwiftUI `.toolbar` + `NavigationStack` / `NavigationSplitView`) enter the side column. Custom `UIToolbar`, `UINavigationBar`, `UITabBar`, or floating button strips do not; all toolbar actions must use system bars |
| Which column becomes vertical | Only toolbar items in the split view's content (detail) column enter the side column. Sidebar controls (such as + beside My Libraries) stay at its top, near the content they affect |
| Toolbar items | Supply both a title and SF Symbol for every item; overflow menus retain titles. From iOS 27.1, Select / Done keep symbols and Select All / Deselect All use `.horizontalOnly`; earlier systems keep text |
| Side-column order | Top to bottom: Back / Close (custom ones use `.cancellationAction` / leading items) → primary actions (high visibility priority) → remaining original groups. Library Home [+]; library contents Select · ⋯; remote directory pin · ⋯; server details ⋯ |
| Selection mode | Bottom actions use system bottom-toolbar items; Done gets high visibility priority; from iOS 27.1, More joins system overflow. See [SelectionBar](components/SelectionBar/README.md) |
| Overflow | From iOS 27.1, merge the page's own ⋯ contents into system overflow (`additionalOverflowItems` / `ToolbarOverflowMenu`), leaving one ⋯ per screen. Use ⋯ only for overflow; other menus such as Sort use their own symbols. iOS 27.0 and earlier keep the page's own ⋯ menu |
| Priority | Items collapse from bottom to top by default. Last to collapse: Library Home [+], remote-directory pin (also showing Saved state), and Done and Mark as Read in selection mode. Use `visibilityPriority` (UIKit `item.visibilityPriority`, SwiftUI `.visibilityPriority`), setting groups before individual items |
| Counts | Symbol buttons that need counts use system badges (`item.badge = .count(n)` / `.badge(n)`), not text-plus-number buttons, which would stay in the horizontal bar |
| Compression | Library, Remote, and Settings browsing pages use the default (collapse toolbar items first, keeping the tab bar). Selection mode is task-oriented: `verticalBarCompressionBehavior = .prefersBarItems` / `.toolbarVerticalCompressionBehavior(.prefersToolbarItems)` |
| No extra spacing | Do not add custom spacing around bars or extra clearance beside the side column (see Page Margins) |
| Sheets | Add Comics uses `.toolbarVerticalBehavior(.disabled)` from iOS 27.1; form sheets keep the default. The outer-display comparison is unfinished; see [system adaptation](05-batches.md#system-adaptation) |
| Grid columns | Compute as usual from container width and existing minimum-width tokens |
| Grids crossing a vertical fold region | Connected for library and remote-directory grids, not the thumbnail overview. Rule: whenever a fold region exists (including inactive regions in the query), use even columns, half on each side. **Keep outer margins unchanged and increase spacing on both sides of the crease** so the center gap aligns with it; column widths stay equal. Opening/closing changes only the center gap, without reordering |
| Floating elements | `TaskBanner`, `LightToast`, remote-directory task cards, and the global import overlay stay within the safe area. When a vertical fold region is active, normally centered elements move into the trailing region (matching system Alert placement) without crossing the fold. From iOS 27.1, `TaskBanner` uses `ConcentricRectangle` concentric corners; `LightToast` stays a capsule |
| Sheet / Alert / menu / popover | Let the system handle them (automatically avoiding fold regions; outer-display sheets stop before the camera). Do not reposition manually |
| Background and foreground | Backgrounds (grouped surfaces, reader black) may reach screen edges; foreground text, buttons, and covers stay inside the safe area |

## Reader

| Item | Rule |
| --- | --- |
| Single Page / Double Page | Double pages are available only at regular width (existing `supportsDoublePageSpread`). The inner display follows user preference without automatic switching. The outer display or compact split-view window temporarily shows a single page **without overwriting** preference; returning to the inner display restores it. Stay on the same reading page when switching |
| Double-page position (not connected) | Design requirement: align the spread center to the crease (the division region's centerline, including inactive regions in the query), not the safe-area center, because the side status bar makes the safe area asymmetric. When flat, pages meet as currently implemented; when half-folded, each page sits and fits on its own side of the fold region |
| Single page on the inner display in landscape | Centered, crossing the crease. This is content and is allowed; tap regions stay unchanged |
| Reading viewport | Determined by the window and safe area, not `UIScreen.main`. There is currently no `.occlusion` query; the design requires avoiding the permanent camera region without changing viewport geometry as tools show/hide |
| Top bar | Stays horizontal: Back · title · [Bookmarks · Aa · ⋯]. Entirely within the safe area, avoiding the trailing status-bar / Dynamic Island column. It still uses `ReaderChromeMetrics.horizontalPadding`, without side container margins. These are custom reader controls and intentionally do not enter the system side column. Half-folded partitioning is not connected; the design requires Back + title on the leading side and the three buttons on the trailing side, truncating the title before the crease. Do not make it a vertical side bar: the reader is immersive, and the protected vertical-mode track already occupies the trailing edge |
| Display panel (Aa) | A bottom floating panel at compact width (close with ×, swipe down, or tap `Aa` again); a popover at regular width (system avoids fold regions; tap outside to close). Decide by size class, not device |
| More (⋯) | System menu with automatic avoidance |
| Page-jump overlay | Keyboard lift uses window height. Crease avoidance is not connected; the design requires staying out of fold regions: trailing side for vertical folds, lower half for horizontal folds |
| Thumbnail overview | Columns follow size class and container width; even columns across the crease are not connected |
| Cross-comic navigation capsule | No page calls `ReaderContextNavigator`; any future adoption must avoid fold regions |
| Orientation lock | The inner display ignores the app's supported orientations. Rotation (This Reading Only) in the reader rotates only content, with behavior unchanged. The outer display remains readable in landscape |
| Inner camera | The inner front camera becomes a reserved region only while active. The reader top bar only needs safe-area layout, with no separate handling |

### Protected Navigation Lists · Environment Adaptation Only

Applies to `ReaderBottomBar` (`ReaderThumbnailScrubber`, floating preview, page-number capsule) and `ReaderVerticalThumbnailRail`.

| Item | Current implementation / constraint | Unchanged |
| --- | --- | --- |
| Tier | iPad, **or** both window width and height size classes regular → iPad values; otherwise → iPhone values. iPad always keeps its tier; Duo inner display uses iPad, outer and compact split view use iPhone. iPhone Plus / Max landscape is regular width and compact height, so still uses iPhone. Keep the existing viewport width ≥ `regularReaderLayoutMinWidth` check | All values within both tiers |
| Viewport fallback | Use key-window bounds; return zero size if no window exists and let the caller fall back | Calculation method |
| Container | Uses existing viewport / safe-area constraints; half-folded constraints are not connected. The design requires staying in one usable region: bottom list on the trailing side for a vertical fold (already in the lower half for a horizontal fold); right-side track limited to the lower half for a horizontal fold (already trailing for a vertical fold) | Appearance, dimensions, animation, visibility, gestures, page jumps |

The window determines the tier, not the container narrowed by half-folding. Thumbnail sizes do not jump during opening/closing; a narrower container changes only how many thumbnails are visible.

## Engineering Requirements

- Use an SDK providing the relevant APIs and keep availability checks. See [system adaptation](05-batches.md#system-adaptation) for actual version boundaries and [development workflow](../development-workflow.md) for minimum OS and build requirements.
- Do not add `UIRequiresFullScreen`. Reserved-region queries: SwiftUI `reservedRegions(kind:)`, UIKit `UIView.reservedRegions(kind:)`; fold regions are `.division`, cameras `.occlusion`; include `.includeInactive` when determining column count.
- From iOS 18, the root tab bar keeps `mode = .tabBar` without enabling a second tab-bar sidebar.
- New layouts keep using size classes; do not add device-orientation checks such as `UIDevice.current.orientation`.
- The outer display must also work in landscape (tent posture). It is compact width × compact height, with the least space in the side column and the greatest overflow risk. Do not lock portrait. The inner display ignores declared app orientations.
- Test iPhone Duo in Xcode Device Hub: closed, inner portrait / landscape, half-folded book, tabletop, split view on left / right; light/dark mode, AX5, Reduce Transparency (the side column gains a background; content must remain clear), all four languages. Protected-component screenshots on iPhone and iPad must match the pre-change version pixel for pixel.

## Outside Adaptation Scope

A tabletop-specific reading mode, automatic posture-based single/double-page switching, pages designed only for the outer display, custom side bars, and appearance changes to the two protected navigation lists.

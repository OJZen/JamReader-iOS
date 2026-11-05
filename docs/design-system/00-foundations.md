# Visual and Copy Foundations

JamReader is a personal comic reader and manager for iPhone / iPad, with equal weight on local libraries and remote (SMB / WebDAV) reading. The interface must be **native, quiet, and content-first**: covers and comics lead, and the interface recedes. Build on system navigation, controls, fonts, and semantic colors. Use jam color sparingly to mark actions and reading progress. Jam color echoes the JamReader name: a deep purplish red, like a jar of raspberry jam. Honey gold (`favorite`) is its only warm-color companion.

This file owns visual and copy foundations. See the [README](README.md) in this directory for the directory guide, preview instructions, and document ownership.

> **Protected:** Preserve the bottom thumbnail navigation list in paged reading and the right-side thumbnail navigation list in vertical reading unchanged. No token or component change in this system may affect them. See `components/ProtectedNavigation` and [03-reader.md](03-reader.md).

## Content and Copy

- Use Simplified Chinese as the design language while ensuring English, Traditional Chinese (Taiwan), and Japanese translations do not overflow. Allow about 40% expansion in buttons and labels; book titles may always truncate.
- Use a plain, direct tone, without exclamation marks, emoji, or cutesy language. Address users with “你”, not “您”, in Chinese.
- State the result before the reason: “无法访问‘Comics’文件夹。授权已失效，书库内容和阅读进度都还在。”
- Use Arabic numerals with spaces between Chinese text and numbers: “312 本 · 24 个文件夹”, “第 78 / 186 页”. Use “ · ” as the separator.
- Write only what helps the next decision. Ordinary pages have no explanatory paragraphs; explain empty states, errors, permissions, and destructive actions. Put consequences in confirmation dialogs, not row-by-row page footnotes. Do not add gesture tutorials such as “Swipe left to…”.

### Fixed Terminology

| Concept | Use this term (zh-Hans) | Avoid (zh-Hans) |
| --- | --- | --- |
| Local collection space | 书库 | 资料库、库 |
| User-created, with files inside the app | App 内书库 | 托管书库 |
| Directly use a folder in Files | 关联文件夹 / 使用已有文件夹 | 链接、挂载 |
| Default import library | 已导入漫画 | 导入目录 |
| Save a remote comic to this device | 离线副本、保存离线副本 | 下载 (ambiguous on its own) |
| Copy a remote comic into a local library | 导入到书库 | 下载、保存 |
| Temporary files from online reading | 阅读缓存 / 临时数据 | 离线 |
| Remote-folder shortcut | 已保存文件夹 | 收藏夹、书签 |
| Recently added to a library | 最近加入 | 最近、最近阅读 |
| Add to tags or reading lists | 标签与列表 | 整理、归类 |
| Deletes files | 删除 | 移除 |
| Removes only app records or shortcuts | 移除 | 删除 |
| Rebuildable data | 清理 | 删除 |

## Visual Foundations

### Colors

- Page backgrounds: ordinary lists and cover grids use `bg`; grouped pages such as settings, forms, and server details use `bg-grouped`, with `surface` cells and `surface-2` nested blocks. These match UIKit semantic colors; implement them with system colors directly.
- Text: titles and body use `ink`; subtitles, counts, and times use `ink-2`; placeholders and disabled text use `ink-3`. `ink-2` is Apple's original value, about 3.4:1 on white in light mode, so do not use `ink-2` alone for critical information below 13pt.
- Jam color has two uses:
  - `jam` is for **fills and markers**: solid primary-button backgrounds, selection checks, reading progress bars, Imported Comics in the storage bar, and brand blocks. Text and icons on it always use `on-jam` (white). Light: #9B1E56; dark: raspberry jam #C23A76.
  - `accent` (= the AccentColor asset) is for **tappable text and icons**: toolbar buttons, links, selected text, and selected tabs. It matches `jam` in light mode and brightens to jam pink #E886B2 in dark mode to remain readable on black.
  - Because dark-mode `accent` is bright, solid buttons must not inherit AccentColor, which makes white text unreadable. Always set `.tint(.appJam)` explicitly.
- `jam-deep` (#5C1233, the jar-bottom color) is only for brand blocks: covers, app-icon backgrounds, and launch screens, not controls.
- The reader does not follow appearance changes. Its accent is fixed to `reader-accent` (bright jam pink) for reader markers such as active bookmarks; reading-preparation progress bars use `jam`.
- Switches keep system green, consistent with iOS, rather than jam color.
- Selected filter chips and light notices use an `accent-soft` background with `accent-on-soft` text.
- Status colors have only five meanings: `success` (Read, complete), `offline` (Available Offline), `warning` (Older Copy, read-only), `danger` (failure, deletion), and `favorite` (stars). The first four have `-soft` backgrounds; `favorite` has no matching background token. Status always uses an icon and text, never color alone.
- `accent` and `danger` are both in the red family (20–30° hue difference, similar lightness in dark mode). Destructive actions must include both a trash/warning icon and Delete text. Never use `accent` or `jam` for destructive actions; system menus and dialogs use system destructive red.
- `label-*` preserves the 12 original colors compatible with the YACReader database. Show only a 10pt dot, always beside the tag name.
- The reader does not follow system appearance: pure-black `reader-bg` canvas, `reader-chrome` material with `reader-ink` / `reader-ink-2` tools, and `reader-stroke` borders.

### Typography

- Use only system fonts (SF Pro / PingFang). All text uses Dynamic Type styles, not fixed font sizes. Token font sizes represent the default Large setting and are only mockup references.
- Page large titles use `largeTitle`; section titles `title2`; sheet titles `headline`; primary list rows `body`; secondary rows `subheadline` or `footnote`; titles below covers use 13pt medium over two lines, with `caption1` status.
- Page numbers, percentages, and file sizes always use monospaced digits (`.monospacedDigit()`).
- Do not use custom font files. System fonts need no bundling, so `type.fonts` is empty.

### Spacing and Layout

- Use only `space-*` spacing (2 / 4 / 8 / 12 / 16 / 20 / 24 / 32 / 48, matching `Spacing`). See [page margins](06-iphone-duo.md#page-margins) for horizontal margins and older-system fallbacks; do not hard-code them again per page. Use `space-xl` between sections.
- Cover grids: compact windows adapt using `size-grid-min-compact`, typically 3 columns at ordinary widths, with `space-sm` column gaps and `space-lg` row gaps. iPad adapts between `size-grid-min`–`size-grid-max`. List rows are at least `size-row` high.
- Tap targets are at least `size-touch` (44pt). Trailing More buttons are also 44×44.
- Decide width using container width and size class, not device model. Regular width uses a system sidebar and content area; `size-sidebar` is a static-mockup reference, not a fixed runtime sidebar width. Narrow windows naturally collapse into the iPhone layout.

### Shapes, Materials, and Shadows

- Corners: covers use `radius-cover` (6); search fields and selected sidebar rows `radius-md`; grouped lists and cards `radius-lg`; sheets and floating panels `radius-xl`; capsules `radius-full`. All use `.continuous` curves.
- Do not draw outlined cards or colored left borders. Establish hierarchy with spacing and `surface` backgrounds.
- From iOS 26, system Liquid Glass owns navigation-bar buttons, tab bars, and toolbars. iOS 17.6–18 falls back to system materials (`glass` and `glass-stroke` illustrate only this fallback; do not draw custom glass).
- Shadows: covers use `shadow-cover` (optional in dark mode); overlays use `shadow-lg`; other surfaces rely on material without shadows.

### Motion

- Animation explains state changes, not decoration. Reuse `AppAnimation`: `chromeToggle` (spring 0.35 / 0.82) for tools, `sheetPresent` for sheets, `overlayPop` for overlays, and `quickFade` (0.15s) for light transitions.
- Comic opening and closing share one hero transition: the cover flies to the page's reader position on open; on close, the current page flies back and fades into the cover en route. Only one comic image moves throughout, with the original cover hidden during flight. The reader's black background only fades, without moving. During downward/rightward dismissal, the page follows the finger and continues flying back from the release position. If the cover is offscreen or the reader has switched comics, the page shrinks and fades in place.
- With Reduce Motion enabled, hero transitions use a crossfade and list insertion/deletion has no positional animation.
- Do not animate large layout changes or frequent progress updates.

### States

- Remote-copy states use [StatusBadge](components/StatusBadge/README.md); component states and actual page adoption are documented separately. Reading cache does not show an offline badge.
- A cover's badge position holds only its most important state (see `ComicCover` for priority). Read / Unread appears only in the subtitle, without dots.
- Loading preserves context (source, cover); empty states offer one next step; errors preserve the actual reason and recovery action (`Notice`); destructive actions state what is deleted and preserved (`ConfirmDialog`).
- Long tasks reuse existing progress entries rather than adding a task center. See [TaskBanner](components/TaskBanner/README.md) for local task-banner and remote-overlay responsibilities.
- The storage bar uses `chart-*` neutrals for remote downloads, temporary data, and covers, and `jam` for Imported Comics; do not borrow status colors.

## Icons

- Use SF Symbols, outlined by default and `.fill` for selection/emphasis, following text weight and Dynamic Type.
- Icons in preview cards are hand-drawn outlined web stand-ins, **not** final assets. Use the SF Symbols below in implementation.

| Purpose | SF Symbol |
| --- | --- |
| Library tab | `books.vertical` / `.fill` |
| Remote tab | `server.rack` |
| Settings tab | `gearshape` / `.fill` |
| Add | `plus` |
| More | `ellipsis` (row trailing edge, toolbar) |
| App Managed / Linked Folder / Imported Comics | `books.vertical` / `folder.badge.link` (`folder` is available on iOS 17) / `tray` |
| Import Here / Import to Library | `square.and.arrow.down` |
| Save Offline Copy / Available Offline | `arrow.down.circle` / `arrow.down.circle.fill` |
| Older Copy | `clock.badge.exclamationmark` |
| Failure | `exclamationmark.triangle` |
| Favorite / Rating | `star` / `star.fill` |
| Read | `checkmark.circle` |
| Tags / Reading Lists | `tag` / `list.bullet` |
| Recently Added | `sparkles` |
| Saved Folders / Save Folder | `pin` / `pin.fill` (not `star`, which only means favorite comics) |
| Bookmarks | `bookmark` / `bookmark.fill` |
| Display settings | `textformat.size` |
| Thumbnail overview | `square.grid.3x3` |
| Save to Photos | `photo` |
| Delete | `trash` |

## Accessibility

- Every status has text; a Chinese VoiceOver example is “雾港侦探 第 3 卷，读到 42%，已离线”.
- Text contrast: `ink` ≥ 7:1 in all contexts; `accent` ≥ 4.5:1 on all backgrounds (light 6.9–7.7, dark 5.6–8.5); `on-jam` on `jam`: light 7.7, dark 5.1; `jam` as a graphic marker ≥ 3:1 (3.4 on dark surface).
- Keyboard focus uses a 2pt solid `focus-ring` outer ring; iPad pointer hover uses system effects.
- At Dynamic Type AX5, cover grids drop to 2 columns, list rows become multiline, and toolbar text buttons become icons with accessibility names.
- Check light/dark mode, Reduce Motion, and Increase Contrast.

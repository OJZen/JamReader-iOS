# YACReader iOS Priority Frame Recipes

更新时间：2026-04-09

## 1. 文档用途

这份文档是给高保真出图阶段使用的“直接搭建配方”。

和前面几份文档的关系：

- `yacreader-ios-ui-redesign-blueprint.md` 负责方向
- `yacreader-ios-figma-screen-spec.md` 负责搭建规则
- `yacreader-ios-priority-screen-content-spec.md` 负责内容和文案
- `yacreader-ios-priority-frame-recipes.md` 负责具体怎么摆

当前只细化 3 个最高优先页面：

1. `Library Home`
2. `Browse Home`
3. `Remote Browser`

## 2. 通用搭建规则

### 2.1 Compact Frame

- 基础画板：`393 x 852`
- 页面左右边距：`16`
- 区块垂直间距：`20`
- 大区块垂直间距：`24`
- 卡片内边距：`16`

### 2.2 Regular Frame

- 基础画板：`1024 x 1366`
- Sidebar：`320`
- Detail 内容左右边距：`24`
- Detail 模块间距：`24`
- Detail 最大内容宽度：`1180`

### 2.3 组件基础

统一用这些基础组件：

- `Nav Bar / Large`
- `Nav Bar / Inline`
- `Search Field / Drawer`
- `InsetCard / Overview`
- `InsetCard / Action`
- `List Row / Library`
- `List Row / Server`
- `List Row / Remote Directory`
- `List Row / Remote Comic`
- `Section Header / With Meta`
- `Quick Filter Chip`
- `Summary Metric Pill`
- `Inline Metadata`

## 3. Recipe 1: Library Home

### 3.1 Compact / Populated

Frame Name:

- `Compact / Library Home / Populated / V1`

Frame Structure:

```text
Screen
  NavBar
  Scroll Content
    Continue Reading Section
    Libraries Section
    Import Section
    Feedback Area
```

### 3.2 Compact / Layer Tree

```text
Library Home
  Top Nav
    Title: Library
    Trailing: Add
  Content Stack
    Section: Continue Reading
      Horizontal Scroll
        Resume Card 01
        Resume Card 02
        Resume Card 03
    Section: Libraries
      Library Row 01
      Library Row 02
      Library Row 03
    Section: Import
      Import Action Card
        Action Tile 01
        Action Tile 02
        Action Tile 03
    Optional Banner
```

### 3.3 Compact / Sizing

- Continue Reading section title to first card: `12`
- Resume card width: `236`
- Resume card height: `132`
- Resume cards gap: `12`
- Library row min height: `64`
- Import action tile min height: `56`
- Import action tile gap: `12`

### 3.4 Compact / Resume Card Recipe

Structure:

```text
Resume Card
  Cover
  Text Stack
    Title
    Subtitle
    Progress
  Resume Affordance
```

Specs:

- Card container: `InsetCard / Overview`
- Cover: `72 x 108`
- Cover radius: `10`
- Title: `Subheadline / Semibold`, 2 lines max
- Subtitle: `Caption`, 1 line
- Progress: `Caption / Semibold`
- Resume affordance: play badge in bottom trailing of cover

Sample Content:

- Title: `Batman: Year One`
- Subtitle: `Issue 3`
- Progress: `Page 14 of 42`

### 3.5 Compact / Library Row Recipe

Structure:

```text
Library Row
  ListIconBadge
  Text Stack
    Title
    Subtitle
    Metadata Line
  Chevron
```

Specs:

- Leading badge: `30 x 30`
- Row vertical padding: `8`
- Title: `Body / Semibold`
- Subtitle: `Subheadline`
- Metadata line gap: `8`

Sample Rows:

1.
- Title: `Main Library`
- Subtitle: `248 comics · 31 folders`
- Metadata: `Ready`, `Writable`, `App Managed`

2.
- Title: `Archive`
- Subtitle: `1,104 comics · 87 folders`
- Metadata: `Ready`, `Read Only`, `Linked Folder`

### 3.6 Compact / Import Card Recipe

Structure:

```text
Import Card
  Section Label
  Action Tile
  Action Tile
  Action Tile
```

Action Tile Structure:

```text
Action Tile
  Icon Badge
  Text Stack
    Title
    Supporting Text
  Chevron
```

Action Copy:

1.
- Title: `Add Library Folder`
- Supporting: `Register an existing folder as a library.`

2.
- Title: `Import Comic Files`
- Supporting: `Copy selected comic files into a library.`

3.
- Title: `Import Comic Folder`
- Supporting: `Import all supported comics from a folder.`

### 3.7 Regular / Split Recipe

Frame Name:

- `Regular / Library / Split Selected / V1`

Structure:

```text
Split Root
  Sidebar
    Inline Nav Bar
    Library List
  Detail
    Content Stack
      Library Overview Card
      Continue Reading
      Browse By
```

Sidebar:

- Row spacing follows system sidebar
- Selected row keeps standard sidebar selected background

Detail:

- Overview card top margin from nav: `24`
- Continue Reading top gap: `24`
- Browse By top gap: `24`

### 3.8 Required States

需要至少补这 3 个状态：

- `Compact / Library Home / Empty`
- `Compact / Library Home / Populated`
- `Regular / Library / Split Idle`

## 4. Recipe 2: Browse Home

### 4.1 Compact / Populated

Frame Name:

- `Compact / Browse Home / Populated / V1`

Frame Structure:

```text
Screen
  NavBar
  Scroll Content
    Remote Summary Card
    Servers Section
    Quick Access Section
```

### 4.2 Compact / Layer Tree

```text
Browse Home
  Top Nav
    Title: Browse
    Trailing: Add Server
  Content Stack
    Summary Card
    Section: Servers
      Server Row 01
      Server Row 02
      Server Row 03
    Section: Quick Access
      Shortcut Row: Saved Folders
      Shortcut Row: Offline Shelf
```

### 4.3 Compact / Summary Card Recipe

Structure:

```text
Summary Card
  Header
    Title
    Subtitle
  Metrics Row
    Metric 01
    Metric 02
    Metric 03
```

Content:

- Title: `Remote Library`
- Subtitle: `Browse servers, saved folders, and offline copies.`
- Metrics:
  - `3 Servers`
  - `12 Saved Folders`
  - `46 Offline Copies`

Specs:

- Card style: `InsetCard / Overview`
- Metrics layout: 3 equal items
- Metric title: `Caption`
- Metric value: `Title 3 / Semibold`

### 4.4 Compact / Server Row Recipe

Structure:

```text
Server Row
  Provider Badge
  Text Stack
    Name
    Summary
  Chevron
```

Sample Rows:

1.
- Badge tint: Blue
- Name: `NAS SMB`
- Summary: `192.168.1.8:445 · SMB`

2.
- Badge tint: Indigo
- Name: `Comics WebDAV`
- Summary: `reader.example.com:443 · WebDAV`

3.
- Badge tint: Blue
- Name: `Studio Archive`
- Summary: `10.0.0.12:445 · SMB`

### 4.5 Compact / Quick Access Recipe

Saved Folders Row:

- Title: `Saved Folders`
- Subtitle: `12 bookmarked`
- Badge tint: Teal
- Trailing count: `12`

Offline Shelf Row:

- Title: `Offline Shelf`
- Subtitle: `46 cached`
- Badge tint: Green
- Trailing count: `46`

### 4.6 Regular / Split Recipe

Frame Name:

- `Regular / Browse / Split Selected Server / V1`

Structure:

```text
Split Root
  Sidebar
    Inline Nav
    Section: Servers
    Section: Quick Access
  Detail
    Selected Server Detail Preview
```

Sidebar order:

1. Servers
2. Quick Access

Detail placeholder copy:

- Title: `Select a Server`
- Description: `Choose a remote server or quick access shortcut from the sidebar.`

### 4.7 Required States

至少补齐：

- `Compact / Browse Home / Empty`
- `Compact / Browse Home / Populated`
- `Regular / Browse / Split Idle`

## 5. Recipe 3: Remote Browser

### 5.1 Compact / Folder / List

Frame Name:

- `Compact / Remote Browser / Folder / List / V1`

Frame Structure:

```text
Screen
  Inline Nav
  Search Drawer
  Scroll Content
    Context Overview Card
    Folders Section
    Comic Files Section
```

### 5.2 Compact / Layer Tree

```text
Remote Browser
  Top Nav
    Title: Batman
    Trailing: Display Toggle / Sort / More
  Search
    Placeholder: Filter this folder
  Content Stack
    Context Overview Card
    Section: Folders
      Directory Row 01
      Directory Row 02
    Section: Comic Files
      Comic Row 01
      Comic Row 02
      Comic Row 03
    Footer Note
```

### 5.3 Compact / Context Overview Card Recipe

Structure:

```text
Overview Card
  Path Label Row
    Context Glyph
    Current Path
  Metrics
    Folders
    Comics
    Offline
  Metadata Line
  Description
```

Sample Content:

- Path: `/Comics/DC/Batman`
- Metrics:
  - `3 Folders`
  - `18 Comics`
  - `6 Offline`
- Metadata:
  - `NAS SMB`
  - `Saved folder`
  - `Filtering`
- Description:
  - `Showing filtered results inside this folder.`

Default unfiltered variant:

- Metadata:
  - `NAS SMB`
  - `Saved folder`
  - `2 hidden`
- Description:
  - `Browse folders and comics inside the current remote path.`

Specs:

- Context glyph: `48 x 48`
- Path line: `Subheadline / Semibold`, 2 lines max
- Metrics gap: `12`
- Metadata line gap: `8`
- Description: `Footnote / Medium`

### 5.4 Compact / Folder Section Recipe

Section Header:

- Title: `Folders`
- Meta: `2 folders`

Directory Row Structure:

```text
Directory Row
  Symbol Tile
  Text Stack
    Name
    Metadata
  Action Space
```

Sample Rows:

1.
- Name: `Year One`
- Metadata: `Folder`, `Updated Mar 21`

2.
- Name: `The Long Halloween`
- Metadata: `Folder`, `Updated Mar 08`

### 5.5 Compact / Comic Files Section Recipe

Section Header:

- Title: `Comic Files`
- Meta:
  - `18 comics`
  - `6 downloaded copies`

Comic Row Structure:

```text
Comic Row
  Cover
  Text Stack
    Title
    Metadata
  Action Space
```

Sample Rows:

1. Reading progress variant
- Title: `Batman 404`
- Metadata: `Page 14 of 28`
- Cache dot: current

2. Current cache variant
- Title: `Batman 405`
- Metadata: `Current cache`
- Cache dot: current

3. File-size variant
- Title: `Batman 406`
- Metadata: `84 MB`, `Mar 18`
- Cache dot: none

### 5.6 Compact / More Menu Recipe

Menu sections顺序：

1. Favorite
2. Navigate
3. Folder / Results

Labels:

- `Add to Favorites` 或 `Remove from Favorites`
- `Up One Level`
- `Go to Root`
- `Save Visible Comics` 或 `Save Results Offline`
- `Remove Downloaded Copies` 或 `Remove Downloaded Result Copies`
- `Import This Folder` 或 `Import Results`

### 5.7 Compact / Filtered Variant

当存在搜索词时，页面需要同时替换这些文案：

- Section title `Folders` -> `Matching Folders`
- Section title `Comic Files` -> `Matching Comics`
- More menu section label `Folder` -> `Results`
- Save action `Save Visible Comics` -> `Save Results Offline`
- Import action `Import This Folder` -> `Import Results`

### 5.8 Compact / Grid Variant

Frame Name:

- `Compact / Remote Browser / Folder / Grid / V1`

Grid规则：

- 列宽最小：`156`
- 列宽最大：`206`
- 卡片间距：`12`

Grid Card Structure:

```text
Remote Comic Grid Card
  Cover / Symbol Tile
  Text Stack
    Name
    Metadata
    Optional Progress Strip
```

要求：

- 目录和漫画共用同一栅格系统
- 目录可用 symbol tile，漫画必须优先封面
- cache 状态在封面区表达，不在文字区重复刷屏

### 5.9 Regular / Folder / Grid

Frame Name:

- `Regular / Remote Browser / Grid / V1`

Structure:

```text
Detail Screen
  Inline Nav
  Search
  Overview Card
  Grid Section: Folders
  Grid Section: Comic Files
```

Grid规则：

- 列宽最小：`200`
- 列宽最大：`280`
- Section gap：`20`

### 5.10 Required States

至少补齐：

- `Compact / Remote Browser / Folder / List`
- `Compact / Remote Browser / Folder / Grid`
- `Compact / Remote Browser / Filtered`
- `Compact / Remote Browser / Empty Folder`
- `Compact / Remote Browser / No Matches`
- `Regular / Remote Browser / Grid`

## 6. Recipe 4: Saved Folders

### 6.1 Compact / List

Frame Name:

- `Compact / Saved Folders / List / V1`

Structure:

```text
Screen
  Inline Nav
  Search Drawer
  Scroll Content
    Summary Card
    Server Section 01
    Server Section 02
```

Navigation:

- Title: `Saved Folders`
- Search prompt: `Search saved remote folders`

### 6.2 Compact / Summary Card Recipe

Structure:

```text
Summary Card
  Metrics
    Shortcuts
    Servers or Provider
  Metadata Line
  Description
```

Suggested content:

- Metrics:
  - `12 Shortcuts`
  - `3 Servers`
- Metadata:
  - `Search: Batman`
  - `12 saved locations`
- Description:
  - `Pinned folders keep your most-used remote paths close across servers.`

Focused-profile variant:

- Metrics:
  - `4 Shortcuts`
  - `SMB Provider`
- Metadata:
  - `NAS SMB`
- Description:
  - `Pinned folders from NAS SMB stay one tap away.`

### 6.3 Compact / Section Header Recipe

Structure:

```text
Server Header
  Server Name
  Metadata
```

Metadata example:

- `SMB`
- `4 saved folders`

### 6.4 Compact / Saved Folder Row Recipe

Use existing visual pattern from `RemoteSavedFolderCard`.

Structure:

```text
Saved Folder Row Card
  Star Badge
  Text Stack
    Shortcut Title
    Metadata Line 01
    Metadata Line 02
  Action Space
```

Sample row:

- Title: `Batman Weekly`
- Metadata line 1: `/Comics/DC/Batman`
- Metadata line 2: `NAS SMB`, `SMB`, `Updated Mar 21`

### 6.5 Compact / States

Required:

- `Compact / Saved Folders / Empty`
- `Compact / Saved Folders / Populated`
- `Compact / Saved Folders / Search Empty`
- `Compact / Saved Folders / Rename Shortcut Sheet`

Rename sheet:

- Title: `Rename Shortcut`
- Field label: `Display Name`
- Secondary row: `Path`
- Actions: `Cancel`, `Save`

## 7. Recipe 5: Offline Shelf

### 7.1 Compact / Grouped List

Frame Name:

- `Compact / Offline Shelf / Grouped / V1`

Structure:

```text
Screen
  Inline Nav
  Search Drawer
  Scroll Content
    Summary Card
    Server Group 01
    Server Group 02
```

Navigation:

- Title: `Offline Shelf`
- Search prompt: `Search downloaded remote comics`
- Trailing menu:
  - Filter
  - Sort

Filter labels:

- `All`
- `Offline Ready`
- `Older Copies`

Sort labels:

- `Recently Opened`
- `Title`
- `Server`

### 7.2 Compact / Summary Card Recipe

Structure:

```text
Summary Card
  Metrics
    Copies
    Ready
    Older or Servers
  Metadata
  Description
```

Default content:

- Metrics:
  - `46 Copies`
  - `31 Ready`
  - `3 Servers`
- Metadata:
  - `8.2 GB`
  - `3 servers`
  - `Sorted by Recently Opened`
- Description:
  - `Downloaded comics stay available on this device across your configured servers.`

Filtered content example:

- Metrics:
  - `46 Copies`
  - `31 Ready`
  - `15 Older`
- Metadata:
  - `Search: Batman`
  - `Older Copies`
  - `Sorted by Title`
- Description:
  - `15 offline copies match the current search.`

### 7.3 Compact / Server Group Header Recipe

Structure:

```text
Server Group Header
  Server Name
  Metadata
  Overflow Menu
```

Metadata examples:

- `12 ready`
- `2 older`

Overflow menu label:

- `Clear Downloaded Copy` or `Clear Downloaded Copies`

### 7.4 Compact / Offline Comic Row Recipe

Use `RemoteOfflineComicCard` as visual reference.

Structure:

```text
Offline Comic Row Card
  Cover
  Text Stack
    Title
    Metadata Line 01
    Metadata Line 02
  Action Space
```

Sample row variants:

1. Current copy
- Title: `Akira Vol. 1`
- Metadata: `Ready on device`, `Page 101 of 214`

2. Older copy
- Title: `Batman 404`
- Metadata: `Local copy may be older`, `NAS SMB`

3. Remote only fallback state should not appear in shelf primary list; if needed, treat as explanatory state in detail copy only.

### 7.5 Compact / Item Actions

Per-item menu labels:

- `Browse Source Folder`
- `Refresh Downloaded Copy`
- `Delete Downloaded Copy`

Swipe actions:

- `Refresh`
- `Delete`

### 7.6 Compact / States

Required:

- `Compact / Offline Shelf / Empty`
- `Compact / Offline Shelf / Grouped`
- `Compact / Offline Shelf / Search Empty`
- `Compact / Offline Shelf / Filter Older Copies`
- `Compact / Offline Shelf / Delete Confirmation`
- `Compact / Offline Shelf / Clear Server Copies Confirmation`

### 7.7 Regular / Grouped

Frame Name:

- `Regular / Offline Shelf / Grouped / V1`

Notes:

- Keep grouped-by-server structure
- Allow longer section headers with metadata and menu
- Preserve list-first behavior; this page does not need a grid-first redesign

## 8. Recipe 6: Reader

### 8.1 Compact / Chrome Hidden

Frame Name:

- `Compact / Reader / Chrome Hidden / V1`

Structure:

```text
Reader Screen
  Content Layer
  Optional Top Status Badge
```

Rules:

- No visible top bar
- No visible bottom bar
- Content occupies the screen edge to edge
- Only transient notices may float at top

### 8.2 Compact / Chrome Visible

Frame Name:

- `Compact / Reader / Chrome Visible / V1`

Structure:

```text
Reader Screen
  Top Gradient
    Top Bar
  Content Layer
  Status Badge Stack
  Bottom Gradient
    Bottom Dock
      Scrubber
      Page Indicator Chip
```

Top bar:

- Leading: `Back`
- Center: current title
- Trailing:
  - `Browse Pages` shortcut on Regular only
  - `Menu`

Bottom area:

- Scrubber is the primary navigation element
- Page chip format: `12 / 180 · 7%`

### 8.3 Reader / Status Badge Stack

Use `ReaderStatusBadge`.

Visible variants:

1. `Background download in progress`
2. `Refreshing Remote Copy`
3. `Opened the downloaded copy saved on this device.`
4. `Opened an older downloaded copy saved on this device.`

Placement:

- Top center area
- Stacked with `8` vertical gap
- Never wider than readable content width

### 8.4 Reader / Page Jump Overlay

Frame Name:

- `Compact / Reader / Page Jump Overlay / V1`

Structure:

```text
Dim Overlay
  Material Card
    Current Page Label
    Close Button
    Page Field
    Go Button
```

Content:

- Top label: `Page 12 of 180`
- Field placeholder: `Go to page…`
- Primary action: `Go`

Specs:

- Card max width: `320`
- Card corner radius: `20`
- Input height: `48`
- Field and button gap: `12`

### 8.5 Reader / Thumbnail Browser Sheet

Frame Name:

- `Compact / Reader / Pages Sheet / V1`

Structure:

```text
Sheet
  Nav Bar
    Title: Pages
    Actions: Done / Current
  Scroll Content
    Overview Card
    Thumbnail Grid
```

Overview card content:

- Title: `Browse Pages`
- Supporting: `Jump quickly, compare nearby pages, or return to where you left off.`
- Stats:
  - `Current`
  - `Total`
- Page field:
  - label `Open page`
  - buttons `Open` and `Current`

Grid rules:

- Compact thumbnail: `118 x 166`
- Regular thumbnail: `144 x 204`

### 8.6 Reader / Controls Sheet

Frame Name:

- `Compact / Reader / Controls Sheet / V1`

Section order must follow current implementation:

1. `File Info`
2. `Navigate`
3. `Reading Status`
4. `Library`
5. `Display`
6. `Rotation`
7. `Bookmarks`

Key rows to show in high fidelity:

- `Browse Thumbnails`
- `Open Selected Page`
- `Add Favorite` / `Remove Favorite`
- `Mark Read` / `Mark Unread`
- `Bookmark Current Page`
- `Quick Edit Metadata`
- `Edit Metadata`
- `Tags and Reading Lists`
- `Rotate Left`
- `Rotate Right`
- `Reset Rotation`

### 8.7 Regular / Double Page

Frame Name:

- `Regular / Reader / Double Page / V1`

Rules:

- Keep same chrome language as compact
- Show double-page spread content
- Enable top trailing `Browse Pages` shortcut
- Bottom scrubber scales up according to regular metrics

Required states:

- `Compact / Reader / Chrome Hidden`
- `Compact / Reader / Chrome Visible`
- `Compact / Reader / Page Jump Overlay`
- `Compact / Reader / Pages Sheet`
- `Compact / Reader / Controls Sheet`
- `Regular / Reader / Double Page`

## 9. Recipe 7: Remote Opening / Loading

### 9.1 Compact / Loading

Frame Name:

- `Compact / Remote Opening / Loading / V1`

Structure:

```text
Dark Gradient Background
  Radial Glow
  Loading Card
```

Loading card content:

- Progress indicator
- Percentage text
- Speed text
- Loading message
- Secondary action button
- Primary action button

Default examples:

- Loading message: `Downloading…`
- Secondary action:
  - `Cancel` or `Cancel Download`
- Primary action:
  - `Back`

### 9.2 Compact / Error

Frame Name:

- `Compact / Remote Opening / Error / V1`

Loading card content:

- Symbol: `wifi.exclamationmark`
- Title: `Remote Comic Unavailable`
- Error message body
- Buttons:
  - `Back`
  - `Retry`

Card specs:

- Max width: `360`
- Corner radius: `28`
- White translucent fill on dark background

## 10. Recipe 8: Settings Home

### 10.1 Compact / Overview

Frame Name:

- `Compact / Settings Home / Overview / V1`

Structure:

```text
Screen
  Large Nav
  Scroll Content
    Optional Summary Card
    Reading Section
    Remote Section
    Storage Section
    About Section
```

Note:

- Current implementation works without a summary card
- Recommended design pass may add a lightweight Overview Card above the sections

Reading section rows:

- `Comics`
- `Manga`
- `Webcomics`

Remote section rows:

- `Manage Cache`
- `Cache Policy`

Storage section rows:

- `Remote Downloads`
- `Cover Thumbnails`
- `Imported Comics`

About section rows:

- `About`
- `Imported Comics Library`

### 10.2 Regular / Split

Frame Name:

- `Regular / Settings / Split / V1`

Structure:

```text
Split Root
  Sidebar
    Overview
    Reading
    Remote
    Storage
    About
  Detail
    Selected Pane Content
```

Sidebar row style:

- Use `SettingsPaneRow`
- Keep icon badge + title + detail summary

## 11. Recipe 9: Remote Cache Settings

### 11.1 Compact / Remote Cache

Frame Name:

- `Compact / Remote Cache / Overview / V1`

Structure:

```text
Screen
  Inline Nav
  Form Content
    Summary Card
    Downloaded Copies Section
    Cover Thumbnails Section
    Imported Comics Library Section
```

Navigation:

- Title: `Remote Cache`

### 11.2 Summary Card Recipe

Structure:

```text
Summary Card
  Glyph + Title + Subtitle
  Metric Grid
  Metadata
  Description
```

Fixed title:

- `Local Remote Storage`

Subtitle:

- `Manage downloaded remote comics and generated covers kept on this device.`

Metrics:

- `Servers`
- `Downloads`
- `Covers`
- `Imported Size`

### 11.3 Downloaded Copies Section

Rows:

- `Retention`
- Segmented `Cache Preset`
- `Current Limit`
- `On This Device`
- Optional destructive row:
  - `Clear Downloaded Copies`

Footer:

- `Clearing downloaded copies also removes remote browsing history and remembered server folder positions.`

### 11.4 Cover Thumbnails Section

Rows:

- `On This Device`
- Optional destructive row:
  - `Clear Thumbnail Cache`

Footer:

- `Thumbnail cache only affects generated remote covers. Downloaded copies and reading progress stay intact.`

### 11.5 Imported Comics Library Section

Rows:

- `On This Device`
- Optional destructive row:
  - `Clear Imported Comics`

Footer:

- `Imported comics are part of your local library. Clearing remote downloads or thumbnails will not remove them.`

### 11.6 Required States

- `Compact / Remote Cache / Empty`
- `Compact / Remote Cache / Populated`
- `Compact / Remote Cache / Clear Downloads Confirmation`
- `Compact / Remote Cache / Clear Thumbnails Confirmation`
- `Compact / Remote Cache / Clear Imported Comics Confirmation`

## 12. Recipe 10: Remote Server Detail

### 12.1 Compact / Detail

Frame Name:

- `Compact / Server Detail / Overview / V1`

Structure:

```text
Screen
  Inline Nav
  List Content
    Summary Card
    Quick Access Section
    Recent Comics Section
```

Navigation:

- Title: profile display title
- Trailing menu: `Server Actions`

### 12.2 Summary Card Recipe

Structure:

```text
Summary Card
  Glyph + Title + Provider
  Metrics
    Saved
    Offline
    Recent
  Metadata
```

Sample content:

- Title: `NAS SMB`
- Provider: `SMB`
- Metrics:
  - `12 Saved`
  - `46 Offline`
  - `8 Recent`
- Metadata:
  - `192.168.1.8:445`
  - `/Comics`
  - `reader`

### 12.3 Quick Access Section

Rows:

- `Browse Remote Library` or `Continue Browsing`
- `Saved Folders`
- `Offline Shelf`

Subtitle examples:

- `/`
- `Open shortcuts for this server.`
- `Open comics kept on this device.`

### 12.4 Recent Comics Section

If empty:

- Title: `No Browsing History`
- Description: `Open a comic from this remote server and it will appear here.`

If populated:

- Reuse `RemoteOfflineComicCard`
- Support trailing action menu for `Delete History Entry`

### 12.5 Server Actions Menu

Labels:

- `Edit Server`
- `Open Saved Folders`
- `Open Offline Shelf`
- `Clear Browsing History`
- `Clear Download Cache`
- `Delete Server`

## 13. Recipe 11: Remote Server Editor

### 13.1 Compact / New Server

Frame Name:

- `Compact / Server Editor / New / V1`

Structure:

```text
Sheet
  Inline Nav
  Form
    Overview Card
    Provider Section
    Connection Section
    Location Section
    Access Section
```

Navigation titles:

- `New SMB Server`
- `New WebDAV Server`
- `Edit SMB Server`
- `Edit WebDAV Server`

Actions:

- Leading: `Cancel`
- Trailing: `Add` or `Save`

### 13.2 Overview Card Recipe

Structure:

```text
Overview Card
  Glyph + Title + Subtitle
  Metrics
    Protocol
    Port
    Access
  Metadata
  Info Label
```

Subtitle variants:

- `New remote connection`
- `Update remote connection`

Metadata examples:

- `nas.local`
- `/Comics/Weekly`
- `Guest access`
- `Password in Keychain`

Info label example:

- `Browsing starts at /Comics/Weekly.`

### 13.3 Form Sections

Provider:

- Segmented `Provider`

Connection:

- `Display Name`
- `Host`
- `Port`

Location:

- `Share` or `Server Path`
- `Base Directory`

Access:

- Segmented `Authentication`
- `Username`
- `Password`
- `Saved Password`

### 13.4 Presentation

- Compact: `.medium` to `.large` sheet feel
- Regular: page-sized form sheet

## 14. 交付建议

如果要开始真正出完整高保真图，建议按下面顺序建 frame：

1. `Compact / Library Home / Populated`
2. `Compact / Browse Home / Populated`
3. `Compact / Remote Browser / Folder / List`
4. `Compact / Remote Browser / Filtered`
5. `Compact / Saved Folders / List`
6. `Compact / Offline Shelf / Grouped`
7. `Compact / Reader / Chrome Visible`
8. `Compact / Remote Opening / Loading`
9. `Compact / Settings Home / Overview`
10. `Compact / Remote Cache / Overview`
11. `Compact / Server Detail / Overview`
12. `Compact / Server Editor / New`
13. `Regular / Library / Split Selected`
14. `Regular / Browse / Split Selected Server`
15. `Regular / Remote Browser / Grid`
16. `Regular / Reader / Double Page`
17. `Regular / Settings / Split`

## 15. 与代码对齐的关键点

这些地方不要设计漂移：

- `Library Home` 仍以 library list 为重心
- `Browse Home` 仍以 server list 为重心，不做 dashboard 化
- `Saved Folders` 与 `Offline Shelf` 都是列表优先，不需要强行卡片瀑布流
- `Remote Browser` 真实 section 名是 `Folders` / `Comic Files`
- 搜索提示分别是 `Filter this folder`、`Search saved remote folders`、`Search downloaded remote comics`
- 远程对象优先显示阅读进度，其次缓存状态，再其次文件大小
- `Reader` 的主基调始终是黑底沉浸式内容层
- `Reader Controls` 的真实 section 顺序不能乱
- `Remote Cache` 是 form-driven 管理页，不是 dashboard
- `Remote Server Editor` 是系统表单，不是营销式 onboarding

## 16. 一次性交付完成标准

到这一步，设计稿至少应当覆盖：

- App Root
- Library Home
- Library Browser Root
- Browse Home
- Remote Browser
- Saved Folders
- Offline Shelf
- Reader
- Remote Opening Loading
- Settings Home
- Remote Cache
- Remote Server Detail
- Remote Server Editor

如果这些页面都出齐，并且 compact / regular 的关键状态都补全，这一轮 UI 设计交付就可以视为完整。

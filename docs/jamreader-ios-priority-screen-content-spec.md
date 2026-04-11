# JamReader iOS Priority Screen Content Spec

更新时间：2026-04-09

## 1. 文档目的

这份文档给高保真设计阶段使用，重点解决两件事：

- 核心页面到底显示哪些具体内容
- 页面里的标题、分区名、按钮名、badge 文案、示例数据怎么写

推荐配合以下文档一起看：

- 总体方向：`docs/jamreader-ios-ui-redesign-blueprint.md`
- Figma 搭建结构：`docs/jamreader-ios-figma-screen-spec.md`
- 高保真搭建配方：`docs/jamreader-ios-priority-frame-recipes.md`
- 产品行为依据：`docs/jamreader-ios-product-engineering-spec.md`

## 2. 使用原则

这份内容稿尽量和当前代码已有词汇保持一致，不凭空创造新命名。

优先遵守：

1. 先沿用现有 UI 文案
2. 再统一层级和语气
3. 最后才考虑局部微调

整体语气：

- 简洁
- 直接
- 不营销
- 不过度解释
- 偏系统应用风格

## 3. 核心组件文案规则

### 3.1 Section Header

统一规则：

- 1 到 3 个词
- 首字母大写
- 不加句号

推荐用法：

- `Libraries`
- `Continue Reading`
- `Quick Access`
- `Folders`
- `Comics`
- `Reading`
- `Remote`
- `Storage`

### 3.2 Button / Menu Label

规则：

- 动作动词优先
- 避免抽象词
- 与系统菜单长度接近

推荐保留当前词汇：

- `Add Library Folder`
- `Import Comic Files`
- `Import Comic Folder`
- `Browse Thumbnails`
- `Open Selected Page`
- `Manage Cache`
- `Clear Downloads`
- `Clear Thumbnails`
- `Clear Imported Comics`

### 3.3 Status Badge

badge 文案控制在 1 到 2 个词。

推荐集合：

- `Ready`
- `Linked Folder`
- `App Managed`
- `Read Only`
- `Offline`
- `Current Cache`
- `Stale Cache`
- `Bookmarked`
- `Favorite`

### 3.4 Empty State

规则：

- 标题一句话
- 描述一句话
- 如果能下一步操作，就给一个主按钮

推荐格式：

- Title: `No Libraries Yet`
- Description: `Add a library folder or import comics to get started.`
- Action: `Add Library`

## 4. Priority Screen 1: Library Home

### 4.1 Screen Purpose

让用户一进来就能完成三件事：

- 回到最近阅读内容
- 看见已有 Library
- 快速发起导入

### 4.2 Navigation

- Title: `Library`
- Trailing action: `Add`
- Add menu items:
  - `Add Library Folder`
  - `Import Comic Files`
  - `Import Comic Folder`

### 4.3 Populated Layout

从上到下：

1. `Continue Reading`
2. `Libraries`
3. `Import`
4. 可选反馈条

### 4.4 Continue Reading Section

Section Title:

- `Continue Reading`

Resume Card 内容：

- Cover
- Title
- Subtitle
- Progress text
- Resume affordance

推荐示例数据：

- Title: `Batman: Year One`
- Subtitle: `Issue 3`
- Progress: `Page 14 of 42`
- Assistive label: `Resume`

### 4.5 Libraries Section

Section Title:

- `Libraries`

Library Row 结构：

- Leading: `books.vertical.fill`
- Title: Library 名称
- Subtitle: `248 comics · 31 folders`
- Metadata:
  - `Ready`
  - `Writable`
  - `App Managed`

示例 1：

- Title: `Main Library`
- Subtitle: `248 comics · 31 folders`
- Metadata: `Ready`, `Writable`, `App Managed`

示例 2：

- Title: `Archive`
- Subtitle: `1,104 comics · 87 folders`
- Metadata: `Ready`, `Read Only`, `Linked Folder`

### 4.6 Import Section

Section Title:

- `Import`

Card 内 3 个动作建议写法：

1. `Add Library Folder`
   - Supporting text: `Register an existing folder as a library.`
2. `Import Comic Files`
   - Supporting text: `Copy selected comic files into a library.`
3. `Import Comic Folder`
   - Supporting text: `Import all supported comics from a folder.`

### 4.7 Empty State

- Title: `No Libraries Yet`
- Description: `Add a library folder or import comics to get started.`
- Action: `Add Library`

### 4.8 Design-to-Code Mapping

- Shell view: `LibraryHomeView`
- Row style reference: `LibraryRowView`
- Empty state reference: `EmptyStateView`

## 5. Priority Screen 2: Library Browser Root

### 5.1 Screen Purpose

把一个 library 的“首页感”做出来，而不是直接变成文件列表。

### 5.2 Navigation

- Title: 当前 library 名称
- Search prompt: `Search entire library`
- Trailing actions:
  - Display Mode
  - Sort
  - Maintenance / More

### 5.3 Header Overview Card

建议结构：

- Leading badge: `books.vertical.fill`
- Title: library 名称
- Supporting line: 路径或访问状态摘要
- Metrics:
  - `Comics`
  - `Folders`
  - `Recent`
- Metadata line:
  - `Ready`
  - `Writable`
  - `Linked Folder` 或 `App Managed`

示例：

- Title: `Main Library`
- Supporting: `/Users/Shared/Comics`
- Metrics:
  - `248 Comics`
  - `31 Folders`
  - `12 Recent`
- Metadata: `Ready`, `Writable`, `App Managed`

### 5.4 Quick Filter

沿用当前代码：

- `All`
- `Unread`
- `Favorites`
- `Bookmarked`

图标对应：

- `square.grid.2x2`
- `book.closed`
- `star`
- `bookmark`

### 5.5 Browse By

Section Title:

- `Browse By`

入口建议：

- `Reading`
- `Favorites`
- `Recent`
- `Tags`
- `Reading Lists`

支持文案可选，不是必须。

### 5.6 Preview Sections

Section Titles:

- `Continue Reading`
- `Recently Added`
- `Favorites`

Comic Row 示例：

- Title: `Akira Vol. 2`
- Subtitle: `akira-v2.cbz`
- Progress: `Page 82 of 214`
- Optional issue badge: `#2`

### 5.7 Search Results State

顶部状态建议：

- `Matching Folders`
- `Matching Comics`

若无结果：

- Title: `No Results`
- Description: `Try a different title, file name, or series keyword.`

### 5.8 Design-to-Code Mapping

- Screen shell: `LibraryBrowserView`
- Row/card references: `LibraryComicRow`, `LibraryComicCard`, `LibraryFolderCard`
- Filter reference: `FilterChipBar`

## 6. Priority Screen 3: Browse Home

### 6.1 Screen Purpose

让用户快速理解自己的远程资产。

### 6.2 Navigation

- Title: `Browse`
- Trailing action: `Add Remote Server`

### 6.3 Summary Card

建议标题：

- `Remote Library`

Metrics：

- `Servers`
- `Saved Folders`
- `Offline Copies`

示例：

- `3 Servers`
- `12 Saved Folders`
- `46 Offline Copies`

### 6.4 Servers Section

Section Title:

- `Servers`

Server Row 结构：

- Badge
- Server Name
- Endpoint summary
- Provider label

示例 1：

- Name: `NAS SMB`
- Summary: `192.168.1.8:445 · SMB`

示例 2：

- Name: `Comics WebDAV`
- Summary: `reader.example.com:443 · WebDAV`

### 6.5 Quick Access Section

Section Title:

- `Quick Access`

Rows:

1. `Saved Folders`
   - Subtitle: `12 bookmarked`
2. `Offline Shelf`
   - Subtitle: `46 cached`

### 6.6 Empty State

- Title: `No Servers`
- Description: `Add a remote server to browse your comic library over the network.`
- Action: `Add Server`

### 6.7 Design-to-Code Mapping

- Screen shell: `BrowseHomeView`
- Row references: `BrowseHomeServerRow`, `BrowseHomeQuickAccessRow`

## 7. Priority Screen 4: Remote Browser

### 7.1 Screen Purpose

这是 Browse 系统的主战场，重点是“浏览、保存离线、导入本地、直接阅读”。

### 7.2 Navigation

- Search prompt: `Filter this folder`
- Trailing actions:
  - `List` / `Grid`
  - `Sort`
  - `More`

Sort labels建议：

- `Name`
- `Recently Updated`
- `Largest First`

### 7.3 Context Overview Card

建议字段：

- Title: 当前目录名
- Supporting line 1: 完整路径
- Supporting line 2: 所属 server
- Metrics:
  - `Folders`
  - `Comics`
  - `Offline`
- State badges:
  - `Saved`
  - `Filtered`
  - `2 Hidden Unsupported`

示例：

- Title: `Batman`
- Path: `/Comics/DC/Batman`
- Server: `NAS SMB`
- Metrics:
  - `3 Folders`
  - `18 Comics`
  - `6 Offline`
- Badges:
  - `Saved`
  - `Filtered`

### 7.4 Folder Row

结构：

- Leading icon: `folder.fill`
- Title: 文件夹名
- Subtitle: 路径或更新时间
- Trailing: chevron

示例：

- Title: `Year One`
- Subtitle: `Updated Mar 21`

### 7.5 Remote Comic Row

信息优先级：

1. Cover
2. Title
3. File name or size
4. Reading progress or cache status

示例 A：有进度

- Title: `Batman 404`
- Subtitle: `batman_404.cbz`
- Progress: `Page 14 of 28`
- Status: `Current Cache`

示例 B：无进度

- Title: `Batman 405`
- Subtitle: `84 MB`
- Status: `Remote Only`

### 7.6 More Menu

保留这些动作为主：

- `Favorite Folder`
- `Remove Favorite`
- `Up One Level`
- `Go to Root`
- `Save Visible Comics`
- `Remove Downloaded Copies`
- `Import Current Folder`

### 7.7 Empty Folder State

- Title: `Nothing Here`
- Description: `This folder does not contain supported comics or subfolders.`

### 7.8 Design-to-Code Mapping

- Screen shell: `RemoteServerBrowserView`
- Card references: remote browse card components in `RemoteBrowseCardComponents.swift`

## 8. Priority Screen 5: Offline Shelf

### 8.1 Screen Purpose

突出“这是一组可以离线读的资产”，不是下载日志。

### 8.2 Navigation

- Title: `Offline Shelf`
- Search field: placeholder 可延用系统 search
- Trailing actions:
  - Sort
  - More

Filter labels：

- `All`
- `Offline Ready`
- `Older Copies`

Sort labels：

- `Recently Opened`
- `Title`
- `Server`

### 8.3 Group Header

每个 server group 结构：

- Server name
- Copy count
- Secondary action: `Clear All`

示例：

- `NAS SMB`
- `14 copies`
- `Clear All`

### 8.4 Offline Comic Row

结构：

- Cover
- Title
- Server / path 摘要
- Availability label
- Optional progress

Availability 文案集合：

- `Ready on device`
- `Local copy may be older`
- `Remote only`

示例：

- Title: `Akira Vol. 1`
- Subtitle: `NAS SMB`
- Availability: `Ready on device`
- Progress: `Page 101 of 214`

### 8.5 Empty State

- Title: `No Offline Comics Yet`
- Description: `Save remote comics to read them without a network connection.`

### 8.6 Design-to-Code Mapping

- Screen shell: `RemoteOfflineShelfView`
- Card reference: `RemoteOfflineComicCard`

## 9. Priority Screen 6: Reader

### 9.1 Screen Purpose

内容是主角，所有 UI 都必须退后。

### 9.2 Chrome Hidden

状态说明：

- 不显示导航信息
- 只保留内容层
- 状态提示按需浮出

### 9.3 Chrome Visible

Top bar:

- `Back`
- 当前标题
- `Browse Thumbnails` 入口，仅 Regular
- `Menu`

Bottom area:

- Scrubber
- Page chip

Page chip 文案格式：

- `12 / 180 · 7%`

### 9.4 Reader Controls Sheet

Section titles 沿用当前实现：

- `File Info`
- `Navigate`
- `Reading Status`
- `Library`
- `Display`
- `Rotation`
- `Bookmarks`

关键条目建议沿用：

- `Browse Thumbnails`
- `Open Selected Page`
- `Quick Edit Metadata`
- `Edit Metadata`
- `Tags and Reading Lists`

### 9.5 Page Jump Overlay

标题建议：

- `Go to Page`

Supporting text：

- `Page 12 of 180`

Primary action：

- `Go`

Secondary action：

- `Cancel`

### 9.6 Remote Reader Status Messages

建议保留并统一语气：

- `Opened the downloaded copy saved on this device.`
- `Opened an older downloaded copy saved on this device.`
- `Background download in progress`
- `Refreshing Remote Copy`

### 9.7 Remote Opening Loading Screen

主信息：

- Title: 当前远程文件名
- Progress percent
- Speed

Actions:

- `Back`
- `Retry`
- `Cancel Download`

### 9.8 Design-to-Code Mapping

- Local shell: `ComicReaderView`
- Remote shell: `RemoteComicReaderView`
- Chrome reference: `ReaderChromeOverlay`
- Controls reference: `ReaderControlsSupport`

## 10. Priority Screen 7: Settings Home

### 10.1 Screen Purpose

把高频阅读偏好和低频缓存管理分开表达。

### 10.2 Navigation

- Title: `Settings`

### 10.3 Summary Card

建议标题：

- `Overview`

建议摘要项：

- `Reading Defaults`
- `Cache Policy`
- `Imported Library`

示例值：

- `Left to Right · Fit Page`
- `Balanced`
- `12.4 GB`

### 10.4 Reading Section

Rows:

- `Comics`
- `Manga`
- `Webcomics`

示例摘要：

- `Left to Right · Fit Page · Cover single`
- `Right to Left · Fit Height · Cover spread`
- `Vertical Scroll · Fit Width · Cover single`

### 10.5 Remote Section

Rows:

- `Manage Cache`
- `Cache Policy`

示例值：

- `Balanced`

### 10.6 Storage Section

Rows:

- `Downloaded Copies`
- `Thumbnail Cache`
- `Imported Comics`

Destructive actions:

- `Clear Remote Downloads`
- `Clear Cover Thumbnails`
- `Clear Imported Comics`

### 10.7 About Section

Rows:

- `About`
- `Imported Comics Library`

### 10.8 Design-to-Code Mapping

- Screen shell: `SettingsHomeView`
- Row reference: `SettingsPaneRow`

## 11. 建议的高保真交付顺序

如果要继续推进到高保真稿，推荐顺序：

1. Library Home
2. Library Browser Root
3. Browse Home
4. Remote Browser
5. Offline Shelf
6. Reader
7. Settings Home

这样最先能统一 app 的主视觉秩序。

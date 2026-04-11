# JamReader iOS Figma Screen Spec

更新时间：2026-04-01

## 1. 这份文档解决什么问题

如果说 `jamreader-ios-ui-redesign-blueprint.md` 负责回答“应该设计成什么气质”，那这份文档负责回答“在 Figma 里具体要画哪些页面、用哪些尺寸、组件怎么搭”。

推荐把两份文档配合使用：

- 总方向与页面原则：`docs/jamreader-ios-ui-redesign-blueprint.md`
- 具体搭建与交付：`docs/jamreader-ios-figma-screen-spec.md`
- 核心页面文案与示例内容：`docs/jamreader-ios-priority-screen-content-spec.md`

## 2. 参考画板

为了让设计和实现都稳定，建议先固定 2 套参考画板，不追求覆盖所有设备型号。

### 2.1 Compact 参考画板

- Frame Name: `Compact / Base`
- Size: `393 x 852`
- 用途：iPhone 主参考尺寸

内容区规则：

- 页面左右内容边距：`16`
- 模块间距：`20`
- 大模块间距：`24`
- 卡片内部 padding：`16`

### 2.2 Regular 参考画板

- Frame Name: `Regular / Base`
- Size: `1024 x 1366`
- 用途：iPad 主参考尺寸

分栏建议：

- Sidebar 宽度：`320`
- Detail 起始内容宽度：`640 - 760`
- Detail 内容居中最大宽度：`1180` 以内

内容区规则：

- Sidebar 内边距遵循系统 sidebar
- Detail 页左右内容边距：`24`
- 模块间距：`24`
- 大模块间距：`32`

## 3. 基础 Token

### 3.1 间距

| 名称 | 值 |
| --- | --- |
| `space-2` | 2 |
| `space-4` | 4 |
| `space-8` | 8 |
| `space-12` | 12 |
| `space-16` | 16 |
| `space-20` | 20 |
| `space-24` | 24 |
| `space-32` | 32 |
| `space-48` | 48 |

### 3.2 圆角

| 名称 | 值 |
| --- | --- |
| `radius-6` | 6 |
| `radius-10` | 10 |
| `radius-14` | 14 |
| `radius-18` | 18 |
| `radius-20` | 20 |
| `radius-22` | 22 |

推荐映射：

- Filter chip: `10`
- Status badge: `12 capsule`
- Row card: `18`
- Overview card: `22`
- Sheet: `20 - 24`

### 3.3 字体

只使用 SF Pro / iOS 系统字体风格，不引入品牌字体。

| 层级 | Figma 样式建议 |
| --- | --- |
| Large Title | `Large Title / Semibold` |
| Title 2 | `Title 2 / Bold` |
| Title 3 | `Title 3 / Semibold` |
| Headline | `Headline / Semibold` |
| Body | `Body / Regular` |
| Body Strong | `Body / Semibold` |
| Subheadline | `Subheadline / Regular` |
| Footnote | `Footnote / Regular` |
| Caption | `Caption 1 / Regular` |
| Caption Strong | `Caption 1 / Semibold` |
| Caption 2 | `Caption 2 / Semibold` |

### 3.4 颜色角色

| 角色 | 建议 |
| --- | --- |
| `bg/app` | `systemGroupedBackground` |
| `bg/surface-primary` | `systemBackground` |
| `bg/surface-secondary` | `secondarySystemBackground` |
| `text/primary` | `label` |
| `text/secondary` | `secondaryLabel` |
| `text/tertiary` | `tertiaryLabel` |
| `accent/primary` | Blue |
| `status/success` | Green |
| `status/warning` | Orange |
| `status/danger` | Red |
| `status/remote` | Teal / Indigo |
| `status/favorite` | Yellow |

## 4. 组件尺寸规范

这一节尽量和现有实现对齐，方便后面落 SwiftUI。

### 4.1 常用结构尺寸

| 组件 | 规格 |
| --- | --- |
| 标准列表行最小高度 | `64` |
| Library / Browse icon badge | `30 x 30` |
| Settings icon badge | `28 x 28` |
| Inset list row card radius | `18` |
| Inset overview card radius | `22` |
| Status badge padding | `10 x 5` |
| Filter chip padding | `12 x 8` |
| Toast padding | `16 x 12` |

### 4.2 封面尺寸

| 场景 | 规格 |
| --- | --- |
| 列表行漫画封面 | `44 x 62` |
| 列表行标准缩略图 | `48 x 48` |
| 文件夹卡封面 | `96 x 120` |
| 漫画网格卡封面 | `120 x 168` |

### 4.3 Reader 组件尺寸

| 组件 | Compact | Regular |
| --- | --- | --- |
| 顶部/底部 chrome 按钮热区 | `44 x 44` | `44 x 44` |
| Scrubber thumbnail | `40 x 58` | `54 x 78` |
| Scrubber item frame | `46 x 76` | `62 x 104` |
| Scrubber frame height | `100` | `132` |
| 浮动预览卡圆角 | `18` | `18` |

## 5. Figma 页面组织

推荐建立 5 个页面。

### 5.1 `00 Foundation`

放基础样式：

- Color Roles
- Typography
- Spacing
- Radius
- Shadow
- Materials

### 5.2 `01 Components`

放可复用组件：

- InsetCard
- OverviewCard
- ListIconBadge
- SettingsIcon
- StatusBadge
- FilterChip
- InlineMetadataLine
- SummaryMetricPill
- LibraryRow
- ServerRow
- ComicRow
- ComicCard
- FolderCard
- Toast
- Banner
- ReaderChromeButton

### 5.3 `02 Compact Flows`

放 iPhone 版页面。

### 5.4 `03 Regular Flows`

放 iPad 版页面和分栏态。

### 5.5 `04 Prototype`

只放关键跳转链路：

- Library Home -> Library Browser -> Reader
- Browse Home -> Remote Browser -> Remote Reader
- Settings Home -> Remote Cache Settings

## 6. 首轮必须画的页面清单

### 6.1 Compact

优先级 `P0`：

1. `Compact / Library Home / Empty`
2. `Compact / Library Home / Populated`
3. `Compact / Library Browser / Root`
4. `Compact / Library Browser / Folder`
5. `Compact / Library Browser / Search Results`
6. `Compact / Browse Home / Empty`
7. `Compact / Browse Home / Populated`
8. `Compact / Remote Browser / Folder`
9. `Compact / Offline Shelf`
10. `Compact / Reader / Chrome Hidden`
11. `Compact / Reader / Chrome Visible`
12. `Compact / Reader / Page Jump Overlay`
13. `Compact / Settings Home`

第二优先级 `P1`：

1. `Compact / Saved Folders`
2. `Compact / Server Detail`
3. `Compact / Server Editor`
4. `Compact / Remote Browser / Filtered`
5. `Compact / Reader Controls Sheet`
6. `Compact / Remote Opening / Loading`
7. `Compact / Remote Cache Settings`
8. `Compact / Library Browser / Selection Mode`

### 6.2 Regular

优先级 `P0`：

1. `Regular / Library / Split Idle`
2. `Regular / Library / Split Selected`
3. `Regular / Library Browser / Grid`
4. `Regular / Browse / Split Idle`
5. `Regular / Browse / Split Selected Server`
6. `Regular / Remote Browser / Grid`
7. `Regular / Settings / Split`
8. `Regular / Reader / Double Page`

第二优先级 `P1`：

1. `Regular / Saved Folders / Split`
2. `Regular / Offline Shelf / Grouped`
3. `Regular / Reader Controls Sheet`
4. `Regular / Remote Opening / Loading`

## 7. 关键页面线框

这一节的目标不是做视觉定稿，而是锁定信息骨架。

### 7.1 Compact / Library Home / Populated

```text
[Nav Bar] Library                              [+]

[Continue Reading Carousel]
  [Resume Card] [Resume Card] [Resume Card]

[Section Header] Libraries
  [Library Row]
  [Library Row]
  [Library Row]

[Import Entry Card]
  [Add Library Folder]
  [Import Comic Files]
  [Import Comic Folder]

[Optional Banner / Recent Maintenance Status]
```

视觉提示：

- Continue Reading 卡片高度不要太高，避免压住 Libraries
- Libraries 仍然是页面中心
- Import Card 是辅助入口，不抢主标题

### 7.2 Compact / Library Browser / Root

```text
[Nav Bar] Library Name                    [Sort][More]
[Search]
[Quick Filter Chips]

[Overview Card]
  [Library Badge] Title              [Maintenance]
  [Path / Compatibility]
  [Metric] Comics  [Metric] Folders  [Metric] Recent
  [Metadata Line]

[Browse By]
  [Reading] [Favorites] [Recent] [Tags] [Reading Lists]

[Preview Section] Continue Reading
  [Comic Card] [Comic Card] [Comic Card]

[Preview Section] Recently Added
  [Comic Row]
  [Comic Row]

[Preview Section] Favorites
  [Comic Row]
  [Comic Row]
```

视觉提示：

- Root 页不是文件浏览器感，而是首页感
- Browse By 更像功能入口条，不像设置按钮列表

### 7.3 Compact / Library Browser / Folder

```text
[Nav Bar] Folder Name               [Display][Sort][More]
[Search]
[Quick Filter Chips]

[Current Folder Overview Card]
  [Folder Title]
  [Path]
  [Metadata]

[Context Chips]
  [Up One Level] [Go to Root]

[Section Header] Folders
  [Folder Row]
  [Folder Row]

[Section Header] Comics
  [Comic Row]
  [Comic Row]
  [Comic Row]
```

视觉提示：

- Up / Root 仅做轻量 chip
- 如果处于过滤状态，应在 Overview Card 下有细小结果状态条

### 7.4 Compact / Browse Home / Populated

```text
[Nav Bar] Browse                                [+]

[Remote Summary Card]
  [Metric] Servers
  [Metric] Saved Folders
  [Metric] Offline Copies

[Section Header] Servers
  [Server Row]
  [Server Row]
  [Server Row]

[Section Header] Quick Access
  [Saved Folders Row]
  [Offline Shelf Row]
```

视觉提示：

- Browse 首页不做复杂 dashboard
- Summary Card 只负责帮助用户建立全局认知

### 7.5 Compact / Remote Browser / Folder

```text
[Nav Bar] Server / Folder             [Display][Sort][More]
[Search: Filter this folder]

[Context Overview Card]
  [Path]
  [Server]
  [Metric] Folders [Metric] Comics [Metric] Offline
  [State Badges] Favorited / Filtered / Hidden Unsupported

[Section Header] Folders
  [Folder Row]
  [Folder Row]

[Section Header] Comics
  [Remote Comic Row]
  [Remote Comic Row]
  [Remote Comic Row]
```

视觉提示：

- 缓存状态只做一个明确表达点
- 如果有阅读进度，优先给进度，不展示体积

### 7.6 Compact / Offline Shelf

```text
[Nav Bar] Offline Shelf                      [Sort][More]
[Search]
[Filter Chips] All / Offline Ready / Older Copies

[Server Group Header]
  Server Name                     [Clear All]

  [Offline Comic Row]
  [Offline Comic Row]

[Server Group Header]
  Server Name                     [Clear All]

  [Offline Comic Row]
```

视觉提示：

- 这页应更像“我的可读资产”，不是“下载历史”
- 组头比普通 section header 稍强一点，但不要像大卡片

### 7.7 Compact / Reader / Chrome Visible

```text
[Top Gradient]
  [Back]        [Title]        [Thumbs?] [Menu]


              [Comic Content]


[Bottom Gradient]
  [Scrubber with center-focused page]
  [Page Chip: 12 / 180 · 7%]
```

视觉提示：

- chrome 要“漂浮”在内容之上
- 标题和按钮都要轻
- 页码 chip 是单独的可点触对象

### 7.8 Compact / Settings Home

```text
[Nav Bar] Settings

[Overview Summary Card]
  [Reading Summary]
  [Remote Cache Policy]
  [Imported Library Footprint]

[Section Header] Reading
  [Comics]
  [Manga]
  [Webcomics]

[Section Header] Remote
  [Manage Cache]
  [Cache Policy]

[Section Header] Storage
  [Downloaded Copies]
  [Thumbnail Cache]
  [Imported Comics]

[Section Header] About
  [About Row]
```

视觉提示：

- 仍然要像 Settings，不像管理后台
- 首页更多是摘要，不做深度操作

## 8. 组件构造说明

### 8.1 Overview Card

用途：

- Library Root 概览
- Remote Browser 上下文
- Browse Home 摘要
- Settings 首页摘要

推荐结构：

1. 顶部：icon badge + title + trailing action
2. 中部：1 行次级说明
3. 下部：2 到 3 个 summary metrics
4. 底部：metadata line / badges

不要把 4 行以上正文塞进 overview card。

### 8.2 List Row

统一结构：

1. leading icon 或封面
2. title
3. subtitle
4. metadata
5. trailing disclosure 或数量

规则：

- 主信息左对齐
- trailing 信息只留一个重点
- 行尾操作如果很多，留给 context menu / swipe

### 8.3 Comic Row

推荐高度：

- 行高视觉上控制在 `76 - 88`
- 标题最多 2 行
- 副标题最多 1 行
- metadata 最多 1 行

### 8.4 Comic Grid Card

推荐规则：

- 封面保持固定比例
- 标题 2 行封顶
- 副标题 2 行封顶
- 状态区不超过 2 行

### 8.5 Status Badge

视觉要点：

- 不要描边
- 文字 semibold
- 底色透明度轻
- 永远是附加态，不做大按钮

### 8.6 Filter Chip

状态：

- Default
- Selected
- Pressed

选中态：

- 背景 accent
- 文字反白
- 图标可保留但弱于文字

## 9. 必须准备的状态变体

每个核心页面至少补齐以下状态，不要只画 happy path。

### 9.1 Library

- Empty
- Populated
- Searching
- Search Empty
- Selection Mode
- Import Success Feedback

### 9.2 Browse

- No Servers
- Has Servers
- Has Quick Access
- Server Validation Error
- Remote Browser Filtered
- Remote Browser Empty Folder

### 9.3 Reader

- Chrome Hidden
- Chrome Visible
- Page Jump Overlay
- Controls Sheet
- Remote Status Badge Visible
- Remote Opening Loading

### 9.4 Settings

- Overview
- Cache Management
- Destructive Confirmation

## 10. Prototype 重点

Figma prototype 只做最关键的 5 条链路：

1. Library Home 打开资料库
2. Library Browser 打开漫画并进入 Reader
3. Browse Home 进入 Remote Browser
4. Remote Browser 打开远程漫画
5. Settings Home 进入 Cache Settings

原型规则：

- 不做复杂动效拼接
- 只用来验证层级、路径和关键入口是否顺手
- Reader 的 chrome 显隐可以做两帧切换，不必追求高保真动效

## 11. 与代码对齐的注意点

这几项设计不要偏离当前实现：

- 分栏逻辑必须保留
- Library / Browse / Settings 都是 grouped 或 split 语义，不是单页 dashboard
- Reader 按钮热区保持 `44 x 44`
- Reader 仍以黑底内容层为核心
- Quick Filter、StatusBadge、InsetCard 都是已经存在的语言，应延续而不是推倒重做

## 12. 建议的下一步

如果要继续往下推进，推荐顺序是：

1. 先画 `Library Home`、`Library Browser Root`、`Browse Home`
2. 再画 `Remote Browser`、`Offline Shelf`
3. 最后统一 `Reader` 和 `Settings`

这样能最快建立整套产品的视觉秩序。

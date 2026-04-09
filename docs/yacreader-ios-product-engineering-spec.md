# YACReader iOS 重写版产品/交互/实现说明

更新时间：2026-04-09

本文基于当前仓库代码结构整理，目标是为产品经理、设计师、iOS 开发、测试同学提供一份统一的功能/UI/UX/交互说明。  
整理范围覆盖 `App`、`Features`、`SharedUI`、`ReaderKernel`、`Core` 等主要模块，重点聚焦已经落在代码里的真实行为，而不是仅停留在规划稿层面。

当前本地资料库底座已经统一为 App 自管模型：

- 资料库状态数据库：`Application Support/YACReader/AppLibraryV2.sqlite`
- 封面与派生资源：`Application Support/YACReader/LibraryAssets/<libraryID>/`
- 外部目录只作为内容源，不再承载 `.yacreaderlibrary`、`library.ydb` 或桌面兼容模式语义

## 1. 产品定位

这是一个面向 iPhone / iPad 的漫画阅读应用，整体方向可以概括为：

- 基于 YACReader 原版能力做 iOS 原生重写。
- 支持本地漫画库与远程漫画源并行使用。
- 兼顾“书库管理”和“直接阅读”两类核心场景。
- 设计风格明确贴近 iOS 原生系统体验，强调克制、清晰、可预期、内容优先。
- 在原有能力基础上加入大量移动端增强，包括远程服务器、离线缓存、阅读器手势、批量管理、标签/阅读列表、导入策略、缓存策略等。

从代码实际呈现看，这不是一个“单纯打开压缩包阅读”的工具，而是一个同时具备以下三层能力的产品：

- 个人书库管理器：本地书库、导入、元数据、标签、阅读列表、批量操作。
- 网络漫画浏览器：SMB / WebDAV 远程服务器浏览、收藏远程文件夹、离线书架、远程缓存。
- 专业阅读器：支持图片序列 / PDF / Webtoon 风格纵向阅读，多种布局和交互方式，支持书签、评分、收藏、阅读进度。

## 2. 总体信息架构

### 2.1 顶层导航

App 顶层采用 3 Tab 结构：

| Tab | SF Symbol | 作用 |
| --- | --- | --- |
| Library | `books.vertical.fill` | 本地书库入口，管理 Library、导入、浏览、搜索、阅读、元数据与组织结构。 |
| Browse | `globe.asia.australia.fill` | 远程浏览入口，管理服务器、浏览远程目录、保存文件夹、离线书架、远程阅读。 |
| Settings | `gearshape.fill` | 阅读默认配置、远程缓存策略、设备存储占用、应用信息。 |

全局特征：

- iPad / Regular 宽度下，多个一级页面会切换成 `NavigationSplitView`。
- iPhone / Compact 宽度下，以 `NavigationStack` 为主。
- App 根层支持键盘快捷键：
  - `Cmd+1` 切到 Library
  - `Cmd+2` 切到 Browse
  - `Cmd+3` 切到 Settings
- App 根层会在 TabBar 上方悬浮显示远程后台导入进度和反馈卡片，说明“远程导入”是跨页面、全局可感知的长任务。

### 2.2 核心模块关系

整体可以理解为 5 个核心系统：

1. 本地书库系统  
   Library Home -> Library Browser -> Reader -> Metadata / Organization

2. 本地导入系统  
   文件/文件夹导入 -> 选择目标 Library -> 自动索引 -> 进入浏览与阅读

3. 远程浏览系统  
   Browse Home -> Server -> Remote Browser -> Remote Reader / 保存离线 / 导入本地

4. 阅读器系统  
   本地 Reader 与远程 Reader 共用一套阅读会话和大部分 UI 外壳，但在点击路由、状态动作、持久化方式上有差异

5. 设置与存储系统  
   管理默认阅读布局、缓存保留策略、离线下载、远程封面缓存、Imported Comics Library

## 3. 设计原则与视觉语言

### 3.1 整体风格

代码中的视觉表达非常明确地指向“iOS 原生、克制、内容优先”：

- 主要使用系统语义色：`systemBackground`、`secondarySystemBackground`、`systemGroupedBackground` 等。
- 主要使用系统字体和 `preferredFont` / 动态字体风格，不走强品牌定制字体路线。
- 卡片、列表、Sheet、Toolbar、Context Menu、Swipe Actions 都遵循原生 iOS 组件语义。
- 重点通过层次、间距、轻阴影、半透明材质、渐变遮罩来建立质感，而不是重品牌视觉。
- 阅读器使用黑底内容面，顶部/底部 chrome 用黑色渐变蒙层压在内容之上，典型 iOS 媒体阅读范式。

### 3.2 设计 token 倾向

从 `DesignTokens.swift` 可以归纳出以下设计语言：

- 间距节奏偏规律化，常见 4 / 8 / 12 / 16 / 20 / 24 / 32。
- 圆角普遍较大，卡片/Sheet/浮层偏柔和连续曲线。
- 阴影很轻，主要做层级提示，不做重拟物。
- 状态色分工清晰：
  - 蓝色：主交互、导航、服务器、标签/状态默认强调
  - 绿色：成功、离线可用、缓存可读
  - 橙色：警告、旧缓存、只读/不可直接写
  - 红色：删除、危险动作
  - 青/靛：远程、缓存策略、服务器相关附加语义

### 3.3 全局 UI 组件范式

整个项目大量复用以下模式：

- Inset Card：信息摘要卡、概览卡、说明卡。
- Grouped List / Form：设置、编辑、导入、服务器编辑。
- StatusBadge：胶囊型状态标签。
- Inline Metadata：图标 + 文本的轻量信息串。
- Empty State / Error State / Loading State：各模块都有比较完整的空态和错误态。
- Context Menu + Swipe Actions + Regular 宽度下的常驻省略号菜单：同一对象在不同设备宽度下提供不同密度的操作入口。
- Search + Filter Chips + Sort Menu + Display Mode Menu：浏览型页面的标准操作骨架。

### 3.4 动效与过渡

从实现上可以看到几个重要动效原则：

- 阅读器 chrome 的显隐带动画，而不是硬切。
- 本地/远程封面进入阅读器使用 Hero 过渡，强调“从封面进入内容”的沉浸感。
- 阅读底部缩略条会根据中心位置做缩放、抬升、透明度变化，并在拖动时显示浮动大预览卡。
- 下拉关闭阅读器采用类似 Photos 的交互：内容跟随下移、整体变淡、轻微缩放。

## 4. 自适应布局策略

这是一个明显为 iPhone 与 iPad 都做过专门处理的应用。

### 4.1 iPhone / Compact

- 首页多为 `NavigationStack`。
- 工具栏动作会合并进单一 `ellipsis` 菜单。
- 书库/特殊集合很多场景只强调 List 视图。
- 阅读器双页模式不可用。
- 边缘点击区域更宽，约占左右各 24%。

### 4.2 iPad / Regular

- Library、Browse、Settings 都能进入双栏或分栏工作流。
- 常见对象列表右侧会显示常驻的省略号动作按钮。
- 浏览页会开放 Grid 视图。
- 阅读器支持 Double Page Spread。
- 阅读器顶部可直接显示“浏览缩略页”快捷按钮。
- 边缘点击区域更窄，约占左右各 18%，减少误触。

## 5. 全局状态与反馈系统

### 5.1 反馈类型

全局和局部反馈主要分为：

- Toast / Feedback Card：导入成功、缓存刷新、离线保存等。
- Banner：如 Library 扫描完成提示。
- Alert / Confirmation Dialog：错误、删除确认、清理缓存确认。
- Status Badge：对象本身的轻量状态表达。
- Reader Status Badge：阅读器顶部状态提示，如后台下载中、使用本地缓存副本打开等。

### 5.2 空态覆盖

项目空态覆盖比较完整，典型包括：

- No Libraries Yet
- No Remote Servers
- No Favorites Yet
- Nothing in Progress
- No Recent Comics
- No Tags Yet
- No Reading Lists Yet
- No offline comics yet
- 空文件夹
- 搜索无结果

这意味着产品在“无数据首次进入”和“过滤后为空”两个阶段都做了明确区分。

## 6. 本地书库系统

### 6.1 Library Home

Library 首页负责展示本地 Library 列表，并承担所有导入入口。

### 页面职责

- 展示已添加的本地 Library。
- 创建新 Library 入口。
- 导入漫画文件/文件夹入口。
- 管理单个 Library 的 rename / info / remove。
- 在 iPad 下作为分栏主列表，右侧展示选中 Library 的详情页。

### 顶部主动作

Add 菜单包含：

| 动作 | SF Symbol | 说明 |
| --- | --- | --- |
| Add Library Folder | `folder.badge.plus` | 将本地文件夹注册成一个 Library。 |
| Import Comic Files | `doc.badge.plus` | 导入选中的漫画文件。 |
| Import Comic Folder | `folder.badge.plus` | 导入整个漫画文件夹。 |

### 空态

- 图标：`books.vertical`
- 标题：No Libraries Yet
- 语义：引导用户先建立书库，再开始导入

### Library Row 信息

每个 Library 行至少表达：

- 名称
- 副标题：如“X comics · Y folders”
- 访问状态 / 可写性 / 库类型

### 单个 Library 操作

通过 Context Menu、Swipe Actions、Action Sheet 可触发：

- Rename
- Library Info
- Remove from app

其中 Remove 的语义是“从应用中移除入口”，不是直接删除源文件夹本体。

### 6.2 Library 访问模式

本项目现在只区分“内容来源”和“当前设备上的访问能力”，不再兼容桌面版库格式。

| 模式 | 产品语义 | 用户可做的事 |
| --- | --- | --- |
| Linked Folder | 外部目录注册到 App | 浏览、搜索、阅读、刷新、写本地元数据与阅读状态；若源目录可写则允许导入与物理删除 |
| Imported Comics | App 托管书库 | 浏览、搜索、阅读、刷新、导入、写本地元数据与阅读状态 |
| Read Only | 当前设备只能读取源目录 | 浏览、搜索、阅读、刷新、写本地元数据与阅读状态；禁止向源目录导入或物理删除 |

产品上的重要信息表达：

- Linked Folder 显示为 `Linked Folder`
- App 托管库显示为 `App Managed`
- Read Only 模式会提示当前源目录只读，直接导入不可用

关键产品策略：

- 外部目录只负责提供漫画内容，不承载 App 私有数据库或缓存
- 所有业务状态统一写入 App 本地数据库与资产目录
- 风险前置到 UI 提示层，而不是等到执行失败

### 6.3 导入链路

本地导入是一个独立能力，不是简单“把文件放进去”。

### 导入目标选择

系统支持导入到：

- Imported Comics（应用托管的导入书库）
- 某个具体本地 Library

导入目标选择页会表达：

- 哪些目标可选
- 哪些目标只读/不可导入
- 当前建议目标
- 导入会执行“复制 + 自动索引”

补充说明：

- 源目录只读的 Linked Folder 仍允许 Browse、搜索和阅读，但不允许直接导入到该目录。
- 远程导入会先下载到设备，再复制进本地 Library。

### 导入后结果

导入不是单次“打开”，而是进入正式书库数据流：

- 文件被复制到目标存储位置
- 数据库被索引
- 后续可参与搜索、标签、阅读列表、阅读进度、评分、ComicInfo 导入等完整能力

### 6.4 Library Browser

这是本地书库最核心的浏览页面。

### 页面职责

- 浏览根目录与任意子目录
- 搜索整个库或当前目录
- 筛选 unread / favorites / bookmarked
- 排序、切换 list / grid
- 进入阅读器
- 进行批量管理
- 查看 Continue Reading / Recently Added / Favorites 等快捷视图
- 进入 Tags / Reading Lists

### 根层内容组织

根层并不是普通文件列表，而是“总览型首页”，主要包含：

- Overview Card：当前库概览、路径、数量、库类型/可写性、扫描信息
- Continue Reading
- Browse By：
  - Reading
  - Favorites
  - Recent
  - Tags
  - Reading Lists
- Preview Sections：
  - Continue Reading 预览
  - Recently Added 预览
  - Favorites 预览

### 子目录内容组织

进入子目录后页面结构更偏“文件浏览器”：

- 当前目录概览卡
- Up / Root 快捷跳转 chips
- 文件夹列表
- 漫画列表
- 当前筛选与搜索状态提示

### 搜索

分两类：

| 搜索类型 | 文案 | 范围 |
| --- | --- | --- |
| 根层搜索 | Search entire library | 搜索整个 Library |
| 子目录过滤 | folderSearchQuery | 仅过滤当前目录可见对象 |

搜索结果页面会拆成：

- Matching folders
- Matching comics

并保留 quick filter 的联动效果。

### 快速筛选

Quick Filter 使用 chip 形式呈现：

| 筛选项 | 图标 |
| --- | --- |
| All | `square.grid.2x2` |
| Unread | `book.closed` |
| Favorites | `star` |
| Bookmarked | `bookmark` |

### 排序

本地 Library 主要支持：

- Default / Source order
- Title A-Z
- Title Z-A
- Filename
- Recently Opened
- Recently Added

### 展示模式

| 模式 | 图标 | 说明 |
| --- | --- | --- |
| List | `list.bullet` | 信息密度高，移动端主力模式 |
| Grid | `square.grid.2x2` | 更强调封面浏览，主要在 Regular 宽度可用 |

### 漫画条目视觉信息

单个漫画 Row / Card 一般会呈现：

- 封面
- 标题
- 副标题 / 文件名
- 期号 badge（如有）
- 阅读进度
- 已读状态
- 收藏状态
- 书签数量

Continue Reading 的视觉额外特点：

- 封面右下角叠加“播放”徽章
- Card 文案突出“Resume”

### 文件夹条目视觉信息

文件夹对象会表达：

- 文件夹封面占位或封面图
- 目录名
- 子文件/子文件夹数量
- 路径或概览信息
- 状态 badges

### 工具栏与维护动作

Library Browser 的非选择态工具栏包含：

- Import ComicInfo
- Import Comic Files
- Recent 时间窗口选择
- Maintenance Menu
- Display Mode Menu
- Sort Menu

Maintenance Menu 的关键动作：

- Refresh library
- Refresh current folder
- Import library ComicInfo
- Import current folder ComicInfo

Regular 宽度下这些动作相对展开；Compact 下会更集中收进 `ellipsis` 菜单。

### 6.5 漫画对象操作

单个漫画在本地书库里支持多层级操作。

### 进入阅读

- 点击条目直接进入阅读器
- 封面到阅读器使用 Hero 过渡

### 常驻动作入口

- Regular 宽度下，行右侧会保留 `ellipsis.circle` 样式动作按钮
- 所有宽度下都支持 Context Menu

### Swipe Actions

前置（Leading）常见动作：

- Mark Read / Mark Unread

后置（Trailing）常见动作：

- Info
- Edit Metadata
- Favorite / Unfavorite
- Delete

### Quick Actions Sheet

单本漫画的快速操作 Sheet 会展示：

- 标题、副标题
- 类型 badge
- 阅读状态、收藏、评分、书签数等状态 badges
- Edit Metadata
- Tags and Reading Lists
- Favorite / Unfavorite
- Mark Read / Unread
- Rating 选择
- 从当前上下文移除
- 从书库删除

### 6.6 选择模式与批量操作

Library Browser、Special Collection、Organization Detail 都支持选择模式。

### 选择模式交互

- 顶部按钮在 `Select` / `Done` 之间切换
- 支持 `Select All` / `Clear`
- 底部显示选中数量摘要
- 底部提供 `Actions`

### 批量动作

批量动作能力包括：

- Mark Read
- Mark Unread
- Favorite
- Unfavorite
- Batch Edit Metadata
- Batch ComicInfo Import
- Batch Organization
- 从当前标签/阅读列表上下文移除

### 批量元数据编辑字段

批量元数据编辑支持按字段开关应用，主要包括：

- Type
- Rating
- Series
- Volume
- Story Arc
- Publisher
- Language ISO
- Format
- Tags

### 批量 ComicInfo 导入策略

支持两种导入策略：

- Fill Missing
- Overwrite Existing

这说明 ComicInfo 不只是单本导入，也支持面向批量整理场景。

### 6.7 Special Collections

Special Collections 是书库根层的重要捷径。

| 集合 | 图标 | 产品语义 |
| --- | --- | --- |
| Reading | `book` | 已打开但未读完的漫画 |
| Favorites | `star` | 被用户收藏的漫画 |
| Recent | `clock` | 最近 N 天新增的漫画 |

每个 Special Collection 都有：

- 单独列表页
- 搜索
- Quick Filter
- Sort
- List / Grid 切换
- 选择模式
- 批量操作

Recent 集合支持“最近时间窗口”概念，不是死板的固定列表。

### 6.8 Tags 与 Reading Lists

### 产品定位

本项目将“轻标签”和“阅读队列”拆成两套模型：

| 类型 | 图标 | 语义 |
| --- | --- | --- |
| Tags | `tag` / `tag.fill` | 用于跨目录分组与轻量分类 |
| Reading Lists | `text.badge.plus` | 用于故事线、顺序阅读、队列组织 |

### Organization Root

根层支持：

- 查看 Tags 或 Reading Lists
- 搜索
- 排序
- List / Grid
- 新建
- 编辑
- 删除

### Collection Detail

单个 Tag / Reading List 明细页支持：

- 查看集合内漫画
- 搜索
- Quick Filter
- 排序
- List / Grid
- 选择模式
- 批量移出当前集合

### 单本组织编辑

从 Reader 或 Quick Actions 可打开组织页，对单本漫画：

- 加入 / 移出 Tag
- 加入 / 移出 Reading List

行内会显示是否已分配的指示状态。

### Tag 颜色系统

Tag 颜色使用固定调色盘而不是自由拾色，现有 12 种：

| 名称 | Hex |
| --- | --- |
| Red | `#FD777C` |
| Orange | `#FEBF34` |
| Yellow | `#F5E934` |
| Green | `#B6E525` |
| Cyan | `#9FFFDD` |
| Blue | `#82C7FF` |
| Violet | `#8286FF` |
| Purple | `#E39FFF` |
| Pink | `#FF9FDD` |
| White | `#E3E3E3` |
| Light | `#C8C8C8` |
| Dark | `#ABABAB` |

这套颜色更像“系统化标签色板”，适合稳定管理，不强调自由配色。

### 6.9 元数据编辑

### Quick Metadata

Quick Metadata 面向高频轻编辑，字段包括：

- Title
- Series
- Issue Number
- Volume
- Type
- Story Arc
- Publisher
- Tags

### Full Metadata

Full Metadata 是完整编辑器，包含：

- Core
  - Title
  - Series
  - Issue Number
  - Volume
  - Type
- Publishing
  - Story Arc
  - Publication Date
  - Publisher
  - Imprint
  - Format
  - Language ISO
- Credits
  - Writer
  - Penciller
  - Inker
  - Colorist
  - Letterer
  - Cover Artist
  - Editor
- Cast & Tags
  - Characters
  - Teams
  - Locations
  - Tags
- Notes
  - Synopsis
  - Notes
  - Review

此外还支持在编辑页顶部直接导入嵌入式 `ComicInfo.xml`。

## 7. 阅读器系统

阅读器是本项目最精细的交互模块。

### 7.1 支持内容类型

当前阅读器支持：

- Image Sequence：图片序列漫画
- PDF
- Unsupported：已被索引但阅读器尚未完成支持的类型

对图片序列又分两种阅读形态：

- Paged：分页阅读
- Vertical Continuous：纵向连续阅读

### 7.2 本地 Reader 与远程 Reader 的差异

### 本地 Reader

- 支持前后漫画上下文跳转
- 支持收藏、已读、评分、元数据编辑、标签/阅读列表
- 进度写回本地数据库
- 布局偏好按漫画类型分别记忆

### 远程 Reader

- 主要面向“单本远程内容阅读”
- 不提供本地 Library 级的收藏/评分/元数据编辑
- 记录远程阅读进度和远程书签
- 可以显示“当前打开的是本地缓存副本 / 旧缓存副本 / 正在后台下载”这类状态
- 布局偏好统一按 `comic` 类型保存

### 7.3 阅读器壳层结构

阅读器统一采用以下层次：

1. 内容层  
   漫画页 / PDF 页 / Webtoon 长图

2. 顶部 chrome  
   返回、标题、缩略图按钮、菜单

3. 底部 chrome  
   缩略图 scrubber + 页码/进度 chip

4. 顶部状态层  
   下载进度、刷新状态、缓存提示

5. 模态层  
   页码跳转浮层

默认行为：

- 阅读器打开后 navigation bar 和 tab bar 会隐藏
- chrome 默认隐藏
- `Cmd+W` 可关闭阅读器
- 阅读时禁用自动锁屏，离开阅读器后恢复

### 7.4 顶部 chrome

顶部栏构成：

- Back：`chevron.left`
- 标题：当前漫画标题或远程文件名
- Secondary Action：`square.grid.3x2`，用于快速打开缩略页浏览，仅在 Regular 宽度且页数 > 1 时出现
- Menu：`ellipsis`

按钮风格：

- 白色图标
- 44x44 触控热区
- 半透明圆形背景
- 下方叠加黑色渐变蒙层，避免和内容冲突

### 7.5 底部 chrome

底部栏由两部分组成：

1. 缩略图 Scrubber  
   横向滚动缩略页条，居中页放大并上浮

2. 页码/进度 chip  
   形如 `12 / 180 · 7%`

这个底栏是阅读器中最复杂的导航组件之一：

- 居中页会被识别为当前焦点页
- 拖动时显示浮动大预览卡
- 点击具体缩略页可立即跳页
- 停止拖动后会自动对齐并提交到目标页
- Scrubber 交互中会暂时关闭下拉退出能力，防止手势冲突

### 7.6 缩略图 Scrubber 视觉规则

底部 Scrubber 的视觉规则：

- 中心页缩略图放大
- 越靠近边缘越缩小、变淡
- 焦点页有白色描边
- 中心焦点会有轻微“上浮”
- 两端使用透明渐变遮罩，强化中间聚焦感
- 拖动时会在屏幕中部上方显示更大的浮动预览卡

这是一种明显经过移动端定制的“轻量 Cover Flow”体验，比普通 Slider 更有阅读器产品感。

### 7.7 阅读器设置 Sheet

Reader Controls Sheet 的结构非常完整：

- File Info
- Navigate
- Reading Status
- Library
- Display
- Rotation
- Bookmarks

### Navigate

- 当前页信息
- Browse Thumbnails
- Quick Scrub Slider
- Open Selected Page

### Reading Status

本地 Reader：

- Add / Remove Favorite
- Mark Read / Unread
- Bookmark / Remove Current Bookmark
- Rating 0~5

远程 Reader：

- Bookmark / Remove Current Bookmark
- 跳页 / 缩略页 / 旋转 / 布局设置
- 不包含本地 Library 级元数据动作

### Library

本地 Reader 可直接进入：

- Quick Edit Metadata
- Edit Metadata
- Tags and Reading Lists

### Display

支持的布局项：

- Reading Mode
  - Paged
  - Vertical Scroll
- Fit Mode
  - Fit Page
  - Fit Width
  - Fit Height
  - Original Size
- Page Layout
  - Single Page
  - Double Page
- Reading Direction
  - Left to Right
  - Right to Left
- Show Covers as Single Page

重要规则：

- iPhone 不开放双页展开，iPad 才支持 Double Page。
- Vertical Scroll 模式下会自动隐藏 spread 与 rotation 相关控制。
- 布局偏好按漫画类型独立记忆，本地至少区分 comic / manga / webcomic。

### Rotation

支持：

- Rotate Left
- Rotate Right
- Reset Rotation

旋转角度为：

- 0°
- 90°
- 180°
- 270°

### Bookmarks

书签列表会按页号显示，可直接跳页。

产品上的一个细节差异：

- 本地 Reader 书签数量上限为 3
- 远程 Reader 当前实现未看到同样的 3 个上限限制

这是一个值得产品确认的“本地/远程体验差异点”。

### 7.8 页码跳转浮层

点击底部页码 chip 后会出现页码跳转浮层。

特征：

- 半透明黑色背景遮罩
- 居中的材质卡片
- 顶部显示当前页 / 总页数
- 数字输入框自动聚焦
- `Go` 按钮仅在输入页码合法时可点击
- 非控件区域点击只会先收起键盘，不会直接关闭浮层
- 输入范围必须在 `1...pageCount`

### 7.9 缩略页浏览 Sheet

缩略页浏览是完整独立页面，不只是底部 scrubber 的放大版。

功能包括：

- 网格化浏览所有页
- 当前页高亮
- 顶部概览卡展示 Current / Total
- 输入页码直接打开
- `Open` 打开指定页
- `Current` 快速滚回当前阅读位置
- `Done` 关闭

Regular 宽度下缩略图更大，布局更宽松。

### 7.10 阅读器手势矩阵

这是产品层面最关键的阅读交互说明。

### A. 图片分页阅读（本地 Library）

| 手势 / 输入 | 行为 | 备注 |
| --- | --- | --- |
| 单击中间区域 | 显示/隐藏 chrome | chrome 隐藏时切换为显示；显示时切回隐藏 |
| 单击左侧边缘 | 若当前可向前翻页则翻页；若已到边界且有上一本则打开上一册；若 chrome 已显示则隐藏 chrome | Compact 约 24% 宽度，Regular 约 18% |
| 单击右侧边缘 | 若当前可向后翻页则翻页；若已到边界且有下一本则打开下一册；若 chrome 已显示则隐藏 chrome | 翻页成功有轻触觉反馈 |
| 左右滑动 | 分页翻页 | `UICollectionView` 分页 |
| 双击 | 在“适配缩放”与“约 2.5x 放大”之间切换 | 动画带弹性 |
| 捏合 | 缩放 | 最大缩放约为当前最小缩放的 4 倍或至少 4x |
| 放大后拖拽 | 平移内容 | 仅内容溢出时开放 pan |
| 下拉 | 关闭阅读器 | 仅未缩放、未开 sheet、未开页码跳转、未拖 scrubber 时启用 |
| 键盘右/下/Space | 下一页 | iPad / 键盘场景 |
| 键盘左/上/Shift+Space | 上一页 | iPad / 键盘场景 |

### B. 图片纵向连续阅读（Webtoon / Vertical Scroll）

| 手势 / 输入 | 行为 | 备注 |
| --- | --- | --- |
| 纵向滚动 | 在长图页之间上下浏览 | 这是主导航方式 |
| 单击中间区域 | 显示/隐藏 chrome | |
| 单击左右边缘 | 本地 Reader 下可触发上一册 / 下一册边界动作；远程 Reader 下用于 chrome 切换 | 不承担“页内翻页”职责 |
| 键盘下/Space | 下一页（滚到下一张） | |
| 键盘上/Shift+Space | 上一页 | |
| 下拉 | 关闭阅读器 | 同样受“未缩放、无冲突操作”约束 |

### C. PDF 阅读

| 手势 / 输入 | 行为 | 备注 |
| --- | --- | --- |
| 单击左边缘 | 若 PDF 还能前翻则前一页；否则交给 Reader chrome 路由 | |
| 单击右边缘 | 若 PDF 还能后翻则后一页；否则交给 Reader chrome 路由 | |
| 单击中间 | 显示/隐藏 chrome | |
| 已放大状态下任意单击 | 视为中间点击，仅切换 chrome | 防止误翻页 |
| PDF 自带缩放/拖动 | 由 PDFKit 承担 | |
| 键盘右/下/Space | 下一页 | |
| 键盘左/上/Shift+Space | 上一页 | |

### D. 远程 Reader 的点击路由差异

远程 Reader 为“单本远程内容阅读”模型，点击区域策略更克制：

- 左 / 中 / 右所有单击区域都只负责切换 chrome
- 不存在“点左边打开上一册、点右边打开下一册”的逻辑
- 这与本地书库 Reader 明显不同

### E. 下拉关闭阈值

下拉关闭的触发条件相当明确：

- 位移超过约 `120pt`
- 或向下速度超过约 `800pt/s`

且手势启动要求“明显偏垂直”，避免与左右翻页或 scrubber 拖动冲突。

### 7.11 进度、书签与状态持久化

阅读器会持久化：

- 当前页
- 页数
- 已打开状态
- 是否读完
- 最后阅读时间
- 书签页数组

持久化策略：

- 页面变化后延迟约 `350ms` 做一次去抖保存
- 退出阅读器时强制保存
- 切后台时强制保存

本地 Reader 还会把：

- 收藏状态
- 已读状态
- 评分
- 元数据

写回本地数据库。

### 7.12 已知边界

阅读器里已经明确暴露出的边界包括：

- 某些已被索引的文件类型仍处于“Reader Not Ready”状态
- 文案明确说明：archive page extraction 仍在迁移中

这意味着产品已经支持索引层面识别，但阅读能力并未对所有格式完全补齐。

## 8. 远程浏览系统

### 8.1 Browse Home

Browse 首页负责远程系统的总入口。

### 页面结构

- Servers
- Quick Access

Quick Access 按数据决定是否出现：

| 入口 | 图标 | 颜色 | 条件 |
| --- | --- | --- | --- |
| Saved Folders | `star.fill` | teal | 至少有一个远程收藏文件夹 |
| Offline Shelf | `arrow.down.circle.fill` | green | 至少有一个本地离线副本 |

### 主动作

- 右上角 `plus`：添加远程服务器

### 服务器项操作

- Edit
- Delete

支持：

- Context Menu
- Swipe Actions
- iPad 分栏直接选中右侧展开

### 8.2 远程服务器配置

当前支持两种 Provider：

| Provider | 图标 | 默认色 | 默认端口 |
| --- | --- | --- | --- |
| SMB | `server.rack` | blue | 445 |
| WebDAV | `globe` | indigo | 443 |

### 服务器配置字段

- Display Name
- Provider
- Host
- Port
- Share / Server Path
- Base Directory
- Authentication
  - Guest
  - Username & Password
- Username
- Password

### 交互与产品策略

- 新建默认是 SMB + 用户名密码模式。
- 密码保存在 Keychain。
- 如果编辑服务器时只改路径/凭据，系统会清理相关记忆路径、浏览历史、快捷方式、缓存等，避免旧数据污染。
- 服务器保存前会做校验：
  - 端口必须是数字
  - 需要密码时不能为空
  - Provider 配置合法性需通过 browsing service 验证

### 服务器编辑页视觉

编辑页顶部有概览卡，集中表达：

- 协议
- 端口
- 访问方式
- endpoint
- share / path
- 密码是否已在 Keychain

图形上会在 Provider 主图标右下角叠加一个认证状态小圆点：

- Guest：人物图标，偏橙
- 用户名密码：锁图标，偏绿

### 8.3 Remote Server List / Detail

### Server List 页面能力

- 汇总服务器数、Saved Folders 数、Cached 数
- 查看每台服务器的概览
- 进入详情
- Edit Server
- Open Saved Folders
- Open Offline Shelf
- Clear Browsing History
- Clear Download Cache
- Delete Server

### Server Row 信息

单行会表达：

- 服务器名称
- Provider 类型
- endpoint / share 概要
- 保存文件夹数
- 最近活动
- 离线缓存数

### 8.4 Remote Browser

远程目录浏览器是 Browse 系统里的主战场。

### 页面职责

- 浏览远程目录层级
- 当前目录内搜索
- 排序
- List / Grid 切换
- 收藏当前文件夹
- 保存当前可见漫画到离线
- 将远程漫画导入本地 Library
- 直接进入远程阅读器

### 顶部工具栏动作

- Display Mode：List / Grid
- Sort Menu
- `ellipsis` 菜单：
  - 收藏/取消收藏当前文件夹
  - Up One Level
  - Go to Root
  - Save visible comics / Save results offline
  - Remove downloaded copies
  - Import current folder / Import results

### 搜索

搜索文案是 “Filter this folder”，说明远程搜索当前实现是“当前目录结果过滤”，不是全服务器全文搜索。

### 排序

支持：

- Name
- Recently Updated
- Largest First

### 概览卡信息

远程浏览概览卡会表达：

- 当前路径
- 根目录 / 文件夹上下文图形
- 文件夹数
- 漫画数
- 离线副本数
- 所属服务器
- 是否已收藏该路径
- 当前是否处于过滤状态
- 被隐藏的 unsupported file 数

### 条目类型

| 对象 | 视觉 |
| --- | --- |
| 目录 | `folder.fill` 或目录 tile |
| 远程漫画 | 远程封面缩略图 |
| 远程普通文件 | `doc.richtext.fill` 等文件占位 |

### 缓存状态表达

远程漫画对象的缓存状态很重要：

- Current cache：绿色/缓存可用语义
- Stale cache：橙色/旧副本语义
- Unavailable：无本地副本

在列表中用右下角小圆点表达，在网格中用下载 badge 表达。

### 阅读进度表达

如果该远程漫画已有阅读记录，会优先显示：

- `book.closed`
- 阅读进度文案

而不是显示文件大小。

### Swipe / Context 操作

针对单个远程对象，常见动作包括：

- Save offline / Refresh offline copy
- Remove downloaded copy
- Import to local library
- 对目录执行“整目录导入”或“保存当前结果”

### 8.5 远程导入本地

远程导入不是简单下载，而是有完整的 scope + destination 选择。

### 导入范围

| Scope | 含义 |
| --- | --- |
| Visible Comics Only | 只导入当前过滤结果里可见的漫画文件 |
| This Folder Only | 只导入当前目录直接包含的漫画 |
| Include Subfolders | 递归导入当前目录及所有子目录 |

### 导入流程

1. 从 Remote Browser 发起导入
2. 选择 Import Scope
3. 选择本地目标 Library
4. 后台下载远程文件到本机
5. 再复制进本地目标 Library
6. 自动索引并进入本地书库体系

### 产品上的重要工程约束

- App 全局只允许一套远程后台导入流程运行，避免并发任务互相覆盖
- Library import 会尽量避免把旧缓存副本误导入进正式 Library

### 8.6 Saved Remote Folders

这是远程系统里的“路径级收藏”。

### 能力

- 浏览所有已收藏的远程文件夹
- 搜索 title / path / server
- 可按服务器聚合
- 点击后直接打开该远程路径
- 可 Rename Shortcut
- 可 Remove Shortcut

### 视觉语义

- 主图标：`star.fill`
- 黄色强调
- 元信息包括 server、provider、更新时间、路径

### 8.7 Offline Shelf

Offline Shelf 是远程系统里非常关键的增强能力。

### 能力

- 查看本机已保存的远程漫画副本
- 搜索
- 过滤当前可用 / 旧副本
- 排序
- 按服务器分组
- 直接离线打开阅读
- 回到源目录
- 刷新该副本
- 删除该副本
- 清空单服务器所有离线副本

### 过滤维度

| Filter | 含义 |
| --- | --- |
| All | 全部离线记录 |
| Offline Ready | 当前本地副本是最新可读 |
| Older Copies | 本地副本可能早于远程最新版本 |

### 排序维度

- Recently Opened
- Title
- Server

### 状态文案语义

- Ready on device
- Local copy may be older
- Remote only

这组语义对用户非常重要，因为它明确区分了“可读但可能过时”和“当前最新可离线读”。

### 8.8 远程阅读链路

远程阅读并不是单一实现，而是分情况打开：

### 打开策略

1. 如果用户选择 prefer local cache，且本地已有副本  
   直接打开本地缓存

2. 如果本地已有 current cache  
   优先打开 current cache

3. 如果支持 streaming open，且文档加载器支持远程流式读取  
   先流式打开，再在后台补齐完整下载

4. 否则  
   先完整下载，再进入阅读器

### 打开中的视觉

远程加载页是一个独立设计：

- 黑底纵向渐变
- 顶部发光式 radial highlight
- 白色进度条/百分比
- 显示下载速度
- Back / Retry / Cancel Download 按钮

### 远程 Reader 状态提示

远程 Reader 顶部会浮出状态 badge，常见包括：

- Opened the downloaded copy saved on this device.
- Opened an older downloaded copy saved on this device.
- Background download in progress
- Refreshing Remote Copy

这类状态对用户感知“我读的是线上源还是本地缓存”非常重要。

## 9. 设置与存储系统

### 9.1 Settings Home

Settings 采用 Overview 式入口，Regular 宽度下会进入分栏。

主要分区：

- Reading
- Remote
- Storage
- About

### 9.2 Reading Defaults

为 3 类内容分别维护默认阅读布局：

| 内容类型 | 图标 | 颜色 |
| --- | --- | --- |
| Comics | `book.fill` | blue |
| Manga | `book.closed.fill` | purple |
| Webcomics | `scroll.fill` | green |

Settings 首页只显示摘要，例如：

- Reading Direction
- Fit Mode
- Cover single / spread

### 9.3 Remote Cache Settings

Remote Cache 是单独页面，不只是一个开关。

### 页面汇总指标

- Servers
- Downloads
- Covers
- Imported Size

### 可管理对象

1. Downloaded Copies
2. Cover Thumbnails
3. Imported Comics Library

### 缓存保留策略

可通过 `Cache Preset` 调整远程缓存保留策略，当前有预设概念，而不是用户自由填数字。

### 清理动作

- Clear Downloaded Copies
- Clear Thumbnail Cache
- Clear Imported Comics

### 清理语义差异

- 清理 Downloaded Copies：
  - 删除远程离线副本
  - 清除远程浏览历史
  - 清除记住的远程路径位置
- 清理 Thumbnail Cache：
  - 只删除远程封面缓存
  - 不影响下载副本和阅读进度
- 清理 Imported Comics：
  - 清空 Imported Comics Library 中的实际文件
  - Library 条目本身保留为空

### 9.4 About

Settings 中还会展示：

- App Version
- Local Library Count

说明产品已具备最基础的应用信息页能力，但并不过度复杂。

## 10. 图标与视觉语义总表

以下是项目里最重要的一组图标语义，不是全量 SF Symbol 清单，而是产品信息层最关键的一批。

| 场景 | 图标 | 含义 |
| --- | --- | --- |
| 本地书库 Tab | `books.vertical.fill` | Library 顶层入口 |
| 远程 Browse Tab | `globe.asia.australia.fill` | Browse 顶层入口 |
| 设置 Tab | `gearshape.fill` | Settings 顶层入口 |
| 添加书库 | `folder.badge.plus` | 添加 Library / 导入目录 |
| 导入文件 | `doc.badge.plus` | 导入漫画文件 |
| Continue Reading | `play.fill` 徽章 | 从封面继续阅读 |
| Reading 集合 | `book` | 正在读 |
| Favorites 集合 | `star` | 收藏 |
| Recent 集合 | `clock` | 最近新增 |
| Tags | `tag` / `tag.fill` | 标签 |
| Reading Lists | `text.badge.plus` | 阅读列表 |
| Reader 缩略页 | `square.grid.3x2` | 页缩略浏览 |
| Reader 菜单 | `ellipsis` | 阅读器设置/动作 |
| 收藏 | `star` / `star.slash` | Favorite 状态切换 |
| 当前页书签 | `bookmark` / `bookmark.slash` | 当前页书签 |
| 已读 | `checkmark.circle` | 标记已读 |
| 撤销已读 | `arrow.uturn.backward.circle` | 标记未读 |
| 远程服务器 SMB | `server.rack` | SMB Provider |
| 远程服务器 WebDAV | `globe` | WebDAV Provider |
| Saved Folder | `star.fill` | 收藏的远程目录 |
| Offline Shelf | `arrow.down.circle.fill` | 本地缓存的远程漫画 |
| 缓存策略 | `slider.horizontal.3` | Remote Cache Policy |
| 阅读刷新 | `arrow.clockwise` / `arrow.clockwise.circle` | 刷新/重扫 |
| 危险操作 | `trash` | 删除/清理 |

## 11. 关键交互细节与边界行为

这里列出 PM / QA / 开发特别需要对齐的细节。

### 11.1 点击区域并非总是“翻页”

- 本地分页图片阅读里，边缘点击主要服务于翻页和前后漫画跳转。
- 纵向连续阅读里，左右点击不是页内翻页逻辑，主导航依赖垂直滚动。
- 远程 Reader 里，左右点击不做前后漫画跳转，只切换 chrome。

### 11.2 下拉关闭有严格条件

只有在以下条件都满足时才生效：

- 未放大
- 未打开页码跳转
- 未显示 Reader Controls / Thumbnail Browser / Metadata 等 Sheet
- 未拖动底部 scrubber

### 11.3 Double Page 不是全平台能力

- 只有 Regular 宽度允许双页模式
- iPhone 自动保持 Single Page

### 11.4 Vertical 模式会主动简化控制项

- Vertical Scroll 下隐藏 spread 和 rotation 控件
- 说明产品在这里优先保证“连续阅读一致性”，而不是给过多选项

### 11.5 本地/远程功能并不完全对等

本地 Reader 独有：

- Favorite
- Rating
- Quick Metadata
- Full Metadata
- Tags / Reading Lists
- 前后漫画切换

远程 Reader 独有：

- 缓存来源提示
- 后台下载状态
- 刷新远程副本状态

### 11.6 远程浏览会隐藏 unsupported files

用户在目录里不会直接看到所有不支持项，但页面会保留“隐藏了多少不支持文件”的提示，这是一种折中做法：

- UI 保持干净
- 用户又不会误以为目录内容消失

## 12. 工程实现关注点

这一部分更偏给开发和维护者。

### 12.1 阅读器是统一会话架构

阅读器并不是每种文档各写一套状态，而是通过统一的 `ReaderSessionController` / `ReaderSessionState` 管：

- 当前页
- chrome 显示状态
- 页码跳转状态
- 当前布局

然后再把不同内容类型挂接到不同容器：

- `ImageSequenceReaderContainerView`
- `VerticalImageSequenceReaderContainerView`
- `PDFReaderContainerView`

### 12.2 点击路由是抽象过的

点击不是每个页面自己散写，而是经由：

- `ReaderTapRegion`
- `ReaderTapRoutingConfiguration`
- `ReaderGestureCoordinator`

这意味着后续如果要调整“左中右点击”的产品策略，可以从统一路由层改。

### 12.3 远程阅读是多阶段资源策略

远程打开链路整合了：

- cache 命中
- streaming
- full download
- background download

这部分已经不是单纯 UI 逻辑，而是“资源获取策略 + 体验策略”的组合。

### 12.4 记忆行为很多

产品会记忆：

- 最近选中的导入目标
- 最近浏览到的远程路径
- 阅读布局偏好
- 本地/远程阅读进度
- 远程书签

这使得产品体验更连贯，但也意味着：

- 更需要处理“路径/凭据变化后旧状态失效”的清理逻辑
- 更需要在 QA 中验证跨会话恢复

## 13. 推荐给产品经理重点关注的议题

基于当前代码，建议优先和产品确认以下议题：

1. 本地 Reader 书签上限 3 个，而远程 Reader 当前未见同样上限，是否需要统一。
2. 远程 Reader 不支持前后漫画跳转，这是否符合长期产品预期。
3. Unsupported archive 的迁移优先级是否足够高，因为它直接影响“已索引但不可读”的用户感知。
4. `Linked Folder / App Managed / Read Only` 三类 Library 的用户文案是否需要进一步统一成更易懂的产品语言。
5. Batch Metadata 与 ComicInfo 导入已经很强，是否需要补一套更系统的“整理工作流”入口。

## 14. 推荐给开发与测试重点关注的回归点

1. iPhone / iPad 两套布局都要单独验证，尤其是 split view 与 grid/list 切换。
2. Reader 的点击、缩放、下拉关闭、scrubber 拖动之间手势冲突要重点回归。
3. 远程缓存 current / stale / unavailable 三种状态的 UI 文案与动作按钮要逐一核对。
4. 远程服务器编辑后，旧缓存、旧路径、旧快捷方式是否按预期清理。
5. Import 到 Imported Comics Library 与 Import 到普通 Library 的结果路径与索引行为要分别验证。

## 15. 主要实现入口文件

便于继续追代码的核心入口如下：

- `yacreader/App/AppRootView.swift`
- `yacreader/App/AppDependencies.swift`
- `yacreader/Features/Libraries/LibraryHomeView.swift`
- `yacreader/Features/Libraries/LibraryListViewModel.swift`
- `yacreader/Features/Browser/LibraryBrowserView.swift`
- `yacreader/Features/Browser/LibraryBrowserViewModel.swift`
- `yacreader/Features/Browser/LibrarySpecialCollectionView.swift`
- `yacreader/Features/Browser/LibraryOrganizationView.swift`
- `yacreader/Features/Reader/ComicReaderView.swift`
- `yacreader/Features/Reader/ComicReaderViewModel.swift`
- `yacreader/Features/Remote/RemoteServerBrowserView.swift`
- `yacreader/Features/Remote/RemoteServerBrowserViewModel.swift`
- `yacreader/Features/Remote/RemoteComicReaderView.swift`
- `yacreader/Features/Settings/SettingsHomeView.swift`
- `yacreader/Features/Settings/RemoteCacheSettingsView.swift`
- `yacreader/SharedUI/Components/ReaderChromeOverlay.swift`
- `yacreader/SharedUI/Components/PullDownToDismissModifier.swift`
- `yacreader/SharedUI/Components/ImageSequenceReaderContainerView.swift`
- `yacreader/SharedUI/Components/VerticalImageSequenceReaderContainerView.swift`
- `yacreader/SharedUI/Components/PDFReaderContainerView.swift`
- `yacreader/ReaderKernel/ReaderGestureCoordinator.swift`
- `yacreader/ReaderKernel/ReaderTapSupport.swift`
- `yacreader/Core/Types/ReaderDisplayLayout.swift`

---

这份文档可以视作当前版本的“产品 + 交互 + 实现对照稿”。  
后续如果继续深化，建议下一轮补两类内容：

- 页面级别的逐屏截图说明与状态流转图
- 数据模型 / 数据库字段 / 远程缓存目录结构的工程附录

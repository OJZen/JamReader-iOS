# JamReader iOS UI Redesign Blueprint

更新时间：2026-04-09

## 1. 文档目的

这份文档把现有产品说明、当前 SwiftUI 实现和新的 UI 方向整理成一套可直接落到 Figma 的界面蓝图。

目标不是推翻现有气质，而是在以下前提下统一体验：

- 保留当前代码里已经成立的 iOS 原生感
- 强化“内容优先、阅读优先、层级清楚”的体验
- 让 iPhone 和 iPad 都有稳定、优雅、长期使用不累的界面
- 给设计师一套明确的页面骨架、组件语言和 Figma 页面组织方式

## 2. 设计基线

当前代码已经给出了非常明确的视觉方向，后续设计应沿着这条线继续深化，而不是另起一套品牌语言。

现有基线可从这些文件读出：

- `docs/jamreader-ios-product-engineering-spec.md`
- `docs/ui-design-requirements.md`
- `JamReader/SharedUI/DesignTokens.swift`
- `JamReader/SharedUI/Components/CardSurfaceComponents.swift`
- `JamReader/SharedUI/Components/ReaderChromeOverlay.swift`
- `JamReader/Features/Libraries/LibraryHomeView.swift`
- `JamReader/Features/Browser/LibraryBrowserComponents.swift`
- `JamReader/Features/Browse/BrowseHomeView.swift`
- `JamReader/Features/Settings/SettingsHomeView.swift`

与本地书库相关的页面，还应默认遵守一个实现前提：

- 所有书库状态来自 App 自管数据库与本地资产目录。
- 外部目录只作为漫画内容源，不再展示桌面兼容、镜像模式或数据库路径这类历史概念。

从这些实现里能总结出 6 个必须保留的判断：

1. 这是一个系统感很强的 app，不是重品牌包装型产品。
2. 颜色应该服务信息语义，而不是制造大面积装饰。
3. 列表、分组、sheet、toolbar、context menu 都要尽量贴近 iOS 默认语义。
4. 卡片可以有，但卡片要轻，不要厚重。
5. 阅读器必须是最沉浸、最克制的一层。
6. iPad 不是简单放大版 iPhone，而是分栏工作流。

## 3. 北极星体验

一句话方向：

`像 Books 一样安静，像 Files 一样清楚，像 Photos 一样沉浸，像 Settings 一样可信赖。`

整体感受应是：

- 简洁
- 安静
- 轻盈
- 有秩序
- 内容优先
- 长时间使用不累

明确避免：

- 大面积品牌渐变
- 高饱和色块堆叠
- 过度玻璃化
- 工具栏按钮过多
- 看起来像桌面文件管理器直接缩小
- 一屏上同时出现太多同义动作

## 4. 视觉系统

### 4.1 色彩策略

基础表面继续以系统语义色为主：

| 角色 | 建议 |
| --- | --- |
| App Background | `systemGroupedBackground` |
| Primary Surface | `systemBackground` |
| Secondary Surface | `secondarySystemBackground` |
| Elevated Surface | `secondarySystemBackground` + 轻描边 |
| Primary Text | `label` |
| Secondary Text | `secondaryLabel` |
| Tertiary Text | `tertiaryLabel` |

强调色不新增品牌主色，继续使用 iOS Accent Blue 作为主交互色。其它颜色只承担语义：

| 语义 | 颜色 |
| --- | --- |
| 主交互 / 链接 / 默认高亮 | Blue |
| 成功 / 可离线 / Ready | Green |
| 警告 / Stale / 受限 | Orange |
| 危险 / 删除 | Red |
| 远程 / 网络 / 缓存策略 | Teal / Indigo |
| 收藏 | Yellow |

设计要求：

- 首页和浏览页不出现大面积纯色品牌背景
- 彩色只出现在图标徽标、badge、状态点、按钮强调态
- 阅读器内容页保持黑底体系
- 材质感仅用于 toast、浮层、阅读器输入浮层、少量控制面板

### 4.2 间距与圆角

延续当前代码里的节奏：

| Token | 值 |
| --- | --- |
| 4 | 微间距 |
| 8 | 紧凑内容间距 |
| 12 | 行内结构间距 |
| 16 | 标准内容 padding |
| 20 | 页面区块间距 |
| 24 | 页面大模块起始间距 |
| 32 | 首页区块间距 / 大留白 |

圆角建议统一为 4 层：

| 用途 | 圆角 |
| --- | --- |
| 状态 badge / 小 chip | 10-12 |
| 行级轻卡片 / 列表内突出行 | 14-18 |
| 内容卡片 / 概览卡 | 18-22 |
| Sheet / 大浮层 | 20-24 |

### 4.3 字体层级

只使用系统字体，不引入品牌字体。

| 层级 | 用法 |
| --- | --- |
| Large Title | Tab 首页标题 |
| Title 2 | 空态标题、重点区块标题 |
| Title 3 | 卡片主标题、小节标题 |
| Headline | 侧边栏主标题、列表强调行 |
| Body | 主列表文案 |
| Subheadline | 次级信息 |
| Footnote | 元信息、说明 |
| Caption / Caption 2 | badge、状态、辅助标签 |

文字要求：

- 标题少而稳，不追求广告式排版
- 次级信息尽量保持 1 到 2 行
- 大多数列表项让用户先看到标题，再看到状态
- 数值、路径、日期都归到次级层级

### 4.4 阴影、描边与材质

继续使用轻阴影和轻描边：

- 卡片默认只保留 1px 低透明描边
- 阴影只给浮起层和少量 toast，不给普通列表过度投影
- 材质优先 `ultraThinMaterial` 或接近系统材质的轻玻璃感
- 玻璃感只给辅助 UI，不盖住主要内容

### 4.5 核心组件语言

这套 UI 的核心不是“花式控件”，而是少量可复用的结构模块：

1. Overview Card
2. Inset Content Card
3. Inset List Row
4. Status Badge
5. Inline Metadata Line
6. Quick Filter Chips
7. Summary Metric Pill
8. Empty State
9. Feedback Toast / Banner
10. Reader Chrome Button

统一规则：

- 图标左、信息右、动作后置
- badge 永远是附加信息，不夺主标题
- 元信息优先横排，空间不够时自动折为竖排
- 每个卡片只强调一个主意图，避免同卡片里塞太多按钮

## 5. 页面级 UI 方案

### 5.1 App Root

顶层保持 3 Tab：

- Library
- Browse
- Settings

界面策略：

- Root 背景统一使用 grouped background
- Tab 图标延续当前 SF Symbols
- 全局远程导入反馈卡继续悬浮在 TabBar 之上
- 悬浮反馈卡应显得像系统任务提示，而不是通知横幅

紧凑型设备：

- 使用标准大标题导航
- 保持页面自带滚动上下文，不做过度自定义 tab 容器

Regular 宽度：

- 每个一级页面优先进入 split workflow
- 左栏维持稳定导航，右栏承载真正内容

### 5.2 Library Home

新的 Library 首页建议从“纯列表入口”升级为“轻总览入口”，但仍然保持克制。

#### iPhone 布局骨架

从上到下：

1. Continue Reading 横向卡片带
2. Libraries 分组列表
3. Import Entry Card
4. 可选维护提示或最近扫描结果

#### iPad 布局骨架

左栏：

- Libraries 列表
- 固定 Add 按钮

右栏空态：

- 如果没有库，显示 Add Library 引导
- 如果已有库但未选中，显示 Select a Library

右栏选中后：

- 该 library 的概览摘要
- Continue Reading
- Browse By

#### Library Row 设计

每个资料库行只表达最重要的 4 件事：

- 名称
- 规模摘要
- 当前访问状态
- 库类型

视觉规则：

- 左侧保留彩色方形 icon badge
- 标题使用 semibold body
- 副标题为单行灰字
- 状态用 metadata line，不做过大 badge 堆叠

#### Import Entry Card

建议增加一个轻量导入卡片，内部是 3 个清晰动作：

- Add Library Folder
- Import Comic Files
- Import Comic Folder

设计方式：

- 使用单张 InsetCard
- 每个入口用图标 + 标题 + 一句说明
- iPhone 下垂直排列
- iPad 下可做三列等宽 action tiles

### 5.3 Library Browser

Library Browser 是信息最密集的页面，设计重点是“把复杂功能层级化”。

#### Root 首页

根层不是文件列表，而是总览页。建议结构：

1. Overview Card
2. Browse By 快捷分区
3. Continue Reading 预览
4. Recently Added 预览
5. Favorites 预览

Overview Card 需要表达：

- Library 名称
- 当前路径或 Root 状态
- comic / folder 数
- 库类型 / 可写性
- 最近扫描状态

视觉建议：

- 左上使用 library icon badge
- 右上保留 maintenance menu
- 中间用 2 到 3 个 summary metrics
- 底部是状态 metadata line

#### 子目录页

进入子目录后，页面切换成更偏文件浏览器的结构：

1. 当前目录 Overview Card
2. Up / Root chips
3. Folders
4. Comics
5. 搜索或筛选结果状态条

视觉要求：

- 当前路径尽量简短显示，长路径可在次级说明里换行
- Up / Root 是轻量 chip，不做大按钮条
- 文件夹列表在上，漫画列表在下

#### 搜索与筛选条

紧凑型设备：

- 使用系统 searchable
- Quick Filter 单独放在搜索结果下方

Regular 宽度：

- 搜索框、Quick Filter、Sort、Display Mode 可以在同一内容顶部形成两层轻工具区

Quick Filter 样式：

- 默认灰底圆角矩形
- 选中时变 Accent Blue，文字反白
- 图标比文字更轻，不要太抢

#### 漫画 List Row

行内信息顺序：

1. 封面
2. 标题
3. 副标题
4. 阅读状态行
5. 可选 issue badge

设计重点：

- 标题允许两行
- 进度、收藏、书签数量融合成一行轻 metadata
- `#issue` badge 只在有值时出现
- 不让行尾动作破坏主内容阅读节奏

#### 漫画 Grid Card

Grid 仅在 Regular 宽度作为重点浏览模式。

卡片结构：

- 大封面
- 标题
- 副标题
- 状态 badges

要求：

- 卡片高度稳定
- 封面与文字保持清楚间距
- 选中态用 accent 描边，不做大面积蓝底

### 5.4 Browse Home

Browse 首页的目标是让用户一进来就知道：

- 我有哪些服务器
- 我有哪些远程快捷入口
- 我有哪些离线资产

#### 页面结构

从上到下：

1. Remote Summary Card
2. Servers
3. Quick Access

Remote Summary Card 建议新增：

- 服务器数
- Saved Folders 数
- Offline Copies 数

这样用户第一次进 Browse，不会只看到一串服务器名称。

#### Server Row

每行保持轻量：

- Provider badge
- 服务器名
- endpoint + provider 摘要
- 行尾 chevron

如果未来要增加信息，优先加在详情页，不要把首页行变成信息墙。

#### Quick Access

Saved Folders 和 Offline Shelf 应该有更明显的“功能入口”感：

- 使用和服务器相同的 icon badge 体系
- 保留右侧数量
- 色彩分别固定为 teal / green

### 5.5 Remote Server Detail 与 Editor

虽然当前代码重点放在浏览流程，但这两个页面建议统一成更完整的系统型表单体验。

#### Server Detail

页面结构：

1. Hero Overview Card
2. Saved Folders
3. Offline Copies
4. Maintenance Actions

Overview Card 信息：

- Server Name
- Provider
- endpoint
- share / base path
- auth mode
- keychain status

视觉点：

- 主 provider 图标右下叠加 auth 状态点
- 点的语义保持现有规则
- Guest 用橙色人物
- Credentials 用绿色锁

#### Server Editor

表单继续用 grouped form，但建议顶部始终有一个 Preview Card：

- 当前协议
- 当前端口
- endpoint 拼装结果
- 认证方式

交互要求：

- 不合法输入即时显示 inline 提示
- 保存按钮只在可提交时高亮
- 密码字段默认不回显，但要有 “Stored in Keychain” 提示

### 5.6 Remote Browser

Remote Browser 是 Browse 系统的主战场，设计应该更像“可阅读的远程目录”，而不是通用网络文件管理器。

#### 页面骨架

1. Context Overview Card
2. Filter this folder Search
3. Sort / Display / More
4. Folder results
5. Comic results

#### Context Overview Card

建议信息区块为：

- 当前路径
- 当前 server
- folder 数
- comic 数
- offline 数
- 是否收藏
- 是否处于过滤状态
- unsupported 隐藏数量

布局建议：

- 顶部一行放路径与 server
- 中间用 3 个 summary metrics
- 底部用 metadata badges 表示 favorite / filtered / unsupported

#### 远程对象 Row / Card

目录：

- 以 folder icon 或目录 tile 为主
- 辅助表达路径、子项数、更新时间

漫画：

- 封面优先
- 标题和文件名分层
- 若有阅读进度，优先显示进度而非体积
- 缓存状态只做一处重点表达

缓存状态建议统一：

- Ready: 绿色点或绿色 badge
- Stale: 橙色点或橙色 badge
- Remote only: 灰色弱化状态

#### More Menu 的呈现方式

低频动作集中进 `ellipsis`：

- Favorite / Unfavorite Folder
- Up One Level
- Go to Root
- Save visible comics
- Remove downloaded copies
- Import current folder

原则：

- 高频浏览动作在主界面可见
- 批处理和维护动作不要上浮成页面主按钮

### 5.7 Saved Folders

这是远程系统里最容易做得“温和而有辨识度”的页面。

页面结构：

1. 搜索
2. 可按服务器分组的列表
3. 每条 shortcut 使用星标卡片

卡片语言：

- 主图标为黄色星形
- 标题是 shortcut title
- 次级信息是 server、provider、updatedAt
- 路径放在 metadata 中，不抢主标题

如果内容较多：

- iPhone 仍以列表卡片为主
- iPad 可加左侧 group list，右侧 detail preview

### 5.8 Offline Shelf

Offline Shelf 应体现“可读资产管理”的感觉，而不是单纯下载列表。

页面结构：

1. Summary Strip
2. 搜索
3. Filter Chips
4. Sort
5. 以服务器为组的离线漫画列表

Filter Chips：

- All
- Offline Ready
- Older Copies

每个离线对象需表达：

- 封面
- 标题
- server
- 最后打开时间或状态文案
- Ready / Older / Remote only

建议为每台服务器增加组头摘要：

- 服务器名
- 当前离线数
- Clear All for This Server

### 5.9 Reader

Reader 是整套设计里最该“少设计”的页面，因为内容本身就是主角。

#### 阅读器主界面

保持现有结构：

1. 内容层
2. 顶部 chrome
3. 底部 chrome
4. 顶部状态层
5. 模态层

#### 顶部 chrome

维持 44x44 半透明圆形按钮，不要做成厚重导航条。

规则：

- 白色图标
- 黑色渐变遮罩
- 标题始终居中感强，但不挤压按钮热区
- Regular 宽度时才出现缩略页快捷按钮

#### 底部 chrome

底部是阅读器最有产品特征的区域，建议继续强化：

- 居中页放大并轻微上浮
- 焦点页保留白描边
- 左右边缘增加渐隐遮罩
- 页码 chip 使用轻玻璃或轻描边深色 capsule

#### 页码跳转浮层

视觉方向：

- 整体黑色半透明遮罩
- 中间卡片使用深色材质
- 输入框宽而稳，数字一眼可读
- Go 按钮为唯一主强调色

#### Reader Controls Sheet

不建议做成重设计面板，继续保留系统 sheet 气质。

层次建议：

- 顶部显示当前漫画标题和封面小缩略图
- 每个 section 标题清楚，但避免过粗
- Toggle / Menu / Rating 都优先用系统 form 风格

#### 远程打开加载页

这部分建议保留更鲜明的气氛，但仍要克制：

- 黑底纵向渐变
- 顶部一团低强度 radial glow
- 白色主进度
- 次级信息显示下载速度与状态
- 主操作只保留 Back、Retry、Cancel Download

### 5.10 Settings

Settings 不需要做成“控制台”，应像一个可靠的系统设置入口。

#### Settings Home

首页结构建议：

1. Overview Summary Card
2. Reading
3. Remote
4. Storage
5. About

Summary Card 可以表达：

- 当前默认阅读模式摘要
- 远程缓存策略
- 本地导入库占用

#### Pane Row

延续现有 iOS Settings 风格：

- 左侧彩色 icon
- 中间标题 + 一句 detail
- 无需额外装饰背景

#### Remote Cache Settings

应是单独的管理页，而不是简单 form。

建议结构：

1. Summary Metrics
2. Cache Preset
3. Downloaded Copies
4. Thumbnail Cache
5. Imported Comics

清理按钮规则：

- destructive 动作永远单独分组
- 每种清理语义都必须有明确说明

## 6. 动效与过渡

动效原则：弱存在感，但有明确目的。

保留并强化这些动效：

1. 封面进入阅读器的 Hero 过渡
2. 阅读器 chrome 的淡入淡出
3. Scrubber 的缩放与上浮
4. Toast / feedback card 的轻弹出
5. pull-down dismiss 的跟手下移和整体淡出

避免：

- 首页大面积错层动画
- 卡片无意义漂浮
- 过强弹簧
- 列表每个元素都独立入场

## 7. 自适应规则

### 7.1 iPhone / Compact

- 以 List 为主，Grid 只在必要场景出现
- Toolbar 动作适度收拢
- 优先单手可达
- 保持标题、筛选、搜索的清楚顺序

### 7.2 iPad / Regular

- 采用分栏，避免把所有内容堆在一个长页面
- 列表与详情并存
- Grid 更积极
- 行级常驻更多操作，但依然不应显得嘈杂

## 8. Figma 组织建议

虽然这份文档没有直接写入 Figma 文件，但建议设计稿按下面结构组织，便于后续实现和对照代码。

如果需要更具体的画板、组件尺寸和页面线框，请继续参考：

- `docs/jamreader-ios-figma-screen-spec.md`

### 8.1 Pages

推荐建 4 个 Figma 页面：

1. `Foundation`
2. `Compact Flows`
3. `Regular Flows`
4. `Components`

### 8.2 Foundation 页面

至少包含：

- Color roles
- Spacing scale
- Corner radius
- Typography scale
- Icon badge samples
- Status badge samples
- Surface examples
- Reader chrome button

### 8.3 Compact Flows 页面

建议至少覆盖这些帧：

- App Root
- Library Home
- Library Browser Root
- Library Browser Folder
- Browse Home
- Remote Browser
- Saved Folders
- Offline Shelf
- Reader
- Reader Controls Sheet
- Settings Home
- Remote Cache Settings

### 8.4 Regular Flows 页面

建议至少覆盖：

- Library split view
- Browse split view
- Settings split view
- Reader on iPad
- Grid-first browser state

### 8.5 Components 页面

建议抽出这些组件：

- InsetCard
- InsetListRow
- OverviewCard
- LibraryRow
- ServerRow
- ComicRow
- ComicCard
- StatusBadge
- InlineMetadataLine
- FilterChip
- SummaryMetricPill
- Toast
- Reader chrome controls

## 9. 首轮设计优先级

如果时间有限，优先做这 8 个高价值界面：

1. Library Home
2. Library Browser Root
3. Library Browser Folder
4. Browse Home
5. Remote Browser
6. Offline Shelf
7. Reader
8. Settings Home

这 8 个页面定下来后，整套产品的视觉秩序基本就成立了。

## 10. 给实现阶段的约束

设计落地时应始终和现有实现约束对齐：

- 保持系统字体
- 保持 SF Symbols 体系
- 保持当前语义色主导
- 保持 iPhone / iPad 双布局
- 阅读器不引入高干扰 UI
- 状态表达优先用 badge、metadata、轻提示，不滥用 banner

## 11. 总结

这次 UI 设计不应追求“焕然一新”的视觉翻新，而应追求“更像一款已经成熟的 iOS 漫画阅读器”。

正确的方向不是把界面做得更响亮，而是：

- 让内容更靠前
- 让层级更稳定
- 让信息更容易扫读
- 让阅读更沉浸
- 让本地与远程两个系统看起来属于同一个产品

# JamReader 维护踩坑记录

更新时间：2026-08-23

这份文档记录项目重构和真机调试过程中反复踩过的坑。目标不是描述所有实现细节，而是让后续维护者在遇到类似问题时先检查这些高风险点，避免继续叠补丁。

## 1. 总体原则

- App 自管数据库是唯一业务真相。外部目录只是内容源，不要把业务状态、封面缓存、扫描状态写回源目录。
- 本地库、远程缓存、远程流式、完整下载后阅读必须尽量走统一 reader pipeline。不要重新引入远程专用阅读状态机。
- 远程缓存、导入缓存、缩略图缓存、数据库记录必须成对维护。只删文件不删记录，或者只删记录不删文件，都会制造“显示已缓存但打不开”这类问题。
- SwiftUI 外层负责业务和导航，UIKit 层负责高频列表、阅读器页面、手势、缩略图列表和复杂转场。不要把手势和 viewport 状态分散到多个 SwiftUI 生命周期回调里。
- 真机问题优先相信现象。iPadOS 后台恢复、旋转、sheet 手势、SMB/WebDAV 网络行为经常和模拟器不同。
- 当前文档、`.github` 里的 AI 指令和 README 不能互相矛盾。过时计划和交付稿应删除，由 Git 保留历史。

## 2. 原生库数据库

### 2.1 不要恢复旧桌面库兼容逻辑

当前架构已经移除旧隐藏库目录、`library.ydb`、`storageMode`、`mirrored`、`Desktop Compatible` 这套兼容模型。后续如果看到相关代码或文案，通常是回归。

检查：

```bash
rg -n "library\\.ydb|\\.jamreaderlibrary|storageMode|Desktop Compatible|Browse Only|mirrored" JamReader
```

预期：

- 运行时代码不依赖这些关键字。
- 文档中可以作为历史说明出现，但不能作为当前功能路径。

### 2.2 SQLite 外键必须每次连接都开启

SQLite 的 `PRAGMA foreign_keys = ON` 是连接级设置，不是数据库级设置。只在初始化时打开不够，后续新连接仍可能不执行级联删除。

风险现象：

- 删除漫画后 `comic_tags` 或 `reading_list_items` 留 orphan。
- 删除 library 后 `folders / comics / tags / reading_lists / scan_runs` 没有一起清理。
- 组织页、标签页、阅读列表计数和实际内容不一致。

维护要求：

- 所有数据库写入都通过 `AppLibraryDatabase.withConnection`。
- `withConnection` 每次建连后执行 `PRAGMA foreign_keys = ON`。
- 新增直接 SQLite 连接时必须重复这个规则。

### 2.3 整型 ID 不是跨库安全身份

公开模型目前仍保留 `Int64` ID，但这些 ID 不能被当作全局唯一业务身份。全局单库 SQLite 下，任何写操作如果只写 `WHERE id = ?`，都可能误改另一个 library 的同 ID 记录。

维护要求：

- 状态写入必须先解析当前 `libraryID`。
- `UPDATE / DELETE / INSERT ... SELECT` 必须带 `library_id` 条件。
- 标签、阅读列表、成员关系写入前必须验证 comic/tag/readingList 属于同一个 library。
- `stable_id` 是为未来同步准备的内部 UUID，不等于当前 UI 选择集的公开 ID。

检查：

```bash
rg -n "WHERE id = \\?|DELETE FROM [a-z_]+ WHERE id = \\?|UPDATE [a-z_]+.*WHERE id = \\?" JamReader/Data
```

### 2.4 数据库读取失败不能伪装为空库

`LibraryDescriptorStore.load()` 这类入口不能吞掉数据库错误并返回空数组。否则上层可能把“读取失败”理解成“没有库”，进而触发错误初始化、错误覆盖或误导 UI。

正确行为：

- 数据层真实抛错。
- ViewModel 把错误转换成 alert 或错误状态。
- 不要在失败时静默清空库列表。

### 2.5 删除库和删除缓存是两件事

删除 library 应该清理库记录、索引、状态、资产目录和必要的真实文件。删除缓存只应该清理远程下载副本、缩略图、半成品下载等缓存内容。

高风险点：

- 设置页“删除缓存”不能删除用户导入到本地库的漫画。
- 删除缓存后必须同步删除对应缓存数据库记录。
- `Imported Comics` 是普通 app-managed library，不是远程缓存。
- UI 上显示的缓存大小应使用真实磁盘占用，不要只累加逻辑文件大小。

### 2.6 新建 library 后重启打不开，多半是 root/bookmark 持久化问题

曾出现新建 library 当次可用，重启后显示没有权限。不要只查 UI 导航，优先查 library 记录和 root URL 恢复。

维护要求：

- App-managed library 的 root 应在 App 沙盒内，并能由 library 记录稳定恢复。
- Linked folder 必须持久化 security-scoped bookmark。
- `rootPath`、`bookmarkData`、`kind` 和实际文件位置要一起验证。
- 重启 app 后至少验证一次新建库打开、导入、刷新。

### 2.7 命名、沙盒路径和文档必须一致

项目已经改名为 JamReader。重命名时容易漏掉三类位置：

- `Application Support/JamReader`、`Caches/JamReader` 这类持久化目录。
- bundle id、显示名、scheme、日志 label、UserDefaults key。
- README、`.github/copilot-instructions.md`、`docs/README.md`、检查脚本。

维护要求：

- 不要因为改名就迁移或删除用户数据，除非明确设计了迁移流程。
- 新增持久化路径时使用统一 helper，不要手写旧目录名。
- 当前架构说明和 AI 指令必须以 App 自管数据库为准；已失去决策价值的迁移或设计计划不要继续留在工作树中。

## 3. 导入链路

### 3.1 远程导入不是“离线缓存”

SMB/WebDAV 导入到本地库时，流程应是：

1. 远程文件下载到临时/staging 位置。
2. 导入服务复制或移动到目标 library root。
3. 本地库扫描索引新文件。
4. 刷新 library 列表、漫画数量、最近记录和目标页面。
5. 清理临时下载。

不要把“远程离线缓存存在”当作“本地库已导入”。这两个概念的数据表、生命周期和删除入口不同。

### 3.2 导入完成但库为空，通常检查索引阶段

出现“下载流程完成、库存在、但库里没有漫画”时，优先检查：

- 文件是否真的复制到了目标 library root。
- 目标 root 是否是当前 library 记录中的 root。
- 导入后是否调用扫描/indexing。
- 扫描是否忽略了目标文件类型。
- 扫描是否被隐藏文件规则、目录规则、取消 token 或权限错误提前中断。
- UI 是否刷新了对应 library 的 snapshot 和漫画数量。

### 3.3 文件夹导入要区分“图片漫画目录”和普通目录

以图片文件为主的目录是一个完整漫画，不是普通文件夹集合。递归扫描时不能把这类目录继续拆散成多个条目。

维护要求：

- 图片目录识别优先于普通目录递归。
- 隐藏目录和点开头文件应被忽略。
- 历史隐藏兼容目录、历史 app 垃圾目录也应被忽略。

### 3.4 导入期间 UI 冻住，先查 overlay hit-testing

SMB 导入时曾出现“界面完全无法操作”。根因不是下载本身，而是全屏导入浮层 window 的透明区域吞掉了所有触摸。

相关文件：

- `JamReader/App/AppRootView.swift`
- `JamReader/App/AppRootTabBarControllerView.swift`

维护要求：

- 高层 overlay window 必须是 passthrough。
- 透明区域必须把触摸透传给底层 window。
- 只有实际含 `UIControl` 或 gesture recognizer 的浮层控件可以接收触摸。
- `Color.clear` 只用于监听或测量时必须 `.allowsHitTesting(false)`。

排查方法：

- 导入进行中尝试滚动底层列表、切 tab、点击底层按钮。
- 同时确认导入卡片的取消、展开、主操作按钮仍能点击。

### 3.5 导入实时刷新不能只刷新当前页面

导入期间和导入完成后，需要刷新多个层级的 UI。只刷新导入弹窗或远程浏览器不够。

维护要求：

- Library Home 的漫画数量要更新。
- 目标 Library Browser 要能看到新漫画。
- 最近阅读、继续阅读、特殊集合和组织页的 snapshot 不应卡在旧状态。
- 导入失败或部分失败时，反馈要区分下载失败、复制失败、索引失败。
- 远程导入完成后打开目标库，应优先使用最新 library descriptor 和 scanner 结果。

## 4. 远程 SMB/WebDAV

### 4.1 WebDAV Range 是流式读取和封面预读的边界

ZIP/CBZ 不是顺序友好的格式。没有 Range 支持时，为了读取封面或页面，经常必须下载大量甚至完整文件。

当前策略：

- WebDAV 支持 Range：允许 ZIP 边读边缓存、允许封面读取。
- WebDAV 不支持 Range：不读取封面，不做边读边缓存，完整下载后再打开。
- SMB：可通过随机读/分块读支持更好的远程读取体验，但仍要防止并发缓存任务互相影响。

不要为了“显示一个封面”对 no-Range WebDAV 做全量下载。

### 4.2 PDF 封面预取要保守

PDF 封面获取曾导致目录卡死风险，尤其在二级目录预热封面时更危险。

维护要求：

- 远程浏览器封面预热不要主动处理 PDF。
- 二级目录封面预热需要超时、数量上限和连续失败熔断。
- 当前目录封面未完成前，不要激进扫描更深层目录。

### 4.3 SMB/WebDAV 浏览器要隐藏点开头文件

远程浏览器应隐藏：

- 点开头文件和目录。
- app 自己或其他漫画应用留下的隐藏目录。
- 不支持的普通文件。

原因：

- 用户目录不应被系统文件污染。
- 二级目录预热如果读到异常文件，容易造成卡顿或失败。

### 4.4 同名图片封面优先级

如果漫画文件旁边存在合法的同名图片，应优先作为漫画封面，而不是打开压缩包读取第一页。

维护要求：

- 只接受合法图片。
- 失败时回退压缩包封面。
- 远程和本地封面链路都要保持一致，否则列表/grid 可能显示不同封面。
- Grid 从低清缓存切高分辨率时要避免黑边和拉伸错误。

### 4.5 远程缓存必须有 active lease

阅读器正在使用的缓存文件不能被缓存清理、自动裁剪或手动删除任务删掉。

风险现象：

- 打开漫画后突然“漫画不可用”。
- 连续打开多个漫画后全部不可用。
- 后台回来后最近阅读里的缓存漫画打不开，重启 app 又恢复。

维护要求：

- 打开 reader 时注册 active cache lease。
- reader 销毁或切换漫画时释放 lease。
- 缓存清理必须跳过 active lease 文件。
- 缓存记录损坏或文件缺失时要清理记录，并给出可重试错误。

### 4.6 旧缓存会伪装成当前网络问题

WebDAV/SMB 曾出现“ZIP 打不开”，后来确认是旧缓存损坏或旧路径记录导致。排查远程打开失败时，不要只看网络协议。

优先检查：

- 缓存记录指向的文件是否存在。
- 文件大小、mtime、remote signature 是否和记录一致。
- 缓存文件是否是半成品下载。
- 打开失败后是否清理了坏记录并按当前远程策略重试。
- 用户手动删除缓存后，数据库记录是否同步删除。

### 4.7 远程浏览状态是用户体验状态，不是业务真相

远程服务器页面、当前目录、侧边栏收缩状态、列表/grid 显示模式需要记住，但这些状态不能影响文件打开、导入或缓存判断。

维护要求：

- 浏览状态可存在 UserDefaults。
- 远程服务器配置和凭据仍按现有 JSON/UserDefaults/Keychain 体系处理。
- 不要把远程浏览状态混入 AppLibraryV2.sqlite 的本地漫画库表。
- 切换服务器、删除服务器、凭据失效时，要清理或忽略对应浏览状态。

## 5. 统一阅读器 Pipeline

### 5.1 不要再拆本地 reader 和远程 reader

当前目标是所有入口生成统一 `ComicOpenRequest`，再由 `ComicOpenCoordinator` 打开成 `ComicReaderSession` 和 `ComicDocument`。

维护要求：

- 本地库、最近阅读、远程缓存、远程流式、完整下载后打开都走同一个 `ComicReaderView`。
- 远程进度可以继续写 JSON，但只能通过统一 state store adapter 访问。
- 不要新增远程专用 reader shell 来单独维护 page/layout/bookmark/progress。
- 阅读布局默认值由 `ReaderLayoutPreferencesStore` 全局共享；不要再按漫画类型拆分设置入口、持久化 key 或运行时选择分支。

### 5.2 Opening Comic 卡住但下滑时显示图片，是层级或状态发布问题

曾出现实际文档已打开，但 UI 一直显示 `Opening Comic`；触发下滑关闭或其他刷新后图片才出现。

优先检查：

- `ComicReaderLoadState.ready` 是否已发布到主线程。
- opening fallback 是否仍在 document layer 上方。
- ZStack 的 `zIndex` 是否让 loading 覆盖 ready 内容。
- `Task` token 是否过期结果覆盖了当前 ready 状态。
- UIKit reader 容器是否已创建但 SwiftUI 没有重新计算 body。

不要用“多刷新一次”掩盖这个问题。正确修复应保证 ready 后 document 层稳定高于 fallback。

### 5.3 后台恢复不能释放 reader 资源

App 进入后台时可以保存进度、清理图片内存缓存，但不能释放当前 document/source lease。

风险现象：

- 后台一段时间回来后显示漫画不可用。
- reader 自动退出并伴随导航返回动画。
- 最近阅读缓存漫画偶发打不开，重启恢复。

维护要求：

- `didEnterBackground` 只做保存和可重建缓存清理。
- 安全作用域、远程 reader、document pageSource 的释放只发生在 reader deinit、切换漫画或明确关闭时。
- 后台恢复后不要自动重建导航栈。

### 5.4 异步打开必须使用 request token

远程下载、缓存检查、文档打开、封面生成都可能晚于用户的下一次操作完成。过期任务不能覆盖当前 reader 状态。

维护要求：

- 每次打开漫画生成新 token。
- async 结果回写前检查 token。
- 切换漫画、关闭 reader、重新打开 reader 时取消旧任务。
- 后台缓存完成不能重置当前页码。

### 5.5 阅读进度刷新要向列表回传

从最近阅读或 library 打开漫画，阅读页码变化后，返回列表需要刷新对应 item。

维护要求：

- 本地进度写入后触发 `onComicUpdated`。
- 最近阅读、继续阅读、收藏、特殊集合都要接收同一个更新事件。
- 不要只更新 reader 内部 ViewModel。

### 5.6 “远程缓存能打开、本地库打不开”通常是 source resolution 分叉

曾出现远程浏览器里的离线缓存能打开，但同一漫画从本地库打开卡在 `Opening Comic`。这类问题通常不是解码器问题，而是本地库入口和远程缓存入口解析出来的 readable source 不一致。

维护要求：

- 所有入口都构造 `ComicOpenRequest`。
- 文件 URL、security scope、cache lease、reader state scope 都由 `ComicOpenCoordinator` 统一解析。
- 不要在某个入口绕过 coordinator 直接创建 `ComicDocument`。
- 本地库记录的 `relativePath` 要和 library root 组合验证，不能拿远程 cache URL 兜底。

## 6. 阅读器布局、手势和旋转

### 6.1 首次翻页放大，多半是 zoom/layout 初始化顺序问题

现象：

- 刚打开漫画后第一次左右翻页，下一页看起来被放大。
- 翻过去后瞬间恢复正常。

排查：

- 新页面进入可见区前是否已经用最终 bounds 计算 min zoom。
- cell/page reuse 时是否重置了 zoomScale。
- `contentInset`、`contentOffset` 是否在 imageView frame 确定前写入。
- 是否存在延迟布局覆盖了初始化值。
- 取消一次未完成的翻页后，当前页重新挂载时必须保留用户缩放，不能按“新页面”重置。

现有保护入口：

- `ReaderSpreadWillDisplayActionTests` 覆盖取消翻页返回当前页时保留 viewport。
- `ReaderViewportLayoutActionTests` 覆盖目标 viewport 到达前等待、真实尺寸变化后重置、尺寸不变时保留缩放。

### 6.2 竖屏切横屏错乱，先查窗口 bounds 和容器重建

曾出现竖屏切横屏后左侧黑屏 reader、右侧露出漫画列表。根因属于 reader presentation/container 在旋转时没有稳定占满窗口。

维护要求：

- iPad multitasking/旋转不要使用 `UIScreen.main.bounds` 作为真实 viewport。
- 优先使用当前 reader/collection view 的实际 bounds，而不是全局屏幕尺寸。
- viewport 变化时通过 `synchronizeCachedControllerViewports(to:)` 更新全部缓存页面，不能只更新当前页。
- 页面在目标 viewport 到达前应等待；只有真实尺寸变化才重置布局，尺寸未变时保留用户缩放。
- 不要为了旋转重建 reader session、document 或 source lease。
- 横屏打开正常但竖屏切横屏错乱时，重点查旋转生命周期，不是文档加载。

轻微闪一下可以接受；露出底层列表或出现半屏黑屏不可接受。

### 6.3 缩略图窗口必须用高性能列表

SwiftUI 原始缩略图列表在大量页面时性能很差。现在应使用 UIKit collection/list 实现。

维护要求：

- iPhone 默认双列。
- iPad 默认三列或根据宽度计算更高列数。
- 顶部信息和列表的滚动关系要明确，不要让 sheet 手势抢走列表滑动。
- 第二次打开缩略图窗口崩或退出 reader，通常是 sheet identity、dismiss binding 或 reader presentation 状态冲突。

### 6.4 Sheet 里的滚动和下拉关闭会互相抢手势

缩略图 sheet 曾出现列表无法滑动，向下滑直接关闭窗口。

维护要求：

- 使用 `.presentationContentInteraction(.scrolls)`。
- UIKit collection view 必须承担滚动，不要外面再包一层会抢手势的 SwiftUI ScrollView。
- sheet 顶部固定区域过大时会让列表不可见，应让顶部内容跟随列表滚动或压缩。

### 6.5 iPadOS 顶部系统栏会遮挡 reader chrome

阅读器显示 UI 时，返回按钮和系统时间可能重叠。

维护要求：

- 顶部 chrome 使用窗口 safe area，不只用 SwiftUI safeAreaInsets。
- reader 全屏 `.ignoresSafeArea` 后，内部控件仍要手动加安全区。
- 旋转后重新解析 window safe area。

## 7. 导航和转场

### 7.1 SwiftUI 导航状态和 UIKit 转场不要互相抢控制权

项目中经历过阅读器自动退出、页面返回到最顶层、缩略图窗口打开后 reader 被干掉等问题。很多不是 reader 文档问题，而是导航状态和 presentation 状态互相覆盖。

维护要求：

- 读者页的打开/关闭由统一 presentation coordinator 管理。
- 不要在多个 ViewModel 同时持有“当前 reader 是否显示”的真源。
- `onDisappear` 不等于用户关闭 reader，尤其在 sheet、旋转、后台恢复时。
- 后台恢复时不要重置 root tabs 或导航栈，除非检测到实际结构损坏。

### 7.2 Hero 动画依赖 source frame，后台恢复后容易失效

后台久了回来，hero 动画可能退化成从左上角展开。这通常是 source view/frame 已过期。

维护要求：

- 进入后台或页面刷新后，source frame 需要重新捕获。
- 如果找不到稳定 source frame，应退化成明确的 bottom-up 或 fade，而不是使用 `(0,0)` 假 frame。
- 不要让旧截图或旧 preview image 覆盖新打开的漫画。

### 7.3 Root tab 修复逻辑要保守

iPadOS 后台恢复后曾出现 tab 栏多出空白项。修复 root tabs 是必要的，但修复逻辑不能把正常 navigation/presentation 当作损坏来重装。

维护要求：

- 只在 tab controller 数量或 identity 明显错误时 repair。
- repair 不应关闭正在显示的 reader 或 sheet。
- didBecomeActive 里的 repair 必须尽量小。

### 7.4 Sheet 和 reader presentation 不能共享隐式关闭信号

缩略图 sheet 第二次打开后 reader 退出，通常是 sheet dismiss、reader dismiss、navigation pop 共用了同一个状态源。

维护要求：

- 缩略图、元数据、页码跳转等 sheet 关闭只影响 sheet 自己。
- reader 关闭必须走 reader presentation coordinator 的明确路径。
- `dismiss()`、`onDisappear`、interactive sheet drag 不应直接清空当前 reader request。
- UIKit presenter 中的 SwiftUI sheet 属于独立 hosting tree；需要即时反馈的控件必须在 sheet 内观察状态 owner，不能只传入打开瞬间的值快照。
- 对第二次打开 sheet 做真机回归测试。

## 8. UI hit-testing 和透明层

### 8.1 全屏 overlay window 默认是危险的

只要新建独立 `UIWindow` 并高于主 window，就必须明确 hit-test 策略。SwiftUI 透明区域也可能返回内部 hosting view，导致整屏吞触摸。

维护要求：

- overlay window 使用 passthrough `hitTest`。
- 透明背景不能接收触摸。
- 只允许实际交互元素接收触摸。
- 真机测试时必须在 overlay 存在时操作底层页面。

### 8.2 `Color.clear` 不等于“不参与交互”

`Color.clear` 在 SwiftUI 中仍可能形成可命中的 view，尤其配合 `.background`、`.overlay`、`GeometryReader` 或 preference 时。

维护要求：

- 纯测量层：`.allowsHitTesting(false)`。
- 纯 observer 层：`.allowsHitTesting(false)`。
- 占位 spacer：`.allowsHitTesting(false)` 并 `accessibilityHidden(true)`。
- 真正可点区域才使用 `.contentShape`。

### 8.3 Loading overlay 要有取消入口

远程打开或下载时，如果 UI 显示 downloading/opening，必须能取消。否则网络卡住时用户只能杀 app。

维护要求：

- `ReaderOpeningStateView` 这类 opening/downloading 页面提供 Cancel。
- Cancel 要取消 request token 和底层下载任务。
- 取消后不能把旧 ready/error 回写到新 reader。

## 9. 性能和内存

### 9.1 远程缩略图预热必须有预算

目录里文件夹很多时曾卡死，原因通常是二级目录封面预热读到了大量或异常文件。

维护要求：

- 当前目录漫画封面优先。
- 只有当前目录封面都已有缓存时，才考虑二级目录封面。
- 二级目录预热有总数量上限、单文件超时、连续失败熔断。
- 跳过隐藏目录、PDF、no-Range WebDAV。
- 用户新动作产生时可以重置或切换预热任务。

### 9.2 大量远程 I/O 不应拖慢主线程

导入远程文件夹时 UI 掉帧，常见原因：

- ViewModel 是 `@MainActor`，里面做了过重循环或同步文件操作。
- 进度回调过于频繁导致主线程刷新过多。
- 批量封面生成和下载同时抢 I/O。

维护要求：

- 下载、扫描、文件复制、封面生成放后台。
- MainActor 只做状态发布。
- 进度发布节流，避免每个 chunk 都刷新 UI。
- 批量任务支持取消。

### 9.3 后台内存优化不能破坏 reader session

为了降低被系统杀掉的概率，可以清理可重建图片缓存，但不能清掉正在阅读所需的 document/source/pageSource。

检查：

- 后台恢复后 reader 仍停在原页。
- 缓存漫画仍可翻页。
- 最近阅读 item 能打开。
- 没有自动返回首页或播放退出动画。

### 9.4 封面质量问题通常来自缓存尺寸和显示模式切换

SMB 浏览器中，文件夹封面在 list/grid 切换时曾出现低清、黑边、拉伸不一致。

维护要求：

- list 和 grid 不应共用过小的最终位图。
- 缓存 key 要包含必要的目标尺寸或质量等级。
- 低清占位可以先显示，但高分辨率结果回来后必须替换。
- 封面裁剪策略要统一，避免同一缓存图在不同 aspect ratio 下出现黑边。

## 10. 缓存和存储设置

### 10.1 显示缓存大小要用真实磁盘占用

iOS 设置里看到的 App 占用和 app 自己统计差很多时，通常是只算了逻辑文件大小，没有算 APFS allocated size、临时文件或半成品缓存。

维护要求：

- 缓存管理显示真实占用。
- “Other cache data” 单独显示和删除。
- 删除缓存时显示正在删除状态，避免 UI 看起来卡死。
- 删除文件后同步删数据库记录。

### 10.2 缓存上限只是策略，不是强同步

用户设置 500MB/1G/2G/4G/无限制后，自动裁剪要考虑 active lease 和正在下载文件。

维护要求：

- 默认 1G。
- UI 以 MB 显示。
- 不删除 active reader 文件。
- 自动上限裁剪不删除用户显式保存的离线副本；它们只由明确的下载副本清理操作删除。
- 不把半成品文件算作可正常打开的缓存。

## 11. 漫画格式和封面

运行时扩展名策略由 `SupportedComicFormats` 负责，产品能力列表由 README 负责；本节只记录容易回归的格式行为。

维护注意：

- 图片目录是漫画，不是普通目录。
- 压缩包封面读取要有超时和错误隔离。
- PDF 缩略图使用 CoreGraphics 本地渲染，不依赖 reader 引擎。
- PDF 在远程预热路径要保守。
- EPUB/PDF 通过统一 reader 打开，但不要假设它们和图片序列共享所有 viewport 行为；MuPDF 渲染页也要保留文档语义。
- 同名图片封面优先于压缩包第一页。

## 12. 最小回归检查清单

每次改动远程、导入、阅读器或缓存后，至少跑这些检查。

自动验证以 `docs/development-workflow.md` 的变更类型矩阵和命令为准。本节只补充高风险场景的人工检查，不复制容易过时的构建参数。

本地库：

- 新建 library 后重启 app，library 仍能打开。
- 新建 library 后导入漫画，重启后漫画仍能打开。
- 从 SMB 导入单个 ZIP，library 不显示未初始化，且能看到漫画。
- 从 SMB 导入漫画文件夹，图片目录按单本漫画处理。
- 远程导入期间底层 UI 不冻结，目标库漫画数量实时或准实时更新。
- 删除 library 和删除缓存互不误伤。
- 阅读后返回，最近阅读页码刷新。

远程浏览：

- SMB/WebDAV 浏览器隐藏点开头文件。
- 目录封面不会因为 PDF 或异常二级目录卡死。
- no-Range WebDAV 不预读封面、不流式打开。
- Range WebDAV ZIP 可边读边缓存。
- 缓存删除后不会继续显示已缓存。
- 删除坏缓存记录后再次打开同一远程漫画，会按当前网络策略重新获取。
- 关闭并重开 app 后，远程服务器页、当前目录、显示模式按预期恢复。

阅读器：

- 本地库、最近阅读、远程缓存、SMB 远程、WebDAV 远程都能打开。
- Opening/Downloading 页面有取消按钮。
- 后台停留后返回，reader 不自动退出，不显示漫画不可用。
- 竖屏打开后切横屏，不能露出底层列表或半屏黑屏。
- 首次翻页不出现临时放大。
- 缩略图 sheet 第一次和第二次打开都正常。
- 远程缓存入口和本地库入口打开同一文件时，走同一套 reader pipeline。

Overlay/导航：

- 远程导入进行中，底层 UI 仍能滚动和点击。
- 导入浮层按钮仍能点击。
- 后台恢复后 tab 栏不多出空白项。
- Hero source frame 不存在时不要从左上角错误展开。

## 13. 判断是否应该重构，而不是继续打补丁

出现下面任意情况，应停下来整理职责边界：

- 同一 bug 已经在 3 个以上生命周期回调里补过。
- 修 reader 打开导致缩略图 sheet、导航栈或后台恢复回归。
- 本地和远程各修一遍同样状态。
- 删除缓存、导入、阅读器打开之间互相影响。
- UI 只有在“触发一次刷新/下滑/旋转”后才恢复正常。

这些现象通常说明状态真源分散或异步任务过期结果覆盖当前状态。继续增加 refresh token、delay、`DispatchQueue.main.async` 往往会扩大回归面。

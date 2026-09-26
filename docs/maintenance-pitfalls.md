# JamReader 维护踩坑记录

这份文档保留常见故障的排查入口和回归检查。历史现象不表示当前版本仍有该故障；当前实现以代码和测试为准，代码检查和构建通过不能代替真机复现。

## 1. 总体原则

数据所有权、UIKit 导航/手势边界和统一 reader pipeline 见[项目上下文](project-context.md)。构建、测试和交付要求见[开发流程](development-workflow.md)；本页只补充具体失效方式。

真机问题应结合实际现象排查。iPadOS 后台恢复、旋转、sheet 手势、SMB/WebDAV 网络行为不能仅凭模拟器结果下结论。

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

公开模型使用 `Int64` row ID。虽然这些 ID 在各自表内唯一，调用方仍可能传入另一个 library 的记录 ID；只写 `WHERE id = ?` 无法验证该记录属于当前 library。

维护要求：

- 公开状态写入入口必须从 contextual database URL 解析当前 `libraryID`，并按 `library_id` 校验作用域。
- 标签、阅读列表、成员关系写入前必须验证 comic/tag/readingList 属于同一个 library。
- 私有索引器可用同一 library-scoped snapshot 和事务得到的 row ID 更新或删除；不要把这个例外扩展到公开 API。
- `stable_id` 是内部 UUID，不等于当前 UI 选择集的公开 ID。

检查：

```bash
rg -n "WHERE id = \\?|DELETE FROM [a-z_]+ WHERE id = \\?|UPDATE [a-z_]+.*WHERE id = \\?" JamReader/Data/Libraries
```

命中项需要追踪调用方、SQL 条件和事务；搜索结果本身不能证明隔离正确。

### 2.4 数据库读取失败不能伪装为空库

`LibraryDescriptorStore.load()` 这类入口不能吞掉数据库错误并返回空数组。否则上层可能把“读取失败”理解成“没有库”，进而触发错误初始化、错误覆盖或误导 UI。

正确行为：

- 数据层真实抛错。
- ViewModel 把错误转换成 alert 或错误状态。
- 不要在失败时静默清空库列表。

### 2.5 删除库和删除缓存是两件事

删除 library 会清理库记录、索引、状态和派生资产；`LibraryStorageManager.deleteManagedLibraryFilesIfNeeded` 只删除 app-managed/imported 内容，移除 linked library 不删除外部源目录。删除单本漫画是另一条会修改源文件的流程，由 `LibraryComicRemovalService` 协调隔离、数据库提交和失败回滚。

高风险点：

- 设置页“删除缓存”不能删除用户导入到本地库的漫画。
- 删除下载副本后应清理匹配的缓存元数据并刷新离线副本状态，不应清空阅读历史来代替缓存维护。
- `Imported Comics` 使用独立的 `importedComics` kind，但同样由 app 管理文件，不是远程缓存。
- 缓存统计和裁剪规则见[第 10 节](#10-缓存和存储设置)。

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

### 2.8 本地库回归入口

按改动范围选择 `LibraryScannerDatabaseTests`、`LibraryComicDeletionTransactionTests`、`LibraryComicRemovalServiceTests` 和 `LibraryListViewModelPersistenceTests`。新增或修复持久化、隔离、回滚、删除逻辑时补对应回归测试；人工场景见[第 12 节](#12-最小回归检查清单)。

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

先检查 `JamReader/App/AppRootView.swift` 和 `JamReader/App/AppRootTabBarControllerView.swift` 的浮层命中策略，规则统一见[第 8 节](#8-ui-hit-testing-和透明层)。同时验证底层列表、tab 和浮层取消按钮仍可操作。

### 3.5 导入结果不能只刷新当前页面

导入进度和索引结果需要区分。`ImportedComicsImportService` 在一批文件传输后集中索引；取消时若已有文件落盘，会尝试补偿索引。不要为刷新数量而逐文件重复全库扫描，也不要把文件已复制直接显示为索引成功。

维护要求：

- 索引完成后，Library Home 数量和目标 Library Browser 内容都要更新。
- 最近阅读、继续阅读、特殊集合和组织页的 snapshot 不应卡在旧状态。
- 导入失败或部分失败时，反馈要区分下载失败、复制失败、索引失败。
- 远程导入完成后打开目标库，应优先使用最新 library descriptor 和 scanner 结果。

`ImportedComicsImportServiceIntegrationTests` 覆盖批量索引、取消补偿、目标路径边界和重名处理。

## 4. 远程 SMB/WebDAV

### 4.1 WebDAV Range 是流式读取和封面预读的边界

ZIP/CBZ 不是顺序友好的格式。没有 Range 支持时，为了读取封面或页面，经常必须下载大量甚至完整文件。

当前策略：

- WebDAV 确认支持 Range：允许 ZIP/CBZ 流式打开和支持格式的远程封面读取。
- WebDAV 确认不支持 Range：禁用远程封面读取和流式打开，改为完整下载后打开；仍可使用已有本地缓存生成封面。
- Range 探测失败时，`webDAVRangeRequestsSupported` 当前保留乐观尝试；它不等于已确认支持 Range。流式打开失败会报错，不能假设所有失败都会自动切换为完整下载。
- SMB：可通过随机读/分块读支持更好的远程读取体验，但仍要防止并发缓存任务互相影响。

SMB 流式 reader 的连接可能在长时间熄屏后失效。`ManagedSMBRemoteFileReader` 在传输断开、会话过期或文件句柄失效时合并重连，重新登录、连接共享并打开同一路径，然后重试原字节范围一次；权限、认证、路径错误与主动取消不重连。重连后的文件大小变化会拒绝读取，避免继续套用旧 ZIP 索引。关闭 reader 必须取消重连，并释放迟到的新连接。完整 ZIP 副本已下载时，正式页面优先读取本地数据；这些恢复行为不能重建 document、导航栈或重置页码。

不要为了“显示一个封面”对 no-Range WebDAV 做全量下载。

### 4.2 PDF 封面预取要保守

PDF 封面获取曾导致目录卡死风险，尤其在二级目录预热封面时更危险。

维护要求：

- 远程浏览器不直接提取远端 PDF 封面，目录预览候选和漫画预热均跳过 PDF；已有本地 PDF 副本可按请求策略用 CoreGraphics 生成封面。
- 目录检查和封面预热的预算边界见[9.1](#91-远程缩略图预热必须有预算)。

### 4.3 SMB/WebDAV 浏览器要隐藏点开头文件

远程浏览器应隐藏：

- 点开头文件和目录。
- app 自己或其他漫画应用留下的隐藏目录。
- 不支持的普通文件。

原因：

- 用户目录不应被系统文件污染。
- 二级目录预热如果读到异常文件，容易造成卡顿或失败。

### 4.4 本地与远程封面来源不同

`LibraryComicMetadataExtractor` 在本地目录查找并校验同名图片，优先用作封面；没有有效图片时回退格式自身的提取链路。

远程 `fetchDirectThumbnail` 当前从图片漫画目录的 `coverPath` 或压缩包提取，不查找压缩包旁的同名图片；不能把本地 sidecar 行为写成已实现的远程能力。显示质量问题见[9.4](#94-封面质量问题通常来自缓存尺寸和显示模式切换)。

### 4.5 远程缓存必须有 active lease

阅读器正在使用的缓存文件不能被缓存清理、自动裁剪或手动删除任务删掉。

风险现象：

- 打开漫画后突然“漫画不可用”。
- 连续打开多个漫画后全部不可用。
- 后台回来后最近阅读里的缓存漫画打不开，重启 app 又恢复。

维护要求：

- 打开 reader 时注册 active cache lease。
- reader 销毁或切换漫画时释放 lease。
- 自动裁剪跳过 active lease 文件；单条删除和同作用域批量清理会拒绝操作，要求先关闭 reader。
- 缓存记录损坏或文件缺失时要清理记录，并给出可重试错误。

### 4.6 旧缓存会伪装成当前网络问题

WebDAV/SMB 曾出现“ZIP 打不开”，后来确认是旧缓存损坏或旧路径记录导致。排查远程打开失败时，不要只看网络协议。

优先检查：

- 缓存记录指向的文件是否存在。
- 文件大小、mtime、remote signature 是否和记录一致。
- 缓存文件是否是半成品下载。
- 打开失败后是否清理了坏记录并按当前远程策略重试。
- 用户手动删除缓存后，缓存元数据和离线副本状态是否同步清理。

### 4.7 远程浏览状态是用户体验状态，不是业务真相

远程服务器页面、当前目录、侧边栏收缩状态、列表/grid 显示模式需要记住，但这些状态不能影响文件打开、导入或缓存判断。

维护要求：

- 浏览状态可存在 UserDefaults。
- 远程服务器配置和凭据仍按现有 JSON/UserDefaults/Keychain 体系处理。
- 不要把远程浏览状态混入 AppLibraryV2.sqlite 的本地漫画库表。
- 切换服务器、删除服务器、凭据失效时，要清理或忽略对应浏览状态。

## 5. 统一阅读器 Pipeline

### 5.1 不要再拆本地 reader 和远程 reader

当前所有入口生成统一 `ComicOpenRequest`，再由 `ComicOpenCoordinator` 打开成 `ComicReaderSession` 和 `ComicDocument`；架构入口见[项目上下文](project-context.md#reader)。

维护要求：

- 本地库、最近阅读、远程缓存、远程流式、完整下载后打开都走同一个 `ComicReaderView`。
- 远程进度可以继续写 JSON，但只能通过统一 state store adapter 访问。
- 不要新增远程专用 reader shell 来单独维护 page/layout/bookmark/progress。

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

当前缩略图 sheet 通过 `ReaderThumbnailBrowserUIKitContainer` 使用 UIKit collection view，维护时保留列表复用和预取机制。

维护要求：

- `ReaderThumbnailBrowserMetrics` 使用双列或 iPad/宽容器三列，按容器宽度调整列宽和间距；宽布局另外支持左右分区。
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

### 6.6 垂直连续阅读不能复用下拉关闭

垂直列表和下滑关闭共用纵轴时，普通翻阅会被误判为退出。

维护要求：

- 分页阅读保持下滑关闭；垂直连续阅读使用单指右滑关闭。
- 关闭手势必须先通过严格方向判断，不能在滚动已经发生后再决定是否接管。
- 已缩放内容或沿关闭方向仍可平移的滚动视图优先，底部横向缩略图不能触发右滑关闭。
- 关闭交互激活后临时锁住当前 reader scroller，取消或结束时立即恢复。

### 6.7 垂直连续阅读的宽度和缩放必须由同一布局维护

垂直页面在 1 倍时使用完整 reader viewport 宽度，不叠加横向安全区或 iPad 固定宽度上限。缩放应统一放大 collection 布局并保留触点锚点，不要给复用 cell 嵌套独立滚动视图；缩放后由 collection 自身处理双轴平移并阻止右滑关闭，viewport 尺寸变化时回到 1 倍并重新锚定当前页。

页面间距由共享 `ReaderDisplayLayout.pageSpacingEnabled` 持久化，默认开启，且只在垂直连续或双页布局下显示设置入口；隐藏入口不能清空保存值。关闭时仅把相邻漫画页之间的线距设为 0，不能改变页宽、外层 viewport 或手势 owner。

缩略图只能在正式页面加载期间充当占位；cell 已显示正式图后，即使缓存被回收，也不能被预览通知降级。预取取消后的 cell 进入可见区时必须补回正式图加载，内存警告只取消不可见页任务；已取消任务的迟到结果不能清理替代请求或更新页面。`VerticalReaderPageLoadingTests` 覆盖这些加载和复用边界。

### 6.8 垂直阅读的快速导航使用右侧缩略图轨道

垂直连续模式隐藏底部横向缩略图列表，只保留紧凑页码入口；右侧轨道按整本漫画进度为每一页保留位置，以单个绘制层组成连续缩略图带。普通缩略图宽度使用固定档位：iPad 为 6/10/16/24 pt，iPhone 为 4/8/12/18 pt，选择能容纳当前页数的最宽档。普通项按 2:3 宽高比和约 1 pt 间距紧密排列，轨道高度随内容收紧，上限为当前 reader viewport 高度的 2/3，并受安全区和工具栏留白约束；最细档仍放不下时压缩 item 高度和间距，保留每页位置。手指所在的原 item 直接放大并向左突出，前后两页按距离逐级形变，焦点宽度上限分别为 38/30 pt。

放大区根据同一组 item 形变后的实际高度计算间距，把焦点上方的列表整体上推、下方列表整体下推；轨道首尾留白必须覆盖完整放大位移，长漫画也不能裁切或层叠邻页。整条轨道使用淡黑色半透明背景，侧栏缩略图按最大放大 item 的尺寸和显示缩放率准备（常规 iPad @2x 最长边 112 px），viewport 改变时同步调整目标分辨率。整条轨道只绘制这种小图，中央预览加载完成后也先缩小再补入轨道。浮动页码固定右边缘与焦点缩略图的间距，按总页数预留数字宽度；只对当前页使用短数字过渡，总页数弱化显示，“减少动态效果”开启时停用数字滚动和缩放。

拖动期间在 viewport 中央显示当前焦点页的大图预览，宽度以 viewport 的 1/2 为上限，高度随图片实际比例变化；超过安全区内可用高度时整体等比缩小，背景和边框贴合图片，不留上下黑边。预览不接收触摸；显示时同步读取共享预览缓存及缩略图 pipeline 的目标尺寸缓存，选择对应页已有的最高分辨率预览，任一缓存被淘汰时仍应复用另一份清晰图，不得先降级成轨道小图。缓存不足时，停留后复用焦点加载任务补足显示分辨率，不能显示上一页的迟到图片。松手关闭预览并提交一次跳页；取消则关闭预览并保留原页。

缩略图带优先复用分辨率足够的 reader 预览缓存；缓存过小时通过 `ComicPageDataSource.localDataForPage` 从本地漫画或已有远程页缓存补齐，无法本地补齐才保留小图。不得放大像素来冒充清晰图，迟到的小图也不能替换已准备好的清晰缩略图。该入口不得下载远程页面或把整本解压数据写入正式页缓存；流式 ZIP 若已完成后台下载，可直接读取其本地文件，翻页时会检查本地副本变化并刷新。扫描、解压与 ImageIO 解码在后台逐页执行，UIKit 异步缩略图准备从 MainActor 发起，每批最多 12 张小图合并回 UI；关闭或更换文档时取消，迟到结果不得混入新轨道。焦点预览经过短延迟后才允许加载；未拖动时只准备小图，拖动时按中央预览的尺寸与屏幕缩放率准备，不能因快速扫过轨道而连续触发远端读取、解压或图片解码。

轨道手势由 UIKit 管理。交互期间必须阻止右滑关闭，取消时回到原页；chrome 隐藏或 reader 锁定后轨道不得继续接收触摸。轨道尺寸和位置使用当前 viewport 与窗口 safe area，不能依赖 `UIScreen.main.bounds`。

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

目录探测与封面预热是两条链路，不应混为“等当前目录封面全部缓存后再检查子目录”。

维护要求：

- `RemoteServerBrowsingService.listDirectory` 在列目录时检查子目录，识别图片漫画和有限的预览候选；保留检查超时与连续失败停止检查的机制。
- `RemoteServerBrowserView` 按可见范围预热当前目录漫画：主范围允许远程提取，次范围只用缓存，PDF 不参与预热。
- 文件夹卡片的预览请求使用 `allowsRemoteFetch: false`，不能为填满卡片额外下载漫画。no-Range 规则见[4.1](#41-webdav-range-是流式读取和封面预读的边界)。
- 保留并发和范围限制；滚动、切目录、切显示模式或打开 reader 时取消或重新规划任务。

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

`AppMemoryPressureCoordinator` 清理可重建图片缓存，reader 资源生命周期规则统一见[5.3](#53-后台恢复不能释放-reader-资源)。恢复后应保留页码、翻页能力和当前导航状态。

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
- 删除后刷新缓存元数据、离线副本状态和占用统计。

### 10.2 缓存上限只是策略，不是强同步

`RemoteCachePolicyStore` 的预设同时限制漫画数量和总字节数；自动裁剪还要考虑 active lease、显式离线副本和正在下载文件，因此占用可能暂时超过策略上限。

维护要求：

- 默认 1G。
- UI 以 MB 显示。
- 不删除 active reader 文件。
- 自动上限裁剪不删除用户显式保存的离线副本；它们只由明确的下载副本清理操作删除。
- 离线保护记录无法读取或尚未完成恢复时，停止自动裁剪，不能把失败当成“没有需要保护的副本”。
- 不把半成品文件算作可正常打开的缓存。

## 11. 漫画格式和封面

运行时扩展名策略由 `SupportedComicFormats` 负责，产品能力列表由 README 负责；本节只记录容易回归的格式行为。

维护注意：

- 压缩包封面读取要有超时和错误隔离。
- PDF/EPUB 的引擎选择见[开发流程](development-workflow.md#build-and-static-checks)。MuPDF 成功打开后使用 image-sequence reader；EPUB 的网页 fallback 有自己的阅读位置和页面交互，不能假设二者共享全部 viewport 行为。
- 图片目录识别见 3.3；PDF 预热和同名封面来源见 4.2–4.4。

## 12. 最小回归检查清单

按改动边界选择相关场景；不要把未执行的人工检查描述成已通过。

自动验证以[开发流程](development-workflow.md#validation-by-change-type)的变更类型矩阵和命令为准。本节只补充高风险场景的人工检查。

本地库：

- 新建 library 后重启 app，library 仍能打开。
- 新建 library 后导入漫画，重启后漫画仍能打开。
- 从 SMB 导入单个 ZIP，library 不显示未初始化，且能看到漫画。
- 从 SMB 导入漫画文件夹，图片目录按单本漫画处理。
- 远程导入期间底层 UI 不冻结；索引完成后目标库数量和内容更新。
- 删除 library 和删除缓存互不误伤。
- 删除漫画后，标签和阅读列表计数同步下降；移除 library 后清理对应记录和派生资产，linked 源目录仍保留。
- 跨库传入 comic/tag/reading-list ID 时拒绝写入；数据库不可读时显示错误，不伪装为空库。
- 阅读后返回，最近阅读页码刷新。

远程浏览：

- SMB/WebDAV 浏览器隐藏点开头文件。
- 目录封面不会因为 PDF 或异常二级目录卡死。
- no-Range WebDAV 不做远程封面读取、不流式打开；已有本地封面仍可显示。
- Range WebDAV ZIP 可流式打开，完整副本后台下载遵循用户设置。
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

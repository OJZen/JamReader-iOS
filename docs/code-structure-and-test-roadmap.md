# JamReader 代码结构与测试建设评估

更新时间：2026-07-06

本文面向最后开发阶段的维护和回归防护。结论先行：当前项目已经具备较完整的产品功能，但核心业务仍集中在少数超大文件中；在继续拆分前，应先补 XCTest target 和核心业务测试，避免重构过程中误伤远程导入、缓存、书库索引和阅读器状态。

## 当前快照

- Swift 文件约 297 个，总量约 7.2 万行。
- Xcode project 目前只有 `JamReader` 一个 app target，没有 XCTest / UI test target。
- 体量最大的运行时代码集中在：
  - `JamReader/Data/Remote/RemoteServerBrowsingService.swift`：远程校验、目录浏览、SMB/WebDAV 细节、下载、缓存、封面、递归扫描、range 能力、active lease、缓存裁剪混在一起。
  - `JamReader/Features/Browser/LibraryBrowserView.swift`：书库内容、搜索、选择、多种展示、批量操作、sheet/presenter 桥接、导入入口集中在一个 view。
  - `JamReader/Features/Remote/RemoteServerBrowserView.swift` 和 `RemoteServerBrowserViewModel.swift`：远程浏览 UI、UIKit section 构建、缩略图预热、导入、离线、最近记录和错误恢复耦合较多。
  - `JamReader/Data/Libraries/NativeLibraryState.swift`、`NativeLibraryIndexing.swift`、`ImportedComicsImportService.swift`：数据库读写、扫描索引、导入复制和恢复逻辑都属于高风险业务链路。
  - `JamReader/SharedUI/Components/ImageSequenceReaderContainerView.swift`、`ReaderChromeOverlay.swift`：阅读器 UIKit 容器、缩放/翻页/预热、顶部底部控制、缩略图 scrubber 体量仍偏大。
- 现有脚本和文档已经有维护意识：
  - `scripts/check_no_swiftui_gestures.sh` 已经能防止重新引入 SwiftUI 手势。
  - `docs/maintenance-pitfalls.md` 已经记录了多项真实踩坑，后续测试应优先覆盖这里列出的事故类型。

## 拆分原则

1. 先补测试 target，再拆业务文件。没有测试时直接拆 `RemoteServerBrowsingService` / `NativeLibraryState` / reader 容器，回归风险过高。
2. 保留 facade，逐步内部分流。外部调用点先继续使用现有服务名，内部拆成小服务，降低一次性改动范围。
3. View 只保留状态表达和轻量编排。排序、section 构建、导入计划、缓存策略、路径归一化、文件类型判断都应移到可单测类型。
4. UIKit 继续负责高频交互。阅读器页面、远程大列表、缩略图列表和手势不要回到 SwiftUI gesture。
5. 数据库写入保持 library 作用域。任何拆分都不能弱化 `library_id`、外键、缓存记录和文件生命周期的一致性。

## 建议拆分路线

### P0：测试基础设施

先新增 `JamReaderTests` target，使用 XCTest，不必先引入 UI test target。测试目标需要能 `@testable import JamReader`，并提供临时目录、临时 UserDefaults、可替换 FileManager/URLSession/fake remote reader 等测试工具。

建议新增：

- `JamReaderTests/Support/TestTempDirectory.swift`
- `JamReaderTests/Support/TestFixtures.swift`
- `JamReaderTests/Support/FakeRemoteRandomAccessFileReader.swift`
- `JamReaderTests/Support/URLProtocolStub.swift`
- `JamReaderTests/Support/SQLiteTestHarness.swift`

CI 最小命令：

```bash
xcodebuild -project JamReader.xcodeproj -scheme JamReader -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project JamReader.xcodeproj -scheme JamReader -destination 'platform=iOS Simulator,name=iPhone 17' test
./scripts/check_no_swiftui_gestures.sh
```

如果本机没有固定 simulator，可以先用 `generic/platform=iOS Simulator` 做 build，把 test 放到开发机/CI 的可用模拟器矩阵里。

### P1：远程浏览和缓存拆分

`RemoteServerBrowsingService` 应保留为外部 facade，但内部拆成以下边界：

- `RemoteServerProfileValidator`：只负责 SMB/WebDAV profile 校验。
- `RemotePathResolver`：统一 `normalizeDisplayPath`、SMB relative path、WebDAV URL/path join、cache scope key。
- `RemoteDirectoryListingService`：只负责 list directory，并通过 provider adapter 分发。
- `RemoteDirectoryInspectionService`：负责识别图片目录漫画、目录 preview items、cover entry。
- `RemoteComicReferenceFactory`：负责 `RemoteDirectoryItem -> RemoteComicFileReference`，降低导入/缓存/阅读链路 ID 混乱风险。
- `RemoteThumbnailService`：负责 range 缩略图、同名图片封面、PDF/EPUB 保守策略、并发限制。
- `RemoteDownloadService`：负责单个和批量下载、断点续传、进度聚合、取消。
- `RemoteCacheStore`：负责 cache path、metadata、availability、summary、clear。
- `RemoteCacheEvictionService`：负责 policy 裁剪和 active lease 保护。
- `RemoteProviderClient` protocol：将 SMB/WebDAV 真实网络实现隔离，测试用 fake provider 覆盖目录、文件大小、range 失败、权限失败等情况。

这部分优先测试 cache key 和 path，因为之前已经出现过跨服务器/跨目录数据混乱问题。

### P1：书库、导入、索引拆分

`NativeLibraryState.swift` 建议拆成 repository 组合：

- `LibraryFolderRepository`
- `LibraryComicRepository`
- `LibraryOrganizationRepository`
- `LibraryReadingStateRepository`
- `LibrarySpecialCollectionRepository`
- `LibrarySearchRepository`

每个 repository 的写入必须显式携带 `libraryID`，不要只传裸 `comicID` / `folderID`。

`NativeLibraryIndexing.swift` 建议拆成：

- `LibraryDiscoveryService`：递归发现目录、文件、图片目录漫画。
- `ComicFileHasher`：稳定文件 hash 与快速 hash 策略。
- `LibraryIndexSyncService`：把 discovery 结果同步进 SQLite。
- `CoverExtractionService`：本地压缩包/PDF/EPUB/图片目录封面。
- `FolderCoverComposer`：文件夹合成封面绘制。

`ImportedComicsImportService.swift` 建议拆成：

- `ImportDestinationResolver`：目标库创建、选择、权限、root 恢复。
- `ImportSourceEnumerator`：单文件、目录递归、图片目录漫画识别。
- `ImportFileTransferService`：复制/移动/重名处理/临时 staging。
- `ImportIndexCoordinator`：导入后扫描、恢复、刷新通知。
- `ImportResultMessageBuilder`：用户反馈文本生成。

这些拆分可以先不改 UI，对外仍提供 `importComicResourcesAsync`。

### P1：阅读器内核和 UI 边界

阅读器问题已经多次证明属于高风险区域。建议保持当前已验证手势架构，不做行为重写，只整理文件边界：

- `ComicOpenPipeline.swift`：继续作为打开漫画 facade，但拆出 `ComicOpenSessionFactory`、`ComicReadableSourceResolver`、`ComicReaderStateStore` 已有部分可继续独立。
- `ImageSequenceReaderContainerView.swift`：拆出 `ReaderPagedCollectionViewController`、`ReaderPageHostCell`、`ReaderPagePrefetchController`、`ReaderKeyboardCommandInstaller`。
- `ZoomableImagePageView.swift`：保留 UIKit 缩放核心，补测试和小范围 review，不要把缩放状态迁回 SwiftUI。
- `ReaderChromeOverlay.swift`：拆成 `ReaderTopChromeView`、`ReaderBottomChromeView`、`ReaderScrubberView`、`ReaderScrubberCoordinator`，scrubber 的数学计算单独测试。

### P2：Feature View 瘦身

`LibraryBrowserView.swift` 当前包含页面状态、toolbar、内容分支、list/grid item、sheet bridge、selection、UserDefaults 持久化。建议拆成：

- `LibraryBrowserScreen`
- `LibraryBrowserToolbar`
- `LibraryBrowserContentSection`
- `LibraryComicListSection`
- `LibraryComicGridSection`
- `LibraryBrowserSelectionController`
- `LibraryBrowserPresentationRouter`
- `LibraryBrowserPreferencesStore`

`RemoteServerBrowserView.swift` 建议把纯逻辑先抽出去：

- `RemoteBrowserDisplaySnapshotBuilder`
- `RemoteBrowserSectionBuilder`
- `RemoteThumbnailPreheatPlanner`
- `RemoteBrowserPresentationRouter`
- `RemoteBrowserToolbar`

`AppDependencies` 目前是全量依赖容器。可以保留顶层 `AppDependencies`，但增加 feature 级视图：

- `LibraryFeatureDependencies`
- `RemoteFeatureDependencies`
- `ReaderFeatureDependencies`
- `SettingsFeatureDependencies`

这样 view 初始化参数会更短，测试也能只构造当前功能所需依赖。

## 优先补充的测试

### P0：纯逻辑单元测试

这些测试最便宜，收益最高：

- `ComicPageNameSorterTests`
  - 自然排序：`1.jpg, 2.jpg, 10.jpg`
  - 忽略 `__MACOSX`
  - 支持 `webp/gif/png/jpg`
  - 大量页面时不触发昂贵二次分组
- `ReaderDisplayLayoutTests`
  - iPhone 禁用双页时自动归一为单页
  - webcomic 默认纵向滚动和 fit width
  - RTL 双页展示顺序
  - cover as single page 的 spread 生成
- `RemoteServerProfileTests`
  - SMB/WebDAV URL 拼接
  - base directory 归一化
  - default port 处理
  - `remoteCacheScopeKey` 能区分 provider/host/port/share/WebDAV path
- `RemoteDirectoryItemIdentityTests`
  - 不同 server、provider、share、cache scope、path 生成不同 id
  - 图片目录漫画和普通文件的 reference kind 正确
- `ComicDocumentLoaderFormatTests`
  - 目录作为图片漫画打开
  - ZIP/CBZ 走 zip reader
  - RAR/7Z/CBR 走 libarchive
  - PDF/EPUB 策略正确
  - MOBI 当前产品口径是暂不支持，运行时代码也应有对应测试约束

### P1：数据库和文件系统集成测试

- `AppLibraryDatabaseTests`
  - 初始化 schema 成功
  - 每次连接都开启 foreign key
  - 删除 library/comic 后关联表级联清理
  - 读取失败不能伪装为空库
- `LibraryIndexingServiceTests`
  - 本地 ZIP/PDF/EPUB 被索引
  - 图片占多数的目录被识别为单本漫画
  - 点开头文件、隐藏目录、`__MACOSX` 被忽略
  - 删除源文件后数据库记录和封面资产被清理
  - 同名/移动文件时 hash 复用符合预期
- `ImportedComicsImportServiceTests`
  - 单文件导入
  - 目录导入
  - 图片目录漫画导入
  - 重名冲突生成稳定目标名
  - 导入失败不留下错误 library descriptor
  - 远程 staging 文件导入完成后被清理
- `LibraryComicRemovalServiceTests`
  - 删除单本漫画会清理文件、数据库、封面、组织关系
  - app-managed library 和 linked folder 的删除语义不同

### P1：远程缓存和远程读取测试

- `RemoteCacheStoreTests`
  - 同名文件来自不同 SMB/WebDAV 服务器不会共用缓存路径
  - 同服务器不同 share/base path 不会互相污染
  - `clearCachedComics` 同时清理缓存文件、metadata、阅读记录
  - active reader lease 保护正在阅读的文件
  - partial download metadata 不兼容时不会错误续传
- `RemoteZIPArchiveReaderTests`
  - 使用 fake range reader 只读取 ZIP central directory 和目标图片
  - corrupt EOCD、ZIP64、不完整 range 返回明确错误
  - reader 不允许越界 read
  - 无图片条目时返回可解释错误
- `RemoteWebDAVClientTests`
  - PROPFIND 解析目录、文件大小、修改时间
  - Range 支持探测缓存
  - no-Range WebDAV 不触发远程封面全量下载
- `SMBConnectionPoolTests`
  - 连接复用
  - idle eviction
  - cancellation 后释放 in-use 状态

### P2：ViewModel 和关键 UI 行为测试

先测 ViewModel，不急着做大量 UI test：

- `RemoteServerBrowserViewModelTests`
  - load 成功/失败/离线恢复
  - import visible/current folder/directory/comic 的调用顺序
  - save offline/remove offline 的状态刷新
  - feedback auto-dismiss 不影响真实状态
- `LibraryBrowserViewModelTests`
  - 搜索 token 防旧结果覆盖新结果
  - refresh folder/library 的分支
  - selection 在 visible IDs 改变时收敛
  - 删除漫画后列表和 special collection 更新
- `ComicReaderViewModelTests`
  - load token 防旧 document 覆盖新 document
  - progress/bookmark/favorite/rating/read 状态保存
  - remote streaming/downloaded/offline 三种打开路径
  - previous/next comic 导航
  - scene phase 下进度保存

UI test 只保留少量端到端 smoke：

- 启动 app，底部 tab 可切换。
- 添加远程服务器表单可打开/关闭。
- 打开一本本地测试漫画并能翻页。
- 设置页清缓存后不误删本地导入漫画。

## 静态检查建议

在现有 `check_no_swiftui_gestures.sh` 基础上新增：

- `check_no_legacy_yacreader_terms.sh`：防止旧兼容词回流到运行时代码。
- `check_supported_formats_consistency.sh`：对齐 `ComicDocumentLoader`、导入支持列表、远程支持列表、README。
- `check_database_write_scope.sh`：粗扫 `WHERE id = ?`、`DELETE FROM ... WHERE id = ?`，提示人工确认 `library_id` 作用域。
- `check_no_large_view_growth.sh`：列出超过 800 行的 SwiftUI view 文件，作为 review 提醒。

## 里程碑

### M1：测试 target 和第一批纯逻辑测试

目标：不改业务行为，新增测试工程和 20-30 个纯逻辑测试。

验收：

- `xcodebuild test` 可运行。
- `ComicPageNameSorter`、`ReaderDisplayLayout`、`RemoteServerProfile`、`RemoteDirectoryItem` 有覆盖。
- 支持格式一致性有测试或脚本约束。

### M2：远程缓存/导入测试安全网

目标：覆盖最容易造成用户数据混乱的路径。

验收：

- 不同 SMB/WebDAV server 的缓存路径隔离有测试。
- 清空 SMB/WebDAV 缓存同时清历史记录有测试。
- active lease 保护有测试。
- 远程导入 staging 到本地 library 的路径有测试。

### M3：拆 `RemoteServerBrowsingService`

目标：保留现有 public API，内部拆出 path/cache/download/thumbnail/listing 服务。

验收：

- 外部调用点基本不变。
- 原有远程浏览、导入、离线、在线封面逻辑通过现有测试。
- 真机至少回归 SMB 和 WebDAV 各一条路径。

### M4：拆书库导入和索引

目标：把数据库读写、扫描发现、封面生成、导入复制拆成可测试模块。

验收：

- 图片目录漫画、本地导入、目录导入、删除漫画都有测试。
- 扫描结果和 UI 计数一致。
- `docs/maintenance-pitfalls.md` 中数据库/导入相关事故均有测试或检查脚本覆盖。

### M5：拆超大 View 和阅读器 UI 文件

目标：在业务测试已有保护后，再瘦身 `LibraryBrowserView`、`RemoteServerBrowserView`、`ReaderChromeOverlay`、`ImageSequenceReaderContainerView`。

验收：

- 大文件数量明显下降。
- 阅读器手势仍全部在 UIKit 原生手势层。
- `check_no_swiftui_gestures.sh` 通过。
- 本地测试漫画翻页、缩放、跳页、退出重进不回归。

## 已处理的产品/代码口径不一致

2026-07-06 已按“暂不支持 MOBI”的产品口径移除运行时 MOBI 支持入口，并建议用测试和静态检查防止回流。历史风险点包括：

- `ComicDocumentLoader` 会尝试 MuPDF 或 Quick Look 打开 MOBI。
- `RemoteServerBrowsingService`、`NativeLibraryIndexing`、`ImportedComicsImportService`、`LibraryBrowserViewModel` 的支持格式列表仍包含 `mobi`。
- `EBookDocumentSupport` 和 `MuPDFDocumentRenderer` 也仍把 MOBI 列为支持扩展。

后续如果要重新支持 MOBI，必须先有完全可控的 reader 方案，再恢复导入、索引、远程浏览和文档说明。

## 执行优先级

短期不要先做大规模 View 重构。更合理的顺序是：

1. 新增 XCTest target。
2. 补纯逻辑测试和格式一致性检查。
3. 补远程缓存/导入/索引测试。
4. 保留 facade 拆远程服务和导入索引服务。
5. 最后拆大 View 和阅读器 UI 文件。

这样能把“代码更好看”和“未来不再误伤业务”绑定在一起，而不是只做表面整理。

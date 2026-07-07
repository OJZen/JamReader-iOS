# JamReader 日志策略

更新时间：2026-07-07

目标：日志用于追踪 App 动作和复盘问题，不用于记录用户内容全文。日志应覆盖关键业务入口、成功/失败结果、缓存和持久化边界，同时避免在滚动、缩略图预热、分块读取等高频路径中产生噪声。

## 统一入口

运行时代码统一使用 `AppLog` 中的 category：

- `AppLog.library`：书库加载、刷新、删除、组织关系等。
- `AppLog.libraryImport`：本地/远程导入、目标库解析、复制移动、索引恢复。
- `AppLog.libraryIndexing`：扫描、hash、数据库同步、封面索引。
- `AppLog.remote`：SMB/WebDAV 浏览、在线打开、下载、批量离线。
- `AppLog.remoteCache`：离线缓存、辅助缓存、cache policy、active reader lease。
- `AppLog.reader`：打开 reader、远程/本地 session、保存进度、页面保存。
- `AppLog.persistence`：UserDefaults、SQLite、文件持久化失败边界。
- `AppLog.ui`：只记录影响业务状态的 UI 协调，不记录普通点击和滚动。

## 输出规则

- 使用 `AppLogSanitizer.path` 打印本地路径或远程路径，只保留末尾关键组件。
- 使用 `AppLogSanitizer.url` 打印 URL，自动去掉 username、password、query、fragment。
- 使用 `AppLogSanitizer.namesPreview` 打印文件列表，默认最多 8 个条目。
- 使用 `AppLogSanitizer.errorDescription` 打印错误，默认最多 500 个字符。
- 不打印密码、token、authorization header、完整用户目录、完整书名列表、图片数据、XML/HTML/PDF/EPUB 内容。

## 推荐日志级别

- `notice`：用户可感知的重要动作，例如清缓存、应用缓存策略。
- `info`：普通业务动作，例如远程目录加载完成、单本下载完成。
- `warning`：可恢复但需要关注，例如索引恢复、active lease 阻止清理、零漫画扫描结果。
- `error`：失败且需要用户提示或开发排查，例如数据库同步失败、远程连接失败、下载失败。

## 需要继续补的区域

- 暂无已知必须补充的高价值日志入口；后续以实际问题复盘和测试缺口为准继续收敛。

## 当前已覆盖的高价值区域

- App lifecycle/cache pressure：已记录内存警告、后台切换触发的内存缓存清理。
- Library list ViewModel：已记录书库加载、新增文件夹、创建托管书库、重命名等低频动作。
- Library organization：已记录标签、书单、集合成员关系、单本/批量组织分配、收藏/阅读状态、评分、元数据保存和 ComicInfo 导入。
- Library comic removal：已记录单本/批量漫画从本地书库移除、只读拒绝和删除失败原因。
- Library import/indexing：已记录导入、复制移动、索引恢复、扫描同步、导入书库清空、ComicInfo 批量导入等结果摘要。
- Library metadata batch editing：已记录批量元数据保存的选中数量、字段数量和失败原因。
- Reader ViewModel：已记录 reader 打开、取消、超时、保存页面和进度保存失败。
- Reader open pipeline：已记录本地文件、本地书库、远程缓存、远程流式、远程下载 fallback 和失败原因。
- Reader support services：已记录页面磁盘缓存异常、磁盘缓存 trim 摘要、EPUB 准备/解包/复用/失败。
- Remote browsing service：已记录远程目录加载、单本下载、批量下载、缓存策略和缓存清理。
- Remote WebDAV range probing：已记录 byte-range 探测结果和每个服务器作用域首次探测失败的 fallback。
- Remote SMB connection pool：已记录连接创建/复用/失败/驱逐/空闲清理，端点仅输出脱敏哈希 ID。
- Remote background import：已记录后台导入开始、拒绝、完成、取消和反馈展示。
- Remote cache settings：已记录设置页发起的缓存策略变更、下载/辅助缓存/缩略图/导入书库清理。
- Remote server list ViewModel：已记录服务器加载、保存、删除、缓存清理和浏览历史删除。
- Remote browser ViewModel：已记录目录加载、收藏文件夹、远程导入、离线保存和删除离线副本。
- Remote/browser reader preferences：已记录远程浏览显示/排序偏好、阅读器布局偏好保存，以及异常 rawValue 忽略。
- Remote offline shelf：已记录离线书架加载、刷新离线副本、删除单本离线副本、清空服务器离线副本。
- Saved remote folders：已记录收藏远程文件夹列表加载、重命名和删除。
- Persistence stores：已记录 JSON 文件 store、UserDefaults Codable helper、Keychain、维护状态记录的失败边界。

## 后续建议补测试的区域

- Library comic removal：需要覆盖只读书库拒绝、去重删除、漫画文件缺失但数据库删除继续执行、封面删除失败不阻断主流程。
- Library organization：需要覆盖标签/书单增删改、重复名称拦截、集合成员批量移除、批量收藏/阅读状态变更。
- Metadata editor：需要覆盖 ComicInfo `fillMissing` 和 `overwriteExisting` 两种导入策略，以及保存失败时不更新原始快照。
- Remote cache/import：需要覆盖不同服务器同名路径隔离、清缓存同时清历史、在线封面读取失败 fallback。

## 不建议补日志的区域

- 每一页图片解码、缩放、滚动、预热和 cell 复用。
- SMB/WebDAV 分块读取每个 chunk。
- 缩略图列表中每个 item 的成功加载。
- SwiftUI body、UIKit layout pass、频繁触发的 progress 回调。

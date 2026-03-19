# 阅读器与手势系统重构计划

更新时间：2026-03-19

## 1. 背景判断

当前图片分页阅读器已经暴露出结构性问题，而不是单点 bug：

- 首次进入阅读器时，页面会先居中，再在数百毫秒后自动顶到顶部
- 同一问题会出现在“打开上次阅读页”“从列表 push 进入阅读器”“返回后重新进入”等场景
- 历次补丁已经覆盖 `viewWillAppear / viewDidAppear / viewDidLayoutSubviews / SwiftUI update / viewport refresh token / jump overlay / chrome overlay` 等多个层次，问题依旧存在
- 这说明当前运行时状态、viewport、导航转场、缩放容器、页码同步之间的职责分配本身就不稳定

结论：

- 现有分页阅读器不适合继续在原架构上增量修补
- 阅读器运行时内核与手势协调层需要整体重构
- 重构优先级高于继续补充阅读器新功能

## 2. 当前架构的核心问题

### 2.1 运行时状态分散

当前阅读器状态横跨多个层级：

- SwiftUI 外层：
  - [ComicReaderView.swift](/Volumes/Ju/Projects/ios/yacreader/yacreader/Features/Reader/ComicReaderView.swift)
  - [RemoteComicReaderView.swift](/Volumes/Ju/Projects/ios/yacreader/yacreader/Features/Remote/RemoteComicReaderView.swift)
- 运行时 ViewModel：
  - [ComicReaderViewModel.swift](/Volumes/Ju/Projects/ios/yacreader/yacreader/Features/Reader/ComicReaderViewModel.swift)
- UIKit 容器：
  - [ImageSequenceReaderContainerView.swift](/Volumes/Ju/Projects/ios/yacreader/yacreader/SharedUI/Components/ImageSequenceReaderContainerView.swift)
  - [VerticalImageSequenceReaderContainerView.swift](/Volumes/Ju/Projects/ios/yacreader/yacreader/SharedUI/Components/VerticalImageSequenceReaderContainerView.swift)
  - [PDFReaderContainerView.swift](/Volumes/Ju/Projects/ios/yacreader/yacreader/SharedUI/Components/PDFReaderContainerView.swift)

这导致：

- 页码状态和实际显示状态不是单一真源
- SwiftUI 生命周期和 UIKit 转场生命周期交错
- 一处“为了稳定显示做的修复”会影响另一处“为了同步状态做的修复”

### 2.2 分页实现选型不稳

当前分页图片阅读器建立在：

- `UIPageViewController`
- 页内 `UIScrollView`
- 每页手工布局、手工缩放、手工居中

问题在于：

- `UIPageViewController` 的 child appearance / transition completion 时机不够可控
- 页内 `UIScrollView` 在导航 push/pop、safe area 变化、内容缩放回弹时会额外触发布局回路
- 当前实现多次尝试自己维护 `contentOffset / contentInset / frame / zoomScale`，实际已经进入“谁最后写入谁生效”的不稳定状态

### 2.3 手势协调缺少统一调度中心

虽然已经遵守“手势只走 UIKit”，但目前协调仍然分散：

- 单击区域判断在页内
- 翻页行为一部分在分页容器，一部分在外层阅读器
- chrome 显隐、跳页、缩略图、外接键盘、上下册导航，都在不同层级触发

结果是：

- 手势语义没有单一入口
- 缩放态、非缩放态、分页态、纵向连续态的行为不统一
- 一旦增加新交互，很容易再次把运行时链路缠在一起

### 2.4 本地阅读与远程阅读重复实现

当前本地和远程阅读器都拥有各自一套外层壳：

- [ComicReaderView.swift](/Volumes/Ju/Projects/ios/yacreader/yacreader/Features/Reader/ComicReaderView.swift)
- [RemoteComicReaderView.swift](/Volumes/Ju/Projects/ios/yacreader/yacreader/Features/Remote/RemoteComicReaderView.swift)

它们共享了部分底层容器，但运行时控制仍有重复：

- 初始页恢复
- jump overlay
- chrome 显隐
- viewport refresh
- 进度持久化触发点

这会放大任何一次阅读器修复的工作量和回归面。

## 3. 重构目标

### 3.1 必达目标

- 分页图片阅读器首次进入、重新进入、翻页、旋转后都稳定适屏
- 缩放、双击缩放、拖拽、左右翻页的优先级稳定
- 所有手势协调仍然全部留在 UIKit
- 本地阅读和远程阅读共用同一套阅读器内核
- 外层 SwiftUI 仅负责导航、sheet、业务入口，不再直接干预阅读 viewport

### 3.2 架构目标

- 阅读运行时采用“单一真源”
- 手势采用统一调度器
- viewport 不再依赖多层刷新 token + 生命周期补丁
- paged / vertical / PDF 三种阅读模式共享统一宿主和统一命令接口

### 3.3 产品目标

- 保持移动端优先，不再尝试复刻桌面交互
- iPhone：
  - 单页分页
  - 双击缩放
  - 左右边缘翻页
  - 中间点按显示 chrome
- iPadOS：
  - 保留双页能力
  - 支持键盘翻页
  - regular width 下更强调高效浏览

## 4. 新架构方案

## 4.1 总体分层

重构后分成 4 层：

### A. Reader Shell

职责：

- SwiftUI 导航入口
- 业务 sheet / alert 入口
- 与库浏览器、远程浏览器衔接

文件：

- 精简 [ComicReaderView.swift](/Volumes/Ju/Projects/ios/yacreader/yacreader/Features/Reader/ComicReaderView.swift)
- 精简 [RemoteComicReaderView.swift](/Volumes/Ju/Projects/ios/yacreader/yacreader/Features/Remote/RemoteComicReaderView.swift)

约束：

- 不持有 viewport 细节
- 不直接操控页内缩放或刷新 token
- 不承载任何手势逻辑

### B. Reader Runtime / Session

新增模块，建议目录：

- `yacreader/ReaderKernel/*`

核心对象建议：

- `ReaderSessionController`
- `ReaderSessionState`
- `ReaderCommand`
- `ReaderCapability`
- `ReaderContentDescriptor`
- `ReaderNavigationCoordinator`

职责：

- 当前文档、当前页、当前模式、当前 layout 的单一真源
- 处理翻页、跳页、上下册切换、书签跳转、缩略图定位等命令
- 给 chrome、内容容器、外层壳提供统一状态接口

### C. Reader Host UIKit 宿主

建议新增：

- `ReaderHostViewController`
- `ReaderChromeViewController`
- `ReaderGestureCoordinator`

职责：

- 真正承载阅读内容
- 管理 chrome overlay
- 统一接收 tap / double tap / pan / keyboard 命令
- 把运行时命令分发给具体内容控制器

### D. Content Controllers

三类内容控制器统一协议：

- `ImagePagedContentController`
- `ImageContinuousContentController`
- `PDFContentController`

协议建议：

- `ReaderContentControlling`
- `func apply(command: ReaderCommand)`
- `func prepareInitialViewport()`
- `func restoreViewport(for pageIndex: Int)`
- `var visiblePageIndex: Int { get }`
- `var supportsZooming: Bool { get }`

## 4.2 分页图片阅读器重做方案

这是当前 blocker，优先级最高。

### 交互基线：参考相册类 App，而不是桌面阅读器

后续分页阅读器和手势系统，明确采用“相册 / 图片浏览器”作为交互基线。

原因：

- 漫画分页阅读和相册单张浏览在交互结构上高度相似
- 用户对 iOS 相册类交互已经非常熟悉，学习成本最低
- 相册类交互天然更适合触屏，而不是鼠标/桌面热区逻辑

明确借鉴的交互词汇：

- 单击中间区域显示 / 隐藏 chrome
- 双击按点击位置放大，再双击回 fit
- pinch 连续缩放
- 未放大时左右滑动翻页
- 已放大时优先拖动当前图像
- 放大后允许自然回弹，不做额外桌面式操作热区

明确不照搬的相册交互：

- 默认纵向下滑关闭
  - 对漫画阅读来说，这会和纵向连续阅读、页内拖动产生冲突
- 编辑态手势
- 长按上下文菜单优先级高于阅读手势

产品结论：

- 阅读器手势将以“iOS 相册用户会自然预期的方式”作为默认行为
- 桌面阅读器残留的鼠标逻辑、边角兼容逻辑、人工 viewport 干预逻辑，应从新实现中尽量剔除

### 选型决策

放弃当前 `UIPageViewController + 每页手工 viewport 修复` 路线，改为：

- 横向 `UICollectionView`
- `isPagingEnabled = true`
- 每个 cell 内一个标准 `ZoomableImageScrollView`

原因：

- cell 生命周期比 `UIPageViewController` 更稳定、可观察
- 更容易做预取和邻页缓存
- 可明确拿到当前 visible cell，而不是依赖 page VC 的 transition 回调
- 更适合后续统一本地与远程阅读链路

### 单页视图标准实现

每个分页 cell 只做一件事：

- 承载一个 `UIScrollView`
- `scrollView` 内只放一个 `contentView`
- `contentView` 内放图像层 `UIImageView` 或 `CATiledLayer` host

缩放与居中原则：

- 使用标准 `viewForZooming(in:)`
- `minimumZoomScale` 由 viewport 和图片尺寸计算
- 只在两个时机重置到 fit：
  - 第一次页面显示
  - 用户显式恢复默认缩放
- 居中只通过更新 `contentView.frame.origin` 实现
- 不再使用额外的 viewport refresh token 去驱动页内补丁

### 分页与缩放手势优先级

统一规则：

- 未放大：
  - 左右拖拽优先交给横向分页 collection view
  - 中间单击切换 chrome
  - 左右边缘单击翻页
- 已放大：
  - 拖拽优先交给页内 scroll view
  - 只有当页内横向已到边界且仍继续拖拽时，才允许触发跨页
- 双击：
  - 从 fit 缩放到预设 zoom
  - 再双击回 fit

实现方式：

- 自定义 `ReaderGestureCoordinator`
- 用 `UIGestureRecognizerDelegate` 明确设置：
  - `shouldRecognizeSimultaneouslyWith`
  - `shouldRequireFailureOf`
  - `gestureRecognizerShouldBegin`

## 4.3 纵向连续阅读重构方向

当前纵向连续阅读比分页稳定，但仍应迁入统一内核。

策略：

- 保留 `UICollectionView` 技术路线
- 把页码同步、命令处理、chrome 显隐迁到统一 `ReaderSessionController`
- 纵向模式只保留“内容控制器”职责

重点优化：

- 当前页判定算法统一
- 缩放手势与纵向滚动手势协调统一
- iPad 居中阅读列继续保留

## 4.4 PDF 阅读器重构方向

PDF 不必完全重做渲染，但要接入统一宿主。

策略：

- 保留 PDFKit / 现有 PDF 内容容器
- 适配统一命令接口和统一 chrome 接口
- 统一边缘点按、键盘翻页、缩略图入口、跳页入口

## 4.5 Chrome 与业务入口重构

chrome 需要和内容分离。

建议：

- `ReaderChromeViewController` 作为 child VC 悬浮在 `ReaderHostViewController` 上
- chrome 不参与内容布局，不改变阅读内容 frame
- jump、thumbnails、bookmarks、layout sheet 都通过 host 统一调起

这样可以彻底避免：

- chrome 显隐导致内容跳动
- overlay 与内容视图互相触发布局链

## 4.6 本地与远程统一

目标不是两个阅读器分别修，而是：

- 本地与远程共用同一套 `ReaderHostViewController`
- 差异只留在：
  - 文档来源
  - 进度持久化后端
  - 远程刷新动作

建议抽象：

- `ReaderProgressStore`
- `ReaderDocumentProvider`
- `ReaderLibraryContext`

本地与远程分别注入不同实现。

## 5. 目录与文件改造建议

### 5.1 新增目录

建议新增：

- `yacreader/ReaderKernel/`

建议文件：

- `ReaderHostViewController.swift`
- `ReaderSessionController.swift`
- `ReaderSessionState.swift`
- `ReaderCommand.swift`
- `ReaderGestureCoordinator.swift`
- `ReaderChromeViewController.swift`
- `ReaderContentControlling.swift`
- `ImagePagedContentController.swift`
- `ImageContinuousContentController.swift`
- `PDFContentController.swift`
- `ZoomableImagePageView.swift`
- `ReaderViewportState.swift`
- `ReaderPagePrefetchController.swift`

### 5.2 现有文件处理策略

保留并逐步收缩：

- [ComicReaderView.swift](/Volumes/Ju/Projects/ios/yacreader/yacreader/Features/Reader/ComicReaderView.swift)
- [RemoteComicReaderView.swift](/Volumes/Ju/Projects/ios/yacreader/yacreader/Features/Remote/RemoteComicReaderView.swift)
- [ComicReaderViewModel.swift](/Volumes/Ju/Projects/ios/yacreader/yacreader/Features/Reader/ComicReaderViewModel.swift)

逐步替换：

- [ImageSequenceReaderContainerView.swift](/Volumes/Ju/Projects/ios/yacreader/yacreader/SharedUI/Components/ImageSequenceReaderContainerView.swift)
- [VerticalImageSequenceReaderContainerView.swift](/Volumes/Ju/Projects/ios/yacreader/yacreader/SharedUI/Components/VerticalImageSequenceReaderContainerView.swift)
- [PDFReaderContainerView.swift](/Volumes/Ju/Projects/ios/yacreader/yacreader/SharedUI/Components/PDFReaderContainerView.swift)
- [ReaderChromeOverlay.swift](/Volumes/Ju/Projects/ios/yacreader/yacreader/SharedUI/Components/ReaderChromeOverlay.swift)
- [ReaderPageJumpOverlay.swift](/Volumes/Ju/Projects/ios/yacreader/yacreader/SharedUI/Components/ReaderPageJumpOverlay.swift)

保留数据层：

- [ComicDocumentLoader.swift](/Volumes/Ju/Projects/ios/yacreader/yacreader/Data/Reader/ComicDocumentLoader.swift)
- [ReaderPageCache.swift](/Volumes/Ju/Projects/ios/yacreader/yacreader/Data/Reader/ReaderPageCache.swift)
- [ReaderLayoutPreferencesStore.swift](/Volumes/Ju/Projects/ios/yacreader/yacreader/Data/Reader/ReaderLayoutPreferencesStore.swift)

## 6. 分阶段执行计划

## Phase 0：冻结旧分页阅读器扩散修复

目标：

- 旧分页阅读器只接受阻断级 crash 修复
- 停止继续向旧架构叠加新功能

任务：

- 记录当前已知问题列表
- 标记旧分页容器为“待替换”
- 新功能优先接入未来的新宿主接口，不再直接接旧分页容器

完成标准：

- 阅读器问题单不再继续朝旧分页容器打补丁扩散

## Phase 1：抽出统一 Reader Runtime

目标：

- 建立单一真源

当前状态：

- 已开始实现，基础文件已落地：`ReaderSessionState`、`ReaderCommand`、`ReaderContentDescriptor`、`ReaderSessionController`
- 已把本地 / 远程阅读壳的 `currentPage / chrome / pageJump / layout` 运行期状态接到 `ReaderSessionController` 过渡层
- 已补上 `ReaderSessionSupport` 与 `ReaderPersistenceSupport`，开始把页码显示、跳页解析、阅读进度快照、书签归一化等共享语义从本地 / 远程阅读壳抽离
- 本地 / 远程阅读壳已经开始把 `visiblePage / chrome / pageJump text` 等高频交互写入切到 `ReaderCommand` 入口，减少继续直连 session 可变状态的地方
- 已开始把本地 / 远程阅读器控制面板往共享 section 收敛，并让远程阅读切到与本地一致的 gear-sheet 控制工作流
- 当前仍未把所有业务写回与导航命令完全迁入 runtime；这一阶段已完成“外层状态先并轨”，并开始继续收拢持久化和阅读命令

任务：

- 定义 `ReaderSessionState`
- 定义 `ReaderCommand`
- 定义 `ReaderContentControlling`
- 把当前页、页数、layout、书签、chrome 状态、跳页状态统一进 runtime

完成标准：

- 外层 SwiftUI 不再直接驱动 viewport
- 本地与远程都能用同一套 runtime 接口

## Phase 2：实现新的 ZoomableImagePageView

目标：

- 先把单页缩放和居中做稳

当前状态：

- 已开始实现，`ZoomableImagePageView` 已落地，并已替换旧 `ComicImageSpreadViewController` 里直接管理 `UIScrollView` 的实现
- 已同步移除本地 / 远程阅读器外层那条 `120ms / 520ms` 的历史 viewport 校准脉冲，避免新容器再次被补丁式二次刷新干扰

任务：

- 新建标准 `UIScrollView + contentView + imageView`
- 完成 fit page / width / height / original size
- 完成 double tap zoom
- 完成 zoom 后内容拖拽
- 完成 rotation 后重新 fit

必须通过的手测：

- 第一次打开任意页不跳
- 打开上次阅读页不跳
- push 进入后不跳
- pop 再进不跳
- 旋转设备后不跳
- 双击放大和缩小稳定

## Phase 3：实现新的 ImagePagedContentController

目标：

- 用 `UICollectionView` 重建分页

当前状态：

- 已完成主链路切换：[ImageSequenceReaderContainerView.swift](/Volumes/Ju/Projects/ios/yacreader/yacreader/SharedUI/Components/ImageSequenceReaderContainerView.swift) 现已由横向 `UICollectionView` 分页宿主承载 `ComicImageSpreadViewController`
- 旧 `UIPageViewController` 分页路线已退出主链路，并开始删除遗留代码
- 当前分页阅读器已通过“首次进入、再次进入、连续翻页、跳页弹窗后恢复”等核心手测

任务：

- 横向分页 collection view
- cell 复用
- 当前 visible page 判定
- 邻页预取
- 邻页缓存回收
- 触觉反馈

必须通过的手测：

- 连续快速翻页不跳
- 翻页回来仍适屏
- 已放大页拖动不误翻页
- 未放大页左右拖动能稳定翻页

## Phase 4：接入统一手势协调器

目标：

- 所有手势语义统一

任务：

- 单击热区
- 双击缩放
- pan 优先级
- edge tap 翻页
- keyboard commands
- iPad 外接键盘翻页

完成标准：

- paged / vertical / PDF 都使用统一命令分发
- 手势冲突规则集中定义，不散落在各内容容器里

## Phase 5：接入 Chrome、Jump、Thumbnails、Bookmarks

目标：

- 让新内核具备完整可用性

当前状态：

- 已把本地 / 远程阅读器外层整理为共享 `ReaderSurface`
- 已抽出共享 `ReaderTopBar`、`ReaderTopStatusStack`、`ReaderStatusBadge`
- `ReaderPageJumpOverlay` 继续作为统一跳页入口，避免再回到 sheet 驱动的布局干扰

任务：

- chrome overlay child VC
- jump to page
- thumbnails
- bookmarks
- layout sheet
- favorite/read/rating/metadata 入口

完成标准：

- 新阅读器可完整替代当前用户主链路

## Phase 6：本地阅读切换到新内核

目标：

- 优先稳定本地主链路

当前状态：

- 已完成“本地图像分页阅读接新分页宿主 + 共享外层 chrome 壳”的第一版落地
- 当前剩余工作主要集中在把页码、书签、布局偏好进一步往 `ReaderSessionController` 归拢

任务：

- `ComicReaderView` 接新 host
- 进度写回
- 书签写回
- 上下册导航
- 阅读布局偏好同步

完成标准：

- 本地图片分页阅读默认走新内核

## Phase 7：远程阅读切换到新内核

目标：

- 清理本地与远程重复实现

当前状态：

- 已完成远程阅读对新分页宿主的接线
- 远程阅读外层 UI 已与本地阅读并轨到同一套 `ReaderSurface`
- 远程阅读进度 / 书签持久化已经开始复用共享 `ReaderPersistenceSupport`
- 远程阅读已开始接入与本地一致的控制面板 section，并补上旋转控制与底部 gear-sheet 工作流
- 当前仍保留远程特有的刷新、缓存回退提示与部分存储后端逻辑，后续继续往 runtime 统一接口收敛

任务：

- `RemoteComicReaderView` 接新 host
- 远程进度 store 适配
- 远程刷新入口
- 缓存回退提示入口

完成标准：

- 远程阅读共享同一套阅读 runtime

## Phase 8：纵向与 PDF 接统一宿主

目标：

- 阅读器完成真正意义上的统一架构

任务：

- vertical content controller 适配
- PDF content controller 适配
- 统一 chrome
- 统一命令系统

完成标准：

- paged / vertical / PDF 三条链路都由同一 reader host 托管

## Phase 9：删除旧实现与收尾

目标：

- 清理历史补丁

任务：

- 移除旧 `ImageSequenceReaderContainerView` 逻辑
- 清理外层 refresh token 和过渡性修复
- 整理文档
- 补 UI tests / regression checklist

完成标准：

- 阅读器没有“双系统并存”的维护负担

## 7. 里程碑

### M1：单页缩放内核稳定

交付：

- 新 `ZoomableImagePageView`

判定：

- 首次进入 / 再次进入 / 翻页回来 / 旋转后都不跳

### M2：本地分页阅读切新内核

交付：

- 本地图像分页阅读从旧容器切换到新容器

判定：

- 常用阅读主链路稳定

### M3：手势统一

交付：

- `ReaderGestureCoordinator`

判定：

- 翻页、双击缩放、chrome 显隐、缩放态拖拽全部稳定

### M4：远程阅读并轨

交付：

- 本地与远程统一阅读宿主

判定：

- 远程链路不再维护一套平行阅读控制逻辑

### M5：三模式统一

交付：

- paged / vertical / PDF 全部接统一宿主

判定：

- 阅读器进入可持续扩展阶段

## 8. 测试与验收矩阵

必须手测的关键场景：

- 从资料库打开漫画
- 从特殊列表打开漫画
- 从标签 / 阅读列表打开漫画
- 打开上次阅读页
- 打开第一页 / 中间页 / 最后一页
- push 进入后立即显示
- pop 返回后再次进入
- 翻页 20 次以上
- 已放大后拖动
- 已放大后翻页回到默认 fit
- 切换 paged / vertical
- 旋转设备
- 切后台再回来
- 内存警告后继续阅读
- 本地漫画
- 远程漫画
- iPhone
- iPadOS regular width
- 外接键盘翻页

建议补的自动化：

- 单页缩放几何单元测试
- runtime command 单元测试
- 阅读器 smoke UI test
- 关键手势冲突 UI test

## 9. 性能要求

- 首次打开首屏时间不因重构明显回退
- 连续翻页期间不出现主线程解码卡顿
- 邻页预取必须可取消
- 内存告警必须能回收非当前页缓存
- 远程阅读不能因统一内核而把缓存层写死成本地假设

## 10. 产品取舍

重构期间明确取舍：

保留：

- 单页分页
- 纵向连续阅读
- iPad 双页
- 缩略图跳页
- 页码跳转
- 书签
- 收藏 / 已读 / 评分 / 元数据入口
- 本地与远程阅读

降级或延后：

- 桌面式复杂滤镜链
- 非核心的阅读实验模式
- 任何会再次把阅读 runtime 搞复杂的“为兼容桌面而兼容桌面”的交互

明确不做：

- 放大镜
- iPhone 双页常驻
- SwiftUI 手势实现

## 11. 风险与控制

主要风险：

- 重构跨度大，短期会形成新旧实现并存
- 本地和远程统一时，状态持久化接口需要重新抽象
- paged / vertical / PDF 三模式统一后，宿主层职责容易膨胀

控制措施：

- 先解决 paged image blocker，再逐步吞并 vertical 和 PDF
- 用协议把数据源和进度后端隔离
- 每一阶段都要求能独立跑通主链路
- 每阶段结束都做一次回归清单

## 12. 执行顺序建议

建议从现在开始，严格按下面顺序推进：

1. 冻结旧分页容器，只做阻断级修复
2. 先做 `ReaderSessionController`
3. 再做 `ZoomableImagePageView`
4. 再做 `UICollectionView` 分页容器
5. 再接统一手势协调器
6. 先切本地阅读
7. 再切远程阅读
8. 最后统一 vertical 与 PDF

## 13. 当前结论

当前阅读器最大问题已经不再是“某个偏移算错了”，而是：

- 运行时状态源过多
- 宿主层次过多
- viewport 与业务状态耦合
- 手势缺少集中协调

因此，后续阅读器工作应从“继续修旧容器”切换为“建立新内核并逐步替换旧容器”。

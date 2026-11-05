# 阅读器

## 原样保留（不在设计范围）

- **分页阅读底部缩略图导航列表**：`ReaderBottomBar`（`ReaderThumbnailScrubber`、条目放大与抬升、浮动页面预览、下方页码胶囊）。
- **竖向连续阅读右侧缩略图导航列表**：`ReaderVerticalThumbnailRail`（轨道、拖动预览、松手跳页、紧凑页码入口）。

位置、尺寸、间距、缩略图样式、动效、显隐、触控、跳页行为全部保留。它们仍引用部分 `Spacing`、`AppFont`；共享值必须保持不变，需要改共享 token 时先隔离为组件私有常量。周边工具的出现与动画不得移动或挤压它们。静态示意数值见 [ProtectedNavigation](components/ProtectedNavigation/README.md)。

## 工具布局

| 部分 | 当前界面 | 组件规则 |
| --- | --- | --- |
| 顶栏 | 返回 · 书名 · [书签 · Aa · ⋯]；不显示页码 | [ReaderTopBar](components/ReaderTopBar/README.md) |
| 显示设置 | 紧凑宽度为底部系统 sheet，常规宽度为 popover；只列出生效控件 | [ReaderDisplayPanel](components/ReaderDisplayPanel/README.md) |
| 更多 | 页面操作与这本漫画的管理动作；本地不含删除，远程只有信息 | [ReaderMoreMenu](components/ReaderMoreMenu/README.md) |
| 页码与跳页 | 分页底部页码胶囊、竖向紧凑页码入口打开 `ReaderPageJumpOverlay` | 受保护组件 |
| 准备阅读 / 打不开 | 与转场共用封面落点；加载反馈和恢复动作按状态显示 | [ScreenRemoteActions](components/ScreenRemoteActions/README.md) |

跨本导航胶囊未被页面使用，原因见 [实现取舍](05-batches.md#阅读器)。

## 行为契约（任何方案都不能改）

分页、竖向、退出、缩放、工具显隐、轨道松手跳页、取消、进度与书签等完整契约由 [设计需求第 5 节](../design-requirements.md#5-漫画阅读器保护范围与可改部分) 负责。布局调整不得改变这些行为或数据边界。显示面板与格式能力按下表处理。

## 显示面板的控件可见性

| 控件 | 分页 · 窄 | 分页 · 宽 | 竖向 | PDF / EPUB 渲染页 |
| --- | --- | --- | --- | --- |
| 阅读模式 | ● | ● | ● | — |
| 单页 / 双页 | — | ● | — | — |
| 双页排列 | — | 双页时 ● | — | — |
| 首页单独 | — | 双页时 ● | — | — |
| 适应方式 | ● | ● | — | — |
| 页间距 | — | 双页时 ● | ● | — |
| 旋转（仅本次） | ● | ● | — | ● |

PDF / EPUB 渲染页使用固定单页布局，但支持旋转；EPUB 网页模式不提供这组图像布局控件。实现由 `ReaderDisplayPanelControls` 与文档能力共同决定。

## iPhone Duo

窗口宽度决定单双页可用性与面板形式；受保护导航的档位另按 [环境适配规则](06-iphone-duo.md#受保护导航列表--只做环境适配) 判断。窄窗口单页显示不改写双页偏好。折痕与摄像头几何的实际缺口见 [尚未接入的环境适配](05-batches.md#尚未接入的环境适配)，不能把静态稿当作已实现。

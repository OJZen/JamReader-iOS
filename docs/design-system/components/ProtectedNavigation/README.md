# ProtectedNavigation

**受保护组件。** 分页阅读底部缩略图导航列表（`ReaderBottomBar` + `ReaderThumbnailScrubber`，含其页码胶囊与浮动预览）和竖向阅读右侧缩略图导航列表（`ReaderVerticalThumbnailRail`）原样沿用。

## 约束

- 位置、尺寸、间距、缩略图样式、圆角（13 / ≤8）、放大与抬升动效、显隐、触控、跳页行为全部不改。
- 本卡片仅按代码数值示意（compact：缩略图 40×58、条目 46×76、帧高 100；轨道容器 136pt、交互宽 68pt），不是新设计。
- 共享 token 不得间接改变它们；当前引用与隔离规则见 [阅读器保护范围](../../03-reader.md#原样保留不在设计范围)。
- 周边工具的出现与动画不得挤压或移动它们。
- 拖动预览、松手跳页、取消与隐藏后的触控契约见 [阅读器需求](../../../design-requirements.md#5-漫画阅读器保护范围与可改部分)。

## iPhone Duo：只做环境适配

档位按 [环境适配规则](../../06-iphone-duo.md#受保护导航列表--只做环境适配) 判断，数值和交互不变。半折容器限制尚未接入，不能把 [ScreenDuoReader](../ScreenDuoReader/README.md) 的示意当作现有能力；缺口见 [实现边界](../../05-batches.md#尚未接入的环境适配)。

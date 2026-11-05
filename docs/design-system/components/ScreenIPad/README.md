# ScreenIPad

iPad 书库：UIKit split view，侧栏常驻“来源 + 集合”，内容区网格按容器宽度自适应（稿中 6 列仅为示意）。

- 三个分区用系统标签栏切换：iPadOS 18 起为顶部浮动标签栏（图示），iPadOS 17.6 为底部标签栏；不自绘。
- 侧栏与内容同屏时按一屏检查重复入口：集合入口在侧栏出现时，内容区不放 2×2 集合卡；继续阅读的位置由 [ContinueReading](../ContinueReading/README.md) 的设置决定，选择“各书库内”时仍在书库根目录显示。
- 添加书库只在侧栏“我的书库”标题旁的 +；内容区工具栏为“选择” · ⋯，与 iPhone 一致。
- 窄窗口（Slide Over / 1/3 分屏）自然收拢为 iPhone 布局。
- App 注册的分区快捷键见 [Sidebar](../Sidebar/README.md)。静态稿中的 ⌘F、⌘N、空格打开、⌘⌫ 删除没有对应的书库快捷键实现。
- iPhone Duo 内屏（常规宽度）使用同一布局；判断依据是窗口宽度，不是设备类型。见 `ScreenDuoLibrary`。

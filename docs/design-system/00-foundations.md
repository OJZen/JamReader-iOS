# 视觉与文案基础

JamReader 是 iPhone / iPad 上的个人漫画阅读与管理工具：本地书库与远程（SMB / WebDAV）阅读并重。界面要**原生、安静、内容优先**——封面和漫画本身是主角，界面退到后面。用系统导航、系统控件、系统字体和语义色作为地基，只在少数地方用果酱色告诉用户“这里能点”“读到这儿了”。果酱色呼应 JamReader 的名字：深红偏紫，像一罐树莓果酱；蜂蜜金（`favorite`）是它唯一的暖色搭档。

本文件是视觉与文案基础。目录说明、预览查看方式与文档分工见同目录 [README](README.md)。

> **受保护：** 分页阅读底部缩略图导航列表、竖向阅读右侧缩略图导航列表原样保留，不受本系统任何 token 或组件改动影响。见 `components/ProtectedNavigation` 与 [03-reader.md](03-reader.md)。

## 内容与文案

- 以简体中文为设计语言，同时保证英文、繁体中文（台湾）、日文三种翻译不溢出：按钮和标签预留约 40% 的伸缩空间，书名一律可截断。
- 语气平实、直接，不用感叹号、不用 emoji、不卖萌。用“你”指用户，不用“您”。
- 先说结果，再说原因：“无法访问‘Comics’文件夹。授权已失效，书库内容和阅读进度都还在。”
- 数字用阿拉伯数字，中文与数字之间加空格：“312 本 · 24 个文件夹”“第 78 / 186 页”。分隔符用“ · ”。
- 只写帮助下一步决策的字。普通页面不放说明段落；空状态、错误、权限、破坏性操作才解释。后果说明写在确认弹窗里，不在页面上逐条写脚注；不写“左滑可以……”这类操作教学。

### 固定用词

| 概念 | 用这个词 | 不要用 |
| --- | --- | --- |
| 本地收藏空间 | 书库 | 资料库、库 |
| 用户新建、文件在 App 内 | App 内书库 | 托管书库 |
| 直接使用“文件”里的文件夹 | 关联文件夹 / 使用已有文件夹 | 链接、挂载 |
| 默认导入书库 | 已导入漫画 | 导入目录 |
| 远程漫画存到本机 | 离线副本、保存离线副本 | 下载（单独使用时含义不清） |
| 远程漫画复制进本地书库 | 导入到书库 | 下载、保存 |
| 在线阅读的临时文件 | 阅读缓存 / 临时数据 | 离线 |
| 远程文件夹快捷入口 | 已保存文件夹 | 收藏夹、书签 |
| 最近加入书库 | 最近加入 | 最近、最近阅读 |
| 添加到标签或阅读列表 | 标签与列表 | 整理、归类 |
| 会删除文件 | 删除 | 移除 |
| 只去掉 App 内记录或快捷方式 | 移除 | 删除 |
| 可重建的数据 | 清理 | 删除 |

## 视觉基础

### 颜色

- 页面底色：普通列表与封面网格用 `bg`；设置、表单、服务器详情等分组页用 `bg-grouped`，单元格用 `surface`，嵌套块用 `surface-2`。这些等于 UIKit 语义色，直接用系统色实现。
- 文字：标题与正文 `ink`；副标题、数量、时间 `ink-2`；占位与禁用 `ink-3`。`ink-2` 是 Apple 原值，浅色下在白底约 3.4:1，所以关键信息不要只用 `ink-2` 写在 13pt 以下。
- 果酱色分两种用法：
  - `jam` 用于**填充与标记**：实心主按钮底、选中勾、阅读进度条、存储条“书库漫画”、品牌色块。上面的文字图标一律 `on-jam`（白）。浅色 #9B1E56，深色调为树莓果酱 #C23A76。
  - `accent`（= AccentColor 资源）用于**可点的文字与图标**：工具栏按钮、链接、选中态文字、标签栏选中项。浅色与 `jam` 同值；深色提亮为果酱粉 #E886B2，否则在黑底上读不清。
  - 因为深色下 `accent` 很亮，实心按钮不能继承 AccentColor（白字会看不清），一律显式 `.tint(.appJam)`。
- `jam-deep`（#5C1233，罐底色）只用于品牌色块：封面、App 图标底、启动画面，不用于控件。
- 阅读器不随外观变化，强调色固定用 `reader-accent`（亮果酱粉），用于已加书签与准备阅读的进度。
- 开关保持系统绿，不染果酱色，与 iOS 一致。
- 选中的筛选标签和轻提示用 `accent-soft` 底 + `accent-on-soft` 字。
- 状态色只有五种语义：`success`（已读、完成）、`offline`（已离线）、`warning`（较旧副本、只读）、`danger`（失败、删除）、`favorite`（星标）。每种都有 `-soft` 底色。状态永远是“图标 + 文字”，不能只靠颜色。
- `accent` 与 `danger` 同属红色系（色相差 20–30°，深色下明度接近）：破坏性动作必须同时有 trash / 警告图标和“删除”字样，`accent` 与 `jam` 永远不用于破坏性动作；系统菜单与弹窗中的 destructive 交给系统红。
- 标签颜色 `label-*` 是与 YACReader 数据库兼容的 12 色原值，只画 10pt 圆点，旁边一定有标签名。
- 阅读器不跟随系统外观：画布 `reader-bg` 纯黑，工具用 `reader-chrome` 材质 + `reader-ink` / `reader-ink-2`，描边 `reader-stroke`。

### 字体

- 只用系统字体（SF Pro / 苹方），所有文字走 Dynamic Type 文本样式，不写死字号。token 中的字号是默认 Large 档的数值，仅供设计稿对照。
- 页面大标题 `largeTitle`；分区标题 `title2`；Sheet 标题 `headline`；列表主行 `body`；副行 `subheadline` 或 `footnote`；封面下书名 13pt medium 两行、状态 `caption1`。
- 页码、百分比、文件大小一律等宽数字（`.monospacedDigit()`）。
- 不使用自定义字体文件；系统字体无需打包，所以 `type.fonts` 为空。

### 间距与布局

- 间距只用 `space-*`（2 / 4 / 8 / 12 / 16 / 20 / 24 / 32 / 48，与 `Spacing` 一致）。页面左右边距用系统的容器边距（UIKit 布局边距 / SwiftUI `contentMargins(for: .container)`；iPhone 约 16–20，iPad 更大，iPhone Duo 靠侧边控件一侧约为 0），不写死；只有拿不到系统边距时才回退到 `space-md`（iPhone）/ `space-lg`（iPad）。分区之间 `space-xl`。
- 封面网格：iPhone 默认 3 列（`size-grid-min-compact`），列距 `space-sm`、行距 `space-lg`；iPad 在 `size-grid-min`–`size-grid-max` 之间自适应。列表模式行高至少 `size-row`。
- 点击区域至少 `size-touch`（44pt）。行尾“更多”按钮也是 44×44。
- 宽度判断用容器宽度与 size class，不用设备型号。iPad 用侧栏（`size-sidebar`）+ 内容区，内容最大宽 `size-content-max`；窄窗口自然收拢成 iPhone 布局。

### 形状、材质与阴影

- 圆角：封面 `radius-cover`（6，比现有 10 更利落）；搜索框、侧栏选中行 `radius-md`；分组列表、卡片 `radius-lg`；Sheet 与浮动面板 `radius-xl`；胶囊 `radius-full`。全部用 `.continuous` 曲线。
- 不画描边卡片、不画彩色左边框；层级靠间距与 `surface` 底色区分。
- iOS 26 起，导航栏按钮、标签栏、工具条交给系统 Liquid Glass；iOS 17.6–18 回退为系统材质（`glass`、`glass-stroke` 只用于这一回退态的示意，不要自绘玻璃）。
- 阴影：封面 `shadow-cover`（深色模式可省略）；浮层 `shadow-lg`；其余靠材质不加阴影。

### 动效

- 动画解释状态变化，不做装饰。沿用 `AppAnimation`：工具显隐 `chromeToggle`（spring 0.35 / 0.82）、Sheet `sheetPresent`、浮层 `overlayPop`、轻切换 `quickFade`（0.15s）。
- 打开和关闭漫画共用一个 hero 过渡：打开时封面飞到页面在阅读器里的位置，关闭时当前页飞回封面并在途中渐变成封面。全程只有一份漫画在动，原封面在飞行时隐藏；阅读器的黑底只淡入淡出，不跟着移动。下滑 / 右滑退出时页面跟手，松手后从手指位置继续飞回。封面已不在屏幕上或已换到别的漫画时，页面原地缩小淡出。
- 开启“减弱动态效果”时：hero 过渡改为交叉淡入，列表插入删除不做位移动画。
- 大范围布局变化、高频进度更新不加动画。

### 状态

- 远程副本统一五态：未下载 / 下载中 / 已离线 / 较旧副本 / 失败（`StatusBadge`）。阅读缓存不显示徽标。
- 一张封面的角标位只放一个最重要的状态（优先级见 `ComicCover`）；已读 / 未读只写在副标题里，不画圆点。
- 加载保留上下文（来源、封面）；空状态给一个下一步；错误保留真实原因和恢复动作（`Notice`）；破坏性操作写清删除什么、保留什么（`ConfirmDialog`）。
- 长任务只有一个入口：`TaskBanner`。不新增任务中心。
- 存储占用条用 `chart-*` 中性色，不借用状态色。

## 图标

- 使用 SF Symbols，线性为默认，选中/强调用 `.fill` 版本，跟随文字字重与 Dynamic Type。
- 预览卡片里的图标是为网页示意手绘的线性替身，**不是**最终资源；实现时按下表使用 SF Symbols。

| 用途 | SF Symbol |
| --- | --- |
| 书库标签 | `books.vertical` / `.fill` |
| 远程标签 | `server.rack` |
| 设置标签 | `gearshape` / `.fill` |
| 添加 | `plus` |
| 更多 | `ellipsis`（行尾、工具栏） |
| App 内书库 / 关联文件夹 / 已导入 | `books.vertical` / `folder.badge.link`（iOS 17 可用 `folder`）/ `tray` |
| 导入到这里 / 导入到书库 | `square.and.arrow.down` |
| 保存离线副本 / 已离线 | `arrow.down.circle` / `arrow.down.circle.fill` |
| 较旧副本 | `clock.badge.exclamationmark` |
| 失败 | `exclamationmark.triangle` |
| 收藏 / 评分 | `star` / `star.fill` |
| 已读 | `checkmark.circle` |
| 标签 / 阅读列表 | `tag` / `list.bullet` |
| 最近加入 | `sparkles` |
| 已保存文件夹 / 保存此文件夹 | `pin` / `pin.fill`（不用 `star`，星形只表示收藏漫画） |
| 书签 | `bookmark` / `bookmark.fill` |
| 显示设置 | `textformat.size` |
| 缩略图总览 | `square.grid.3x3` |
| 存到相册 | `photo` |
| 删除 | `trash` |

## 无障碍

- 所有状态有文字；VoiceOver 读出“雾港侦探 第 3 卷，读到 42%，已离线”。
- 文字对比：`ink` 全场景 ≥ 7:1；`accent` 在所有底色 ≥ 4.5:1（浅 6.9–7.7、深 5.6–8.5）；`on-jam` 在 `jam` 上浅 7.7、深 5.1；`jam` 作图形标记 ≥ 3:1（深色 surface 上 3.4）。
- 键盘焦点用 2pt `focus-ring` 实线外环；iPad 指针悬停用系统 hover 效果。
- Dynamic Type 到 AX5 时：封面网格降为 2 列，列表行改为多行布局，工具栏文字按钮改图标 + 无障碍名称。
- 浅色 / 深色、减弱动态效果、增强对比度都要过一遍。

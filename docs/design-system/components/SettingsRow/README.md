# SettingsRow

设置行：系统 `Form` 行 + 30pt 圆角图标块（彩色只用于设置页的分类识别）。

- 开关行、值行（菜单选择，`chevron.up.chevron.down`）、导航行（chevron）。
- 辅助功能字号下选择器使用 `.navigationLink`，标题与当前值上下显示，避免菜单值被截断；由 `settingsPickerStyle()` 统一处理。
- 分组脚注说明影响范围，例如“布局设置会作为之后打开的漫画的默认值”。
- 存储条：按类别分段（已导入漫画 `jam`、远程下载 `chart-downloads`、临时数据 `chart-temp`、远程封面 `chart-thumbs`）。不借用状态色，免得“临时数据”看起来像警告。
- 每类一行，行尾是清理 / 清空按钮与确认弹窗，永远不提供“一键全部清理”。

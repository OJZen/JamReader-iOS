# Buttons

按钮：系统按钮样式，不自造形状。

| 样式 | SwiftUI | 用途 |
| --- | --- | --- |
| primary | `.borderedProminent` + `.tint(.appJam)` | 每屏最多一个：继续阅读、导入、保存 |
| secondary | `.bordered` | 并列的次要动作 |
| plain | `.borderless` | 取消、文字链接 |
| danger | `role: .destructive` | 只在确认弹窗与菜单末尾 |
| 工具栏 | 系统 ToolbarItem（iOS 26 玻璃） | 导航栏操作 |

- 实心按钮底色用 `jam`、文字用 `on-jam`（白）。不要让它继承 AccentColor：深色下 `accent` 是亮果酱粉，白字在上面不可读。
- 文字按钮、链接、工具栏按钮用 `accent`。
- 键盘焦点：2pt `focus-ring` 外环，偏移 2pt。
- 禁用 35% 透明，并说明为何不可用（Notice / 脚注），不留无效按钮。

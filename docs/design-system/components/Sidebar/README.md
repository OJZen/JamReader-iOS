# Sidebar

iPad 侧栏：在一屏内同时看到“来源”与“集合”，用 UIKit split view（现有外壳）。

## 规则
- 宽度使用 split view 系统默认值；行高至少 44；选中行 `fill` 底 + `radius-md`（集中在 `SidebarSelectionStyle.swift` 修改）。
- 书库分区：继续阅读（汇总）、我的书库列表（类型图标：App 内 `books.vertical`、关联文件夹 `folder.badge.link`、已导入 `tray`）。
- 选中书库后出现该书库的集合分区；远程侧栏为 服务器 / 离线书架 / 已保存文件夹；设置侧栏为 通用 / 阅读 / 书库 / 存储。
- ⌘1/2/3 切换分区；焦点与指针交互使用系统控件。窗口适配见 [iPhone Duo](../../06-iphone-duo.md#书库--远程--设置)。

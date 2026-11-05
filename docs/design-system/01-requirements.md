# 设计决策

业务能力、操作流程、数据边界由 [设计需求](../design-requirements.md) 负责。本章只保留界面决策的理由；入口、组件与数值在各自负责文档维护。

| 决策 | 理由 | 规则位置 |
| --- | --- | --- |
| 本地书库与远程分为两个入口 | 文件归属、进度与管理能力不同，不能把离线保存当作本地导入 | [信息架构](02-architecture.md) |
| 添加漫画按用途组织 | 用户先决定复制文件、使用已有文件夹或新建空书库，再选目标 | [添加漫画](components/ScreenAddComics/README.md) |
| 继续阅读的位置二选一 | 只有一个书库时也不重复展示同一组漫画 | [ContinueReading](components/ContinueReading/README.md) |
| 集合内筛选与搜索组合 | 保持集合范围，空结果能解释当前条件 | [FilterChips](components/FilterChips/README.md) |
| 点封面阅读，更多菜单管理 | 阅读不必先经过详情页，轻操作与删除分开 | [MoreMenu](components/MoreMenu/README.md) |
| 果酱色区分填充与可点文字 | 深色下提亮文字强调色，实心按钮仍保留白字对比度 | [颜色](00-foundations.md#颜色) |
| 状态用图标与文字表达 | 颜色只作辅助；阅读缓存不能冒充主动离线保存 | [StatusBadge](components/StatusBadge/README.md) |
| 阅读器工具按页面与漫画分组 | 显示面板只列出生效控件，页码入口与受保护导航不重复 | [阅读器](03-reader.md) |
| 导航按窗口宽度适配 | 窄窗口聚焦当前页，宽窗口同时显示来源与内容 | [窗口适配](06-iphone-duo.md) |

页面状态见 [状态要求](../design-requirements.md#页面状态)，功能边界见 [维护与评审](../design-requirements.md#8-维护与评审)。实现与静态稿的差异及未接入的环境适配见 [实现取舍与能力边界](05-batches.md)。

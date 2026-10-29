# StatusBadge

状态标识：图标 + 文字的胶囊，颜色只做辅助，读屏读出文字。

## 远程副本五态（全 App 只用这一套）
| 状态 | token | 图标 | 含义 |
| --- | --- | --- | --- |
| 未下载 | `fill` / `ink-2` | download | 只在服务器上；通常不显示，只在信息页出现 |
| 下载中 | `accent-soft` / `accent-on-soft` | 进度环 | 显示百分比，可在任务条取消 |
| 已离线 | `offline-soft` / `offline` | arrow.down.circle.fill | 本机有完整副本，以已知信息为准 |
| 较旧副本 | `warning-soft` / `warning` | clock.badge.exclamationmark | 服务器文件比副本新，可“更新副本” |
| 失败 | `danger-soft` / `danger` | exclamationmark.triangle | 中断或失败，不冒充完成 |

“阅读缓存”不显示徽标——缓存不等于离线。

## 其它
- 已读 `success` + 勾；阅读中只写百分比。
- 书库：只读（`warning` + lock）、需要重新授权（`danger`）。
- 协议标签 SMB / WEBDAV 为中性灰，不加颜色。

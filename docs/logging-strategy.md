# JamReader 日志策略

日志用于还原一次业务动作及其失败边界，不用于记录用户内容，也不应成为滚动、解码或网络分块热路径的负担。实际覆盖以 `AppLog` 调用和测试为准，不在文档维护逐模块完成清单。

## 入口与分类

运行时代码统一使用 `JamReader/Core/Logging/AppLog.swift`，常用分类如下；完整分类以该文件为准：

- `library`、`libraryImport`、`libraryIndexing`：资料库、导入、扫描和索引。
- `remote`、`remoteCache`：SMB/WebDAV、下载、离线副本、缓存策略和 active lease。
- `reader`：打开、session 生命周期、进度与页面保存。
- `persistence`：SQLite、UserDefaults、Keychain 和文件持久化失败。
- `ui`：仅记录会改变业务状态的协调动作，不记录普通点击、滚动或 layout。

Objective-C/C 桥接层使用相同 subsystem `ooou.fun.jamreader` 和匹配 category，不使用 `OS_LOG_DEFAULT`。

## 隐私与字段

`AppLogSanitizer` 各方法的保护范围不同，不能把“经过 helper”理解成“已脱敏”：

| 方法 | 当前行为与限制 |
| --- | --- |
| `url` | 移除用户名、密码、query 和 fragment；仍保留主机和路径 |
| `path` | 保留末尾路径分量并限制长度；文件名仍可见 |
| `namesPreview` | 限制名称数量和总长度；保留的名称仍是原文 |
| `errorDescription` | 对 `String(describing: error)` 限制长度；不移除错误中的凭据、URL 或路径 |
| `hashedIdentifier` | 返回 SHA-256 摘要前缀，用于标识关联 |

- 写日志前按字段选择处理方式；无法确认安全的错误应记录固定业务摘要或错误 domain/code，不能把截断后的任意错误当成安全的 `.public` 字段。
- `error=` 不直接拼接 `localizedDescription` 或 `String(describing:)`。
- 不记录用户名、密码、token、authorization header、凭据引用原文、完整用户目录、完整书名列表、图片或文档正文。
- 记录数量、耗时、provider、结果类型和经过脱敏的作用域；不要为了调试输出用户内容。

## 级别

- `notice`：用户可感知的重要维护动作或策略变化。
- `info`：低频业务动作成功或正常结束。
- `warning`：可恢复的异常、fallback 或一致性修复。
- `error`：需要用户提示或开发排查的失败。

## 记录边界

适合记录：业务入口与摘要结果、持久化提交、导入/删除/缓存协调、连接或 reader session 生命周期、一次性 fallback。

默认保持静默：每页解码与预热、每个 cell/thumbnail 成功、SMB/WebDAV chunk、SwiftUI `body`、UIKit layout、频繁 progress，以及格式探测链中的正常失败。外层最终失败必须有一条可关联日志。

## 阅读器性能跟踪

`JamReader/ReaderKernel/ReaderPerformanceTrace.swift` 仅在 Debug 构建且进程环境变量 `JAM_READER_TRACE=1` 时启用，通过 `AppLog.reader.debug` 记录翻页、布局、预热和反馈耗时。它默认关闭，Release 始终关闭；开启跟踪不等于已验证性能改善。

## 验证

按[开发流程](development-workflow.md#validation-by-change-type)验证日志修改。`AppLogSanitizerTests` 目前覆盖文本截断、URL 字段移除、路径尾部保留和名称数量限制；没有通用错误脱敏或哈希标识测试。新增敏感字段或脱敏逻辑时补相应边界测试，静态日志检查只能发现部分明显违规。

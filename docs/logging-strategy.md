# JamReader 日志策略

更新时间：2026-08-23

日志用于还原一次业务动作及其失败边界，不用于记录用户内容，也不应成为滚动、解码或网络分块热路径的负担。实际覆盖以 `AppLog` 调用和测试为准，不在文档维护逐模块完成清单。

## 入口与分类

运行时代码统一使用 `JamReader/Core/Logging/AppLog.swift`：

- `library`、`libraryImport`、`libraryIndexing`：资料库、导入、扫描和索引。
- `remote`、`remoteCache`：SMB/WebDAV、下载、离线副本、缓存策略和 active lease。
- `reader`：打开、session 生命周期、进度与页面保存。
- `persistence`：SQLite、UserDefaults、Keychain 和文件持久化失败。
- `ui`：仅记录会改变业务状态的协调动作，不记录普通点击、滚动或 layout。

Objective-C/C 桥接层使用相同 subsystem `ooou.fun.jamreader` 和匹配 category，不使用 `OS_LOG_DEFAULT`。

## 隐私与字段

- 路径、URL、名称列表、错误和稳定标识分别经过 `AppLogSanitizer.path`、`url`、`namesPreview`、`errorDescription`、`hashedIdentifier`。
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

保持静默：每页解码与预热、每个 cell/thumbnail 成功、SMB/WebDAV chunk、SwiftUI `body`、UIKit layout、频繁 progress，以及格式探测链中的正常失败。外层最终失败必须有一条可关联日志。

修改日志后运行 `./scripts/check_project_static_guards.sh`。脱敏行为由 `AppLogSanitizerTests` 保护；新增字段时补相应边界测试，尤其是 URL 凭据、路径、authorization、哈希标识和超长错误。

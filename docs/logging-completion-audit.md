# JamReader 日志完成审计

更新时间：2026-07-07

本文件记录当前日志系统的完成状态、可验证证据和刻意保留的边界。它不是功能需求文档，主要用于后续维护时快速判断新增日志是否符合现有策略。

## 当前结论

- 运行时代码统一使用 `AppLog` 和项目 subsystem `ooou.fun.jamreader`。
- Swift 代码禁止直接构造 `Logger`；Objective-C/C 桥接层只允许使用项目 subsystem 创建 `os_log_t`。
- 日志中的路径、URL、错误、名称列表、凭据引用等字段已有统一 sanitizer 或哈希策略。
- `scripts/build_ios.sh` 已在 `xcodebuild` 前运行 `scripts/check_logging_hygiene.sh`，日志卫生检查已进入常规构建链路。
- 当前没有发现必须继续补的高价值日志入口；剩余静默 fallback 已在 `docs/logging-strategy.md` 中归类为格式探测、归档枚举、远程封面热路径和缩略图缓存维护。

## 已验证命令

```bash
scripts/check_logging_hygiene.sh
```

结果：通过。覆盖直接输出、绕过 `AppLog`、默认 `os_log`、明显凭据字段、未走 `AppLogSanitizer.errorDescription` 的 `error=` 日志字段。

```bash
scripts/build_ios.sh
```

结果：通过。构建期间会先执行 `check_logging_hygiene`。当前仅有既有 AppIntents metadata warning。

```bash
rg -n "NSLog\(|OS_LOG_DEFAULT|\bprint\(|\bdebugPrint\(" JamReader -g '*.{swift,m,h,mm,c,cpp}'
```

结果：无命中。

```bash
rg -n 'error=\\\([^"\\]*(localizedDescription|String[[:space:]]*\([[:space:]]*describing:)' JamReader --glob '*.swift'
```

结果：无命中。

## 已覆盖区域

- App lifecycle/cache pressure。
- Library list/storage/import/indexing/organization/removal/metadata editing。
- Reader open pipeline、Reader ViewModel、Reader page cache、EPUB preparation、按需 reader trace。
- Remote SMB/WebDAV browsing、range probing、connection pool、download/import/offline/cache/history/favorites/settings。
- Persistence stores，包括 JSON、UserDefaults、Keychain、SQLite inspection、maintenance records。

详细列表以 `docs/logging-strategy.md` 的“当前已覆盖的高价值区域”为准。

## 隐私与噪声边界

- 不记录密码、用户名、authorization header、token、凭据引用原文、图片数据、XML/HTML/PDF/EPUB 内容。
- 路径默认只保留末尾关键组件，远程路径通过 `AppLogSanitizer.path` 或预先脱敏变量输出。
- 错误描述默认最多 500 字符，普通文本默认最多 300 字符，名称列表默认最多 8 项。
- 不在页面解码、滚动、cell 复用、SMB/WebDAV chunk 读取、缩略图成功加载等热路径逐项打日志。

## 后续测试建议

当前按项目要求未运行测试，也未在本轮新增测试。后续建议优先补：

- `AppLogSanitizer` 的 path/url/error/namesPreview/hashedIdentifier 截断和脱敏单元测试。
- Library storage/source resolution fallback 的限频日志和返回语义测试。
- Remote cache/import 的服务器隔离、同名路径隔离、清缓存清历史测试。
- Keychain 状态读取失败时不暴露凭据、不误判为可复用密码的 ViewModel 测试。
- Reader open pipeline 的本地、远程缓存、远程流式、远程下载 fallback 日志路径测试。

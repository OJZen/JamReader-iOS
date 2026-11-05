# JamReader Logging Strategy

Logs reconstruct a business action and where it failed. They do not record user content and must not burden scrolling, decoding, or network-chunk hot paths. Actual coverage is defined by `AppLog` calls and tests; do not maintain a module-by-module completion checklist in this document.

## Entry Point and Categories

Runtime code uses `JamReader/Core/Logging/AppLog.swift` throughout. Common categories follow; that file defines the complete list:

- `library`, `libraryImport`, `libraryIndexing`: libraries, import, scanning, and indexing.
- `remote`, `remoteCache`: SMB/WebDAV, downloads, offline copies, cache policy, and active leases.
- `reader`: opening, session lifecycle, progress, and page saving.
- `persistence`: SQLite, UserDefaults, Keychain, and file-persistence failures.
- `ui`: only coordination actions that change business state, not ordinary taps, scrolling, or layout.

Objective-C/C bridges use the same subsystem, `ooou.fun.jamreader`, and a matching category, not `OS_LOG_DEFAULT`.

## Privacy and Fields

`AppLogSanitizer` methods protect different things. Passing through a helper does not mean a value is redacted:

| Method | Current behavior and limits |
| --- | --- |
| `url` | Removes username, password, query, and fragment; retains host and path |
| `path` | Keeps trailing path components and limits length; filenames remain visible |
| `namesPreview` | Limits name count and total length; retained names remain verbatim |
| `errorDescription` | Limits the length of `String(describing: error)`; does not remove credentials, URLs, or paths from errors |
| `hashedIdentifier` | Returns a SHA-256 digest prefix for identity correlation |

- Choose handling per field before logging. If an error cannot be confirmed safe, log a fixed business summary or error domain/code. Arbitrary truncated errors are not safe `.public` fields.
- Do not concatenate `localizedDescription` or `String(describing:)` directly into `error=`.
- Do not log usernames, passwords, tokens, authorization headers, raw credential references, full user directories, full lists of book titles, images, or document bodies.
- Log counts, durations, providers, result types, and redacted scopes. Do not output user content for debugging.

## Levels

- `notice`: important maintenance actions or policy changes visible to users.
- `info`: successful or normal completion of infrequent business actions.
- `warning`: recoverable exceptions, fallbacks, or consistency repairs.
- `error`: failures requiring user feedback or developer investigation.

## Logging Boundaries

Suitable events: business entry points and summary results, persistence commits, import/deletion/cache coordination, connection or reader-session lifecycle, and one-time fallbacks.

Silent by default: per-page decoding and warming, each successful cell/thumbnail, SMB/WebDAV chunks, SwiftUI `body`, UIKit layout, frequent progress, and expected failures in format probing. A final failure at the outer layer must have one correlatable log entry.

## Reader Performance Tracing

`JamReader/ReaderKernel/ReaderPerformanceTrace.swift` is enabled only in Debug builds with the process environment variable `JAM_READER_TRACE=1`. It logs page-turn, layout, warming, and feedback durations through `AppLog.reader.debug`. It is off by default and always off in Release. Enabling tracing does not establish a performance improvement.

## Validation

Validate logging changes using [development workflow](development-workflow.md#validation-by-change-type). `AppLogSanitizerTests` currently covers text truncation, URL field removal, trailing path retention, and name-count limits; it has no general error-redaction or hashed-identifier tests. Add boundary tests for new sensitive fields or redaction logic. Static logging checks detect only some obvious violations.

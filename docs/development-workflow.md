# JamReader Development Workflow

Use this document for repository setup, validation, and handoff. Product and architecture context lives in [project context](project-context.md); known failure modes live in [maintenance pitfalls](maintenance-pitfalls.md).

## Before Editing

Follow the [agent entry point](../AGENTS.md), identify the feature boundary and matching tests, and trace callers before editing a shared function. Extend an existing service/store when it already owns the operation. If a user-authored change conflicts with the task, realign instead of overwriting it.

## Repository Hygiene

- Keep transient work in a task-specific directory on the external project disk. The standard build location is `.xcodebuild/`; override it with `CODEX_BUILD_ARTIFACTS_ROOT` when a separate external cache is preferable.
- `.mupdf/`, `.xcodebuild*/`, sample archives, local caches, credentials, and device artifacts are local-only.
- System temporary directories are acceptable only for small, short-lived tool-managed files when an external path is impractical; do not leave task output there.
- Delete superseded task output and task-specific DerivedData after verification. Check ownership before cleaning existing artifacts; keep an incremental cache only while it still saves active work.
- Never clean application containers, imported comics, linked source folders, runtime databases, business caches, or `.mupdf/` just to recover build space.

## Build And Static Checks

Builds require Xcode with the iOS SDK; the static scripts require Bash, `rg`, and Python 3.

Run all repository policy checks:

```bash
./scripts/check_project_static_guards.sh
```

This scans for forbidden SwiftUI gesture APIs, unsupported-MOBI references, obvious logging violations, and localization catalog errors. These guards do not prove runtime gesture behavior, complete format support, or complete log redaction.

Build the unsigned app for a generic iOS device:

```bash
./scripts/build_ios.sh
```

The script runs static guards, then cleans and builds in `${DERIVED_DATA_PATH:-${CODEX_BUILD_ARTIFACTS_ROOT:-.xcodebuild}/build-ios}`. The default MuPDF root is defined in the script under `.mupdf/`; `MUPDF_ROOT` can override it. Linking requires `include/mupdf/fitz.h` and both `libmupdf.a` and `libmupdf-third.a` in that root's `build/ios-arm64/` directory.

Without those inputs, PDF reading is unavailable and EPUB uses bundled epub.js. When MuPDF can open the document, PDF/EPUB pages use the image-sequence reader; EPUB also falls back to epub.js if MuPDF opening fails.

`LocalPDFThumbnailRenderer` uses CoreGraphics without requiring MuPDF. The local-library metadata extractor may try MuPDF first; a visible PDF cover alone does not prove that the build can open PDF pages in the reader.

MuPDF arguments are supplied by `build_ios.sh`, not by merely opening the Xcode project. The simulator commands below and CI do not link the local device libraries and do not validate MuPDF rendering.

## Tests

Discover available destinations and reuse an installed simulator before creating a device or downloading a runtime. Check disk space before a large build:

```bash
xcodebuild -project JamReader.xcodeproj -scheme JamReader -showdestinations
```

Run the full XCTest suite with a discovered simulator identifier:

```bash
xcodebuild \
  -project JamReader.xcodeproj \
  -scheme JamReader \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' \
  -derivedDataPath "$PWD/.xcodebuild/tests" \
  CODE_SIGNING_ALLOWED=NO \
  test
```

During iteration, add an option such as `-only-testing:JamReaderTests/RemoteServerBrowserLayoutTests` to the command above, then run the wider affected suite before handoff.

Tests that touch files or SQLite should create isolated temporary roots and must not depend on developer application data or real remote credentials. Network protocol tests should use fakes/stubs; real SMB/WebDAV behavior belongs in explicit device validation.

## Continuous Integration

- `.github/workflows/ios-ci.yml` runs static guards, an unsigned simulator build, and the full `JamReaderTests` target on a dynamically selected iPhone simulator.
- `.github/workflows/static-guards.yml` runs the same policy checks on Ubuntu for a fast, low-cost signal.

Keep both layers: the Linux job catches portable policy failures quickly, while the macOS job validates the Xcode project and tests. Neither replaces physical-device, real SMB/WebDAV, rotation, memory-pressure, or security-scoped-access validation.

The project currently has an app target and an XCTest target, but no UI test target. Do not describe manual interaction coverage as automated.

## Validation By Change Type

For every change, run static guards and `git diff --check`. Source or Xcode project changes also require the generic iOS build above. Add the relevant checks below; documentation-only work does not require building or launching the app.

| Change | Additional validation |
| --- | --- |
| Documentation only | link/path/anchor review and verification of implementation claims |
| Pure model/store logic | focused XCTest |
| UI or ViewModel | focused XCTest, compact and regular-width review using [UI guidelines](ui-guidelines.md#change-checklist) |
| Reader/gesture/viewport | reader tests, full XCTest when feasible, iPhone/iPad manual paging/zoom/rotation/background checks |
| SQLite/import/deletion/cache | integration tests, restart/reload behavior, record/file consistency checks |
| SMB/WebDAV | remote tests plus real-server checks for listing, thumbnail, open, cancel, import/offline, and cache cleanup |
| Format policy/localization | format/localization tests; build for catalog changes as well |

Use the [manual regression checklist](maintenance-pitfalls.md#12-最小回归检查清单) for the affected high-risk paths. When the user limits validation or the environment cannot run a check, report that boundary explicitly. Simulator success does not prove device gestures, memory pressure, security-scoped access, SMB behavior, or iPad restoration.

## Performance Review

- Keep main-thread work within a frame budget; move scans, archive reads, network I/O, thumbnail extraction, and image decode away from it.
- Bound task concurrency, prefetch distance, cache size, retries, and recursive directory inspection.
- Cancel work when cells disappear, requests are superseded, views close, or server identity changes.

## Review And Handoff

Before declaring work complete:

```bash
git diff --check
git status --short
```

Review the full diff for data-loss paths, stale async results, server/library identity mixing, main-thread I/O, unbounded caches, hidden duplicate UI actions, hard-coded device paths, secrets, and generated artifacts. Report the exact validation run and any skipped simulator, real-server, or physical-device checks. Commit or push only when requested, and stage only files belonging to the change.

After validation, remove obsolete task artifacts and run `git status --short --ignored` when cleanup or ignore rules changed. A clean Git status does not justify deleting user/runtime data.

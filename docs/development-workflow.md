# JamReader Development Workflow

Use this document for repository setup, validation, and handoff. Product and architecture context lives in `project-context.md`; known failure modes live in `maintenance-pitfalls.md`.

## Before Editing

1. Run `git status --short --branch` and inspect existing diffs.
2. Identify the narrow feature boundary and its matching tests.
3. Read the relevant maintenance pitfall before touching reader, navigation, SQLite, import, remote, or cache code.
4. Prefer extending an existing service/store over adding a parallel path. If a file is large, extract a tested responsibility while preserving its facade.

Do not reformat or revert unrelated files. If a user-authored change conflicts with the task, stop and realign instead of overwriting it.

## Repository Hygiene

- Keep transient work on the external project disk. The standard build location is `.xcodebuild/`; override it with `CODEX_BUILD_ARTIFACTS_ROOT` when a separate external cache is preferable.
- `.mupdf/`, `.xcodebuild*/`, sample archives, local caches, credentials, and device artifacts are local-only.
- Use a task-specific directory below the external project disk. System temporary directories are acceptable only for small, short-lived tool-managed files when an external path is impractical; do not leave task output there.
- Delete superseded generated output and task-specific DerivedData after verification. Keep an incremental cache only while it still saves active work.
- Never clean application containers, imported comics, linked source folders, runtime databases, business caches, or `.mupdf/` just to recover build space.
- Add documentation only when it owns a distinct question. Update an existing authoritative page instead of creating a second explanation.

## Build And Static Checks

Run all repository policy checks:

```bash
./scripts/check_project_static_guards.sh
```

This validates UIKit-only gesture ownership, the unsupported-MOBI format policy, logging hygiene, and localization catalogs.

Build the unsigned app for a generic iOS device:

```bash
./scripts/build_ios.sh
```

The script cleans and builds below `${CODEX_BUILD_ARTIFACTS_ROOT:-.xcodebuild}`. It links MuPDF when `.mupdf/mupdf-1.27.2` is complete or when `MUPDF_ROOT` points to a compatible build; otherwise PDF support is compiled as unavailable and EPUB uses its web fallback.

## Tests

Discover available destinations rather than documenting a machine-specific simulator:

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

During iteration, narrow with `-only-testing`, then run the wider affected suite before handoff:

```bash
xcodebuild \
  -project JamReader.xcodeproj \
  -scheme JamReader \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' \
  -derivedDataPath "$PWD/.xcodebuild/tests" \
  CODE_SIGNING_ALLOWED=NO \
  test \
  -only-testing:JamReaderTests/RemoteServerBrowserLayoutTests
```

Tests that touch files or SQLite should create isolated temporary roots and must not depend on developer application data or real remote credentials. Network protocol tests should use fakes/stubs; real SMB/WebDAV behavior belongs in explicit device validation.

## Continuous Integration

- `.github/workflows/ios-ci.yml` runs static guards, an unsigned simulator build, and the full `JamReaderTests` target on a dynamically selected iPhone simulator.
- `.github/workflows/static-guards.yml` runs the same policy checks on Ubuntu for a fast, low-cost signal.

Keep both layers: the Linux job catches portable policy failures quickly, while the macOS job validates the Xcode project and tests. Neither replaces physical-device, real SMB/WebDAV, rotation, memory-pressure, or security-scoped-access validation.

The project currently has an app target and an XCTest target, but no UI test target. Do not describe manual interaction coverage as automated.

## Validation By Change Type

| Change | Minimum validation |
| --- | --- |
| Documentation only | link/path review, `git diff --check` |
| Pure model/store logic | focused XCTest, static guards, `git diff --check` |
| UI or ViewModel | focused XCTest, static guards, generic iOS build, compact and regular-width review |
| Reader/gesture/viewport | reader tests, full XCTest when feasible, build, iPhone/iPad manual paging/zoom/rotation/background checks |
| SQLite/import/deletion/cache | integration tests, restart/reload behavior, record/file consistency checks |
| SMB/WebDAV | remote tests plus real-server checks for listing, thumbnail, open, cancel, import/offline, and cache cleanup |
| Format policy/localization/project settings | full static guards and generic iOS build |

Use `docs/maintenance-pitfalls.md#12-最小回归检查清单` for high-risk manual coverage. Simulator success does not prove device gestures, memory pressure, security-scoped access, SMB behavior, or iPad restoration.

## Performance And UX Review

- Keep main-thread work within a frame budget; move scans, archive reads, network I/O, thumbnail extraction, and image decode away from it.
- Bound task concurrency, prefetch distance, cache size, retries, and recursive directory inspection.
- Cancel work when cells disappear, requests are superseded, views close, or server identity changes.
- Use UIKit collection views for large/high-frequency surfaces and UIKit recognizers for gestures.
- Preserve system navigation, sheets, safe areas, accessibility labels, Dynamic Type, and native iPhone/iPad adaptation.
- Avoid duplicate actions across tabs, cards, toolbars, and context menus; one clear primary entry is preferable.

## Review And Handoff

Before declaring work complete:

```bash
git diff --check
git status --short
```

Review the full diff for data-loss paths, stale async results, server/library identity mixing, main-thread I/O, unbounded caches, hidden duplicate UI actions, hard-coded device paths, secrets, and generated artifacts. Report the exact validation run and any skipped simulator, real-server, or physical-device checks. Commit or push only when requested, and stage only files belonging to the change.

After validation, remove obsolete task artifacts and run `git status --short --ignored` when cleanup or ignore rules changed. A clean Git status does not justify deleting user/runtime data.

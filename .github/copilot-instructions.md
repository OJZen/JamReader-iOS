# Copilot Instructions — JamReader iOS

## Build & Validate

```bash
# CLI build (no code signing)
xcodebuild \
  -project JamReader.xcodeproj \
  -scheme JamReader \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/jamreader-derived-data \
  CODE_SIGNING_ALLOWED=NO \
  build

# Or use the build script
scripts/build_ios.sh

# Gesture policy check (CI-blocking — must pass before any PR)
scripts/check_no_swiftui_gestures.sh
```

No automated test suite exists. Validation is manual (see migration plan for hand-test checklist).

## Architecture Overview

Single iOS app (iPhone + iPad) combining desktop JamReader + JamReaderLibrary. SwiftUI shell with UIKit for reader/gesture-heavy surfaces. Three-tab bottom navigation:

- **书库 (Library)** — local library management, collections, import
- **浏览 (Browse)** — SMB/WebDAV remote browsing, offline shelf, saved folders
- **设置 (Settings)** — preferences, cache, maintenance

### Layer Structure

| Layer | Location | Role |
|-------|----------|------|
| App | `JamReader/App/` | Entry point, `AppDependencies` DI container, tab routing |
| Core | `JamReader/Core/` | Pure domain models and types (no UI imports) |
| Data | `JamReader/Data/` | SQLite, archive readers, scanner, thumbnail pipeline, remote services |
| ReaderKernel | `JamReader/ReaderKernel/` | `ReaderSessionController`, gesture coordinator, `ZoomableImagePageView` |
| Features | `JamReader/Features/` | Feature modules: Reader, Libraries, Browser, Browse (remote), Settings |
| SharedUI | `JamReader/SharedUI/` | Reusable SwiftUI components, UIKit bridges, design tokens |
| Vendor | `JamReader/Vendor/` | `SWXMLHash 8.1.1` (XML), `SMBClient 0.3.1` (SMB protocol) |

### Reader Architecture

All local and remote entry points must go through the unified reader open pipeline:

1. **Open request** — Library, remote cache, remote stream, and file URL callers create `ComicOpenRequest`.
2. **Open coordinator** — `ComicOpenCoordinator` resolves the request into `ComicReaderSession` + `ComicDocument`, including source URL, cache lease, security scope, initial progress, and state store.
3. **Reader shell** — `ComicReaderView` hosts the reader UI. Do not reintroduce a separate remote reader shell with its own page/progress/layout state machine.
4. **Content containers** — `ImageSequenceReaderContainerView` (paged UICollectionView), `VerticalImageSequenceReaderContainerView` (continuous scroll), `PDFReaderContainerView`, and EPUB support render the active document.

### Data Layer

- **Database**: Raw SQLite3 C API (not CoreData/GRDB). The app-owned library database is `Application Support/JamReader/AppLibraryV2.sqlite`; external folders are content sources only.
- **Assets**: Library covers and derived resources live under `Application Support/JamReader/LibraryAssets/<libraryID>/`. Do not write covers or metadata into source folders.
- **Archive formats**: ZIP/CBZ (custom parser + libarchive fallback), TAR/CBT (custom), RAR/CBR/7Z/CB7/ARJ (libarchive via ObjC++ bridge `YRLibArchiveReader`), PDF (PDFKit), EPUB. Router: `ComicDocumentLoader`.
- **Remote**: Vendored `SMBClient` with async/await API. `RemoteServerBrowsingService` abstracts SMB/WebDAV listing, remote cache, and supported streaming. WebDAV ZIP streaming/cover prefetch requires Range support; no-Range WebDAV falls back to full download before opening.
- **Thumbnails/cache**: Reader pages, remote thumbnails, offline copies, and partial downloads have separate lifecycles. Cache deletion must also remove matching cache records and must not delete active reader leases.

## Hard Constraints

### No SwiftUI Gestures (CI-enforced)

All gesture handling must use UIKit `UIGestureRecognizer`. The script `scripts/check_no_swiftui_gestures.sh` blocks `.gesture()`, `.onTapGesture()`, `DragGesture`, `MagnificationGesture`, `RotationGesture`, `LongPressGesture`, `.simultaneousGesture()`, `.highPriorityGesture()`. Violations fail CI.

### Native Library Ownership

JamReader does not read or write desktop compatibility databases. The app-owned SQLite database is the only business truth.

- Do not create hidden library folders or database files in source folders.
- Store paths as library-scoped relative paths; use file fingerprints only to preserve local state across rename/move during rescan.
- Scope all mutable SQLite writes by `library_id`; public `Int64` IDs are not globally safe.
- Enable SQLite foreign keys for every connection, not only at bootstrap.
- Remote server configuration and credentials stay in their existing JSON/UserDefaults/Keychain stores; do not merge them into the local library schema without an explicit design change.

### Tab Boundary Isolation

Each tab owns its scope. No functional creep across tabs. No duplicate entry points for the same action.

## Key Conventions

### Swift Style

- **Concurrency**: async/await + `@MainActor` on ViewModels/Controllers. Use `actor` for thread-safe caches. No Combine Publisher chains for async work.
- **Models**: Structs in `Core/`, all `Identifiable`, `Hashable`. Immutable with `updating*()` builder methods (e.g., `updatingReadState()`).
- **Services**: `final class`, constructor injection. No service locators.
- **ViewModels**: Conform to `LoadableViewModel` protocol (`isLoading` / `loadIfNeeded()` / `load()`). Use `@Published` for state, `@StateObject` to own, `@ObservedObject` when passed.
- **Error handling**: Guard-let early returns. Result enums over thrown exceptions.
- **Naming**: `*ViewModel`, `*Reader` (archive), `*Store` (persistence), `*Descriptor` (config), `*Service` (business logic).

### Reader Gestures (Immutable Spec)

- **Un-zoomed**: L/R drag → paging, center tap → toggle chrome, edge tap → page turn, double-tap → zoom
- **Zoomed**: drag → intra-page scroll, only cross-page when at content edge
- **iPad keyboard**: arrow keys → paging, space → page turn
- Reference: iOS Photos/Books app interaction model, not desktop readers

### Dependencies Policy

Prefer system frameworks (PDFKit, ImageIO, SQLite3, CryptoKit). Only two vendored deps (SWXMLHash, SMBClient). Do not add new dependencies unless critical and discussed first.

### Performance Rules

- UI blocking ≤ 16 ms. Scan, cover extraction, page decode: all background tasks.
- Reader page cache: 3–5 pages in memory max. Prefetch bounded to 3-page lookahead.
- Memory warning → evict non-current page cache, cancel prefetch.
- Large images: adaptive downsampling based on device + zoom range.

## Minimum Deployment

- **iOS 17.6**, iPhone + iPad
- **Swift 5**, Whole Module Optimization in Release
- ObjC++ bridging header: `JamReader/Bridging-Header.h` (for `YRLibArchiveReader`)

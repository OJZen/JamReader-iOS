# Copilot Instructions — YACReader iOS

## Build & Validate

```bash
# CLI build (no code signing)
xcodebuild \
  -project yacreader.xcodeproj \
  -scheme yacreader \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/yacreader-derived-data \
  CODE_SIGNING_ALLOWED=NO \
  build

# Or use the build script
scripts/build_ios.sh

# Gesture policy check (CI-blocking — must pass before any PR)
scripts/check_no_swiftui_gestures.sh
```

No automated test suite exists. Validation is manual (see migration plan for hand-test checklist).

## Architecture Overview

Single iOS app (iPhone + iPad) combining desktop YACReader + YACReaderLibrary. SwiftUI shell with UIKit for reader/gesture-heavy surfaces. Three-tab bottom navigation:

- **书库 (Library)** — local library management, collections, import
- **浏览 (Browse)** — SMB/WebDAV remote browsing, offline shelf, saved folders
- **设置 (Settings)** — preferences, cache, maintenance

### Layer Structure

| Layer | Location | Role |
|-------|----------|------|
| App | `yacreader/App/` | Entry point, `AppDependencies` DI container, tab routing |
| Core | `yacreader/Core/` | Pure domain models and types (no UI imports) |
| Data | `yacreader/Data/` | SQLite, archive readers, scanner, thumbnail pipeline, remote services |
| ReaderKernel | `yacreader/ReaderKernel/` | `ReaderSessionController`, gesture coordinator, `ZoomableImagePageView` |
| Features | `yacreader/Features/` | Feature modules: Reader, Libraries, Browser, Browse (remote), Settings |
| SharedUI | `yacreader/SharedUI/` | Reusable SwiftUI components, UIKit bridges, design tokens |
| Vendor | `yacreader/Vendor/` | `SWXMLHash 8.1.1` (XML), `SMBClient 0.3.1` (SMB protocol) |

### Reader Architecture (4 layers)

1. **Reader Shell (SwiftUI)** — `ComicReaderView` / `RemoteComicReaderView`. Navigation entry only.
2. **Reader Runtime** — `ReaderSessionController` is the single source of truth for page index, chrome visibility, layout. All mutations go through `ReaderCommand` (command/reducer pattern).
3. **Reader Host (UIKit)** — `ReaderGestureCoordinator` dispatches taps. Chrome overlay doesn't affect content layout.
4. **Content Controllers** — `ImageSequenceReaderContainerView` (paged, UICollectionView-based), `VerticalImageSequenceReaderContainerView` (continuous scroll), `PDFReaderContainerView`. Each wraps `ZoomableImagePageView` (UIScrollView-based zoom).

### Data Layer

- **Database**: Raw SQLite3 C API (not CoreData/GRDB). Schema mirrors desktop `library.ydb` v9.16.0 for full compatibility.
- **Archive formats**: ZIP/CBZ (custom parser + libarchive fallback), TAR/CBT (custom), RAR/CBR/7Z/CB7/ARJ (libarchive via ObjC++ bridge `YRLibArchiveReader`), PDF (PDFKit). Router: `ComicDocumentLoader`.
- **Remote**: Vendored `SMBClient` with async/await API. `RemoteServerBrowsingService` abstracts directory listing. Downloads go to local cache, not streamed live.
- **Thumbnails**: Two-tier cache — memory (NSCache, 48 items / 192 MB) + disk (512 MB LRU in `Caches/YACReader/ReaderPages/`).

## Hard Constraints

### No SwiftUI Gestures (CI-enforced)

All gesture handling must use UIKit `UIGestureRecognizer`. The script `scripts/check_no_swiftui_gestures.sh` blocks `.gesture()`, `.onTapGesture()`, `DragGesture`, `MagnificationGesture`, `RotationGesture`, `LongPressGesture`, `.simultaneousGesture()`, `.highPriorityGesture()`. Violations fail CI.

### Desktop Library Compatibility

Must read/write desktop `library.ydb` without corruption:
- Comic hashing: SHA1 of first 512 KB + file size (`pseudoHash`)
- Cover scaling: 640px wide (landscape), 480px wide (portrait), 960px tall (super-long), JPEG quality 75
- Two storage modes: **In-place** (`.yacreaderlibrary/` beside source) and **Mirrored** (app sandbox only)

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
- ObjC++ bridging header: `yacreader/Bridging-Header.h` (for `YRLibArchiveReader`)

# JamReader Project Context

This is the current engineering map for JamReader and the default orientation document for a new session. It describes shipped code boundaries, not a future plan. If it drifts from implementation or tests, update this file with the code change.

## Product Scope

JamReader is a native iPhone and iPad comic reader with three primary areas:

- **Library** manages app-owned and linked local libraries, imports, folders, search, metadata, tags, reading lists, and reading progress.
- **Browse** manages SMB/WebDAV servers, remote directories, saved folders, history, online reading, imports, and offline copies.
- **Settings** owns app startup behavior, the shared reader default and display behavior, reusable import defaults, storage/cache policy, library maintenance, and app information.

Image directories are supported through the scanner and `DirectoryImageSequenceReader`. Supported file extensions are centralized in `JamReader/Core/Types/SupportedComicFormats.swift`:

- ZIP/CBZ, RAR/CBR, 7Z/CB7, ARJ, TAR/CBT
- PDF when the local MuPDF engine is linked
- EPUB through MuPDF when available, otherwise the bundled epub.js reader

MOBI is intentionally unsupported. Adding a format requires coordinated importing, scanning, local opening, remote presentation, tests, localization, and product documentation; `SupportedComicFormats` remains the runtime policy owner.

## Runtime Shape

The app is a UIKit/SwiftUI hybrid with a UIKit lifecycle and navigation shell.

The app target uses Swift 5, supports iPhone and iPad, and has an iOS 17.6 deployment target. APIs newer than the deployment target need availability handling. User-facing strings cover English, Simplified Chinese, Traditional Chinese (Taiwan), and Japanese.

| Area | Primary location | Responsibility |
| --- | --- | --- |
| Bootstrap | `JamReader/JamReaderApp.swift` | `AppDelegate`, `SceneDelegate`, root window creation |
| Composition | `JamReader/App/AppDependencies.swift` | Constructs shared stores, services, and reader pipeline |
| Navigation | `JamReader/App/AppRootTabBarControllerView.swift`, `AppNavigationSupport.swift` | Native tabs/navigation, route persistence, iPhone/iPad adaptation |
| Presentation | `JamReader/App/UIKitPresentationCoordinator.swift` | Reader transitions and system sheet presentation |
| Domain | `JamReader/Core/` | Shared models, enums, and format policy |
| Local data | `JamReader/Data/Libraries/`, `JamReader/Data/SQLite/` | Library storage, raw SQLite repositories, scanning, indexing, import, removal |
| Remote data | `JamReader/Data/Remote/` | SMB/WebDAV clients, listing, thumbnails, downloads, caches, offline copies |
| Reader core | `JamReader/ReaderKernel/` | Open requests, sessions, progress, commands, UIKit gesture/zoom behavior |
| Screens | `JamReader/Features/` | Library, browse, remote, reader, and settings feature state/UI |
| UI bridges | `JamReader/SharedUI/` | Reusable views, UIKit containers, reader chrome, design tokens |
| Bundled code | `JamReader/Vendor/`, `JamReader/Resources/EPUBReader/` | SMBClient, SWXMLHash, and epub.js assets |
| Regression tests | `JamReaderTests/` | Unit and file/database/network-boundary integration tests |

The Xcode project uses file-system-synchronized groups. New source files under `JamReader/` or `JamReaderTests/` are normally discovered automatically, but target membership and a real build still need verification.

## Core Flows

### Local Library

1. `LibraryHomeView` and `LibraryBrowserView` expose libraries and indexed comics.
2. `LibraryStorageManager` resolves an app-managed root or a security-scoped linked folder.
3. `LibraryScanner` and the native indexing repositories synchronize discovered content into the app database.
4. Opening creates `ComicOpenRequest.library`; `ComicOpenCoordinator` resolves access, state, and document lifetime.
5. `ComicReaderView` and `ComicReaderViewModel` render the session and persist progress/metadata through the shared state store.

Local library kinds are `appManaged`, `linkedFolder`, and the default `Imported Comics` app-managed library. Importing content is different from creating a remote offline copy: an import must end inside a selected local library and be indexed before it is complete.

### Remote Browse And Read

1. `BrowseHomeView` lists saved SMB/WebDAV profiles and remote shortcuts.
2. `RemoteServerBrowserViewModel` uses `RemoteServerBrowsingService` for listing, previews, downloads, and cache state.
3. Opening creates `ComicOpenRequest.remote` and joins the same reader pipeline as local content.
4. ZIP/CBZ can use remote random access when the provider supports it. Other formats fall back to a complete local download before opening.
5. Active reader leases protect in-use cache files from cleanup or eviction.

Remote cover work must stay bounded. Prefer a valid same-name image; otherwise use supported random/range reads. A WebDAV server without Range support must not trigger a full comic download merely to show a thumbnail.

### Reader

`ComicOpenRequest -> ComicOpenCoordinator -> ComicReaderSession + ComicDocument -> ComicReaderView` is the single opening path. Do not recreate a separate local, cached, or remote reader state machine.

- `ComicDocumentLoader` routes directories and supported file formats.
- `ImageSequenceReaderContainerView` owns horizontal paging with `UICollectionView`.
- `VerticalImageSequenceReaderContainerView` owns continuous reading.
- `ZoomableImagePageView` owns zoom/pan coordination.
- `ReaderGestureCoordinator` and UIKit recognizers own reader gestures.
- `ReaderChromeOverlay` and related controls are presentation layers; they must not change reader viewport geometry.
- `ReaderLayoutPreferencesStore` owns one layout default shared by every image-sequence comic; library file types do not create separate reader profiles.

Reader lifecycle, viewport synchronization, zoom preservation, gestures, transitions, and background restoration are high-risk. Read the reader sections of [`maintenance-pitfalls.md`](maintenance-pitfalls.md) and run focused tests before changing them.

## Data Ownership

The app-owned database is the business source of truth:

- `Application Support/JamReader/AppLibraryV2.sqlite` stores libraries, folders, comics, organization, and reading state.
- `Application Support/JamReader/LibraryAssets/<library-id>/` stores derived covers and library assets.
- App-managed comic files live below the JamReader application-support root; linked folders remain external content sources and use persisted bookmarks.
- Remote profiles, shortcuts, progress, and offline-copy metadata use their existing JSON/UserDefaults stores. Passwords remain in Keychain.
- Remote comic downloads and sidecars live under `Caches/JamReader/RemoteComics/`; cleanup must respect active reader leases and matching records.
- Remote thumbnail files live under the independently bounded `Caches/JamReader/RemoteThumbnails/` cache.

Important invariants:

- Enable SQLite foreign keys for every connection.
- Public mutation APIs must resolve and validate `library_id`; integer row IDs are not cross-library identities. Internal indexing may use a row ID only when it came from the same library-scoped snapshot and transaction.
- Never write app metadata into a linked source folder.
- Never represent a persistence failure as an empty library.
- File deletion and matching database/cache-record deletion must be one coordinated operation.
- Keep remote server identity and normalized path in every cache/import key to prevent cross-server collisions.

## Dependency Boundary

Use Apple frameworks first, including UIKit, SwiftUI, Foundation, ImageIO, Security, and SQLite3. The current archive layer also has a native libarchive bridge; the repository vendors SMBClient, SWXMLHash, and epub.js. MuPDF is an optional local build input under `.mupdf/` or `MUPDF_ROOT` and must not be committed.

Do not add a dependency for a small convenience. A new dependency needs a concrete capability/performance benefit, active maintenance, acceptable license and binary size, and a clear ownership boundary.

## Where To Start

| Change | Start reading | Regression focus |
| --- | --- | --- |
| App tabs/navigation | `JamReader/App/AppRootTabBarControllerView.swift`, `JamReader/App/AppNavigationSupport.swift` | compact/regular width, state restoration, presentation |
| Library/import/index | `JamReader/Data/Libraries/`, matching feature ViewModel | restart persistence, security scope, scan counts, deletion |
| SMB/WebDAV/cache | `JamReader/Data/Remote/RemoteServerBrowsingService.swift`, adjacent stores/models | server/path isolation, cancellation, active lease, no-Range behavior |
| Reader/opening | `JamReader/ReaderKernel/ComicOpenPipeline.swift`, `JamReader/Features/Reader/ComicReaderViewModel.swift`, reader containers | paging, zoom, rotation, background resume, progress |
| Settings/preferences | `JamReader/Features/Settings/`, stores injected by `AppDependencies` | persistence, compact/regular navigation, destructive-action boundaries |
| Shared UI | `JamReader/SharedUI/DesignTokens.swift`, existing components | Dynamic Type, reduce motion, light/dark mode, compact/regular width |
| Formats | `JamReader/Core/Types/SupportedComicFormats.swift`, `JamReader/Data/Reader/ComicDocumentLoader.swift` | import/scan/open parity and format guard |
| Localization | `JamReader/Localizable.xcstrings`, `JamReader/InfoPlist.xcstrings`, `scripts/check_localizations.py` | all four languages and placeholder parity |
| Logging | `JamReader/Core/Logging/AppLog.swift`, `docs/logging-strategy.md` | privacy, useful failure context, no hot-path noise |

Known regression history and manual checks live in [`maintenance-pitfalls.md`](maintenance-pitfalls.md).

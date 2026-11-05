# JamReader Maintenance Pitfalls

This document keeps diagnostic entry points and regression checks for common failures. Historical symptoms do not mean the current version still has the fault. Code and tests define the current implementation; passing code checks and builds does not replace reproducing an issue on a physical device.

## 1. General Principles

See [project context](project-context.md) for data ownership, UIKit navigation/gesture boundaries, and the unified reader pipeline. See [development workflow](development-workflow.md) for build, test, and handoff requirements. This page only adds specific failure modes.

Investigate device issues against the actual symptoms. Simulator results alone cannot establish iPadOS background restoration, rotation, sheet gestures, or SMB/WebDAV network behavior.

## 2. Native Library Database

### 2.1 Do Not Restore Legacy Desktop Library Compatibility

The current architecture has removed the compatibility model built around legacy hidden library directories, `library.ydb`, `storageMode`, `mirrored`, and `Desktop Compatible`. Related code or copy usually indicates a regression.

Check:

```bash
rg -n "library\\.ydb|\\.jamreaderlibrary|storageMode|Desktop Compatible|Browse Only|mirrored" JamReader
```

Expected:

- Runtime code does not depend on these keywords.
- Documentation may mention them as history, but not as current feature paths.

### 2.2 Enable SQLite Foreign Keys on Every Connection

SQLite's `PRAGMA foreign_keys = ON` is a connection-level setting, not a database-level setting. Enabling it only during initialization is insufficient; later connections may still skip cascading deletes.

Symptoms:

- Deleting a comic leaves orphans in `comic_tags` or `reading_list_items`.
- Deleting a library does not also clean up `folders / comics / tags / reading_lists / scan_runs`.
- Organization, tag, and reading-list counts do not match their contents.

Requirements:

- Route all database writes through `AppLibraryDatabase.withConnection`.
- Run `PRAGMA foreign_keys = ON` after every connection created by `withConnection`.
- Apply the same rule to any new direct SQLite connection.

### 2.3 Integer IDs Are Not Safe Cross-Library Identities

Public models use `Int64` row IDs. Although these IDs are unique within their tables, callers can still pass a record ID from another library. `WHERE id = ?` alone cannot verify that the record belongs to the current library.

Requirements:

- Public state-write entry points must resolve the current `libraryID` from the contextual database URL and validate scope by `library_id`.
- Before writing tags, reading lists, or membership, verify that the comic/tag/readingList belongs to the same library.
- Private indexers may update or delete using row IDs obtained from the same library-scoped snapshot and transaction. Do not extend this exception to public APIs.
- `stable_id` is an internal UUID, not the public ID used by the current UI selection set.

Check:

```bash
rg -n "WHERE id = \\?|DELETE FROM [a-z_]+ WHERE id = \\?|UPDATE [a-z_]+.*WHERE id = \\?" JamReader/Data/Libraries
```

Trace the callers, SQL conditions, and transactions of each match. Search results alone do not prove correct isolation.

### 2.4 Database Read Failures Must Not Appear as Empty Libraries

Entry points such as `LibraryDescriptorStore.load()` must not swallow database errors and return an empty array. Otherwise, higher layers may interpret a read failure as no libraries and trigger incorrect initialization, overwrites, or misleading UI.

Correct behavior:

- The data layer throws the actual error.
- The ViewModel converts it into an alert or error state.
- A failure must not silently clear the library list.

### 2.5 Deleting a Library and Deleting Cache Are Separate Operations

Deleting a library removes its records, index, state, and derived assets. `LibraryStorageManager.deleteManagedLibraryFilesIfNeeded` only deletes app-managed/imported content; removing a linked library does not delete its external source directory. Deleting an individual comic is a separate flow that changes source files. `LibraryComicRemovalService` coordinates file isolation, database commit, and rollback on failure.

High-risk points:

- “Delete Cache” in Settings must not delete comics the user imported into local libraries.
- Deleting downloaded copies should remove matching cache metadata and refresh offline-copy state. Clearing reading history is not a substitute for cache maintenance.
- `Imported Comics` has a separate `importedComics` kind, but its files are still app-managed content, not remote cache.
- See [section 10](#10-cache-and-storage-settings) for cache accounting and trimming rules.

### 2.6 A New Library That Fails After Restart Usually Has a Root or Bookmark Persistence Problem

New libraries have worked in the current session but reported missing permission after restart. Check library records and root URL restoration first, not just UI navigation.

Requirements:

- An app-managed library root must be inside the app sandbox and reliably restorable from its library record.
- Linked folders must persist a security-scoped bookmark.
- Verify `rootPath`, `bookmarkData`, `kind`, and the actual file location together.
- After restarting the app, verify opening, importing into, and refreshing the new library at least once.

### 2.7 Names, Sandbox Paths, and Documentation Must Agree

The project has been renamed to JamReader. Renames often miss three groups of locations:

- Persistent directories such as `Application Support/JamReader` and `Caches/JamReader`.
- Bundle ID, display name, scheme, log labels, and UserDefaults keys.
- README, `.github/copilot-instructions.md`, `docs/README.md`, and check scripts.

Requirements:

- Do not migrate or delete user data just because of a rename unless a migration has been explicitly designed.
- Use the shared helper for new persistent paths; do not hard-code old directory names.

### 2.8 Local Library Regression Entry Points

Choose `LibraryScannerDatabaseTests`, `LibraryComicDeletionTransactionTests`, `LibraryComicRemovalServiceTests`, and `LibraryListViewModelPersistenceTests` according to the change. Add matching regression tests when adding or fixing persistence, isolation, rollback, or deletion logic. See [section 12](#12-minimum-regression-checklist) for manual scenarios.

## 3. Import Pipeline

### 3.1 Remote Import Is Not Offline Cache

Importing from SMB/WebDAV into a local library should follow this flow:

1. Download remote files to a temporary/staging location.
2. Have the import service copy or move them into the target library root.
3. Scan and index the new files in the local library.
4. Refresh the library list, comic counts, recent records, and target page.
5. Clean up temporary downloads.

Do not treat the presence of a remote offline cache as a completed local-library import. They have different data tables, lifecycles, and deletion entry points.

### 3.2 If Import Finishes but the Library Is Empty, Check Indexing First

When downloading finishes and the library exists but contains no comics, check:

- Were the files actually copied into the target library root?
- Is that root the one in the current library record?
- Did scanning/indexing run after import?
- Did the scan ignore the target file type?
- Did hidden-file rules, directory rules, a cancellation token, or a permission error stop the scan early?
- Did the UI refresh the snapshot and comic count for that library?

### 3.3 Folder Import Must Distinguish Image Comic Directories from Ordinary Directories

A directory made up mainly of image files is one complete comic, not an ordinary folder collection. Recursive scans must not split these directories into multiple entries.

Requirements:

- Recognize image directories before recursing through ordinary directories.
- Ignore hidden directories and dot-prefixed files.
- Also ignore legacy hidden compatibility directories and obsolete app junk directories.

### 3.4 If the UI Freezes During Import, Check Overlay Hit-Testing First

The UI has become completely unresponsive during SMB import. The cause was not the download itself: transparent regions of the full-screen import overlay window swallowed every touch.

First check overlay hit-testing in `JamReader/App/AppRootView.swift` and `JamReader/App/AppRootTabBarControllerView.swift`. See [section 8](#8-ui-hit-testing-and-transparent-layers) for the shared rules. Also verify that the underlying list, tabs, and overlay cancel button remain usable.

### 3.5 Import Results Must Refresh More Than the Current Page

Distinguish import progress from indexing results. `ImportedComicsImportService` indexes a batch after file transfer. On cancellation, it attempts compensating indexing if files have already reached disk. Do not rescan the whole library per file just to refresh counts, or present a copied file as successfully indexed.

Requirements:

- When indexing finishes, update both Library Home counts and the target Library Browser contents.
- Recent reading history, Continue Reading, special collections, and organization snapshots must not remain stale.
- For failed or partially failed imports, distinguish download, copy, and indexing failures in feedback.
- When opening the target library after a remote import, prefer the latest library descriptor and scanner results.

`ImportedComicsImportServiceIntegrationTests` covers batch indexing, cancellation compensation, target path boundaries, and name collisions.

## 4. Remote SMB/WebDAV

### 4.1 WebDAV Range Support Determines Streaming and Cover Prefetching

ZIP/CBZ is not friendly to sequential reads. Without Range support, reading a cover or page often requires downloading much or all of the file.

Current policy:

- WebDAV with confirmed Range support: allow ZIP/CBZ streaming and remote cover reads for supported formats.
- WebDAV with confirmed lack of Range support: disable remote cover reads and streaming; download the full file before opening. Existing local cache can still generate covers.
- When Range probing fails, `webDAVRangeRequestsSupported` currently allows an optimistic attempt. This is not confirmed Range support. Failed streaming opens report an error; do not assume every failure automatically falls back to a full download.
- SMB: random/chunked reads can improve remote reading, but concurrent cache tasks must still be kept from interfering with each other.

An SMB streaming reader connection may expire after the screen stays off for a long time. On a transport disconnect, expired session, or invalid file handle, `ManagedSMBRemoteFileReader` coalesces reconnect attempts, signs in again, connects to the share, opens the same path, and retries the original byte range once. It does not reconnect for permission, authentication, or path errors, or explicit cancellation. A changed file size after reconnection causes the read to be rejected, so the old ZIP index is not reused. Closing the reader must cancel reconnection and release new connections that arrive late. When a full ZIP copy has downloaded, full page reads prefer local data. These recovery steps must not rebuild the document or navigation stack, or reset the page number.

Do not download a full file from no-Range WebDAV just to show a cover.

### 4.2 Prefetch PDF Covers Conservatively

PDF cover fetching has risked freezing directories, especially when warming covers in child directories.

Requirements:

- The remote browser does not extract remote PDF covers directly. Both directory preview candidates and comic warming skip PDF. Existing local PDF copies may generate covers with CoreGraphics according to request policy.
- See [9.1](#91-remote-thumbnail-warming-must-have-a-budget) for directory inspection and cover-warming budgets.

### 4.3 SMB/WebDAV Browsers Must Hide Dot-Prefixed Files

The remote browser should hide:

- Dot-prefixed files and directories.
- Hidden directories left by this app or other comic apps.
- Unsupported ordinary files.

Reasons:

- System files should not clutter user directories.
- Unexpected files encountered while warming child directories can cause stalls or failures.

### 4.4 Local and Remote Covers Have Different Sources

`LibraryComicMetadataExtractor` finds and validates an image with the same base name in the local directory and prefers it as the cover. If no valid image exists, it falls back to the format's own extraction pipeline.

Remote `fetchDirectThumbnail` currently extracts from an image comic directory's `coverPath` or an archive. It does not look for a same-name image beside the archive. Do not describe local sidecar behavior as an implemented remote capability. See [9.4](#94-cover-quality-problems-usually-come-from-cache-size-and-display-mode-changes) for display-quality issues.

### 4.5 Remote Cache Must Have Active Leases

Cache cleanup, automatic trimming, and manual deletion must not delete cache files in use by the reader.

Symptoms:

- “Comic Unavailable” suddenly appears after opening a comic.
- All comics become unavailable after opening several in sequence.
- Cached comics in recent reading history fail to open after returning from the background, but work after restarting the app.

Requirements:

- Register an active cache lease when opening the reader.
- Release it when the reader is destroyed or switches comics.
- Automatic trimming skips files with active leases. Single-item deletion and batch cleanup in the same scope reject the operation and require closing the reader first.
- Remove corrupt cache records or records for missing files, and provide a retryable error.

### 4.6 Old Cache Can Look Like a Current Network Problem

WebDAV/SMB ZIP-opening failures have turned out to be corrupt old cache or stale path records. Do not check only the network protocol when a remote open fails.

Check first:

- Does the file referenced by the cache record exist?
- Do file size, mtime, and remote signature match the record?
- Is the cached file an incomplete download?
- After an open failure, was the bad record removed and the operation retried under the current remote policy?
- After manual cache deletion, were cache metadata and offline-copy state also cleared?

### 4.7 Remote Browsing State Is Presentation State, Not Business Truth

Remember the remote server page, current directory, sidebar collapse state, and list/grid mode. These states must not affect file opening, importing, or cache decisions.

Requirements:

- Browsing state may live in UserDefaults.
- Remote server configuration and credentials still use the existing JSON/UserDefaults/Keychain system.
- Do not mix remote browsing state into the local-library tables in AppLibraryV2.sqlite.
- Clear or ignore the corresponding browsing state when switching or deleting servers, or when credentials expire.

### 4.8 Thread and Semaphore Boundaries for Remote Reads

The project isolates types to `MainActor` by default, and `nonisolated async` also remains on the caller's actor. Without `Task.detached`, `@concurrent`, or a dedicated queue, code that appears to run in the background may all run on the main thread. SMB and WebDAV reader `read` calls also start on the main thread.

Requirements:

- Synchronous callbacks such as libarchive's must run on a dedicated `DispatchQueue` when they block waiting for remote reads. On the main thread, reads can never start and must time out. On the cooperative thread pool, reads likewise cannot start once all threads are occupied.
- Do not nest `withConnectedSMBClient`. Acquiring `smbClientSemaphore` while already holding it makes every request wait on another once concurrency reaches the limit. Image-directory comic downloads and recursive directory listings acquire connections per request in the inner layer.
- `AsyncSemaphore.wait` throws `CancellationError` on task cancellation without occupying a slot. Place the release `defer` after a successful `wait`, and distinguish cancellation from ordinary failure in callers.

## 5. Unified Reader Pipeline

### 5.1 Do Not Split Local and Remote Readers Again

All current entry points create a unified `ComicOpenRequest`, which `ComicOpenCoordinator` opens into a `ComicReaderSession` and `ComicDocument`. See [project context](project-context.md#reader) for the architecture entry point.

Requirements:

- Local libraries, recent reading history, remote cache, remote streaming, and opening after a full download all use the same `ComicReaderView`.
- Remote progress may still be written to JSON, but only through the unified state store adapter.
- Do not add a remote-only reader shell with its own page/layout/bookmark/progress state.

### 5.2 Opening Comic Stuck Until a Downward Swipe Indicates Layering or State Publication Problems

The document has opened successfully while the UI continued to show `Opening Comic`; images appeared only after a downward dismissal swipe or another refresh.

Check first:

- Was `ComicReaderLoadState.ready` published on the main thread?
- Is the opening fallback still above the document layer?
- Does the ZStack's `zIndex` place loading above ready content?
- Did a stale `Task` token let an old result overwrite the current ready state?
- Was the UIKit reader container created without SwiftUI recomputing its body?

Do not hide this with an extra refresh. The correct fix keeps the document layer reliably above the fallback once ready.

### 5.3 Background Restoration Must Not Release Reader Resources

The app may save progress and clear in-memory image cache when entering the background, but must not release the current document/source lease.

Symptoms:

- “Comic Unavailable” appears after returning from a while in the background.
- The reader exits automatically with a navigation-back animation.
- Cached comics in recent reading history intermittently fail to open, then work after restart.

Requirements:

- `didEnterBackground` only saves state and clears rebuildable cache.
- Release the security scope, remote reader, and document pageSource only when the reader deinitializes, switches comics, or explicitly closes.
- Do not automatically rebuild the navigation stack on background restoration.

### 5.4 Asynchronous Opening Must Use Request Tokens

Remote downloads, cache checks, document opens, and cover generation may finish after the user's next action. Stale tasks must not overwrite the current reader state.

Requirements:

- Generate a new token for each comic open.
- Check the token before writing back async results.
- Cancel old tasks when switching comics, closing the reader, or reopening it.
- Background cache completion must not reset the current page number.

### 5.5 Reading Progress Updates Must Reach Lists

After opening a comic from recent reading history or a library and changing pages, returning to the list must refresh the corresponding item.

Requirements:

- Trigger `onComicUpdated` after writing local progress.
- Recent reading history, Continue Reading, Favorites, and special collections must receive the same update event.
- Do not update only the reader's internal ViewModel.

### 5.6 Remote Cache Opening While the Local Library Fails Usually Indicates Divergent Source Resolution

A comic has opened from offline cache in the remote browser while the same comic from the local library stayed at `Opening Comic`. This usually indicates inconsistent readable-source resolution between the local-library and remote-cache entry points, rather than a decoder problem.

Requirements:

- Every entry point constructs `ComicOpenRequest`.
- `ComicOpenCoordinator` resolves file URLs, security scope, cache leases, and reader state scope centrally.
- No entry point may bypass the coordinator to create `ComicDocument` directly.
- Validate a local library record's `relativePath` together with its library root. Do not fall back to a remote cache URL.

## 6. Reader Layout, Gestures, and Rotation

### 6.1 Zoom on the First Page Turn Usually Indicates Zoom or Layout Initialization Order

Symptoms:

- On the first horizontal page turn after opening a comic, the next page appears enlarged.
- It snaps back to normal after the turn.

Check:

- Was minimum zoom calculated using final bounds before the new page became visible?
- Was zoomScale reset during cell/page reuse?
- Were `contentInset` and `contentOffset` set before the imageView frame was final?
- Did delayed layout overwrite the initial values?
- After cancelling an incomplete page turn, remounting the current page must preserve the user's zoom, not reset it as a new page.

Existing regression coverage:

- `ReaderSpreadWillDisplayActionTests` covers preserving the viewport when a cancelled page turn returns to the current page.
- `ReaderViewportLayoutActionTests` covers waiting for the target viewport, resetting after a real size change, and preserving zoom when size is unchanged.

### 6.2 If Portrait-to-Landscape Rotation Breaks Layout, Check Window Bounds and Container Rebuilding

Rotation from portrait to landscape has left a black reader on the left and exposed the comic list on the right. The reader presentation/container failed to keep filling the window during rotation.

Requirements:

- Do not use `UIScreen.main.bounds` as the real viewport for iPad multitasking or rotation.
- Prefer the actual bounds of the current reader/collection view over global screen dimensions.
- When the viewport changes, update all cached pages through `synchronizeCachedControllerViewports(to:)`, not just the current page.
- Pages should wait for the target viewport. Reset layout only on a real size change; preserve user zoom when size is unchanged.
- Do not rebuild the reader session, document, or source lease for rotation.
- If opening in landscape works but rotating from portrait breaks layout, focus on the rotation lifecycle, not document loading.

A brief flicker is acceptable. Exposing the underlying list or leaving half the screen black is not.

### 6.3 The Thumbnail Sheet Must Use a High-Performance List

The current thumbnail sheet uses a UIKit collection view through `ReaderThumbnailBrowserUIKitContainer`. Preserve list reuse and prefetching during maintenance.

Requirements:

- `ReaderThumbnailBrowserMetrics` uses two columns, or three on iPad/wide containers, and adjusts column width and spacing to the container width. Wide layouts also support left/right sections.
- Define how top information scrolls with the list. Do not let sheet gestures steal list scrolling.
- A crash or reader exit on the second thumbnail-sheet open usually indicates a conflict in sheet identity, dismiss binding, or reader presentation state.

### 6.4 Sheet Scrolling and Swipe-Down Dismissal Can Compete for Gestures

The thumbnail sheet has prevented list scrolling and dismissed immediately on a downward swipe.

Requirements:

- Use `.presentationContentInteraction(.scrolls)`.
- Let the UIKit collection view own scrolling. Do not wrap it in a SwiftUI ScrollView that competes for gestures.
- An oversized fixed header can hide the list. Let top content scroll with the list or compress it.

### 6.5 The iPadOS System Top Bar Can Obscure Reader Chrome

When the reader UI is visible, the back button can overlap the system clock.

Requirements:

- Top chrome uses the window safe area, not only SwiftUI safeAreaInsets.
- After the full-screen reader uses `.ignoresSafeArea`, its controls still need safe-area padding applied manually.
- Resolve the window safe area again after rotation.

### 6.6 Vertical Continuous Reading Must Not Reuse Swipe-Down Dismissal

When the vertical list and swipe-to-dismiss share the vertical axis, ordinary reading can be mistaken for an exit.

Requirements:

- Keep swipe-down dismissal for paged reading; use a one-finger rightward swipe for vertical continuous reading.
- Dismissal gestures must first pass a strict direction check. Do not decide to take over after scrolling has begun.
- Zoomed content and scroll views that can still pan in the dismissal direction take priority. Bottom horizontal thumbnails must not trigger rightward dismissal.
- Temporarily lock the current reader scroller when interactive dismissal starts, and restore it immediately on cancellation or completion.

### 6.7 Vertical Reading Width and Zoom Must Share One Layout Owner

At 1×, vertical pages use the full reader viewport width, without added horizontal safe-area insets or a fixed iPad width cap. Zoom the collection layout as a whole and preserve the touch anchor; do not nest independent scroll views inside reusable cells. After zooming, the collection handles panning on both axes and blocks rightward dismissal. A viewport size change returns to 1× and reanchors the current page.

Page spacing persists through the shared `ReaderDisplayLayout.pageSpacingEnabled`, is on by default, and exposes its setting only in vertical continuous or double-page layouts. Hiding the setting must not clear its saved value. Turning it off only sets spacing between adjacent comic pages to 0; it must not change page width, the outer viewport, or the gesture owner.

Thumbnails may serve only as placeholders while full pages load. Once a cell shows a full image, preview notifications must not downgrade it even if its cache is evicted. A cell becoming visible after prefetch cancellation must restart full-image loading. Memory warnings cancel only tasks for invisible pages. Late results from cancelled tasks must not clear replacement requests or update pages. `VerticalReaderPageLoadingTests` covers these loading and reuse boundaries.

### 6.8 Vertical Reading Uses a Right-Side Thumbnail Track for Quick Navigation

Vertical continuous mode hides the bottom horizontal thumbnail list and keeps only a compact page-number entry point. The right-side track reserves a position for every page across the whole comic, using a single drawing layer for a continuous thumbnail strip. Normal thumbnail widths use fixed tiers: 6/10/16/24 pt on iPad and 4/8/12/18 pt on iPhone. Choose the widest tier that fits the current page count. Normal items use a 2:3 aspect ratio and about 1 pt spacing. Track height fits its content, up to 2/3 of the current reader viewport height, constrained by the safe area and toolbar clearance. If the narrowest tier still does not fit, compress item height and spacing while keeping every page position. The original item under the finger enlarges directly and extends left; the two pages before and after it deform progressively with distance. Focused width is capped at 38/30 pt respectively.

The magnified region computes spacing from the actual deformed heights of that same set of items, pushing the list above the focus upward and the list below it downward. Clearance at both ends of the track must cover the full magnification displacement; neighboring pages must not clip or overlap even in long comics. The whole track uses a faint translucent black background. Sidebar thumbnails are prepared for the largest magnified item and display scale (112 px on the longest edge for a typical iPad at @2x), with target resolution updated when the viewport changes. The track draws only these small images; even a completed central preview is downsampled before being added to the track. The floating page number keeps a fixed gap between its right edge and the focused thumbnail and reserves digit width for the total page count. Only the current page uses a short numeric transition; the total count is subdued. Reduce Motion disables number scrolling and scaling.

During dragging, show a large preview of the focused page in the viewport center, with width capped at 1/2 of the viewport and height following the image's actual aspect ratio. If it exceeds the height available within the safe area, scale it down proportionally. The background and border fit the image without black bars above or below. The preview does not receive touches. When showing it, read both the shared preview cache and the thumbnail pipeline's target-size cache synchronously and choose the highest-resolution existing preview for that page. If either cache entry is evicted, reuse the other clear image rather than first falling back to a small track image. If cache resolution is insufficient, reuse the focus loading task after a dwell to reach display resolution. Do not show a late image from the previous page. Releasing closes the preview and commits one page jump; cancelling closes it and keeps the original page.

The thumbnail strip first reuses reader preview cache with sufficient resolution. If the cache is too small, use `ComicPageDataSource.localDataForPage` to fill it from the local comic or existing remote-page cache; keep the small image only when local data cannot supply a better one. Do not upscale pixels to pretend an image is sharp, and do not let a late small image replace a prepared sharp thumbnail. This entry point must not download remote pages or write the whole comic's decompressed data into the full-page cache. A streaming ZIP whose background download has completed may read its local file directly; page turns check for changes to the local copy and refresh it. Scanning, extraction, and ImageIO decoding run page by page in the background. UIKit asynchronous thumbnail preparation starts from MainActor, with at most 12 small images batched back to the UI at a time. Cancel when closing or changing documents; late results must not enter the new track. Allow focus preview loading only after a short delay. Prepare only small images when not dragging; during dragging, prepare for the central preview size and screen scale. Sweeping quickly across the track must not continually trigger remote reads, extraction, or image decoding.

UIKit owns track gestures. During interaction, block rightward dismissal; cancellation returns to the original page. The track must stop receiving touches when chrome is hidden or the reader is locked. Track size and position use the current viewport and window safe area, not `UIScreen.main.bounds`.

## 7. Navigation and Transitions

### 7.1 SwiftUI Navigation State and UIKit Transitions Must Not Compete for Control

The project has seen automatic reader exits, navigation returning to the root, and the reader being torn down after opening the thumbnail sheet. Many of these were navigation and presentation states overwriting each other, not document problems.

Requirements:

- A shared presentation coordinator manages reader opening and closing.
- Do not let multiple ViewModels each own the source of truth for whether the current reader is visible.
- `onDisappear` does not mean the user closed the reader, especially during sheets, rotation, or background restoration.
- Do not reset root tabs or the navigation stack on background restoration unless actual structural damage is detected.

### 7.2 Hero Animations Depend on Source Frames That Can Expire After Background Restoration

After a long time in the background, a hero animation may degrade into expansion from the top-left corner. This usually means the source view/frame is stale.

Requirements:

- Recapture the source frame after backgrounding or a page refresh. On close, get its live position from `HeroSourceRegistry`; a frame saved on open is stale after rotation or a window change.
- If no stable source frame exists, fall back to an explicit bottom-up or fade transition rather than a fake `(0,0)` frame.
- Do not let an old screenshot or preview image cover a newly opened comic. After the reader advances to the next comic, the cover and source belong to the previous one: stop using them when `ReaderHeroContext.isShowingOpenedComic` is false.
- Only `ReaderHeroView` flies. Do not capture and scale the entire reader again: shrinking a screenshot with black bars and toolbars back into the cover produced the previous black card. New reading modes must implement `ReaderHeroPageSource` and call `onFirstPageShown` when the first page appears.
- Restore hidden covers. SwiftUI covers reappear only on their next update, so keep the flying view for one or two extra frames on close. UIKit cell reuse restores opacity through `unregister`.

### 7.3 Repair Root Tabs Conservatively

Blank tab-bar items have appeared after iPadOS background restoration. Root-tab repair is necessary, but it must not treat normal navigation/presentation as damage and reinstall it.

Requirements:

- Repair only when the tab controller count or identity is clearly wrong.
- Repair must not close a visible reader or sheet.
- Keep repair in didBecomeActive as small as possible.

### 7.4 Sheets and Reader Presentation Must Not Share Implicit Dismissal Signals

A reader exit after opening the thumbnail sheet a second time usually means sheet dismissal, reader dismissal, and navigation pop share a state source.

Requirements:

- Closing thumbnail, metadata, or page-jump sheets affects only that sheet.
- Reader dismissal must take the explicit path through the reader presentation coordinator.
- `dismiss()`, `onDisappear`, and interactive sheet dragging must not directly clear the current reader request.
- A SwiftUI sheet in a UIKit presenter has an independent hosting tree. Controls needing immediate feedback must observe the state owner inside the sheet, not merely receive a value snapshot from the moment it opened.
- Run a physical-device regression check for opening a sheet a second time.

## 8. UI Hit-Testing and Transparent Layers

### 8.1 Full-Screen Overlay Windows Are Dangerous by Default

Any independent `UIWindow` placed above the main window needs an explicit hit-test policy. Even transparent SwiftUI regions may return an internal hosting view and swallow touches across the screen.

Requirements:

- Overlay windows use passthrough `hitTest`.
- Transparent backgrounds must not receive touches.
- Only actual interactive elements may receive touches.
- Physical-device testing must exercise the underlying page while the overlay exists.

### 8.2 `Color.clear` Does Not Mean Noninteractive

`Color.clear` can still create a hittable SwiftUI view, especially with `.background`, `.overlay`, `GeometryReader`, or preferences.

Requirements:

- Measurement-only layers: `.allowsHitTesting(false)`.
- Observer-only layers: `.allowsHitTesting(false)`.
- Placeholder spacers: `.allowsHitTesting(false)` and `accessibilityHidden(true)`.
- Use `.contentShape` only for actual tap targets.

### 8.3 Loading Overlays Need a Cancel Action

If the UI shows downloading/opening during a remote open or download, cancellation must be available. Otherwise a stalled network leaves users with no option but to kill the app.

Requirements:

- Opening/downloading screens such as `ReaderOpeningStateView` provide Cancel.
- Cancel must cancel the request token and underlying download task.
- After cancellation, old ready/error results must not write back into a new reader.

## 9. Performance and Memory

### 9.1 Remote Thumbnail Warming Must Have a Budget

Directory inspection and cover warming are separate pipelines. Do not combine them into waiting for every cover in the current directory to cache before checking child directories.

Requirements:

- `RemoteServerBrowsingService.listDirectory` inspects child directories during listing to identify image comics and a limited set of preview candidates. Keep inspection timeouts and the mechanism that stops inspection after consecutive failures.
- `RemoteServerBrowserView` warms comics in the current directory by visible range: the primary range allows remote extraction, the secondary range uses cache only, and PDF is excluded.
- Folder-card preview requests use `allowsRemoteFetch: false`; they must not download extra comics to fill the card. See [4.1](#41-webdav-range-support-determines-streaming-and-cover-prefetching) for no-Range rules.
- Keep concurrency and range limits. Cancel or replan tasks on scrolling, directory changes, display-mode changes, or reader opening.
- Remote read count for a single cover must not grow with page count: remote ZIP covers read only the selected page's local file header.

### 9.2 Heavy Remote I/O Must Not Slow the Main Thread

Common causes of dropped UI frames during remote-folder import:

- A `@MainActor` ViewModel performs heavy loops or synchronous file operations.
- Progress callbacks trigger main-thread refreshes too often.
- Batch cover generation and downloads compete for I/O.

Requirements:

- Run downloads, scans, file copies, and cover generation in the background.
- MainActor only publishes state.
- Throttle progress publication; do not refresh the UI for every chunk.
- Batch tasks support cancellation.

### 9.3 Background Memory Optimization Must Not Break Reader Sessions

`AppMemoryPressureCoordinator` clears rebuildable image cache. See [5.3](#53-background-restoration-must-not-release-reader-resources) for the shared reader-resource lifecycle rules. Restoration should preserve the page number, paging capability, and current navigation state.

### 9.4 Cover Quality Problems Usually Come from Cache Size and Display-Mode Changes

Folder covers in the SMB browser have shown low resolution, black bars, and inconsistent stretching when switching between list and grid.

Requirements:

- List and grid must not share a final bitmap that is too small.
- Cache keys must include the necessary target size or quality tier.
- Low-resolution placeholders may appear first, but must be replaced when high-resolution results arrive.
- Use a consistent cover-cropping policy to avoid black bars when the same cached image appears at different aspect ratios.

### 9.5 Image Decoding and Cache File Locks Must Stay off the Main Thread

A brief stall on a page turn or occasional pauses while scrolling remote lists often mean decoding or lock waits remain on the main thread.

Requirements:

- `ReaderPagedImageDecoder` finishes decoding paged-mode pages inside the loading task. `UIImage(data:)` defers decoding until Core Animation first draws it; handing it directly to `UIImageView` leaves decoding on the main thread during the page-turn animation.
- After eager decoding, all loaded spreads occupy decoded-image memory. `controllerRetentionRadius` sets the limit; a memory warning retains only the current spread.
- Load the current spread first. Start neighbor warming and data prefetching only after it succeeds or fails. Queue neighbors by distance, with at most 2 fetching and decoding concurrently to bound the initial peak. A queued neighbor that becomes the current spread bypasses the queue; cancelled tasks must return their slots.
- `ZoomableImagePageView` computes fit zoom from its own actual bounds, not an internal scroll view that has not laid out yet. It refits after a size change; already zoomed content is only clamped to the valid zoom range.
- Summary scans and trimming may hold `RemoteThumbnailDiskCacheStore`'s `fileMutationLock` for a long time. Cache generation reads on the main thread use only `generationLock`. Reading and decoding disk thumbnails do not hold the file lock; callers discard late results by generation.

## 10. Cache and Storage Settings

### 10.1 Display Cache Size Using Actual Disk Usage

Large differences between app usage in iOS Settings and the app's own totals usually mean only logical file size was counted, excluding APFS allocated size, temporary files, or incomplete cache.

Requirements:

- Cache management shows actual usage.
- Show and delete “Other cache data” separately.
- Show a deletion-in-progress state during cache deletion so the UI does not appear frozen.
- After deletion, refresh cache metadata, offline-copy state, and usage totals.

### 10.2 Cache Limits Are Policy, Not a Strict Synchronous Guarantee

`RemoteCachePolicyStore` presets limit both comic count and total bytes. Automatic trimming must also account for active leases, explicit offline copies, and in-progress downloads, so usage may temporarily exceed the policy limit.

Requirements:

- Default: 1G.
- The UI displays MB.
- Do not delete active reader files.
- Automatic limit trimming does not delete offline copies the user explicitly saved. Only explicit downloaded-copy cleanup deletes them.
- Stop automatic trimming if offline-protection records cannot be read or have not finished restoring. Do not interpret failure as no copies needing protection.
- Do not count incomplete files as normally openable cache.

## 11. Comic Formats and Covers

`SupportedComicFormats` owns runtime extension policy; README owns the product capability list. This section records only format behavior prone to regressions.

Maintenance notes:

- Archive cover reads need timeouts and error isolation.
- See [development workflow](development-workflow.md#build-and-static-checks) for PDF/EPUB engine selection. A successful MuPDF open uses the image-sequence reader. The EPUB web fallback has its own reading location and page interactions; do not assume both share all viewport behavior.
- See 3.3 for image-directory recognition and 4.2–4.4 for PDF warming and same-name cover sources.

## 12. Minimum Regression Checklist

Choose relevant scenarios by the change boundary. Do not describe manual checks that were not run as passed.

The change-type matrix and commands in [development workflow](development-workflow.md#validation-by-change-type) govern automated validation. This section only adds manual checks for high-risk scenarios.

Local libraries:

- Create a library and restart the app; the library still opens.
- Create a library, import comics, and restart; the comics still open.
- Import a single ZIP from SMB; the library does not appear uninitialized and the comic is visible.
- Import a comic folder from SMB; image directories are treated as single comics.
- The underlying UI does not freeze during remote import; target-library counts and contents update after indexing.
- Library deletion and cache deletion do not affect each other's data.
- Deleting a comic also reduces tag and reading-list counts. Removing a library cleans up its records and derived assets while preserving the linked source directory.
- Writes reject comic/tag/reading-list IDs from another library. An unreadable database shows an error rather than an empty library.
- Returning after reading refreshes the page number in recent reading history.

Remote browsing:

- SMB/WebDAV browsers hide dot-prefixed files.
- Directory covers do not freeze because of PDFs or abnormal child directories.
- No-Range WebDAV does not read remote covers or stream opens; existing local covers can still display.
- Range-enabled WebDAV ZIPs can stream; background download of full copies follows user settings.
- Deleted cache no longer appears cached.
- After deleting a bad cache record, reopening the same remote comic fetches it again under the current network policy.
- After closing and reopening the app, the remote server page, current directory, and display mode restore as expected.

Reader:

- Local libraries, recent reading history, remote cache, remote SMB, and remote WebDAV all open.
- Opening/Downloading screens have a cancel button.
- After a stay in the background, the reader neither exits automatically nor shows “Comic Unavailable”.
- Opening in portrait and rotating to landscape does not expose the underlying list or leave half the screen black.
- The first page turn has no temporary enlargement.
- The thumbnail sheet works on both the first and second open.
- Remote-cache and local-library entry points use the same reader pipeline when opening the same file.

Overlay/navigation:

- During remote import, the underlying UI still scrolls and responds to taps.
- Import overlay buttons still respond to taps.
- Background restoration does not add blank tab-bar items.
- A missing hero source frame does not cause an incorrect expansion from the top-left corner.

## 13. When to Refactor Instead of Adding More Patches

Stop and clarify responsibility boundaries if any of these occur:

- The same bug has been patched in 3 or more lifecycle callbacks.
- Fixing reader opening causes regressions in the thumbnail sheet, navigation stack, or background restoration.
- The same state is fixed separately for local and remote paths.
- Cache deletion, import, and reader opening interfere with one another.
- The UI only recovers after a refresh, downward swipe, or rotation.

These symptoms usually indicate scattered sources of truth or stale async results overwriting current state. Adding more refresh tokens, delays, or `DispatchQueue.main.async` calls often expands the regression surface.

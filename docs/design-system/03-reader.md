# Reader

## Preserve Unchanged (Outside Design Scope)

- **Bottom thumbnail navigation list in paged reading**: `ReaderBottomBar` (`ReaderThumbnailScrubber`, item enlargement and lift, floating page preview, page-number capsule below).
- **Right-side thumbnail navigation list in vertical continuous reading**: `ReaderVerticalThumbnailRail` (track, drag preview, page jump on release, compact page-number entry).

Preserve all positions, dimensions, spacing, thumbnail styles, animation, visibility, touch handling, and page-jump behavior. They still reference some `Spacing` and `AppFont` values; keep shared values unchanged, or isolate them as private component constants before changing shared tokens. Nearby tools and their animations must not move or squeeze them. See [ProtectedNavigation](components/ProtectedNavigation/README.md) for static illustration values.

## Tool Layout

| Part | Current interface | Component rules |
| --- | --- | --- |
| Top bar | Back · title · [Bookmarks · Aa · ⋯]; no page number | [ReaderTopBar](components/ReaderTopBar/README.md) |
| Display settings | Bottom system sheet at compact width, popover at regular width; only effective controls appear | [ReaderDisplayPanel](components/ReaderDisplayPanel/README.md) |
| More | Page actions and management for This Comic; local excludes deletion, remote has only Info | [ReaderMoreMenu](components/ReaderMoreMenu/README.md) |
| Page number and jumping | Paged bottom page-number capsule and vertical compact page-number entry open `ReaderPageJumpOverlay` | Protected components |
| Preparing to read / cannot open | Shares the cover destination with transitions; loading feedback and recovery actions depend on state | [ScreenRemoteActions](components/ScreenRemoteActions/README.md) |

No page uses the cross-comic navigation capsule. See [implementation decisions](05-batches.md#reader) for why.

## Behavior Contract (No Proposal May Change It)

[Design requirements section 5](../design-requirements.md#5-comic-reader-protected-and-editable-areas) owns the full contract for paging, vertical reading, dismissal, zoom, tool visibility, track page jumps on release, cancellation, progress, and bookmarks. Layout changes must not alter these behaviors or data boundaries. Handle display-panel and format capabilities using the table below.

## Display-Panel Control Visibility

| Control | Paged · narrow | Paged · wide | Vertical | PDF / EPUB rendered pages |
| --- | --- | --- | --- | --- |
| Reading Mode | ● | ● | ● | — |
| Single Page / Double Page | — | ● | — | — |
| Spread Order | — | ● with double pages | — | — |
| Show First Page Alone | — | ● with double pages | — | — |
| Fit Mode | ● | ● | — | — |
| Page Spacing | — | ● with double pages | ● | — |
| Rotation (This Reading Only) | ● | ● | — | ● |

PDF / EPUB rendered pages use a fixed single-page layout but support rotation. EPUB web mode does not offer these image-layout controls. `ReaderDisplayPanelControls` and document capabilities jointly determine implementation.

## iPhone Duo

Window width determines single/double-page availability and panel form. Protected navigation tiers follow the separate [environment adaptation rules](06-iphone-duo.md#protected-navigation-lists--environment-adaptation-only). Single-page display in a narrow window does not overwrite double-page preference. See [environment adaptation not yet connected](05-batches.md#environment-adaptation-not-yet-connected) for actual gaps in crease and camera geometry; static mockups are not implemented capabilities.

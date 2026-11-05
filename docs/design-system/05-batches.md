# Implementation Decisions and Capability Limits

This page keeps differences between implementation and static mockups, with reasons. Git retains batch tasks, acceptance logs, and old attempts. Component READMEs own page rules; see [development workflow](../development-workflow.md#validation-by-change-type) for validation requirements.

## Library and Import

| Difference | Implementation and reason |
| --- | --- |
| Icons and text in the selection bottom bar | Uses the system bottom toolbar; iPhone does not show text below every icon, avoiding a separate button strip that cannot adapt with system bars. See [SelectionBar](components/SelectionBar/README.md) |
| Search and breadcrumb placement | Search uses system-default visibility; subfolder breadcrumbs sit at the top of content after search. Always-visible search or a large-title subtitle collapses the large title early when pushing/replacing the navigation stack, so the mockup's position before search was not adopted |
| All in the home summary | Uses a reading page grouped by library, without reusing single-library collection search, selection, or batch actions; those operations are scoped to one library database and cannot be applied across libraries. See [ContinueReading](components/ContinueReading/README.md) for scope |
| Summary covers | `LibraryContinueReadingViewModel.coverURL` only checks derived cover files and does not extract on demand for other libraries; missing covers show placeholders |
| In-place reauthorization | The library service has no such entry. Library Info explains access failure and retained records without a nonfunctional button |
| Import results and cancellation | Import counts include reused files and cannot separate newly added / already existing. Scanning and ComicInfo metadata import have no UI cancellation path. See [TaskBanner](components/TaskBanner/README.md) for actual feedback and cancellation entries |

## Remote and Storage

| Difference | Implementation and reason |
| --- | --- |
| Remote-directory title | Keeps an inline title. The UIKit collection view is not connected to large-title collapse; breadcrumbs, counts, and sort sit in a fixed location bar below the title |
| Remote-import target and counts | `RemoteImportOptionsSheet` selects only a library and writes to its root; subdirectories are listed only after import starts, so no recursive total is available beforehand. Starting from a directory row may also lack an immediate-child count; do not invent counts or a target-subfolder picker |
| Downloading / failure badges | `StatusBadge` provides both states, but remote lists do not connect them per comic. Save Offline Copy uses a bottom task card and result notice, currently without a cancel button; component capability is not page capability |
| Download progress while preparing to read | The callback provides only a fraction, so show a percentage, not downloaded / total bytes. See [ScreenRemoteActions](components/ScreenRemoteActions/README.md) for loading and failure-page rules |
| Edit Server on the failure page | Saving closes the reader and returns to the directory. The original open request holds the old configuration; retrying on that page would keep using old settings |
| WebDAV form | Keeps separate Address, Port, Server Path, and Start Folder fields rather than the static mockup's single URL / path input |
| Storage totals | Local user-file totals cover only the default Imported Comics library; other app-managed libraries have no size accounting. The usage bar is not the total for all libraries or the whole app |
| Offline notice | `NetworkStatusMonitor` reflects only the system network path; an available network does not prove NAS reachability, and actual access may still fail |

Offline Shelf no longer has a whole-server clear entry, but the old `RemoteOfflineShelfViewModel.clearDownloadedCopies` method remains without callers. It clears history and the remembered location; do not reuse it for a new cleanup entry. See [deletion, removal, and cleanup](../design-requirements.md#deletion-removal-and-cleanup) for the effects of existing cleanup entries.

## Reader

| Difference or decision | Reason and boundary |
| --- | --- |
| Solid display-panel background | Glass over colorful comics reduces control readability; compact windows use a system sheet, regular windows a popover. See [ReaderDisplayPanel](components/ReaderDisplayPanel/README.md) |
| One-step bookmark replacement at the limit | Avoids presenting another confirmation while a system Alert is closing; replace in one write, not delete then add. See [reader requirements](../design-requirements.md#5-comic-reader-protected-and-editable-areas) for count and behavior |
| Display controls appear only when effective | Page Spacing has no effect on a single page; Fit Mode keeps Original, and rotation keeps a reset action afterward. See the [control table](03-reader.md#display-panel-control-visibility) for visibility |
| This Comic section title | The title is not shown when the first item is a system `ControlGroup`; keep the separator without drawing a custom menu |
| Cross-comic navigation capsule | `ReaderContextNavigator` is defined but unused by pages; no entry was added for the static mockup. Local cross-comic reading keeps edge taps |
| Current / Locate in the thumbnail overview | Current scrolls back to the page being read and resets the Quick Jump page number; Locate scrolls to the page selected in Quick Jump. Neither commits reading position; do not merge them because their names are similar |

See [motion](00-foundations.md#motion) for transition visuals and [transition maintenance](../maintenance-pitfalls.md#72-hero-animations-depend-on-source-frames-that-can-expire-after-background-restoration) for source-frame and page-handoff constraints. See [performance maintenance](../maintenance-pitfalls.md#95-image-decoding-and-cache-file-locks-must-stay-off-the-main-thread) for loading order, decoding, and cache-lock rules; do not repeat fix logs here.

## System Adaptation

- `AdaptiveSplitShell` hands off the same page controllers to avoid rebuilding navigation on width changes. The sidebar uses system-default width; see [iPhone Duo](06-iphone-duo.md) for window and restoration rules.
- Compact home and sidebar home each have an instance. Only the visible one handles one-time events such as import completion, pending library focus, and Add Server, avoiding duplicate navigation from both homes.
- High toolbar visibility priority starts at iOS 27.0. System overflow menus, Select / Done symbols, horizontal-only Select All, container margins, concentric corners, and crease queries start at iOS 27.1. This preserves bar appearance on earlier systems; ordinary iPhone / iPad also use these behaviors at the corresponding versions.
- The Add Comics sheet disables vertical toolbars from iOS 27.1 to leave width for cards; form sheets keep the system default. A Device Hub comparison of both outer-display presentations is still missing. Do not record the current choice as visually accepted.

## Environment Adaptation Not Yet Connected

These remain [iPhone Duo design rules](06-iphone-duo.md#reader), not existing capabilities. Do not mark them implemented merely because the redesign is complete:

- The reader does not query the outer camera's permanent `.occlusion` reserved region.
- Double pages are not aligned to the crease or placed on separate sides when half-folded.
- The top bar and page-jump overlay do not split by or avoid half-folded regions; the unused cross-comic navigation capsule also lacks this adaptation.
- The protected bottom list and right-side track have no half-folded region constraints. Existing tiers and behavior continue to follow [protection constraints](components/ProtectedNavigation/README.md).
- `FoldSplitGridMetrics` is used only for library and remote-directory grids; the thumbnail overview does not use even columns across the crease.

Device acceptance checks for the inner display, half-folded posture, split view, and continuity while opening/closing still need to be added. State handoff in unit tests does not replace device behavior.

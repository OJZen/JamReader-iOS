# Information Architecture and Flows

See [InformationArchitecture](components/InformationArchitecture/README.md) for the overview diagram. The three top-level areas are Library, Remote, and Settings. The reader opens full-screen and returns to the original location and group on exit.

## Primary Navigation

| Area | Regular-width sidebar | Contents |
| --- | --- | --- |
| Library `books.vertical` | Continue Reading (according to settings) · My Libraries · current library's collections | Local libraries, import, organization |
| Remote `server.rack` | Offline Shelf · Saved Folders · Servers | SMB / WebDAV, offline copies |
| Settings `gearshape` | General · Reading · Library · Storage | Global defaults and storage management |

Compact width uses single-column navigation. See [window adaptation](06-iphone-duo.md) for window changes and sidebar restoration.

## Entry Placement and Page Reuse

Keep one primary visible entry for the same action on a screen. Long press, swipe, and keyboard interactions may reuse it. Deduplication must not leave only hidden gestures. Treat an iPad sidebar and content area visible together as one screen.

| Feature | Current entry |
| --- | --- |
| Add | Either toolbar [+] or the empty-state button opens the same [Add Comics sheet](components/ScreenAddComics/README.md) |
| Import within a library | Root and subfolder ⋯ → Import Here… → File / Folder; uses the current library and folder |
| Import Comic Info | ⋯ → Import Comic Info…: choose scope and Fill Empty Fields / Overwrite Existing Fields policy; multiselect uses the selected scope directly |
| Refresh and scan | ⋯ → Refresh & Scan (This Folder / Entire Library); see [TaskBanner](components/TaskBanner/README.md) for progress |
| Recently Added Period | Settings → Library and the Recently Added page share one preference |
| Sort / View As | Local sort is to the right of the Comics section title; remote sort is in the location bar; Grid / List is in ⋯ |
| Continue Reading | See [ContinueReading](components/ContinueReading/README.md) for placement and scope |
| Navigate up | System back and tappable breadcrumbs; local breadcrumbs sit at the top of content after search, remote breadcrumbs in a fixed location bar |
| Maintenance records and library management | Library content page ⋯ → Library Info; home-page long press reuses Rename, Info, Remove / Delete actions |
| Comic management | [MoreMenu](components/MoreMenu/README.md); local ⋯ / long press share one menu, with swipe shortcuts from it |
| Server browsing | One Browse Files action in server details opens the last location, or Start Folder if none is recorded; use breadcrumbs to return to root |
| Server shortcuts | Saved Folders / Offline Shelf in the This Server shortcut area share pages with Remote home, scoped to current / all servers respectively |
| Download cleanup | Server management cleans the current server; Settings → Storage cleans all; Offline Shelf keeps single-copy removal without a whole-server clear action |
| Reader tools | [Top bar, display panel, More menu](03-reader.md#tool-layout); exact page jumps still use the protected page-number entry |

## Key Flows

See [key workflows](../design-requirements.md#4-key-workflows) for business steps, cancellation paths, and completion criteria. See [implementation decisions](05-batches.md) for differences between static mockups and data capabilities. Do not add a second import, reading, or task flow.

## Deletion, Removal, and Cleanup

Confirmation copy must state [deletion, removal, and cleanup consequences](../design-requirements.md#deletion-removal-and-cleanup). See [ConfirmDialog](components/ConfirmDialog/README.md) for presentation rules.

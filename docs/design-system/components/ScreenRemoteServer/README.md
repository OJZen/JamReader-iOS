# ScreenRemoteServer

Server details and remote directories.

## Server Details
- Header: name, protocol, address; only one primary Browse Files button, opening the last location (Start Folder if none is recorded). Use breadcrumbs to return to root; do not add a separate Browse from Root button.
- Continue Reading uses the ContinueReading component with that server's reading history; remove one entry through long press.
- This Server shortcuts: Saved Folders, Offline Shelf. Do not repeat them in the menu.
- ⋯: Edit Server · Clear Reading History · Clear Downloads on This Device (preserves history, reuses server-management cleanup) · Delete Server.

## Remote Directory
- Inline title is the folder name, with Server › Path breadcrumbs and no search field. See [implementation limits](../../05-batches.md#remote-and-storage) for the title decision.
- Pin button: Save Folder / Unsave Folder (solid when saved). Sort sits at the right of the status row (Name / Update / Size). ⋯: View As, Import This Folder to Library…, Save Page Comics as Offline Copies, Remove Local Copies on This Page.
- Every breadcrumb level is tappable, replacing Up / Root menu entries.
- Unsupported files appear only as a footnote count.

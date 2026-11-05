# ScreenOffline

Offline Shelf and Saved Folders are separate pages, each scoped to all servers or the current server.

## Offline Shelf
- When offline, a top Notice says “Every comic here opens without a connection.”
- Search + filters (All / Needs Update, with counts) + sort (Recent / Title / Server). The former current / older filters are merged; users need to know which copies need updating.
- While online, older-copy rows have a trailing Update button. Hide it offline, with “Can update when online” in the subtitle, rather than offer a button certain to fail. Other actions (remove copy, go to its folder) use long press / swipe. Import to Library requires returning to the remote directory and reusing the same import flow.
- Whole-server cleanup exists only in server management and Settings → Storage, not Offline Shelf. See [design requirements](../../../design-requirements.md#deletion-removal-and-cleanup) for cleanup consequences.

## Saved Folders
Group by server. Navigation-bar Edit enters editing mode for rename/removal (swipe is a shortcut). Removal confirmation states “Files on the server are not affected.” Tap to enter the corresponding remote directory.

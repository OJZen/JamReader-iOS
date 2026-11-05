# ScreenRemoteActions

Remote comic actions, import, and reading preparation.

- Tap the cover to read directly. Group management actions by [MoreMenu](../MoreMenu/README.md#remote-comics); do not use one ambiguous download icon for offline saving and importing.
- The import sheet shows source path, directory scope, target library, and destination explanation. Show immediate-child counts when known. Import writes to the target root, with no subfolder picker or recursive precount; see [remote limits](../../05-batches.md#remote-and-storage) for why.
- With an opening preview, the cover stays at the opening animation's destination until the first page is ready to replace it. Only after about 0.9 seconds show the compact bottom status capsule (reason and percentage), top title, and ×. Without a preview, show centered status immediately. × cancels opening and returns.
- Failure pages offer Retry; remote comics also offer Edit Server. Saving edits closes the reader and returns to the directory; see [implementation decisions](../../05-batches.md#remote-and-storage) for why.
- Failure covers prefer the opening preview, then read only from the disk thumbnail cache; do not make network requests for a failure page. Show a warning icon when no cover is available or the window is too short. Do not add an Alert with the same content when the failure page appears; retain error Alerts when an existing comic is still displayed.

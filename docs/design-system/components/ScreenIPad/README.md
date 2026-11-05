# ScreenIPad

iPad library: UIKit split view with a persistent source + collections sidebar. The content grid adapts to container width (the mockup's 6 columns are illustrative only).

- Switch the three areas with the system tab bar: top floating tabs from iPadOS 18 (illustrated), bottom tabs on iPadOS 17.6; do not draw custom tabs.
- Check the sidebar and content together as one screen for duplicate entries. When collections appear in the sidebar, omit the 2×2 collection cards from content. [ContinueReading](../ContinueReading/README.md) settings determine placement; Inside Each Library still shows it at the library root.
- Add a library only through + beside My Libraries in the sidebar; the content toolbar is Select · ⋯, matching iPhone.
- Narrow windows (Slide Over / 1/3 split view) naturally collapse to the iPhone layout.
- See [Sidebar](../Sidebar/README.md) for app-registered area shortcuts. The static mockup's ⌘F, ⌘N, Space to open, and ⌘⌫ to delete have no corresponding library shortcut implementation.
- The iPhone Duo inner display (regular width) uses the same layout; window width, not device type, determines it. See `ScreenDuoLibrary`.

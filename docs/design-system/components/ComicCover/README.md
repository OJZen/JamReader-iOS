# ComicCover

Cover item: the sole representation of a comic in a grid. The cover dominates, with a two-line title and one subtitle line for the most important current state.

Do not use unread dots: most library comics are unread by default, so a screen full of dots is noise. Use Unread in FilterChips to find unread comics.

## When to Use
- Grid mode in library contents, collections, remote directories, and Offline Shelf; grids adapt to container width and minimum cover width, typically 3 columns in ordinary compact windows.
- Tapping a cover opens the reader directly (hero transition; see motion in `00-foundations`). No detail page before reading.

## Caller Provides
- Cover image (local `LocalCoverThumbnailView` / remote `RemoteComicThumbnailView`); if missing, show a `surface-2` background and `book` icon, not a file-extension image.
- `title` (2 lines, truncated), one subtitle state, optional progress (0–1), badge state, and selection state.

## State Rules
| Priority | State | Presentation |
| --- | --- | --- |
| 1 | Selection mode | Circular check at bottom right; unselected items do not dim. Unselectable cards (such as unsupported remote actions) use 55% opacity |
| 2 | Failure / Downloading | Top-right badge (`danger` warning / progress ring) and subtitle text |
| 3 | Remote copy | Available Offline: `offline` solid download icon; Older Copy: `warning` clock |
| 4 | Reading progress | Bottom 3pt `jam` progress bar and “Read to 42%” |
| 5 | Read / Unread | Subtitle only (Read with a check, Unread as plain text); no cover dots |
| — | Favorite | `favorite` star badge, only when the badge position is free |

The top-right badge position holds at most one badge. The bottom progress bar occupies a different position and may coexist. Downloading / failure are component-state rules, not connected per comic in current remote directories; see [StatusBadge](../StatusBadge/README.md).

## Do / Don't
- Do: use plain subtitle wording (“Read to 42%”, “Available Offline”); color is secondary.
- Don't: stack badges, file format, and size on covers; put these in More → Info.
- Don't: present Available Offline as imported into a library; these are different concepts.

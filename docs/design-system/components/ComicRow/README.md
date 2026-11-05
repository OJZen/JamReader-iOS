# ComicRow

List rows provide denser information for list mode, search results, reading history, and Offline Shelf.

## Structure
- Left: 32×48 cover (`size-row-thumb` height, 2:3); folders replace it with an `accent` solid folder icon.
- Primary row: `body`, one-line truncated title. Secondary row: `footnote` + `ink-2`, status first, then one fact (page count / size / time).
- In Progress shows a 120pt-wide, 3pt `jam` progress bar.
- Trailing edge: comics have a 44×44 More button (`PersistentRowActionButtonLabel`, `ellipsis` icon); folders have a chevron. Minimum row height is `size-row`.

## Caller Provides
Title, secondary-row status and fact, progress, tap action (read or enter folder), and More menu contents (see MoreMenu).

## Do / Don't
- Do: show at most one status marker per secondary row.
- Don't: repeat the server name in that server's directory rows; the page title already identifies the source.

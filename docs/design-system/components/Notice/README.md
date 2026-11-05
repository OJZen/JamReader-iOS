# Notice

Inline notices explain errors, permissions, read-only state, search scope, and similar conditions at the top of content, without interrupting with a dialog.

## Structure
Icon (status color) + title (`subheadline` semibold) + description (`footnote`, `ink-2`) + at most 3 text actions (`accent`).

## Rules
- Failures preserve location and input; actions offer real exits (Retry, Edit Server, go to Offline Shelf).
- Distinguish inaccessible (`danger`) from unwritable (`warning`).
- No in-place reauthorization entry exists; notices only explain access failure and retained records. See [implementation limits](../../05-batches.md#library-and-import).
- Use Alert only for blocking confirmations (see ConfirmDialog).

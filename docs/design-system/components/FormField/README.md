# FormField

Form rows use system `Form` (inset grouped) for server editing, library renaming, and metadata editing.

## Rules
- Labels are 92pt wide and left-aligned, with input on the right. Placeholders give examples rather than repeat labels (“e.g. Comics”).
- Show protocol-specific fields: SMB = Address, Port, Share, Start Folder; WebDAV = Address, Port, Server Path, Start Folder.
- Errors: field labels use `danger`, explanations appear in section footnotes, and entered content is retained.
- Saving configuration does not test the connection; connection happens when accessing remote content. See [implementation limits](../../05-batches.md#remote-and-storage) for form differences.
- Before saving address or account changes, use ConfirmDialog to explain history, shortcuts, and local copies that may be cleared.
- Leaving with unsaved changes: system confirmation with Discard Changes / Keep Editing; swiping down must not silently discard them.

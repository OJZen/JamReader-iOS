# ConfirmDialog

Destructive confirmation states what is deleted and what remains. Use system Alert / confirmationDialog with specific verbs for buttons.

## Rules
- Include the target name in the title and explain deleted and preserved data in the body. Use system confirmation dialogs; do not promise a colored impact list.
- The delete confirmation button uses system destructive styling; Cancel is always present. Do not offer Undo without a recovery mechanism.
- See [fixed terminology](../../00-foundations.md#fixed-terminology) for wording and [deletion, removal, and cleanup](../../../design-requirements.md#deletion-removal-and-cleanup) for consequences.
- Batch titles state count and scope (“Delete 12 Comics?”).
- Present the dialog from the tapped button: attach `confirmationDialog` to the button, not the page root, or it will appear from the screen top.

## Required Scenarios
Deleting local comics, deleting app-managed libraries, removing linked libraries, deleting servers, changing server location/identity, clearing downloads, emptying Imported Comics, and clearing reading history.

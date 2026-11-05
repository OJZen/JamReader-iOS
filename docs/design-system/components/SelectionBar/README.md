# SelectionBar

Batch-selection bottom bar: use the system bottom toolbar, with tab-bar visibility handled by OS version.

## Rules
- Navigation title: “3 Selected”; leading Select All / Deselect All; trailing Done.
- Bottom bar: Mark as Read, Favorite, Tags & Lists, More (Edit Metadata, Import Comic Info), Delete (`danger`, with a second confirmation stating count).
- If all selected comics are read / favorited, switch the respective action to Mark as Unread / Unfavorite; mixed states use Mark as Read / Favorite.
- Disable actions when nothing is selected; after leaving selection mode, taps open comics again.
- Batch metadata editing changes only fields checked by the user.
- Implement with the system bottom toolbar (`toolbarItems` / `ToolbarItem(placement: .bottomBar)`), not a custom button strip. Only system bars automatically enter the side column on the iPhone Duo outer display. Give every button both title and symbol.
- From iOS 27.1, merge More contents into system overflow and omit a separate More button; iOS 27.0 and earlier keep More.

From iOS 18, use UIKit's system tab-bar hiding API. iOS 17.6 keeps the tab bar and shows selection actions in the native bottom toolbar. Accessibility text sizes use icons with accessibility names to avoid squeezing five text actions into one row.

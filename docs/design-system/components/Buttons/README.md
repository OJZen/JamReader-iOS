# Buttons

Buttons use system styles, without custom shapes.

| Style | SwiftUI | Purpose |
| --- | --- | --- |
| primary | `.borderedProminent` + `.tint(.appJam)` | At most one per screen: Continue Reading, Import, Save |
| secondary | `.bordered` | Secondary actions alongside others |
| plain | `.borderless` | Cancel, text links |
| danger | `role: .destructive` | Only in confirmation dialogs and at the end of menus |
| Toolbar | System ToolbarItem (iOS 26 glass) | Navigation-bar actions |

- Solid buttons use `jam` backgrounds and `on-jam` (white) text. Do not inherit AccentColor: dark-mode `accent` is bright jam pink, making white text unreadable.
- Text buttons, links, and toolbar buttons use `accent`.
- Keyboard focus: 2pt `focus-ring` outer ring, offset 2pt.
- Disabled buttons use 35% opacity and explain why they are unavailable (Notice / footnote); do not leave ineffective buttons.

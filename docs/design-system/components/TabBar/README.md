# TabBar

iPhone primary navigation: Library · Remote · Settings. Browse was renamed Remote to avoid confusion with browsing libraries.

## Rules
- Use system `UITabBarController`. From iOS 26, it automatically appears as a floating Liquid Glass tab bar (illustrated); iOS 17–18 falls back to the standard tab bar, without custom drawing.
- Icons: `books.vertical` / `server.rack` / `gearshape`; Library and Settings use fill variants when selected, Remote keeps `server.rack`, tinted with `accent`.
- Restore at launch according to Settings → General → Open at Launch.
- See [SelectionBar](../SelectionBar/README.md) for selection-mode tab visibility and version differences.

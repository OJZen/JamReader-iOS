# SettingsRow

Settings rows: system `Form` rows with a 30pt rounded icon block (color only identifies categories on Settings pages).

- Switch rows, value rows (menu selection, `chevron.up.chevron.down`), and navigation rows (chevron).
- At accessibility text sizes, pickers use `.navigationLink`, with title and current value stacked to avoid truncating menu values; `settingsPickerStyle()` handles this centrally.
- Section footnotes explain scope, for example “These settings become the default for comics you open later.”
- Storage bar: segments by category (Imported Comics `jam`, Remote Downloads `chart-downloads`, Temporary Data `chart-temp`, Remote Covers `chart-thumbs`). Do not borrow status colors, which would make Temporary Data look like a warning.
- One row per category, with trailing Clean Up / Empty Library and confirmation; never offer one-tap cleanup of everything.

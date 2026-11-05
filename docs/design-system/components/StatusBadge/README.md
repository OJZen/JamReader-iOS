# StatusBadge

Status marker: an icon-and-text capsule. Color is secondary; screen readers announce the text.

## Remote-Copy States Provided by the Component
| State | Token | Icon | Meaning |
| --- | --- | --- | --- |
| Not Downloaded | `fill` / `ink-2` | download | Only on the server; normally hidden, shown only in Info |
| Downloading | `accent-soft` / `accent-on-soft` | Progress ring | Show percentage when a progress fraction exists |
| Available Offline | `offline-soft` / `offline` | arrow.down.circle.fill | A complete local copy exists, based on known information |
| Older Copy | `warning-soft` / `warning` | clock.badge.exclamationmark | Server file is newer than the copy; offers Update Copy |
| Failure | `danger-soft` / `danger` | exclamationmark.triangle | Interrupted or failed, never presented as complete |

Remote directories currently connect only Available Offline / Older Copy; task cards and result notices report downloading and failure. See [implementation limits](../../05-batches.md#remote-and-storage). Reading cache does not show an offline badge; component state cannot replace checking offline-copy records.

## Other States
- Read: `success` + check; In Progress shows only percentage.
- Libraries: read-only (`warning` + lock), Needs Reauthorization (`danger`).
- SMB / WEBDAV protocol labels use neutral gray, without added color.

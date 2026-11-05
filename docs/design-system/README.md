# JamReader Design System

Information architecture, visual tokens, component specifications, page mockups, and implementation decisions for JamReader's current interface. Combined Continue Reading on Library Home and collection quick filters are connected. iPhone Duo window adaptation is connected; see [implementation decisions and capability limits](05-batches.md) for limits such as reader crease geometry.

## Document Ownership

| Document | Owns |
| --- | --- |
| [design-requirements.md](../design-requirements.md) | Business requirements, data boundaries, deletion consequences, and reader behavior that must be preserved (what to do and what cannot change) |
| This directory | Interface rules: information architecture, entry placement, visual tokens, components, and pages; differences between implementation and static mockups, with reasons |
| [ui-guidelines.md](../ui-guidelines.md) | Lasting general UI requirements and checklists |

`design-requirements.md` owns data boundaries, deletion consequences, and the reader behavior contract. This directory owns page structure, entry placement, and visual values. When documentation conflicts with code, verify the implementation and correct the documentation; controls in a static mockup do not establish existing capabilities.

## Contents

| File | Contents |
| --- | --- |
| [00-foundations.md](00-foundations.md) | Visual and copy foundations: colors, typography, spacing, shapes, motion, states, icons (SF Symbols mapping), fixed terminology, and accessibility |
| [01-requirements.md](01-requirements.md) | Rationale for design decisions and owning documents |
| [02-architecture.md](02-architecture.md) | Information architecture, current entry placement, and page reuse |
| [03-reader.md](03-reader.md) | Reader: protected areas, tool layout, and display-panel control visibility |
| [04-implementation.md](04-implementation.md) | Code mapping: token → Swift, component → file |
| [05-batches.md](05-batches.md) | Implementation decisions and capability limits: differences from static mockups, reasons, and environment adaptation not yet connected |
| [06-iphone-duo.md](06-iphone-duo.md) | iPhone Duo adaptation: outer / inner / half-folded layout rules, reader and protected-component environment adaptation |
| `tokens.json` | Single source of numeric values (light/dark colors, font sizes, spacing, corners, shadows, dimensions) |
| `tokens.css` | Generated from `tokens.json`, for preview pages only; do not edit manually |
| `components/<name>/README.md` | Component or page rules: when to use, required data, Do / Don't |
| `components/<name>/preview.html` | Static illustrations (`Screen*` contains page mockups; `InformationArchitecture` contains the architecture diagram) |
| `components/bundle.css` | Preview-page styles, not app code |
| `index.html` | Preview overview |
| `assets/` | Design illustrations (sample covers, comic pages, app-icon candidates) and generation prompts; for mockups only, not the app |

## View Previews

Open `index.html` in a browser (Safari / Chrome can open the local file directly). Select a card on the left and switch light/dark mode at the top right. When opening an individual `preview.html`, append `?theme=dark` to view dark mode.

- Previews are static HTML illustrations for comparing layout, hierarchy, copy, and states. Component READMEs and implementation limits take precedence. Static mockups still contain capabilities that are not connected; they are not app screenshots. Do not reproduce the web page pixel for pixel.
- Preview icons are hand-drawn web stand-ins. Use the SF Symbols in the `00-foundations.md` icon table in the app.
- Cover images are placeholder color blocks, and titles are fictional examples.
- Yellow dashed boxes marked “Preserve unchanged” identify protected components. They illustrate code values, not new designs.

## Maintenance

- Update the owning document and code together when interface behavior or entry placement changes.
- After changing `tokens.json`, run `python3 docs/design-system/build_tokens_css.py` to regenerate `tokens.css`.
- When system controls or data capabilities make implementation differ from mockups, link the component rules to [implementation decisions and capability limits](05-batches.md) rather than appending batch logs.
